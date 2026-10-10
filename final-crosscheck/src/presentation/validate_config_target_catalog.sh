#!/usr/bin/env bash
# presentation: validate-config.sh --target-catalog の handler(ValidateTargetCatalogArgs)。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-final-crosscheck.md
#       「変更概要」「コマンド契約」: validate-config.sh のエントリポイント(tier-facade。facade/src/presentation/validate-config.sh)が
#       本ファイルを source し、`--target-catalog <path>` の検証を validate_config_target_catalog <path> <verbose> に委譲する
#       (引数の解釈・排他・値必須の判定はエントリポイント側。本 tier は検証ロジック validate_target_catalog を提供する)。
# 登録の所在: docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md
# 自 tier の domain / usecase / repository は本ファイルの位置からの相対パスで source する(エントリポイントの cwd に依存しない)。
# CSV の解析関数(job_map_repo_load / csv_parse)と出力フィールド関数(cli_field_*)はエントリポイントが先に source した
# tier-facade のものを使う(契約未宣言の tier 間依存。上記 issue 参照。本ファイルからは facade を source しない)。
# shellcheck source-path=SCRIPTDIR
VALIDATE_CONFIG_TARGET_CATALOG_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../domain/target_catalog.sh
source "$VALIDATE_CONFIG_TARGET_CATALOG_SRC_DIR/domain/target_catalog.sh"
# shellcheck source=../repository/target_catalog_repo.sh
source "$VALIDATE_CONFIG_TARGET_CATALOG_SRC_DIR/repository/target_catalog_repo.sh"
# shellcheck source=../usecase/validate_target_catalog.sh
source "$VALIDATE_CONFIG_TARGET_CATALOG_SRC_DIR/usecase/validate_target_catalog.sh"

# --target-catalog の usecase 委譲(引数は validate_config_job_map と同じ: 検証対象パス、verbose の true/false)
validate_config_target_catalog() {
  local path="$1" verbose="${2:-false}"
  validate_target_catalog "$path" "$verbose"
}
