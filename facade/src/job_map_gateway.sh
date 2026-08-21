#!/usr/bin/env bash
# gateway 層: ジョブマップ(実行先解決定義)の解決。
# ファイル形式は未契約(issues/20260817T000000Z)のため検証境界の JSON 形式に限定する:
#   { "version": "v1.4.0",
#     "jobs": { "<job_id>": { "hang_detect_limit_minutes": 30,
#                             "slots": { "blue": { host, exec_user, script_path, work_dir, fixed_args[], impl_version, credential_ref }, "green": {...} } } } }
# run 共通項目(version / hang_detect_limit_minutes)と slot 別項目(slots.<slot>)を分けて読み、
# execution_specs / slot_execution_specs の分離(tier-facade.md データモデル変更)に対応させる。
# shellcheck shell=bash
# 層間で共有する CLI 実行コンテキスト(run_id 等のグローバル)は bin/relaygate と他層のファイルで定義・参照するため、
# 単一ファイル検査での未定義・未使用警告は対象外
# shellcheck disable=SC2034,SC2154

declare -A slot_host=()
declare -A slot_exec_user=()
declare -A slot_script_path=()
declare -A slot_work_dir=()
declare -A slot_impl_version=()
declare -A slot_fixed_args_json=()
declare -A slot_fixed_args_shell=()
declare -A slot_credential_ref_json=()

# job_map_error はジョブマップ境界の診断情報を秘密値なしで返し、業務エラーで終了する。
job_map_error() {
  business_error "JOB_IDに対応するジョブマップが見つかりません: $job_id (boundary=job_map, field=$1, category=$2). Next action: fix the job map entry for this JOB_ID and rerun the job."
}

# job_map_string_field は JSON オブジェクトの非空文字列フィールドを取り出す(不正なら空を返す)。
job_map_string_field() {
  # shellcheck disable=SC2016
  deadline_run jq -er --arg field "$2" 'if (.[$field] | type) == "string" and (.[$field] | length) > 0 then .[$field] else empty end' <<<"$1" 2>/dev/null || true
}

# resolve_job_map はジョブマップから run 共通項目と選択 slot ごとの実行設定を解決する。
resolve_job_map() {
  local job_entry slot slot_entry fixed_args_shell
  local -a fixed_args=()
  if [[ -z ${RELAYGATE_JOB_MAP_PATH:-} ]] || ! deadline_run test -r "$RELAYGATE_JOB_MAP_PATH"; then
    job_map_error path unavailable
  fi
  # shellcheck disable=SC2016
  job_entry="$(deadline_run jq -cer --arg id "$job_id" '.jobs[$id] | select(type == "object")' "$RELAYGATE_JOB_MAP_PATH" 2>/dev/null || true)"
  [[ -n $job_entry ]] || job_map_error jobs not_found
  job_map_version="$(deadline_run jq -er 'if (.version | type) == "string" and (.version | length) > 0 then .version else empty end' "$RELAYGATE_JOB_MAP_PATH" 2>/dev/null || true)"
  [[ -n $job_map_version ]] || job_map_error version invalid_type
  hang_detect_limit_minutes="$(deadline_run jq -er 'if (.hang_detect_limit_minutes | type) == "number" then .hang_detect_limit_minutes | tostring else empty end' <<<"$job_entry" 2>/dev/null || true)"
  [[ $hang_detect_limit_minutes =~ ^[1-9][0-9]*$ ]] || job_map_error hang_detect_limit_minutes invalid_value
  for slot in "${selected_slots[@]}"; do
    # shellcheck disable=SC2016
    slot_entry="$(deadline_run jq -cer --arg slot "$slot" '.slots[$slot] | select(type == "object")' <<<"$job_entry" 2>/dev/null || true)"
    [[ -n $slot_entry ]] || job_map_error "slots.$slot" not_found
    slot_host[$slot]="$(job_map_string_field "$slot_entry" host)"
    slot_exec_user[$slot]="$(job_map_string_field "$slot_entry" exec_user)"
    slot_script_path[$slot]="$(job_map_string_field "$slot_entry" script_path)"
    slot_work_dir[$slot]="$(job_map_string_field "$slot_entry" work_dir)"
    slot_impl_version[$slot]="$(job_map_string_field "$slot_entry" impl_version)"
    slot_credential_ref_json[$slot]="$(deadline_run jq -ce 'if .credential_ref == null then null elif (.credential_ref | type) == "string" and (.credential_ref | length) > 0 then .credential_ref else empty end' <<<"$slot_entry" 2>/dev/null || true)"
    slot_fixed_args_json[$slot]="$(deadline_run jq -ce 'if .fixed_args == null then null elif (.fixed_args | type) == "array" and (.fixed_args | all(.[]; type == "string")) then .fixed_args else empty end' <<<"$slot_entry" 2>/dev/null || true)"
    [[ -n ${slot_host[$slot]} && -n ${slot_exec_user[$slot]} && -n ${slot_script_path[$slot]} && -n ${slot_work_dir[$slot]} && -n ${slot_impl_version[$slot]} && -n ${slot_fixed_args_json[$slot]} && -n ${slot_credential_ref_json[$slot]} ]] || job_map_error "slots.$slot" invalid_type
    [[ ${slot_host[$slot]} =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ && ${slot_exec_user[$slot]} =~ ^[a-z_][a-z0-9_-]*\$?$ ]] || job_map_error "slots.$slot.ssh_target" invalid_value
    # 固定引数は bash の %q 形式で連結した 1 文字列に正規化する(改行・空白を含む要素も 1 引数として保存・伝播する)
    if [[ ${slot_fixed_args_json[$slot]} == null ]]; then
      slot_fixed_args_shell[$slot]=""
    else
      fixed_args_shell="$(deadline_run jq -er '[.[] | @sh] | join(" ")' <<<"${slot_fixed_args_json[$slot]}")" || job_map_error "slots.$slot.fixed_args" deadline
      # jq の @sh 出力だけを配列に復元する
      # shellcheck disable=SC2294
      eval "fixed_args=($fixed_args_shell)"
      slot_fixed_args_shell[$slot]="$(shell_join "${fixed_args[@]}")"
    fi
  done
}

# shell_join は引数列を bash の %q 形式で空白連結する(引数が無ければ空文字)。
shell_join() {
  local joined="" argument
  for argument in "$@"; do
    if [[ -z $joined ]]; then printf -v joined '%q' "$argument"; else printf -v joined '%s %q' "$joined" "$argument"; fi
  done
  printf '%s' "$joined"
}
