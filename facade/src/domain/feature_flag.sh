#!/usr/bin/env bash
# domain: FeatureFlag(値オブジェクト)/ SlotRunnerAssignment の検証表と運用モード名の導出。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/tier-facade.md
#       「設定契約(feature flag env)」「組合せ検証」「運用モード表」
# 文言の正本: _cross-cutting/api/cli-command-contract.yaml config_files.feature-flag.env.error_messages
# この層は I/O(env ファイル読み込み・runner --help の起動)を行わない。実体パスの存在・実行可否だけは
# 仕様が domain の責務としているため `test` で判定する。
# 違反行は stdout に `error:` / `hint:` / `warn:` 1 行ずつ出し(全件収集。1 件目で止めない)、
# 呼び出し元(usecase)が stderr へ振り分ける。戻り値は「error 行が 1 件以上あれば 1、無ければ 0」。
# 値は任意文字列(実装版 `-n` 等)を含むため、出力は echo ではなく printf の固定フォーマットで行う。
# 違反行の `key=` / `value=` / `path:` / `path=` に埋め込む任意入力(キー名・値・パス)は、制御文字を可視表記にする
# (domain/cli_field.sh の cli_field_safe_text。tier-facade.md「出力契約」stderr / ui-design.md「制御文字の表記」)。
# 依存: domain/cli_field.sh(未 source なら自分で source する。単体でも source できるようにするため)
# shellcheck source-path=SCRIPTDIR

if ! declare -F cli_field_safe_text >/dev/null; then
  # shellcheck source=cli_field.sh
  source "${BASH_SOURCE[0]%/*}/cli_field.sh"
fi

# 設定所有区分: feature flag が所有するキー(契約 config_files.feature-flag.env.keys)。
# 9 キー(元の方針資料の設定契約と同じ。設定版は持たない)と、slot ジョブマップの場所を書く任意の 2 キー。
# 値を取り込むのはこのキーだけで、このキーは未知キーではない(任意の 2 キーは、無くても値が空でも違反にも warn にもしない)
FEATURE_FLAG_DEFINED_KEYS=(
  BLUE_MODE
  GREEN_MODE
  RAPID_CROSSCHECK_MODE
  BLUE_IMPL
  GREEN_IMPL
  BLUE_RUNNER
  GREEN_RUNNER
  RAPID_CROSSCHECK_RUNNER
  RAPID_CROSSCHECK_WORKER
  BLUE_JOB_MAP_CSV
  GREEN_JOB_MAP_CSV
)

# slot 実行モード / 速報クロスチェックモードの列挙(3 値)
FEATURE_FLAG_MODE_FOREGROUND="foreground"
FEATURE_FLAG_MODE_BACKGROUND="background"
FEATURE_FLAG_MODE_OFF="off"
FEATURE_FLAG_MODE_HINT="hint: use foreground, background or off"

# 確報クロスチェック非起動: キー名が `FINAL_` で始まる全キーは feature flag に置けない
# (接頭辞判定・大文字小文字を区別。キー名の列挙ではない。未知キー warn より先に判定し、同じキーに warn は出さない)。
# 範囲の正本: cli-command-contract.yaml config_files.feature-flag.env.validation_rules
FEATURE_FLAG_FORBIDDEN_KEY_PREFIX="FINAL_"

# 運用モード名(英字コード。RDRA バリエーション「運用モード」)
OPERATION_MODE_PARALLEL="parallel"
OPERATION_MODE_GREEN_ONLY="green_only"
OPERATION_MODE_NEXT_GEN_PARALLEL="next_gen_parallel"
OPERATION_MODE_CUSTOM="custom"

# 空値の表記(ui-design.md 出力フォーマット「空値」)
FEATURE_FLAG_EMPTY_VALUE="-"

# 報告行(`warn:` / `error:` / `hint:`)の出し先。既定は stdout(1 行ずつ)。
# 行数に比例する件数の行を受け取る呼び出し元(usecase)は配列に溜める(サブシェルで受けて行に分け直すと、数十 MB の報告で
# 秒単位の時間がかかる)。配列に溜めるときは、呼び出し元が feature_flag_reset_report_lines で初期化し、呼び出しの後に出し先を戻して、
# feature_flag_flush_report_lines で出す(FEATURE_FLAG_REPORT_LINES へ行を足してから出してもよい)
FEATURE_FLAG_REPORT_SINK_STDOUT="stdout"
FEATURE_FLAG_REPORT_SINK_ARRAY="array"
FEATURE_FLAG_REPORT_SINK="$FEATURE_FLAG_REPORT_SINK_STDOUT"
FEATURE_FLAG_REPORT_LINES=()

# 報告行を出す(1 引数 1 行)
feature_flag_emit() {
  if [ "$FEATURE_FLAG_REPORT_SINK" = "$FEATURE_FLAG_REPORT_SINK_ARRAY" ]; then
    FEATURE_FLAG_REPORT_LINES+=("$@")
  else
    printf '%s\n' "$@"
  fi
}

