#!/usr/bin/env bash
# エントリポイント(cli-command-contract.yaml: validate-config.sh の配置先は tier-facade の bin/)。
# 本体は src/presentation/validate-config.sh。RELAY_GATE_HOME の既定は本スクリプトのディレクトリ。
set -euo pipefail
VALIDATE_CONFIG_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELAY_GATE_HOME="${RELAY_GATE_HOME:-$VALIDATE_CONFIG_BIN_DIR}"
export RELAY_GATE_HOME
exec "$VALIDATE_CONFIG_BIN_DIR/../src/presentation/validate-config.sh" "$@"
