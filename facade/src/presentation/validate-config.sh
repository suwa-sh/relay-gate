#!/usr/bin/env bash
# presentation: validate-config.sh(ValidateConfigRequest)。
# 書式: validate-config.sh (--feature-flag <path> | --job-map <path> | --crosscheck-job-map <path> | --target-catalog <path>) [--verbose] [--help]
# 仕様: _cross-cutting/api/cli-command-contract.yaml commands[validate-config.sh](検証種別オプションはちょうど 1 つ)、
#       _cross-cutting/ux-ui/ui-design.md 共通オプション(`--key value` 形式 / 未知オプションは終了コード 2 / --help)
# 終了コード: 0 検証 OK / 2 引数不正・ファイルなし・検証違反 / 6 実行エラー(runner --help 問い合わせの準備失敗。
#             契約 runner_help_probe.preparation_failure。1 は set -e の予期しない終了として区別する)
# 検証種別ごとの usecase は `validate_config_<kind>` 関数へ委譲する(--feature-flag は本 UC。他は所有 UC が追加する)
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

VALIDATE_CONFIG_SCRIPT_NAME="validate-config.sh"
VALIDATE_CONFIG_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# RELAY_GATE_HOME の既定はスクリプト自身のディレクトリ(bin/ の wrapper から起動される場合は wrapper が設定する)
RELAY_GATE_HOME="${RELAY_GATE_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
RELAY_GATE_CONFIG_DIR="${RELAY_GATE_CONFIG_DIR:-$RELAY_GATE_HOME/config}"
export RELAY_GATE_HOME RELAY_GATE_CONFIG_DIR

# shellcheck source=../domain/feature_flag.sh
source "$VALIDATE_CONFIG_SRC_DIR/domain/feature_flag.sh"
# shellcheck source=../domain/cli_field.sh
source "$VALIDATE_CONFIG_SRC_DIR/domain/cli_field.sh"
# shellcheck source=../repository/feature_flag_config.sh
source "$VALIDATE_CONFIG_SRC_DIR/repository/feature_flag_config.sh"
# shellcheck source=../gateway/runner_probe.sh
source "$VALIDATE_CONFIG_SRC_DIR/gateway/runner_probe.sh"
# shellcheck source=../usecase/validate_feature_flag.sh
source "$VALIDATE_CONFIG_SRC_DIR/usecase/validate_feature_flag.sh"

VALIDATE_CONFIG_KIND_OPTIONS="--feature-flag|--job-map|--crosscheck-job-map|--target-catalog"

validate_config_usage() {
  cat <<USAGE
usage: $VALIDATE_CONFIG_SCRIPT_NAME (--feature-flag <path> | --job-map <path> | --crosscheck-job-map <path> | --target-catalog <path>) [--verbose] [--help]

options:
  --feature-flag <path>         validate a feature flag env file (exactly one validation option is required)
  --job-map <path>              validate a slot job map CSV
  --crosscheck-job-map <path>   validate a crosscheck job map CSV
  --target-catalog <path>       validate a target catalog CSV
  --verbose                     print info: lines to stderr
  --help                        print this usage and exit 0

exit codes:
  0  validation ok
  2  invalid arguments / config file not found / validation error
  6  execution error (runner --help probe could not be prepared)
USAGE
}

# --feature-flag の usecase 委譲(本 UC「feature flag を設定する」)
validate_config_feature_flag() {
  local path="$1" verbose="$2"
  validate_feature_flag_query "$path" "$RELAY_GATE_CONFIG_DIR" "$verbose"
}

validate_config_main() {
  local kinds=() kind="" path="" verbose=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --help)
        validate_config_usage
        return 0
        ;;
      --verbose)
        verbose=true
        shift
        ;;
      --feature-flag | --job-map | --crosscheck-job-map | --target-catalog)
        if [ $# -lt 2 ] || [[ "$2" == --* ]]; then
          printf '%s\n' "error: option required option=$1" >&2
          return 2
        fi
        kinds+=("$1")
        kind="${1#--}"
        path="$2"
        shift 2
        ;;
      --*)
        printf '%s\n' "error: unknown option option=$1" >&2
        return 2
        ;;
      *)
        printf '%s\n' "error: unexpected argument value=$1" >&2
        return 2
        ;;
    esac
  done

  # 検証種別オプションはちょうど 1 つ(0 個・2 個以上は終了コード 2)
  if [ "${#kinds[@]}" -eq 0 ]; then
    printf '%s\n' "error: option required option=$VALIDATE_CONFIG_KIND_OPTIONS" >&2
    printf '%s\n' "hint: specify exactly one validation option" >&2
    return 2
  fi
  if [ "${#kinds[@]}" -gt 1 ]; then
    local joined
    joined="$(
      IFS=,
      printf '%s\n' "${kinds[*]}"
    )"
    printf '%s\n' "error: options are exclusive options=$joined" >&2
    printf '%s\n' "hint: specify exactly one validation option" >&2
    return 2
  fi

  local handler="validate_config_${kind//-/_}"
  if ! declare -F "$handler" >/dev/null; then
    printf '%s\n' "error: validation kind is not implemented option=--$kind" >&2
    return 6
  fi
  "$handler" "$path" "$verbose"
}

validate_config_main "$@"
