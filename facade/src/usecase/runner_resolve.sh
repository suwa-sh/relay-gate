# shellcheck shell=bash source-path=SCRIPTDIR
# usecase: 共通ライブラリ lib/runner-resolve.sh の本体(ResolveExecutionTargetQuery。Runner Result Contract「ジョブマップ解決」)。
# 仕様: docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/ジョブマップで JOB_ID から実行先を解決する/
#       spec.md「処理フロー」「分岐条件一覧」「計算ルール一覧」/ tier-facade.md「出力契約」「UC ロジック」/
#       _cross-cutting/api/cli-command-contract.yaml commands「$BLUE_RUNNER / $GREEN_RUNNER」(exit_codes / environment / notes)、
#       config_files.feature-flag.env.job_map_location(slot runner の場所の決め方)、config_input_rules(byte_checks / snapshot / internal_failure)
# 流れ: ジョブマップの場所を決める → 存在と読み取り → 読み込み(1 時点の複製)→ バイト点検 → ヘッダー → 全行の構造(クォート・列数)と
#   JOB_ID の行 → 採用した行の値((6)〜(9))→ 引数連結 → 実行ログ `INFO job map resolved ...`。
# 失敗したときは、実行ログに ERROR を 1 回だけ出し、成果物ディレクトリに started-at.txt / stdout.log(空)/ stderr.log / exitcode.txt を
# 揃えてから、exitcode.txt と同じ値を返す。stderr.log の error 行は 1 行。ただし契約が全件の報告を定める違反(バイト点検の全件 + hint、
# ヘッダーの列名の重複は列名ごと)は検証コマンドと同じ順・同じ件数で書く。成功したときはファイルを書かない(解決フェーズは副作用を持たない)。
# プロセスの stdout / stderr には何も出さない(runner IF)。
#
# 標準の slot runner と自作の runner が使う関数(正本は CLI 契約 runner IF の standard_runner.runner_resolve_library。spec-decision-042。
# 名前・引数・結果の受け取り方は後方互換を保つ約束で、実装の都合では変えない。parse_csv_row / build_argument_list も同じ約束の補助関数):
#   resolve_execution_target <script> <run_id> <job_id> <role> [PARAM...]
#     戻り値 0 … 解決した。結果は EXECUTION_TARGET_HOST / _USER / _SCRIPT / _WORK_DIR / _FIXED_PARAMS(配列)/
#                _HANG_DETECT_LIMIT_MINUTES / _CREDENTIAL_REF / _MAP_VERSION / _EXEC(local | ssh)、ARGUMENT_LIST(配列)、
#                RUNNER_RESOLVE_MAP_PATH(使ったジョブマップのパス)。host / user / credential_ref / map_version の空文字は null
#     戻り値 非 0 … 解決していない。runner は RUNNER_RESOLVE_EXIT_CODE の値で終える(実装を実行しない)。
#                通常は 2 / 6(Runner Result を揃え済み。exitcode.txt と同じ値)で、戻り値も同じ値。
#                同じ run_id / role の exitcode.txt が既にあった(二重起動)ときは既存の値で、それが 0 のときだけ
#                戻り値は RUNNER_RESOLVE_STATUS_NOT_RESOLVED(戻り値 0 は「解決した」だけを表す)。
#                exitcode.txt が無く aborted.txt がある(中止済みの slot)ときは 6(成果物は書かない)
#   runner_resolve_reject_invocation <script> <run_id> <role> <message>
#     runner IF の引数の違反を実行ログに ERROR で残し、run_id と role が分かれば Runner Result を揃える。
#     戻り値は常に非 0 で、runner は RUNNER_RESOLVE_EXIT_CODE の値(2。揃えられなければ 6。二重起動なら既存の値。中止済みの slot なら 6)で終える
#   runner_resolve_guard_existing_result <run_id> <role>
#     二重起動の判定(契約 runner IF の idempotency)。戻り値 0 … 続けてよい / 非 0 … runner は RUNNER_RESOLVE_EXIT_CODE の値
#     (公開済みなら既存の exitcode.txt の値、中止済みの slot なら 6)で終える。成果物には触れない。
#     解決に失敗した経路は関数の中でこの判定を済ませている。解決に成功した runner は、後続の段へ進む前に呼ぶ
#   build_argument_list <fixed_params の JSON 配列の文字列> [PARAM...]   結果は ARGUMENT_LIST(domain/execution_target.sh)
#   parse_csv_row <line>   結果は CSV_CELLS。戻り値 1 はクォート不正
# 呼び出す側は RELAY_GATE_CONFIG_DIR / RELAY_GATE_ARTIFACT_ROOT / RELAY_GATE_LOG_DIR を設定しておく(既定の決め方は runner の実体の責務。
# 標準の slot runner は standard_runner.home)。source した側のシェルの設定(set / trap)を変えず、何も出力しない。

