#!/usr/bin/env bash
# domain: TargetCatalogRules(対象カタログの検証表。純粋関数)。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-final-crosscheck.md
#       「設定契約(対象カタログ)」列の検証表 / 「検証ルール一覧」/ spec.md「計算ルール一覧」(カタログ版の集計)
# 文言の正本: _cross-cutting/api/cli-command-contract.yaml commands[validate-config.sh].stderr
#   (対象カタログは job_id 列を持たないため `job_id=` は付けない)
# この層は I/O を持たない(CSV の読み込み・クォート解析は repository/target_catalog_repo.sh)。
# 違反行は `error:` / `info:` を 1 行ずつ target_catalog_emit で TARGET_CATALOG_REPORT_LINES に溜める(全件収集。1 件目で止めない)。
# 任意入力(セルの値・列名・パス)を行に埋め込むときは、制御文字を可視表記にする(cli_field_safe_text。ui-design.md「制御文字の表記」)。
# 依存: cli_field_safe_text(tier-facade の facade/src/domain/cli_field.sh。validate-config.sh のエントリポイントが先に source する)。
#   契約 contracts[] に無い tier 間依存のため、扱いは
#   docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md に従う(暫定の依存)。
# bash 5.0 以上(連想配列。契約 conventions.runtime_prerequisites)

# 報告行(error / info / hint)の溜め先(usecase が検証を終えてから stderr へ出す。内部障害のときは捨てる)
TARGET_CATALOG_REPORT_LINES=()
# 溜めた error 行の件数(stdout の violations= に使う)
TARGET_CATALOG_ERROR_COUNT=0

# 設定契約: 対象カタログの 5 列(列順固定。契約 config_files[target-catalog.csv].columns。列数は usecase が読む)。
# 必須 3 列は catalog_version / target_type / target_identifier(検証ルール 7。validate_target_catalog_row が判定する)
# shellcheck disable=SC2034
TARGET_CATALOG_COLUMNS=(
  catalog_version
  target_type
  target_identifier
  compare_condition
  business_date_handling
)
# ヘッダー不一致の expected= に出す列名(契約の列順。カンマ区切り)
TARGET_CATALOG_HEADER_EXPECTED="catalog_version,target_type,target_identifier,compare_condition,business_date_handling"
# target_catalog_header_cell_shown の結果(actual= に出す 1 セル分の表記)
TARGET_CATALOG_HEADER_CELL_SHOWN=""

# 対象種別の列挙(検証ルール 4。バリエーション「対象カタログの対象種別」)
TARGET_CATALOG_TYPE_TABLE="table"
TARGET_CATALOG_TYPE_FILE="file"
TARGET_CATALOG_TYPE_ENUM="table,file"

# 空値の表記(ui-design.md 出力フォーマット「空値」)
TARGET_CATALOG_EMPTY_VALUE="-"

# target_catalog_row_bind_at の結果(1 行分の TargetCatalogRecord の値。列順は TARGET_CATALOG_COLUMNS)
TARGET_CATALOG_ROW_CATALOG_VERSION=""
TARGET_CATALOG_ROW_TARGET_TYPE=""
TARGET_CATALOG_ROW_TARGET_IDENTIFIER=""
TARGET_CATALOG_ROW_COMPARE_CONDITION=""
TARGET_CATALOG_ROW_BUSINESS_DATE_HANDLING=""

# 重複検査(検証ルール 5)の状態: キー(catalog_version / target_type / target_identifier)ごとの出現行番号と初出順
# 連想配列の添字はセルの値を改行で連結した複合キー(セルは改行を含まないため、区切りとして衝突しない)。
# -g: 関数の中(bats の setup 等)から source されても大域変数として宣言する(無いと関数のローカルになり添字が算術式として評価される)
declare -gA TARGET_CATALOG_KEY_LINES=()
TARGET_CATALOG_KEY_ORDER=()
# カタログ版の集計(計算ルール「カタログ版の集計」)の状態: 初出順の distinct 値と既知集合
declare -gA TARGET_CATALOG_VERSION_SEEN=()
TARGET_CATALOG_VERSION_LIST=()
# 対象種別ごとの行数(stdout の tables= / files=)
TARGET_CATALOG_TABLE_COUNT=0
TARGET_CATALOG_FILE_COUNT=0

