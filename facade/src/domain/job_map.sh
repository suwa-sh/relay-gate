#!/usr/bin/env bash
# domain: JobMap(エンティティ)/ JobMapRow(値オブジェクト)/ HangDetectLimit の検証表(純粋関数)。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/slot ごとのジョブマップを定義する/tier-facade.md
#       「設定契約(slot ジョブマップ CSV)」列の検証表 / ヘッダー検証 / JSON 配列の判定
# 文言の正本: _cross-cutting/api/cli-command-contract.yaml commands[validate-config.sh].stderr
# この層は I/O を持たない(CSV の読み込み・クォート解析は repository/job_map_repo.sh)。
# 違反行は `error:` / `warn:` / `info:` を 1 行ずつ job_map_emit で出す(全件収集。1 件目で止めない)。
# 既定では stdout に出し、呼び出し元(usecase)が stderr へ振り分ける。usecase が JOB_MAP_REPORT_SINK を
# JOB_MAP_REPORT_SINK_ARRAY にすると JOB_MAP_REPORT_LINES に溜める(内部障害のときに他の行を出さないため。
# config_input_rules.internal_failure)。戻り値は「error 行が 1 件以上あれば 1、無ければ 0」。
# 値は任意文字列を含むため、出力は echo ではなく printf の固定フォーマットで行う。
# 任意入力(セルの値・列名・パス)を行に埋め込むときは、制御文字を可視表記にする(domain/cli_field.sh の
# cli_field_safe_text。ANSI エスケープを出さず 1 行 1 事実を保つ)。
# 依存: domain/cli_field.sh(呼び出し元が先に source する)。bash 5.0 以上(連想配列。契約 conventions.runtime_prerequisites)

# 補助コマンド(sort)が失敗したときの戻り値(検証結果の 0 / 1 と区別する。値は conventions.exit_codes の実行エラーと同じ)
JOB_MAP_STATUS_COMMAND_FAILED=6

# 報告行の出力先: 空なら stdout へ 1 行ずつ出す。JOB_MAP_REPORT_SINK_ARRAY なら JOB_MAP_REPORT_LINES に溜める
JOB_MAP_REPORT_SINK_ARRAY="array"
JOB_MAP_REPORT_SINK=""
JOB_MAP_REPORT_LINES=()

# 報告行(error / warn / info / hint)を 1 行出す
# 引数: line
job_map_emit() {
  if [ "$JOB_MAP_REPORT_SINK" = "$JOB_MAP_REPORT_SINK_ARRAY" ]; then
    JOB_MAP_REPORT_LINES+=("$1")
  else
    printf '%s\n' "$1"
  fi
}

# 設定所有区分: slot ジョブマップが所有する 9 列(契約の列順。runner・mode・実装版・比較対象の列は置かない)
JOB_MAP_COLUMNS=(
  job_id
  host
  user
  work_dir
  script
  fixed_params
  hang_detect_limit_minutes
  credential_ref
  map_version
)
# 必須 5 列
JOB_MAP_REQUIRED_COLUMNS=(job_id work_dir script fixed_params hang_detect_limit_minutes)
# 対で置く任意列(両方あるか両方無いか)
JOB_MAP_COLUMN_HOST="host"
JOB_MAP_COLUMN_USER="user"

# 空値の表記(ui-design.md 出力フォーマット「空値」)
JOB_MAP_EMPTY_VALUE="-"
# 実行方式(--verbose の exec=)
JOB_MAP_EXEC_SSH="ssh"
JOB_MAP_EXEC_LOCAL="local"
# 列がヘッダーに無いことを示す位置
JOB_MAP_COLUMN_ABSENT=-1
# JSON の文字列に未エスケープで置けない制御文字 U+0001〜U+001F(8 進表記)。
# U+0000 を含む行と UTF-8 として不正な行は repository が CSV の解析前に拒否するため、ここには現れない
# (bash の文字列は U+0000 を保持できない)。U+007F と非 ASCII 文字は JSON の文字列にそのまま置けるため、そのまま取り込む。
JOB_MAP_JSON_CONTROL_CHARS=$'\001\002\003\004\005\006\007\010\011\012\013\014\015\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037'
# JSON の文字列の中でそのまま取り込めない文字(閉じ引用符・エスケープの開始・未エスケープで置けない制御文字)
JOB_MAP_JSON_STRING_SPECIAL_CHARS="\"\\$JOB_MAP_JSON_CONTROL_CHARS"
# JSON の文字列へ戻すときに前へバックスラッシュを付ける文字(閉じ引用符とバックスラッシュ)
JOB_MAP_JSON_BACKSLASH_ESCAPED_CHARS="\"\\"

