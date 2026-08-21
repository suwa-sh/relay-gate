#!/usr/bin/env bash
# gateway 層: run_id / attempt_id / event_id の発番。
# 既定は uuidgen。RELAYGATE_ID_GENERATOR に実行ファイルを指定すると `<generator> <kind> [<qualifier>]` で発番を委譲する
# (tier BDD「run_id発番が ... を返すよう固定されている」の seam。本番運用では未設定のまま使う)。
# shellcheck shell=bash
# 層間で共有する CLI 実行コンテキスト(run_id 等のグローバル)は bin/relaygate と他層のファイルで定義・参照するため、
# 単一ファイル検査での未定義・未使用警告は対象外
# shellcheck disable=SC2034,SC2154

# generate_id は kind(run_id / attempt_id / event_id)と qualifier(slot 等)を渡して識別子を 1 件発番する。
generate_id() {
  local kind="$1" qualifier="${2:-}" value
  if [[ -n ${RELAYGATE_ID_GENERATOR:-} ]]; then
    value="$(deadline_run "$RELAYGATE_ID_GENERATOR" "$kind" "$qualifier")" || return 1
  else
    value="$(deadline_run uuidgen)" || return 1
    value="${value,,}"
  fi
  # SQL・SSH 環境変数へそのまま渡すため、識別子は英数字と . _ : - に限定する
  [[ $value =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$ ]] || return 1
  printf '%s' "$value"
}

# clock_now_utc は現在時刻を UTC の ISO 8601(マイクロ秒精度)で返す。
# 秒精度では同一秒内のイベントの時系列(runner_result_events.occurred_at「履歴の時系列順序の基準」)が定まらないため、
# 契約型 datetime が保持できるサブ秒精度で記録する(perl Time::HiRes はコアモジュール)。
clock_now_utc() {
  # shellcheck disable=SC2016
  deadline_run perl -MTime::HiRes=time -MPOSIX=strftime -e 'my $t = time(); my $s = int($t); printf "%s.%06dZ", strftime("%Y-%m-%dT%H:%M:%S", gmtime($s)), int(($t - $s) * 1_000_000)'
}

# issue_run_identity は run_id・選択 slot ごとの attempt_id・履歴/監査イベント id・起動受付時刻を一度だけ確定する。
issue_run_identity() {
  local slot index selected_count
  run_id="$(generate_id run_id)" || business_error "Identifier generation failed (boundary=id). Next action: check uuidgen or RELAYGATE_ID_GENERATOR, then rerun the job."
  accepted_at="$(clock_now_utc)" || business_error "Clock read failed (boundary=clock). Next action: check the system clock, then rerun the job."
  runner_event_ids=()
  for slot in "${selected_slots[@]}"; do
    slot_attempt_id["$slot"]="$(generate_id attempt_id "$slot")" || business_error "Identifier generation failed (run_id=$run_id, slot=$slot, boundary=id). Next action: check uuidgen or RELAYGATE_ID_GENERATOR, then rerun the job."
    runner_event_ids+=("$(generate_id event_id "runner_result_events:$slot")") || business_error "Identifier generation failed (run_id=$run_id, slot=$slot, boundary=id). Next action: check uuidgen or RELAYGATE_ID_GENERATOR, then rerun the job."
  done
  # 監査イベント: slot_launch_accepted 1 件 + slot_launch_attempted を選択 slot 数
  audit_event_ids=()
  selected_count=${#selected_slots[@]}
  for ((index = 0; index <= selected_count; index++)); do
    audit_event_ids+=("$(generate_id event_id "audit_logs:$index")") || business_error "Identifier generation failed (run_id=$run_id, boundary=id). Next action: check uuidgen or RELAYGATE_ID_GENERATOR, then rerun the job."
  done
}
