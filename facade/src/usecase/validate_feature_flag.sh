#!/usr/bin/env bash
# usecase: ValidateFeatureFlagQuery(validate-config.sh --feature-flag の本体。読み取り専用・副作用なし)。
# 入力の複製 → (i) バイト点検(NUL / UTF-8 / BOM / CR)→ (ii) 行の構造(invalid line・同じキーの重複)
# → (iii) --verbose の info 行・未知キーの warn・検証表の全項目(違反を全件収集)・対応ジョブマップ・runner --help 問い合わせ
# → 結果出力(stdout 15 キー固定順 / stderr)。検査の段は CLI 契約 config_input_rules.env_files に従う。
# (i)(ii) で止めた回は、その段の error 行(と hint)だけを出し、stdout も info 行も出さない(--feature-flag の stdout は検証 OK のときだけ)。
# 仕様: tier-facade.md「出力契約」「UC ロジック」。stdout の 15 キー固定順は
#       _cross-cutting/api/cli-command-contract.yaml commands[validate-config.sh].stdout が正。
#       行の形式(`key=value` / `key: value` / 空値 `-`)は domain/cli_field.sh(ui-design.md 出力フォーマット)に従う。
#       stderr に出す任意入力(キー名・値・パス)は制御文字を可視表記にする(cli_field_safe_text)。
# 依存: domain/feature_flag.sh, domain/cli_field.sh, repository/feature_flag_config.sh, gateway/runner_probe.sh,
#       domain/job_map.sh と usecase/validate_job_map.sh(validate_job_map_report_byte_errors。バイト点検の文言と順序の規則を
#       slot ジョブマップ・速報クロスチェック設定と共有する。未 source なら自分で source する)
# 戻り値: 0(検証 OK)/ 2(ファイルなし・読めない・入力の守備範囲の違反・検証違反 1 件以上)/
#         6(入力の複製の失敗・補助コマンドの失敗(config_input_rules.internal_failure。バイト点検・行の構造の取り出し・
#           可視表記をまとめて作る sed / tr の失敗を含む)、runner --help 問い合わせの準備失敗
#           (runner_help_probe.preparation_failure)。stdout を出さず、error 行 1 つ(+ hint)だけを出す)
# 任意文字列の値(実装版など)を出力するため echo は使わず printf の固定フォーマットで出す。
# shellcheck source-path=SCRIPTDIR

if ! declare -F job_map_emit >/dev/null; then
  # shellcheck source=../domain/job_map.sh
  source "${BASH_SOURCE[0]%/*}/../domain/job_map.sh"
fi
if ! declare -F validate_job_map_report_byte_errors >/dev/null; then
  # shellcheck source=validate_job_map.sh
  source "${BASH_SOURCE[0]%/*}/validate_job_map.sh"
fi

FEATURE_FLAG_EXIT_OK=0
FEATURE_FLAG_EXIT_VALIDATION_ERROR=2
FEATURE_FLAG_EXIT_EXECUTION_ERROR=6

# validate_feature_flag_resolve_if_version の結果(サブシェルを使わずグローバルで返す。大きな設定を読み込んだ後の
# サブシェルの起動は、プロセスの複製に時間がかかる)
#   VALIDATE_FEATURE_FLAG_IF_VERSION  … slot の runner IF 版(`-` を含む)
#   VALIDATE_FEATURE_FLAG_PROBE_ERROR … 準備失敗のときの error 行
VALIDATE_FEATURE_FLAG_IF_VERSION=""
VALIDATE_FEATURE_FLAG_PROBE_ERROR=""