RUNNER_RESOLVE_SRC_DIR="${BASH_SOURCE[0]%/*}/.."
# shellcheck source=../domain/cli_field.sh
source "$RUNNER_RESOLVE_SRC_DIR/domain/cli_field.sh"
# shellcheck source=../domain/job_map.sh
source "$RUNNER_RESOLVE_SRC_DIR/domain/job_map.sh"
# shellcheck source=../domain/relay_gate_clock.sh
source "$RUNNER_RESOLVE_SRC_DIR/domain/relay_gate_clock.sh"
# shellcheck source=../domain/execution_target.sh
source "$RUNNER_RESOLVE_SRC_DIR/domain/execution_target.sh"
# shellcheck source=../repository/job_map_repo.sh
source "$RUNNER_RESOLVE_SRC_DIR/repository/job_map_repo.sh"
# shellcheck source=../gateway/execution_log.sh
source "$RUNNER_RESOLVE_SRC_DIR/gateway/execution_log.sh"
# shellcheck source=../gateway/filesystem_adapter.sh
source "$RUNNER_RESOLVE_SRC_DIR/gateway/filesystem_adapter.sh"
# バイト点検の報告(validate_job_map_report_byte_errors)を検証コマンドと共有する
# shellcheck source=validate_job_map.sh
source "$RUNNER_RESOLVE_SRC_DIR/usecase/validate_job_map.sh"

RUNNER_RESOLVE_EXIT_VALIDATION_ERROR=2
RUNNER_RESOLVE_EXIT_EXECUTION_ERROR=6
RUNNER_RESOLVE_ROLE_BLUE="blue"
RUNNER_RESOLVE_ROLE_GREEN="green"
RUNNER_RESOLVE_ERROR_PREFIX="error: "
RUNNER_RESOLVE_WARN_PREFIX="warn: "
# 解決していないが runner の終了コードは 0(既存の exitcode.txt が 0 の二重起動)のときの関数の戻り値
RUNNER_RESOLVE_STATUS_NOT_RESOLVED=1

# 解決しなかったときに runner が終える値(exitcode.txt と同じ値。二重起動なら既存の exitcode.txt の値)。解決したときは空
RUNNER_RESOLVE_EXIT_CODE=""

# 使ったジョブマップのパス(環境変数の値そのまま、または既定の場所。相対パスの解決も正規化もしない)
RUNNER_RESOLVE_MAP_PATH=""
# 実行ログを開いたスクリプト名(1 プロセスで 1 回だけ開く)
RUNNER_RESOLVE_LOG_SCRIPT=""
# 実行ログの run_id 欄(制御文字を可視表記にした値。未確定は `-`)
RUNNER_RESOLVE_LOG_RUN_ID=""

# CSV 1 行をセルに分解する(tier-facade.md ティア完了条件の parse_csv_row。本体は検証コマンドと同じ repository の csv_parse)
# 引数: line(改行を含まない 1 行)
# 戻り値: 0 … CSV_CELLS にセル / 1 … クォート不正
parse_csv_row() {
  csv_parse "$1"
}

# role が blue / green か
runner_resolve_role_is_valid() {
  [ "$1" = "$RUNNER_RESOLVE_ROLE_BLUE" ] || [ "$1" = "$RUNNER_RESOLVE_ROLE_GREEN" ]
}

