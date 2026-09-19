#!/usr/bin/env bash
# usecase: ValidateFeatureFlagQuery。
# ファイル読み込み → 検証表の全項目を評価 → 違反を全件収集 → 結果出力(stdout 15 キー固定順 / stderr 違反行)。
# 仕様: tier-facade.md「出力契約」「UC ロジック」。stdout の 15 キー固定順は
#       _cross-cutting/api/cli-command-contract.yaml commands[validate-config.sh].stdout が正。
#       行の形式(`key=value` / `key: value` / 空値 `-`)は domain/cli_field.sh(ui-design.md 出力フォーマット)に従う。
# 依存: domain/feature_flag.sh, domain/cli_field.sh, repository/feature_flag_config.sh, gateway/runner_probe.sh
# 戻り値: 0(検証 OK)/ 2(ファイルなし・読めない・検証違反 1 件以上)/ 6(runner --help 問い合わせの準備失敗。
#         契約 cli-command-contract.yaml validate-config.sh runner_help_probe.preparation_failure: 即時終了し stdout は出さない)
# 任意文字列の値(実装版など)を出力するため echo は使わず printf の固定フォーマットで出す。

FEATURE_FLAG_EXIT_OK=0
FEATURE_FLAG_EXIT_VALIDATION_ERROR=2
FEATURE_FLAG_EXIT_EXECUTION_ERROR=6

# slot の runner IF 版を解決する(契約 runner_help_probe)。
# mode=off の slot / 実体検証(絶対パス・実行可能)に違反した slot は問い合わせず `-`。
# 「応答しない」(上限到達・非 0 終了・版行なし・版が 1 でない)は warn を添えて `-`(拒否しない)。
# 引数: slot mode runner
# 戻り値: 0 … 1 行目 = if_version(`-` を含む)。warn があれば 2 行目に `warn:` 行
#         6 … 準備失敗。1 行目に `error: runner probe failed slot=<s> reason=<r>`
validate_feature_flag_resolve_if_version() {
  local slot="$1" mode="$2" runner="$3" version probe_status
  if ! feature_flag_mode_is_active "$mode" || ! feature_flag_path_is_executable "$runner"; then
    printf '%s\n' "$FEATURE_FLAG_EMPTY_VALUE"
    return 0
  fi
  version="$(runner_probe_if_version "$runner")"
  probe_status=$?
  if [ "$probe_status" -eq "$RUNNER_PROBE_STATUS_PREPARATION_FAILED" ]; then
    printf '%s\n' "error: runner probe failed slot=$slot reason=$version"
    return "$FEATURE_FLAG_EXIT_EXECUTION_ERROR"
  fi
  if [ "$probe_status" -eq "$RUNNER_PROBE_STATUS_RESPONDED" ] && runner_probe_version_is_current "$version"; then
    printf '%s\n' "$version"
  else
    printf '%s\n' "$FEATURE_FLAG_EMPTY_VALUE"
    printf '%s\n' "warn: runner does not respond to --help slot=$slot runner=$runner"
  fi
  return 0
}

# off の slot の値は `-` にする(表示用)
validate_feature_flag_slot_value() {
  local mode="$1" value="$2"
  if feature_flag_mode_is_active "$mode"; then
    feature_flag_display_value "$value"
  else
    printf '%s\n' "$FEATURE_FLAG_EMPTY_VALUE"
  fi
}

# 検証 OK 時の stdout(15 キー固定順)。パス系のキーは常に `key: value`、それ以外は値に応じて `key=value` / `key: value`
# 引数: path blue_mode green_mode rapid_mode blue_job_map green_job_map blue_if green_if
validate_feature_flag_render() {
  local path="$1" blue_mode="$2" green_mode="$3" rapid_mode="$4"
  local blue_job_map="$5" green_job_map="$6" blue_if="$7" green_if="$8"
  cli_path_field_line config_path "$path"
  cli_field_line blue_mode "$blue_mode"
  cli_field_line green_mode "$green_mode"
  cli_field_line blue_impl "$(validate_feature_flag_slot_value "$blue_mode" "${BLUE_IMPL:-}")"
  cli_field_line green_impl "$(validate_feature_flag_slot_value "$green_mode" "${GREEN_IMPL:-}")"
  cli_path_field_line blue_runner "$(validate_feature_flag_slot_value "$blue_mode" "${BLUE_RUNNER:-}")"
  cli_path_field_line green_runner "$(validate_feature_flag_slot_value "$green_mode" "${GREEN_RUNNER:-}")"
  cli_field_line rapid_crosscheck_mode "$rapid_mode"
  cli_path_field_line rapid_crosscheck_runner "$(validate_feature_flag_slot_value "$rapid_mode" "${RAPID_CROSSCHECK_RUNNER:-}")"
  cli_path_field_line rapid_crosscheck_worker "$(validate_feature_flag_slot_value "$rapid_mode" "${RAPID_CROSSCHECK_WORKER:-}")"
  cli_field_line operation_mode "$(derive_operation_mode "$blue_mode" "$green_mode" "$rapid_mode")"
  cli_path_field_line blue_job_map "$(validate_feature_flag_slot_value "$blue_mode" "$blue_job_map")"
  cli_path_field_line green_job_map "$(validate_feature_flag_slot_value "$green_mode" "$green_job_map")"
  cli_field_line blue_runner_if_version "$blue_if"
  cli_field_line green_runner_if_version "$green_if"
}

