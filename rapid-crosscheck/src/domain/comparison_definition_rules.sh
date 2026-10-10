#!/usr/bin/env bash
# domain: ComparisonDefinitionRules(比較定義の検証表。純粋関数)。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-rapid-crosscheck.md
#       「設定契約(クロスチェックジョブマップ)」列の検証ルール / 予約 job_id final-crosscheck / 検証ルール一覧 #2〜#8, #10
#       _cross-cutting/api/cli-command-contract.yaml config_input_rules「ヘッダー列名の重複(CSV)」/
#       config_files crosscheck-job-map.csv columns(compare_command は absolute path、full 行の compare_targets は catalog 固定)
# 文言の正本: _cross-cutting/api/cli-command-contract.yaml commands[validate-config.sh].stderr(共通形式)
# この層は CSV の読み込み・クォート解析をしない(repository/crosscheck_job_map_repo.sh)。
# 違反行は job_map_emit で 1 行ずつ出す(全件収集。1 件目で止めない。報告 sink は usecase が配列にする)。
# 任意入力(セルの値・パス)は制御文字を可視表記にする(cli_field_safe_text。ui-design.md「制御文字の表記」)。
# 依存(契約未宣言の tier 間依存。validate-config.sh 経由の実行時は tier-facade が先に source 済み):
#   facade/src/domain/cli_field.sh(cli_field_safe_text)/ facade/src/domain/job_map.sh(job_map_emit)
#   根拠: docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md

# 設定所有区分: クロスチェックジョブマップが所有する 6 列(列順固定。slot ジョブマップの host / user 等は置かない)。
# 列数は usecase の列数検証(検証ルール #3)が読む。ヘッダーの一致判定は列ごとに行う(文字列の再結合で比較しない)
CROSSCHECK_JOB_MAP_EXPECTED_COLUMNS=(job_id comparison_type compare_targets compare_command compare_options definition_version)
CROSSCHECK_JOB_MAP_EXPECTED_HEADER="job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version"
# shellcheck disable=SC2034
CROSSCHECK_JOB_MAP_COLUMN_COUNT=6
# full 行の compare_targets の固定値(設定契約「予約 job_id final-crosscheck」/ 契約 columns.compare_targets)
COMPARE_TARGETS_CATALOG="catalog"

# 宣言(コメント行)の名前(対象カタログ参照の 2 件は usecase / repository が読む)
CROSSCHECK_DECL_EXIT_CODE_CONTRACT="exit_code_contract"
# shellcheck disable=SC2034
CROSSCHECK_DECL_TARGET_CATALOG_PATH="target_catalog_path"
# shellcheck disable=SC2034
CROSSCHECK_DECL_CATALOG_VERSION="catalog_version"
# 比較ツール終了コード契約への適合宣言の値(固定文字列。0=OK / 3=NG / 6=実行エラー。relay-gate は値を変換しない)
CROSSCHECK_EXIT_CODE_CONTRACT_VALUE="0:OK,3:NG,6:ERROR"

# 比較種別(comparison_type)
COMPARISON_TYPE_JOB="job"
COMPARISON_TYPE_FULL="full"
# 予約 job_id(確報用。comparison_type=full の行だけに使う。canonical C5)
FINAL_CROSSCHECK_JOB_ID="final-crosscheck"
# compare_options のプレースホルダ(job 行は成果物 URI、full 行は対象カタログと業務日付に置換される)
PLACEHOLDER_BLUE="{blue}"
PLACEHOLDER_GREEN="{green}"
PLACEHOLDER_CATALOG_VERSION="{catalog_version}"
PLACEHOLDER_BUSINESS_DATE="{business_date}"

# validate_comparison_definition_row が出した error 行の件数
COMPARISON_DEFINITION_ROW_ERRORS=0

# 行数に比例して呼ばれる関数は、バイト単位の判定のための LC_ALL=C を呼び出し元が設定済みなら設定しない
# (LC_ALL の設定は setlocale を伴い、関数呼び出しより重い。usecase の行ループは C にして呼ぶ)

# job_id は `^[A-Za-z0-9_-]+$`(ASCII のバイトとして判定する)
comparison_definition_is_valid_job_id() {
  if [ "${LC_ALL:-}" != C ]; then
    local LC_ALL=C
  fi
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]
}