# 実行ログを開き、run_id 欄の表記を決める。書き込めないときは、実行ログを書かずに続ける
# (契約 RELAY_GATE_LOG_DIR の on_missing は stderr に warn を出すが、runner は stderr に出さないため何も出さない)
# 引数: script run_id(未確定は空)
runner_resolve_open_log() {
  if [ "$RUNNER_RESOLVE_LOG_SCRIPT" != "$1" ]; then
    RUNNER_RESOLVE_LOG_SCRIPT="$1"
    execution_log_open "$1" "${RELAY_GATE_LOG_DIR:-}" || true
  fi
  if [ -n "$2" ]; then
    cli_field_safe_text "$2"
    RUNNER_RESOLVE_LOG_RUN_ID="$CLI_FIELD_SAFE_TEXT"
  else
    RUNNER_RESOLVE_LOG_RUN_ID="$EXECUTION_LOG_NO_RUN_ID"
  fi
}

# 解決しなかった runner の終了コードを RUNNER_RESOLVE_EXIT_CODE に載せ、関数の戻り値(必ず非 0)を返す。
# 終了コードが 0(既存の exitcode.txt が 0 の二重起動)のときも 0 を返さない(呼ぶ側が「解決した」と取り違えないため)
# 引数: exit_code
runner_resolve_not_resolved() {
  RUNNER_RESOLVE_EXIT_CODE="$1"
  if [ "$1" -eq 0 ]; then
    return "$RUNNER_RESOLVE_STATUS_NOT_RESOLVED"
  fi
  return "$1"
}

# 成果物ディレクトリ facade/<run_id>/<role>(契約 artifact_layout)。結果は RUNNER_RESOLVE_ROLE_DIR
# 引数: run_id role
RUNNER_RESOLVE_ROLE_DIR=""
runner_resolve_role_dir() {
  RUNNER_RESOLVE_ROLE_DIR="${RELAY_GATE_ARTIFACT_ROOT:-}/facade/$1/$2"
}

# 二重起動の判定(契約 runner IF の exit_codes / idempotency)。同じ run_id / role の成果物を書いてよいか・先へ進んでよいかを決める。
#   - exitcode.txt が既にある(この run の結果は公開済み): 実行ログに WARN を残し、既存の値を runner の終了コードにする
#     (プロセスの終了コードを exitcode.txt と一致させる。値を読めなければ 6)
#   - exitcode.txt が無く aborted.txt がある(中止済みの slot での再起動): 実行ログに `WARN slot already aborted run_id=... role=...` を
#     残して 6。exitcode.txt を書かない(再実行は background-rerun.sh が新しい run_id で行う)
# どちらの場合も成果物に一切触れない。実行ログは開いてあること(resolve_execution_target / runner_resolve_reject_invocation の後)。
# 解決に成功した runner も、後続の段へ進む前にこの関数で確かめる(契約 standard_runner.runner_resolve_library の functions)
# 引数: run_id role
# 戻り値: 0 … 公開済みでも中止済みでもない(続けてよい)/ 非 0 … runner は RUNNER_RESOLVE_EXIT_CODE の値で終える(runner_resolve_not_resolved)
runner_resolve_guard_existing_result() {
  local role="$2"
  runner_resolve_role_dir "$1" "$role"
  filesystem_adapter_slot_state "$RUNNER_RESOLVE_ROLE_DIR"
  case "$FILESYSTEM_ADAPTER_SLOT_STATE" in
    "$FILESYSTEM_ADAPTER_SLOT_PUBLISHED")
      execution_log_write "$RUNNER_RESOLVE_LOG_RUN_ID" WARN "runner result already published run_id=$RUNNER_RESOLVE_LOG_RUN_ID role=$role"
      if filesystem_adapter_read_exit_code "$RUNNER_RESOLVE_ROLE_DIR"; then
        runner_resolve_not_resolved "$FILESYSTEM_ADAPTER_EXIT_CODE"
        return
      fi
      runner_resolve_not_resolved "$RUNNER_RESOLVE_EXIT_EXECUTION_ERROR"
      return
      ;;
    "$FILESYSTEM_ADAPTER_SLOT_ABORTED")
      execution_log_write "$RUNNER_RESOLVE_LOG_RUN_ID" WARN "slot already aborted run_id=$RUNNER_RESOLVE_LOG_RUN_ID role=$role"
      runner_resolve_not_resolved "$RUNNER_RESOLVE_EXIT_EXECUTION_ERROR"
      return
      ;;
  esac
  return 0
}

