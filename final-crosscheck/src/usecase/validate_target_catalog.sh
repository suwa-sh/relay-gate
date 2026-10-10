#!/usr/bin/env bash
# usecase: ValidateTargetCatalog(validate_target_catalog)。
# 入力の複製(単一スナップショット)→ バイト点検(NUL / UTF-8 / BOM / CR)→ ヘッダー検証(列定義と完全一致・列名の重複)
# → 行ごとの列検証 → 重複検査 → 集計出力。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-final-crosscheck.md
#       「出力契約」「検証ルール一覧」「UC ロジック」(違反は全件収集。読み取り専用・RDB に触れない)
#       _cross-cutting/api/cli-command-contract.yaml commands[validate-config.sh].stdout(--target-catalog の固定順)/ stderr(共通形式)/
#       config_input_rules(rules / snapshot / internal_failure)
#       行の形式(`key=value` / `key: value` / 空値 `-`)は facade/src/domain/cli_field.sh(ui-design.md 出力フォーマット)に従う。
# 報告行(error / info / hint)は domain の target_catalog_emit で TARGET_CATALOG_REPORT_LINES に溜め、検証を終えてから stderr へ出す。
# 内部障害(終了コード 6)のときは溜めた行を捨て、error 行 1 つ(+ hint)だけを出す(stdout も出さない)。
# 依存: domain/target_catalog.sh, repository/target_catalog_repo.sh,
#       cli_field_safe_text / cli_field_line / cli_path_field_line(tier-facade の facade/src/domain/cli_field.sh。
#       契約 contracts[] に無い tier 間依存。扱いは
#       docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md に従う)
# 戻り値: 0(検証 OK)/ 2(ファイルなし・読めない・入力の守備範囲の違反・ヘッダー不一致・列名の重複・クォート不正・
#         列数不一致・列検証違反・対象の重複)/ 6(入力の複製の失敗、または補助コマンドの失敗。検証 OK にも違反にもしない)

TARGET_CATALOG_EXIT_OK=0
TARGET_CATALOG_EXIT_VALIDATION_ERROR=2
TARGET_CATALOG_EXIT_EXECUTION_ERROR=6

# 出力契約の stdout 1 行目(検証種別)
TARGET_CATALOG_CONFIG_NAME="target-catalog"
TARGET_CATALOG_STATUS_VALID="valid"
TARGET_CATALOG_STATUS_INVALID="invalid"
# 設定契約: 各行の列数(検証ルール 3)
TARGET_CATALOG_COLUMN_COUNT="${#TARGET_CATALOG_COLUMNS[@]}"

# 溜めた報告行を stderr へ出す(1 回の printf で出す)
validate_target_catalog_flush_report() {
  if [ "${#TARGET_CATALOG_REPORT_LINES[@]}" -gt 0 ]; then
    printf '%s\n' "${TARGET_CATALOG_REPORT_LINES[@]}" >&2
  fi
  TARGET_CATALOG_REPORT_LINES=()
}

# 違反の最後に出す hint(出力契約 stderr: `hint: fix the rows above and rerun validate-config.sh --target-catalog <path>`)
# 引数: shown_path
validate_target_catalog_emit_hint() {
  target_catalog_emit "hint: fix the rows above and rerun validate-config.sh --target-catalog $1"
}

# クォート不正の行を全件報告する(ヘッダーが使えず列検証に進めないときも、クォート不正は行番号付きで全部出す)
# 引数: shown_path
validate_target_catalog_report_quote_errors() {
  local shown_path="$1" row_index=0 row_count="${#TARGET_CATALOG_ROW_LINES[@]}"
  while [ "$row_index" -lt "$row_count" ]; do
    if [ "${TARGET_CATALOG_ROW_STATUSES[$row_index]}" = "$TARGET_CATALOG_PARSE_QUOTE_INVALID" ]; then
      target_catalog_emit "error: csv quote is invalid line=${TARGET_CATALOG_ROW_LINES[$row_index]} path: $shown_path"
    fi
    row_index=$((row_index + 1))
  done
}