# slot の runner IF 版を解決する(契約 runner_help_probe)。
# mode=off の slot / 実体検証(解決後のパスに実体が存在し実行可能)に違反した slot は問い合わせず `-`。
# 「応答しない」(上限到達・非 0 終了・版行なし・版が 1 でない)は warn を報告行に足して `-`(拒否しない)。
# 問い合わせで起動するのも、warn 行の `runner=` に出すのも解決後のパス(契約 runner_path_resolution の usage / display)
# 引数: slot mode runner(解決後のパス)
# 戻り値: 0 … VALIDATE_FEATURE_FLAG_IF_VERSION に版(`-` を含む)。warn があれば報告行(feature_flag_emit)に 1 行
#         6 … 準備失敗。VALIDATE_FEATURE_FLAG_PROBE_ERROR に `error: runner probe failed slot=<s> reason=<r>`
validate_feature_flag_resolve_if_version() {
  local slot="$1" version probe_status=0
  VALIDATE_FEATURE_FLAG_IF_VERSION="$FEATURE_FLAG_EMPTY_VALUE"
  VALIDATE_FEATURE_FLAG_PROBE_ERROR=""
  if ! feature_flag_mode_is_active "$2" || ! feature_flag_path_is_executable "$3"; then
    return 0
  fi
  version="$(runner_probe_if_version "$3")" || probe_status=$?
  if [ "$probe_status" -eq "$RUNNER_PROBE_STATUS_PREPARATION_FAILED" ]; then
    cli_field_safe_text "$version"
    VALIDATE_FEATURE_FLAG_PROBE_ERROR="error: runner probe failed slot=$slot reason=$CLI_FIELD_SAFE_TEXT"
    return "$FEATURE_FLAG_EXIT_EXECUTION_ERROR"
  fi
  if [ "$probe_status" -eq "$RUNNER_PROBE_STATUS_RESPONDED" ] && runner_probe_version_is_current "$version"; then
    VALIDATE_FEATURE_FLAG_IF_VERSION="$version"
  else
    feature_flag_emit_value_line "warn: runner does not respond to --help slot=$slot runner=" "$3"
  fi
  return 0
}

# slot のフィールド 1 行(off の slot の値は `-`。空の値も `-`)
# 引数: kind(field|path) key mode value
validate_feature_flag_slot_field_line() {
  if ! feature_flag_mode_is_active "$3"; then
    set -- "$1" "$2" "$3" ""
  fi
  if [ "$1" = path ]; then
    cli_path_field_line "$2" "$4"
  else
    cli_field_line "$2" "$4"
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
  validate_feature_flag_slot_field_line field blue_impl "$blue_mode" "${BLUE_IMPL:-}"
  validate_feature_flag_slot_field_line field green_impl "$green_mode" "${GREEN_IMPL:-}"
  validate_feature_flag_slot_field_line path blue_runner "$blue_mode" "${BLUE_RUNNER:-}"
  validate_feature_flag_slot_field_line path green_runner "$green_mode" "${GREEN_RUNNER:-}"
  cli_field_line rapid_crosscheck_mode "$rapid_mode"
  validate_feature_flag_slot_field_line path rapid_crosscheck_runner "$rapid_mode" "${RAPID_CROSSCHECK_RUNNER:-}"
  validate_feature_flag_slot_field_line path rapid_crosscheck_worker "$rapid_mode" "${RAPID_CROSSCHECK_WORKER:-}"
  feature_flag_resolve_operation_mode "$blue_mode" "$green_mode" "$rapid_mode"
  cli_field_line operation_mode "$FEATURE_FLAG_OPERATION_MODE"
  validate_feature_flag_slot_field_line path blue_job_map "$blue_mode" "$blue_job_map"
  validate_feature_flag_slot_field_line path green_job_map "$green_mode" "$green_job_map"
  cli_field_line blue_runner_if_version "$blue_if"
  cli_field_line green_runner_if_version "$green_if"
}

# 可視表記をまとめて作る外部コマンド(sed / tr)の失敗を、補助コマンドの失敗として報告する(config_input_rules.internal_failure:
# error 行 1 つだけを出し、stdout も他の行も出さない。呼び出し元は終了コード 6 で終える)。
# 可視表記は、何かを出力する前にまとめて作るため、この行より前に出した行は無い
# 引数: shown_path(表示用に置き換え済みのパス)
validate_feature_flag_report_escape_failure() {
  printf '%s\n' "error: internal command failed commands=$CLI_FIELD_BATCH_FAILED_COMMANDS path: $1" >&2
}