# 報告行を 1 行溜める。`error:` で始まる行は件数も数える
# 引数: line
target_catalog_emit() {
  TARGET_CATALOG_REPORT_LINES+=("$1")
  case "$1" in
    error:*) TARGET_CATALOG_ERROR_COUNT=$((TARGET_CATALOG_ERROR_COUNT + 1)) ;;
  esac
}

# 検証の状態(報告行・重複検査・集計)を初期化する(usecase が検証の開始時に呼ぶ)
target_catalog_rules_reset() {
  TARGET_CATALOG_REPORT_LINES=()
  TARGET_CATALOG_ERROR_COUNT=0
  TARGET_CATALOG_KEY_LINES=()
  TARGET_CATALOG_KEY_ORDER=()
  TARGET_CATALOG_VERSION_SEEN=()
  TARGET_CATALOG_VERSION_LIST=()
  TARGET_CATALOG_TABLE_COUNT=0
  TARGET_CATALOG_FILE_COUNT=0
}

# 行数に比例して呼ばれる関数は、バイト単位の判定のための LC_ALL=C を呼び出し元が設定済みなら設定しない
# (LC_ALL の設定は setlocale を伴い、関数呼び出しより重い。usecase の行ループは C にして呼ぶ)

# catalog_version は非空で英数字・`.`・`_`・`-`(設定契約の列の検証表)。
# 文字範囲は ASCII のバイトとして判定する(ロケールの照合順序で範囲にアクセント付き文字や全角数字が入らないようにする)
target_catalog_is_valid_catalog_version() {
  if [ "${LC_ALL:-}" != C ]; then
    local LC_ALL=C
  fi
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

# target_type は `table` または `file`(検証ルール 4)
target_catalog_is_valid_target_type() {
  [ "$1" = "$TARGET_CATALOG_TYPE_TABLE" ] || [ "$1" = "$TARGET_CATALOG_TYPE_FILE" ]
}

# actual= に出す列名の 1 セル分の表記: カンマまたは二重引用符を含む列名は入力と同じクォート規則(二重引用符で囲み、
# 内側の二重引用符は `""`)で囲む。引用で結合された 1 セルのヘッダー(`"catalog_version,target_type,..."`)を
# 契約どおりの 5 列と見分けられるようにする(カンマで再連結した文字列は 5 列の表記と同じになるため)
# 結果: TARGET_CATALOG_HEADER_CELL_SHOWN
# 引数: column
target_catalog_header_cell_shown() {
  local column="$1"
  case "$column" in
    *,* | *\"*)
      column="${column//\"/\"\"}"
      TARGET_CATALOG_HEADER_CELL_SHOWN="\"$column\""
      ;;
    *) TARGET_CATALOG_HEADER_CELL_SHOWN="$column" ;;
  esac
}

