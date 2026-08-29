#!/usr/bin/env bash
# presentation 層: CLI 引数・環境変数の解析と検証(SelectSlotRequest)、標準出力・標準エラー・終了コードの契約。
# 終了コードは tier-facade.md「終了コード」表に従う(0 正常 / 1 業務エラー / 2 バリデーション / 124 タイムアウト)。
# shellcheck shell=bash
# 層間で共有する CLI 実行コンテキスト(run_id 等のグローバル)は bin/relaygate と他層のファイルで定義・参照するため、
# 単一ファイル検査での未定義・未使用警告は対象外
# shellcheck disable=SC2034,SC2154

# validation_error はバリデーションエラー(終了コード 2)で終了する。
validation_error() {
  printf '%s\n' "$1" >&2
  exit 2
}

# business_error は業務エラー(終了コード 1)で終了する。
business_error() {
  printf '%s\n' "$1" >&2
  exit 1
}

# timeout_error はタイムアウト(終了コード 124)で終了する。
timeout_error() {
  printf '%s\n' "$1" >&2
  exit 124
}

# parse_select_slot_request は select-slot の CLI 引数を request DTO(job_id, additional_args)に変換する。
# 追加引数は argv の要素をそのまま保持する(再分割・再結合・トリム・クォート付与をしない)。
parse_select_slot_request() {
  [[ $# -ge 2 && $1 == "--job-id" && -n $2 ]] || validation_error "JOB_ID is required. Next action: pass --job-id <JOB_ID>."
  job_id="$2"
  shift 2
  additional_args=()
  if [[ $# -gt 0 ]]; then
    [[ $1 == "--" ]] || validation_error "unexpected argument: $1. Next action: put additional arguments after '--'."
    shift
    additional_args=("$@")
  fi
}

# validate_select_slot_environment は feature flag・監査 actor・認証情報ディレクトリをまとめて検証する
# (LP-001: 全パラメータをこの時点で検証)。違反は全件を標準エラーへ出してから終了コード 2 で終了する。
# ジョブマップの環境変数は起動対象 slot に限って gateway 層が検証する(mode=off の slot は未設定でもエラーにしない)。
validate_select_slot_environment() {
  local -a violations=()
  local pair
  for pair in "BLUE_MODE:$blue_mode" "GREEN_MODE:$green_mode"; do
    case "${pair#*:}" in
      off | background | foreground) ;;
      *) violations+=("${pair%%:*} must be off, background, or foreground") ;;
    esac
  done
  # SR-001 排他的 foreground 制約
  if [[ $blue_mode == foreground && $green_mode == foreground ]]; then
    violations+=("BLUE_MODEとGREEN_MODEを同時にforegroundにすることはできません")
  fi
  case "$rapid_crosscheck_mode" in
    on | off) ;;
    *) violations+=("RAPID_CROSSCHECK_MODE must be on or off") ;;
  esac
  # 起動前監査イベントの actor。省略時に facade を既定値としない(tier-facade.md 環境変数表)
  [[ -n $operator ]] || violations+=("RELAYGATE_OPERATOR is required (audit actor is not defaulted)")
  # 認証情報ディレクトリ(credential_resolution: SSH 接続を行う全コマンドで必須)
  [[ -n $credential_dir ]] || violations+=("RELAYGATE_CREDENTIAL_DIR is required (credential_ref is resolved under this directory)")
  if [[ ${#violations[@]} -gt 0 ]]; then
    printf '%s\n' "${violations[@]}" >&2
    validation_error "Next action: fix the environment variables above and rerun the job."
  fi
}

# print_launch_results は選択 slot ごとに run_id・slot_type・role・attempt_id・status を 1 行で標準出力する。
# status は起動受付の STARTING(tier-facade.md 標準出力契約。送出失敗 / timeout 後も維持し、実行状態の正本は runner_results)。
print_launch_results() {
  local slot
  for slot in "${selected_slots[@]}"; do
    printf 'run_id=%s slot_type=%s role=%s attempt_id=%s status=%s\n' "$run_id" "$slot" "${slot_role[$slot]}" "${slot_attempt_id[$slot]}" "$RUNNER_STATUS_STARTING"
  done
}

# launch_failure_message は起動イベント送出の失敗種別に応じた標準エラーの先頭文(spec.md 異常系の文言)を返す。
launch_failure_message() {
  local slot="$1" kind="$2"
  case "$kind" in
    failed) printf '%s実装への起動イベント送出に失敗しました' "$slot" ;;
    timeout) printf '%s実装への起動イベント送出がtimeoutしました' "$slot" ;;
  esac
}
