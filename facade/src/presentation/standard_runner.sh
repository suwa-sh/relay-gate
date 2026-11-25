# shellcheck shell=bash source-path=SCRIPTDIR
# presentation: 標準の slot runner(runners/standard-runner.sh)の本体(RunnerInvocation)。
# 仕様: cli-command-contract.yaml commands「$BLUE_RUNNER / $GREEN_RUNNER」(runner IF version = 1 / --help / options / exit_codes / standard_runner)/
#       UC「ジョブマップで JOB_ID から実行先を解決する」tier-facade.md「コマンド契約」「出力契約」
# ここまでの範囲: --help の応答、runner IF の引数の検査、解決フェーズ(共通ライブラリ lib/runner-resolve.sh)。
# execution-spec 保存・実装の実行・Runner Result 公開(成功時の exitcode.txt)・完了通知・復元起動(--execution-spec)は
# 後続の UC が lib/runner-*.sh とあわせて実装する。
# プロセスの stdout / stderr には何も出さない(--help を除く。Runner Result の不変条件 (3))。

STANDARD_RUNNER_NAME="standard-runner.sh"
# 現在の runner IF 版(契約 invoked_by の「runner IF version = 1」)
STANDARD_RUNNER_IF_VERSION=1
# runner IF 引数不正(契約 exit_codes の 2)
STANDARD_RUNNER_EXIT_INVALID_ARGUMENT=2
# 解決フェーズの後に続く段(execution-spec 保存・実装の実行)がまだ無い間の終了コード。後続 UC が実装するまでの仮置き
# (exitcode.txt は書かない。前提は AssumptionRecord に記録)
STANDARD_RUNNER_EXIT_NOT_AVAILABLE=6
# 配置ディレクトリ(契約 standard_runner.home: 起動されたパスの字面の runners/ の 1 つ上。入口がこのファイルを読んだパスから決める。
# 環境変数 RELAY_GATE_HOME は使わない)
STANDARD_RUNNER_HOME="${BASH_SOURCE[0]%/src/presentation/*}"

# 共通ライブラリは配置ディレクトリの lib/ から読む(契約 standard_runner.home)
# shellcheck source=../../lib/runner-resolve.sh
source "$STANDARD_RUNNER_HOME/lib/runner-resolve.sh"

standard_runner_usage() {
  printf '%s\n' \
    "usage: $STANDARD_RUNNER_NAME --run-id <run_id> --job-id <JOB_ID> --role blue|green --mode foreground|background [--execution-spec <path>] [--help] -- [PARAM...]" \
    "runner-if-version=$STANDARD_RUNNER_IF_VERSION"
}

# `--` より前に --help があれば 0
standard_runner_help_requested() {
  local arg
  for arg in "$@"; do
    if [ "$arg" = "--" ]; then
      return 1
    fi
    if [ "$arg" = "--help" ]; then
      return 0
    fi
  done
  return 1
}

# standard_runner_parse_arguments の結果(RunnerInvocation)
STANDARD_RUNNER_RUN_ID=""
STANDARD_RUNNER_JOB_ID=""
STANDARD_RUNNER_ROLE=""
STANDARD_RUNNER_MODE=""
STANDARD_RUNNER_EXECUTION_SPEC_GIVEN=false
STANDARD_RUNNER_PARAMS=()
# 引数の違反(最初の 1 件。`error: ` を除いた本文)。復元起動(--execution-spec)に関する違反は後続 UC が文言を決めるため空のまま
STANDARD_RUNNER_ARGUMENT_ERROR=""

# 最初の違反だけを控える
standard_runner_note_error() {
  if [ -z "$STANDARD_RUNNER_ARGUMENT_ERROR" ]; then
    STANDARD_RUNNER_ARGUMENT_ERROR="$1"
  fi
}