# 検証ルール 2 / 入力の守備範囲「ヘッダー列名の重複」: ヘッダー行が列定義と完全一致するか(列順固定)。
#   - 同じ列名が 2 回以上あれば `error: duplicate column column=<name> path: ...`(重複した列名ごとに 1 行。config_input_rules)
#   - 列定義と一致しなければ `error: header mismatch expected=<契約の列> actual=<実際の列> path: ...`
#     (ヘッダー行が無い空のファイル・コメントだけのファイルは actual= が空。タブ区切りのファイルは 1 セルの列名として actual= に出る)
# 一致の判定は、解析済みのセル数が列定義の数と等しく、かつ各セルが同じ位置の列名と等しいことで行う
# (カンマで再連結した文字列の比較では、引用で結合された 1 セル・4 セルのヘッダーを 5 列と誤認する)。
# 出力順: duplicate column の error → header mismatch の error
# 戻り値: 0 … 一致 / 1 … 違反あり(報告済み)
# 引数: path header...
validate_target_catalog_header() {
  local path="$1"
  shift
  local shown_path column key errors=0 actual="" separator="" index=0 mismatch=0
  cli_field_safe_text "$path"
  shown_path="$CLI_FIELD_SAFE_TEXT"

  # 列名の出現回数を数え、2 回以上の列名を初出順に 1 行ずつ報告する(連想配列の添字は空の列名でも使えるよう接頭辞を付ける)
  local -A counts=() reported=()
  for column in "$@"; do
    key="c$column"
    counts["$key"]=$((${counts["$key"]:-0} + 1))
  done
  for column in "$@"; do
    key="c$column"
    if [ "${counts["$key"]}" -gt 1 ] && [ -z "${reported["$key"]+x}" ]; then
      reported["$key"]=1
      cli_field_safe_text "$column"
      target_catalog_emit "error: duplicate column column=$CLI_FIELD_SAFE_TEXT path: $shown_path"
      errors=$((errors + 1))
    fi
  done

  # セル数と位置ごとの列名で一致を判定する(比較は元の値で行う)
  if [ "$#" -ne "${#TARGET_CATALOG_COLUMNS[@]}" ]; then
    mismatch=1
  else
    for column in "$@"; do
      if [ "$column" != "${TARGET_CATALOG_COLUMNS[index]}" ]; then
        mismatch=1
        break
      fi
      index=$((index + 1))
    done
  fi
  if [ "$mismatch" -ne 0 ]; then
    # 列名は任意入力(表示用に制御文字を可視表記にし、カンマを含む列名は引用して列境界を示す)
    for column in "$@"; do
      target_catalog_header_cell_shown "$column"
      actual+="$separator$TARGET_CATALOG_HEADER_CELL_SHOWN"
      separator=","
    done
    cli_field_safe_text "$actual"
    target_catalog_emit "error: header mismatch expected=$TARGET_CATALOG_HEADER_EXPECTED actual=$CLI_FIELD_SAFE_TEXT path: $shown_path"
    errors=$((errors + 1))
  fi
  [ "$errors" -eq 0 ]
}

# 全データ行のセルを連結した配列(repository の TARGET_CATALOG_CELLS)から、offset で始まる 1 行分を
# TARGET_CATALOG_ROW_* に載せる(列順固定なので添字は契約の列順そのもの)。
# 前提: ヘッダー一致済みで、セル数が 5(列数検証は usecase)
# 引数: cells_array_name offset
target_catalog_row_bind_at() {
  local -n target_catalog_cells_ref="$1"
  local offset="$2"
  TARGET_CATALOG_ROW_CATALOG_VERSION="${target_catalog_cells_ref[offset]}"
  TARGET_CATALOG_ROW_TARGET_TYPE="${target_catalog_cells_ref[offset + 1]}"
  TARGET_CATALOG_ROW_TARGET_IDENTIFIER="${target_catalog_cells_ref[offset + 2]}"
  # compare_condition / business_date_handling は任意列(検証しない。--verbose の表示にも使わない)
  # shellcheck disable=SC2034
  TARGET_CATALOG_ROW_COMPARE_CONDITION="${target_catalog_cells_ref[offset + 3]}"
  # shellcheck disable=SC2034
  TARGET_CATALOG_ROW_BUSINESS_DATE_HANDLING="${target_catalog_cells_ref[offset + 4]}"
}

# 必須列の空セル(検証ルール 7): `error: <column> is empty line=N value=`
# 引数: column line
target_catalog_empty_cell_error() {
  target_catalog_emit "error: $1 is empty line=$2 value="
}

# 列の値の違反: `error: <column> is <reason> line=N value=<v>`(value は表示用に制御文字を可視表記にする)
# 引数: column_and_reason line value(元の値)
target_catalog_value_error() {
  cli_field_safe_text "$3"
  target_catalog_emit "error: $1 line=$2 value=$CLI_FIELD_SAFE_TEXT"
}