# キーごとの検査と stdout で表示しうる値(mode 3 キーと、off でない slot・速報クロスチェックの値)の可視表記を、まとめて作って控える。
# 値は数 MB になりうる(行の長さに上限は無い)。後の検査・表示(サブシェルで動くものを含む)は控えを使い、外部コマンドを起動しない
# 戻り値: 0 … 控えた・控える必要が無かった / 1 … 外部コマンドが失敗した
validate_feature_flag_prepare_shown_values() {
  local -a values=("${BLUE_MODE:-}" "${GREEN_MODE:-}" "${RAPID_CROSSCHECK_MODE:-}")
  if feature_flag_mode_is_active "${BLUE_MODE:-}"; then
    values+=("${BLUE_IMPL:-}" "${BLUE_RUNNER:-}")
  fi
  if feature_flag_mode_is_active "${GREEN_MODE:-}"; then
    values+=("${GREEN_IMPL:-}" "${GREEN_RUNNER:-}")
  fi
  if feature_flag_mode_is_active "${RAPID_CROSSCHECK_MODE:-}"; then
    values+=("${RAPID_CROSSCHECK_RUNNER:-}" "${RAPID_CROSSCHECK_WORKER:-}")
  fi
  # slot ジョブマップの決めた場所(off の slot は空。stdout と job map not found の map= で表示する)
  values+=("$FEATURE_FLAG_BLUE_JOB_MAP" "$FEATURE_FLAG_GREEN_JOB_MAP")
  cli_field_safe_text_prepare "${values[@]}"
}

