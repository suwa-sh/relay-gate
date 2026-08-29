#!/usr/bin/env bash
# domain 層: feature flag 判定(slot・役割の確定)、run 共通 hang_detect_limit_minutes の採用規則、
# 監査イベントの正規化(audit-event-contract.yaml hash_chain.canonical_form)とハッシュチェーンの純粋ロジック。
# 外部 I/O を持たない。値は spec.md の状態遷移一覧・audit-event-contract.yaml・rdb-schema.yaml に従う。
# shellcheck shell=bash
# 層間で共有する CLI 実行コンテキスト(run_id 等のグローバル)は bin/relaygate と他層のファイルで定義・参照するため、
# 単一ファイル検査での未定義・未使用警告は対象外
# shellcheck disable=SC2034,SC2154

# Runner 実行状態と遷移イベント名(rdb-schema runner_result_events.event_name)。
# 本 UC が記録するのは起動受付(STARTING / attempt_started)と、起動イベント送出の失敗(FAILED / attempt_failed)・
# timeout(UNKNOWN / attempt_unknown。推測で FAILED にしない)の補償記録。送出成功後の遷移は後続 UC の責務
readonly RUNNER_STATUS_STARTING="STARTING"
readonly RUNNER_STATUS_FAILED="FAILED"
readonly RUNNER_STATUS_UNKNOWN="UNKNOWN"
readonly RUNNER_EVENT_ATTEMPT_STARTED="attempt_started"
readonly RUNNER_EVENT_ATTEMPT_FAILED="attempt_failed"
readonly RUNNER_EVENT_ATTEMPT_UNKNOWN="attempt_unknown"
# 初回起動の attempt_no(tier-facade.md データモデル変更表)
readonly INITIAL_ATTEMPT_NO=1

# 監査イベント契約(audit-event-contract.yaml)の固定値
readonly AUDIT_SCHEMA_VERSION="1.0"
readonly AUDIT_EVENT_SLOT_LAUNCH_ACCEPTED="slot_launch_accepted"
readonly AUDIT_EVENT_SLOT_LAUNCH_ATTEMPTED="slot_launch_attempted"
readonly AUDIT_EVENT_SLOT_LAUNCH_FAILED="slot_launch_failed"
readonly AUDIT_EVENT_SLOT_LAUNCH_TIMEOUT="slot_launch_timeout"
readonly AUDIT_OPERATION_SLOT_LAUNCH="slot_launch"
readonly AUDIT_OUTCOME_ACCEPTED="accepted"
readonly AUDIT_OUTCOME_FAILED="failed"
readonly AUDIT_OUTCOME_TIMEOUT="timeout"
readonly AUDIT_ERROR_LAUNCH_EVENT_SEND_FAILED="launch_event_send_failed"
readonly AUDIT_ERROR_LAUNCH_EVENT_SEND_TIMEOUT="launch_event_send_timeout"
# slot / attempt_id が非該当のイベントは NULL ではなく '-' を格納する(冪等キーを NULL で無効化しない)
readonly AUDIT_NOT_APPLICABLE="-"

declare -A slot_role=()
declare -A slot_attempt_id=()
selected_slots=()

# select_slot_roles は BLUE_MODE/GREEN_MODE から起動対象 slot と役割を起動順で確定する。
# 起動順は background → foreground(tier-facade.md ビジネスルール「起動イベントの送出順序」)。
# 同じ役割の中では blue → green。off の slot は選択しない(ジョブマップも読まない)。排他制約の検証は presentation 層で済んでいる前提。
select_slot_roles() {
  local role slot mode
  selected_slots=()
  for role in background foreground; do
    for slot in blue green; do
      if [[ $slot == blue ]]; then mode="$blue_mode"; else mode="$green_mode"; fi
      if [[ $mode == "$role" ]]; then
        selected_slots+=("$slot")
        slot_role[$slot]="$role"
      fi
    done
  done
}

# resolve_hang_detect_limit_minutes は run 共通の hang_detect_limit_minutes を確定する
# (cli-command-contract.yaml job_map_contract.hang_detect_limit_minutes_rule)。
# background role の slot の値を採用し、両 slot が background なら大きい方、background が無ければ起動対象の唯一の slot の値。
resolve_hang_detect_limit_minutes() {
  local slot candidate=""
  for slot in "${selected_slots[@]}"; do
    [[ ${slot_role[$slot]} == background ]] || continue
    if [[ -z $candidate || ${slot_hang_detect_limit_minutes[$slot]} -gt $candidate ]]; then
      candidate="${slot_hang_detect_limit_minutes[$slot]}"
    fi
  done
  if [[ -z $candidate ]]; then
    candidate="${slot_hang_detect_limit_minutes[${selected_slots[0]}]}"
  fi
  hang_detect_limit_minutes="$candidate"
}