# 入力の守備範囲の違反(config_input_rules.rules)を原因ごとの文言で行番号順に全件報告する。
# 1 行に複数の原因があれば BOM → NUL → 文字コード → CR の順に出す。`hint: use LF line endings` は最後の CR の error 行の次に 1 回。
# 戻り値: 0 … 違反なし / 1 … 違反あり(報告済み)
# 引数: shown_path
validate_target_catalog_report_byte_errors() {
  local shown_path="$1" line number last_cr=0 reported=0
  local nul_lines=() encoding_lines=() cr_lines=()
  for number in ${TARGET_CATALOG_NUL_LINES[@]+"${TARGET_CATALOG_NUL_LINES[@]}"}; do
    nul_lines[number]=1
  done
  for number in ${TARGET_CATALOG_ENCODING_LINES[@]+"${TARGET_CATALOG_ENCODING_LINES[@]}"}; do
    encoding_lines[number]=1
  done
  for number in ${TARGET_CATALOG_CR_LINES[@]+"${TARGET_CATALOG_CR_LINES[@]}"}; do
    cr_lines[number]=1
    last_cr="$number"
  done
  for line in ${TARGET_CATALOG_MALFORMED_LINES[@]+"${TARGET_CATALOG_MALFORMED_LINES[@]}"}; do
    if [ "$TARGET_CATALOG_BOM_LINE" -eq "$line" ]; then
      target_catalog_emit "error: byte order mark is not allowed line=$line path: $shown_path"
      reported=$((reported + 1))
    fi
    if [ -n "${nul_lines[line]+x}" ]; then
      target_catalog_emit "error: nul byte is not allowed line=$line path: $shown_path"
      reported=$((reported + 1))
    fi
    if [ -n "${encoding_lines[line]+x}" ]; then
      target_catalog_emit "error: encoding is not utf-8 line=$line path: $shown_path"
      reported=$((reported + 1))
    fi
    if [ -n "${cr_lines[line]+x}" ]; then
      target_catalog_emit "error: carriage return is not allowed line=$line path: $shown_path"
      reported=$((reported + 1))
      if [ "$line" -eq "$last_cr" ]; then
        target_catalog_emit "hint: use LF line endings"
      fi
    fi
  done
  [ "$reported" -eq 0 ]
}

# 内部障害を報告する(実行エラー。溜めた報告行は出さない。config_input_rules.internal_failure)
# 引数: commands(カンマ区切りの失敗したコマンド名) shown_path
validate_target_catalog_report_command_failure() {
  TARGET_CATALOG_REPORT_LINES=()
  printf '%s\n' "error: internal command failed commands=$1 path: $2" >&2
}

# 入力の複製の失敗を報告する(config_input_rules.internal_failure)
# 引数: shown_path
validate_target_catalog_report_snapshot_failure() {
  TARGET_CATALOG_REPORT_LINES=()
  printf '%s\n' "error: config snapshot failed path: $1" >&2
  printf '%s\n' "hint: check TMPDIR is writable" >&2
}

# 検証の入口(tier-final-crosscheck.md「変更概要」の validate_target_catalog)
# 引数: path verbose(true|false)
validate_target_catalog() {
  local path="$1" verbose="${2:-false}" shown_path
  cli_field_safe_text "$path"
  shown_path="$CLI_FIELD_SAFE_TEXT"

  # 検証ルール 1: ファイルが存在し読める(文言は契約 validate-config.sh stderr の共通形式)
  if [ ! -e "$path" ]; then
    printf '%s\n' "error: config file not found path: $shown_path" >&2
    return "$TARGET_CATALOG_EXIT_VALIDATION_ERROR"
  fi
  if [ ! -f "$path" ] || [ ! -r "$path" ]; then
    printf '%s\n' "error: config file is not readable path: $shown_path" >&2
    return "$TARGET_CATALOG_EXIT_VALIDATION_ERROR"
  fi

  target_catalog_rules_reset
  validate_target_catalog_run "$path" "$verbose" "$shown_path"
}

# 行ごとの検証(全件。ヘッダー一致済み)。
# 列数不一致の行(空白だけの行を含む)は列を対応付けられないため、列検証・重複検査・集計の対象にしない。
# 行数に比例して呼ぶ判定はすべてバイト単位なので、ループ全体を C にして呼び出し先が LC_ALL を設定し直さずに済むようにする
# 引数: verbose shown_path
validate_target_catalog_rows() {
  local verbose="$1" shown_path="$2"
  local row_index=0 row_count="${#TARGET_CATALOG_ROW_LINES[@]}" line actual
  local LC_ALL=C
  while [ "$row_index" -lt "$row_count" ]; do
    line="${TARGET_CATALOG_ROW_LINES[$row_index]}"
    actual="${TARGET_CATALOG_ROW_CELL_COUNTS[$row_index]}"
    if [ "${TARGET_CATALOG_ROW_STATUSES[$row_index]}" = "$TARGET_CATALOG_PARSE_QUOTE_INVALID" ]; then
      target_catalog_emit "error: csv quote is invalid line=$line path: $shown_path"
    elif [ "$actual" -ne "$TARGET_CATALOG_COLUMN_COUNT" ]; then
      target_catalog_emit "error: column count mismatch line=$line expected=$TARGET_CATALOG_COLUMN_COUNT actual=$actual"
    else
      target_catalog_row_bind_at TARGET_CATALOG_CELLS "${TARGET_CATALOG_ROW_OFFSETS[$row_index]}"
      if validate_target_catalog_row "$line" && [ "$verbose" = "true" ]; then
        target_catalog_row_checked_line "$line"
      fi
      target_catalog_register_key "$line"
      target_catalog_register_aggregates
    fi
    row_index=$((row_index + 1))
  done
}