# テスト用の現在時刻(RELAY_GATE_NOW)が設定されていれば、実行ログに WARN を 1 行残す(契約 conventions.environment_variables の RELAY_GATE_NOW)
runner_resolve_log_injected_clock() {
  if [ -n "${RELAY_GATE_NOW:-}" ]; then
    execution_log_write "$RUNNER_RESOLVE_LOG_RUN_ID" WARN "test clock injected now=$RELAY_GATE_NOW"
  fi
}

# 失敗を報告する: 実行ログに ERROR を 1 回(最初の error 行の本文)出し、Runner Result を揃える。
#   - 公開済み(exitcode.txt がある)・中止済み(exitcode.txt が無く aborted.txt がある): 既存の成果物を上書きせず、
#     実行ログに WARN を残して、契約の終了コードで終える(runner_resolve_guard_existing_result)
#   - 揃えられない(ディレクトリを作れない・書けない): 実行ログに ERROR を残して 6(exitcode.txt は無いまま)
# 引数: run_id role exit_code stderr_line...(1 行目が `error: ...`。2 行目以降に error 行・hint 行が続くことがある)
# 戻り値: 非 0(runner の終了コードは RUNNER_RESOLVE_EXIT_CODE。runner_resolve_not_resolved)
runner_resolve_fail() {
  local run_id="$1" role="$2" exit_code="$3" role_dir shown_dir
  shift 3
  execution_log_write "$RUNNER_RESOLVE_LOG_RUN_ID" ERROR "${1#"$RUNNER_RESOLVE_ERROR_PREFIX"}"
  runner_resolve_guard_existing_result "$run_id" "$role" || return
  role_dir="$RUNNER_RESOLVE_ROLE_DIR"
  relay_gate_clock_now
  relay_gate_clock_format_utc "$RELAY_GATE_CLOCK_EPOCH"
  if ! filesystem_adapter_publish_failure "$role_dir" "$RELAY_GATE_CLOCK_TEXT" "$exit_code" "$@"; then
    cli_field_safe_text "$role_dir"
    shown_dir="$CLI_FIELD_SAFE_TEXT"
    execution_log_write "$RUNNER_RESOLVE_LOG_RUN_ID" ERROR "runner result write failed run_id=$RUNNER_RESOLVE_LOG_RUN_ID role=$role path: $shown_dir"
    runner_resolve_not_resolved "$RUNNER_RESOLVE_EXIT_EXECUTION_ERROR"
    return
  fi
  runner_resolve_not_resolved "$exit_code"
}

# runner IF の引数の違反(presentation が見つけたもの)を報告する。run_id か role が分からなければ成果物は書けないため、
# 実行ログにだけ残す(tier-facade.md エラーメッセージ表「必須オプション欠落」)
# 引数: script run_id(分からなければ空) role(分からなければ空) message(`error: ` を除いた本文)
# 戻り値: 非 0(runner の終了コードは RUNNER_RESOLVE_EXIT_CODE。2。Runner Result を揃えられなければ 6。二重起動なら既存の値)
runner_resolve_reject_invocation() {
  local script="$1" run_id="$2" role="$3" message="$4"
  runner_resolve_open_log "$script" "$run_id"
  if [ -z "$run_id" ] || ! runner_resolve_role_is_valid "$role"; then
    execution_log_write "$RUNNER_RESOLVE_LOG_RUN_ID" ERROR "$message"
    runner_resolve_not_resolved "$RUNNER_RESOLVE_EXIT_VALIDATION_ERROR"
    return
  fi
  # started-at.txt に注入された時刻を使うため、解決の経路と同じく WARN を残す(形式が不正な値は使わず、報告は引数の違反の 1 件だけ)
  if relay_gate_clock_injection_is_valid; then
    runner_resolve_log_injected_clock
  fi
  runner_resolve_fail "$run_id" "$role" "$RUNNER_RESOLVE_EXIT_VALIDATION_ERROR" "$RUNNER_RESOLVE_ERROR_PREFIX$message"
}

