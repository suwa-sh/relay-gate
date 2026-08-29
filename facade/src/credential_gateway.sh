#!/usr/bin/env bash
# gateway 層: 認証情報(SSH 秘密鍵)の解決。
# 正本は _cross-cutting/api/cli-command-contract.yaml の credential_resolution(認証情報ディレクトリ方式):
#   - credential_ref が非 null → {RELAYGATE_CREDENTIAL_DIR}/{credential_ref}
#   - credential_ref が null   → RELAYGATE_SSH_KEY_PATH(未設定なら業務エラー)
#   - 解決したファイルが存在しない・読めない → 業務エラー(ファイルパスの実値と鍵の内容は出力しない)
#   - 秘密鍵は所有者のみ読み取り可能(0600)で配置する。パーミッション検査の失敗は業務エラー
# 鍵の実値は保持せずパスだけを起動イベント送出(ssh -i)へ渡す。RDB・監査・標準出力・標準エラーには参照名しか出さない。
# shellcheck shell=bash
# 層間で共有する CLI 実行コンテキスト(run_id 等のグローバル)は bin/relaygate と他層のファイルで定義・参照するため、
# 単一ファイル検査での未定義・未使用警告は対象外
# shellcheck disable=SC2034,SC2154

declare -A slot_ssh_key_path=()

# credential_error は認証情報の解決失敗を業務エラー(終了コード 1)で終了する。参照名以外の実値・パスは出さない。
credential_error() {
  business_error "SSH認証情報を解決できません: credential_ref=$1$2. Next action: place the private key for this credential_ref under RELAYGATE_CREDENTIAL_DIR with mode 0600, then rerun the job."
}

# inspect_key_file は秘密鍵ファイルの存在・通常ファイル・可読性を 1 回で検査し、パーミッションを 4 桁 8 進で返す
# (perl はコアモジュールのみ。GNU / BSD の stat 差異を避ける)。失敗は 1(存在しない・通常ファイルでない・読めない)。
inspect_key_file() {
  # shellcheck disable=SC2016
  deadline_run perl -e 'my $p = $ARGV[0]; (-f $p && -r $p) or exit 1; my @s = stat($p) or exit 1; printf "%04o", $s[2] & 07777' "$1"
}

# resolve_credential_for_slot は slot の credential_ref から SSH 秘密鍵パスを解決し、存在・可読・パーミッションを検査する。
resolve_credential_for_slot() {
  local slot="$1" credential_ref="${slot_credential_ref[$1]}" key_path mode
  if [[ -n $credential_ref ]]; then
    [[ -n ${credential_dir:-} ]] || credential_error "$credential_ref" " (RELAYGATE_CREDENTIAL_DIR is unset)"
    key_path="$credential_dir/$credential_ref"
  else
    [[ -n ${default_ssh_key_path:-} ]] || business_error "SSH認証情報を解決できません: credential_ref=null かつ RELAYGATE_SSH_KEY_PATH 未設定. Next action: set credential_ref in the job map or RELAYGATE_SSH_KEY_PATH, then rerun the job."
    credential_ref="null"
    key_path="$default_ssh_key_path"
  fi
  mode="$(inspect_key_file "$key_path")" || credential_error "$credential_ref" ""
  # 所有者以外に読み書き実行権が無いこと(0600 / 0400)。group / other のビットが立っていれば失敗
  [[ $mode =~ ^0?[0-7]00$ ]] || credential_error "$credential_ref" " (permission must be 0600)"
  slot_ssh_key_path[$slot]="$key_path"
}

# resolve_credentials は起動対象の全 slot 分の認証情報を transaction 開始前に解決する(解決不能なら RDB へ書き込まず起動しない)。
resolve_credentials() {
  local slot
  for slot in "${selected_slots[@]}"; do
    resolve_credential_for_slot "$slot"
  done
}
