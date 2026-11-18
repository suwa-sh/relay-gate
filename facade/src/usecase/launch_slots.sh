#!/usr/bin/env bash
# usecase: LaunchSlotsCommand(facade.sh の本体。slot 実行モードを選択して runner を起動する)。
# 仕様: docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/
#       spec.md「処理フロー」「分岐条件一覧」「状態遷移一覧」/ tier-facade.md「UC ロジック」「出力契約」/
#       _cross-cutting/api/cli-command-contract.yaml commands の facade.sh(config_violation_report / exit_codes / execution_log / notes)
# 流れ: feature-flag.env の検査(検証コマンドと同じ関数。最初の違反の 1 行だけを出す)→(off 以外)rapid-crosscheck.env の検査
#   → run_id の発行 → 成果物ディレクトリの作成 →(off 以外)parallel_runs + rapid_runs の INSERT(同一トランザクション)
#   → background の slot をすべて起動(blue → green)→ foreground の slot を起動(off 以外は slot ごとに起動前 INSERT・起動後 pid UPDATE)
#   →(off 以外)parallel_runs を STARTED → RUNNING → foreground の PID だけを待つ → foreground の exitcode.txt の値を返す。
# foreground の stdout.log / stderr.log の中継と中継後の COMPLETED への遷移は UC「foreground slot の結果をジョブスケジューラへ中継する」の担当。
# エラーは usecase で 1 回だけ実行ログに ERROR を出し、stderr の error 行は 1 行だけ出す(CLR-001)。
# 検証エラー(引数・feature-flag.env・rapid-crosscheck.env・RELAY_GATE_NOW)も、stderr と同じ error 行を run_id 未確定(`-`)の ERROR で残す。
# 依存: domain/feature_flag.sh, domain/cli_field.sh, domain/slot_launch_plan.sh, domain/relay_gate_clock.sh,
#       repository/feature_flag_config.sh, repository/rapid_crosscheck_env.sh, repository/parallel_run_repo.sh,
#       repository/slot_execution_repo.sh, gateway/runner_process_adapter.sh, gateway/rdb_client.sh, gateway/execution_log.sh,
#       usecase/validate_feature_flag.sh(validate_feature_flag_load_input / validate_feature_flag_collect_key_errors)、
#       usecase/validate_rapid_crosscheck.sh(validate_rapid_crosscheck_load_input)

LAUNCH_SLOTS_SCRIPT_NAME="facade.sh"
LAUNCH_SLOTS_EXIT_VALIDATION_ERROR=2
LAUNCH_SLOTS_EXIT_EXECUTION_ERROR=6
LAUNCH_SLOTS_FEATURE_FLAG_FILE="feature-flag.env"
LAUNCH_SLOTS_RAPID_CROSSCHECK_FILE="rapid-crosscheck.env"
LAUNCH_SLOTS_EXECUTION_SPEC_FILE="execution-spec.json"
LAUNCH_SLOTS_EXITCODE_FILE="exitcode.txt"

# 実行中の run の文脈(関数の間で受け渡す)
LAUNCH_SLOTS_RUN_ID=""
LAUNCH_SLOTS_CONN_REF=""
LAUNCH_SLOTS_RAPID_ACTIVE=false
LAUNCH_SLOTS_STARTED_PIDS=()

# 値を実行ログ・stderr に出す表記(制御文字を可視表記にする。空なら `-`)。結果は LAUNCH_SLOTS_SHOWN
LAUNCH_SLOTS_SHOWN=""
launch_slots_shown() {
  if [ -n "${1:-}" ]; then
    cli_field_safe_text "$1"
    LAUNCH_SLOTS_SHOWN="$CLI_FIELD_SAFE_TEXT"
  else
    LAUNCH_SLOTS_SHOWN="$FEATURE_FLAG_EMPTY_VALUE"
  fi
}

# 現在時刻のローカルの日時(管理 DB の *_at 列に渡す値)。結果は RELAY_GATE_CLOCK_TEXT
launch_slots_now_datetime() {
  relay_gate_clock_now
  relay_gate_clock_format_datetime "$RELAY_GATE_CLOCK_EPOCH"
}