# 溜めた報告行(JOB_MAP_REPORT_LINES)のうち warn 行を実行ログに WARN で出し、error 行を出た順のまま
# RUNNER_RESOLVE_ERROR_LINES に載せる(stderr.log に書く行。実行ログの ERROR は runner_resolve_fail が 1 行目だけを 1 回出す)
RUNNER_RESOLVE_ERROR_LINES=()
runner_resolve_drain_report() {
  local line
  RUNNER_RESOLVE_ERROR_LINES=()
  for line in ${JOB_MAP_REPORT_LINES[@]+"${JOB_MAP_REPORT_LINES[@]}"}; do
    case "$line" in
      "$RUNNER_RESOLVE_WARN_PREFIX"*) execution_log_write "$RUNNER_RESOLVE_LOG_RUN_ID" WARN "${line#"$RUNNER_RESOLVE_WARN_PREFIX"}" ;;
      "$RUNNER_RESOLVE_ERROR_PREFIX"*) RUNNER_RESOLVE_ERROR_LINES+=("$line") ;;
    esac
  done
  JOB_MAP_REPORT_LINES=()
}

# ResolveExecutionTargetQuery
# 引数: script(実行ログの {script}。例 standard-runner.sh) run_id job_id role(blue | green) [PARAM...]
# 戻り値: 0 … 解決した / 非 0 … 解決していない(runner は RUNNER_RESOLVE_EXIT_CODE で終える。2 … 入力・設定の検証エラー /
#         6 … 実行エラー(どちらも Runner Result を揃え済み)/ 二重起動なら既存の exitcode.txt の値)
# shellcheck disable=SC2034  # 結果のグローバル(RUNNER_RESOLVE_EXIT_CODE。共通ライブラリを使う runner が読む)
resolve_execution_target() {
  local script="$1" run_id="$2"
  # 報告行は配列に溜め、値は溜めるときに可視表記にする(戻るときに出力先を元に戻す)
  local saved_sink="$JOB_MAP_REPORT_SINK" saved_defer="$JOB_MAP_REPORT_DEFER_ESCAPE" status=0
  shift 2
  execution_target_reset
  RUNNER_RESOLVE_MAP_PATH=""
  RUNNER_RESOLVE_EXIT_CODE=""
  runner_resolve_open_log "$script" "$run_id"
  JOB_MAP_REPORT_SINK="$JOB_MAP_REPORT_SINK_ARRAY"
  JOB_MAP_REPORT_DEFER_ESCAPE=false
  JOB_MAP_REPORT_LINES=()
  runner_resolve_run "$run_id" "$@" || status=$?
  JOB_MAP_REPORT_LINES=()
  JOB_MAP_REPORT_SINK="$saved_sink"
  JOB_MAP_REPORT_DEFER_ESCAPE="$saved_defer"
  return "$status"
}

