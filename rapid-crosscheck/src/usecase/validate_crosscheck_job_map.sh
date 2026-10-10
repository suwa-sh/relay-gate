#!/usr/bin/env bash
# usecase: ValidateCrosscheckJobMap(`validate-config.sh --crosscheck-job-map <path>` の検証本体)。
# 入力の複製(単一スナップショット)→ バイト点検(NUL / UTF-8 / BOM / CR)→ ヘッダー検証(列名の重複 → 列順固定の一致)→ 宣言検証
# → 行ごとの列検証 → job_id 重複検査 → 対象カタログ参照の解決(カタログのバイト点検・クォート不正・列名の重複・列数不一致を
#   ジョブマップと同じ共通文言で全件報告 → 形式違反が無ければ版の有無)→ 集計出力。
# 違反は全件収集してから出力する(1 件目で止めない)。violations=N は出した error 行の件数(warn / info / hint は数えない)。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-rapid-crosscheck.md
#       「出力契約」「検証ルール一覧」「UC ロジック」/ spec.md「計算ルール一覧」(行数集計・対象カタログ参照の解決)
#       _cross-cutting/api/cli-command-contract.yaml commands[validate-config.sh].stdout / stderr、config_input_rules
# stdout(順序固定): config=crosscheck-job-map / path: / rows= / target_catalog_path: / catalog_version= / exit_code_contract= / status=
#   (違反ありは status=invalid の次に violations=N)。行の形式(`key=value` / `key: value` / 空値 `-`)は facade/src/domain/cli_field.sh。
# stderr: 違反ごとに 1 行、最後に hint。報告行は job_map_emit で JOB_MAP_REPORT_LINES に溜め、検証を終えてから stderr へ出す。
#   内部障害(終了コード 6)のときは溜めた行を捨て error 行 1 つ(+ hint)だけを出す(stdout も出さない)。
# 依存: domain/comparison_definition_rules.sh, repository/crosscheck_job_map_repo.sh と、
#       tier-facade の facade/src/domain/cli_field.sh(cli_field_*)/ facade/src/domain/job_map.sh(job_map_emit、validate_job_map_unique_job_ids)/
#       facade/src/repository/job_map_repo.sh(JOB_MAP_* の読み込み結果)。後者 3 つは契約未宣言の tier 間依存
#       (根拠: docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md)
# 戻り値: 0(検証 OK)/ 2(ファイルなし・読めない・入力の守備範囲の違反・ヘッダー不一致・宣言不正・行の違反・重複・参照未解決)/
#         6(入力の複製の失敗、補助コマンドの失敗。検証 OK にも違反にもしない)

CROSSCHECK_JOB_MAP_EXIT_OK=0
CROSSCHECK_JOB_MAP_EXIT_VALIDATION_ERROR=2
CROSSCHECK_JOB_MAP_EXIT_EXECUTION_ERROR=6
CROSSCHECK_JOB_MAP_CONFIG_NAME="crosscheck-job-map"
CROSSCHECK_JOB_MAP_OPTION="--crosscheck-job-map"

# 溜めた報告行のうち、添字 from 以降にある error 行の件数(warn / info / hint は数えない。違反件数 violations=N の単位)。
# 結果は VALIDATE_CROSSCHECK_JOB_MAP_COUNTED_ERRORS
# 引数: from
VALIDATE_CROSSCHECK_JOB_MAP_COUNTED_ERRORS=0
validate_crosscheck_job_map_count_errors_since() {
  local index="$1" count="${#JOB_MAP_REPORT_LINES[@]}"
  VALIDATE_CROSSCHECK_JOB_MAP_COUNTED_ERRORS=0
  while [ "$index" -lt "$count" ]; do
    case "${JOB_MAP_REPORT_LINES[$index]}" in
      "error: "*) VALIDATE_CROSSCHECK_JOB_MAP_COUNTED_ERRORS=$((VALIDATE_CROSSCHECK_JOB_MAP_COUNTED_ERRORS + 1)) ;;
    esac
    index=$((index + 1))
  done
}

# 溜めた報告行を stderr へ出す
validate_crosscheck_job_map_flush_report() {
  if [ "${#JOB_MAP_REPORT_LINES[@]}" -gt 0 ]; then
    printf '%s\n' "${JOB_MAP_REPORT_LINES[@]}" >&2
  fi
  JOB_MAP_REPORT_LINES=()
}

