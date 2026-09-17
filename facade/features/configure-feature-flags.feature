# source: docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/tier-facade.md#ティア完了条件(BDD)
# 転写: ティア完了条件の gherkin を意訳せず転写(S2 test-scaffold 生成。uc_id=fd678b04。spec event 20260917_100000_feedback_impl_feedback_fd678b04_cycle2 追従の再転写)
Feature: feature flag を設定する - facade / slot runner ティア

  Scenario: validate-config_sh_feature-flag は有効な並行稼働設定に終了コード 0 と operation_mode=parallel を返す
    Given 一時ファイル ff.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=<実行可能な一時スクリプト> GREEN_RUNNER=<実行可能な一時スクリプト> RAPID_CROSSCHECK_RUNNER=<実行可能な一時スクリプト> RAPID_CROSSCHECK_WORKER=<実行可能な一時スクリプト> を書く
    And 両 runner スタブは --help で "runner-if-version=1" を返し、RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stdout は 15 行で、11 行目は "operation_mode=parallel" である
    And stdout の 2 行目は "blue_mode=foreground"、4 行目は "blue_impl=blue-2.3.1" である
    And stdout の最終行は "green_runner_if_version=1" である(mode=off の slot なら "-")
    And stderr に "warn: unknown key" で始まる行は出ない

  Scenario: validate-config_sh_feature-flag は両 slot foreground を終了コード 2 で拒否する
    Given ff.env に BLUE_MODE=foreground GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off を書く
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground" が出る

  Scenario: validate-config_sh_feature-flag は off の slot の実装版と runner を検証しない
    Given ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> を書き BLUE_IMPL / BLUE_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER を書かない
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv がある(blue-job-map.csv は無くてよい)
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stdout に "blue_impl=-" "blue_runner: -" "rapid_crosscheck_runner: -" と "operation_mode=green_only" が出る

  Scenario: validate-config_sh_feature-flag は runner が実行不可なら終了コード 2 を返す
    Given ff.env に GREEN_MODE=foreground GREEN_IMPL=green-1.4.0 GREEN_RUNNER=/nonexistent/green.sh を書く
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: file not executable key=GREEN_RUNNER path=/nonexistent/green.sh" が出る

  Scenario: validate-config_sh_feature-flag は off でない slot の実装版の欠落を終了コード 2 で拒否する
    Given ff.env に GREEN_MODE=foreground GREEN_RUNNER=<実行可能> を書き GREEN_IMPL を書かない
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: option required option=GREEN_IMPL path: ff.env" が出る

  Scenario: validate-config_sh_feature-flag は速報有効時に速報 runner と worker の実体を検証する
    Given 有効な並行稼働設定の RAPID_CROSSCHECK_WORKER を /nonexistent/worker.sh に書き換える
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: file not executable key=RAPID_CROSSCHECK_WORKER path=/nonexistent/worker.sh" が出る

  Scenario: validate-config_sh_feature-flag は未知キーを warn で報告し終了コード 0 を返す
    Given 有効な設定に加えて CONFIG_VERSION=cfg-v1 を書く
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stderr に "warn: unknown key key=CONFIG_VERSION path: ff.env" が出る

  Scenario: validate-config_sh_feature-flag は FINAL_ で始まるキーを未知キーではなく終了コード 2 で拒否する
    Given 有効な並行稼働設定に加えて FINAL_DB_CONN_REF=final-db と FINAL_CROSSCHECK_MODE=background を書く
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF" と "error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE" の両方が出る
    And stderr に "warn: unknown key" で始まる行は出ない

  Scenario: validate-config_sh_feature-flag はファイルが無ければ終了コード 2 を返す
    When `validate-config.sh --feature-flag /nonexistent.env` を実行する
    Then 終了コード 2 で stderr に "error: config file not found path: /nonexistent.env" が出る