# 列が空: `error: <column> is empty line=N job_id=<v> value=`(検証ルール #10)
# 引数: column line job_id(元の値)
comparison_definition_empty_error() {
  cli_field_safe_text "$3"
  job_map_emit "error: $1 is empty line=$2 job_id=$CLI_FIELD_SAFE_TEXT value="
}

# 列の値の違反: `error: <column> is <reason> line=N job_id=<v> value=<v>`
# 引数: column_and_reason line job_id(元の値) value(元の値)
comparison_definition_value_error() {
  local job_id
  cli_field_safe_text "$3"
  job_id="$CLI_FIELD_SAFE_TEXT"
  cli_field_safe_text "$4"
  job_map_emit "error: $1 line=$2 job_id=$job_id value=$CLI_FIELD_SAFE_TEXT"
}

# 入力の守備範囲「ヘッダー列名の重複(CSV)」(config_input_rules): 同じ列名が 2 回以上あれば
# `error: duplicate column column=<name> path: ...` を重複した列名ごとに 1 行(初出順)出す。
# クロスチェックジョブマップのヘッダーと、参照する対象カタログのヘッダーの両方に使う(全設定ファイル共通の規則)。
# 戻り値: 0 … 重複なし / 1 … 重複あり(報告済み。件数は CROSSCHECK_DUPLICATE_COLUMN_ERRORS)
# 引数: shown_path header_cells...
CROSSCHECK_DUPLICATE_COLUMN_ERRORS=0
report_duplicate_columns() {
  local shown_path="$1" column key
  shift
  # 連想配列の添字は空の列名でも使えるよう接頭辞を付ける(facade の validate_job_map_header と同じ方式)
  local -A counts=() reported=()
  CROSSCHECK_DUPLICATE_COLUMN_ERRORS=0
  for column in "$@"; do
    key="c$column"
    counts["$key"]=$((${counts["$key"]:-0} + 1))
  done
  for column in "$@"; do
    key="c$column"
    if [ "${counts["$key"]}" -gt 1 ] && [ -z "${reported["$key"]+x}" ]; then
      reported["$key"]=1
      cli_field_safe_text "$column"
      job_map_emit "error: duplicate column column=$CLI_FIELD_SAFE_TEXT path: $shown_path"
      CROSSCHECK_DUPLICATE_COLUMN_ERRORS=$((CROSSCHECK_DUPLICATE_COLUMN_ERRORS + 1))
    fi
  done
  [ "$CROSSCHECK_DUPLICATE_COLUMN_ERRORS" -eq 0 ]
}

# ヘッダー不一致の `actual=` に出す列名の並び。列の境界が読み取れるよう、カンマ・二重引用符を含む列名は
# CSV と同じ二重引用符の囲み(内側の `"` は `""`)で出す(1 セルに `job_id,comparison_type,...` が入った入力を
# expected= と同じ文字列で出さない)。結果は COMPARISON_DEFINITION_HEADER_TEXT
# 引数: header_cells...
COMPARISON_DEFINITION_HEADER_TEXT=""
comparison_definition_header_text() {
  local cell text="" first=true
  for cell in "$@"; do
    case "$cell" in
      *,* | *\"*)
        cell="\"${cell//\"/\"\"}\""
        ;;
    esac
    if [ "$first" = true ]; then
      text="$cell"
      first=false
    else
      text="$text,$cell"
    fi
  done
  COMPARISON_DEFINITION_HEADER_TEXT="$text"
}

