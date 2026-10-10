#!/usr/bin/env bash
# presentation: validate-config.sh --crosscheck-job-map の handler(ValidateCrosscheckJobMapArgs)。
# validate-config.sh の本体(エントリポイント)は tier-facade が所有し(facade/src/presentation/validate-config.sh)、
# 本ファイルが存在すれば source して `validate_config_crosscheck_job_map <path> <verbose>` を `--crosscheck-job-map` の handler として呼ぶ
# (tier-rapid-crosscheck.md「変更概要」: bash の source で直接依存。CLP-003)。引数のパスはそのまま使う(既定パスによる補完はしない)。
# 仕様: _cross-cutting/api/cli-command-contract.yaml commands[validate-config.sh] options[--crosscheck-job-map](owner_tier: tier-rapid-crosscheck)
# 自 tier の domain / usecase / repository は本ファイルの位置からの相対パスで source する。
# tier-facade の関数(csv_parse 系・cli_field_* 系・job_map_repo_* 系・job_map_emit・validate_job_map_unique_job_ids)は
# validate-config.sh が先に source しているものを使う(契約未宣言の tier 間依存。
# 根拠: docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md)
# shellcheck source-path=SCRIPTDIR

RAPID_CROSSCHECK_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../domain/comparison_definition_rules.sh
source "$RAPID_CROSSCHECK_SRC_DIR/domain/comparison_definition_rules.sh"
# shellcheck source=../repository/crosscheck_job_map_repo.sh
source "$RAPID_CROSSCHECK_SRC_DIR/repository/crosscheck_job_map_repo.sh"
# shellcheck source=../usecase/validate_crosscheck_job_map.sh
source "$RAPID_CROSSCHECK_SRC_DIR/usecase/validate_crosscheck_job_map.sh"

# --crosscheck-job-map の usecase 委譲
# 引数: path verbose(true|false)
validate_config_crosscheck_job_map() {
  local path="$1" verbose="$2"
  validate_crosscheck_job_map "$path" "$verbose"
}
