# source: docs/specs/latest/適用構成業務/適用構成定義フロー/slot runner の実体スクリプトを割り当てる/tier-facade.md#ティア完了条件(BDD)
# 転写: gherkin ブロックを意訳せず転写(S2 test-scaffold 初回生成。uc_id=65b09d93)
Feature: slot runner の実体スクリプトを割り当てる - facade / slot runner ティア

  Scenario: standard-runner_sh の --help は runner-if-version=1 を返す
    When `runners/standard-runner.sh --help` を実行する
    Then 終了コード 0 で stdout に "usage: " で始まる行と "runner-if-version=1" が出る

  Scenario: 配置ディレクトリの runners には標準の slot runner があり ssh-runner_sh は無い
    Given relay-gate を配置したディレクトリ <home> がある
    When <home>/runners/ のファイルを確かめる
    Then <home>/runners/standard-runner.sh は通常ファイルで実行権限がある
    And <home>/runners/ssh-runner.sh は存在しない
    And <home>/lib/ に runner-resolve.sh / runner-spec.sh / runner-result.sh / runner-notify.sh がある

  Scenario: validate-config_sh_feature-flag は標準の slot runner を両 slot に割り当てた設定の runner 割当とジョブマップ所在を出力する
    Given ff.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=<runners/standard-runner.sh の絶対パス> GREEN_RUNNER=<同じ絶対パス> RAPID_CROSSCHECK_MODE=off を書く
    And RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stderr は 0 行である
    And stdout は 15 行で、6 行目は "blue_runner: <runners/standard-runner.sh の絶対パス>"、7 行目は "green_runner: <runners/standard-runner.sh の絶対パス>"(同じパス)である
    And stdout の 12 行目は "blue_job_map: <RELAY_GATE_CONFIG_DIR>/blue-job-map.csv"、14 行目は "blue_runner_if_version=1"、15 行目は "green_runner_if_version=1" である

  Scenario: validate-config_sh_feature-flag は設定ファイルからの相対パスで書いた標準の slot runner を受理する
    Given relay-gate の配置ディレクトリ <home> の下の config/ff.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=../runners/standard-runner.sh GREEN_RUNNER=../runners/standard-runner.sh RAPID_CROSSCHECK_MODE=off を書く
    And RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある
    When <home> とは別のディレクトリを作業ディレクトリにして `validate-config.sh --feature-flag <home の絶対パス>/config/ff.env` を実行する
    Then 終了コード 0 で stdout の 6 行目は "blue_runner: <home の絶対パス>/config/../runners/standard-runner.sh"、7 行目は "green_runner: <home の絶対パス>/config/../runners/standard-runner.sh" である
    And stdout の 14 行目は "blue_runner_if_version=1"、15 行目は "green_runner_if_version=1" である

  Scenario: validate-config_sh_feature-flag は blue に標準の slot runner、green に自作の runner を割り当てた設定を受理する
    Given ff.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=<runners/standard-runner.sh の絶対パス> GREEN_RUNNER=<--help で "runner-if-version=1" を返す実行可能な自作 runner スタブの絶対パス> RAPID_CROSSCHECK_MODE=off を書く
    And RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stderr は 0 行である(割り当てられた実体が標準か自作かを区別しない)
    And stdout の 6 行目は "blue_runner: <runners/standard-runner.sh の絶対パス>"、7 行目は "green_runner: <自作 runner スタブの絶対パス>"、14 行目は "blue_runner_if_version=1"、15 行目は "green_runner_if_version=1" である

  Scenario: validate-config_sh_feature-flag は相対パスの runner を設定ファイルのあるディレクトリ基準で解決して問い合わせる
    Given 一時ディレクトリ conf の ff.env に BLUE_MODE=off GREEN_MODE=foreground GREEN_IMPL=green-1.4.0 GREEN_RUNNER=./green-runner.sh RAPID_CROSSCHECK_MODE=off を書く
    And conf/green-runner.sh は、起動されるたびに引数を記録し --help で "runner-if-version=1" を返す実行可能なスタブである
    And 作業ディレクトリにするディレクトリ work(conf とは別)に、起動されたら記録を残す別の実行可能な green-runner.sh がある
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv がある
    When work を作業ディレクトリにして `validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する
    Then 終了コード 0 で stdout に "green_runner: <conf の絶対パス>/./green-runner.sh" と "green_runner_if_version=1" が出て、stderr に "path is not absolute" を含む行は出ない
    And conf のスタブは引数 --help で 1 回起動され、work の green-runner.sh は起動されていない

  Scenario: validate-config_sh_feature-flag は応答しない相対パスの runner を解決後のパスで警告する
    Given 一時ディレクトリ conf の ff.env に BLUE_MODE=off GREEN_MODE=foreground GREEN_IMPL=green-1.4.0 GREEN_RUNNER=./green-runner.sh RAPID_CROSSCHECK_MODE=off を書く
    And conf/green-runner.sh は --help に "runner-if-version=" を含まない出力を返す実行可能ファイルである
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv がある
    When `validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する
    Then 終了コード 0 で stderr に "warn: runner does not respond to --help slot=green runner=<conf の絶対パス>/./green-runner.sh" が出る

  Scenario: validate-config_sh_feature-flag はジョブマップが無い slot を終了コード 2 で拒否する
    Given ff.env に GREEN_MODE=background GREEN_RUNNER=<実行可能> を書き RELAY_GATE_CONFIG_DIR/green-job-map.csv が無い
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: job map not found slot=green map=<RELAY_GATE_CONFIG_DIR>/green-job-map.csv" が出る

  Scenario: validate-config_sh_feature-flag は --help に応答しない runner を待機上限で打ち切り両 slot 未応答でも 10 秒以内に復帰する
    Given ff.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 RAPID_CROSSCHECK_MODE=off と、--help を受けると 30 秒 sleep する実行可能なスタブ runner を BLUE_RUNNER / GREEN_RUNNER に書く
    And RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で、起動から終了までの経過時間は 10 秒以内である(契約 runner_help_probe.response_time_budget の問い合わせの上限 9.2 秒に、数行の設定の検査の時間を加えた、この入力での確認)
    And stderr に "warn: runner does not respond to --help slot=blue runner=" で始まる行と "warn: runner does not respond to --help slot=green runner=" で始まる行が出る
    And stdout に "blue_runner_if_version=-" と "green_runner_if_version=-" が出る
    And 終了時点でスタブ runner のプロセスは残っていない

  Scenario: validate-config_sh_feature-flag は --help 問い合わせの準備に失敗すると終了コード 6 で止まる
    Given 有効な並行稼働設定の ff.env があり、一時ファイルの作成先(環境変数 TMPDIR)が存在しないディレクトリ /nonexistent/tmp を指す
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 6 で stderr に "error: runner probe failed slot=blue reason=" で始まる行が出る
    And stderr に "warn: runner does not respond to --help" で始まる行は出ず、stdout は 0 行である

  Scenario: 差し替えた runner 実体は runner IF だけで facade から起動できる
    Given 起動引数と環境変数を記録し Runner Result 3 ファイルを書く自作 runner を GREEN_RUNNER に割り当てる
    When `facade.sh JOB001 x` を BLUE_MODE=off GREEN_MODE=foreground GREEN_IMPL=green-1.4.0 RAPID_CROSSCHECK_MODE=off で実行する
    Then 自作 runner は "--run-id <run_id> --job-id JOB001 --role green --mode foreground -- x" で起動され、facade は exitcode.txt の値で終了する
    And 自作 runner の環境変数に RAPID_CROSSCHECK_MODE=off と GREEN_IMPL=green-1.4.0 があり、RAPID_CROSSCHECK_RUNNER は無い
