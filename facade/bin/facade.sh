#!/usr/bin/env bash
# エントリポイント(cli-command-contract.yaml: facade.sh。ジョブスケジューラの業務ジョブ定義から `facade.sh JOB_ID [PARAM...]` で起動される)。
# 本体は src/presentation/facade.sh。RELAY_GATE_HOME の既定は本スクリプトのディレクトリ(validate-config.sh と同じ置き方)。
set -euo pipefail
FACADE_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELAY_GATE_HOME="${RELAY_GATE_HOME:-$FACADE_BIN_DIR}"
export RELAY_GATE_HOME
exec "$FACADE_BIN_DIR/../src/presentation/facade.sh" "$@"