# 違反の報告を終える: 溜めた報告行と hint を stderr へ出す(出力契約の stderr。hint は最後に 1 回)
# 引数: shown_path
validate_crosscheck_job_map_report_violations() {
  validate_crosscheck_job_map_flush_report
  printf '%s\n' "hint: fix the rows above and rerun validate-config.sh $CROSSCHECK_JOB_MAP_OPTION $1" >&2
}

# 内部障害(補助コマンドの失敗)。溜めた行は出さない(config_input_rules.internal_failure)
# 引数: commands shown_path
validate_crosscheck_job_map_report_command_failure() {
  JOB_MAP_REPORT_LINES=()
  printf '%s\n' "error: internal command failed commands=$1 path: $2" >&2
}

# 内部障害(入力の複製の失敗)
# 引数: shown_path
validate_crosscheck_job_map_report_snapshot_failure() {
  JOB_MAP_REPORT_LINES=()
  printf '%s\n' "error: config snapshot failed path: $1" >&2
  printf '%s\n' "hint: check TMPDIR is writable" >&2
}

# 入力の守備範囲の違反(config_input_rules.rules)を原因ごとの文言で行番号順に全件報告する。
# 1 行に複数の原因があれば BOM → NUL → 文字コード → CR の順。`hint: use LF line endings` は最後の CR の error 行の次に 1 回。
# 戻り値: 0 … 違反なし / 1 … 違反あり(報告済み)
# 引数: shown_path
validate_crosscheck_job_map_report_byte_errors() {
  local shown_path="$1" line number last_cr=0 reported=0
  local nul_lines=() encoding_lines=() cr_lines=()
  for number in ${JOB_MAP_NUL_LINES[@]+"${JOB_MAP_NUL_LINES[@]}"}; do
    nul_lines[number]=1
  done
  for number in ${JOB_MAP_ENCODING_LINES[@]+"${JOB_MAP_ENCODING_LINES[@]}"}; do
    encoding_lines[number]=1
  done
  for number in ${JOB_MAP_CR_LINES[@]+"${JOB_MAP_CR_LINES[@]}"}; do
    cr_lines[number]=1
    last_cr="$number"
  done
  for line in ${JOB_MAP_MALFORMED_LINES[@]+"${JOB_MAP_MALFORMED_LINES[@]}"}; do
    if [ "$JOB_MAP_BOM_LINE" -eq "$line" ]; then
      job_map_emit "error: byte order mark is not allowed line=$line path: $shown_path"
      reported=$((reported + 1))
    fi
    if [ -n "${nul_lines[line]+x}" ]; then
      job_map_emit "error: nul byte is not allowed line=$line path: $shown_path"
      reported=$((reported + 1))
    fi
    if [ -n "${encoding_lines[line]+x}" ]; then
      job_map_emit "error: encoding is not utf-8 line=$line path: $shown_path"
      reported=$((reported + 1))
    fi
    if [ -n "${cr_lines[line]+x}" ]; then
      job_map_emit "error: carriage return is not allowed line=$line path: $shown_path"
      reported=$((reported + 1))
      if [ "$line" -eq "$last_cr" ]; then
        job_map_emit "hint: use LF line endings"
      fi
    fi
  done
  [ "$reported" -eq 0 ]
}

# クォート不正のデータ行を全件報告する(ヘッダーが使えず列検証に進めないときも行番号付きで出す)
# 引数: shown_path
validate_crosscheck_job_map_report_quote_errors() {
  local shown_path="$1" row_index=0 row_count="${#JOB_MAP_ROW_LINES[@]}"
  while [ "$row_index" -lt "$row_count" ]; do
    if [ "${JOB_MAP_ROW_STATUSES[$row_index]}" = "$JOB_MAP_PARSE_QUOTE_INVALID" ]; then
      job_map_emit "error: csv quote is invalid line=${JOB_MAP_ROW_LINES[$row_index]} path: $shown_path"
    fi
    row_index=$((row_index + 1))
  done
}

