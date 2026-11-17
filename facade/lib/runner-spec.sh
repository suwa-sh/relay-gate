# shellcheck shell=bash source-path=SCRIPTDIR
# 共通ライブラリ「execution-spec 保存」の入口。標準の slot runner と自作の runner が source する
# (cli-command-contract.yaml commands「$BLUE_RUNNER / $GREEN_RUNNER」の standard_runner.custom_runner)。
# 本体は配置ディレクトリの src/usecase/runner_spec.sh。source した側のシェルの設定(set / trap)を変えず、何も出力しない。
# shellcheck source=../src/usecase/runner_spec.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../src/usecase/runner_spec.sh"
