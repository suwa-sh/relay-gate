# shellcheck shell=bash
# presentation: 標準の slot runner(runners/standard-runner.sh)の本体。
# 仕様: cli-command-contract.yaml commands「$BLUE_RUNNER / $GREEN_RUNNER」(runner IF version = 1 / --help / options / exit_codes / standard_runner)
# UC「slot runner の実体スクリプトを割り当てる」の範囲は --help の応答と runner IF の引数の受理まで。ジョブマップ解決・
# execution-spec 保存・実装の実行・Runner Result 公開(exitcode.txt を含む)・完了通知は後続の UC が lib/runner-*.sh とあわせて実装する。

STANDARD_RUNNER_NAME="standard-runner.sh"
# 現在の runner IF 版(契約 invoked_by の「runner IF version = 1」)
STANDARD_RUNNER_IF_VERSION=1
# runner IF 引数不正(契約 exit_codes の 2)
STANDARD_RUNNER_EXIT_INVALID_ARGUMENT=2
# 引数が正しい起動の終了コード。後続 UC が runner IF の処理を実装するまでの仮置き(前提 A-004)
STANDARD_RUNNER_EXIT_NOT_AVAILABLE=6

standard_runner_usage() {
  printf '%s\n' \
    "usage: $STANDARD_RUNNER_NAME --run-id <run_id> --job-id <JOB_ID> --role blue|green --mode foreground|background [--execution-spec <path>] [--help] -- [PARAM...]" \
    "runner-if-version=$STANDARD_RUNNER_IF_VERSION"
}

# `--` より前に --help があれば 0(前提 A-003)
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

# runner IF の引数(契約 options)を検査する。必須オプションの欠落・空の値・値の欠落・列挙外・未知のオプション・
# --execution-spec と PARAM の併用(契約 args の「--execution-spec 指定時は受け付けない」)は 1
standard_runner_arguments_valid() {
  local run_id="" job_id="" role="" mode="" execution_spec_given=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --)
        shift
        if [ "$execution_spec_given" = true ] && [ "$#" -gt 0 ]; then
          return 1
        fi
        break
        ;;
      --run-id | --job-id | --role | --mode | --execution-spec)
        # 値の欠落と空の値は引数不足(契約 exit_codes の 2。空の --execution-spec は「spec なし」)
        if [ "$#" -lt 2 ] || [ -z "$2" ]; then
          return 1
        fi
        case "$1" in
          --run-id) run_id="$2" ;;
          --job-id) job_id="$2" ;;
          --role) role="$2" ;;
          --mode) mode="$2" ;;
          --execution-spec) execution_spec_given=true ;;
        esac
        shift 2
        ;;
      *)
        return 1
        ;;
    esac
  done
  # 必須オプションの欠落(値の空は上で拒否済み)
  [ -n "$run_id" ] && [ -n "$job_id" ] || return 1
  case "$role" in blue | green) ;; *) return 1 ;; esac
  case "$mode" in foreground | background) ;; *) return 1 ;; esac
}

# 何も出力しない(runner は stdout / stderr に出さない。Runner Result の不変条件 (3))。
# 引数不正は 2、引数が正しければ仮置きの終了コードで終える(exitcode.txt の公開は後続 UC。前提 A-004)
standard_runner_main() {
  if standard_runner_help_requested "$@"; then
    standard_runner_usage
    return 0
  fi
  if ! standard_runner_arguments_valid "$@"; then
    return "$STANDARD_RUNNER_EXIT_INVALID_ARGUMENT"
  fi
  return "$STANDARD_RUNNER_EXIT_NOT_AVAILABLE"
}