# 宣言 3 件の検証(検証ルール #8 と設定所有区分の対象カタログ参照)。結果は VALIDATE_CROSSCHECK_JOB_MAP_* に載せる。
# 同じ宣言が複数回あるときは初出の値を使い、2 回目以降は `declaration is invalid` として報告する(どちらを使うか決められないため)。
# 戻り値: 報告した error 行の件数を VALIDATE_CROSSCHECK_JOB_MAP_DECL_ERRORS に載せ、常に 0
# 引数: shown_path
VALIDATE_CROSSCHECK_JOB_MAP_DECL_ERRORS=0
VALIDATE_CROSSCHECK_JOB_MAP_EXIT_CODE_CONTRACT=""
VALIDATE_CROSSCHECK_JOB_MAP_TARGET_CATALOG_PATH=""
VALIDATE_CROSSCHECK_JOB_MAP_CATALOG_VERSION=""
VALIDATE_CROSSCHECK_JOB_MAP_REFERENCE_DECLARED=false
validate_crosscheck_job_map_declarations() {
  local shown_path="$1" name index=0 count errors=0 reference_errors=0
  local -A duplicates=()
  VALIDATE_CROSSCHECK_JOB_MAP_DECL_ERRORS=0
  VALIDATE_CROSSCHECK_JOB_MAP_REFERENCE_DECLARED=false

  crosscheck_job_map_repo_declaration "$CROSSCHECK_DECL_EXIT_CODE_CONTRACT"
  VALIDATE_CROSSCHECK_JOB_MAP_EXIT_CODE_CONTRACT="$CROSSCHECK_JOB_MAP_DECL_VALUE"
  if ! validate_exit_code_contract_declaration "$shown_path" "$CROSSCHECK_JOB_MAP_DECL_FOUND" "$CROSSCHECK_JOB_MAP_DECL_VALUE"; then
    errors=$((errors + 1))
  fi

  crosscheck_job_map_repo_declaration "$CROSSCHECK_DECL_TARGET_CATALOG_PATH"
  VALIDATE_CROSSCHECK_JOB_MAP_TARGET_CATALOG_PATH="$CROSSCHECK_JOB_MAP_DECL_VALUE"
  if ! validate_required_declaration "$shown_path" "$CROSSCHECK_DECL_TARGET_CATALOG_PATH" "$CROSSCHECK_JOB_MAP_DECL_FOUND" "$CROSSCHECK_JOB_MAP_DECL_VALUE"; then
    reference_errors=$((reference_errors + 1))
  fi

  crosscheck_job_map_repo_declaration "$CROSSCHECK_DECL_CATALOG_VERSION"
  VALIDATE_CROSSCHECK_JOB_MAP_CATALOG_VERSION="$CROSSCHECK_JOB_MAP_DECL_VALUE"
  if ! validate_required_declaration "$shown_path" "$CROSSCHECK_DECL_CATALOG_VERSION" "$CROSSCHECK_JOB_MAP_DECL_FOUND" "$CROSSCHECK_JOB_MAP_DECL_VALUE"; then
    reference_errors=$((reference_errors + 1))
  fi
  if [ "$reference_errors" -eq 0 ]; then
    VALIDATE_CROSSCHECK_JOB_MAP_REFERENCE_DECLARED=true
  fi
  errors=$((errors + reference_errors))

  # 2 回目以降の同名宣言(出現順)
  count="${#CROSSCHECK_JOB_MAP_DECL_NAMES[@]}"
  while [ "$index" -lt "$count" ]; do
    name="${CROSSCHECK_JOB_MAP_DECL_NAMES[$index]}"
    case "$name" in
      "$CROSSCHECK_DECL_EXIT_CODE_CONTRACT" | "$CROSSCHECK_DECL_TARGET_CATALOG_PATH" | "$CROSSCHECK_DECL_CATALOG_VERSION")
        if [ -n "${duplicates[$name]+x}" ]; then
          cli_field_safe_text "${CROSSCHECK_JOB_MAP_DECL_VALUES[$index]}"
          job_map_emit "error: $name declaration is invalid value=$CLI_FIELD_SAFE_TEXT path: $shown_path"
          errors=$((errors + 1))
        else
          duplicates[$name]=1
        fi
        ;;
    esac
    index=$((index + 1))
  done
  VALIDATE_CROSSCHECK_JOB_MAP_DECL_ERRORS="$errors"
  return 0
}