# 解決の本体(resolve_execution_target から呼ぶ。JOB_MAP_REPORT_SINK は配列)
# 引数: run_id job_id role [PARAM...]
# shellcheck disable=SC2034  # 結果のグローバル(RUNNER_RESOLVE_MAP_PATH / ARGUMENT_LIST。共通ライブラリを使う runner が読む)
runner_resolve_run() {
  local run_id="$1" job_id="$2" role="$3" map="" shown_map shown_job_id load_status=0
  shift 3
  # 判定はすべてバイト単位(検証コマンドと同じ。出力のバイト列は変わらない)
  local LC_ALL=C
  cli_field_safe_text "$job_id"
  shown_job_id="$CLI_FIELD_SAFE_TEXT"

  # role が分からなければ、ジョブマップも成果物ディレクトリも決まらない(実行ログにだけ残す)
  if ! runner_resolve_role_is_valid "$role"; then
    cli_field_safe_text "$role"
    execution_log_write "$RUNNER_RESOLVE_LOG_RUN_ID" ERROR "invalid value option=--role value=$CLI_FIELD_SAFE_TEXT"
    runner_resolve_not_resolved "$RUNNER_RESOLVE_EXIT_VALIDATION_ERROR"
    return
  fi
  if ! relay_gate_clock_injection_is_valid; then
    cli_field_safe_text "$RELAY_GATE_NOW"
    runner_resolve_fail "$run_id" "$role" "$RUNNER_RESOLVE_EXIT_VALIDATION_ERROR" \
      "error: invalid value env=$RELAY_GATE_CLOCK_ENV value=$CLI_FIELD_SAFE_TEXT"
    return
  fi
  runner_resolve_log_injected_clock

  # 計算ルール「ジョブマップパス」: 自 slot の環境変数の値が空でなければそのまま使い、未設定・空なら既定の場所
  if [ "$role" = "$RUNNER_RESOLVE_ROLE_BLUE" ]; then
    map="${BLUE_JOB_MAP_CSV:-}"
  else
    map="${GREEN_JOB_MAP_CSV:-}"
  fi
  if [ -z "$map" ]; then
    map="${RELAY_GATE_CONFIG_DIR:-}/$role-job-map.csv"
  fi
  RUNNER_RESOLVE_MAP_PATH="$map"
  cli_field_safe_text "$map"
  shown_map="$CLI_FIELD_SAFE_TEXT"

  # (2) ジョブマップの存在と読み取り権限(判定は検証コマンド --job-map と同じ job_map_repo_probe)。
  # 無いときは tier-facade.md エラーメッセージ表の「マップなし」、あるが読めないときは全コマンド共通の定型文(ui-design.md エラー表示規約)
  local probe_status=0
  job_map_repo_probe "$map" || probe_status=$?
  if [ "$probe_status" -eq "$JOB_MAP_REPO_PROBE_NOT_FOUND" ]; then
    runner_resolve_fail "$run_id" "$role" "$RUNNER_RESOLVE_EXIT_VALIDATION_ERROR" "error: job map not found slot=$role map=$shown_map"
    return
  fi
  if [ "$probe_status" -ne 0 ]; then
    runner_resolve_fail "$run_id" "$role" "$RUNNER_RESOLVE_EXIT_VALIDATION_ERROR" "error: config file is not readable path: $shown_map"
    return
  fi

  # 読み込み(1 時点の複製を読む。config_input_rules.snapshot)。複製の失敗と補助コマンドの失敗は exitcode.txt=6
  job_map_repo_load "$map" || load_status=$?
  if [ "$load_status" -eq "$JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED" ]; then
    runner_resolve_fail "$run_id" "$role" "$RUNNER_RESOLVE_EXIT_EXECUTION_ERROR" \
      "error: config snapshot failed path: $shown_map" "hint: check TMPDIR is writable"
    return
  fi
  if [ "$load_status" -ne 0 ]; then
    runner_resolve_fail "$run_id" "$role" "$RUNNER_RESOLVE_EXIT_EXECUTION_ERROR" \
      "error: internal command failed commands=$JOB_MAP_REPO_FAILED_COMMANDS path: $shown_map"
    return
  fi

  # バイト点検(NUL / UTF-8 / BOM / CR)。違反は検証コマンドと同じ順・同じ件数で全件出して、解析しない
  if ! validate_job_map_report_byte_errors "$shown_map"; then
    local -a byte_lines=("${JOB_MAP_REPORT_LINES[@]}")
    JOB_MAP_REPORT_LINES=()
    runner_resolve_fail "$run_id" "$role" "$RUNNER_RESOLVE_EXIT_VALIDATION_ERROR" "${byte_lines[@]}"
    return
  fi

  # (3) ヘッダー(必須列 5、host / user は両方あるか両方無い、列名の重複。未知列は実行ログに WARN)。
  # ヘッダーの error 行は検証コマンドと同じ順・同じ件数で stderr.log に書く(列名の重複は重複した列名ごとに 1 行。
  # config_input_rules.rules「ヘッダー列名の重複」)
  if [ "$JOB_MAP_HEADER_STATUS" = "$JOB_MAP_PARSE_QUOTE_INVALID" ]; then
    runner_resolve_fail "$run_id" "$role" "$RUNNER_RESOLVE_EXIT_VALIDATION_ERROR" \
      "error: csv quote is invalid line=$JOB_MAP_HEADER_LINE path: $shown_map"
    return
  fi
  validate_job_map_header "$map" ${JOB_MAP_HEADER[@]+"${JOB_MAP_HEADER[@]}"} || true
  runner_resolve_drain_report
  if [ "${#RUNNER_RESOLVE_ERROR_LINES[@]}" -gt 0 ]; then
    runner_resolve_fail "$run_id" "$role" "$RUNNER_RESOLVE_EXIT_VALIDATION_ERROR" "${RUNNER_RESOLVE_ERROR_LINES[@]}"
    return
  fi
  job_map_header_bind "${JOB_MAP_HEADER[@]}"

  # 行の構造((4) CSV セルのクォート整合 と 列数。空白だけの行は 1 セルの行として列数不一致。config_input_rules.rules)と
  # (5) JOB_ID の行(完全一致。重複は先頭の行を採用)を、全行の 1 回の走査で調べる。
  # 構造の違反はどの行にあっても拒否し、行番号が最小の 1 件を報告して解決しない(列を対応付けられない行は job_id を取り出せない)
  local row_index=0 row_count="${#JOB_MAP_ROW_LINES[@]}" job_id_index="${JOB_MAP_COLUMN_INDEXES[0]}"
  local expected="${#JOB_MAP_HEADER[@]}" structure_error="" adopted="" matched_lines="" cell_count
  while [ "$row_index" -lt "$row_count" ]; do
    if [ "${JOB_MAP_ROW_STATUSES[row_index]}" = "$JOB_MAP_PARSE_QUOTE_INVALID" ]; then
      structure_error="error: csv quote is invalid line=${JOB_MAP_ROW_LINES[row_index]} path: $shown_map"
      break
    fi
    cell_count="${JOB_MAP_ROW_CELL_COUNTS[row_index]}"
    if [ "$cell_count" -ne "$expected" ]; then
      structure_error="error: column count mismatch line=${JOB_MAP_ROW_LINES[row_index]} expected=$expected actual=$cell_count"
      break
    fi
    if [ "${JOB_MAP_CELLS[JOB_MAP_ROW_OFFSETS[row_index] + job_id_index]}" = "$job_id" ]; then
      if [ -z "$adopted" ]; then
        adopted="$row_index"
      fi
      matched_lines+="${matched_lines:+,}${JOB_MAP_ROW_LINES[row_index]}"
    fi
    row_index=$((row_index + 1))
  done
  if [ -n "$structure_error" ]; then
    runner_resolve_fail "$run_id" "$role" "$RUNNER_RESOLVE_EXIT_VALIDATION_ERROR" "$structure_error"
    return
  fi
  if [ -z "$adopted" ]; then
    runner_resolve_fail "$run_id" "$role" "$RUNNER_RESOLVE_EXIT_VALIDATION_ERROR" \
      "error: job_id=$shown_job_id not found in job map slot=$role map=$shown_map"
    return
  fi
  local line="${JOB_MAP_ROW_LINES[adopted]}"
  if [ "$matched_lines" != "$line" ]; then
    execution_log_write "$RUNNER_RESOLVE_LOG_RUN_ID" WARN "duplicate job_id in job map job_id=$shown_job_id lines=$matched_lines"
  fi

  # (6)〜(9) 採用した行の値 → ExecutionTarget。credential_ref の warn 行(値は出さない)は成功・失敗を問わず実行ログに WARN で出す
  local target_status=0
  job_map_row_bind_at JOB_MAP_CELLS "${JOB_MAP_ROW_OFFSETS[adopted]}"
  execution_target_from_row "$line" || target_status=$?
  runner_resolve_drain_report
  if [ "$target_status" -ne 0 ]; then
    runner_resolve_fail "$run_id" "$role" "$RUNNER_RESOLVE_EXIT_VALIDATION_ERROR" "${RUNNER_RESOLVE_ERROR_LINES[@]}"
    return
  fi

  # 引数連結規則: 固定引数の後ろに PARAM を順序どおり足す(解析済みの固定引数を使う)
  ARGUMENT_LIST=(${EXECUTION_TARGET_FIXED_PARAMS[@]+"${EXECUTION_TARGET_FIXED_PARAMS[@]}"} "$@")

  local shown_host="$JOB_MAP_EMPTY_VALUE" shown_map_version="$JOB_MAP_EMPTY_VALUE"
  if [ -n "$EXECUTION_TARGET_HOST" ]; then
    cli_field_safe_text "$EXECUTION_TARGET_HOST"
    shown_host="$CLI_FIELD_SAFE_TEXT"
  fi
  if [ -n "$EXECUTION_TARGET_MAP_VERSION" ]; then
    cli_field_safe_text "$EXECUTION_TARGET_MAP_VERSION"
    shown_map_version="$CLI_FIELD_SAFE_TEXT"
  fi
  execution_log_write "$RUNNER_RESOLVE_LOG_RUN_ID" INFO "job map resolved job_id=$shown_job_id slot=$role host=$shown_host map_version=$shown_map_version"
  return 0
}
