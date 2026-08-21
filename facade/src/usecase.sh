#!/usr/bin/env bash
# usecase 層: SelectAndStartSlotCommand。
# feature flag 判定 → ジョブマップ解決 → run 共通 / slot 別実行設定と起動試行 identity の確定 → 起動前監査ゲート(同一 transaction)
# → commit 後に外部 slot を起動(background → foreground の順)→ 起動結果を応答する。
# shellcheck shell=bash
# 層間で共有する CLI 実行コンテキスト(run_id 等のグローバル)は bin/relaygate と他層のファイルで定義・参照するため、
# 単一ファイル検査での未定義・未使用警告は対象外
# shellcheck disable=SC2034,SC2154

# select_and_start_slot は select-slot コマンドの本体を実行する。
select_and_start_slot() {
  local slot launch_failures=0
  select_slot_roles
  resolve_job_map
  resolve_rdb_target
  resolve_ssh_timeout
  # 追加引数は run 共通。固定引数と同じ %q 形式で 1 文字列に正規化して保存・伝播する
  additional_args_shell="$(shell_join "${additional_args[@]}")"
  issue_run_identity
  compose_audit_chain
  # RAPID_CROSSCHECK_MODE=off では速報管理 DB(rapid_crosscheck_requests)へ接続・書込みしない。
  # 本 UC は速報比較依頼を作成しないため、どちらのモードでも rapid_crosscheck_requests には触れない
  persist_launch_transaction
  for slot in "${selected_slots[@]}"; do
    launch_slot "$slot" || launch_failures=1
  done
  print_launch_results
  ((launch_failures == 0)) || exit 1
}