# 行ごとの検証(全件)。結果は VALIDATE_CROSSCHECK_JOB_MAP_ROW_ERRORS / VALIDATE_CROSSCHECK_JOB_MAP_JOB_ID_PAIRS。
# クォート不正・列数不一致の行は列を対応付けられないため、列検証・重複検査の対象にしない。
# 列は列順固定(ヘッダー検証済み)なので、セルの連結配列から添字で直接取り出す(行数に比例する時間)。
# --verbose は検査した行ごとに `info: checked job_id=...` を出す(終了コードに影響しない)。
# 引数: verbose shown_path
VALIDATE_CROSSCHECK_JOB_MAP_ROW_ERRORS=0
VALIDATE_CROSSCHECK_JOB_MAP_JOB_ID_PAIRS=()
validate_crosscheck_job_map_rows() {
  local verbose="$1" shown_path="$2"
  local row_index=0 row_count="${#JOB_MAP_ROW_LINES[@]}" line actual offset job_id
  local LC_ALL=C
  VALIDATE_CROSSCHECK_JOB_MAP_ROW_ERRORS=0
  VALIDATE_CROSSCHECK_JOB_MAP_JOB_ID_PAIRS=()
  while [ "$row_index" -lt "$row_count" ]; do
    line="${JOB_MAP_ROW_LINES[$row_index]}"
    actual="${JOB_MAP_ROW_CELL_COUNTS[$row_index]}"
    if [ "${JOB_MAP_ROW_STATUSES[$row_index]}" = "$JOB_MAP_PARSE_QUOTE_INVALID" ]; then
      job_map_emit "error: csv quote is invalid line=$line path: $shown_path"
      VALIDATE_CROSSCHECK_JOB_MAP_ROW_ERRORS=$((VALIDATE_CROSSCHECK_JOB_MAP_ROW_ERRORS + 1))
    elif [ "$actual" -ne "$CROSSCHECK_JOB_MAP_COLUMN_COUNT" ]; then
      job_map_emit "error: column count mismatch line=$line expected=$CROSSCHECK_JOB_MAP_COLUMN_COUNT actual=$actual"
      VALIDATE_CROSSCHECK_JOB_MAP_ROW_ERRORS=$((VALIDATE_CROSSCHECK_JOB_MAP_ROW_ERRORS + 1))
    else
      offset="${JOB_MAP_ROW_OFFSETS[$row_index]}"
      job_id="${JOB_MAP_CELLS[offset]}"
      if ! validate_comparison_definition_row "$line" "$job_id" "${JOB_MAP_CELLS[offset + 1]}" "${JOB_MAP_CELLS[offset + 2]}" \
        "${JOB_MAP_CELLS[offset + 3]}" "${JOB_MAP_CELLS[offset + 4]}" "${JOB_MAP_CELLS[offset + 5]}"; then
        VALIDATE_CROSSCHECK_JOB_MAP_ROW_ERRORS=$((VALIDATE_CROSSCHECK_JOB_MAP_ROW_ERRORS + COMPARISON_DEFINITION_ROW_ERRORS))
      fi
      if [ "$verbose" = "true" ]; then
        cli_field_safe_text "$job_id"
        job_map_emit "info: checked job_id=$CLI_FIELD_SAFE_TEXT"
      fi
      VALIDATE_CROSSCHECK_JOB_MAP_JOB_ID_PAIRS+=("$line" "$job_id")
    fi
    row_index=$((row_index + 1))
  done
}

# 読み込み済みの対象カタログ(JOB_MAP_*)のデータ行の形式違反を全件、物理行順に共通文言で報告する(config_input_rules は
# 全設定ファイル共通。クォート不正は `csv quote is invalid`(path はカタログ)、列数不一致(空白だけの行を含む)は
# `column count mismatch`)。expected はカタログのヘッダー行の列数(列名・列数の検証は tier-final-crosscheck に委ねる)。
# 戻り値: 0 … 違反なし / 1 … 違反あり(報告済み。件数は CROSSCHECK_TARGET_CATALOG_ROW_ERRORS)
# 引数: shown_path
CROSSCHECK_TARGET_CATALOG_ROW_ERRORS=0
crosscheck_target_catalog_report_row_errors() {
  local shown_path="$1" row_index=0 row_count="${#JOB_MAP_ROW_LINES[@]}" expected="${#JOB_MAP_HEADER[@]}" line actual
  CROSSCHECK_TARGET_CATALOG_ROW_ERRORS=0
  while [ "$row_index" -lt "$row_count" ]; do
    line="${JOB_MAP_ROW_LINES[$row_index]}"
    actual="${JOB_MAP_ROW_CELL_COUNTS[$row_index]}"
    if [ "${JOB_MAP_ROW_STATUSES[$row_index]}" = "$JOB_MAP_PARSE_QUOTE_INVALID" ]; then
      job_map_emit "error: csv quote is invalid line=$line path: $shown_path"
      CROSSCHECK_TARGET_CATALOG_ROW_ERRORS=$((CROSSCHECK_TARGET_CATALOG_ROW_ERRORS + 1))
    elif [ "$actual" -ne "$expected" ]; then
      job_map_emit "error: column count mismatch line=$line expected=$expected actual=$actual"
      CROSSCHECK_TARGET_CATALOG_ROW_ERRORS=$((CROSSCHECK_TARGET_CATALOG_ROW_ERRORS + 1))
    fi
    row_index=$((row_index + 1))
  done
  [ "$CROSSCHECK_TARGET_CATALOG_ROW_ERRORS" -eq 0 ]
}