# 実行ログを開く(1 回の起動で 1 回だけ。書き込めないときは stderr に warn を 1 行出して、実行ログを書かずに続ける)
LAUNCH_SLOTS_LOG_OPENED=false
launch_slots_open_log() {
  if [ "$LAUNCH_SLOTS_LOG_OPENED" = true ]; then
    return 0
  fi
  LAUNCH_SLOTS_LOG_OPENED=true
  if ! execution_log_open "$LAUNCH_SLOTS_SCRIPT_NAME" "$RELAY_GATE_LOG_DIR"; then
    launch_slots_shown "$RELAY_GATE_LOG_DIR"
    printf '%s\n' "warn: log dir is not writable path: $LAUNCH_SLOTS_SHOWN" >&2
  fi
}

# stderr に error 行を 1 行出し、同じ内容を実行ログに ERROR で残す
# 引数: message(`error: ` を除いた本文)
launch_slots_fail() {
  printf 'error: %s\n' "$1" >&2
  execution_log_write "${LAUNCH_SLOTS_RUN_ID:-$EXECUTION_LOG_NO_RUN_ID}" ERROR "$1"
}

# 引数の検証エラー(presentation が見つけたもの)を報告する: stderr に error 行(と hint)を出し、error 行を実行ログに
# run_id 未確定(`-`)の ERROR で残す
# 引数: message(`error: ` を除いた本文) [hint(`hint: ` を除いた本文)]
launch_slots_reject_arguments() {
  launch_slots_open_log
  launch_slots_fail "$1"
  if [ -n "${2:-}" ]; then
    printf 'hint: %s\n' "$2" >&2
  fi
}

# 共有の検証関数(検証コマンドと同じ関数。stderr へ直接書く)を呼び、出した行を変えずに stderr へ出してから、
# error 行を実行ログに ERROR で 1 回ずつ残す(検証コマンドは実行ログを持たないため、記録は facade の usecase だけで行う)。
# stderr は一時ファイルに受けて同じシェルの中で呼ぶ(サブシェルにしない。検証関数が載せたグローバル変数を残すため)。
# 一時ファイルを作れないときは、検証関数の出力をそのまま stderr に出し、失敗の終了コードだけを実行ログに残す
# 引数: command [args...]
# 戻り値: command の戻り値
launch_slots_validate_logging_errors() {
  local status=0 capture="" line
  if ! capture="$(mktemp "${TMPDIR:-/tmp}/relay-gate-facade-report.XXXXXX" 2>/dev/null)" || [ -z "$capture" ]; then
    "$@" || status=$?
    if [ "$status" -ne 0 ]; then
      execution_log_write "$EXECUTION_LOG_NO_RUN_ID" ERROR "config validation failed exit_code=$status"
    fi
    return "$status"
  fi
  "$@" 2>"$capture" || status=$?
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "$line" >&2
    case "$line" in
      "error: "*) execution_log_write "$EXECUTION_LOG_NO_RUN_ID" ERROR "${line#error: }" ;;
    esac
  done <"$capture"
  rm -f -- "$capture"
  return "$status"
}

# feature-flag.env を検査して読み込む(契約 config_violation_report: (i)(ii) は検証コマンドと同じく全件。(iii) は未知キーの warn 行を
# すべて出してから、検証コマンドの error 行の順で最初の違反の error 行(と続く hint)だけを出す。対応ジョブマップの所在と
# runner への --help の問い合わせは行わない)
# 引数: path config_dir verbose
# 戻り値: 0 … 違反なし(BLUE_MODE などのグローバル変数と FEATURE_FLAG_BLUE_JOB_MAP / FEATURE_FLAG_GREEN_JOB_MAP に解決済みの値)/
#         2 … 違反あり / 6 … 補助コマンドの失敗
launch_slots_load_feature_flag() {
  local path="$1" config_dir="$2" verbose="$3" shown_path status=0 collect_status=0 index
  local -a shown_keys=()
  cli_field_safe_text "$path"
  shown_path="$CLI_FIELD_SAFE_TEXT"
  validate_feature_flag_load_input "$path" "$shown_path" || return $?

  local saved_sink="$FEATURE_FLAG_REPORT_SINK"
  validate_feature_flag_collect_key_errors "$config_dir" shown_keys || collect_status=$?
  FEATURE_FLAG_REPORT_SINK="$saved_sink"
  if [ "$collect_status" -eq "$FEATURE_FLAG_EXIT_EXECUTION_ERROR" ]; then
    feature_flag_reset_report_lines
    validate_feature_flag_report_escape_failure "$shown_path"
    return "$LAUNCH_SLOTS_EXIT_EXECUTION_ERROR"
  fi
  {
    feature_flag_report_unknown_keys shown_keys
    if [ "$collect_status" -ne 0 ]; then
      feature_flag_flush_first_violation
      status="$LAUNCH_SLOTS_EXIT_VALIDATION_ERROR"
    fi
  } >&2
  feature_flag_reset_report_lines
  # --verbose の info は stderr に出さず実行ログにだけ出す(中継経路を汚さない。契約 common_options の --verbose)
  if [ "$verbose" = true ]; then
    for index in ${shown_keys[@]+"${!shown_keys[@]}"}; do
      execution_log_write "$EXECUTION_LOG_NO_RUN_ID" INFO "key loaded key=${shown_keys[index]} path: $shown_path"
    done
  fi
  return "$status"
}

