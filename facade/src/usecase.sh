#!/usr/bin/env bash
# usecase 層: SelectAndStartSlotCommand。
# feature flag 判定 → 起動対象 slot のジョブマップ読み込み・検証 → 認証情報の解決 → run 共通 / slot 別実行設定と
# 起動試行 identity の確定 → 起動前監査ゲート(同一 transaction)→ commit 後に外部 slot へ起動イベントを送出
# (background → foreground の順)→ 送出失敗 / timeout の補償記録 → 終了コードを応答する。
# shellcheck shell=bash
# 層間で共有する CLI 実行コンテキスト(run_id 等のグローバル)は bin/relaygate と他層のファイルで定義・参照するため、
# 単一ファイル検査での未定義・未使用警告は対象外
# shellcheck disable=SC2034,SC2154

# select_and_start_slot は select-slot コマンドの本体を実行する。
select_and_start_slot() {
  local slot launch_failures=0 launch_timeouts=0
  select_slot_roles
  # ジョブマップ・認証情報の検証は transaction 開始前に起動対象の全 slot 分を行う(失敗時は RDB へ書き込まず起動しない)
  resolve_job_maps
  resolve_credentials
  resolve_rdb_target
  resolve_ssh_timeout
  # 追加引数は run 共通。要素順のまま JSON 配列として保存する(argument_serialization)
  additional_args_json="$(json_array_of "${additional_args[@]}")" || business_error "Argument serialization failed (boundary=jq). Next action: check jq on PATH, then rerun the job."
  issue_run_identity
  compose_audit_chain
  # RAPID_CROSSCHECK_MODE=off では速報管理 DB(rapid_crosscheck_requests)へ接続・書込みしない。
  # 本 UC は速報比較依頼を作成しないため、どちらのモードでも rapid_crosscheck_requests には触れない
  persist_launch_transaction
  # 起動受付の記録は commit 時点で確定しているため、送出結果にかかわらず標準出力する(標準出力契約)
  print_launch_results
  for slot in "${selected_slots[@]}"; do
    launch_slot "$slot"
    case "$launch_result" in
      ok) ;;
      failed)
        launch_failures=1
        compensate_launch "$slot" failed
        ;;
      timeout)
        launch_timeouts=1
        compensate_launch "$slot" timeout
        ;;
    esac
  done
  # 終了コード: 送出失敗ありなら 1、timeout のみなら 124(cli-command-contract.yaml exit_codes)
  ((launch_failures == 0)) || exit 1
  ((launch_timeouts == 0)) || exit 124
}

# compensate_launch は起動イベント送出の失敗(FAILED / attempt_failed)または timeout(UNKNOWN / attempt_unknown)を補償記録する。
# transaction 1(履歴 INSERT + snapshot UPDATE)を commit してから、transaction 2 で slot_launch_failed / slot_launch_timeout を追記する。
# 監査追記に失敗した場合はローカル永続 outbox へ退避し、transaction 1 の commit は取り消さない(failure_contract.post_launch)。
compensate_launch() {
  local slot="$1" kind="$2" runner_event_id audit_event_id
  launch_outcome_of "$kind"
  # CLI deadline を使い切っていても補償記録は必ず試みる(deadline_run を猶予付きへ切り替える)
  deadline_grace=1
  runner_event_id="$(generate_id event_id "runner_result_events:$slot:$compensation_event_name")" || id_error ", run_id=$run_id, slot=$slot"
  next_event_time || clock_error
  if ! persist_compensation_transaction "$slot" "$runner_event_id" "$event_time" "$compensation_status" "$compensation_event_name"; then
    printf '%s\n' "$(launch_failure_message "$slot" "$kind") が、補償記録(runner_results を $compensation_status へ更新)に失敗しました (run_id=$run_id, boundary=rdb, reason=$launch_reason). Next action: check RDB connectivity and reconcile runner_results for this attempt manually." >&2
    return 0
  fi
  printf '%s\n' "$(launch_failure_message "$slot" "$kind"): slot_type=$slot attempt_id=${slot_attempt_id[$slot]} を $compensation_status として記録しました (run_id=$run_id, boundary=ssh, reason=$launch_reason). Next action: check SSH reachability of ${slot_exec_user[$slot]}@${slot_host[$slot]} and the recorded status, then rerun the job if needed." >&2
  audit_event_id="$(generate_id event_id "audit_logs:$slot:$compensation_audit_event")" || id_error ", run_id=$run_id, slot=$slot"
  next_event_time || clock_error
  if ! append_post_launch_audit "$audit_event_id" "$compensation_audit_event" "$slot" "${slot_attempt_id[$slot]}" "$event_time" "$compensation_outcome" "$compensation_error_code"; then
    if write_audit_outbox "$audit_event_id" "$compensation_audit_event" "$slot" "${slot_attempt_id[$slot]}" "$event_time" "$compensation_outcome" "$compensation_error_code"; then
      printf '%s\n' "Audit event $compensation_audit_event could not be appended and was saved to the local outbox (run_id=$run_id, slot=$slot, outbox=$(audit_outbox_dir)). Next action: retry the outbox once the RDB is reachable." >&2
    else
      printf '%s\n' "Audit event $compensation_audit_event could not be appended nor saved to the local outbox (run_id=$run_id, slot=$slot, attempt_id=${slot_attempt_id[$slot]}, occurred_at=$event_time). Next action: append the audit event manually." >&2
    fi
  fi
}