# sha256_hex は標準入力の SHA-256 を 16 進小文字で返す(perl Digest::SHA はコアモジュールでエアーギャップ環境でも利用可能)。
sha256_hex() {
  perl -MDigest::SHA=sha256_hex -e 'local $/; print sha256_hex(<STDIN>)'
}

# audit_escape は canonical_form.escaping に従い、値の '\' を '\\' へ、'|' を '\|' へこの順で置換する。
audit_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//|/\\|}"
  printf '%s' "$value"
}

# audit_event_canonical は監査イベント本体を canonical_form の正規化文字列(previous_hash を除く 13 項目)にする。
# 引数: event_id event_name slot attempt_id occurred_at outcome final_status error_code(null は空文字で渡す)。
# 項目順は field_order(event_id, event_name, schema_version, run_id, parent_run_id, slot, attempt_id, occurred_at,
# actor, operation, outcome, final_status, error_code)。parent_run_id は通常起動のため null(空文字)。
audit_event_canonical() {
  local event_id="$1" event_name="$2" slot="$3" attempt_id="$4" occurred_at="$5" outcome="$6" final_status="$7" error_code="$8"
  local -a fields=("$event_id" "$event_name" "$AUDIT_SCHEMA_VERSION" "$run_id" "" "$slot" "$attempt_id" "$occurred_at" "$operator" "$AUDIT_OPERATION_SLOT_LAUNCH" "$outcome" "$final_status" "$error_code")
  local index canonical=""
  for index in "${!fields[@]}"; do
    ((index == 0)) || canonical+="|"
    canonical+="$(audit_escape "${fields[$index]}")"
  done
  printf '%s' "$canonical"
}

# audit_event_hash は正規化済みイベント本体の末尾に '|previous_hash'(run 内最初のイベントは空)を付加して SHA-256 を算出する
# (canonical_form.previous_hash_position / first_event_representation / event_hash)。
audit_event_hash() {
  local canonical="$1" previous_hash="$2"
  printf '%s|%s' "$canonical" "$previous_hash" | sha256_hex
}

# compose_audit_chain は起動前監査イベント列(slot_launch_accepted → 選択 slot ごとの slot_launch_attempted)を
# run_id 単位のハッシュチェーンとして組み立てる。新規 run_id のため previous_hash は空(NULL)から始める。
# 入力: audit_event_ids / audit_occurred_ats(イベントごとに取得した単調増加の時刻)
# 出力: audit_event_names / audit_slots / audit_attempt_ids / audit_previous_hashes / audit_event_hashes
compose_audit_chain() {
  local index previous_hash="" canonical slot
  audit_event_names=("$AUDIT_EVENT_SLOT_LAUNCH_ACCEPTED")
  audit_slots=("$AUDIT_NOT_APPLICABLE")
  audit_attempt_ids=("$AUDIT_NOT_APPLICABLE")
  for slot in "${selected_slots[@]}"; do
    audit_event_names+=("$AUDIT_EVENT_SLOT_LAUNCH_ATTEMPTED")
    audit_slots+=("$slot")
    audit_attempt_ids+=("${slot_attempt_id[$slot]}")
  done
  audit_previous_hashes=()
  audit_event_hashes=()
  for index in "${!audit_event_names[@]}"; do
    canonical="$(audit_event_canonical "${audit_event_ids[$index]}" "${audit_event_names[$index]}" "${audit_slots[$index]}" "${audit_attempt_ids[$index]}" "${audit_occurred_ats[$index]}" "$AUDIT_OUTCOME_ACCEPTED" "" "")"
    audit_previous_hashes+=("$previous_hash")
    previous_hash="$(audit_event_hash "$canonical" "$previous_hash")"
    audit_event_hashes+=("$previous_hash")
  done
}

# launch_outcome_of は起動イベント送出の結果種別(failed / timeout)から補償記録の値組を確定する。
# 出力: compensation_status / compensation_event_name / compensation_audit_event / compensation_outcome / compensation_error_code
launch_outcome_of() {
  case "$1" in
    failed)
      compensation_status="$RUNNER_STATUS_FAILED"
      compensation_event_name="$RUNNER_EVENT_ATTEMPT_FAILED"
      compensation_audit_event="$AUDIT_EVENT_SLOT_LAUNCH_FAILED"
      compensation_outcome="$AUDIT_OUTCOME_FAILED"
      compensation_error_code="$AUDIT_ERROR_LAUNCH_EVENT_SEND_FAILED"
      ;;
    timeout)
      compensation_status="$RUNNER_STATUS_UNKNOWN"
      compensation_event_name="$RUNNER_EVENT_ATTEMPT_UNKNOWN"
      compensation_audit_event="$AUDIT_EVENT_SLOT_LAUNCH_TIMEOUT"
      compensation_outcome="$AUDIT_OUTCOME_TIMEOUT"
      compensation_error_code="$AUDIT_ERROR_LAUNCH_EVENT_SEND_TIMEOUT"
      ;;
    *) return 1 ;;
  esac
}