# 検証ルール #2: ヘッダー行が列定義と完全一致(順序含む。列数の相違・列名の相違・未知列・欠落はすべて不一致)。
# 判定は列の個数と各位置の列名で行う(セルを再結合した文字列では、1 セルに全列名を入れた入力を区別できない)。
# 列名の重複は、不一致の報告の前に入力の守備範囲の規則(report_duplicate_columns)で報告する。
# 戻り値: 0 … 一致 / 1 … 不一致(報告済み。件数は CROSSCHECK_JOB_MAP_HEADER_ERRORS)
# 引数: shown_path header_cells...
CROSSCHECK_JOB_MAP_HEADER_ERRORS=0
validate_crosscheck_job_map_header() {
  local shown_path="$1" index=0 position matched=true
  shift
  CROSSCHECK_JOB_MAP_HEADER_ERRORS=0
  if ! report_duplicate_columns "$shown_path" "$@"; then
    CROSSCHECK_JOB_MAP_HEADER_ERRORS="$CROSSCHECK_DUPLICATE_COLUMN_ERRORS"
    matched=false
  fi
  if [ "$#" -ne "${#CROSSCHECK_JOB_MAP_EXPECTED_COLUMNS[@]}" ]; then
    matched=false
  else
    for index in "${!CROSSCHECK_JOB_MAP_EXPECTED_COLUMNS[@]}"; do
      position=$((index + 1))
      if [ "${!position}" != "${CROSSCHECK_JOB_MAP_EXPECTED_COLUMNS[$index]}" ]; then
        matched=false
        break
      fi
    done
  fi
  if [ "$matched" = true ]; then
    return 0
  fi
  comparison_definition_header_text "$@"
  cli_field_safe_text "$COMPARISON_DEFINITION_HEADER_TEXT"
  job_map_emit "error: header mismatch expected=$CROSSCHECK_JOB_MAP_EXPECTED_HEADER actual=$CLI_FIELD_SAFE_TEXT path: $shown_path"
  CROSSCHECK_JOB_MAP_HEADER_ERRORS=$((CROSSCHECK_JOB_MAP_HEADER_ERRORS + 1))
  return 1
}

# 検証ルール #8: `# exit_code_contract=0:OK,3:NG,6:ERROR` 宣言。
# 戻り値: 0 … 適合 / 1 … 違反(報告済み)
# 引数: shown_path found_count value
validate_exit_code_contract_declaration() {
  local shown_path="$1" found="$2" value="$3"
  if [ "$found" -eq 0 ]; then
    job_map_emit "error: $CROSSCHECK_DECL_EXIT_CODE_CONTRACT declaration not found path: $shown_path"
    return 1
  fi
  if [ "$value" != "$CROSSCHECK_EXIT_CODE_CONTRACT_VALUE" ]; then
    cli_field_safe_text "$value"
    job_map_emit "error: $CROSSCHECK_DECL_EXIT_CODE_CONTRACT declaration is invalid value=$CLI_FIELD_SAFE_TEXT path: $shown_path"
    return 1
  fi
  return 0
}

# 設定所有区分: 対象カタログ参照の宣言(`# target_catalog_path=` / `# catalog_version=`)は必須で、値が非空。
# 戻り値: 0 … 宣言あり / 1 … 違反(報告済み)
# 引数: shown_path name found_count value
validate_required_declaration() {
  local shown_path="$1" name="$2" found="$3" value="$4"
  if [ "$found" -eq 0 ]; then
    job_map_emit "error: $name declaration not found path: $shown_path"
    return 1
  fi
  if [ -z "$value" ]; then
    job_map_emit "error: $name declaration is invalid value= path: $shown_path"
    return 1
  fi
  return 0
}