# 対象カタログ参照の解決(検証ルール #9)。カタログを読み込み、入力の守備範囲の違反(config_input_rules は全設定ファイル共通)を
# ジョブマップ本体と同じ順序・同じ文言(path はカタログのパス、line はカタログの物理行)で全件報告する:
#   バイト点検(NUL / 不正な UTF-8 / BOM / CR)→ ヘッダー行のクォート不正(+ データ行のクォート不正)→ ヘッダーの列名の重複
#   → データ行のクォート不正・列数不一致(空白だけの行を含む)。
# 形式違反のあるカタログでは版を照合しない(列を対応付けられない行を無視して成功にしない)。
# 形式違反・列名の重複・catalog_version 列なし・該当行なし・ファイル不在のいずれも、参照は解決できないので
# 最後に `error: target catalog reference unresolved path=... catalog_version=...` を 1 行出す。
# 出した error 行の件数は VALIDATE_CROSSCHECK_JOB_MAP_CATALOG_ERRORS(解決できたら 0)。
# 戻り値: 0 … 解決の判定を終えた / 1 … 内部障害(報告済み。呼び出し元が終了コード 6 にする)
# 引数: catalog_path version
VALIDATE_CROSSCHECK_JOB_MAP_CATALOG_ERRORS=0
validate_crosscheck_job_map_resolve_catalog() {
  local catalog_path="$1" version="$2" load_status=0 resolved=false format_ok=true shown_catalog shown_version
  local report_index="${#JOB_MAP_REPORT_LINES[@]}"
  VALIDATE_CROSSCHECK_JOB_MAP_CATALOG_ERRORS=0
  cli_field_safe_text "$catalog_path"
  shown_catalog="$CLI_FIELD_SAFE_TEXT"
  crosscheck_target_catalog_repo_load "$catalog_path" || load_status=$?
  if [ "$load_status" -eq "$JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED" ]; then
    validate_crosscheck_job_map_report_snapshot_failure "$shown_catalog"
    return 1
  fi
  if [ "$load_status" -eq "$JOB_MAP_REPO_STATUS_COMMAND_FAILED" ]; then
    validate_crosscheck_job_map_report_command_failure "$JOB_MAP_REPO_FAILED_COMMANDS" "$shown_catalog"
    return 1
  fi
  if [ "$load_status" -eq "$CROSSCHECK_TARGET_CATALOG_FORMAT_INVALID" ]; then
    # 形式違反の行は解析できないため、ヘッダーの判定に進まない(ジョブマップ側と同じ順序)
    if ! validate_crosscheck_job_map_report_byte_errors "$shown_catalog"; then
      :
    elif [ "$JOB_MAP_HEADER_STATUS" = "$JOB_MAP_PARSE_QUOTE_INVALID" ]; then
      # ヘッダーが使えないので列数不一致は判定できない。データ行のクォート不正だけを報告する(ジョブマップ本体と同じ)
      job_map_emit "error: csv quote is invalid line=$JOB_MAP_HEADER_LINE path: $shown_catalog"
      validate_crosscheck_job_map_report_quote_errors "$shown_catalog"
    fi
  elif [ "$load_status" -eq "$CROSSCHECK_TARGET_CATALOG_LOADED" ]; then
    report_duplicate_columns "$shown_catalog" ${JOB_MAP_HEADER[@]+"${JOB_MAP_HEADER[@]}"} || format_ok=false
    crosscheck_target_catalog_report_row_errors "$shown_catalog" || format_ok=false
    if [ "$format_ok" = true ] && crosscheck_target_catalog_repo_has_version "$version"; then
      resolved=true
    fi
  fi
  if [ "$resolved" = false ]; then
    cli_field_safe_text "$version"
    shown_version="$CLI_FIELD_SAFE_TEXT"
    job_map_emit "error: target catalog reference unresolved path=$shown_catalog catalog_version=$shown_version"
  fi
  validate_crosscheck_job_map_count_errors_since "$report_index"
  VALIDATE_CROSSCHECK_JOB_MAP_CATALOG_ERRORS="$VALIDATE_CROSSCHECK_JOB_MAP_COUNTED_ERRORS"
  return 0
}