# rapid-crosscheck.env の RAPID_DB_CONN_REF(管理 DB 接続の参照名)を読む(RAPID_CROSSCHECK_MODE が off 以外のときだけ呼ぶ)。
# 検査の順: 存在・読み取り → 入力の守備範囲((i)(ii))→ RAPID_DB_CONN_REF の欠落・空。読むのは参照名だけで、他のキーは検査しない
# 引数: path
# 戻り値: 0 … LAUNCH_SLOTS_CONN_REF に参照名 / 2 / 6
launch_slots_load_conn_ref() {
  local path="$1" shown_path
  cli_field_safe_text "$path"
  shown_path="$CLI_FIELD_SAFE_TEXT"
  launch_slots_validate_logging_errors validate_rapid_crosscheck_load_input "$path" "$shown_path" || return $?
  if [ -z "$RAPID_CROSSCHECK_ENV_DB_CONN_REF" ]; then
    launch_slots_fail "option required option=RAPID_DB_CONN_REF path: $shown_path"
    return "$LAUNCH_SLOTS_EXIT_VALIDATION_ERROR"
  fi
  LAUNCH_SLOTS_CONN_REF="$RAPID_CROSSCHECK_ENV_DB_CONN_REF"
  return 0
}

# 計算ルール「run_id 発行」: 起動日時(ローカル)+ job_id + 8 桁 hex 乱数(4 バイトの乱数。/dev/urandom から読む)
# 引数: job_id
# 戻り値: 0 … LAUNCH_SLOTS_RUN_ID に run_id / 1 … 乱数を読めなかった
launch_slots_issue_run_id() {
  local raw hex
  raw="$(LC_ALL=C od -An -N4 -tx1 /dev/urandom 2>/dev/null)" || return 1
  hex="${raw//[$' \t\n']/}"
  if ! slot_launch_hex8_is_valid "$hex"; then
    return 1
  fi
  relay_gate_clock_now
  relay_gate_clock_format_run_id_time "$RELAY_GATE_CLOCK_EPOCH"
  slot_launch_run_id "$RELAY_GATE_CLOCK_TEXT" "$1" "$hex"
  LAUNCH_SLOTS_RUN_ID="$SLOT_LAUNCH_RUN_ID"
}

# `INFO feature flag loaded ...` 行(off の slot の <slot>_impl は `-`。operation_mode は検証コマンドと同じ導出関数)
launch_slots_log_feature_flag_loaded() {
  local blue_impl="" green_impl="" message
  if feature_flag_mode_is_active "$BLUE_MODE"; then
    # shellcheck disable=SC2153  # feature-flag.env のキー(repository/feature_flag_config.sh が載せる)
    blue_impl="$BLUE_IMPL"
  fi
  if feature_flag_mode_is_active "$GREEN_MODE"; then
    # shellcheck disable=SC2153  # feature-flag.env のキー(repository/feature_flag_config.sh が載せる)
    green_impl="$GREEN_IMPL"
  fi
  feature_flag_resolve_operation_mode "$BLUE_MODE" "$GREEN_MODE" "$RAPID_CROSSCHECK_MODE"
  message="feature flag loaded blue_mode=$BLUE_MODE green_mode=$GREEN_MODE rapid_crosscheck_mode=$RAPID_CROSSCHECK_MODE"
  launch_slots_shown "$blue_impl"
  message+=" blue_impl=$LAUNCH_SLOTS_SHOWN"
  launch_slots_shown "$green_impl"
  message+=" green_impl=$LAUNCH_SLOTS_SHOWN operation_mode=$FEATURE_FLAG_OPERATION_MODE"
  execution_log_write "$LAUNCH_SLOTS_RUN_ID" INFO "$message"
}

