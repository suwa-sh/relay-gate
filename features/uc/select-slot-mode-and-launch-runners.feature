# source: docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/spec.md#E2E完了条件(BDD)
# 転写: 正常系・異常系の 2 ブロックを意訳せず結合(S2 test-scaffold 初回生成。uc_id=09730858)
Feature: slot 実行モードを選択して runner を起動する

  Scenario: 並行稼働モードで blue foreground と green background を起動する(SPEC-001-01)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background BLUE_IMPL=v1 GREEN_IMPL=v2 BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=/opt/relay-gate/rapid-crosscheck-worker.sh が定義されている
    And 両 slot のジョブマップに job_id=JOB001 の行がある
    When ジョブスケジューラが facade.sh JOB001 20260830 full を実行する
    Then green runner が --role green --mode background -- 20260830 full で先に起動される
    And blue runner が --role blue --mode foreground -- 20260830 full でその後に起動される
    And 各 runner の環境変数に RAPID_CROSSCHECK_MODE=background RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh と自 slot の BLUE_IMPL=v1 または GREEN_IMPL=v2 が設定されている
    And facade は blue の PID だけを待機する
    And parallel_runs に run_id の行が status=RUNNING job_id=JOB001 parameters=["20260830","full"] で存在する

  Scenario: background を先に起動し foreground だけを待機する(SPEC-002-01)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background が定義されている
    And green の実装スクリプトは 600 秒、blue の実装スクリプトは 5 秒で終了する
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then facade は blue の終了後 10 秒以内に終了する
    And facade 終了時点で facade/<run_id>/green/exitcode.txt は存在しない(green は実行中)
    And 実行ログに "slot started slot=green mode=background" が "slot started slot=blue mode=foreground" より前に記録される

  Scenario: 新実装の単独本番モードでは green だけを起動し管理 DB に触れない(SPEC-001-03)
    Given ジョブスケジューラのジョブ定義は並行稼働モードのときと同じ facade.sh JOB001 のままで、変更していない
    And feature flag に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off が定義されている
    And 管理 DB の接続設定が存在しない
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then blue runner は起動されない
    And green runner が --role green --mode foreground で起動される
    And facade は管理 DB へ接続せず終了する
    And facade/<run_id>/green/ に started-at.txt が存在する

  Scenario: 次世代並行稼働モードでは blue background と green foreground を起動する(SPEC-001-03)
    Given feature flag に BLUE_MODE=background GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=background が定義されている
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then blue runner が --mode background で先に起動される
    And green runner が --mode foreground でその後に起動される
    And facade は green の PID だけを待機する

  Scenario: off の slot は起動しない(SPEC-001-01)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=off が定義されている
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then green runner は起動されない
    And facade/<run_id>/green/ ディレクトリは作成されない

  Scenario: RAPID_CROSSCHECK_MODE=background では parallel_run を STARTED から RUNNING にする(SPEC-011-01)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background が定義されている
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then parallel_runs に status=STARTED の行が INSERT された後に status=RUNNING へ更新される
    And execution_spec_uri が <RELAY_GATE_ARTIFACT_ROOT>/facade/<run_id>/execution-spec.json を指す
    And rapid_runs に run_id の行が completion_status=PENDING で存在する

  Scenario: RAPID_CROSSCHECK_MODE=off では管理 DB に触れない(SPEC-005-04)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off が定義されている
    And 管理 DB の接続設定が存在しない
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then blue と green の runner が起動される
    And 各 runner の環境変数に RAPID_CROSSCHECK_MODE=off が設定され RAPID_CROSSCHECK_RUNNER は設定されない
    And parallel_runs / slot_executions / rapid_runs に行は作成されない
    And facade 単独で発行した run_id 形式の成果物ディレクトリ facade/<run_id>/ が作成される

  Scenario: RAPID_CROSSCHECK_MODE=foreground でも background と同じく parallel_run を作成する(SPEC-005-04)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=foreground が定義されている
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then parallel_runs に run_id の行が status=RUNNING で存在する
    And rapid_runs に run_id の行が completion_status=PENDING で存在する
    And 各 runner の環境変数に RAPID_CROSSCHECK_MODE=foreground と RAPID_CROSSCHECK_RUNNER が設定されている

  Scenario: 速報クロスチェック設定には管理 DB 接続の参照名だけがあり認証情報の値は含まれない(SPEC-005-06)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background が定義されている
    And 速報クロスチェック設定 <RELAY_GATE_CONFIG_DIR>/rapid-crosscheck.env に RAPID_DB_CONN_REF=mgmt-db RAPID_LEASE_SEC=600 RAPID_POLL_INTERVAL_SEC=30 が定義されている
    When 運用者が速報クロスチェック設定の内容を確認し、ジョブスケジューラが facade.sh JOB001 を実行する
    Then rapid-crosscheck.env にはパスワード・接続文字列などの認証情報の値は無く、管理 DB 接続の参照名 RAPID_DB_CONN_REF だけがある
    And facade は参照名 mgmt-db で管理 DB に接続し parallel_runs に run_id の行を作成する
    And 実行ログにも stderr にも参照名から解決した接続情報の値は出ない

  Scenario: RAPID_CROSSCHECK_MODE=off では速報クロスチェック設定が存在しなくても slot 実行できる(SPEC-005-06)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off が定義されている
    And <RELAY_GATE_CONFIG_DIR>/rapid-crosscheck.env が存在しない
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then blue と green の runner が起動される
    And facade は rapid-crosscheck.env を読まず、終了コードは foreground の exitcode.txt の値である
    And facade/<run_id>/blue/ と facade/<run_id>/green/ に started-at.txt が存在する

  Scenario: feature flag に書いたジョブマップの場所を自 slot の runner へ渡し、書いていない slot の runner へは既定の場所を渡す
    Given 設定ファイル置き場が /etc/relay-gate で、/etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2 と、起動引数と環境変数を記録するスタブ runner を指す BLUE_RUNNER / GREEN_RUNNER と、BLUE_JOB_MAP_CSV=./blue-jobs.csv が定義されている
    And feature flag に GREEN_JOB_MAP_CSV の行は無い
    And /etc/relay-gate/blue-job-map.csv も存在する
    When ジョブスケジューラが /etc/relay-gate とは別の作業ディレクトリ /work で facade.sh JOB001 を実行する
    Then blue runner が --role blue --mode foreground で起動され、環境変数 BLUE_JOB_MAP_CSV=/etc/relay-gate/./blue-jobs.csv が設定されている
    And green runner が --role green --mode background で起動され、環境変数 GREEN_JOB_MAP_CSV=/etc/relay-gate/green-job-map.csv が設定されている
    And blue runner の環境変数 BLUE_JOB_MAP_CSV は /work/blue-jobs.csv でも /etc/relay-gate/blue-job-map.csv でもない

  Scenario: 値が空のジョブマップの場所のキーがある slot の runner は固定の名前のジョブマップで実行先を解決する(SPEC-004-01)
    Given 設定ファイル置き場が /etc/relay-gate で、/etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2 と、標準の slot runner /opt/relay-gate/runners/standard-runner.sh を指す BLUE_RUNNER / GREEN_RUNNER と、値が空の行 `GREEN_JOB_MAP_CSV=` が定義されている
    And /etc/relay-gate/blue-job-map.csv に JOB001 の行があり、/etc/relay-gate/green-job-map.csv に行 `JOB001,,,/var/app/work,/opt/app/bin/green-job001.sh,[],60` がある(host と user が空のローカル実行の行)
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then green runner は環境変数 GREEN_JOB_MAP_CSV=/etc/relay-gate/green-job-map.csv を受け取って起動される(空の値は渡らない)
    And facade/<run_id>/execution-spec.json の slots.green は script=/opt/app/bin/green-job001.sh work_dir=/var/app/work hang_detect_limit_minutes=60 である(/etc/relay-gate/green-job-map.csv の JOB001 の行)
    And facade/<run_id>/green/stderr.log に "error: job map not found" で始まる行は無い

  Scenario: run_id はローカルタイムゾーンの時刻と job_id と 8 桁 hex で発行され成果物と管理 DB で同値である(SPEC-011-04)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background が定義されている
    And TZ=UTC で RELAY_GATE_NOW=2026-08-30T11:30:00Z が設定されている
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then 発行された run_id は正規表現 ^20260830T113000-JOB001-[0-9a-f]{8}$ に一致し、末尾に Z を含まない
    And 成果物ディレクトリ名 facade/<run_id>/ と parallel_runs.run_id は同じ値である

  Scenario: 確報クロスチェックを起動しない(SPEC-001-01)
    Given feature flag に確報クロスチェックの制御キーは存在しない
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then final-crosscheck-runner.sh は起動されない

  Scenario: 両 slot foreground は入力検証で拒否する(SPEC-001-02)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=background が定義されている
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then 終了コード 2 で終了する
    And stderr に "error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground" が出る
    And blue runner も green runner も起動されない
    And parallel_runs に行は作成されない

  Scenario: JOB_ID が無い起動は拒否する
    Given feature flag が正しく定義されている
    When ジョブスケジューラが facade.sh を引数なしで実行する
    Then 終了コード 2 で終了する
    And stderr に "error: JOB_ID required" が出る
    And どの runner も起動されない

  Scenario: 未知の実行モードは拒否する
    Given feature flag に BLUE_MODE=parallel GREEN_MODE=background が定義されている
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then 終了コード 2 で終了する
    And stderr に "error: invalid value key=BLUE_MODE value=parallel" が出る
    And stderr の次行に "hint: use foreground, background or off" が出る
    And どの runner も起動されない

  Scenario: 設定の違反が 2 つあるときは検証コマンドの error 行の順で最初の違反の 1 行だけを出す
    Given /etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 BLUE_RUNNER=relative/blue-runner.sh と実行可能な runner を指す GREEN_RUNNER が定義され、GREEN_IMPL の行は無い
    And /etc/relay-gate/relative/blue-runner.sh は存在しない
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then 終了コード 2 で終了する
    And stderr は "error: file not executable key=BLUE_RUNNER path=/etc/relay-gate/relative/blue-runner.sh" の 1 行だけである
    And stderr に "error: option required option=GREEN_IMPL" で始まる行は出ない
    And blue runner も green runner も起動されない

  Scenario: RAPID_CROSSCHECK_MODE=background で管理 DB に接続できない
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background が定義されている
    And 管理 DB が停止している
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then 終了コード 6 で終了する
    And stderr に "error: management db connection failed run_id=" で始まり "conn_ref=" を含む行が出る
    And どの runner も起動されない