# 列ごとの検証(TARGET_CATALOG_ROW_* を検証する。違反は全件出す)。
# 検証は元の値で行い、メッセージには表示用の値(制御文字を可視表記にしたもの)を出す。
# 任意列 compare_condition / business_date_handling は値を検査しない(無ければ `-` を置く規則は設計者側の記法。空セルも受理する)
# 戻り値: 0 … 違反なし / 1 … 違反あり(報告済み)
# 引数: line(行番号)
validate_target_catalog_row() {
  local line="$1" errors=0

  # catalog_version: 非空。英数字・`.`・`_`・`-`
  if [ -z "$TARGET_CATALOG_ROW_CATALOG_VERSION" ]; then
    target_catalog_empty_cell_error catalog_version "$line"
    errors=$((errors + 1))
  elif ! target_catalog_is_valid_catalog_version "$TARGET_CATALOG_ROW_CATALOG_VERSION"; then
    target_catalog_value_error "catalog_version is invalid" "$line" "$TARGET_CATALOG_ROW_CATALOG_VERSION"
    errors=$((errors + 1))
  fi

  # target_type: table / file(検証ルール 4)
  if [ -z "$TARGET_CATALOG_ROW_TARGET_TYPE" ]; then
    target_catalog_empty_cell_error target_type "$line"
    errors=$((errors + 1))
  elif ! target_catalog_is_valid_target_type "$TARGET_CATALOG_ROW_TARGET_TYPE"; then
    target_catalog_value_error "target_type is not in $TARGET_CATALOG_TYPE_ENUM" "$line" "$TARGET_CATALOG_ROW_TARGET_TYPE"
    errors=$((errors + 1))
  fi

  # target_identifier: 非空のみ(テーブル名・ファイルパスの形式は検査しない)
  if [ -z "$TARGET_CATALOG_ROW_TARGET_IDENTIFIER" ]; then
    target_catalog_empty_cell_error target_identifier "$line"
    errors=$((errors + 1))
  fi

  [ "$errors" -eq 0 ]
}

# 検証ルール 5 の登録: 現在の行のキー(catalog_version, target_type, target_identifier)と行番号を記録する。
# キーの 3 列がすべて非空の行だけを対象にする(空セルは検証ルール 7 で報告済み)。
# 全組合せの比較(行数の 2 乗)を避け、連想配列で行数に比例する時間にする
# 引数: line
target_catalog_register_key() {
  local line="$1" key
  if [ -z "$TARGET_CATALOG_ROW_CATALOG_VERSION" ] || [ -z "$TARGET_CATALOG_ROW_TARGET_TYPE" ] || [ -z "$TARGET_CATALOG_ROW_TARGET_IDENTIFIER" ]; then
    return 0
  fi
  key="$TARGET_CATALOG_ROW_CATALOG_VERSION"$'\n'"$TARGET_CATALOG_ROW_TARGET_TYPE"$'\n'"$TARGET_CATALOG_ROW_TARGET_IDENTIFIER"
  if [ -z "${TARGET_CATALOG_KEY_LINES["$key"]+x}" ]; then
    TARGET_CATALOG_KEY_LINES["$key"]="$line"
    TARGET_CATALOG_KEY_ORDER+=("$key")
  else
    TARGET_CATALOG_KEY_LINES["$key"]+=",$line"
  fi
}

# 検証ルール 5 の報告: 2 行以上に現れたキーごとに 1 行、初出行の昇順(登録順)で出す。
# `lines=` はそのキーが現れた全行の物理行番号を初出行を含めて出現順に並べる(契約 validate-config.sh の stderr の lines= 規則)
# 戻り値: 0 … 重複なし / 1 … 重複あり(報告済み)
target_catalog_report_duplicates() {
  local key lines version type identifier rest duplicates=0
  if [ "${LC_ALL:-}" != C ]; then
    local LC_ALL=C
  fi
  for key in ${TARGET_CATALOG_KEY_ORDER[@]+"${TARGET_CATALOG_KEY_ORDER[@]}"}; do
    lines="${TARGET_CATALOG_KEY_LINES["$key"]}"
    case "$lines" in
      *,*) ;;
      *) continue ;;
    esac
    version="${key%%$'\n'*}"
    rest="${key#*$'\n'}"
    type="${rest%%$'\n'*}"
    identifier="${rest#*$'\n'}"
    # 値は任意入力(表示用に制御文字を可視表記にする。比較は元の値で行った)
    cli_field_safe_text "$version"
    version="$CLI_FIELD_SAFE_TEXT"
    cli_field_safe_text "$type"
    type="$CLI_FIELD_SAFE_TEXT"
    cli_field_safe_text "$identifier"
    identifier="$CLI_FIELD_SAFE_TEXT"
    target_catalog_emit "error: duplicate target catalog_version=$version target_type=$type target_identifier=$identifier lines=$lines"
    duplicates=$((duplicates + 1))
  done
  [ "$duplicates" -eq 0 ]
}