# runner へ渡す環境変数を組み立てる(契約 commands の facade.sh の notes)。
# 常に RELAY_GATE_CONFIG_DIR / RELAY_GATE_ARTIFACT_ROOT / RELAY_GATE_LOG_DIR / RAPID_CROSSCHECK_MODE、off 以外は RAPID_CROSSCHECK_RUNNER
# (解決後のパス)、自 slot の <ROLE>_IMPL と <ROLE>_JOB_MAP_CSV(job_map_location で決めた場所。相手 slot の分は渡さない)。
# RELAY_GATE_HOME は渡さない。RAPID_DB_CONN_REF も渡さない(runner は off 以外のとき rapid-crosscheck.env を自分で読む)。
# feature-flag.env のキーのうち runner IF に無いもの(BLUE_MODE / GREEN_MODE / BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_WORKER)も、
# 親の環境にあっても渡さない(runner は feature-flag.env を読まない。facade が読んだ値が親の export 属性のまま渡るのを防ぐ)。
# RELAY_GATE_NOW は設定されていれば親の環境からそのまま引き継ぐ。それ以外の環境変数(PATH など)は親の環境のまま
# 引数: slot
launch_slots_build_runner_env() {
  local slot="$1"
  # shellcheck disable=SC2034  # gateway/runner_process_adapter.sh が読む
  RUNNER_PROCESS_UNSET=(RELAY_GATE_HOME RAPID_DB_CONN_REF BLUE_MODE GREEN_MODE BLUE_RUNNER GREEN_RUNNER RAPID_CROSSCHECK_WORKER
    BLUE_IMPL GREEN_IMPL BLUE_JOB_MAP_CSV GREEN_JOB_MAP_CSV RAPID_CROSSCHECK_RUNNER)
  RUNNER_PROCESS_ENV=(
    "RELAY_GATE_CONFIG_DIR=$RELAY_GATE_CONFIG_DIR"
    "RELAY_GATE_ARTIFACT_ROOT=$RELAY_GATE_ARTIFACT_ROOT"
    "RELAY_GATE_LOG_DIR=$RELAY_GATE_LOG_DIR"
    "RAPID_CROSSCHECK_MODE=$RAPID_CROSSCHECK_MODE"
  )
  if [ "$LAUNCH_SLOTS_RAPID_ACTIVE" = true ]; then
    RUNNER_PROCESS_ENV+=("RAPID_CROSSCHECK_RUNNER=$RAPID_CROSSCHECK_RUNNER")
  fi
  if [ "$slot" = blue ]; then
    RUNNER_PROCESS_ENV+=("BLUE_IMPL=$BLUE_IMPL" "BLUE_JOB_MAP_CSV=$FEATURE_FLAG_BLUE_JOB_MAP")
  else
    RUNNER_PROCESS_ENV+=("GREEN_IMPL=$GREEN_IMPL" "GREEN_JOB_MAP_CSV=$FEATURE_FLAG_GREEN_JOB_MAP")
  fi
}

# 管理 DB の書き込み失敗(runner 起動前)を報告する。接続できないときは接続失敗、それ以外は INSERT の失敗
# 引数: status(rdb_client_run の戻り値) table
launch_slots_fail_db_insert() {
  if [ "$1" -eq "$RDB_CLIENT_STATUS_CONNECTION_FAILED" ]; then
    launch_slots_shown "$LAUNCH_SLOTS_CONN_REF"
    launch_slots_fail "management db connection failed run_id=$LAUNCH_SLOTS_RUN_ID conn_ref=$LAUNCH_SLOTS_SHOWN"
  else
    launch_slots_fail "management db insert failed table=$2 run_id=$LAUNCH_SLOTS_RUN_ID"
  fi
}