# 引数: path config_dir(slot ジョブマップの既定の場所の置き場。RELAY_GATE_CONFIG_DIR) verbose(true|false)
validate_feature_flag_query() {
  local path="$1" config_dir="$2" verbose="${3:-false}" shown_path load_status=0
  cli_field_safe_text "$path"
  shown_path="$CLI_FIELD_SAFE_TEXT"

  if [ ! -e "$path" ]; then
    printf '%s\n' "error: config file not found path: $shown_path" >&2
    return "$FEATURE_FLAG_EXIT_VALIDATION_ERROR"
  fi
  if [ ! -f "$path" ] || [ ! -r "$path" ]; then
    printf '%s\n' "error: config file is not readable path: $shown_path" >&2
    return "$FEATURE_FLAG_EXIT_VALIDATION_ERROR"
  fi

  # 入力の複製 → バイト点検 → 行の読み取り。内部障害は error 行 1 つ(+ hint)だけを出して終了コード 6
  # (config_input_rules.internal_failure)
  feature_flag_config_load "$path" || load_status=$?
  if [ "$load_status" -eq "$FEATURE_FLAG_CONFIG_STATUS_SNAPSHOT_FAILED" ]; then
    printf '%s\n' "error: config snapshot failed path: $shown_path" "hint: check TMPDIR is writable" >&2
    return "$FEATURE_FLAG_EXIT_EXECUTION_ERROR"
  fi
  if [ "$load_status" -ne 0 ]; then
    printf '%s\n' "error: internal command failed commands=$FEATURE_FLAG_CONFIG_FAILED_COMMANDS path: $shown_path" >&2
    return "$FEATURE_FLAG_EXIT_EXECUTION_ERROR"
  fi

  # (i) バイト・改行の検査(config_input_rules.byte_checks)。違反があればその error 行と hint だけを出して止める
  local saved_sink="$JOB_MAP_REPORT_SINK" byte_status=0
  JOB_MAP_REPORT_SINK="$JOB_MAP_REPORT_SINK_ARRAY"
  # shellcheck disable=SC2034  # validate_job_map_report_byte_errors(job_map_emit)が溜める先
  JOB_MAP_REPORT_LINES=()
  validate_job_map_report_byte_errors "$shown_path" || byte_status=$?
  validate_job_map_flush_report
  JOB_MAP_REPORT_SINK="$saved_sink"
  if [ "$byte_status" -ne 0 ]; then
    return "$FEATURE_FLAG_EXIT_VALIDATION_ERROR"
  fi

  # (ii) 行の構造の検査(config_input_rules.env_files): invalid line を行番号の昇順 → duplicate key を初出行の昇順。
  # 1 件でもあればファイルの値を使わず、キーごとの検査に進まない
  # キー名の可視表記は、行数によらず一定回数の外部コマンドでまとめて作る(cli_field_safe_text_list。キーごとに置き換えを繰り返さない)
  local structure_lines=() number index
  local -a shown_duplicate_keys=()
  for number in ${FEATURE_FLAG_CONFIG_INVALID_LINES[@]+"${FEATURE_FLAG_CONFIG_INVALID_LINES[@]}"}; do
    structure_lines+=("error: invalid line line=$number path: $shown_path")
  done
  if ! cli_field_safe_text_list shown_duplicate_keys ${FEATURE_FLAG_CONFIG_DUPLICATE_KEYS[@]+"${FEATURE_FLAG_CONFIG_DUPLICATE_KEYS[@]}"}; then
    validate_feature_flag_report_escape_failure "$shown_path"
    return "$FEATURE_FLAG_EXIT_EXECUTION_ERROR"
  fi
  for index in "${!FEATURE_FLAG_CONFIG_DUPLICATE_KEYS[@]}"; do
    structure_lines+=("error: duplicate key key=${shown_duplicate_keys[index]} lines=${FEATURE_FLAG_CONFIG_DUPLICATE_LINES[index]} path: $shown_path")
  done
  shown_duplicate_keys=()
  if [ "${#structure_lines[@]}" -gt 0 ]; then
    printf '%s\n' "${structure_lines[@]}" >&2
    return "$FEATURE_FLAG_EXIT_VALIDATION_ERROR"
  fi

  # (iii) キーごとの検査。stderr の行は、検査をすべて終えてから出す。順は info 行すべて(--verbose 時のみ)→ 未知キーの warn 行すべて
  # (どちらもキーがファイルに初めて出た順)→ 検証表・対応ジョブマップの error 行(と hint)→ runner --help 問い合わせの warn 行
  # (config_input_rules.env_files「validate-config.sh の --verbose の info 行」(c))。
  # runner の問い合わせの準備失敗(終了コード 6)の回は、他の行を出さずにその error 行だけを出す(同 (b))
  # error 行と、後ろに続く warn 行は報告行の配列(domain の feature_flag_emit の出し先)に溜める
  local errors=0
  # キー名の可視表記(FEATURE_FLAG_KEYS と同じ並び)。info 行・未知キーの warn 行・確報制御キーの error 行で使い回す。
  # 可視表記は数十 MB になりうる(制御文字 1 つが 6 バイトになる)ため、info 行と warn 行は配列に溜めず、最後に書式で直接出す
  local -a shown_keys=()
  # runner / worker の 4 キーを解決後のパスに置き換える(契約 runner_path_resolution。基準は設定ファイルのあるディレクトリ)。
  # これ以降の実体の検査・runner への問い合わせ・stdout / error 行 / warn 行の表示は、すべて解決後のパスで行う。
  # 表示する値の可視表記を控える前に行う(控えるのは解決後のパスの可視表記)。作業ディレクトリは省略時と同じ $PWD を明示して渡す
  feature_flag_resolve_runner_paths "$PWD"
  # slot ジョブマップの場所を決める(契約 job_map_location。任意の 2 キーの値を同じ規則で解決し、無い・空なら
  # <config_dir>/<slot>-job-map.csv。off の slot は決めない)。所在の検査・stdout・error 行の map= は、決めた場所を使う
  feature_flag_resolve_job_map_locations "$config_dir"
  if ! cli_field_safe_text_list shown_keys ${FEATURE_FLAG_KEYS[@]+"${FEATURE_FLAG_KEYS[@]}"} \
    || ! validate_feature_flag_prepare_shown_values; then
    validate_feature_flag_report_escape_failure "$shown_path"
    return "$FEATURE_FLAG_EXIT_EXECUTION_ERROR"
  fi

  # 検証表(domain の error 行と hint を全件。未知キーの warn 行は最後に出す)・対応ジョブマップ・runner の問い合わせの行は、
  # サブシェルで受けず、報告行の配列で受ける
  local saved_feature_flag_sink="$FEATURE_FLAG_REPORT_SINK"
  FEATURE_FLAG_REPORT_SINK="$FEATURE_FLAG_REPORT_SINK_ARRAY"
  feature_flag_reset_report_lines
  feature_flag_classify_keys
  if ! validate_feature_flag_errors shown_keys; then
    errors=$((errors + 1))
  fi

  local blue_mode="${BLUE_MODE:-}" green_mode="${GREEN_MODE:-}" rapid_mode="${RAPID_CROSSCHECK_MODE:-}"
  local blue_job_map="$FEATURE_FLAG_BLUE_JOB_MAP" green_job_map="$FEATURE_FLAG_GREEN_JOB_MAP"

  # SlotRunnerAssignment: off でない slot の対応ジョブマップ(error_order の 6。blue → green)
  if ! validate_slot_runner_assignment blue "$blue_mode" "$blue_job_map"; then
    errors=$((errors + 1))
  fi
  if ! validate_slot_runner_assignment green "$green_mode" "$green_job_map"; then
    errors=$((errors + 1))
  fi

  # runner IF 版(契約 runner_help_probe.order: blue → green の逐次。warn は拒否しない。
  # 準備失敗は残りの検証と stdout の出力を行わず、その error 行だけを出して終了コード 6 で即時終了する)
  local blue_if green_if
  if ! validate_feature_flag_resolve_if_version blue "$blue_mode" "${BLUE_RUNNER:-}"; then
    FEATURE_FLAG_REPORT_SINK="$saved_feature_flag_sink"
    feature_flag_reset_report_lines
    printf '%s\n' "$VALIDATE_FEATURE_FLAG_PROBE_ERROR" >&2
    return "$FEATURE_FLAG_EXIT_EXECUTION_ERROR"
  fi
  blue_if="$VALIDATE_FEATURE_FLAG_IF_VERSION"
  if ! validate_feature_flag_resolve_if_version green "$green_mode" "${GREEN_RUNNER:-}"; then
    FEATURE_FLAG_REPORT_SINK="$saved_feature_flag_sink"
    feature_flag_reset_report_lines
    printf '%s\n' "$VALIDATE_FEATURE_FLAG_PROBE_ERROR" >&2
    return "$FEATURE_FLAG_EXIT_EXECUTION_ERROR"
  fi
  green_if="$VALIDATE_FEATURE_FLAG_IF_VERSION"
  FEATURE_FLAG_REPORT_SINK="$saved_feature_flag_sink"

  {
    if [ "$verbose" = "true" ]; then
      for index in ${shown_keys[@]+"${!shown_keys[@]}"}; do
        printf 'info: key loaded key=%s path: %s\n' "${shown_keys[index]}" "$shown_path"
      done
    fi
    feature_flag_report_unknown_keys shown_keys
    feature_flag_flush_report_lines
  } >&2
  shown_keys=()
  if [ "$errors" -ne 0 ]; then
    return "$FEATURE_FLAG_EXIT_VALIDATION_ERROR"
  fi

  validate_feature_flag_render "$path" "$blue_mode" "$green_mode" "$rapid_mode" \
    "$blue_job_map" "$green_job_map" "$blue_if" "$green_if"
  return "$FEATURE_FLAG_EXIT_OK"
}
