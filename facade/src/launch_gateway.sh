#!/usr/bin/env bash
# gateway 層: BlueGreenLaunchClient。SSH 経由で blue/green 実装へ起動イベントを送出する。
# 起動イベントは slot_execution_specs の host / exec_user / script_path / work_dir / fixed_args と
# run 共通の additional_args だけから構成し、実装名・バージョンによる分岐を持たない(spec.md E2E「runner設定の差し替えのみで...」)。
# 引数列は固定引数 → 追加引数の順で順序・値を改変せず連結する。
# shellcheck shell=bash
# 層間で共有する CLI 実行コンテキスト(run_id 等のグローバル)は bin/relaygate と他層のファイルで定義・参照するため、
# 単一ファイル検査での未定義・未使用警告は対象外
# shellcheck disable=SC2034,SC2154

readonly MAX_SSH_TIMEOUT_SECONDS=8

# resolve_ssh_timeout は CLI 全体の deadline 内に収める SSH 待機上限を検証する。
resolve_ssh_timeout() {
  ssh_timeout_seconds="${RELAYGATE_SSH_TIMEOUT_SECONDS:-$MAX_SSH_TIMEOUT_SECONDS}"
  [[ "$ssh_timeout_seconds" =~ ^[1-9]$ && "$ssh_timeout_seconds" -le "$MAX_SSH_TIMEOUT_SECONDS" ]] || validation_error "RELAYGATE_SSH_TIMEOUT_SECONDS must be between 1 and $MAX_SSH_TIMEOUT_SECONDS"
  command -v timeout >/dev/null 2>&1 || business_error "SSH timeout utility is unavailable (boundary=ssh). Next action: install coreutils timeout, then rerun the job."
}

# build_remote_command は slot の起動コマンド文字列を組み立てる(作業ディレクトリ移動 + 実行環境変数 + スクリプト + 引数列)。
build_remote_command() {
  local slot="$1" remote_command
  printf -v remote_command 'cd %q && RELAYGATE_RUN_ID=%q RELAYGATE_ATTEMPT_ID=%q RELAYGATE_SLOT=%q RELAYGATE_ROLE=%q RELAYGATE_RAPID_CROSSCHECK_MODE=%q %q' "${slot_work_dir[$slot]}" "$run_id" "${slot_attempt_id[$slot]}" "$slot" "${slot_role[$slot]}" "$rapid_crosscheck_mode" "${slot_script_path[$slot]}"
  [[ -z "${slot_fixed_args_shell[$slot]}" ]] || remote_command+=" ${slot_fixed_args_shell[$slot]}"
  [[ -z "$additional_args_shell" ]] || remote_command+=" $additional_args_shell"
  printf '%s' "$remote_command"
}

# launch_failure は起動失敗を runner 実行状態へ補償記録し、診断情報を標準エラーへ出して失敗を返す。
launch_failure() {
  local slot="$1" reason="$2" status="$3" event_name="$4" exit_code="$5"
  slot_status["$slot"]="$status"
  if ! record_attempt_outcome "$slot" "$status" "$event_name" "$exit_code"; then
    printf '%s\n' "Failed to record the launch outcome for $slot slot (run_id=$run_id, attempt_id=${slot_attempt_id[$slot]}, boundary=rdb). Next action: reconcile runner_results for this attempt manually." >&2
  fi
  printf '%s\n' "Failed to start $slot slot (run_id=$run_id, attempt_id=${slot_attempt_id[$slot]}, boundary=ssh, reason=$reason). Next action: check SSH reachability of ${slot_exec_user[$slot]}@${slot_host[$slot]}, then rerun the job." >&2
  return 1
}

# launch_slot は SSH を介して slot を確定済みの役割で起動する。
# foreground は同期実行、background は非同期起動トリガーのみ(いずれも CLI deadline 内で打ち切る)。
# timeout は結果取得不能として UNKNOWN に記録し、推測で FAILED を確定しない(rdb-schema runner_results.status)。
launch_slot() {
  local slot="$1" remaining_milliseconds remote_command ssh_exit_code ssh_timeout_duration
  remote_command="$(build_remote_command "$slot")"
  remaining_milliseconds="$(remaining_deadline_milliseconds || true)"
  [[ -n "$remaining_milliseconds" ]] || launch_failure "$slot" timeout "$RUNNER_STATUS_UNKNOWN" "$RUNNER_EVENT_ATTEMPT_UNKNOWN" "" || return 1
  remaining_milliseconds=$((remaining_milliseconds - COMPENSATION_RESERVE_MILLISECONDS))
  ((remaining_milliseconds > 0)) || launch_failure "$slot" timeout "$RUNNER_STATUS_UNKNOWN" "$RUNNER_EVENT_ATTEMPT_UNKNOWN" "" || return 1
  if ((ssh_timeout_seconds * 1000 < remaining_milliseconds)); then remaining_milliseconds=$((ssh_timeout_seconds * 1000)); fi
  printf -v ssh_timeout_duration '%d.%03ds' "$((remaining_milliseconds / 1000))" "$((remaining_milliseconds % 1000))"
  if deadline_run_for "$ssh_timeout_duration" ssh -n -o BatchMode=yes -- "${slot_exec_user[$slot]}@${slot_host[$slot]}" "$remote_command" >/dev/null; then
    return 0
  else
    ssh_exit_code=$?
  fi
  if [[ "$ssh_exit_code" -eq 124 ]]; then
    launch_failure "$slot" timeout "$RUNNER_STATUS_UNKNOWN" "$RUNNER_EVENT_ATTEMPT_UNKNOWN" ""
  else
    launch_failure "$slot" ssh_failure "$RUNNER_STATUS_FAILED" "$RUNNER_EVENT_ATTEMPT_FAILED" "$ssh_exit_code"
  fi
}
