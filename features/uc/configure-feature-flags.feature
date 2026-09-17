# source: docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/spec.md#E2E完了条件(BDD)
# 転写: 正常系・異常系の 2 ブロックを意訳せず結合(S2 test-scaffold 生成。uc_id=fd678b04。spec event 20260917_100000_feedback_impl_feedback_fd678b04_cycle2 追従の再転写)
Feature: feature flag を設定する

  Scenario: 並行稼働モードの feature flag を検証する(SPEC-001-01)
    Given /etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/bin/rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=/opt/relay-gate/bin/rapid-crosscheck-worker.sh がある
    And 両 runner・速報 runner・速報 worker は実行可能ファイルで、両 runner は --help に "runner-if-version=1" を返す
    And /etc/relay-gate/blue-job-map.csv と /etc/relay-gate/green-job-map.csv が存在する
    When 基盤適用設計者が validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 0 で終了する
    And stdout に blue_mode=foreground green_mode=background blue_impl=blue-2.3.1 green_impl=green-1.4.0 rapid_crosscheck_mode=background operation_mode=parallel が出る

  Scenario: 元資料の 9 キーの feature flag は未知キー警告なしで検証を通過する(SPEC-001-01)
    Given feature-flag.env に BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE / BLUE_IMPL / GREEN_IMPL / BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER の 9 キーだけを有効な値で書いた
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 0 で終了する
    And stderr に "warn: unknown key" で始まる行は 1 行も出ない

  Scenario: 単独本番モードの feature flag を検証する(SPEC-001-03)
    Given feature-flag.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh がある
    And BLUE_IMPL / BLUE_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER は未設定である
    And green runner は実行可能で --help に "runner-if-version=1" を返し、/etc/relay-gate/green-job-map.csv が存在する
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 0 で stdout に operation_mode=green_only が出る

  Scenario: 次世代並行稼働モードの feature flag を検証する(SPEC-001-03)
    Given feature-flag.env に BLUE_MODE=background GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=background BLUE_IMPL=green-1.4.0 GREEN_IMPL=green-2.0.0 BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/bin/rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=/opt/relay-gate/bin/rapid-crosscheck-worker.sh がある
    And 両 runner・速報 runner・速報 worker は実行可能で、両 runner は --help に "runner-if-version=1" を返し、/etc/relay-gate/blue-job-map.csv と green-job-map.csv が存在する
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 0 で stdout に operation_mode=next_gen_parallel が出る

  Scenario: ジョブ定義を変えずに feature flag だけで運用モードを切り替える(SPEC-001-03)
    Given ジョブスケジューラのジョブ定義は facade.sh JOB001 のままである
    And feature-flag.env は並行稼働の組合せ(BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background)で、validate-config.sh --feature-flag が終了コード 0 で stdout に operation_mode=parallel を返した
    When feature-flag.env を単独本番の組合せ(BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off)へ変更して validate-config.sh --feature-flag を実行する
    Then 終了コード 0 で stdout に operation_mode=green_only が出る
    And stderr に "error:" で始まる行は出ない
    And ジョブスケジューラのジョブ定義は変更していない

  Scenario: 両 slot foreground の feature flag は検証で拒否される(SPEC-001-02)
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=foreground がある
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 2 で stderr に "error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground" が出る

  Scenario: RAPID_CROSSCHECK_MODE の列挙外は拒否される
    Given feature-flag.env に RAPID_CROSSCHECK_MODE=on がある
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 2 で stderr に "error: invalid value key=RAPID_CROSSCHECK_MODE value=on" と "hint: use foreground, background or off" が出る

  Scenario: 速報有効時は速報 runner と worker の実体が必須である(SPEC-005-04)
    Given feature-flag.env に RAPID_CROSSCHECK_MODE=background があり RAPID_CROSSCHECK_RUNNER が未設定、RAPID_CROSSCHECK_WORKER=/opt/relay-gate/bin/missing-worker.sh は存在しない
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 2 で stderr に "error: option required option=RAPID_CROSSCHECK_RUNNER path: /etc/relay-gate/feature-flag.env" と "error: file not executable key=RAPID_CROSSCHECK_WORKER path=/opt/relay-gate/bin/missing-worker.sh" の両方が出る

  Scenario: off でない slot の実装版が無い feature flag は拒否される(SPEC-001-01)
    Given feature-flag.env に GREEN_MODE=foreground があり GREEN_IMPL が未設定である
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 2 で stderr に "error: option required option=GREEN_IMPL path: /etc/relay-gate/feature-flag.env" が出る

  Scenario: 確報の制御キーは拒否される(SPEC-001-01)
    Given feature-flag.env に FINAL_CROSSCHECK_MODE=background がある
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 2 で stderr に "error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE" が出る

  Scenario: FINAL_ で始まる確報設定のキーは未知キーではなく拒否される(SPEC-001-01)
    Given feature-flag.env の 9 キー・両 runner と速報 runner / worker の実体・blue / green のジョブマップは、Scenario「並行稼働モードの feature flag を検証する(SPEC-001-01)」の Given と同じ有効な状態である(単体なら終了コード 0 になる)
    And feature-flag.env に FINAL_DB_CONN_REF=final-db の 1 行を加えた(FINAL_ で始まるが FINAL_CROSSCHECK_ で始まらないキー)
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 2 で stderr に "error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF" が出る
    And stderr の "error:" で始まる行はその 1 行だけである
    And stderr に "warn: unknown key key=FINAL_DB_CONN_REF" で始まる行は出ない

  Scenario: 違反は全件まとめて報告される
    Given feature-flag.env に BLUE_MODE=parallel GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=maybe がある
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 2 で stderr に "error: invalid value key=BLUE_MODE value=parallel" と "error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe" の両方が出る(各行に "hint: use foreground, background or off" が続く)
