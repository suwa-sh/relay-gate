#!/usr/bin/env bash
# presentation: facade.sh(JobLaunchRequest)。
# 書式: facade.sh [--verbose] [--help] JOB_ID [PARAM...]
# 仕様: docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/tier-facade.md
#       「コマンド契約」(引数・オプション)「出力契約」/ _cross-cutting/api/cli-command-contract.yaml commands の facade.sh
#       (option_placement: オプションは JOB_ID より前にだけ置ける。JOB_ID 以降はすべて PARAM として runner へ渡す)
# 終了コード: foreground の exitcode.txt の値 / 2 入力・設定の検証エラー / 6 実行エラー(1 は set -e の予期しない終了として区別する)
# stdout: facade 自身は出力しない(--help を除く)
# 引数の検証エラーは usecase の launch_slots_reject_arguments で stderr と実行ログ(run_id 未確定の `-`)に出す
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

FACADE_SCRIPT_NAME="facade.sh"
FACADE_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 既定の置き場(契約 conventions.environment_variables。RELAY_GATE_HOME の既定はスクリプト自身のディレクトリ。
# bin/ の入口から起動される場合は入口が設定する)
RELAY_GATE_HOME="${RELAY_GATE_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
RELAY_GATE_CONFIG_DIR="${RELAY_GATE_CONFIG_DIR:-$RELAY_GATE_HOME/config}"
RELAY_GATE_ARTIFACT_ROOT="${RELAY_GATE_ARTIFACT_ROOT:-$RELAY_GATE_HOME/var}"
RELAY_GATE_LOG_DIR="${RELAY_GATE_LOG_DIR:-$RELAY_GATE_HOME/log}"
export RELAY_GATE_HOME RELAY_GATE_CONFIG_DIR RELAY_GATE_ARTIFACT_ROOT RELAY_GATE_LOG_DIR

# shellcheck source=../domain/cli_field.sh
source "$FACADE_SRC_DIR/domain/cli_field.sh"
# shellcheck source=../domain/feature_flag.sh
source "$FACADE_SRC_DIR/domain/feature_flag.sh"
# shellcheck source=../domain/job_map.sh
source "$FACADE_SRC_DIR/domain/job_map.sh"
# shellcheck source=../domain/relay_gate_clock.sh
source "$FACADE_SRC_DIR/domain/relay_gate_clock.sh"
# shellcheck source=../domain/slot_launch_plan.sh
source "$FACADE_SRC_DIR/domain/slot_launch_plan.sh"
# shellcheck source=../repository/job_map_repo.sh
source "$FACADE_SRC_DIR/repository/job_map_repo.sh"
# shellcheck source=../repository/feature_flag_config.sh
source "$FACADE_SRC_DIR/repository/feature_flag_config.sh"
# shellcheck source=../repository/rapid_crosscheck_env.sh
source "$FACADE_SRC_DIR/repository/rapid_crosscheck_env.sh"
# shellcheck source=../gateway/rdb_client.sh
source "$FACADE_SRC_DIR/gateway/rdb_client.sh"
# shellcheck source=../repository/parallel_run_repo.sh
source "$FACADE_SRC_DIR/repository/parallel_run_repo.sh"
# shellcheck source=../repository/slot_execution_repo.sh
source "$FACADE_SRC_DIR/repository/slot_execution_repo.sh"
# shellcheck source=../gateway/runner_process_adapter.sh
source "$FACADE_SRC_DIR/gateway/runner_process_adapter.sh"
# shellcheck source=../gateway/execution_log.sh
source "$FACADE_SRC_DIR/gateway/execution_log.sh"
# shellcheck source=../gateway/filesystem_adapter.sh
source "$FACADE_SRC_DIR/gateway/filesystem_adapter.sh"
# shellcheck source=../usecase/validate_job_map.sh
source "$FACADE_SRC_DIR/usecase/validate_job_map.sh"
# shellcheck source=../usecase/validate_feature_flag.sh
source "$FACADE_SRC_DIR/usecase/validate_feature_flag.sh"
# shellcheck source=../usecase/validate_rapid_crosscheck.sh
source "$FACADE_SRC_DIR/usecase/validate_rapid_crosscheck.sh"
# shellcheck source=../usecase/launch_slots.sh
source "$FACADE_SRC_DIR/usecase/launch_slots.sh"

facade_usage() {
  cat <<USAGE
usage: $FACADE_SCRIPT_NAME [--verbose] [--help] JOB_ID [PARAM...]

arguments:
  JOB_ID      business job id (letters, digits, _ and - only)
  PARAM...    passed to the slot runners after -- in the same order

options (only before JOB_ID):
  --verbose   write info lines to the execution log (not to stderr)
  --help      print this usage and exit 0

exit codes:
  foreground slot exitcode.txt value  relayed result
  2  invalid arguments / config validation error (no runner started)
  6  execution error
USAGE
}

facade_main() {
  local verbose=false
  # オプションは JOB_ID より前にだけ置ける(最初の `--` 始まりでない引数が JOB_ID。それ以降はすべて PARAM)
  while [ $# -gt 0 ]; do
    case "$1" in
      --help)
        facade_usage
        return 0
        ;;
      --verbose)
        verbose=true
        shift
        ;;
      --*)
        cli_field_safe_text "$1"
        launch_slots_reject_arguments "unknown option option=$CLI_FIELD_SAFE_TEXT"
        return "$LAUNCH_SLOTS_EXIT_VALIDATION_ERROR"
        ;;
      *) break ;;
    esac
  done

  if [ $# -eq 0 ] || [ -z "$1" ]; then
    launch_slots_reject_arguments "JOB_ID required" "usage: $FACADE_SCRIPT_NAME JOB_ID [PARAM...]"
    return "$LAUNCH_SLOTS_EXIT_VALIDATION_ERROR"
  fi
  if ! slot_launch_job_id_is_valid "$1"; then
    cli_field_safe_text "$1"
    launch_slots_reject_arguments "invalid value key=JOB_ID value=$CLI_FIELD_SAFE_TEXT"
    return "$LAUNCH_SLOTS_EXIT_VALIDATION_ERROR"
  fi

  launch_slots "$verbose" "$@"
}

facade_status=0
facade_main "$@" || facade_status=$?
exit "$facade_status"
