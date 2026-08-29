#!/usr/bin/env bash
# gateway 層: RDB(ジョブキュー兼管理DB)への永続化。ExecutionSpecRecord + AuditEventRecord。
# テーブル名・列名は契約生成物 packages/contracts/relay-gate-db/schema-constants.sh の定数のみを経由する。
# 接続種別は RELAYGATE_RDB_DSN で切り替える:
#   postgresql://  = 正本(rdb-schema.yaml)。psql クライアント経由。audit_chain_heads の run_id 行を
#                    SELECT ... FOR UPDATE で排他ロックし、transaction を 1 リクエスト(psql -c)で送る
#                    (psql -c の文字列は単一リクエストとして送られ、途中のエラーで残りは実行されず rollback される)
#   sqlite://      = 限定検証境界(issues/20260817T230000Z・issues/20260821T220045Z §1)。
#                    行ロック構文を持たないため BEGIN IMMEDIATE の DB 書込みロックで直列化を代替する
# transaction は rdb-schema.yaml transaction_rules の 3 種:
#   1. 起動前監査を含む slot 起動トランザクション(6 テーブル同一 transaction、CTR-008)
#   2. 起動イベント送出失敗 / timeout の補償記録(runner_result_events INSERT + runner_results UPDATE)
#   3. slot_launch_failed / slot_launch_timeout の監査追記(lock_contract に従う別 transaction。失敗は outbox 退避)
# shellcheck shell=bash
# 層間で共有する CLI 実行コンテキスト(run_id 等のグローバル)は bin/relaygate と他層のファイルで定義・参照するため、
# 単一ファイル検査での未定義・未使用警告は対象外
# shellcheck disable=SC2034,SC2154

# 監査追記の CAS(head_hash 一致条件)が競合で空振りした場合の再試行回数
readonly AUDIT_APPEND_MAX_ATTEMPTS=3

# sql_literal は文字列リテラルを SQL 用に安全に組み立てる。
sql_literal() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

# sql_nullable は空文字を NULL、それ以外を文字列リテラルにする。
sql_nullable() {
  if [[ -z $1 ]]; then printf 'NULL'; else sql_literal "$1"; fi
}

# sql_columns は契約の列配列をカンマ区切りの列リストにする。
sql_columns() {
  local IFS=,
  printf '%s' "$*"
}

# resolve_rdb_target は RELAYGATE_RDB_DSN を接続種別と接続先へ変換し、クライアントの存在を確認する。
resolve_rdb_target() {
  case "${RELAYGATE_RDB_DSN:-}" in
    sqlite://*)
      rdb_kind="sqlite"
      rdb_target="${RELAYGATE_RDB_DSN#sqlite://}"
      command -v sqlite3 >/dev/null 2>&1 || business_error "RDB connection failed (boundary=rdb, reason=sqlite_client_unavailable). Next action: install sqlite3, then rerun the job."
      ;;
    postgres://* | postgresql://*)
      rdb_kind="postgresql"
      # psql は接続 URI をそのまま受け取る(認証情報は DSN または PGPASSFILE 等の標準機構に委ねる)
      rdb_target="$RELAYGATE_RDB_DSN"
      command -v psql >/dev/null 2>&1 || business_error "RDB connection failed (boundary=rdb, reason=postgresql_client_unavailable). Next action: install the psql client on PATH, then rerun the job."
      ;;
    *)
      business_error "RDB connection failed (boundary=rdb, reason=unsupported_dsn). Next action: set RELAYGATE_RDB_DSN to postgresql://<uri> or sqlite://<path>."
      ;;
  esac
}

# transaction_begin_sql は接続種別に応じたトランザクション開始文を返す。
transaction_begin_sql() {
  case "$1" in
    sqlite) printf 'BEGIN IMMEDIATE;' ;;
    postgresql) printf 'BEGIN;' ;;
    *) return 1 ;;
  esac
}