# 値を埋め込む報告行のうち、配列に溜めるときに値の表示を後回しにする大きさ(値の合計のバイト数)。
# 値の可視表記は元の最大 6 倍になる。数 MB の値を埋め込んだ行を組み立てて配列に溜めると、行を写すたびに長さに比例する時間が
# かかるため、大きな値は元の値のまま控えておき、出すときに可視表記を直接出す。出力のバイト列は変わらない
FEATURE_FLAG_REPORT_DEFERRED_MIN_BYTES=4096
# 値の表示を後回しにした報告行の、埋め込む値(添字は FEATURE_FLAG_REPORT_LINES と同じ。その行の FEATURE_FLAG_REPORT_LINES は値の前までの文字列)
#   FEATURE_FLAG_REPORT_VALUE_1 … 1 つ目の値 / FEATURE_FLAG_REPORT_MIDDLE … 2 つ目の値の前の文字列 / FEATURE_FLAG_REPORT_VALUE_2 … 2 つ目の値
FEATURE_FLAG_REPORT_VALUE_1=()
FEATURE_FLAG_REPORT_MIDDLE=()
FEATURE_FLAG_REPORT_VALUE_2=()

# 値の表示(空なら空値表記 `-`、それ以外は制御文字を可視表記にした値)を、改行を付けずに stdout へ出す
# 引数: value
feature_flag_print_shown_value() {
  if [ -n "${1:-}" ]; then
    cli_field_print_safe_text "$1"
  else
    printf '%s' "$FEATURE_FLAG_EMPTY_VALUE"
  fi
}

