#!/usr/bin/env bash
# gateway 層: RDB(ジョブキュー兼管理DB)への永続化。ExecutionSpecRecord + AuditEventRecord。
# テーブル名・列名は契約生成物 packages/contracts/relay-gate-db/schema-constants.sh の定数のみを経由する。
# 接続種別は RELAYGATE_RDB_DSN で切り替える:
#   postgresql://  = 正本(rdb-schema.yaml)。psql クライアント経由。audit_chain_heads の run_id 行を
#                    SELECT ... FOR UPDATE で排他ロックし、起動トランザクションを 1 リクエスト(psql -c)で送る
#                    (psql -c の文字列は単一リクエストとして送られ、途中のエラーで残りは実行されず rollback される)
#   sqlite://      = 限定検証境界(issues/20260817T230000Z・issues/20260821T220045Z §1)。
#                    行ロック構文を持たないため BEGIN IMMEDIATE の DB 書込みロックで直列化を代替する
# shellcheck shell=bash
# 層間で共有する CLI 実行コンテキスト(run_id 等のグローバル)は bin/relaygate と他層のファイルで定義・参照するため、
# 単一ファイル検査での未定義・未使用警告は対象外
# shellcheck disable=SC2034,SC2154

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
# 新規 run_id のため行は存在しない前提(= previous_hash NULL から開始)。前提が崩れた場合は後続の
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

# build_launch_transaction_sql は slot 起動トランザクション(起動前監査ゲート)の SQL を組み立てる。
# execution_specs / slot_execution_specs の INSERT、slot ごとの runner_result_events + runner_results の STARTING 記録、
# audit_chain_heads の run_id 行ロック、audit_logs の INSERT と audit_chain_heads の INSERT / UPDATE を
# 同一 transaction にまとめる(rdb-schema.yaml transaction_rules「slot起動トランザクション」「監査イベント追記の直列化」、CTR-008)。
build_launch_transaction_sql() {
  local kind="$1" sql index slot run_id_literal accepted_at_literal additional_args_value
  run_id_literal="$(sql_literal "$run_id")"
  accepted_at_literal="$(sql_literal "$accepted_at")"
  additional_args_value="$(sql_nullable "$additional_args_shell")"
  sql="$(transaction_begin_sql "$kind")" || return 1
  sql+=" INSERT INTO $TBL_EXECUTION_SPECS ($(sql_columns "${COLS_EXECUTION_SPECS[@]}")) VALUES ($run_id_literal,NULL,$(sql_literal "$job_id"),$additional_args_value,$(sql_literal "$job_map_version"),$hang_detect_limit_minutes);"
  for index in "${!selected_slots[@]}"; do
    slot="${selected_slots[$index]}"
    sql+=" INSERT INTO $TBL_SLOT_EXECUTION_SPECS ($(sql_columns "${COLS_SLOT_EXECUTION_SPECS[@]}")) VALUES ($run_id_literal,$(sql_literal "$slot"),$(sql_literal "${slot_host[$slot]}"),$(sql_literal "${slot_exec_user[$slot]}"),$(sql_literal "${slot_script_path[$slot]}"),$(sql_literal "${slot_work_dir[$slot]}"),$(sql_nullable "${slot_fixed_args_shell[$slot]}"),$(sql_literal "${slot_impl_version[$slot]}"),$(sql_credential_ref "${slot_credential_ref_json[$slot]}"));"
    sql+=" INSERT INTO $TBL_RUNNER_RESULT_EVENTS ($(sql_columns "${COLS_RUNNER_RESULT_EVENTS[@]}")) VALUES ($(sql_literal "${runner_event_ids[$index]}"),$run_id_literal,$(sql_literal "$slot"),$(sql_literal "${slot_role[$slot]}"),$(sql_literal "${slot_attempt_id[$slot]}"),$INITIAL_ATTEMPT_NO,$(sql_literal "$RUNNER_EVENT_ATTEMPT_STARTED"),$(sql_literal "$RUNNER_STATUS_STARTING"),$accepted_at_literal,NULL,NULL,NULL,NULL);"
    sql+=" INSERT INTO $TBL_RUNNER_RESULTS ($(sql_columns "${COLS_RUNNER_RESULTS[@]}")) VALUES ($run_id_literal,$(sql_literal "$slot"),$(sql_literal "${slot_role[$slot]}"),$(sql_literal "${slot_attempt_id[$slot]}"),$INITIAL_ATTEMPT_NO,$accepted_at_literal,NULL,NULL,NULL,NULL,$(sql_literal "$RUNNER_STATUS_STARTING"),$accepted_at_literal);"
  done
  sql+=" $(audit_chain_lock_sql "$kind" "$run_id_literal")"
  for index in "${!audit_event_names[@]}"; do
    sql+=" INSERT INTO $TBL_AUDIT_LOGS ($(sql_columns "${COLS_AUDIT_LOGS[@]}")) VALUES ($(sql_literal "${audit_event_ids[$index]}"),$(sql_literal "${audit_event_names[$index]}"),$(sql_literal "$AUDIT_SCHEMA_VERSION"),$run_id_literal,NULL,$(sql_literal "${audit_slots[$index]}"),$(sql_literal "${audit_attempt_ids[$index]}"),$accepted_at_literal,$(sql_literal "$operator"),$(sql_literal "$AUDIT_OPERATION_SLOT_LAUNCH"),$(sql_literal "$AUDIT_OUTCOME_ACCEPTED"),NULL,NULL,$(sql_nullable "${audit_previous_hashes[$index]}"),$(sql_literal "${audit_event_hashes[$index]}"));"
    sql+=" $(audit_chain_head_sql "$run_id_literal" "$(sql_literal "${audit_event_ids[$index]}")" "$(sql_literal "${audit_event_hashes[$index]}")" "$((index + 1))" "$accepted_at_literal")"
  done
  sql+=" COMMIT;"
  printf '%s' "$sql"
}

# sql_credential_ref は認証情報参照名(JSON 文字列 or null)を SQL リテラルへ変換する。実値は扱わない。
sql_credential_ref() {
  if [[ $1 == null ]]; then printf 'NULL'; else sql_literal "$(jq -r '.' <<<"$1")"; fi
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

# persist_launch_transaction は起動前監査ゲートを含む slot 起動トランザクションを commit する。
# commit できない場合は外部 slot を起動しない(終了コード 1。RDB タイムアウトは 124)。
persist_launch_transaction() {
  local sql exit_code=0
  sql="$(build_launch_transaction_sql "$rdb_kind")" || business_error "Pre-launch persistence failed (run_id=$run_id, boundary=rdb, reason=sql_build). Next action: check RELAYGATE_RDB_DSN, then rerun the job."
  rdb_execute "$sql" || exit_code=$?
  if [[ $exit_code -eq 124 ]]; then
    timeout_error "RDB connection timed out before the pre-launch audit was committed (run_id=$run_id, boundary=rdb, reason=timeout). Next action: check RDB availability, then rerun the job; no slot was launched."
  elif [[ $rdb_kind == postgresql && $exit_code -eq 2 ]]; then
    # psql 終了コード 2 = サーバーへ接続できない(認証失敗・到達不能)
    business_error "RDB connection failed (run_id=$run_id, boundary=rdb, reason=connection). Next action: check RELAYGATE_RDB_DSN and RDB reachability, then rerun the job; no slot was launched."
  elif [[ $exit_code -ne 0 ]]; then
    business_error "Pre-launch audit append failed and the slot launch was aborted (run_id=$run_id, boundary=rdb). Next action: check RDB connectivity and audit_logs write permission, then rerun the job; no slot was launched."
  fi
}