# audit_chain_lock_sql は audit_chain_heads の run_id 行を排他ロックする文を返す(audit-event-contract.yaml lock_contract)。
# 起動前: 新規 run_id のため行は存在しない前提(= previous_hash NULL から開始)。前提が崩れた場合は後続の
# audit_chain_heads INSERT が主キー違反で失敗し、transaction 全体が rollback される(チェーン分岐を作らない)。
audit_chain_lock_sql() {
  local kind="$1" run_id_literal="$2"
  case "$kind" in
    sqlite) printf 'SELECT %s FROM %s WHERE %s = %s;' "$COL_AUDIT_CHAIN_HEADS__HEAD_HASH" "$TBL_AUDIT_CHAIN_HEADS" "$COL_AUDIT_CHAIN_HEADS__RUN_ID" "$run_id_literal" ;;
    postgresql) printf 'SELECT %s FROM %s WHERE %s = %s FOR UPDATE;' "$COL_AUDIT_CHAIN_HEADS__HEAD_HASH" "$TBL_AUDIT_CHAIN_HEADS" "$COL_AUDIT_CHAIN_HEADS__RUN_ID" "$run_id_literal" ;;
    *) return 1 ;;
  esac
}

# audit_chain_head_sql は追記した監査イベントをチェーン先頭へ反映する文を返す。
# run 内の最初のイベントは audit_chain_heads の行を新規作成(INSERT)し、以降は同じ行を更新(UPDATE)する
# (_model-summary.yaml audit_chain_heads: SELECT FOR UPDATE → INSERT → UPDATE)。
audit_chain_head_sql() {
  local run_id_literal="$1" event_id_literal="$2" event_hash_literal="$3" chain_length="$4" updated_at_literal="$5"
  if [[ $chain_length -eq 1 ]]; then
    printf 'INSERT INTO %s (%s) VALUES (%s,%s,%s,%s,%s);' "$TBL_AUDIT_CHAIN_HEADS" "$(sql_columns "${COLS_AUDIT_CHAIN_HEADS[@]}")" "$run_id_literal" "$event_id_literal" "$event_hash_literal" "$chain_length" "$updated_at_literal"
  else
    printf 'UPDATE %s SET %s = %s, %s = %s, %s = %s, %s = %s WHERE %s = %s;' "$TBL_AUDIT_CHAIN_HEADS" "$COL_AUDIT_CHAIN_HEADS__HEAD_EVENT_ID" "$event_id_literal" "$COL_AUDIT_CHAIN_HEADS__HEAD_HASH" "$event_hash_literal" "$COL_AUDIT_CHAIN_HEADS__CHAIN_LENGTH" "$chain_length" "$COL_AUDIT_CHAIN_HEADS__UPDATED_AT" "$updated_at_literal" "$COL_AUDIT_CHAIN_HEADS__RUN_ID" "$run_id_literal"
  fi
}

# audit_log_values_sql は audit_logs 1 行分の VALUES 句の中身(契約の列順)を返す。null は空文字で渡す。
# 引数: event_id event_name slot attempt_id occurred_at outcome final_status error_code previous_hash event_hash
audit_log_values_sql() {
  printf '%s,%s,%s,%s,NULL,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s' "$(sql_literal "$1")" "$(sql_literal "$2")" "$(sql_literal "$AUDIT_SCHEMA_VERSION")" "$(sql_literal "$run_id")" "$(sql_literal "$3")" "$(sql_literal "$4")" "$(sql_literal "$5")" "$(sql_literal "$operator")" "$(sql_literal "$AUDIT_OPERATION_SLOT_LAUNCH")" "$(sql_literal "$6")" "$(sql_nullable "$7")" "$(sql_nullable "$8")" "$(sql_nullable "$9")" "$(sql_literal "${10}")"
}