# slot を 1 つ起動する(off 以外は起動前に slot_executions を pid=NULL で INSERT し、起動後に pid を UPDATE する)
# 引数: slot mode job_id [PARAM...]
# 戻り値: 0 … 起動した(LAUNCH_SLOTS_SLOT_PID に PID)/ 6 … 起動前の INSERT の失敗・runner の起動の失敗
LAUNCH_SLOTS_SLOT_PID=""
launch_slots_start_slot() {
  local slot="$1" mode="$2" job_id="$3" artifact_dir runner status=0 pids
  shift 3
  artifact_dir="$(slot_launch_artifact_dir "$RELAY_GATE_ARTIFACT_ROOT" "$LAUNCH_SLOTS_RUN_ID" "$slot")/"
  if [ "$slot" = blue ]; then
    runner="$BLUE_RUNNER"
  else
    runner="$GREEN_RUNNER"
  fi
  if [ "$LAUNCH_SLOTS_RAPID_ACTIVE" = true ]; then
    launch_slots_now_datetime
    slot_execution_repo_create "$LAUNCH_SLOTS_CONN_REF" "$LAUNCH_SLOTS_RUN_ID" "$slot" "$mode" "$artifact_dir" "$RELAY_GATE_CLOCK_TEXT" || status=$?
    if [ "$status" -ne 0 ]; then
      launch_slots_fail_db_insert "$status" slot_executions
      return "$LAUNCH_SLOTS_EXIT_EXECUTION_ERROR"
    fi
  fi
  launch_slots_build_runner_env "$slot"
  if ! runner_process_adapter_launch "$runner" "$LAUNCH_SLOTS_RUN_ID" "$job_id" "$slot" "$mode" "$@"; then
    launch_slots_shown "$runner"
    printf '%s\n' "error: runner failed to start run_id=$LAUNCH_SLOTS_RUN_ID role=$slot runner=$LAUNCH_SLOTS_SHOWN" >&2
    # 起動済みの background runner は止めずに続けさせ、実行ログに起動済みの PID を残す
    pids="${LAUNCH_SLOTS_STARTED_PIDS[*]-}"
    execution_log_write "$LAUNCH_SLOTS_RUN_ID" ERROR "runner failed to start run_id=$LAUNCH_SLOTS_RUN_ID role=$slot runner=$LAUNCH_SLOTS_SHOWN started_pids=${pids:-$FEATURE_FLAG_EMPTY_VALUE}"
    if [ "$LAUNCH_SLOTS_RAPID_ACTIVE" = true ]; then
      launch_slots_now_datetime
      if ! slot_execution_repo_mark_failed "$LAUNCH_SLOTS_CONN_REF" "$LAUNCH_SLOTS_RUN_ID" "$slot" "$RELAY_GATE_CLOCK_TEXT"; then
        execution_log_write "$LAUNCH_SLOTS_RUN_ID" ERROR "management db update failed table=slot_executions run_id=$LAUNCH_SLOTS_RUN_ID"
      fi
    fi
    return "$LAUNCH_SLOTS_EXIT_EXECUTION_ERROR"
  fi
  LAUNCH_SLOTS_SLOT_PID="$RUNNER_PROCESS_PID"
  LAUNCH_SLOTS_STARTED_PIDS+=("$LAUNCH_SLOTS_SLOT_PID")
  if [ "$mode" = "$FEATURE_FLAG_MODE_BACKGROUND" ]; then
    runner_process_adapter_detach "$LAUNCH_SLOTS_SLOT_PID"
  fi
  execution_log_write "$LAUNCH_SLOTS_RUN_ID" INFO "slot started slot=$slot mode=$mode pid=$LAUNCH_SLOTS_SLOT_PID"
  # 起動後の pid の UPDATE の失敗(0 件を含む)は、runner が起動済みのため実行ログ ERROR だけにする(終了コードは変えない)
  if [ "$LAUNCH_SLOTS_RAPID_ACTIVE" = true ] \
    && ! slot_execution_repo_set_pid "$LAUNCH_SLOTS_CONN_REF" "$LAUNCH_SLOTS_RUN_ID" "$slot" "$LAUNCH_SLOTS_SLOT_PID"; then
    execution_log_write "$LAUNCH_SLOTS_RUN_ID" ERROR "management db update failed table=slot_executions run_id=$LAUNCH_SLOTS_RUN_ID"
  fi
  return 0
}