# 計算ルール「カタログ版の集計」と stdout の tables= / files= の登録: 現在の行の catalog_version を distinct 集合に加え、
# target_type が table / file なら対応する行数を数える(他の値は検証ルール 4 で報告済みのため数えない)。
# 空の catalog_version は集計しない(検証ルール 7 で報告済み)
target_catalog_register_aggregates() {
  local version="$TARGET_CATALOG_ROW_CATALOG_VERSION"
  if [ -n "$version" ] && [ -z "${TARGET_CATALOG_VERSION_SEEN["v$version"]+x}" ]; then
    TARGET_CATALOG_VERSION_SEEN["v$version"]=1
    TARGET_CATALOG_VERSION_LIST+=("$version")
  fi
  case "$TARGET_CATALOG_ROW_TARGET_TYPE" in
    "$TARGET_CATALOG_TYPE_TABLE") TARGET_CATALOG_TABLE_COUNT=$((TARGET_CATALOG_TABLE_COUNT + 1)) ;;
    "$TARGET_CATALOG_TYPE_FILE") TARGET_CATALOG_FILE_COUNT=$((TARGET_CATALOG_FILE_COUNT + 1)) ;;
  esac
}

# target_catalog_versions_summary の結果(stdout の catalog_versions= の値。初出順のカンマ区切り。行が無ければ空値表記 `-`)
TARGET_CATALOG_VERSIONS_SUMMARY="$TARGET_CATALOG_EMPTY_VALUE"

# 計算ルール「カタログ版の集計」: 登録済みの distinct 値を初出順にカンマ区切りで TARGET_CATALOG_VERSIONS_SUMMARY に載せる
# (usecase が stdout の catalog_versions= に出す)。連結は += で行う(全体を作り直す形は distinct 値の数の 2 乗の時間がかかる)
# shellcheck disable=SC2034
target_catalog_versions_summary() {
  local version joined="" separator=""
  for version in ${TARGET_CATALOG_VERSION_LIST[@]+"${TARGET_CATALOG_VERSION_LIST[@]}"}; do
    joined+="$separator$version"
    separator=","
  done
  if [ -z "$joined" ]; then
    TARGET_CATALOG_VERSIONS_SUMMARY="$TARGET_CATALOG_EMPTY_VALUE"
  else
    TARGET_CATALOG_VERSIONS_SUMMARY="$joined"
  fi
}

# --verbose の行ごとの補助出力(tier-final-crosscheck.md コマンド契約 `--verbose`: `info: checked target_identifier=...`)。
# 前提: validate_target_catalog_row を通過した行。
# 可視表記への置き換えはバイトごとの写像で、値の間の固定文字列は ASCII の表示文字なので、組み立てた 1 行にまとめて 1 回かける
# (行数に比例して呼ばれるため、関数呼び出しを重ねない)
# 引数: line
target_catalog_row_checked_line() {
  cli_field_safe_text "info: checked target_identifier=$TARGET_CATALOG_ROW_TARGET_IDENTIFIER catalog_version=$TARGET_CATALOG_ROW_CATALOG_VERSION target_type=$TARGET_CATALOG_ROW_TARGET_TYPE line=$1"
  target_catalog_emit "$CLI_FIELD_SAFE_TEXT"
}