# JSON 配列の解析とエスケープが 1 回に取り込む窓の大きさ(バイト)。結果には影響しない(長い値の処理時間だけに効く)
JOB_MAP_PARSE_WINDOW_BYTES=1024

# job_map_header_bind の結果: JOB_MAP_COLUMNS と同じ並びの「ヘッダー内の位置」(無い列は JOB_MAP_COLUMN_ABSENT)
JOB_MAP_COLUMN_INDEXES=()
# job_map_row_bind の結果(1 行分の JobMapRow)
JOB_MAP_ROW_JOB_ID=""
JOB_MAP_ROW_HOST=""
JOB_MAP_ROW_USER=""
JOB_MAP_ROW_WORK_DIR=""
JOB_MAP_ROW_SCRIPT=""
JOB_MAP_ROW_FIXED_PARAMS=""
JOB_MAP_ROW_HANG_DETECT_LIMIT_MINUTES=""
JOB_MAP_ROW_CREDENTIAL_REF=""
JOB_MAP_ROW_MAP_VERSION=""
# job_map_fixed_params_parse の結果(エスケープ解除後の固定引数)
JOB_MAP_FIXED_PARAMS=()
# JOB_MAP_FIXED_PARAMS が現在の JobMapRow(JOB_MAP_ROW_FIXED_PARAMS)の解析結果なら true
# (validate_job_map_row が解析した結果を job_map_row_resolved_line が再解析せずに使う。job_map_row_bind で false に戻す)
JOB_MAP_FIXED_PARAMS_BOUND=false
# job_map_json_escape_string の結果
JOB_MAP_JSON_ESCAPED=""
# job_map_fixed_params_json_build の結果(1 行の JSON 配列表記)
JOB_MAP_FIXED_PARAMS_JSON="[]"
# job_map_split_lines の結果
JOB_MAP_LINES=()
# job_map_version_summary の結果(stdout の map_version の値。元の値のまま。空値表記は `-`)
JOB_MAP_VERSION_SUMMARY="$JOB_MAP_EMPTY_VALUE"

# 列名が契約の 9 列に含まれるか
job_map_is_defined_column() {
  local name="$1" defined
  for defined in "${JOB_MAP_COLUMNS[@]}"; do
    if [ "$name" = "$defined" ]; then
      return 0
    fi
  done
  return 1
}

# 列名が必須 5 列に含まれるか
job_map_is_required_column() {
  local name="$1" required
  for required in "${JOB_MAP_REQUIRED_COLUMNS[@]}"; do
    if [ "$name" = "$required" ]; then
      return 0
    fi
  done
  return 1
}

# ヘッダーに列名があるか
# 引数: name header...
job_map_header_has_column() {
  local name="$1" column
  shift
  for column in "$@"; do
    if [ "$column" = "$name" ]; then
      return 0
    fi
  done
  return 1
}

# 条件「設定所有区分」/「ジョブマップ解決条件」/ 入力の守備範囲「ヘッダー列名の重複」: ヘッダーの列名を検証する。
#   - 必須 5 列がすべて存在し、host / user は両方あるか両方無いこと(違反は 1 行にまとめて missing=<col,...>)
#   - 契約の 9 列以外は `warn: unknown column`(impl_version を含む。拒否しない)
#   - 同じ列名が 2 回以上あれば `error: duplicate column column=<name>`(重複した列名ごとに 1 行。どちらの列を使うか決められない)
# 出力順: unknown column の warn → duplicate column の error → header mismatch の error
# 引数: path header...
validate_job_map_header() {
  local path="$1"
  shift
  local column missing="" has_host=false has_user=false errors=0
  if job_map_header_has_column "$JOB_MAP_COLUMN_HOST" "$@"; then
    has_host=true
  fi
  if job_map_header_has_column "$JOB_MAP_COLUMN_USER" "$@"; then
    has_user=true
  fi

  # 欠落列は契約の列順で並べる
  for column in "${JOB_MAP_COLUMNS[@]}"; do
    if job_map_header_has_column "$column" "$@"; then
      continue
    fi
    if job_map_is_required_column "$column" \
      || { [ "$column" = "$JOB_MAP_COLUMN_HOST" ] && [ "$has_user" = true ]; } \
      || { [ "$column" = "$JOB_MAP_COLUMN_USER" ] && [ "$has_host" = true ]; }; then
      missing="${missing:+$missing,}$column"
    fi
  done

  # パスと未知の列名は任意入力(表示用に制御文字を可視表記にする)。missing= は契約の列名だけ
  local shown_path
  cli_field_safe_text "$path"
  shown_path="$CLI_FIELD_SAFE_TEXT"
  for column in "$@"; do
    if ! job_map_is_defined_column "$column"; then
      cli_field_safe_text "$column"
      job_map_emit "warn: unknown column column=$CLI_FIELD_SAFE_TEXT path: $shown_path"
    fi
  done

  # 列名の出現回数を数え、2 回以上の列名を初出順に 1 行ずつ報告する(連想配列の添字は空の列名でも使えるよう接頭辞を付ける)
  local -A counts=() reported=()
  local key
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
      errors=$((errors + 1))
    fi
  done

  if [ -n "$missing" ]; then
    job_map_emit "error: job map header mismatch missing=$missing path: $shown_path"
    errors=$((errors + 1))
  fi
  [ "$errors" -eq 0 ]
}