# 集計出力(stdout。出力契約の固定順)
# 引数: path rows target_catalog_path catalog_version exit_code_contract errors
validate_crosscheck_job_map_print_summary() {
  local path="$1" rows="$2" catalog_path="$3" catalog_version="$4" exit_code_contract="$5" errors="$6"
  cli_field_line config "$CROSSCHECK_JOB_MAP_CONFIG_NAME"
  cli_path_field_line path "$path"
  cli_field_line rows "$rows"
  cli_path_field_line target_catalog_path "$catalog_path"
  cli_field_line catalog_version "$catalog_version"
  cli_field_line exit_code_contract "$exit_code_contract"
  if [ "$errors" -eq 0 ]; then
    cli_field_line status valid
  else
    cli_field_line status invalid
    cli_field_line violations "$errors"
  fi
}

# 検証の本体(validate_crosscheck_job_map から呼ぶ。JOB_MAP_REPORT_SINK は配列)
# 引数: path verbose shown_path
validate_crosscheck_job_map_run() {
  local path="$1" verbose="$2" shown_path="$3" load_status=0 errors=0 row_count

  # (1) 入力の複製 → (2) バイト点検。複製の失敗と補助コマンドの失敗は検証結果にせず終了コード 6
  crosscheck_job_map_repo_load "$path" || load_status=$?
  if [ "$load_status" -eq "$JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED" ]; then
    validate_crosscheck_job_map_report_snapshot_failure "$shown_path"
    return "$CROSSCHECK_JOB_MAP_EXIT_EXECUTION_ERROR"
  fi
  if [ "$load_status" -ne 0 ]; then
    validate_crosscheck_job_map_report_command_failure "$JOB_MAP_REPO_FAILED_COMMANDS" "$shown_path"
    return "$CROSSCHECK_JOB_MAP_EXIT_EXECUTION_ERROR"
  fi
  # 形式違反の行は解析できないため、ヘッダー・宣言・行・重複の検証には進まない
  if ! validate_crosscheck_job_map_report_byte_errors "$shown_path"; then
    validate_crosscheck_job_map_report_violations "$shown_path"
    return "$CROSSCHECK_JOB_MAP_EXIT_VALIDATION_ERROR"
  fi

  # (3) ヘッダー行(列順固定)。クォート不正・不一致のときは列を対応付けられないため、行の検証に進まない(stdout も出さない)
  if [ "$JOB_MAP_HEADER_STATUS" = "$JOB_MAP_PARSE_QUOTE_INVALID" ]; then
    job_map_emit "error: csv quote is invalid line=$JOB_MAP_HEADER_LINE path: $shown_path"
    validate_crosscheck_job_map_report_quote_errors "$shown_path"
    validate_crosscheck_job_map_report_violations "$shown_path"
    return "$CROSSCHECK_JOB_MAP_EXIT_VALIDATION_ERROR"
  fi
  if ! validate_crosscheck_job_map_header "$shown_path" ${JOB_MAP_HEADER[@]+"${JOB_MAP_HEADER[@]}"}; then
    validate_crosscheck_job_map_report_quote_errors "$shown_path"
    validate_crosscheck_job_map_report_violations "$shown_path"
    return "$CROSSCHECK_JOB_MAP_EXIT_VALIDATION_ERROR"
  fi

  # (4) 宣言(exit_code_contract / target_catalog_path / catalog_version)
  validate_crosscheck_job_map_declarations "$shown_path"
  errors="$VALIDATE_CROSSCHECK_JOB_MAP_DECL_ERRORS"

  # (5) 行ごとの検証(全件)
  row_count="${#JOB_MAP_ROW_LINES[@]}"
  validate_crosscheck_job_map_rows "$verbose" "$shown_path"
  errors=$((errors + VALIDATE_CROSSCHECK_JOB_MAP_ROW_ERRORS))

  # (6) job_id の重複検査(予約 job_id final-crosscheck の最大 1 行も同じ検査で違反になる)。
  #     重複した job_id ごとに error 1 行が出るので、出た error 行の件数を違反件数に加える(戻り値は有無しか伝えない)
  local unique_status=0 report_index="${#JOB_MAP_REPORT_LINES[@]}"
  validate_job_map_unique_job_ids ${VALIDATE_CROSSCHECK_JOB_MAP_JOB_ID_PAIRS[@]+"${VALIDATE_CROSSCHECK_JOB_MAP_JOB_ID_PAIRS[@]}"} || unique_status=$?
  if [ "$unique_status" -eq "$JOB_MAP_STATUS_COMMAND_FAILED" ]; then
    validate_crosscheck_job_map_report_command_failure "sort" "$shown_path"
    return "$CROSSCHECK_JOB_MAP_EXIT_EXECUTION_ERROR"
  fi
  if [ "$unique_status" -ne 0 ]; then
    validate_crosscheck_job_map_count_errors_since "$report_index"
    errors=$((errors + VALIDATE_CROSSCHECK_JOB_MAP_COUNTED_ERRORS))
  fi

  # (7) 対象カタログ参照の解決(検証ルール #9。宣言が揃っているときだけ。カタログの読み込みは JOB_MAP_* を上書きするため最後に行う)
  local catalog_path="$VALIDATE_CROSSCHECK_JOB_MAP_TARGET_CATALOG_PATH" catalog_version="$VALIDATE_CROSSCHECK_JOB_MAP_CATALOG_VERSION"
  local exit_code_contract="$VALIDATE_CROSSCHECK_JOB_MAP_EXIT_CODE_CONTRACT"
  if [ "$VALIDATE_CROSSCHECK_JOB_MAP_REFERENCE_DECLARED" = true ]; then
    validate_crosscheck_job_map_resolve_catalog "$catalog_path" "$catalog_version" || return "$CROSSCHECK_JOB_MAP_EXIT_EXECUTION_ERROR"
    errors=$((errors + VALIDATE_CROSSCHECK_JOB_MAP_CATALOG_ERRORS))
  fi

  # (8) 出力(stderr の報告行 → hint → stdout の集計)
  if [ "$errors" -ne 0 ]; then
    validate_crosscheck_job_map_report_violations "$shown_path"
    validate_crosscheck_job_map_print_summary "$path" "$row_count" "$catalog_path" "$catalog_version" "$exit_code_contract" "$errors"
    return "$CROSSCHECK_JOB_MAP_EXIT_VALIDATION_ERROR"
  fi
  validate_crosscheck_job_map_flush_report
  validate_crosscheck_job_map_print_summary "$path" "$row_count" "$catalog_path" "$catalog_version" "$exit_code_contract" 0
  return "$CROSSCHECK_JOB_MAP_EXIT_OK"
}

