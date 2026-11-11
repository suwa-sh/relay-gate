#!/usr/bin/env bash
# usecase: ValidateRapidCrosscheckCommand(validate-config.sh --rapid-crosscheck の本体。読み取り専用・副作用なし)。
# 入力の複製 → (i) バイト点検(NUL / UTF-8 / BOM / CR)→ (ii) 行の構造(invalid line・同じキーの重複)
# → (iii) --verbose の info 行・未知キーの warn・RAPID_COMPARE_COMMAND の検証表(domain)→ 出力(config_input_rules.env_files の検査の段)。
# (i)(ii) で止めたときも stdout は固定順で出し、値から決まる行は `-` にする。
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

# rapid-crosscheck.env のキー表(契約 config_files.rapid-crosscheck.env の keys)。
# 他の読み手が使うキーも未知キーではない(同 note)。表に無いキーは warn: unknown key を出して継続する
validate_rapid_crosscheck_is_known_key() {
  case "$1" in
    RAPID_DB_CONN_REF | RAPID_COMPARE_COMMAND | RAPID_LEASE_SEC | RAPID_POLL_INTERVAL_SEC) return 0 ;;
  esac
  return 1
}

# 入力の守備範囲((i) バイト・改行 / (ii) invalid line・同じキーの重複)で止めたときの stdout。
# 値から決まる行は `-`(config_input_rules.env_files)
# 引数: path violations
validate_rapid_crosscheck_print_stopped() {
  cli_field_line config "$VALIDATE_RAPID_CROSSCHECK_CONFIG_NAME"
  cli_path_field_line path "$1"
  cli_path_field_line command_path "-"
  cli_field_line has_job_id_placeholder "-"
  cli_field_line status invalid
  cli_field_line violations "$2"
}

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

  # (i) バイト・改行の検査(config_input_rules.byte_checks)。違反があればその error 行と hint だけを出して止める
  local saved_sink="$JOB_MAP_REPORT_SINK" byte_status=0 report_line byte_violations=0
  JOB_MAP_REPORT_SINK="$JOB_MAP_REPORT_SINK_ARRAY"
  # shellcheck disable=SC2034  # validate_job_map_report_byte_errors(job_map_emit)が溜める先
  JOB_MAP_REPORT_LINES=()
  validate_job_map_report_byte_errors "$shown_path" || byte_status=$?
  # violations は error 行の数(hint 行は数えない。config_input_rules.byte_checks.violations)
  for report_line in ${JOB_MAP_REPORT_LINES[@]+"${JOB_MAP_REPORT_LINES[@]}"}; do
    case "$report_line" in
      error:*) byte_violations=$((byte_violations + 1)) ;;
    esac
  done
  validate_job_map_flush_report
  JOB_MAP_REPORT_SINK="$saved_sink"
  if [ "$byte_status" -ne 0 ]; then
    validate_rapid_crosscheck_print_stopped "$path" "$byte_violations"
    return "$VALIDATE_RAPID_CROSSCHECK_EXIT_VALIDATION_ERROR"
  fi

  # (ii) 行の構造の検査(config_input_rules.env_files): invalid line を行番号の昇順 → duplicate key を初出行の昇順。
  # 1 件でもあればファイルの値を使わず、キーごとの検査に進まない
  local structure_lines=() number index
  for number in ${RAPID_CROSSCHECK_ENV_INVALID_LINES[@]+"${RAPID_CROSSCHECK_ENV_INVALID_LINES[@]}"}; do
    structure_lines+=("error: invalid line line=$number path: $shown_path")
  done
  for index in "${!RAPID_CROSSCHECK_ENV_DUPLICATE_KEYS[@]}"; do
    cli_field_safe_text "${RAPID_CROSSCHECK_ENV_DUPLICATE_KEYS[$index]}"
    structure_lines+=("error: duplicate key key=$CLI_FIELD_SAFE_TEXT lines=${RAPID_CROSSCHECK_ENV_DUPLICATE_LINES[$index]} path: $shown_path")
  done
  if [ "${#structure_lines[@]}" -gt 0 ]; then
    printf '%s\n' "${structure_lines[@]}" >&2
    validate_rapid_crosscheck_print_stopped "$path" "${#structure_lines[@]}"
    return "$VALIDATE_RAPID_CROSSCHECK_EXIT_VALIDATION_ERROR"
  fi

  # (iii) キーごとの検査と未知キーの warn。この段の stderr の順は info 行すべて(--verbose 時のみ)→ 未知キーの warn 行すべて
  # → 検証表の error 行(表の順)。info と warn はどちらもキーがファイルに初めて出た順(config_input_rules.env_files
  # 「validate-config.sh の --verbose の info 行」(c))。info は未知キー・値が空のキーも含み、値は出さない。
  # (i)(ii) で止めた回はこの段に来ないため info 行を出さない(同 (b))
  local key notices=()
  if [ "$verbose" = "true" ]; then
    for key in ${RAPID_CROSSCHECK_ENV_KEYS[@]+"${RAPID_CROSSCHECK_ENV_KEYS[@]}"}; do
      cli_field_safe_text "$key"
      notices+=("info: key loaded key=$CLI_FIELD_SAFE_TEXT path: $shown_path")
    done
  fi
  for key in ${RAPID_CROSSCHECK_ENV_KEYS[@]+"${RAPID_CROSSCHECK_ENV_KEYS[@]}"}; do
    if ! validate_rapid_crosscheck_is_known_key "$key"; then
      cli_field_safe_text "$key"
      notices+=("warn: unknown key key=$CLI_FIELD_SAFE_TEXT path: $shown_path")
    fi
  done
  if [ "${#notices[@]}" -gt 0 ]; then
    printf '%s\n' "${notices[@]}" >&2
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