# 列をヘッダー名で対応付ける(順序は問わない)。結果は JOB_MAP_COLUMN_INDEXES。
# 同じ列名が複数あるときは最初の列を使う。
# 引数: header...
job_map_header_bind() {
  local column name position found
  JOB_MAP_COLUMN_INDEXES=()
  for column in "${JOB_MAP_COLUMNS[@]}"; do
    position=0
    found="$JOB_MAP_COLUMN_ABSENT"
    for name in "$@"; do
      if [ "$name" = "$column" ]; then
        found="$position"
        break
      fi
      position=$((position + 1))
    done
    JOB_MAP_COLUMN_INDEXES+=("$found")
  done
}

# 1 行分のセルを JobMapRow(JOB_MAP_ROW_* )に載せる。ヘッダーに無い列の値は空。
# 前提: job_map_header_bind 済みで、セル数がヘッダーの列数と一致している(列数検証は usecase)
# 引数: cells...
job_map_row_bind() {
  local values=() index
  for index in "${JOB_MAP_COLUMN_INDEXES[@]}"; do
    if [ "$index" -eq "$JOB_MAP_COLUMN_ABSENT" ]; then
      values+=("")
    else
      values+=("${@:index+1:1}")
    fi
  done
  job_map_row_assign "${values[@]}"
}

# 全データ行のセルを連結した配列(repository の JOB_MAP_CELLS)から、offset で始まる 1 行分を JobMapRow に載せる。
# job_map_row_bind と同じ結果になる(行ごとにセルの配列を作り直さないため、行数に比例して呼ぶ usecase 向け)。
# 引数: cells_array_name offset
job_map_row_bind_at() {
  local -n job_map_cells_ref="$1"
  local offset="$2" values=() index
  for index in "${JOB_MAP_COLUMN_INDEXES[@]}"; do
    if [ "$index" -eq "$JOB_MAP_COLUMN_ABSENT" ]; then
      values+=("")
    else
      values+=("${job_map_cells_ref[offset + index]}")
    fi
  done
  job_map_row_assign "${values[@]}"
}

# JobMapRow の値を JOB_MAP_COLUMNS の並びで受けて JOB_MAP_ROW_* に載せる
# 引数: values...(9 個。JOB_MAP_COLUMNS の並び)
job_map_row_assign() {
  local values=("$@")
  # JOB_MAP_COLUMNS の並びと同じ
  JOB_MAP_ROW_JOB_ID="${values[0]}"
  JOB_MAP_ROW_HOST="${values[1]}"
  JOB_MAP_ROW_USER="${values[2]}"
  JOB_MAP_ROW_WORK_DIR="${values[3]}"
  JOB_MAP_ROW_SCRIPT="${values[4]}"
  JOB_MAP_ROW_FIXED_PARAMS="${values[5]}"
  JOB_MAP_ROW_HANG_DETECT_LIMIT_MINUTES="${values[6]}"
  JOB_MAP_ROW_CREDENTIAL_REF="${values[7]}"
  # map_version は usecase の「版の集計」が読む(このファイル内では参照しない)
  # shellcheck disable=SC2034
  JOB_MAP_ROW_MAP_VERSION="${values[8]}"
  JOB_MAP_FIXED_PARAMS_BOUND=false
}

# job_id は `^[A-Za-z0-9_-]+$`。
# 文字範囲は ASCII のバイトとして判定する(ロケールの照合順序で範囲にアクセント付き文字や全角数字が入らないようにする)
job_map_is_valid_job_id() {
  local LC_ALL=C
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]
}

# HangDetectLimit: hang_detect_limit_minutes は `^[0-9]+$`(0 = 検知対象外)
job_map_is_valid_hang_detect_limit() {
  local LC_ALL=C
  [[ "$1" =~ ^[0-9]+$ ]]
}