# build_launch_transaction_sql は slot 起動トランザクション(起動前監査ゲート)の SQL を組み立てる。
# execution_specs / slot_execution_specs の INSERT、slot ごとの runner_result_events + runner_results の STARTING 記録、
# audit_chain_heads の run_id 行ロック、audit_logs の INSERT と audit_chain_heads の INSERT / UPDATE を
# 同一 transaction にまとめる(rdb-schema.yaml transaction_rules「起動前監査を含むslot起動トランザクション」、CTR-008)。
# 時刻はイベントごとに取得した値(runner_occurred_ats / audit_occurred_ats)を、同じイベントの派生カラムへ使い回す(same_transaction_rule)。
build_launch_transaction_sql() {
  local kind="$1" sql index slot run_id_literal occurred_at_literal
  run_id_literal="$(sql_literal "$run_id")"
  sql="$(transaction_begin_sql "$kind")" || return 1
  sql+=" INSERT INTO $TBL_EXECUTION_SPECS ($(sql_columns "${COLS_EXECUTION_SPECS[@]}")) VALUES ($run_id_literal,NULL,$(sql_literal "$job_id"),$(sql_literal "$additional_args_json"),$hang_detect_limit_minutes);"
  for index in "${!selected_slots[@]}"; do
    slot="${selected_slots[$index]}"
    occurred_at_literal="$(sql_literal "${runner_occurred_ats[$index]}")"
    sql+=" INSERT INTO $TBL_SLOT_EXECUTION_SPECS ($(sql_columns "${COLS_SLOT_EXECUTION_SPECS[@]}")) VALUES ($run_id_literal,$(sql_literal "$slot"),$(sql_literal "${slot_host[$slot]}"),$(sql_literal "${slot_exec_user[$slot]}"),$(sql_literal "${slot_script_path[$slot]}"),$(sql_literal "${slot_work_dir[$slot]}"),$(sql_literal "${slot_fixed_args_json[$slot]}"),$(sql_literal "${slot_impl_version[$slot]}"),$(sql_nullable "${slot_credential_ref[$slot]}"),$(sql_literal "${slot_job_map_version[$slot]}"));"
    sql+=" INSERT INTO $TBL_RUNNER_RESULT_EVENTS ($(sql_columns "${COLS_RUNNER_RESULT_EVENTS[@]}")) VALUES ($(sql_literal "${runner_event_ids[$index]}"),$run_id_literal,$(sql_literal "$slot"),$(sql_literal "${slot_role[$slot]}"),$(sql_literal "${slot_attempt_id[$slot]}"),$INITIAL_ATTEMPT_NO,$(sql_literal "$RUNNER_EVENT_ATTEMPT_STARTED"),$(sql_literal "$RUNNER_STATUS_STARTING"),$occurred_at_literal,NULL,NULL,NULL,NULL);"
    sql+=" INSERT INTO $TBL_RUNNER_RESULTS ($(sql_columns "${COLS_RUNNER_RESULTS[@]}")) VALUES ($run_id_literal,$(sql_literal "$slot"),$(sql_literal "${slot_role[$slot]}"),$(sql_literal "${slot_attempt_id[$slot]}"),$INITIAL_ATTEMPT_NO,$occurred_at_literal,NULL,NULL,NULL,NULL,$(sql_literal "$RUNNER_STATUS_STARTING"),$occurred_at_literal);"
  done
  sql+=" $(audit_chain_lock_sql "$kind" "$run_id_literal")"
  for index in "${!audit_event_names[@]}"; do
    sql+=" INSERT INTO $TBL_AUDIT_LOGS ($(sql_columns "${COLS_AUDIT_LOGS[@]}")) VALUES ($(audit_log_values_sql "${audit_event_ids[$index]}" "${audit_event_names[$index]}" "${audit_slots[$index]}" "${audit_attempt_ids[$index]}" "${audit_occurred_ats[$index]}" "$AUDIT_OUTCOME_ACCEPTED" "" "" "${audit_previous_hashes[$index]}" "${audit_event_hashes[$index]}"));"
    sql+=" $(audit_chain_head_sql "$run_id_literal" "$(sql_literal "${audit_event_ids[$index]}")" "$(sql_literal "${audit_event_hashes[$index]}")" "$((index + 1))" "$(sql_literal "${audit_occurred_ats[$index]}")")"
  done
  sql+=" COMMIT;"
  printf '%s' "$sql"
}