# runner IF の引数(契約 options)を読んで検査する。違反は 1(必須オプションの欠落・空の値・値の欠落・列挙外・未知のオプション・
# --execution-spec と PARAM の併用(契約 args の「--execution-spec 指定時は受け付けない」))。`--` 以降はすべて PARAM として順序を保つ
# 戻り値: 0 … 正しい(STANDARD_RUNNER_* に値)/ 1 … 違反(STANDARD_RUNNER_ARGUMENT_ERROR に最初の違反。復元起動に関する違反は空)
standard_runner_parse_arguments() {
  local valid=true option
  STANDARD_RUNNER_RUN_ID=""
  STANDARD_RUNNER_JOB_ID=""
  STANDARD_RUNNER_ROLE=""
  STANDARD_RUNNER_MODE=""
  STANDARD_RUNNER_EXECUTION_SPEC_GIVEN=false
  STANDARD_RUNNER_PARAMS=()
  STANDARD_RUNNER_ARGUMENT_ERROR=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --)
        shift
        STANDARD_RUNNER_PARAMS=("$@")
        break
        ;;
      --run-id | --job-id | --role | --mode | --execution-spec)
        # 値の欠落と空の値は引数不足(契約 exit_codes の 2。空の --execution-spec は「spec なし」で、文言は後続 UC)
        if [ "$#" -lt 2 ] || [ -z "$2" ]; then
          valid=false
          if [ "$1" != "--execution-spec" ]; then
            standard_runner_note_error "option required option=$1"
          fi
          if [ "$#" -lt 2 ]; then
            break
          fi
          shift 2
          continue
        fi
        case "$1" in
          --run-id) STANDARD_RUNNER_RUN_ID="$2" ;;
          --job-id) STANDARD_RUNNER_JOB_ID="$2" ;;
          --role) STANDARD_RUNNER_ROLE="$2" ;;
          --mode) STANDARD_RUNNER_MODE="$2" ;;
          --execution-spec) STANDARD_RUNNER_EXECUTION_SPEC_GIVEN=true ;;
        esac
        shift 2
        ;;
      *)
        # 未知のオプション(契約 conventions.option_style)。値を取るかどうか分からないため、ここで読むのをやめる
        valid=false
        cli_field_safe_text "$1"
        standard_runner_note_error "unknown option option=$CLI_FIELD_SAFE_TEXT"
        break
        ;;
    esac
  done
  if [ "$valid" = false ]; then
    return 1
  fi
  # 必須オプションの欠落(値の空は上で拒否済み。書式の並びの順に最初の 1 件)
  for option in run-id job-id role mode; do
    case "$option" in
      run-id) [ -n "$STANDARD_RUNNER_RUN_ID" ] && continue ;;
      job-id) [ -n "$STANDARD_RUNNER_JOB_ID" ] && continue ;;
      role) [ -n "$STANDARD_RUNNER_ROLE" ] && continue ;;
      mode) [ -n "$STANDARD_RUNNER_MODE" ] && continue ;;
    esac
    standard_runner_note_error "option required option=--$option"
    return 1
  done
  case "$STANDARD_RUNNER_ROLE" in
    blue | green) ;;
    *)
      cli_field_safe_text "$STANDARD_RUNNER_ROLE"
      standard_runner_note_error "invalid value option=--role value=$CLI_FIELD_SAFE_TEXT"
      return 1
      ;;
  esac
  case "$STANDARD_RUNNER_MODE" in
    foreground | background) ;;
    *)
      cli_field_safe_text "$STANDARD_RUNNER_MODE"
      standard_runner_note_error "invalid value option=--mode value=$CLI_FIELD_SAFE_TEXT"
      return 1
      ;;
  esac
  if [ "$STANDARD_RUNNER_EXECUTION_SPEC_GIVEN" = true ] && [ "${#STANDARD_RUNNER_PARAMS[@]}" -gt 0 ]; then
    return 1
  fi
  return 0
}