# foreground の exitcode.txt の値(0〜255 の数値 1 行)を LAUNCH_SLOTS_FOREGROUND_EXIT_CODE に載せる
# 引数: artifact_dir
# 戻り値: 0 … 読めた / 1 … 無い・数値でない
LAUNCH_SLOTS_FOREGROUND_EXIT_CODE=""
launch_slots_read_exit_code() {
  local file="$1/$LAUNCH_SLOTS_EXITCODE_FILE" value=""
  LAUNCH_SLOTS_FOREGROUND_EXIT_CODE=""
  # 読めないときのエラーも stderr に出さない(foreground の起動後は stderr を汚さない。リダイレクトは 2>/dev/null を先に置く)
  if [ ! -f "$file" ] || ! IFS= read -r value 2>/dev/null <"$file"; then
    if [ -z "$value" ]; then
      return 1
    fi
  fi
  if [ "${LC_ALL:-}" != C ]; then
    local LC_ALL=C
  fi
  if [[ ! "$value" =~ ^[0-9]{1,3}$ ]] || [ $((10#$value)) -gt 255 ]; then
    return 1
  fi
  LAUNCH_SLOTS_FOREGROUND_EXIT_CODE=$((10#$value))
}

# LaunchSlotsCommand
# 引数: verbose(true|false) job_id [PARAM...]
# 戻り値: foreground の exitcode.txt の値 / 2(入力・設定の検証エラー。runner を起動しない)/ 6(実行エラー)
launch_slots() {
  local verbose="$1" job_id="$2" status=0 slot run_dir artifact_dir foreground_pid
  shift 2
  local config_dir="$RELAY_GATE_CONFIG_DIR"
  LAUNCH_SLOTS_RUN_ID=""
  LAUNCH_SLOTS_CONN_REF=""
  LAUNCH_SLOTS_RAPID_ACTIVE=false
  LAUNCH_SLOTS_STARTED_PIDS=()

  launch_slots_open_log

  # バリデーション(runner を 1 つも起動する前にすべて実施。検証 NG なら run_id を発行せず成果物ディレクトリも作らない)。
  # 検証エラーは stderr に加えて実行ログに run_id 未確定(`-`)の ERROR で 1 回だけ残す(エラーハンドリング CLR-001)
  launch_slots_validate_logging_errors launch_slots_load_feature_flag "$config_dir/$LAUNCH_SLOTS_FEATURE_FLAG_FILE" "$config_dir" "$verbose" || return $?
  plan_slot_launch "$BLUE_MODE" "$GREEN_MODE"
  # 条件「速報クロスチェック有効判定」: off か off 以外か(foreground と background は同じ挙動)。off では rapid-crosscheck.env を読まない
  if feature_flag_mode_is_active "$RAPID_CROSSCHECK_MODE"; then
    LAUNCH_SLOTS_RAPID_ACTIVE=true
    launch_slots_load_conn_ref "$config_dir/$LAUNCH_SLOTS_RAPID_CROSSCHECK_FILE" || return $?
  fi
  if ! relay_gate_clock_injection_is_valid; then
    launch_slots_shown "$RELAY_GATE_NOW"
    launch_slots_fail "invalid value env=$RELAY_GATE_CLOCK_ENV value=$LAUNCH_SLOTS_SHOWN"
    return "$LAUNCH_SLOTS_EXIT_VALIDATION_ERROR"
  fi

  # 1. run_id の発行(RAPID_CROSSCHECK_MODE によらず常に)と、run ディレクトリ・起動対象 role のディレクトリの作成
  if ! launch_slots_issue_run_id "$job_id"; then
    launch_slots_fail "run_id issue failed job_id=$job_id"
    return "$LAUNCH_SLOTS_EXIT_EXECUTION_ERROR"
  fi
  if [ -n "${RELAY_GATE_NOW:-}" ]; then
    execution_log_write "$LAUNCH_SLOTS_RUN_ID" WARN "test clock injected now=$RELAY_GATE_NOW"
  fi
  launch_slots_log_feature_flag_loaded
  execution_log_write "$LAUNCH_SLOTS_RUN_ID" INFO "run started run_id=$LAUNCH_SLOTS_RUN_ID job_id=$job_id"
  run_dir="$(slot_launch_artifact_dir "$RELAY_GATE_ARTIFACT_ROOT" "$LAUNCH_SLOTS_RUN_ID")"
  if ! mkdir -p -- "$run_dir" 2>/dev/null; then
    launch_slots_shown "$run_dir"
    launch_slots_fail "artifact dir create failed run_id=$LAUNCH_SLOTS_RUN_ID path: $LAUNCH_SLOTS_SHOWN"
    return "$LAUNCH_SLOTS_EXIT_EXECUTION_ERROR"
  fi
  for slot in ${SLOT_LAUNCH_PLAN_ORDER[@]+"${SLOT_LAUNCH_PLAN_ORDER[@]}"}; do
    artifact_dir="$run_dir/$slot"
    if ! mkdir -- "$artifact_dir" 2>/dev/null && [ ! -d "$artifact_dir" ]; then
      launch_slots_shown "$artifact_dir"
      launch_slots_fail "artifact dir create failed run_id=$LAUNCH_SLOTS_RUN_ID path: $LAUNCH_SLOTS_SHOWN"
      return "$LAUNCH_SLOTS_EXIT_EXECUTION_ERROR"
    fi
  done

  # 2. off 以外: parallel_runs(STARTED)と rapid_runs(PENDING)を同一トランザクションで INSERT。失敗したら runner を起動しない
  if [ "$LAUNCH_SLOTS_RAPID_ACTIVE" = true ]; then
    slot_launch_parameters_json "$@"
    launch_slots_now_datetime
    parallel_run_repo_create_with_rapid_run "$LAUNCH_SLOTS_CONN_REF" "$LAUNCH_SLOTS_RUN_ID" "$job_id" "$SLOT_LAUNCH_PARAMETERS_JSON" \
      "$run_dir/$LAUNCH_SLOTS_EXECUTION_SPEC_FILE" "$RELAY_GATE_CLOCK_TEXT" || status=$?
    if [ "$status" -ne 0 ]; then
      launch_slots_fail_db_insert "$status" "$PARALLEL_RUN_REPO_FAILED_TABLE"
      return "$LAUNCH_SLOTS_EXIT_EXECUTION_ERROR"
    fi
  fi

  # 3〜4. background の slot をすべて起動してから foreground の slot を起動する(条件「slot 起動順序」)
  for slot in ${SLOT_LAUNCH_PLAN_ORDER[@]+"${SLOT_LAUNCH_PLAN_ORDER[@]}"}; do
    launch_slots_start_slot "$slot" "$(slot_launch_plan_mode_of "$slot")" "$job_id" "$@" || return $?
    if [ "$slot" = "$SLOT_LAUNCH_PLAN_FOREGROUND" ]; then
      foreground_pid="$LAUNCH_SLOTS_SLOT_PID"
    fi
  done

  # 5. off 以外: parallel_runs を STARTED → RUNNING(条件付き UPDATE)。失敗は runner 起動済みのため実行ログ ERROR だけ。
  #    条件に合う行が無く 0 件だったときも遷移していないため INFO(status changed)を書かず、同じ ERROR を残す
  if [ "$LAUNCH_SLOTS_RAPID_ACTIVE" = true ]; then
    if parallel_run_repo_mark_running "$LAUNCH_SLOTS_CONN_REF" "$LAUNCH_SLOTS_RUN_ID"; then
      execution_log_write "$LAUNCH_SLOTS_RUN_ID" INFO "parallel_run status changed from=STARTED to=RUNNING run_id=$LAUNCH_SLOTS_RUN_ID"
    else
      execution_log_write "$LAUNCH_SLOTS_RUN_ID" ERROR "management db update failed table=parallel_runs run_id=$LAUNCH_SLOTS_RUN_ID"
    fi
  fi

  # 6. foreground の PID だけを待つ(background は待たない)
  execution_log_write "$LAUNCH_SLOTS_RUN_ID" INFO "waiting foreground slot=$SLOT_LAUNCH_PLAN_FOREGROUND pid=$foreground_pid"
  runner_process_adapter_wait "$foreground_pid" || true
  artifact_dir="$run_dir/$SLOT_LAUNCH_PLAN_FOREGROUND"
  if ! launch_slots_read_exit_code "$artifact_dir"; then
    # foreground の起動後は stderr を汚さない(実行ログ ERROR だけ)
    launch_slots_shown "$artifact_dir/$LAUNCH_SLOTS_EXITCODE_FILE"
    execution_log_write "$LAUNCH_SLOTS_RUN_ID" ERROR "foreground exit code not available slot=$SLOT_LAUNCH_PLAN_FOREGROUND path: $LAUNCH_SLOTS_SHOWN"
    return "$LAUNCH_SLOTS_EXIT_EXECUTION_ERROR"
  fi
  execution_log_write "$LAUNCH_SLOTS_RUN_ID" INFO "foreground finished slot=$SLOT_LAUNCH_PLAN_FOREGROUND exit_code=$LAUNCH_SLOTS_FOREGROUND_EXIT_CODE"
  return "$LAUNCH_SLOTS_FOREGROUND_EXIT_CODE"
}