# 引数: path verbose(true|false)
validate_crosscheck_job_map() {
  local path="$1" verbose="${2:-false}" shown_path
  cli_field_safe_text "$path"
  shown_path="$CLI_FIELD_SAFE_TEXT"

  if [ ! -e "$path" ]; then
    printf '%s\n' "error: config file not found path: $shown_path" >&2
    printf '%s\n' "hint: fix the rows above and rerun validate-config.sh $CROSSCHECK_JOB_MAP_OPTION $shown_path" >&2
    return "$CROSSCHECK_JOB_MAP_EXIT_VALIDATION_ERROR"
  fi
  if [ ! -f "$path" ] || [ ! -r "$path" ]; then
    printf '%s\n' "error: config file is not readable path: $shown_path" >&2
    printf '%s\n' "hint: fix the rows above and rerun validate-config.sh $CROSSCHECK_JOB_MAP_OPTION $shown_path" >&2
    return "$CROSSCHECK_JOB_MAP_EXIT_VALIDATION_ERROR"
  fi

  # 報告行は検証を終えるまで溜める(内部障害のときに他の行を出さないため)。戻るときに出力先を元に戻す
  local saved_sink="$JOB_MAP_REPORT_SINK" status=0
  JOB_MAP_REPORT_SINK="$JOB_MAP_REPORT_SINK_ARRAY"
  JOB_MAP_REPORT_LINES=()
  validate_crosscheck_job_map_run "$path" "$verbose" "$shown_path" || status=$?
  JOB_MAP_REPORT_SINK="$saved_sink"
  return "$status"
}