# rdb_execute は SQL 文字列を接続先で 1 リクエストとして実行する。全 I/O は単一 CLI deadline で打ち切る。
# psql: -X(psqlrc 無視)-q(結果を出さない)-w(パスワード入力で停止しない)-v ON_ERROR_STOP=1(エラーを終了コードへ反映)
rdb_execute() {
  case "$rdb_kind" in
    sqlite) deadline_run sqlite3 "$rdb_target" "$1" >/dev/null 2>&1 ;;
    postgresql) deadline_run psql -X -q -w -v ON_ERROR_STOP=1 -d "$rdb_target" -c "$1" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# rdb_query は単一値を返す SELECT を実行し、結果(ヘッダー・装飾なし)を標準出力へ返す。
rdb_query() {
  case "$rdb_kind" in
    sqlite) deadline_run sqlite3 -noheader "$rdb_target" "$1" 2>/dev/null ;;
    postgresql) deadline_run psql -X -q -w -A -t -v ON_ERROR_STOP=1 -d "$rdb_target" -c "$1" 2>/dev/null ;;
    *) return 1 ;;
  esac
}

# persist_launch_transaction は起動前監査ゲートを含む slot 起動トランザクションを commit する。
# commit できない場合は外部 slot を起動しない(終了コード 1。RDB タイムアウトは 124)。
persist_launch_transaction() {
  local sql exit_code=0
  sql="$(build_launch_transaction_sql "$rdb_kind")" || business_error "Pre-launch persistence failed (run_id=$run_id, boundary=rdb, reason=sql_build). Next action: check RELAYGATE_RDB_DSN, then rerun the job."
  rdb_execute "$sql" || exit_code=$?
  if [[ $deadline_fired -eq 1 ]]; then
    timeout_error "RDB connection timed out before the pre-launch audit was committed (run_id=$run_id, boundary=rdb, reason=timeout). Next action: check RDB availability, then rerun the job; no slot was launched."
  elif [[ $rdb_kind == postgresql && $exit_code -eq 2 ]]; then
    # psql 終了コード 2 = サーバーへ接続できない(認証失敗・到達不能)
    business_error "RDB connection failed (run_id=$run_id, boundary=rdb, reason=connection). Next action: check RELAYGATE_RDB_DSN and RDB reachability, then rerun the job; no slot was launched."
  elif [[ $exit_code -ne 0 ]]; then
    business_error "Pre-launch audit append failed and the slot launch was aborted (run_id=$run_id, boundary=rdb). Next action: check RDB connectivity and audit_logs write permission, then rerun the job; no slot was launched."
  fi
}