# 値を 1 つか 2 つ埋め込む報告行を出す: `<prefix><値 1 の表示>`、または `<prefix><値 1 の表示><middle><値 2 の表示>`。
# 値の表示は feature_flag_print_shown_value と同じ(空なら `-`)
# 引数: prefix value [middle value2]
feature_flag_emit_value_line() {
  local total="${#2}" index
  if [ $# -ge 4 ]; then
    total=$((total + ${#4}))
  fi
  if [ "$FEATURE_FLAG_REPORT_SINK" != "$FEATURE_FLAG_REPORT_SINK_ARRAY" ]; then
    printf '%s' "$1"
    feature_flag_print_shown_value "$2"
    if [ $# -ge 4 ]; then
      printf '%s' "$3"
      feature_flag_print_shown_value "$4"
    fi
    printf '\n'
  elif [ "$total" -lt "$FEATURE_FLAG_REPORT_DEFERRED_MIN_BYTES" ]; then
    local line
    feature_flag_shown_value "$2"
    line="$1$FEATURE_FLAG_SHOWN_VALUE"
    if [ $# -ge 4 ]; then
      feature_flag_shown_value "$4"
      line+="$3$FEATURE_FLAG_SHOWN_VALUE"
    fi
    FEATURE_FLAG_REPORT_LINES+=("$line")
  else
    index="${#FEATURE_FLAG_REPORT_LINES[@]}"
    FEATURE_FLAG_REPORT_LINES+=("$1")
    FEATURE_FLAG_REPORT_VALUE_1[index]="$2"
    if [ $# -ge 4 ]; then
      FEATURE_FLAG_REPORT_MIDDLE[index]="$3"
      FEATURE_FLAG_REPORT_VALUE_2[index]="$4"
    fi
  fi
}

# 配列に溜めた報告行を、溜めた順に stdout へ出して、配列を空にする(値の表示を後回しにした行は、ここで値の表示を付ける)
feature_flag_flush_report_lines() {
  local index
  for index in ${FEATURE_FLAG_REPORT_LINES[@]+"${!FEATURE_FLAG_REPORT_LINES[@]}"}; do
    if [ -z "${FEATURE_FLAG_REPORT_VALUE_1[index]+x}" ]; then
      printf '%s\n' "${FEATURE_FLAG_REPORT_LINES[index]}"
      continue
    fi
    printf '%s' "${FEATURE_FLAG_REPORT_LINES[index]}"
    feature_flag_print_shown_value "${FEATURE_FLAG_REPORT_VALUE_1[index]}"
    if [ -n "${FEATURE_FLAG_REPORT_MIDDLE[index]+x}" ]; then
      printf '%s' "${FEATURE_FLAG_REPORT_MIDDLE[index]}"
      feature_flag_print_shown_value "${FEATURE_FLAG_REPORT_VALUE_2[index]}"
    fi
    printf '\n'
  done
  feature_flag_reset_report_lines
}

# 配列に溜めた報告行(検証表の error 行と hint。error_order の順)のうち、最初の違反の error 行と、その次の行が hint ならその hint だけを
# stdout へ出して、配列を空にする(契約 commands の facade.sh の config_violation_report。2 つ目以降の違反の行は出さない)。
# 値の表示を後回しにした行は、feature_flag_flush_report_lines と同じく、ここで値の表示を付ける
feature_flag_flush_first_violation() {
  local index
  for index in 0 1; do
    if [ "$index" -ge "${#FEATURE_FLAG_REPORT_LINES[@]}" ]; then
      break
    fi
    if [ "$index" -eq 1 ] && { [ -n "${FEATURE_FLAG_REPORT_VALUE_1[index]+x}" ] \
      || [ "${FEATURE_FLAG_REPORT_LINES[index]:0:5}" != "hint:" ]; }; then
      break
    fi
    printf '%s' "${FEATURE_FLAG_REPORT_LINES[index]}"
    if [ -n "${FEATURE_FLAG_REPORT_VALUE_1[index]+x}" ]; then
      feature_flag_print_shown_value "${FEATURE_FLAG_REPORT_VALUE_1[index]}"
      if [ -n "${FEATURE_FLAG_REPORT_MIDDLE[index]+x}" ]; then
        printf '%s' "${FEATURE_FLAG_REPORT_MIDDLE[index]}"
        feature_flag_print_shown_value "${FEATURE_FLAG_REPORT_VALUE_2[index]}"
      fi
    fi
    printf '\n'
  done
  feature_flag_reset_report_lines
}

# 配列に溜めた報告行を捨てる
feature_flag_reset_report_lines() {
  FEATURE_FLAG_REPORT_LINES=()
  FEATURE_FLAG_REPORT_VALUE_1=()
  FEATURE_FLAG_REPORT_MIDDLE=()
  FEATURE_FLAG_REPORT_VALUE_2=()
}

# feature flag が所有するキーのうち最も長いキー名の長さ(これより長いキーは所有するキーのどれでもない)
FEATURE_FLAG_DEFINED_KEY_MAX_LENGTH=0
feature_flag_measure_defined_keys() {
  local defined
  for defined in "${FEATURE_FLAG_DEFINED_KEYS[@]}"; do
    if [ "${#defined}" -gt "$FEATURE_FLAG_DEFINED_KEY_MAX_LENGTH" ]; then
      FEATURE_FLAG_DEFINED_KEY_MAX_LENGTH="${#defined}"
    fi
  done
}
feature_flag_measure_defined_keys

# feature flag が所有するキー(9 キー + 任意の 2 キー)に含まれるか
feature_flag_is_defined_key() {
  # 長いキーは比べる前に除く(数 MB のキーをキーの数だけ比べない。行数に比例して呼ばれる)
  if [ "${#1}" -gt "$FEATURE_FLAG_DEFINED_KEY_MAX_LENGTH" ]; then
    return 1
  fi
  local key="$1" defined
  for defined in "${FEATURE_FLAG_DEFINED_KEYS[@]}"; do
    if [ "$key" = "$defined" ]; then
      return 0
    fi
  done
  return 1
}

# mode 値が列挙(foreground / background / off)に含まれるか
feature_flag_is_valid_mode() {
  case "$1" in
    "$FEATURE_FLAG_MODE_FOREGROUND" | "$FEATURE_FLAG_MODE_BACKGROUND" | "$FEATURE_FLAG_MODE_OFF") return 0 ;;
    *) return 1 ;;
  esac
}

# 速報クロスチェック有効判定 / slot の検証対象判定: 「off か off 以外か」で判定する
feature_flag_mode_is_active() {
  [ "$1" != "$FEATURE_FLAG_MODE_OFF" ]
}

# 計算ルール「foreground 数」: BLUE_MODE / GREEN_MODE のうち foreground の個数
count_foreground() {
  local count=0 mode
  for mode in "$@"; do
    if [ "$mode" = "$FEATURE_FLAG_MODE_FOREGROUND" ]; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

# 計算ルール「運用モード名」: (BLUE_MODE, GREEN_MODE, RAPID_CROSSCHECK_MODE) → operation_mode。結果は FEATURE_FLAG_OPERATION_MODE
# (サブシェルを使わずグローバルで返す。大きな設定を読み込んだ後のサブシェルの起動は、プロセスの複製に時間がかかる)
FEATURE_FLAG_OPERATION_MODE=""
feature_flag_resolve_operation_mode() {
  case "$1/$2/$3" in
    "$FEATURE_FLAG_MODE_FOREGROUND/$FEATURE_FLAG_MODE_BACKGROUND/$FEATURE_FLAG_MODE_BACKGROUND")
      FEATURE_FLAG_OPERATION_MODE="$OPERATION_MODE_PARALLEL"
      ;;
    "$FEATURE_FLAG_MODE_OFF/$FEATURE_FLAG_MODE_FOREGROUND/$FEATURE_FLAG_MODE_OFF")
      FEATURE_FLAG_OPERATION_MODE="$OPERATION_MODE_GREEN_ONLY"
      ;;
    "$FEATURE_FLAG_MODE_BACKGROUND/$FEATURE_FLAG_MODE_FOREGROUND/$FEATURE_FLAG_MODE_BACKGROUND")
      FEATURE_FLAG_OPERATION_MODE="$OPERATION_MODE_NEXT_GEN_PARALLEL"
      ;;
    *)
      FEATURE_FLAG_OPERATION_MODE="$OPERATION_MODE_CUSTOM"
      ;;
  esac
}

# 運用モード名を stdout に出す
derive_operation_mode() {
  feature_flag_resolve_operation_mode "$1" "$2" "$3"
  printf '%s\n' "$FEATURE_FLAG_OPERATION_MODE"
}

# 値が空なら空値表記 `-` に置き換える
feature_flag_display_value() {
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$FEATURE_FLAG_EMPTY_VALUE"
  fi
}

# 違反行に埋め込む mode 値の表示(空なら空値表記 `-`、それ以外は制御文字を可視表記にした値)。結果は FEATURE_FLAG_SHOWN_VALUE
# (サブシェルを使わずグローバルで返す)
FEATURE_FLAG_SHOWN_VALUE=""
feature_flag_shown_value() {
  if [ -n "${1:-}" ]; then
    cli_field_safe_text "$1"
    FEATURE_FLAG_SHOWN_VALUE="$CLI_FIELD_SAFE_TEXT"
  else
    FEATURE_FLAG_SHOWN_VALUE="$FEATURE_FLAG_EMPTY_VALUE"
  fi
}

# mode キー 1 つの検証: 必須(欠落・空)→ 列挙
# 値は数 MB になりうるため(行の長さに上限は無い)、変数へ写さずに引数のまま使う(1 回写すたびに値の長さに比例する時間がかかる)
# 引数: key path(表示用に置き換え済みのパス) value
validate_feature_flag_mode_key() {
  if [ -z "$3" ]; then
    feature_flag_emit "error: option required option=$1 path: $2"
    return 1
  fi
  if ! feature_flag_is_valid_mode "$3"; then
    feature_flag_emit_value_line "error: invalid value key=$1 value=" "$3"
    feature_flag_emit "$FEATURE_FLAG_MODE_HINT"
    return 1
  fi
  return 0
}

# 非空文字列キー(<SLOT>_IMPL)の検証: 欠落・空は option required
# 引数: key path(表示用に置き換え済みのパス) value
validate_feature_flag_required_value() {
  if [ -z "$3" ]; then
    feature_flag_emit "error: option required option=$1 path: $2"
    return 1
  fi
  return 0
}

# ---- runner / worker の実体パスの解決(契約 config_files.feature-flag.env.runner_path_resolution) ----
# BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER の 4 キーは絶対パスと相対パスのどちらも受け付ける。
# 相対パスの基準は設定ファイルのあるディレクトリ(プロセスの作業ディレクトリではない)。字面だけで決め、外部コマンドを使わない
# (`.`・`..`・連続する `/` を畳まない。シンボリックリンクを辿らない。`~`・環境変数・コマンド置換を展開しない)。
# 検証コマンドと実行時の読み手(facade.sh など)が同じ関数を使う(設定ファイルのパスの文字列が同じなら同じ解決後のパスになる)

# 解決の対象の 4 キーと、そのキーを検査するかを決める mode のキー(同じ添字)
FEATURE_FLAG_RUNNER_PATH_KEYS=(BLUE_RUNNER GREEN_RUNNER RAPID_CROSSCHECK_RUNNER RAPID_CROSSCHECK_WORKER)
FEATURE_FLAG_RUNNER_PATH_MODE_KEYS=(BLUE_MODE GREEN_MODE RAPID_CROSSCHECK_MODE RAPID_CROSSCHECK_MODE)

# feature_flag_resolve_runner_base_dir / feature_flag_resolve_runner_path の結果(サブシェルを使わずグローバルで返す)
FEATURE_FLAG_RUNNER_BASE_DIR=""
FEATURE_FLAG_RESOLVED_RUNNER_PATH=""

# 基準のディレクトリ(base_dir の 2〜4)を FEATURE_FLAG_RUNNER_BASE_DIR に載せる。
# 設定ファイルのパスが `/` で始まらなければ 作業ディレクトリ + `/` + パス で絶対パスにし(作業ディレクトリが `/` のときは `/` + パス)、
# 最後の `/` より前の部分を基準にする(最後の `/` が先頭の 1 文字のとき、基準は `/`)
# 引数: config_path [working_dir](省略時はシェルの $PWD。論理パスで、シンボリックリンクを辿った物理パスにしない)
feature_flag_resolve_runner_base_dir() {
  local config_path="$1" working_dir="${2-$PWD}"
  if [ "${config_path:0:1}" != / ]; then
    if [ "$working_dir" = / ]; then
      config_path="/$config_path"
    else
      config_path="$working_dir/$config_path"
    fi
  fi
  FEATURE_FLAG_RUNNER_BASE_DIR="${config_path%/*}"
  if [ -z "$FEATURE_FLAG_RUNNER_BASE_DIR" ]; then
    FEATURE_FLAG_RUNNER_BASE_DIR=/
  fi
}

# 解決後のパス(resolved_path)を FEATURE_FLAG_RESOLVED_RUNNER_PATH に載せる。
# 絶対パスの値はそのまま。相対パスの値は 基準のディレクトリ + `/` + 値(基準が `/` のときは `/` + 値)。
# 空の値は解決しない(空のまま。必須キーの欠落・空として扱う)。先頭の 1 文字だけを見る(値の全体をパターンに照合しない)
# 引数: base_dir value
feature_flag_resolve_runner_path() {
  if [ -z "$2" ] || [ "${2:0:1}" = / ]; then
    FEATURE_FLAG_RESOLVED_RUNNER_PATH="$2"
  elif [ "$1" = / ]; then
    FEATURE_FLAG_RESOLVED_RUNNER_PATH="/$2"
  else
    FEATURE_FLAG_RESOLVED_RUNNER_PATH="$1/$2"
  fi
}

# 4 キーのグローバル変数を解決後のパスに置き換える。これ以降の検査・問い合わせ・起動・表示は、置き換えた値を使う。
# 置き換えるのは検査するキーだけ(mode が off の slot、RAPID_CROSSCHECK_MODE=off のキーは解決しない)。空・未設定の値は変えない。
# 解決後のパスは `/` で始まるため、2 回呼んでも結果は変わらない
# 入力(グローバル): FEATURE_FLAG_PATH(設定ファイルのパス。渡された字面のまま)と mode 3 キー・対象の 4 キー
# 引数: [working_dir](省略時はシェルの $PWD)
feature_flag_resolve_runner_paths() {
  local index key mode_key
  feature_flag_resolve_runner_base_dir "${FEATURE_FLAG_PATH:-}" "${1-$PWD}"
  for index in "${!FEATURE_FLAG_RUNNER_PATH_KEYS[@]}"; do
    key="${FEATURE_FLAG_RUNNER_PATH_KEYS[index]}"
    mode_key="${FEATURE_FLAG_RUNNER_PATH_MODE_KEYS[index]}"
    if [ -z "${!key:-}" ] || ! feature_flag_mode_is_active "${!mode_key:-}"; then
      continue
    fi
    feature_flag_resolve_runner_path "$FEATURE_FLAG_RUNNER_BASE_DIR" "${!key}"
    printf -v "$key" '%s' "$FEATURE_FLAG_RESOLVED_RUNNER_PATH"
  done
  FEATURE_FLAG_RESOLVED_RUNNER_PATH=""
}

# ---- slot ジョブマップの場所(契約 config_files.feature-flag.env.job_map_location) ----
# 任意の 2 キー BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV の値からパスを決める規則は、runner / worker の 4 キーと同じ 1 つの規則
# (上の feature_flag_resolve_runner_base_dir / feature_flag_resolve_runner_path)を使い、ここには規則を持たない。
# 検証コマンドと、ジョブマップの場所を runner へ渡す実行時の読み手(facade.sh)が同じ関数を使う

# slot の名前と、その slot の場所のキー・mode のキー(同じ添字)
FEATURE_FLAG_JOB_MAP_SLOTS=(blue green)
FEATURE_FLAG_JOB_MAP_KEYS=(BLUE_JOB_MAP_CSV GREEN_JOB_MAP_CSV)
FEATURE_FLAG_JOB_MAP_MODE_KEYS=(BLUE_MODE GREEN_MODE)
# 既定の場所のファイル名の、slot の名前より後ろの部分(`<slot>-job-map.csv`)
FEATURE_FLAG_JOB_MAP_DEFAULT_SUFFIX="-job-map.csv"

# feature_flag_resolve_job_map_locations の結果(決めた場所。off の slot は決めないため空)
FEATURE_FLAG_BLUE_JOB_MAP=""
FEATURE_FLAG_GREEN_JOB_MAP=""

# slot ごとのジョブマップの場所を決めて FEATURE_FLAG_BLUE_JOB_MAP / FEATURE_FLAG_GREEN_JOB_MAP に載せる。
#   キーがあり値が空でない … 値を解決したパス(絶対パスはそのまま。相対パスは設定ファイルのあるディレクトリが基準)
#   キーが無い・値が空     … <config_dir>/<slot>-job-map.csv(この文字列のまま。絶対パスへの変換も正規化もしない)
#   mode が off の slot    … 解決しない(結果は空)
# 2 キーのグローバル変数は書き換えない(既定の場所は相対パスでもそのまま使うため、解決後の値と区別できる別の変数で返す)
# 入力(グローバル): FEATURE_FLAG_PATH と BLUE_MODE / GREEN_MODE / BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV(未設定可)
# 引数: config_dir(RELAY_GATE_CONFIG_DIR。既定を適用した後の値) [working_dir](省略時はシェルの $PWD)
feature_flag_resolve_job_map_locations() {
  local config_dir="$1" index key mode_key location
  feature_flag_resolve_runner_base_dir "${FEATURE_FLAG_PATH:-}" "${2-$PWD}"
  for index in "${!FEATURE_FLAG_JOB_MAP_KEYS[@]}"; do
    key="${FEATURE_FLAG_JOB_MAP_KEYS[index]}"
    mode_key="${FEATURE_FLAG_JOB_MAP_MODE_KEYS[index]}"
    if ! feature_flag_mode_is_active "${!mode_key:-}"; then
      location=""
    elif [ -z "${!key:-}" ]; then
      location="$config_dir/${FEATURE_FLAG_JOB_MAP_SLOTS[index]}$FEATURE_FLAG_JOB_MAP_DEFAULT_SUFFIX"
    else
      feature_flag_resolve_runner_path "$FEATURE_FLAG_RUNNER_BASE_DIR" "${!key}"
      location="$FEATURE_FLAG_RESOLVED_RUNNER_PATH"
    fi
    # shellcheck disable=SC2034  # 結果のグローバル(usecase と実行時の読み手が読む)
    if [ "$index" -eq 0 ]; then
      FEATURE_FLAG_BLUE_JOB_MAP="$location"
    else
      FEATURE_FLAG_GREEN_JOB_MAP="$location"
    fi
  done
  FEATURE_FLAG_RESOLVED_RUNNER_PATH=""
}

# 実体パスキー(<SLOT>_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)の検証:
# 欠落・空 → 存在かつ実行可能(最初に当たった 1 つだけを出す。契約 error_order.per_key)。
# 値は解決後のパスで受け取る(feature_flag_resolve_runner_paths の後)。相対パスであることを理由にした error 行は出さない
# 引数: key path(表示用に置き換え済みの設定ファイルのパス) value(解決後のパス)
validate_feature_flag_executable_path() {
  if [ -z "$3" ]; then
    feature_flag_emit "error: option required option=$1 path: $2"
    return 1
  fi
  if [ ! -f "$3" ] || [ ! -x "$3" ]; then
    feature_flag_emit_value_line "error: file not executable key=$1 path=" "$3"
    return 1
  fi
  return 0
}

# 実体パス(解決後のパス)が検証を通過済み(存在・実行可能)か。runner --help 問い合わせの前提判定に使う。
# 解決していない相対パスは通さない(作業ディレクトリを基準にした実体を起動しない)
feature_flag_path_is_executable() {
  [ "${1:0:1}" = / ] && [ -f "$1" ] && [ -x "$1" ]
}

# feature_flag_classify_keys の結果: FEATURE_FLAG_KEYS の添字(ファイルに初めて出た順)
#   FEATURE_FLAG_UNKNOWN_KEY_INDEXES   … 未知キー(9 キーと任意の 2 キーのどちらでもなく、FINAL_ で始まらないキー)
#   FEATURE_FLAG_FORBIDDEN_KEY_INDEXES … 確報の制御キー(FINAL_ で始まるキー)
FEATURE_FLAG_UNKNOWN_KEY_INDEXES=()
FEATURE_FLAG_FORBIDDEN_KEY_INDEXES=()

# 条件「設定所有区分」「確報クロスチェック非起動」: FEATURE_FLAG_KEYS を 所有するキー / 未知キー / 確報の制御キーに分ける。
# キー名は長いことがあるため(行の長さに上限は無い)、接頭辞と長さだけを見て、キー名の全体を比べる回数を増やさない
feature_flag_classify_keys() {
  local index prefix_length="${#FEATURE_FLAG_FORBIDDEN_KEY_PREFIX}"
  FEATURE_FLAG_UNKNOWN_KEY_INDEXES=()
  FEATURE_FLAG_FORBIDDEN_KEY_INDEXES=()
  for index in ${FEATURE_FLAG_KEYS[@]+"${!FEATURE_FLAG_KEYS[@]}"}; do
    if [ "${FEATURE_FLAG_KEYS[index]:0:prefix_length}" = "$FEATURE_FLAG_FORBIDDEN_KEY_PREFIX" ]; then
      FEATURE_FLAG_FORBIDDEN_KEY_INDEXES+=("$index")
    elif [ "${#FEATURE_FLAG_KEYS[index]}" -gt "$FEATURE_FLAG_DEFINED_KEY_MAX_LENGTH" ] \
      || ! feature_flag_is_defined_key "${FEATURE_FLAG_KEYS[index]}"; then
      FEATURE_FLAG_UNKNOWN_KEY_INDEXES+=("$index")
    fi
  done
}

# 未知キーの warn 行をすべて出す(キーがファイルに初めて出た順。拒否しない)。feature_flag_classify_keys の後に呼ぶ。
# 可視表記のキー名は数十 MB になりうるため、stdout へ出すときは行を組み立てずに printf の書式で出す
# 引数: shown_keys_name(FEATURE_FLAG_KEYS と同じ並びで、キー名を表示用に置き換え済みの配列の名前)
feature_flag_report_unknown_keys() {
  local -n feature_flag_unknown_shown_ref="$1"
  local index path
  cli_field_safe_text "${FEATURE_FLAG_PATH:-$FEATURE_FLAG_EMPTY_VALUE}"
  path="$CLI_FIELD_SAFE_TEXT"
  for index in ${FEATURE_FLAG_UNKNOWN_KEY_INDEXES[@]+"${FEATURE_FLAG_UNKNOWN_KEY_INDEXES[@]}"}; do
    if [ "$FEATURE_FLAG_REPORT_SINK" = "$FEATURE_FLAG_REPORT_SINK_ARRAY" ]; then
      FEATURE_FLAG_REPORT_LINES+=("warn: unknown key key=${feature_flag_unknown_shown_ref[index]} path: $path")
    else
      printf 'warn: unknown key key=%s path: %s\n' "${feature_flag_unknown_shown_ref[index]}" "$path"
    fi
  done
}

# 検証表の error 行(と hint)を全件出す(違反は全件収集)。feature_flag_classify_keys の後に呼ぶ。
# 入力(グローバル。repository が env から構築する):
#   BLUE_MODE GREEN_MODE RAPID_CROSSCHECK_MODE BLUE_IMPL GREEN_IMPL BLUE_RUNNER GREEN_RUNNER
#   RAPID_CROSSCHECK_RUNNER RAPID_CROSSCHECK_WORKER(未設定可。runner / worker の 4 キーは、この関数が解決後のパスに置き換える)
#   FEATURE_FLAG_PATH(メッセージの `path:` と、相対パスの基準のディレクトリに使う。未設定なら `path:` は `-`)
#   FEATURE_FLAG_FORBIDDEN_KEY_INDEXES(確報の制御キーの添字)
# 引数: shown_keys_name(FEATURE_FLAG_KEYS と同じ並びで、キー名を表示用に置き換え済みの配列の名前)
# error 行どうしの順の正本: cli-command-contract.yaml config_files.feature-flag.env.error_order(対応ジョブマップの error 行は usecase がこの後に出す)
validate_feature_flag_errors() {
  local -n feature_flag_error_shown_ref="$1"
  local path errors=0 index foreground_count=0 blue_active=false green_active=false rapid_active=false
  cli_field_safe_text "${FEATURE_FLAG_PATH:-$FEATURE_FLAG_EMPTY_VALUE}"
  path="$CLI_FIELD_SAFE_TEXT"
  # runner / worker の 4 キーは解決後のパスで検査する(呼び出し元が解決済みなら何も変わらない)。作業ディレクトリは省略時と同じ $PWD を明示して渡す
  feature_flag_resolve_runner_paths "$PWD"
  # mode の値は数 MB になりうるため、変数へ写さず、判定の結果だけを控える
  if [ "${BLUE_MODE:-}" = "$FEATURE_FLAG_MODE_FOREGROUND" ]; then
    foreground_count=$((foreground_count + 1))
  fi
  if [ "${GREEN_MODE:-}" = "$FEATURE_FLAG_MODE_FOREGROUND" ]; then
    foreground_count=$((foreground_count + 1))
  fi
  if feature_flag_mode_is_active "${BLUE_MODE:-}"; then
    blue_active=true
  fi
  if feature_flag_mode_is_active "${GREEN_MODE:-}"; then
    green_active=true
  fi
  if feature_flag_mode_is_active "${RAPID_CROSSCHECK_MODE:-}"; then
    rapid_active=true
  fi

  # 列挙・必須(BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE)
  validate_feature_flag_mode_key BLUE_MODE "$path" "${BLUE_MODE:-}" || errors=$((errors + 1))
  validate_feature_flag_mode_key GREEN_MODE "$path" "${GREEN_MODE:-}" || errors=$((errors + 1))
  validate_feature_flag_mode_key RAPID_CROSSCHECK_MODE "$path" "${RAPID_CROSSCHECK_MODE:-}" || errors=$((errors + 1))

  # 条件「foreground slot 排他」: foreground はちょうど 1 slot(2 個・0 個は同じ文言で NG。計算ルール「foreground 数」)
  if [ "$foreground_count" -ne 1 ]; then
    feature_flag_emit_value_line "error: foreground slot must be exactly one blue_mode=" "${BLUE_MODE:-}" " green_mode=" "${GREEN_MODE:-}"
    errors=$((errors + 1))
  fi

  # slot 実行モード: off 以外の slot は <SLOT>_IMPL(非空)と <SLOT>_RUNNER(実体)が必須。off は検証をスキップ
  if [ "$blue_active" = true ]; then
    validate_feature_flag_required_value BLUE_IMPL "$path" "${BLUE_IMPL:-}" || errors=$((errors + 1))
    validate_feature_flag_executable_path BLUE_RUNNER "$path" "${BLUE_RUNNER:-}" || errors=$((errors + 1))
  fi
  if [ "$green_active" = true ]; then
    validate_feature_flag_required_value GREEN_IMPL "$path" "${GREEN_IMPL:-}" || errors=$((errors + 1))
    validate_feature_flag_executable_path GREEN_RUNNER "$path" "${GREEN_RUNNER:-}" || errors=$((errors + 1))
  fi

  # 条件「速報クロスチェック有効判定」: off 以外は速報 runner / worker の実体が必須
  if [ "$rapid_active" = true ]; then
    validate_feature_flag_executable_path RAPID_CROSSCHECK_RUNNER "$path" "${RAPID_CROSSCHECK_RUNNER:-}" || errors=$((errors + 1))
    validate_feature_flag_executable_path RAPID_CROSSCHECK_WORKER "$path" "${RAPID_CROSSCHECK_WORKER:-}" || errors=$((errors + 1))
  fi

  # 条件「確報クロスチェック非起動」: キー名が FINAL_ で始まるキーは該当キーごとに error(同じキーに未知キーの warn は出さない)
  for index in ${FEATURE_FLAG_FORBIDDEN_KEY_INDEXES[@]+"${FEATURE_FLAG_FORBIDDEN_KEY_INDEXES[@]}"}; do
    feature_flag_emit "error: final crosscheck key is not allowed key=${feature_flag_error_shown_ref[index]}"
    errors=$((errors + 1))
  done

  [ "$errors" -eq 0 ]
}

# 検証表の全項目を評価する(違反は全件収集)。入力のグローバルは validate_feature_flag_errors と同じで、加えて
#   FEATURE_FLAG_KEYS(env に現れたキー一覧。未知キー warn / 確報制御キー拒否に使う。未設定なら評価しない)
# 引数: [shown_keys_name](任意。FEATURE_FLAG_KEYS と同じ並びで、キー名を表示用に置き換え済みの配列の名前。省略したらこの関数が作る)
# 行の順(契約 config_input_rules.env_files「validate-config.sh の --verbose の info 行」(c)):
#   未知キーの warn 行をすべて(キーがファイルに初めて出た順)→ error 行(と hint)。
# usecase は、行数に比例する件数の warn 行を溜めずに出すため、この関数を使わず、同じ 3 つの関数(キーの分類 → 未知キーの warn 行 →
# error 行)を自分で順に呼ぶ
validate_feature_flag() {
  local shown_keys_name="${1:-}"
  # shellcheck disable=SC2034  # 名前で渡して使う(cli_field_safe_text_list が載せ、後の 2 つの関数が読む)
  local -a feature_flag_local_shown_keys=()
  # キー名の可視表記は、行数によらず一定回数の外部コマンドでまとめて作る(キーごとに置き換えを繰り返さない)。
  # 外部コマンドが失敗したときは、キーごとに置き換える(結果は同じ。この層は終了コードを決めないため、検証表の結果を返す。
  # 補助コマンドの失敗として終了コード 6 で止めるのは、可視表記を作って渡す usecase の責務)
  if [ -z "$shown_keys_name" ]; then
    if ! cli_field_safe_text_list feature_flag_local_shown_keys ${FEATURE_FLAG_KEYS[@]+"${FEATURE_FLAG_KEYS[@]}"}; then
      local key
      feature_flag_local_shown_keys=()
      for key in ${FEATURE_FLAG_KEYS[@]+"${FEATURE_FLAG_KEYS[@]}"}; do
        cli_field_safe_text "$key"
        feature_flag_local_shown_keys+=("$CLI_FIELD_SAFE_TEXT")
      done
    fi
    shown_keys_name=feature_flag_local_shown_keys
  fi
  feature_flag_classify_keys
  feature_flag_report_unknown_keys "$shown_keys_name"
  validate_feature_flag_errors "$shown_keys_name"
}

# SlotRunnerAssignment: off でない slot の対応ジョブマップが、決めた場所に存在し読めること
# (UC「slot runner の実体スクリプトを割り当てる」が validate-config.sh --feature-flag に追加する検証項目)
# 引数: slot(blue|green) mode job_map_path(feature_flag_resolve_job_map_locations が決めた場所)
validate_slot_runner_assignment() {
  local slot="$1" mode="$2" job_map="$3"
  if ! feature_flag_mode_is_active "$mode"; then
    return 0
  fi
  # 「無い」と「あるが読めない(通常のファイルでない・読み取れない)」を分ける(契約 job_map_location.presence_report)。
  # シンボリックリンクはリンク先で判定する(-e / -f / -r はリンクを辿る)。表示はリンクを解決しない決めた場所のまま
  cli_field_safe_text "$job_map"
  if [ ! -e "$job_map" ]; then
    feature_flag_emit "error: job map not found slot=$slot map=$CLI_FIELD_SAFE_TEXT"
    return 1
  fi
  if [ ! -f "$job_map" ] || [ ! -r "$job_map" ]; then
    feature_flag_emit "error: config file is not readable path: $CLI_FIELD_SAFE_TEXT"
    return 1
  fi
  return 0
}
