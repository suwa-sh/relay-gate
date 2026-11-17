#!/usr/bin/env bash
# 標準の slot runner の入口(cli-command-contract.yaml commands「$BLUE_RUNNER / $GREEN_RUNNER」の standard_runner)。
# 本体は配置ディレクトリの src/presentation/standard_runner.sh。
# shellcheck source-path=SCRIPTDIR
set -euo pipefail
# 配置ディレクトリは、起動されたパスの字面の runners/ の 1 つ上。シンボリックリンクを辿らず、環境変数でも受け取らない(standard_runner.home)
standard_runner_home="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/presentation/standard_runner.sh
source "$standard_runner_home/src/presentation/standard_runner.sh"
standard_runner_main "$@"
