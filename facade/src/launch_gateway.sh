#!/usr/bin/env bash
# gateway 層: BlueGreenLaunchClient。SSH 経由で blue/green 実装へ起動イベントを送出する。
# 起動イベントは slot_execution_specs の host / exec_user / script_path / work_dir / fixed_args / credential_ref と
# run 共通の additional_args だけから構成し、実装名・バージョンによる分岐を持たない(spec.md E2E「runner設定の差し替えのみで...」)。
# 引数列は fixed_args の要素に additional_args の要素を順序・値を改変せず後置連結した argv(argument_serialization.restore_rule)。
# 秘密鍵は credential_resolution で解決したファイルパスを ssh -i で渡す(鍵の実値は扱わない)。
# 送出結果は slot ごとに独立に判定し、失敗(failed)/ timeout を呼び出し側(usecase)へ返す。補償記録は usecase が行う。
# shellcheck shell=bash
# 層間で共有する CLI 実行コンテキスト(run_id 等のグローバル)は bin/relaygate と他層のファイルで定義・参照するため、
# 単一ファイル検査での未定義・未使用警告は対象外
# shellcheck disable=SC2034,SC2154

readonly MAX_SSH_TIMEOUT_SECONDS=8
# 送出失敗 / timeout の補償記録(transaction 1 + 監査追記)を CLI deadline 内に収めるため、SSH 待機から差し引く予約時間
readonly COMPENSATION_RESERVE_MILLISECONDS=2000

# resolve_ssh_timeout は CLI 全体の deadline 内に収める SSH 待機上限を検証する(RELAYGATE_SSH_TIMEOUT_SECONDS は検証用 seam)。
resolve_ssh_timeout() {
  ssh_timeout_seconds="${RELAYGATE_SSH_TIMEOUT_SECONDS:-$MAX_SSH_TIMEOUT_SECONDS}"
  [[ $ssh_timeout_seconds =~ ^[1-9]$ && $ssh_timeout_seconds -le $MAX_SSH_TIMEOUT_SECONDS ]] || validation_error "RELAYGATE_SSH_TIMEOUT_SECONDS must be between 1 and $MAX_SSH_TIMEOUT_SECONDS"
  command -v timeout >/dev/null 2>&1 || business_error "SSH timeout utility is unavailable (boundary=ssh). Next action: install coreutils timeout, then rerun the job."
}

# build_remote_command は slot の起動コマンド文字列を組み立てる(作業ディレクトリ移動 + 実行環境変数 + スクリプト + argv)。
# リモートシェルへ渡すため各要素は %q でクォートするが、保存形式(JSON 配列)と要素の区切りは変えない。
build_remote_command() {
  local slot="$1" remote_command argument
  local -a argv=()
  json_array_to_argv "${slot_fixed_args_json[$slot]}" || return 1
  argv=("${restored_argv[@]}" "${additional_args[@]}")
  printf -v remote_command 'cd %q && RELAYGATE_RUN_ID=%q RELAYGATE_ATTEMPT_ID=%q RELAYGATE_SLOT=%q RELAYGATE_ROLE=%q RELAYGATE_RAPID_CROSSCHECK_MODE=%q %q' "${slot_work_dir[$slot]}" "$run_id" "${slot_attempt_id[$slot]}" "$slot" "${slot_role[$slot]}" "$rapid_crosscheck_mode" "${slot_script_path[$slot]}"
  for argument in "${argv[@]}"; do
    printf -v remote_command '%s %q' "$remote_command" "$argument"
  done
  printf '%s' "$remote_command"
}

# launch_slot は SSH を介して slot を確定済みの役割で起動イベントとして送出する。
# 結果は launch_result(ok / failed / timeout)と launch_reason に置き、終了はしない(呼び出し側が補償記録と終了コードを決める)。
# SSH の待機は seam の上限と「CLI deadline の残余 − 補償記録の予約時間」の小さい方で打ち切る(CTP-009)。
launch_slot() {
  local slot="$1" remaining_milliseconds remote_command ssh_exit_code ssh_timeout_duration
  launch_result=failed
  launch_reason=""
  remote_command="$(build_remote_command "$slot")" || {
    launch_reason="argv_restore"
    return 0
  }
  remaining_milliseconds="$(remaining_deadline_milliseconds || true)"
  remaining_milliseconds=$((${remaining_milliseconds:-0} - COMPENSATION_RESERVE_MILLISECONDS))
  if ((remaining_milliseconds <= 0)); then
    launch_reason="deadline_exhausted"
    return 0
  fi
  if ((ssh_timeout_seconds * 1000 < remaining_milliseconds)); then remaining_milliseconds=$((ssh_timeout_seconds * 1000)); fi
  printf -v ssh_timeout_duration '%d.%03ds' "$((remaining_milliseconds / 1000))" "$((remaining_milliseconds % 1000))"
  # 引数の位置: -i<鍵パス> -oBatchMode=yes -oIdentitiesOnly=yes -- <user@host> <remote_command>(標準入力は使わない)。
  # host / exec_user は契約上任意の文字列のため配列要素のまま '--' の後ろに置き、先頭が '-' でも ssh オプションとして解釈させない
  # (verify F-002。文字種の検証は行わない)。接続先は引数 5 番目に固定する(テストの ssh スタブが位置で判定する)
  if deadline_run_for "$ssh_timeout_duration" ssh "-i${slot_ssh_key_path[$slot]}" -oBatchMode=yes -oIdentitiesOnly=yes -- "${slot_exec_user[$slot]}@${slot_host[$slot]}" "$remote_command" >/dev/null </dev/null; then
    launch_result=ok
    return 0
  else
    ssh_exit_code=$?
  fi
  # timeout の判定は終了コードではなくローカル deadline の発火フラグで行う(verify F-003)。
  # リモートコマンドや ssh 自身が 124 を返した場合は送出失敗(FAILED)として扱う
  if [[ $deadline_fired -eq 1 ]]; then
    launch_result=timeout
    launch_reason="ssh_timeout"
  else
    launch_reason="ssh_failure, ssh_exit=$ssh_exit_code"
  fi
}