# build_compensation_transaction_sql は起動イベント送出失敗 / timeout の補償記録(transaction 1)の SQL を組み立てる。
# 対象 slot の runner_result_events へ履歴を INSERT し、runner_results の同じ試行(STARTING のもの)の status / updated_at を
# 同一 transaction で UPDATE する。exit_code / stdout_path / stderr_path は NULL のまま(実行結果は存在しない)。
# 引数: kind slot event_id occurred_at status event_name
build_compensation_transaction_sql() {
  local kind="$1" slot="$2" event_id="$3" occurred_at="$4" status="$5" event_name="$6" sql run_id_literal
  run_id_literal="$(sql_literal "$run_id")"
  sql="$(transaction_begin_sql "$kind")" || return 1
  sql+=" INSERT INTO $TBL_RUNNER_RESULT_EVENTS ($(sql_columns "${COLS_RUNNER_RESULT_EVENTS[@]}")) VALUES ($(sql_literal "$event_id"),$run_id_literal,$(sql_literal "$slot"),$(sql_literal "${slot_role[$slot]}"),$(sql_literal "${slot_attempt_id[$slot]}"),$INITIAL_ATTEMPT_NO,$(sql_literal "$event_name"),$(sql_literal "$status"),$(sql_literal "$occurred_at"),NULL,NULL,NULL,NULL);"
  sql+=" UPDATE $TBL_RUNNER_RESULTS SET $COL_RUNNER_RESULTS__STATUS = $(sql_literal "$status"), $COL_RUNNER_RESULTS__UPDATED_AT = $(sql_literal "$occurred_at") WHERE $COL_RUNNER_RESULTS__RUN_ID = $run_id_literal AND $COL_RUNNER_RESULTS__SLOT_TYPE = $(sql_literal "$slot") AND $COL_RUNNER_RESULTS__ROLE_TYPE = $(sql_literal "${slot_role[$slot]}") AND $COL_RUNNER_RESULTS__ATTEMPT_ID = $(sql_literal "${slot_attempt_id[$slot]}") AND $COL_RUNNER_RESULTS__STATUS = $(sql_literal "$RUNNER_STATUS_STARTING");"
  sql+=" COMMIT;"
  printf '%s' "$sql"
}

# persist_compensation_transaction は補償記録(transaction 1)を commit する。失敗しても終了せず 1 を返す(呼び出し側が診断する)。
# 引数: slot event_id occurred_at status event_name
persist_compensation_transaction() {
  local sql
  sql="$(build_compensation_transaction_sql "$rdb_kind" "$@")" || return 1
  rdb_execute "$sql"
}

# build_audit_append_transaction_sql は起動後の監査イベント追記(transaction 2)の SQL を組み立てる(lock_contract)。
# audit_chain_heads の run_id 行を排他ロックし、previous_hash に用いた head_hash が現在も先頭であることを条件に
# audit_logs INSERT と audit_chain_heads UPDATE を行う(条件不一致なら両方とも 0 行で、呼び出し側が再計算して再試行する)。
# 引数: kind event_id event_name slot attempt_id occurred_at outcome error_code previous_hash event_hash
build_audit_append_transaction_sql() {
  local kind="$1" event_id="$2" event_name="$3" slot="$4" attempt_id="$5" occurred_at="$6" outcome="$7" error_code="$8" previous_hash="$9" event_hash="${10}"
  local sql run_id_literal head_condition
  run_id_literal="$(sql_literal "$run_id")"
  head_condition="$COL_AUDIT_CHAIN_HEADS__RUN_ID = $run_id_literal AND $COL_AUDIT_CHAIN_HEADS__HEAD_HASH = $(sql_literal "$previous_hash")"
  sql="$(transaction_begin_sql "$kind")" || return 1
  sql+=" $(audit_chain_lock_sql "$kind" "$run_id_literal")"
  sql+=" INSERT INTO $TBL_AUDIT_LOGS ($(sql_columns "${COLS_AUDIT_LOGS[@]}")) SELECT $(audit_log_values_sql "$event_id" "$event_name" "$slot" "$attempt_id" "$occurred_at" "$outcome" "" "$error_code" "$previous_hash" "$event_hash") WHERE EXISTS (SELECT 1 FROM $TBL_AUDIT_CHAIN_HEADS WHERE $head_condition);"
  sql+=" UPDATE $TBL_AUDIT_CHAIN_HEADS SET $COL_AUDIT_CHAIN_HEADS__HEAD_EVENT_ID = $(sql_literal "$event_id"), $COL_AUDIT_CHAIN_HEADS__HEAD_HASH = $(sql_literal "$event_hash"), $COL_AUDIT_CHAIN_HEADS__CHAIN_LENGTH = $COL_AUDIT_CHAIN_HEADS__CHAIN_LENGTH + 1, $COL_AUDIT_CHAIN_HEADS__UPDATED_AT = $(sql_literal "$occurred_at") WHERE $head_condition;"
  sql+=" COMMIT;"
  printf '%s' "$sql"
}

