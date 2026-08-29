#!/usr/bin/env bash
# gateway 層: ジョブマップ(実行先解決定義)の読み込みと検証。
# 正本は _cross-cutting/api/cli-command-contract.yaml の job_map_contract:
#   - slot ごとの独立した JSON ファイル(RELAYGATE_JOB_MAP_PATH_BLUE / _GREEN)。起動対象(mode が off 以外)の slot 分だけ読む
#   - top_level: job_map_version(string) / slot_type(enum blue|green。環境変数の slot と一致) / jobs(object)
#   - job_entry: host / exec_user / script_path / work_dir / impl_version(string 必須)、fixed_args(string 配列、省略時 [])、
#                credential_ref(string、省略時 null)、hang_detect_limit_minutes(integer 1 以上)
#   - 未知のフィールドは無視し、その値を RDB・監査・標準出力・標準エラー・起動イベントへ出さない(必要な項目だけを jq で取り出す)
#   - 検証は transaction 開始前に起動対象の全 slot 分を行い、1 つでも失敗したら RDB へ書き込まず外部 slot を起動しない
# shellcheck shell=bash
# 層間で共有する CLI 実行コンテキスト(run_id 等のグローバル)は bin/relaygate と他層のファイルで定義・参照するため、
# 単一ファイル検査での未定義・未使用警告は対象外
# shellcheck disable=SC2034,SC2154

declare -A slot_job_map_path=()
declare -A slot_job_map_version=()
declare -A slot_host=()
declare -A slot_exec_user=()
declare -A slot_script_path=()
declare -A slot_work_dir=()
declare -A slot_impl_version=()
declare -A slot_fixed_args_json=()
declare -A slot_credential_ref=()
declare -A slot_hang_detect_limit_minutes=()

# credential_ref の書式(credential_resolution)。パス区切り・'..' を含む値を拒否しディレクトリ外参照を防ぐ
readonly CREDENTIAL_REF_PATTERN='^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'

# job_map_env_name は slot に対応するジョブマップ環境変数名を返す。
job_map_env_name() {
  printf 'RELAYGATE_JOB_MAP_PATH_%s' "${1^^}"
}

# job_map_field_error は必須フィールドの欠落・型不正・slot_type 不一致をバリデーションエラー(終了コード 2)で終了する。
job_map_field_error() {
  local slot="$1" field="$2"
  validation_error "ジョブマップの必須フィールドが欠落しています: slot_type=$slot path=${slot_job_map_path[$slot]} field=$field. Next action: fix the job map file for this slot, then rerun the job."
}

# JOB_MAP_EXTRACT_FILTER はジョブマップから本 tier が読む項目だけを 1 回の jq で取り出す(未知のフィールドは読まない)。
# 出力は NUL 区切りの固定順: job_map_version, slot_type, jobs の型, jobs[job_id] の型, host, exec_user, script_path, work_dir,
# impl_version, fixed_args(JSON 配列。省略時 []), credential_ref(省略時 "null"), hang_detect_limit_minutes。
# 欠落・型不正の項目は空文字にし、呼び出し側が job_map_contract の validation 順に判定する
# shellcheck disable=SC2016
readonly JOB_MAP_EXTRACT_FILTER='
  def s: if type == "string" and length > 0 then . else null end;
  (if (.jobs | type) == "object" then .jobs[$id] else null end) as $raw
  | ($raw | type) as $entry_type
  | ($raw | if type == "object" then . else {} end) as $e
  | [ (.job_map_version | s), (.slot_type | if type == "string" then . else null end), (.jobs | type), $entry_type,
      ($e.host | s), ($e.exec_user | s), ($e.script_path | s), ($e.work_dir | s), ($e.impl_version | s),
      ($e.fixed_args | if . == null then [] elif type == "array" and all(.[]; type == "string") then . else null end),
      ($e.credential_ref | if . == null then "null" elif type == "string" and length > 0 then . else null end),
      ($e.hang_detect_limit_minutes | if type == "number" then tostring else null end) ]
  | map(if . == null then "" else tostring end) | join("\u0000") + "\u0000"'