# 列定義: compare_command は絶対パス(契約 columns.compare_command は string(absolute path)。相対パスは受理しない)
comparison_definition_is_absolute_path() {
  case "$1" in
    /*) return 0 ;;
    *) return 1 ;;
  esac
}

# 検証ルール #6: compare_command は存在し実行権限がある通常ファイル
comparison_definition_is_executable() {
  [ -f "$1" ] && [ -x "$1" ]
}

# 列ごとの検証(1 行分。違反は全件出す。件数は COMPARISON_DEFINITION_ROW_ERRORS)。
# 検証ルール #5(job_id 形式)/ #6(compare_command 実行可)/ #7(job 行のプレースホルダ)/ #7a(full 行の予約 job_id とプレースホルダ)/
# #7b(comparison_type の列挙)/ #10(必須列が非空)。重複(#4 / #7a の最大 1 行)は usecase の重複検査が担う。
# 戻り値: 0 … 違反なし / 1 … 違反あり
# 引数: line job_id comparison_type compare_targets compare_command compare_options definition_version
validate_comparison_definition_row() {
  local line="$1" job_id="$2" comparison_type="$3" compare_targets="$4" compare_command="$5" compare_options="$6" definition_version="$7"
  COMPARISON_DEFINITION_ROW_ERRORS=0

  # job_id(#10 → #5)
  if [ -z "$job_id" ]; then
    comparison_definition_empty_error job_id "$line" "$job_id"
    COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
  elif ! comparison_definition_is_valid_job_id "$job_id"; then
    comparison_definition_value_error "job_id is invalid" "$line" "$job_id" "$job_id"
    COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
  fi

  # comparison_type(#10 → #7b → #7a の予約 job_id との対応)
  if [ -z "$comparison_type" ]; then
    comparison_definition_empty_error comparison_type "$line" "$job_id"
    COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
  elif [ "$comparison_type" != "$COMPARISON_TYPE_JOB" ] && [ "$comparison_type" != "$COMPARISON_TYPE_FULL" ]; then
    comparison_definition_value_error "comparison_type is not in $COMPARISON_TYPE_JOB,$COMPARISON_TYPE_FULL" "$line" "$job_id" "$comparison_type"
    COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
  elif [ "$comparison_type" = "$COMPARISON_TYPE_FULL" ] && [ "$job_id" != "$FINAL_CROSSCHECK_JOB_ID" ]; then
    comparison_definition_value_error "job_id is not $FINAL_CROSSCHECK_JOB_ID for comparison_type=$COMPARISON_TYPE_FULL" "$line" "$job_id" "$job_id"
    COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
  elif [ "$comparison_type" = "$COMPARISON_TYPE_JOB" ] && [ "$job_id" = "$FINAL_CROSSCHECK_JOB_ID" ]; then
    # 予約 job_id の行は full 以外を違反にする(設定契約「予約 job_id final-crosscheck」。文言は #7a の対称形)
    comparison_definition_value_error "comparison_type is not $COMPARISON_TYPE_FULL for job_id=$FINAL_CROSSCHECK_JOB_ID" "$line" "$job_id" "$comparison_type"
    COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
  fi

  # compare_targets(#10 → full 行は固定値 `catalog`。job 行の値の形式は検査しない。複数はカンマ区切りの 1 セル)
  if [ -z "$compare_targets" ]; then
    comparison_definition_empty_error compare_targets "$line" "$job_id"
    COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
  elif [ "$comparison_type" = "$COMPARISON_TYPE_FULL" ] && [ "$compare_targets" != "$COMPARE_TARGETS_CATALOG" ]; then
    comparison_definition_value_error "compare_targets is not $COMPARE_TARGETS_CATALOG" "$line" "$job_id" "$compare_targets"
    COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
  fi

  # compare_command(#10 → 絶対パス → #6)
  if [ -z "$compare_command" ]; then
    comparison_definition_empty_error compare_command "$line" "$job_id"
    COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
  elif ! comparison_definition_is_absolute_path "$compare_command"; then
    comparison_definition_value_error "compare_command is not absolute" "$line" "$job_id" "$compare_command"
    COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
  elif ! comparison_definition_is_executable "$compare_command"; then
    comparison_definition_value_error "compare_command is not executable" "$line" "$job_id" "$compare_command"
    COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
  fi

  # compare_options(#10 → #7 / #7a のプレースホルダ。種別が列挙外の行はプレースホルダを判定しない)
  if [ -z "$compare_options" ]; then
    comparison_definition_empty_error compare_options "$line" "$job_id"
    COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
  elif [ "$comparison_type" = "$COMPARISON_TYPE_JOB" ]; then
    if [[ "$compare_options" != *"$PLACEHOLDER_BLUE"* ]] || [[ "$compare_options" != *"$PLACEHOLDER_GREEN"* ]]; then
      comparison_definition_value_error "compare_options is missing $PLACEHOLDER_BLUE or $PLACEHOLDER_GREEN" "$line" "$job_id" "$compare_options"
      COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
    fi
  elif [ "$comparison_type" = "$COMPARISON_TYPE_FULL" ]; then
    if [[ "$compare_options" != *"$PLACEHOLDER_CATALOG_VERSION"* ]] || [[ "$compare_options" != *"$PLACEHOLDER_BUSINESS_DATE"* ]]; then
      comparison_definition_value_error "compare_options is missing $PLACEHOLDER_CATALOG_VERSION or $PLACEHOLDER_BUSINESS_DATE" "$line" "$job_id" "$compare_options"
      COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
    fi
  fi

  # definition_version(#10)
  if [ -z "$definition_version" ]; then
    comparison_definition_empty_error definition_version "$line" "$job_id"
    COMPARISON_DEFINITION_ROW_ERRORS=$((COMPARISON_DEFINITION_ROW_ERRORS + 1))
  fi

  [ "$COMPARISON_DEFINITION_ROW_ERRORS" -eq 0 ]
}