# append_post_launch_audit は起動後の監査イベント(slot_launch_failed / slot_launch_timeout)を lock_contract に従って追記する。
# 現在の head_hash を previous_hash として event_hash を算出し、head が動いていなければ commit、動いていれば再計算して再試行する。
# 追記できない場合は 1 を返す(呼び出し側が failure_contract.post_launch の outbox 退避を行う)。
# 引数: event_id event_name slot attempt_id occurred_at outcome error_code
append_post_launch_audit() {
  local event_id="$1" event_name="$2" slot="$3" attempt_id="$4" occurred_at="$5" outcome="$6" error_code="$7"
  local attempt previous_hash canonical event_hash sql appended
  canonical="$(audit_event_canonical "$event_id" "$event_name" "$slot" "$attempt_id" "$occurred_at" "$outcome" "" "$error_code")"
  for ((attempt = 1; attempt <= AUDIT_APPEND_MAX_ATTEMPTS; attempt++)); do
    previous_hash="$(rdb_query "SELECT $COL_AUDIT_CHAIN_HEADS__HEAD_HASH FROM $TBL_AUDIT_CHAIN_HEADS WHERE $COL_AUDIT_CHAIN_HEADS__RUN_ID = $(sql_literal "$run_id");")" || return 1
    [[ -n $previous_hash ]] || return 1
    event_hash="$(audit_event_hash "$canonical" "$previous_hash")"
    sql="$(build_audit_append_transaction_sql "$rdb_kind" "$event_id" "$event_name" "$slot" "$attempt_id" "$occurred_at" "$outcome" "$error_code" "$previous_hash" "$event_hash")" || return 1
    rdb_execute "$sql" || return 1
    appended="$(rdb_query "SELECT COUNT(*) FROM $TBL_AUDIT_LOGS WHERE $COL_AUDIT_LOGS__EVENT_ID = $(sql_literal "$event_id");")" || return 1
    [[ $appended != 1 ]] || return 0
  done
  return 1
}

# audit_outbox_dir はローカル永続 outbox のディレクトリを返す(failure_contract.post_launch)。
# 置き場所は契約に定義が無いため仮置き(issues/ に記録): RELAYGATE_AUDIT_OUTBOX_DIR、未設定なら XDG state 配下。
audit_outbox_dir() {
  printf '%s' "${RELAYGATE_AUDIT_OUTBOX_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/relaygate/audit-outbox}"
}

# write_audit_outbox は追記できなかった監査イベントを冪等キー(run_id, slot, attempt_id, event_name)ごと JSON で退避する。
# 一時ファイル → リネームで書き込み途中の読み取りを防ぐ。previous_hash / event_hash は再試行時に lock_contract で確定するため含めない。
# 引数: event_id event_name slot attempt_id occurred_at outcome error_code
write_audit_outbox() {
  local dir file
  dir="$(audit_outbox_dir)"
  mkdir -p "$dir" || return 1
  file="$dir/${run_id}_${3}_${4}_${2}.json"
  # shellcheck disable=SC2016
  jq -cn --arg event_id "$1" --arg event_name "$2" --arg schema_version "$AUDIT_SCHEMA_VERSION" --arg run_id "$run_id" --arg slot "$3" --arg attempt_id "$4" --arg occurred_at "$5" --arg actor "$operator" --arg operation "$AUDIT_OPERATION_SLOT_LAUNCH" --arg outcome "$6" --arg error_code "$7" \
    '{event_id: $event_id, event_name: $event_name, schema_version: $schema_version, run_id: $run_id, parent_run_id: null, slot: $slot, attempt_id: $attempt_id, occurred_at: $occurred_at, actor: $actor, operation: $operation, outcome: $outcome, final_status: null, error_code: $error_code}' >"$file.tmp" || return 1
  mv "$file.tmp" "$file"
}