# 引数: path config_dir verbose(true|false)
validate_feature_flag_query() {
  local path="$1" config_dir="$2" verbose="${3:-false}"

  if [ ! -e "$path" ]; then
    printf '%s\n' "error: config file not found path: $path" >&2
    return "$FEATURE_FLAG_EXIT_VALIDATION_ERROR"
  fi
  if [ ! -f "$path" ] || [ ! -r "$path" ]; then
    printf '%s\n' "error: config file is not readable path: $path" >&2
    return "$FEATURE_FLAG_EXIT_VALIDATION_ERROR"
  fi

  feature_flag_config_load "$path"

  if [ "$verbose" = "true" ]; then
    local key
    for key in ${FEATURE_FLAG_KEYS[@]+"${FEATURE_FLAG_KEYS[@]}"}; do
      printf '%s\n' "info: key loaded key=$key path: $path" >&2
    done
  fi

  local errors=0 report
  # 検証表(違反・警告は全件収集してから stderr に出す)
  if report="$(validate_feature_flag)"; then
    :
  else
    errors=$((errors + 1))
  fi
  if [ -n "$report" ]; then
    printf '%s\n' "$report" >&2
  fi

  local blue_mode="${BLUE_MODE:-}" green_mode="${GREEN_MODE:-}" rapid_mode="${RAPID_CROSSCHECK_MODE:-}"
  local blue_job_map="$config_dir/blue-job-map.csv" green_job_map="$config_dir/green-job-map.csv"

  # SlotRunnerAssignment: off でない slot の対応ジョブマップ
  if report="$(validate_slot_runner_assignment blue "$blue_mode" "$blue_job_map")"; then
    :
  else
    errors=$((errors + 1))
  fi
  if [ -n "$report" ]; then
    printf '%s\n' "$report" >&2
  fi
  if report="$(validate_slot_runner_assignment green "$green_mode" "$green_job_map")"; then
    :
  else
    errors=$((errors + 1))
  fi
  if [ -n "$report" ]; then
    printf '%s\n' "$report" >&2
  fi

  # runner IF 版(契約 runner_help_probe.order: blue → green の逐次。warn は拒否しない。
  # 準備失敗は残りの検証と stdout の出力を行わず終了コード 6 で即時終了する)
  local blue_if green_if
  if ! report="$(validate_feature_flag_resolve_if_version blue "$blue_mode" "${BLUE_RUNNER:-}")"; then
    printf '%s\n' "$report" >&2
    return "$FEATURE_FLAG_EXIT_EXECUTION_ERROR"
  fi
  blue_if="${report%%$'\n'*}"
  if [ "$report" != "$blue_if" ]; then
    printf '%s\n' "${report#*$'\n'}" >&2
  fi
  if ! report="$(validate_feature_flag_resolve_if_version green "$green_mode" "${GREEN_RUNNER:-}")"; then
    printf '%s\n' "$report" >&2
    return "$FEATURE_FLAG_EXIT_EXECUTION_ERROR"
  fi
  green_if="${report%%$'\n'*}"
  if [ "$report" != "$green_if" ]; then
    printf '%s\n' "${report#*$'\n'}" >&2
  fi

  if [ "$errors" -ne 0 ]; then
    return "$FEATURE_FLAG_EXIT_VALIDATION_ERROR"
  fi

  validate_feature_flag_render "$path" "$blue_mode" "$green_mode" "$rapid_mode" \
    "$blue_job_map" "$green_job_map" "$blue_if" "$green_if"
  return "$FEATURE_FLAG_EXIT_OK"
}