# 戻り値: 0(--help)/ 2(runner IF の引数の違反・解決の検証エラー)/ 6(実行エラー。解決に成功した後は仮置きの終了コード)/
#         既存の exitcode.txt の値(同じ run_id / role の結果が公開済みの二重起動)/ 6(中止済みの slot での再起動。exitcode.txt は書かない)
standard_runner_main() {
  local status=0
  if standard_runner_help_requested "$@"; then
    standard_runner_usage
    return 0
  fi
  # facade.sh を介さない起動では、設定・成果物・実行ログの置き場の既定を配置ディレクトリから決める(契約 standard_runner.home)
  RELAY_GATE_CONFIG_DIR="${RELAY_GATE_CONFIG_DIR:-$STANDARD_RUNNER_HOME/config}"
  RELAY_GATE_ARTIFACT_ROOT="${RELAY_GATE_ARTIFACT_ROOT:-$STANDARD_RUNNER_HOME/var}"
  RELAY_GATE_LOG_DIR="${RELAY_GATE_LOG_DIR:-$STANDARD_RUNNER_HOME/log}"

  if ! standard_runner_parse_arguments "$@"; then
    # 復元起動(--execution-spec)に関する違反は、後続 UC が実装するまで何も書かずに 2 で終える
    if [ -z "$STANDARD_RUNNER_ARGUMENT_ERROR" ]; then
      return "$STANDARD_RUNNER_EXIT_INVALID_ARGUMENT"
    fi
    # 終了コードは RUNNER_RESOLVE_EXIT_CODE(二重起動なら既存の exitcode.txt の値。関数の戻り値は常に非 0)
    runner_resolve_reject_invocation "$STANDARD_RUNNER_NAME" "$STANDARD_RUNNER_RUN_ID" "$STANDARD_RUNNER_ROLE" \
      "$STANDARD_RUNNER_ARGUMENT_ERROR" || true
    return "$RUNNER_RESOLVE_EXIT_CODE"
  fi
  # 復元起動はジョブマップを読まない(UC「実装スクリプトを実行して Runner Result を出力する」が実装するまで仮置きの終了コード)
  if [ "$STANDARD_RUNNER_EXECUTION_SPEC_GIVEN" = true ]; then
    return "$STANDARD_RUNNER_EXIT_NOT_AVAILABLE"
  fi

  resolve_execution_target "$STANDARD_RUNNER_NAME" "$STANDARD_RUNNER_RUN_ID" "$STANDARD_RUNNER_JOB_ID" "$STANDARD_RUNNER_ROLE" \
    ${STANDARD_RUNNER_PARAMS[@]+"${STANDARD_RUNNER_PARAMS[@]}"} || status=$?
  # 解決しなかった(戻り値が非 0)ときは、実装を実行せず RUNNER_RESOLVE_EXIT_CODE で終える。同じ run_id / role の exitcode.txt が
  # 既にあった二重起動では既存の値(0 を含む)になり、プロセスの終了コードが exitcode.txt と一致する(契約 runner IF の idempotency)
  if [ "$status" -ne 0 ]; then
    return "$RUNNER_RESOLVE_EXIT_CODE"
  fi
  # 解決に成功した回も、後続の段へ進む前に二重起動を確かめる(契約 runner IF の idempotency: exitcode.txt が既にあれば既存の値、
  # exitcode.txt が無く aborted.txt がある中止済みの slot は `WARN slot already aborted` で 6。どちらも成果物に触れない)
  if ! runner_resolve_guard_existing_result "$STANDARD_RUNNER_RUN_ID" "$STANDARD_RUNNER_ROLE"; then
    return "$RUNNER_RESOLVE_EXIT_CODE"
  fi
  # 解決した ExecutionTarget と ARGUMENT_LIST を使う段(execution-spec 保存・実装の実行)は後続 UC
  return "$STANDARD_RUNNER_EXIT_NOT_AVAILABLE"
}
