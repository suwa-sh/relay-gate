#!/usr/bin/env bash
# domain 層: feature flag 判定(slot・役割の確定)、起動試行 identity、監査ハッシュチェーンの純粋ロジック。
# 外部 I/O を持たない。値は spec.md の状態遷移一覧・audit-event-contract.yaml に従う。
# shellcheck shell=bash
# 層間で共有する CLI 実行コンテキスト(run_id 等のグローバル)は bin/relaygate と他層のファイルで定義・参照するため、
# 単一ファイル検査での未定義・未使用警告は対象外
# shellcheck disable=SC2034,SC2154

# Runner 実行状態(6 値のうち本 UC が扱うもの)と遷移イベント名(rdb-schema runner_result_events.event_name)
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
readonly AUDIT_OPERATION_SLOT_LAUNCH="slot_launch"
readonly AUDIT_OUTCOME_ACCEPTED="accepted"
# slot / attempt_id が非該当のイベントは NULL ではなく '-' を格納する(冪等キーを NULL で無効化しない)
readonly AUDIT_NOT_APPLICABLE="-"

declare -A slot_role=()
declare -A slot_attempt_id=()
declare -A slot_status=()
selected_slots=()

# select_slot_roles は BLUE_MODE/GREEN_MODE から起動対象 slot と役割を起動順で確定する。
# 起動順は background → foreground(spec.md「background roleを先に起動しforeground待機中もbackgroundが並走する」)。
# 同じ役割の中では blue → green。off の slot は選択しない。排他制約の検証は presentation 層で済んでいる前提。
select_slot_roles() {
  local role slot mode
  selected_slots=()
  for role in background foreground; do
    for slot in blue green; do
      if [[ $slot == blue ]]; then mode="$blue_mode"; else mode="$green_mode"; fi
      if [[ $mode == "$role" ]]; then
        selected_slots+=("$slot")
        slot_role[$slot]="$role"
        slot_status[$slot]="$RUNNER_STATUS_STARTING"
      fi
    done
  done
}

# sha256_hex は標準入力の SHA-256 を 16 進で返す(perl Digest::SHA はコアモジュールでエアーギャップ環境でも利用可能)。
sha256_hex() {
  perl -MDigest::SHA=sha256_hex -e 'local $/; print sha256_hex(<STDIN>)'
}

# audit_event_canonical は監査イベント本体を正規化文字列にする。
# 正規化形式: 契約 fields の順(event_id, event_name, schema_version, run_id, parent_run_id, slot, attempt_id,
# occurred_at, actor, operation, outcome, final_status, error_code)を '|' で連結し、null は空文字にする。
# 契約は正規化形式そのものを定めていない(issues/20260821T220045Z 追記§5)。
audit_event_canonical() {
  local event_id="$1" event_name="$2" slot="$3" attempt_id="$4" occurred_at="$5"
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s' "$event_id" "$event_name" "$AUDIT_SCHEMA_VERSION" "$run_id" "" "$slot" "$attempt_id" "$occurred_at" "$operator" "$AUDIT_OPERATION_SLOT_LAUNCH" "$AUDIT_OUTCOME_ACCEPTED" "" ""
}

# audit_event_hash は正規化済みイベント本体と previous_hash(run 内最初のイベントは空)から event_hash を算出する。
audit_event_hash() {
  local canonical="$1" previous_hash="$2"
  printf '%s|%s' "$canonical" "$previous_hash" | sha256_hex
}

# compose_audit_chain は起動前監査イベント列(slot_launch_accepted → 選択 slot ごとの slot_launch_attempted)を
# run_id 単位のハッシュチェーンとして組み立てる。新規 run_id のため previous_hash は空(NULL)から始める。
# 出力: audit_event_ids / audit_event_names / audit_slots / audit_attempt_ids / audit_previous_hashes / audit_event_hashes
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
    canonical="$(audit_event_canonical "${audit_event_ids[$index]}" "${audit_event_names[$index]}" "${audit_slots[$index]}" "${audit_attempt_ids[$index]}" "$accepted_at")"
    audit_previous_hashes+=("$previous_hash")
    previous_hash="$(audit_event_hash "$canonical" "$previous_hash")"
    audit_event_hashes+=("$previous_hash")
  done
}
