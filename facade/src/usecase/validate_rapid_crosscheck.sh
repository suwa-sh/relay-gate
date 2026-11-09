#!/usr/bin/env bash
# usecase: ValidateRapidCrosscheckCommand(validate-config.sh --rapid-crosscheck の本体。読み取り専用・副作用なし)。
# 入力の複製 → バイト点検(NUL / UTF-8 / BOM / CR)→ 行の形式(KEY=VALUE)→ RAPID_COMPARE_COMMAND の検証表(domain)→ 出力。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-facade.md
#       「コマンド契約」「検証ルール(domain: launch_command_rules)」
#       _cross-cutting/api/cli-command-contract.yaml commands[validate-config.sh].stdout / stderr、config_input_rules
# facade 単独で検証し、他ティアのシェルファイルを source しない(arch CTR-007)。RDB には触れない。
# stdout の固定順: config=rapid-crosscheck / path: / command_path: / has_job_id_placeholder= / status= / violations=(invalid 時)
# 依存: domain/launch_command.sh, domain/cli_field.sh, repository/rapid_crosscheck_env.sh,
#       usecase/validate_job_map.sh(validate_job_map_report_byte_errors。バイト点検の文言と順序の規則を共有する)
# 戻り値: 0(違反 0 件)/ 2(ファイルなし・読めない・入力の守備範囲の違反・形式違反の行・検証表の違反)/
#         6(入力の複製の失敗・補助コマンドの失敗。config_input_rules.internal_failure。stdout も他の error 行も出さない)

VALIDATE_RAPID_CROSSCHECK_EXIT_OK=0
VALIDATE_RAPID_CROSSCHECK_EXIT_VALIDATION_ERROR=2
VALIDATE_RAPID_CROSSCHECK_EXIT_EXECUTION_ERROR=6
VALIDATE_RAPID_CROSSCHECK_CONFIG_NAME="rapid-crosscheck"

# 引数: path verbose(true|false)
validate_rapid_crosscheck_command() {
  local path="$1" verbose="${2:-false}" shown_path load_status=0
  cli_field_safe_text "$path"
  shown_path="$CLI_FIELD_SAFE_TEXT"

  if [ ! -e "$path" ]; then
    printf '%s\n' "error: config file not found path: $shown_path" >&2
    return "$VALIDATE_RAPID_CROSSCHECK_EXIT_VALIDATION_ERROR"
  fi
  if [ ! -f "$path" ] || [ ! -r "$path" ]; then
    printf '%s\n' "error: config file is not readable path: $shown_path" >&2
    return "$VALIDATE_RAPID_CROSSCHECK_EXIT_VALIDATION_ERROR"
  fi

  rapid_crosscheck_env_read "$path" || load_status=$?
  if [ "$load_status" -eq "$RAPID_CROSSCHECK_ENV_STATUS_SNAPSHOT_FAILED" ]; then
    printf '%s\n' "error: config snapshot failed path: $shown_path" "hint: check TMPDIR is writable" >&2
    return "$VALIDATE_RAPID_CROSSCHECK_EXIT_EXECUTION_ERROR"
  fi
  if [ "$load_status" -ne 0 ]; then
    printf '%s\n' "error: internal command failed commands=$RAPID_CROSSCHECK_ENV_FAILED_COMMANDS path: $shown_path" >&2
    return "$VALIDATE_RAPID_CROSSCHECK_EXIT_EXECUTION_ERROR"
  fi

  # 形式(UTF-8 / LF / BOM なし / NUL なし)から外れた入力は原因ごとの文言で拒否し、キーの検証に進まない
  local saved_sink="$JOB_MAP_REPORT_SINK" byte_status=0
  JOB_MAP_REPORT_SINK="$JOB_MAP_REPORT_SINK_ARRAY"
  # shellcheck disable=SC2034  # validate_job_map_report_byte_errors(job_map_emit)が溜める先
  JOB_MAP_REPORT_LINES=()
  validate_job_map_report_byte_errors "$shown_path" || byte_status=$?
  validate_job_map_flush_report
  JOB_MAP_REPORT_SINK="$saved_sink"
  if [ "$byte_status" -ne 0 ]; then
    return "$VALIDATE_RAPID_CROSSCHECK_EXIT_VALIDATION_ERROR"
  fi

  # KEY=VALUE でない行(config_input_rules.env_files)は全件報告して拒否し、キーの検証に進まない
  if [ "${#RAPID_CROSSCHECK_ENV_INVALID_LINES[@]}" -gt 0 ]; then
    local number
    for number in "${RAPID_CROSSCHECK_ENV_INVALID_LINES[@]}"; do
      printf '%s\n' "error: invalid line line=$number path: $shown_path" >&2
    done
    return "$VALIDATE_RAPID_CROSSCHECK_EXIT_VALIDATION_ERROR"
  fi

  if [ "$verbose" = "true" ]; then
    local key
    for key in ${RAPID_CROSSCHECK_ENV_KEYS[@]+"${RAPID_CROSSCHECK_ENV_KEYS[@]}"}; do
      cli_field_safe_text "$key"
      printf '%s\n' "info: key loaded key=$CLI_FIELD_SAFE_TEXT path: $shown_path" >&2
    done
  fi

  local rules_status=0
  launch_command_rules "$RAPID_CROSSCHECK_ENV_HAS_COMPARE_COMMAND" "$RAPID_CROSSCHECK_ENV_COMPARE_COMMAND" "$shown_path" || rules_status=$?
  if [ "${#LAUNCH_COMMAND_REPORT_LINES[@]}" -gt 0 ]; then
    printf '%s\n' "${LAUNCH_COMMAND_REPORT_LINES[@]}" >&2
  fi

  cli_field_line config "$VALIDATE_RAPID_CROSSCHECK_CONFIG_NAME"
  cli_path_field_line path "$path"
  cli_path_field_line command_path "$LAUNCH_COMMAND_PATH"
  cli_field_line has_job_id_placeholder "$LAUNCH_COMMAND_HAS_JOB_ID"
  if [ "$rules_status" -ne 0 ]; then
    cli_field_line status invalid
    cli_field_line violations "$LAUNCH_COMMAND_VIOLATIONS"
    return "$VALIDATE_RAPID_CROSSCHECK_EXIT_VALIDATION_ERROR"
  fi
  cli_field_line status valid
  return "$VALIDATE_RAPID_CROSSCHECK_EXIT_OK"
}
