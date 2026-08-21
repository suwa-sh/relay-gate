#!/usr/bin/env bash
# gateway 層: RDB(ジョブキュー兼管理DB)への永続化。ExecutionSpecRecord + AuditEventRecord。
# テーブル名・列名は契約生成物 packages/contracts/relay-gate-db/schema-constants.sh の定数のみを経由する。
# 検証境界は SQLite DSN(sqlite://<path>)に限定する(issues/20260817T230000Z)。
# 監査チェーンの直列化は DSN 種別で切り替える(issues/20260821T220045Z §1):
#   PostgreSQL = audit_chain_heads の run_id 行を SELECT ... FOR UPDATE で排他ロック
#   SQLite     = 行ロック構文を持たないため BEGIN IMMEDIATE の DB 書込みロックで代替
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

# resolve_rdb_target は RELAYGATE_RDB_DSN を接続種別と接続先へ変換する。
resolve_rdb_target() {
  case "${RELAYGATE_RDB_DSN:-}" in
    sqlite://*)
      rdb_kind="sqlite"
      rdb_target="${RELAYGATE_RDB_DSN#sqlite://}"
      ;;
    postgres://* | postgresql://*)
      # PostgreSQL クライアントはこの検証境界に配線していない(issues/20260821T220045Z §1)
      business_error "RDB connection failed (boundary=rdb, reason=postgresql_client_unavailable). Next action: use a sqlite:// DSN in this verification boundary."
      ;;
    *)
      business_error "RDB connection failed (boundary=rdb, reason=unsupported_dsn). Next action: set RELAYGATE_RDB_DSN to sqlite://<path>."
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

# build_launch_transaction_sql は slot 起動トランザクション(起動前監査ゲート)の SQL を組み立てる。
# execution_specs / slot_execution_specs の INSERT、slot ごとの runner_result_events + runner_results の STARTING 記録、
# audit_logs の INSERT と audit_chain_heads の更新を同一 transaction にまとめる(CTR-008)。
build_launch_transaction_sql() {
  local kind="$1" sql index slot run_id_literal accepted_at_literal additional_args_value last_index audit_count
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
  done
  audit_count=${#audit_event_names[@]}
  last_index=$((audit_count - 1))
  sql+=" INSERT INTO $TBL_AUDIT_CHAIN_HEADS ($(sql_columns "${COLS_AUDIT_CHAIN_HEADS[@]}")) VALUES ($run_id_literal,$(sql_literal "${audit_event_ids[$last_index]}"),$(sql_literal "${audit_event_hashes[$last_index]}"),$audit_count,$accepted_at_literal);"
  sql+=" COMMIT;"
  printf '%s' "$sql"
}

# sql_credential_ref は認証情報参照名(JSON 文字列 or null)を SQL リテラルへ変換する。実値は扱わない。
sql_credential_ref() {
  if [[ $1 == null ]]; then printf 'NULL'; else sql_literal "$(jq -r '.' <<<"$1")"; fi
}

# rdb_execute は SQL を接続先で実行する。主処理(起動トランザクション)は失敗後の補償時間を残して打ち切る。
rdb_execute() {
  case "$rdb_kind" in
    sqlite) deadline_run_with_compensation_reserve sqlite3 "$rdb_target" "$1" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# rdb_execute_compensation は補償記録の SQL を実行する。予約済みの補償時間を使うため CLI deadline までを上限にする。
rdb_execute_compensation() {
  case "$rdb_kind" in
    sqlite) deadline_run sqlite3 "$rdb_target" "$1" >/dev/null 2>&1 ;;
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
  elif [[ $exit_code -ne 0 ]]; then
    business_error "Pre-launch audit append failed and the slot launch was aborted (run_id=$run_id, boundary=rdb). Next action: check RDB connectivity and audit_logs write permission, then rerun the job; no slot was launched."
  fi
}

# record_attempt_outcome は外部 slot 起動後の失敗を runner_result_events(履歴)+ runner_results(snapshot)へ同一 transaction で記録する。
# 引数: slot status event_name exit_code(空なら NULL)
record_attempt_outcome() {
  local slot="$1" status="$2" event_name="$3" exit_code="$4" event_id occurred_at sql where_clause
  event_id="$(generate_id event_id "runner_result_events:$slot:$event_name")" || return 1
  occurred_at="$(deadline_run date -u '+%Y-%m-%dT%H:%M:%SZ')" || return 1
  where_clause="$COL_RUNNER_RESULTS__RUN_ID = $(sql_literal "$run_id") AND $COL_RUNNER_RESULTS__SLOT_TYPE = $(sql_literal "$slot") AND $COL_RUNNER_RESULTS__ROLE_TYPE = $(sql_literal "${slot_role[$slot]}") AND $COL_RUNNER_RESULTS__ATTEMPT_ID = $(sql_literal "${slot_attempt_id[$slot]}")"
  sql="$(transaction_begin_sql "$rdb_kind")" || return 1
  sql+=" INSERT INTO $TBL_RUNNER_RESULT_EVENTS ($(sql_columns "${COLS_RUNNER_RESULT_EVENTS[@]}")) VALUES ($(sql_literal "$event_id"),$(sql_literal "$run_id"),$(sql_literal "$slot"),$(sql_literal "${slot_role[$slot]}"),$(sql_literal "${slot_attempt_id[$slot]}"),$INITIAL_ATTEMPT_NO,$(sql_literal "$event_name"),$(sql_literal "$status"),$(sql_literal "$occurred_at"),NULL,NULL,NULL,$(sql_nullable_integer "$exit_code"));"
  sql+=" UPDATE $TBL_RUNNER_RESULTS SET $COL_RUNNER_RESULTS__STATUS = $(sql_literal "$status"), $COL_RUNNER_RESULTS__EXIT_CODE = $(sql_nullable_integer "$exit_code"), $COL_RUNNER_RESULTS__UPDATED_AT = $(sql_literal "$occurred_at") WHERE $where_clause;"
  sql+=" COMMIT;"
  rdb_execute_compensation "$sql"
}

# sql_nullable_integer は空文字を NULL、数値を整数リテラルにする。
sql_nullable_integer() {
  if [[ $1 =~ ^[0-9]+$ ]]; then printf '%s' "$1"; else printf 'NULL'; fi
}
