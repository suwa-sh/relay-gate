# source: docs/specs/latest/適用構成業務/適用構成定義フロー/slot runner の実体スクリプトを割り当てる/spec.md#E2E完了条件(BDD)
# 転写: 正常系・異常系の 2 ブロックを意訳せず結合(S2 test-scaffold 初回生成。uc_id=65b09d93)
Feature: slot runner の実体スクリプトを割り当てる

  Scenario: runner 割当を検証する(SPEC-001-04)
    Given /opt/relay-gate/runners/blue-runner.sh と /opt/relay-gate/runners/green-runner.sh が実行可能で、--help に "runner-if-version=1" を返す
    And /etc/relay-gate/blue-job-map.csv と green-job-map.csv が存在する
    And feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh がある
    When 基盤適用設計者が validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 0 で stdout に "blue_runner: /opt/relay-gate/runners/blue-runner.sh" "green_runner: /opt/relay-gate/runners/green-runner.sh" "blue_job_map: /etc/relay-gate/blue-job-map.csv" "green_job_map: /etc/relay-gate/green-job-map.csv" が出る

  Scenario: 標準の slot runner を blue と green の両方に割り当てた設定を検証する(SPEC-001-04)
    Given relay-gate を /opt/relay-gate に配置してあり、relay-gate が提供する標準の slot runner /opt/relay-gate/runners/standard-runner.sh は実行可能である
    And /etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=/opt/relay-gate/runners/standard-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/standard-runner.sh がある
    And /etc/relay-gate/blue-job-map.csv と /etc/relay-gate/green-job-map.csv が存在する(基盤適用設計者が用意したのは feature-flag.env と 2 つの slot ジョブマップだけで、runner のスクリプトは書いていない)
    When 基盤適用設計者が RELAY_GATE_CONFIG_DIR=/etc/relay-gate で validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 0 で stderr に "error:" で始まる行も "warn:" で始まる行も出ない
    And stdout に "blue_runner: /opt/relay-gate/runners/standard-runner.sh" "green_runner: /opt/relay-gate/runners/standard-runner.sh"(同じパス)と "blue_runner_if_version=1" "green_runner_if_version=1" が出る

  Scenario: 設定ファイルと同じディレクトリに置いた runner を相対パスで割り当てる
    Given /etc/relay-gate/blue-runner.sh と /etc/relay-gate/green-runner.sh が実行可能で、--help に "runner-if-version=1" を返す
    And /etc/relay-gate/blue-job-map.csv と green-job-map.csv が存在する
    And /etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 RAPID_CROSSCHECK_MODE=off BLUE_RUNNER=./blue-runner.sh GREEN_RUNNER=./green-runner.sh がある
    When 基盤適用設計者が作業ディレクトリ /tmp で validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 0 で stdout に "blue_runner: /etc/relay-gate/./blue-runner.sh" "green_runner: /etc/relay-gate/./green-runner.sh" "blue_runner_if_version=1" "green_runner_if_version=1" が出る

  Scenario: runner 実体を差し替えても facade は変更不要である(SPEC-001-04)
    Given 並行稼働モードで green runner が新実装 green-1.x 用である
    And 次世代実装は標準の slot runner が扱わない接続で動くため、次世代実装用の自作の runner /opt/relay-gate/runners/green-next-runner.sh を作成し、runner IF と Runner Result Contract に従う
    When feature-flag.env の GREEN_RUNNER を /opt/relay-gate/runners/green-next-runner.sh に変更し validate-config.sh が終了コード 0 を返した後、ジョブスケジューラが facade.sh JOB001 を実行する
    Then facade.sh・速報クロスチェック runner(RAPID_CROSSCHECK_RUNNER の実体)・速報クロスチェック worker(RAPID_CROSSCHECK_WORKER の実体)・hang-detector.sh・background-rerun.sh・abort-green.sh・標準の slot runner(runners/standard-runner.sh)・共通ライブラリ(lib/runner-*.sh)のファイルは変更されていない
    And green/ に Runner Result の 3 ファイルが揃う

  Scenario: facade は設定された runner を runner IF で起動するだけである(SPEC-002-03)
    Given feature-flag.env に BLUE_MODE=foreground BLUE_IMPL=blue-2.3.1 BLUE_RUNNER=<Runner Result 3 ファイルを書くスタブ runner> GREEN_MODE=background GREEN_IMPL=green-1.4.0 RAPID_CROSSCHECK_MODE=off がある
    And GREEN_RUNNER に起動引数と環境変数を記録するスタブ runner を割り当てた
    And 両スタブは --help で "runner-if-version=1" を返し、両 slot のジョブマップに JOB001 の行がある
    When ジョブスケジューラが facade.sh JOB001 x y を実行する
    Then スタブは "--run-id <run_id> --job-id JOB001 --role green --mode background -- x y" で起動され、facade は実装固有の引数を追加していない
    And スタブの環境変数に GREEN_IMPL=green-1.4.0 があり、RAPID_CROSSCHECK_RUNNER は渡されていない(RAPID_CROSSCHECK_MODE=off)

  Scenario: runner 実体が存在しない割当は拒否される
    Given feature-flag.env に GREEN_MODE=background GREEN_RUNNER=/opt/relay-gate/runners/missing.sh がある
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 2 で stderr に "error: file not executable key=GREEN_RUNNER path=/opt/relay-gate/runners/missing.sh" が出る

  Scenario: 対応するジョブマップが無い割当は拒否される
    Given feature-flag.env に GREEN_MODE=background GREEN_RUNNER=<実行可能> があり /etc/relay-gate/green-job-map.csv が無い
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 2 で stderr に "error: job map not found slot=green map=/etc/relay-gate/green-job-map.csv" が出る

  Scenario: runner IF に応答しない実体は警告される
    Given GREEN_RUNNER が --help に "runner-if-version=" を含まない実行可能ファイルである
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 0 で stderr に "warn: runner does not respond to --help slot=green runner=<path>" が出る
    And stdout の green_runner_if_version は "-" である

  Scenario: --help に応答しない runner の問い合わせは待機上限で打ち切られ 10 秒以内に復帰する
    Given BLUE_RUNNER と GREEN_RUNNER が --help を受けると応答せずに 30 秒間終了しない実行可能ファイルである
    And feature-flag.env は BLUE_MODE=foreground GREEN_MODE=background の並行稼働の組合せで、runner 以外の検証はすべて通過する
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 0 で、起動から終了までの経過時間は 10 秒以内である(契約 runner_help_probe.response_time_budget の問い合わせの上限 9.2 秒に、数行の設定の検査の時間を加えた、この入力での確認)
    And stderr に "warn: runner does not respond to --help slot=blue runner=<path>" と "warn: runner does not respond to --help slot=green runner=<path>" の両方が出る
    And stdout の blue_runner_if_version と green_runner_if_version は "-" で、終了時点で runner のプロセスは残っていない