# 検証の本体(validate_target_catalog から呼ぶ)
# 引数: path verbose shown_path
validate_target_catalog_run() {
  local path="$1" verbose="$2" shown_path="$3" load_status=0

  # (1) 入力の複製 → (2) バイト点検。複製の失敗と、複製完了後の補助コマンドの失敗は検証結果にせず終了コード 6
  target_catalog_repo_load "$path" || load_status=$?
  if [ "$load_status" -eq "$TARGET_CATALOG_REPO_STATUS_SNAPSHOT_FAILED" ]; then
    validate_target_catalog_report_snapshot_failure "$shown_path"
    return "$TARGET_CATALOG_EXIT_EXECUTION_ERROR"
  fi
  if [ "$load_status" -ne 0 ]; then
    validate_target_catalog_report_command_failure "$TARGET_CATALOG_REPO_FAILED_COMMANDS" "$shown_path"
    return "$TARGET_CATALOG_EXIT_EXECUTION_ERROR"
  fi

  # 形式(UTF-8 / LF / BOM なし / NUL なし)から外れた入力は原因ごとの文言で拒否する。形式違反の行は解析できないため、
  # ヘッダー・行・重複の検証には進まない(stdout の集計も出さない)
  if ! validate_target_catalog_report_byte_errors "$shown_path"; then
    validate_target_catalog_emit_hint "$shown_path"
    validate_target_catalog_flush_report
    return "$TARGET_CATALOG_EXIT_VALIDATION_ERROR"
  fi

  # (3) ヘッダー行: クォート不正なら列を対応付けられないため、クォート不正だけを全件報告して終える
  if [ "$TARGET_CATALOG_HEADER_STATUS" = "$TARGET_CATALOG_PARSE_QUOTE_INVALID" ]; then
    target_catalog_emit "error: csv quote is invalid line=$TARGET_CATALOG_HEADER_LINE path: $shown_path"
    validate_target_catalog_report_quote_errors "$shown_path"
    validate_target_catalog_emit_hint "$shown_path"
    validate_target_catalog_flush_report
    return "$TARGET_CATALOG_EXIT_VALIDATION_ERROR"
  fi
  # ヘッダー不一致(列順固定)と列名の重複は、列を対応付けられないため列検証に進まない(ヘッダー行が無いファイルも actual= 空で不一致)
  if ! validate_target_catalog_header "$path" ${TARGET_CATALOG_HEADER[@]+"${TARGET_CATALOG_HEADER[@]}"}; then
    validate_target_catalog_report_quote_errors "$shown_path"
    validate_target_catalog_emit_hint "$shown_path"
    validate_target_catalog_flush_report
    return "$TARGET_CATALOG_EXIT_VALIDATION_ERROR"
  fi

  # (4) 行ごとの検証(全件)→ (5) 重複検査 → (6) 集計
  local row_count="${#TARGET_CATALOG_ROW_LINES[@]}" status="$TARGET_CATALOG_STATUS_VALID"
  validate_target_catalog_rows "$verbose" "$shown_path"
  target_catalog_report_duplicates || true
  target_catalog_versions_summary

  # 違反があれば hint を最後に付け、stdout は status=invalid / violations=N で締める(出力契約の固定順)
  if [ "$TARGET_CATALOG_ERROR_COUNT" -ne 0 ]; then
    status="$TARGET_CATALOG_STATUS_INVALID"
    validate_target_catalog_emit_hint "$shown_path"
  fi
  validate_target_catalog_flush_report

  cli_field_line config "$TARGET_CATALOG_CONFIG_NAME"
  cli_path_field_line path "$path"
  cli_field_line rows "$row_count"
  cli_field_line catalog_versions "$TARGET_CATALOG_VERSIONS_SUMMARY"
  cli_field_line tables "$TARGET_CATALOG_TABLE_COUNT"
  cli_field_line files "$TARGET_CATALOG_FILE_COUNT"
  cli_field_line status "$status"
  if [ "$status" = "$TARGET_CATALOG_STATUS_INVALID" ]; then
    cli_field_line violations "$TARGET_CATALOG_ERROR_COUNT"
    return "$TARGET_CATALOG_EXIT_VALIDATION_ERROR"
  fi
  return "$TARGET_CATALOG_EXIT_OK"
}