# 条件「認証情報の非保存」: 参照名(`^[A-Za-z0-9_.-]*$`)の形でない値(`/`・空白・非 ASCII 等、理由を問わない)と `BEGIN` を含む値は
# 同じ warn で受理する(契約 config_files <slot>-job-map.csv columns.credential_ref.on_format_violation)
job_map_credential_ref_looks_like_secret() {
  local value="$1" LC_ALL=C
  if [[ "$value" == */* ]] || [[ "$value" == *BEGIN* ]]; then
    return 0
  fi
  if [[ ! "$value" =~ ^[A-Za-z0-9_.-]*$ ]]; then
    return 0
  fi
  return 1
}

# 条件「ジョブマップ解決条件」: host / user の両方が無い・両方空の行はローカル実行(SSH しない)
# 引数: host user
job_map_row_is_local() {
  [ -z "$1" ] && [ -z "$2" ]
}

# 条件「引数連結規則」: fixed_params(クォート解除後のセル)を JSON 配列(文字列要素のみ)として解析する(jq 非依存)。
#   - 先頭 `[` 末尾 `]`、要素は `"..."` をカンマ区切り。空は `[]`
#   - 要素内のエスケープは `\"` `\\` `\/` `\n` `\t` だけを許可する
#   - ネストした配列・オブジェクト・数値・真偽値は非対応(違反)
# runner の解決関数と共有する(UC「ジョブマップで JOB_ID から実行先を解決する」)。
# 結果: JOB_MAP_FIXED_PARAMS(エスケープ解除後の要素)。戻り値: 0 … JSON 配列 / 1 … 違反
# 引数: text
job_map_fixed_params_parse() {
  # 典型的な値(エスケープ・空白・制御文字を含まない `["a","b"]`)は区切り `","` で分けるだけで状態機械と同じ結果になる。
  # 行数に比例して呼ばれるため、先にこの形を試す(受理する文法と結果は状態機械と同じ)
  if job_map_fixed_params_parse_plain "$1"; then
    return 0
  fi
  # bash の文字列操作は文字列全体の長さに比例する時間がかかるため、1 文字ずつ添字で取り出すと
  # 長さの 2 乗の時間がかかる。JOB_MAP_PARSE_WINDOW_BYTES ずつ rest(未処理の窓)へ取り込み、
  # 文字列内の通常の文字と文字列の外の空白は連続した分をまとめて取り込む。状態遷移は 1 文字ずつの解析と同じ
  local text="$1" tab=$'\t' rest="" offset=0 total
  local char run state="array_open" element=""
  # バイト単位で処理する(ロケールに依存させない)。UTF-8 の多バイト文字の各バイトは 0x80 以上で、
  # 区切りの ASCII 文字と重ならない(UTF-8 として不正な行は repository が解析前に拒否する。この関数はバイト列を変えない)
  local LC_ALL=C
  total="${#text}"
  JOB_MAP_FIXED_PARAMS=()
  while [ -n "$rest" ] || [ "$offset" -lt "$total" ]; do
    if [ -z "$rest" ]; then
      rest="${text:offset:JOB_MAP_PARSE_WINDOW_BYTES}"
      offset=$((offset + JOB_MAP_PARSE_WINDOW_BYTES))
    fi
    case "$state" in
      in_string)
        # 引用符・バックスラッシュ・制御文字の手前まで
        run="${rest%%["$JOB_MAP_JSON_STRING_SPECIAL_CHARS"]*}"
        element+="$run"
        rest="${rest:${#run}}"
        # 窓を使い切った(続きがあれば取り込む。無ければ閉じ引用符が無いまま終端に達した)
        if [ -z "$rest" ]; then
          continue
        fi
        char="${rest:0:1}"
        rest="${rest:1}"
        case "$char" in
          '"')
            JOB_MAP_FIXED_PARAMS+=("$element")
            element=""
            state="after_element"
            ;;
          \\) state="escape" ;;
          # JSON の文字列は未エスケープの制御文字を含められない(生のタブ・CR・ESC 等は違反)
          *) return 1 ;;
        esac
        ;;
      escape)
        char="${rest:0:1}"
        rest="${rest:1}"
        case "$char" in
          '"' | \\ | /) element+="$char" ;;
          n) element+=$'\n' ;;
          t) element+=$'\t' ;;
          *) return 1 ;;
        esac
        state="in_string"
        ;;
      *)
        # 文字列の外: JSON の空白(半角空白・タブ)は読み飛ばす
        run="${rest%%[! "$tab"]*}"
        rest="${rest:${#run}}"
        # 窓が空白だけだった(状態は変えない。続きがあれば取り込む)
        if [ -z "$rest" ]; then
          continue
        fi
        char="${rest:0:1}"
        rest="${rest:1}"
        case "$state/$char" in
          "array_open/[") state="first_element_or_close" ;;
          'first_element_or_close/"' | 'element/"') state="in_string" ;;
          "first_element_or_close/]" | "after_element/]") state="array_closed" ;;
          "after_element/,") state="element" ;;
          *) return 1 ;;
        esac
        ;;
    esac
  done
  [ "$state" = "array_closed" ]
}

# job_map_fixed_params_parse の早期判定: バックスラッシュ・未エスケープで置けない制御文字を含まず、`["` で始まり `"]` で終わり、
# 要素の区切り `","` を除くと二重引用符が残らない値だけを、`","` で分けて JOB_MAP_FIXED_PARAMS に載せる。
# この形の値は状態機械でも同じ要素になる(要素の内側に `"` も `\` も無く、要素の外に空白も無い)。
# 空の `[]` もここで受理する。戻り値: 0 … 解析した / 1 … この形ではない(状態機械で解析する)
# 引数: text
job_map_fixed_params_parse_plain() {
  local text="$1" inner rest separator='","'
  local LC_ALL=C
  JOB_MAP_FIXED_PARAMS=()
  if [ "$text" = "[]" ]; then
    return 0
  fi
  if [[ "$text" == *["\\$JOB_MAP_JSON_CONTROL_CHARS"]* ]] || [[ "$text" != '["'*'"]' ]] || [ "${#text}" -lt 4 ]; then
    return 1
  fi
  inner="${text:2:${#text}-4}"
  rest="${inner//"$separator"/}"
  if [[ "$rest" == *\"* ]]; then
    return 1
  fi
  rest="$inner"
  while [[ "$rest" == *"$separator"* ]]; do
    JOB_MAP_FIXED_PARAMS+=("${rest%%"$separator"*}")
    rest="${rest#*"$separator"}"
  done
  JOB_MAP_FIXED_PARAMS+=("$rest")
  return 0
}

# JOB_MAP_FIXED_PARAMS(解析後の配列)を 1 行の JSON 配列表記にする(--verbose の fixed_params=[...])
# 出力は必ず 1 行の JSON になる(生の制御文字を出さない)。
job_map_fixed_params_to_json() {
  job_map_fixed_params_json_build
  printf '%s\n' "$JOB_MAP_FIXED_PARAMS_JSON"
}

# JOB_MAP_FIXED_PARAMS を 1 行の JSON 配列表記にして JOB_MAP_FIXED_PARAMS_JSON に載せる(サブシェルを使わない)
job_map_fixed_params_json_build() {
  local element json="" separator=""
  local LC_ALL=C
  for element in ${JOB_MAP_FIXED_PARAMS[@]+"${JOB_MAP_FIXED_PARAMS[@]}"}; do
    # エスケープの要らない要素(通常の値)はそのまま置く(行数に比例して呼ばれるため)
    if [[ "$element" != *["$JOB_MAP_JSON_BACKSLASH_ESCAPED_CHARS$CLI_FIELD_SAFE_SPECIAL_CHARS"]* ]]; then
      json+="$separator\"$element\""
    else
      job_map_json_escape_string "$element"
      json+="$separator\"$JOB_MAP_JSON_ESCAPED\""
    fi
    separator=","
  done
  JOB_MAP_FIXED_PARAMS_JSON="[$json]"
}

# 文字列を JSON の文字列(引用符の内側)にエスケープする。結果は JOB_MAP_JSON_ESCAPED。
# `\` `"` 改行 タブは 2 文字のエスケープ、それ以外の制御文字(U+0001〜U+001F、U+007F、U+0080〜U+009F)は \u00XX にする。
# 制御文字の表記は任意入力の表示(cli_field_safe_text)と同じ関数で作る(表記を二重に持たない)。
# 引数: text
job_map_json_escape_string() {
  # 窓の大きさはテストが JOB_MAP_PARSE_WINDOW_BYTES で変えられるようにする(結果には影響しない)
  cli_field_escape_text "$1" "$JOB_MAP_JSON_BACKSLASH_ESCAPED_CHARS" "$JOB_MAP_PARSE_WINDOW_BYTES"
  JOB_MAP_JSON_ESCAPED="$CLI_FIELD_ESCAPED"
}

# 必須列の空セル: `error: <column> is empty line=N job_id=<v> value=`
# 引数: column line job_id(表示用に置き換え済みの値)
job_map_empty_cell_error() {
  job_map_emit "error: $1 is empty line=$2 job_id=$3 value="
}

# 列の値の違反: `error: <column> is <reason> line=N job_id=<v> value=<v>`(value は表示用に制御文字を可視表記にする)
# 引数: column_and_reason line job_id(表示用に置き換え済みの値) value(元の値)
job_map_value_error() {
  cli_field_safe_text "$4"
  job_map_emit "error: $1 line=$2 job_id=$3 value=$CLI_FIELD_SAFE_TEXT"
}

# 列ごとの検証(JOB_MAP_ROW_* を検証する。違反は全件出す)。
# 引数: line(行番号)
validate_job_map_row() {
  local line="$1" errors=0
  # 検証は元の値で行い、メッセージには表示用の値(制御文字を可視表記にしたもの)を出す
  local job_id
  cli_field_safe_text "$JOB_MAP_ROW_JOB_ID"
  job_id="$CLI_FIELD_SAFE_TEXT"

  # job_id
  if [ -z "$JOB_MAP_ROW_JOB_ID" ]; then
    job_map_empty_cell_error job_id "$line" "$job_id"
    errors=$((errors + 1))
  elif ! job_map_is_valid_job_id "$JOB_MAP_ROW_JOB_ID"; then
    job_map_value_error "job_id is invalid" "$line" "$job_id" "$JOB_MAP_ROW_JOB_ID"
    errors=$((errors + 1))
  fi

  # host / user: 両方空はローカル実行。片方だけ空は違反
  if [ -z "$JOB_MAP_ROW_HOST" ] && [ -n "$JOB_MAP_ROW_USER" ]; then
    job_map_empty_cell_error host "$line" "$job_id"
    errors=$((errors + 1))
  fi
  if [ -n "$JOB_MAP_ROW_HOST" ] && [ -z "$JOB_MAP_ROW_USER" ]; then
    job_map_empty_cell_error user "$line" "$job_id"
    errors=$((errors + 1))
  fi

  # work_dir / script: 非空のみ(実行先側のパス。Linux 形式 / Windows 形式 / 相対パスのどれでも受理し、形式は検査しない。
  # 存在確認もしない。relay-gate はパスを解釈も正規化もせず実行先へそのまま渡す)
  if [ -z "$JOB_MAP_ROW_WORK_DIR" ]; then
    job_map_empty_cell_error work_dir "$line" "$job_id"
    errors=$((errors + 1))
  fi
  if [ -z "$JOB_MAP_ROW_SCRIPT" ]; then
    job_map_empty_cell_error script "$line" "$job_id"
    errors=$((errors + 1))
  fi

  # fixed_params: JSON 配列(文字列要素のみ)
  if [ -z "$JOB_MAP_ROW_FIXED_PARAMS" ]; then
    job_map_empty_cell_error fixed_params "$line" "$job_id"
    errors=$((errors + 1))
  elif job_map_fixed_params_parse "$JOB_MAP_ROW_FIXED_PARAMS"; then
    JOB_MAP_FIXED_PARAMS_BOUND=true
  else
    job_map_value_error "fixed_params is not a json array of strings" "$line" "$job_id" "$JOB_MAP_ROW_FIXED_PARAMS"
    errors=$((errors + 1))
  fi

  # hang_detect_limit_minutes: 非負整数(検証は値域のみ。導入時の推奨 60 との差は違反にも警告にもしない)
  if [ -z "$JOB_MAP_ROW_HANG_DETECT_LIMIT_MINUTES" ]; then
    job_map_empty_cell_error hang_detect_limit_minutes "$line" "$job_id"
    errors=$((errors + 1))
  elif ! job_map_is_valid_hang_detect_limit "$JOB_MAP_ROW_HANG_DETECT_LIMIT_MINUTES"; then
    job_map_value_error "hang_detect_limit_minutes is not a non-negative integer" "$line" "$job_id" "$JOB_MAP_ROW_HANG_DETECT_LIMIT_MINUTES"
    errors=$((errors + 1))
  fi

  # credential_ref: 秘密らしい値は警告(拒否しない)。値そのものは出力しない
  if job_map_credential_ref_looks_like_secret "$JOB_MAP_ROW_CREDENTIAL_REF"; then
    job_map_emit "warn: credential_ref looks like a secret or path line=$line job_id=$job_id"
  fi

  [ "$errors" -eq 0 ]
}

# --verbose の解決結果 1 行(契約 validate-config.sh stderr の補助出力)。
# 前提: validate_job_map_row を通過した行(JOB_MAP_ROW_* が検証済み)
job_map_row_resolved_line() {
  local host="$JOB_MAP_ROW_HOST" user="$JOB_MAP_ROW_USER" exec_kind="$JOB_MAP_EXEC_SSH"
  if job_map_row_is_local "$host" "$user"; then
    host="$JOB_MAP_EMPTY_VALUE"
    user="$JOB_MAP_EMPTY_VALUE"
    exec_kind="$JOB_MAP_EXEC_LOCAL"
  fi
  # validate_job_map_row が解析済みなら再解析しない(同じ値の同じ結果)
  if [ "$JOB_MAP_FIXED_PARAMS_BOUND" != true ]; then
    job_map_fixed_params_parse "$JOB_MAP_ROW_FIXED_PARAMS" || return 1
  fi
  job_map_fixed_params_json_build
  # host / user / work_dir / script は任意の文字を含む(表示用に制御文字を可視表記にする)。
  # job_id と hang_detect_limit_minutes は検証済みの ASCII 文字だけだが、同じ経路で出す
  local job_id work_dir script limit
  cli_field_safe_text "$JOB_MAP_ROW_JOB_ID"
  job_id="$CLI_FIELD_SAFE_TEXT"
  cli_field_safe_text "$host"
  host="$CLI_FIELD_SAFE_TEXT"
  cli_field_safe_text "$user"
  user="$CLI_FIELD_SAFE_TEXT"
  cli_field_safe_text "$JOB_MAP_ROW_WORK_DIR"
  work_dir="$CLI_FIELD_SAFE_TEXT"
  cli_field_safe_text "$JOB_MAP_ROW_SCRIPT"
  script="$CLI_FIELD_SAFE_TEXT"
  cli_field_safe_text "$JOB_MAP_ROW_HANG_DETECT_LIMIT_MINUTES"
  limit="$CLI_FIELD_SAFE_TEXT"
  job_map_emit "info: resolved job_id=$job_id host=$host user=$user exec=$exec_kind work_dir=$work_dir script=$script fixed_params=$JOB_MAP_FIXED_PARAMS_JSON hang_detect_limit_minutes=$limit"
}

# 改行区切りの文字列を行の配列 JOB_MAP_LINES にする(空行は含めない)。
# ヒアストリングやプロセス置換を使わない(一時ファイルやサブプロセスの失敗で行を黙って失わないため)。
# 行は任意の文字(空白・タブ・glob 文字)を含むため、単語分割の区切りを改行だけにしてパス名展開を止める
# 引数: text
job_map_split_lines() {
  local text="$1" IFS=$'\n' noglob_was_set=false
  case "$-" in
    *f*) noglob_was_set=true ;;
  esac
  set -f
  # shellcheck disable=SC2206
  JOB_MAP_LINES=($text)
  if [ "$noglob_was_set" = false ]; then
    set +f
  fi
}

# 条件「ジョブマップ解決条件」: job_id はファイル内で一意。
# 重複した job_id ごとに 1 行で、初出行を含む全行番号を出現順に並べる(例: lines=2,5。契約 validate-config.sh stderr の lines= 規則)。
# 複数の job_id が重複するときは、1 回目の出現行が早い job_id から順に出す。
# 全組合せの比較(行数の 2 乗)を避けるため、job_id のバイト列で安定ソートして隣り合う同値をまとめる。
# 連想配列は使わない(job_id is invalid の値は任意の文字を含むため、添字にしない)。
# 引数: line job_id の組の繰り返し(line1 job_id1 line2 job_id2 ...。行番号の昇順)。空の job_id は対象外
validate_job_map_unique_job_ids() {
  local tab=$'\t' records=()
  while [ $# -ge 2 ]; do
    if [ -n "$2" ]; then
      # レコードは `行番号<TAB>job_id`(セルは改行を含まない。job_id 内のタブは 2 列目以降としてキーに含まれる)
      records+=("$1$tab$2")
    fi
    shift 2
  done
  if [ "${#records[@]}" -eq 0 ]; then
    return 0
  fi

  # sort の終了状態を確認できるようにコマンド置換で受ける(プロセス置換は終了状態を親へ伝えない)。
  # sort が失敗した・行数が合わないときは、重複なしとして扱わず JOB_MAP_STATUS_COMMAND_FAILED を返す。
  # sort 自身の stderr は出さない(internal_failure: 内部障害の報告は usecase の error 行 1 つだけ)
  local sorted record line job_id group_id="" group_lines="" group_size=0 reports=()
  if ! sorted="$(printf '%s\n' "${records[@]}" | LC_ALL=C sort -s -t "$tab" -k 2 2>/dev/null)"; then
    return "$JOB_MAP_STATUS_COMMAND_FAILED"
  fi
  job_map_split_lines "$sorted"
  if [ "${#JOB_MAP_LINES[@]}" -ne "${#records[@]}" ]; then
    return "$JOB_MAP_STATUS_COMMAND_FAILED"
  fi
  # 隣り合う同値をまとめる方式は並びに依存するため、job_id がバイト列の昇順に並んでいることも確かめる
  # (並べ替えずに行数だけ合う出力を、重複なしとして受理しない)
  local LC_ALL=C
  for record in "${JOB_MAP_LINES[@]}"; do
    line="${record%%"$tab"*}"
    job_id="${record#*"$tab"}"
    if [ "$group_size" -gt 0 ] && [[ "$job_id" < "$group_id" ]]; then
      return "$JOB_MAP_STATUS_COMMAND_FAILED"
    fi
    if [ "$group_size" -gt 0 ] && [ "$job_id" = "$group_id" ]; then
      group_lines="$group_lines,$line"
      group_size=$((group_size + 1))
      continue
    fi
    if [ "$group_size" -gt 1 ]; then
      # job_id is invalid の値は任意の文字を含む(表示用に制御文字を可視表記にする。比較は元の値で行う)
      cli_field_safe_text "$group_id"
      reports+=("${group_lines%%,*}${tab}error: duplicate job_id job_id=$CLI_FIELD_SAFE_TEXT lines=$group_lines")
    fi
    group_id="$job_id"
    group_lines="$line"
    group_size=1
  done
  if [ "$group_size" -gt 1 ]; then
    cli_field_safe_text "$group_id"
    reports+=("${group_lines%%,*}${tab}error: duplicate job_id job_id=$CLI_FIELD_SAFE_TEXT lines=$group_lines")
  fi

  if [ "${#reports[@]}" -eq 0 ]; then
    return 0
  fi
  # 1 回目の出現行の昇順に並べ直し、並べ替え用の先頭列を外して出す
  if ! sorted="$(printf '%s\n' "${reports[@]}" | LC_ALL=C sort -s -n -t "$tab" -k 1,1 2>/dev/null)"; then
    return "$JOB_MAP_STATUS_COMMAND_FAILED"
  fi
  job_map_split_lines "$sorted"
  if [ "${#JOB_MAP_LINES[@]}" -ne "${#reports[@]}" ]; then
    return "$JOB_MAP_STATUS_COMMAND_FAILED"
  fi
  for record in "${JOB_MAP_LINES[@]}"; do
    job_map_emit "${record#*"$tab"}"
  done
  return 1
}

# 計算ルール「版の集計」: map_version 列の全行の distinct 値(初出順。空の行も 1 つの値として数える)。
# 集計値は JOB_MAP_VERSION_SUMMARY(複数あればカンマ区切り。空の値は空値表記 `-`。行が無い・全行空なら `-`)。
# 出力先が stdout のときは 1 行目に集計値を出す。複数あれば `warn: mixed map_version` を job_map_emit で出す。
# distinct 値の集合は連想配列で持ち、行数に比例する時間で集計する(NFR B.1.1.2 の最悪条件 = 全行の版が相違)。
# 引数: 各行の map_version...(列が無いファイルは全行空で渡される)
job_map_version_summary() {
  local version joined="" shown previous="" first=true distinct_count=0
  # 連想配列の添字は空の値でも使えるよう接頭辞を付ける
  local -A seen=()
  for version in "$@"; do
    # 直前の行と同じ値は既知(1 ファイル 1 版が通常で、連想配列の参照を省く)
    if [ "$first" = false ] && [ "$version" = "$previous" ]; then
      continue
    fi
    first=false
    previous="$version"
    if [ -z "${seen["v$version"]+x}" ]; then
      seen["v$version"]=1
      distinct_count=$((distinct_count + 1))
      shown="${version:-$JOB_MAP_EMPTY_VALUE}"
      joined="${joined:+$joined,}$shown"
    fi
  done
  if [ "$distinct_count" -eq 0 ]; then
    JOB_MAP_VERSION_SUMMARY="$JOB_MAP_EMPTY_VALUE"
  else
    JOB_MAP_VERSION_SUMMARY="$joined"
  fi
  # 集計値は元の値(usecase が cli_field_line で表示用に置き換える。セルは改行を含まないため 1 行に収まる)。
  # warn 行はここで表示用に制御文字を可視表記にする
  if [ "$JOB_MAP_REPORT_SINK" != "$JOB_MAP_REPORT_SINK_ARRAY" ]; then
    printf '%s\n' "$JOB_MAP_VERSION_SUMMARY"
  fi
  if [ "$distinct_count" -gt 1 ]; then
    cli_field_safe_text "$joined"
    job_map_emit "warn: mixed map_version values=$CLI_FIELD_SAFE_TEXT"
  fi
  return 0
}