# resolve_job_map_for_slot は 1 slot 分のジョブマップを読み込み、job_map_contract の validation 順に検証する。
resolve_job_map_for_slot() {
  local slot="$1" env_name path reason credential_ref exit_code
  local -a fields=()
  env_name="$(job_map_env_name "$slot")"
  path="${!env_name:-}"
  [[ -n $path ]] || validation_error "ジョブマップのパスが未設定です: slot_type=$slot env=$env_name. Next action: set $env_name to the job map file for this slot, then rerun the job."
  slot_job_map_path[$slot]="$path"
  exit_code=0
  deadline_run test -r "$path" || exit_code=$?
  if [[ $deadline_fired -eq 1 ]]; then
    timeout_error "ジョブマップを読み込めません: slot_type=$slot path=$path reason=timeout (boundary=job_map). Next action: check the filesystem holding the job map, then rerun the job."
  elif [[ $exit_code -ne 0 ]]; then
    reason="unreadable"
    if ! deadline_run test -e "$path"; then reason="not_found"; fi
    validation_error "ジョブマップを読み込めません: slot_type=$slot path=$path reason=$reason. Next action: check the file exists and is readable, then rerun the job."
  fi
  # JSON として解析できない・オブジェクトでない場合は jq が失敗する(fields が空)
  mapfile -d '' fields < <(deadline_run jq -j --arg id "$job_id" "$JOB_MAP_EXTRACT_FILTER" "$path" 2>/dev/null)
  [[ ${#fields[@]} -eq 12 ]] || validation_error "ジョブマップを読み込めません: slot_type=$slot path=$path reason=invalid_json. Next action: fix the file so it contains one JSON object, then rerun the job."
  # top_level
  slot_job_map_version[$slot]="${fields[0]}"
  [[ -n ${slot_job_map_version[$slot]} ]] || job_map_field_error "$slot" job_map_version
  [[ ${fields[1]} == "$slot" ]] || job_map_field_error "$slot" slot_type
  [[ ${fields[2]} == object ]] || job_map_field_error "$slot" jobs
  # jobs[job_id] の存在(欠落は業務エラー: 終了コード 1)
  [[ ${fields[3]} == object ]] || business_error "JOB_IDに対応するジョブマップが見つかりません: $job_id (slot_type=$slot). Next action: add the job entry to the job map for this slot, then rerun the job."
  # job_entry
  slot_host[$slot]="${fields[4]}"
  [[ -n ${slot_host[$slot]} ]] || job_map_field_error "$slot" "jobs.$job_id.host"
  slot_exec_user[$slot]="${fields[5]}"
  [[ -n ${slot_exec_user[$slot]} ]] || job_map_field_error "$slot" "jobs.$job_id.exec_user"
  slot_script_path[$slot]="${fields[6]}"
  [[ -n ${slot_script_path[$slot]} ]] || job_map_field_error "$slot" "jobs.$job_id.script_path"
  slot_work_dir[$slot]="${fields[7]}"
  [[ -n ${slot_work_dir[$slot]} ]] || job_map_field_error "$slot" "jobs.$job_id.work_dir"
  slot_impl_version[$slot]="${fields[8]}"
  [[ -n ${slot_impl_version[$slot]} ]] || job_map_field_error "$slot" "jobs.$job_id.impl_version"
  # host / exec_user は契約どおり非空文字列のみを要求し、文字種は制限しない(verify F-002)。
  # ssh へは配列要素として '--' の後ろに渡し、オプションとして解釈させない(launch_gateway.sh)
  # fixed_args: 省略時は空配列 []。要素はすべて文字列(argument_serialization)
  slot_fixed_args_json[$slot]="${fields[9]}"
  [[ -n ${slot_fixed_args_json[$slot]} ]] || job_map_field_error "$slot" "jobs.$job_id.fixed_args"
  # credential_ref: 省略時は null(空文字で保持)。書式不正はバリデーションエラー(credential_resolution)
  credential_ref="${fields[10]}"
  [[ -n $credential_ref ]] || job_map_field_error "$slot" "jobs.$job_id.credential_ref"
  if [[ $credential_ref == null ]]; then
    slot_credential_ref[$slot]=""
  else
    [[ $credential_ref =~ $CREDENTIAL_REF_PATTERN ]] || validation_error "credential_ref の書式が不正です: slot_type=$slot. Next action: use only [A-Za-z0-9._-] (max 64 chars) for credential_ref in the job map, then rerun the job."
    slot_credential_ref[$slot]="$credential_ref"
  fi
  # hang_detect_limit_minutes: integer 1 以上
  slot_hang_detect_limit_minutes[$slot]="${fields[11]}"
  [[ ${slot_hang_detect_limit_minutes[$slot]} =~ ^[1-9][0-9]*$ ]] || job_map_field_error "$slot" "jobs.$job_id.hang_detect_limit_minutes"
}

# resolve_job_maps は起動対象の全 slot 分のジョブマップを検証・解決し、run 共通の hang_detect_limit_minutes を確定する。
resolve_job_maps() {
  local slot
  for slot in "${selected_slots[@]}"; do
    resolve_job_map_for_slot "$slot"
  done
  resolve_hang_detect_limit_minutes
}

# json_array_of は引数列を JSON 配列(要素は文字列)にする(argument_serialization.storage_format)。引数が無ければ [] を返す。
json_array_of() {
  if [[ $# -eq 0 ]]; then
    printf '[]'
    return 0
  fi
  printf '%s\0' "$@" | deadline_run jq -Rsc 'split("\u0000")[:-1]'
}

# json_array_to_argv は JSON 配列(要素は文字列)を要素順のまま bash 配列 restored_argv に復元する
# (argument_serialization.restore_rule: 再分割・再結合・トリム・クォート付与をしない)。
json_array_to_argv() {
  local json="$1"
  restored_argv=()
  [[ $json != "[]" ]] || return 0
  mapfile -d '' restored_argv < <(deadline_run jq -j '.[] | . + "\u0000"' <<<"$json")
}
