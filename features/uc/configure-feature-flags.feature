# source: docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/spec.md#E2E完了条件(BDD)
# 転写: 正常系・異常系の 2 ブロックを意訳せず結合(S2 test-scaffold 生成。uc_id=fd678b04。spec event 20260917_100000_feedback_impl_feedback_fd678b04_cycle2 追従の再転写)
# 追記: spec event 20261115_142000_feedback_impl_feedback_fd678b04_cycle3 で足された末尾 2 Scenario(error 行の順 / mode が列挙外の slot の検査)を転写(2026-11-15 の S2 再実行。既存 Scenario は変更なし)
# 追記: spec event 20261115_164000_feedback_runner_relative_path で足された 2 Scenario(方針資料の設定例の書き方の相対パス / 相対パスの基準は設定ファイルのあるディレクトリ)を仕様と同じ位置へ転写し、Scenario「error 行が 2 行以上のときは決まった順に報告される」の Given 1 行と表の 5 行目を仕様の置換どおりに差し替えた(2026-11-15 の S2 再実行。ほかの Scenario は変更なし)
# 追記: 2026-11-16 の仕様更新(slot ジョブマップの場所を書く任意の 2 キー BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV。契約 config_files.feature-flag.env.job_map_location、spec-decision-036 / 038)で足された 4 Scenario(場所を絶対パスで書く / 相対パスの基準 / 名前が違うキーは未知キー / 書いた場所に無い)を仕様と同じ位置へ転写し、Scenario「元資料の 9 キーの feature flag は未知キー警告なしで検証を通過する(SPEC-001-01)」に仕様で足された And 2 行を加えた(2026-11-16 の S2 再実行。ほかの Scenario は変更なし)
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
    And BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV は書かず、RELAY_GATE_CONFIG_DIR=/etc/relay-gate で /etc/relay-gate/blue-job-map.csv と /etc/relay-gate/green-job-map.csv が存在する
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 0 で終了する
    And stderr に "warn: unknown key" で始まる行は 1 行も出ない
    And stderr に "error:" で始まる行は出ず、stdout に "blue_job_map: /etc/relay-gate/blue-job-map.csv" "green_job_map: /etc/relay-gate/green-job-map.csv" が出る(場所を書くキーが無いときは固定の名前を使う)

  Scenario: ジョブマップの場所を絶対パスで書いた feature flag は未知キー警告なしで検証を通過する(SPEC-001-01)
    Given /etc/relay-gate/feature-flag.env に、Scenario「並行稼働モードの feature flag を検証する(SPEC-001-01)」の Given と同じ 9 キーに加えて BLUE_JOB_MAP_CSV=/srv/relay-gate/maps/blue-jobs.csv GREEN_JOB_MAP_CSV=/srv/relay-gate/maps/green-jobs.csv がある
    And 両 runner・速報 runner・速報 worker は実行可能ファイルで、両 runner は --help に "runner-if-version=1" を返す
    And /srv/relay-gate/maps/blue-jobs.csv と /srv/relay-gate/maps/green-jobs.csv が存在し、/etc/relay-gate/blue-job-map.csv と /etc/relay-gate/green-job-map.csv は存在しない
    When 基盤適用設計者が RELAY_GATE_CONFIG_DIR=/etc/relay-gate で validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 0 で stderr は 0 行である("warn: unknown key" で始まる行も "error:" で始まる行も出ない)
    And stdout に "blue_job_map: /srv/relay-gate/maps/blue-jobs.csv" "green_job_map: /srv/relay-gate/maps/green-jobs.csv" と operation_mode=parallel が出る

  Scenario: ジョブマップの場所の相対パスは設定ファイルのあるディレクトリを基準に解決される(SPEC-004-01)
    Given /etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh BLUE_JOB_MAP_CSV=./blue-jobs.csv GREEN_JOB_MAP_CSV=maps/green-jobs.csv がある
    And 両 runner は実行可能で --help に "runner-if-version=1" を返す
    And /etc/relay-gate/blue-jobs.csv と /etc/relay-gate/maps/green-jobs.csv が存在し、作業ディレクトリ /tmp/work に blue-jobs.csv と maps/green-jobs.csv は無い
    When 基盤適用設計者が作業ディレクトリ /tmp/work で validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 0 で stderr に "error:" で始まる行は出ない
    And stdout に "blue_job_map: /etc/relay-gate/./blue-jobs.csv" "green_job_map: /etc/relay-gate/maps/green-jobs.csv" が出る(設定に書いた相対パスのままは出ない)

  Scenario: 方針資料の設定例の書き方(相対パス)の feature flag を検証する
    Given /etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=./blue-runner.sh GREEN_RUNNER=./green-runner.sh RAPID_CROSSCHECK_RUNNER=./rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=./rapid-crosscheck-worker.sh がある
    And /etc/relay-gate に blue-runner.sh / green-runner.sh / rapid-crosscheck-runner.sh / rapid-crosscheck-worker.sh が実行可能ファイルとしてあり、両 runner は --help に "runner-if-version=1" を返す
    And /etc/relay-gate/blue-job-map.csv と /etc/relay-gate/green-job-map.csv が存在する
    When 基盤適用設計者が作業ディレクトリ /tmp で validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 0 で終了し、stderr に "error:" で始まる行は出ない
    And stdout に "blue_runner: /etc/relay-gate/./blue-runner.sh" "green_runner: /etc/relay-gate/./green-runner.sh" "rapid_crosscheck_runner: /etc/relay-gate/./rapid-crosscheck-runner.sh" "rapid_crosscheck_worker: /etc/relay-gate/./rapid-crosscheck-worker.sh" と operation_mode=parallel が出る

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

  Scenario: 相対パスの基準は作業ディレクトリではなく設定ファイルのあるディレクトリである
    Given /etc/relay-gate/feature-flag.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=./green-runner.sh がある
    And /etc/relay-gate/green-runner.sh は存在せず、作業ディレクトリ /tmp/work に実行可能な green-runner.sh がある
    And /etc/relay-gate/green-job-map.csv が存在する
    When 基盤適用設計者が作業ディレクトリ /tmp/work で validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 2 で stderr に "error: file not executable key=GREEN_RUNNER path=/etc/relay-gate/./green-runner.sh" が出る
    And stderr に "path is not absolute" を含む行は出ない

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

  Scenario: 9 キーと任意の 2 キーのどちらでもないキーは未知キーとして警告される(SPEC-001-01)
    Given feature-flag.env の 9 キー・両 runner と速報 runner / worker の実体・blue / green のジョブマップは、Scenario「並行稼働モードの feature flag を検証する(SPEC-001-01)」の Given と同じ有効な状態である(単体なら終了コード 0 になる)
    And feature-flag.env に BLUE_JOB_MAP=/srv/relay-gate/maps/blue-jobs.csv の 1 行を加えた(任意の 2 キーと名前が違うキー)
    When RELAY_GATE_CONFIG_DIR=/etc/relay-gate で validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 0 で stderr に "warn: unknown key key=BLUE_JOB_MAP path: /etc/relay-gate/feature-flag.env" が出る
    And stdout に "blue_job_map: /etc/relay-gate/blue-job-map.csv" が出る(未知キーの値はジョブマップの場所に使われない)

  Scenario: 書いた場所にジョブマップが無い feature flag は解決後のパスつきで拒否される(SPEC-004-01)
    Given /etc/relay-gate/feature-flag.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh GREEN_JOB_MAP_CSV=./green-jobs.csv がある
    And green runner は実行可能で --help に "runner-if-version=1" を返す
    And /etc/relay-gate/green-jobs.csv は存在せず、/etc/relay-gate/green-job-map.csv は存在する
    When RELAY_GATE_CONFIG_DIR=/etc/relay-gate で validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 2 で stdout は 0 行である
    And stderr に "error: job map not found slot=green map=/etc/relay-gate/./green-jobs.csv" が出る(固定の名前のファイルがあっても使わない)

  Scenario: 違反は全件まとめて報告される
    Given feature-flag.env に BLUE_MODE=parallel GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=maybe がある
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 2 で stderr に "error: invalid value key=BLUE_MODE value=parallel" と "error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe" の両方が出る(各行に "hint: use foreground, background or off" が続く)

  Scenario: error 行が 2 行以上のときは決まった順に報告される
    Given /etc/relay-gate/feature-flag.env の 1 行目が BLUE_MODE=foreground、2 行目が GREEN_MODE=foreground、3 行目が RAPID_CROSSCHECK_MODE=maybe、4 行目が GREEN_IMPL=green-1.4.0、5 行目が BLUE_RUNNER=relative/blue-runner.sh、6 行目が FINAL_POLL_LIMIT_SEC=60、7 行目が FINAL_CROSSCHECK_MODE=background である
    And BLUE_IMPL / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER は未設定で、/etc/relay-gate/blue-job-map.csv と /etc/relay-gate/green-job-map.csv は存在せず、/etc/relay-gate/relative/blue-runner.sh も存在しない
    When validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 2 で stdout は 0 行である
    And stderr は次の 12 行だけがこの順に出る
      | error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe                              |
      | hint: use foreground, background or off                                                 |
      | error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground   |
      | error: option required option=BLUE_IMPL path: /etc/relay-gate/feature-flag.env          |
      | error: file not executable key=BLUE_RUNNER path=/etc/relay-gate/relative/blue-runner.sh |
      | error: option required option=GREEN_RUNNER path: /etc/relay-gate/feature-flag.env       |
      | error: option required option=RAPID_CROSSCHECK_RUNNER path: /etc/relay-gate/feature-flag.env |
      | error: option required option=RAPID_CROSSCHECK_WORKER path: /etc/relay-gate/feature-flag.env |
      | error: final crosscheck key is not allowed key=FINAL_POLL_LIMIT_SEC                     |
      | error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE                    |
      | error: job map not found slot=blue map=/etc/relay-gate/blue-job-map.csv                 |
      | error: job map not found slot=green map=/etc/relay-gate/green-job-map.csv               |

  Scenario: mode が列挙外の slot も実装版と対応ジョブマップを検査し runner へ問い合わせる
    Given feature-flag.env に BLUE_MODE=parallel GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_IMPL=green-1.4.0 GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh があり BLUE_IMPL が未設定である
    And 両 runner は実行可能で --help に "runner-if-version=1" を返し、/etc/relay-gate/green-job-map.csv は存在し、/etc/relay-gate/blue-job-map.csv は存在しない
    When validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 2 で stdout は 0 行である
    And stderr は次の 4 行だけがこの順に出る
      | error: invalid value key=BLUE_MODE value=parallel                                  |
      | hint: use foreground, background or off                                            |
      | error: option required option=BLUE_IMPL path: /etc/relay-gate/feature-flag.env     |
      | error: job map not found slot=blue map=/etc/relay-gate/blue-job-map.csv            |
    And blue runner は --help で 1 回起動されている(mode が列挙外の slot も runner へ問い合わせる)
