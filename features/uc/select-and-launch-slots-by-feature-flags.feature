# source: docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/spec.md#E2E完了条件(BDD)
# 転写: spec 20260819_114307 還流後の spec.md から意訳せず転写(正常系 6 + 異常系 3。S2 scoped 再実行)
Feature: feature flag設定に基づきslotを選択して起動する

  Scenario: BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And ジョブマップ v1.4.0 で job_id "daily-settlement" が blue（host=blue-host-01, exec_user=batchuser, work_dir=/opt/relaygate/work, impl_version=blue-2.3.1）と green（host=green-host-01, exec_user=batchuser, work_dir=/opt/relaygate/work, impl_version=green-0.9.0）に解決できる
    And ジョブマップの hang_detect_limit_minutes が 30 である
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を、attempt_id発番が blue="att-blue-0001" / green="att-green-0001" を返すよう固定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 0 で終了する
    And execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", parent_run_id=NULL, job_id="daily-settlement", job_map_version="v1.4.0", hang_detect_limit_minutes=30 の1行がINSERTされる
    And slot_execution_specs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", host="blue-host-01", impl_version="blue-2.3.1", credential_ref="cred-blue-batch") と (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", host="green-host-01", impl_version="green-0.9.0", credential_ref="cred-green-batch") の2行が (run_id, slot_type) で一意に識別されるようINSERTされる
    And slot_execution_specs には認証情報の参照名（credential_ref）のみが保存され、パスワード・秘密鍵などの認証情報の実値は保存されない
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="foreground", attempt_id="att-blue-0001", attempt_no=1, status="STARTING") と (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001", attempt_no=1, status="STARTING") の2行が accepted_at 付きでINSERTされる
    And runner_result_events に対応する event_name="attempt_started", status="STARTING" の履歴が同一transactionでINSERTされる
    And audit_logs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", event_name="slot_launch_accepted", slot="-", attempt_id="-", actor="ops-tanaka", operation="slot_launch", outcome="accepted", schema_version="1.0") の起動前監査イベントがINSERTされ、audit_chain_heads の run_id 行が更新される
    And 標準出力に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の blue/foreground/att-blue-0001/STARTING 行と green/background/att-green-0001/STARTING 行が出力される

  Scenario: RAPID_CROSSCHECK_MODE=offの場合は速報管理DBへ接続しない
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=off, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And ジョブマップ v1.4.0 で job_id "daily-settlement" が解決できる
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を返すよう固定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 0 で終了する
    And rapid_crosscheck_requests へのINSERTは発生しない

  Scenario: BLUE_MODE=off, GREEN_MODE=foregroundで新実装単独本番の運用モードとして起動する
    Given 環境変数に BLUE_MODE=off, GREEN_MODE=foreground, RAPID_CROSSCHECK_MODE=off, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And ジョブマップ v1.4.0 で job_id "daily-settlement" が green（host=green-host-01, impl_version=green-0.9.0）に解決できる
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を、attempt_id発番が "att-green-0001" を返すよう固定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 0 で終了する
    And execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の1行が、slot_execution_specs に slot_type="green" の1行のみがINSERTされる
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="foreground", attempt_id="att-green-0001", attempt_no=1, status="STARTING") の1行がINSERTされる
    And 標準出力に green/foreground/att-green-0001/STARTING の1行のみが出力される（運用モード: 新実装単独本番に相当する組み合わせ）

  Scenario: background roleを先に起動しforeground待機中もbackgroundが並走する
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And ジョブマップ v1.4.0 で job_id "daily-settlement" が blue（host=blue-host-01, impl_version=blue-2.3.1）と green（host=green-host-01, impl_version=green-0.9.0）に解決できる
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を、attempt_id発番が blue="att-blue-0001" / green="att-green-0001" を返すよう固定されている
    And blue実装のforeground実行が完了まで60秒かかる状態である
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then green実装へのbackground起動イベント（非同期起動トリガー）が、blue実装へのforeground起動イベント（同期実行）より先に送出される
    And blue foreground実行の待機中に、runner_results の (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001") が status="RUNNING" で並走している
    And blue foreground実行の完了を待ってから終了コード 0 で終了し、green background実行の完了は待たない

  Scenario: job mapの固定引数の後ろに追加引数を順序を変えず連結する
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And ジョブマップ v1.4.0 で job_id "daily-settlement" の blue の fixed_args が ["--mode", "batch"] に定義されている
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を返すよう固定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement -- --target-date 2026-08-18 --retry 3` を実行する
    Then execution_specs の run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" 行の additional_args に "--target-date 2026-08-18 --retry 3" が保存される
    And slot_execution_specs の (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue") 行の fixed_args に "--mode batch" が保存される
    And blue実装への起動イベントの引数列が "--mode batch --target-date 2026-08-18 --retry 3"（固定引数→追加引数の順、順序・値とも改変なし）で構成される

  Scenario: runner設定の差し替えのみで新世代実装を起動できる（facade本体は無変更）
    Given 環境変数に BLUE_MODE=off, GREEN_MODE=foreground, RAPID_CROSSCHECK_MODE=off, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And ジョブマップが v1.5.0 に更新され、job_id "daily-settlement" の green が host=green-host-01, exec_user=batchuser, script_path=/opt/green-next/run.sh, work_dir=/opt/relaygate/work, impl_version=green-1.0.0 に差し替えられている
    And facade本体のコード・設定はジョブマップ以外に一切変更されていない
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を、attempt_id発番が "att-green-0001" を返すよう固定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 0 で終了する
    And slot_execution_specs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", script_path="/opt/green-next/run.sh", impl_version="green-1.0.0") の1行がINSERTされる
    And green実装への起動イベントは slot_execution_specs の host / exec_user / script_path / work_dir / fixed_args / credential_ref の値のみから構成され、facadeは実装固有の起動方式差異（実装名・バージョンによる分岐）を参照しない

  Scenario: BLUE_MODEとGREEN_MODEが同時にforegroundに設定されている
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=foreground, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 2 で終了する
    And 標準エラーに "BLUE_MODEとGREEN_MODEを同時にforegroundにすることはできません" が出力される
    And execution_specs・slot_execution_specs・runner_results・audit_logs へのINSERTは発生しない

  Scenario: JOB_IDに対応するジョブマップが存在しない
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And job_id "unknown-job" がジョブマップ v1.4.0 に存在しない
    When 運用者が `relaygate concurrent-run select-slot --job-id unknown-job` を実行する
    Then 終了コード 1 で終了する
    And 標準エラーに "JOB_IDに対応するジョブマップが見つかりません: unknown-job" が出力される

  Scenario: 起動前監査の追記に失敗した場合は外部slotを起動しない
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And ジョブマップ v1.4.0 で job_id "daily-settlement" が解決できる
    And audit_logs へのINSERTが失敗する状態になっている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 1 で終了する
    And 標準エラーに起動前監査の追記失敗の原因と次アクションが出力される
    And execution_specs・slot_execution_specs・runner_results・runner_result_events へのINSERTはrollbackされ残らない
    And blue実装・green実装への起動イベントは送出されない
