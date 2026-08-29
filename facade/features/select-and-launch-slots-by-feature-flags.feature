# source: docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/tier-facade.md#ティア完了条件(BDD)
Feature: feature flag設定に基づきslotを選択して起動する - tier-facade

  Background:
    Given 環境変数 RELAYGATE_JOB_MAP_PATH_BLUE=/etc/relaygate/job-map.blue.json, RELAYGATE_JOB_MAP_PATH_GREEN=/etc/relaygate/job-map.green.json, RELAYGATE_CREDENTIAL_DIR=/etc/relaygate/credentials が設定されている
    And blue のジョブマップは job_map_version="v1.4.0", slot_type="blue" で job_id "daily-settlement" が host=blue-host-01, impl_version=blue-2.3.1, fixed_args=["--mode","batch"], credential_ref=cred-blue-batch, hang_detect_limit_minutes=30 に解決できる
    And green のジョブマップは job_map_version="v1.4.0", slot_type="green" で job_id "daily-settlement" が host=green-host-01, impl_version=green-0.9.0, credential_ref=cred-green-batch, hang_detect_limit_minutes=45 に解決できる

  Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を返すよう固定されている
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 0 で終了する
    And execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", hang_detect_limit_minutes=45 の1行がINSERTされる
    And slot_execution_specs に slot_type="blue" と slot_type="green" の2行が job_map_version="v1.4.0" でINSERTされる
    And runner_results に status="STARTING" の2行と、runner_result_events に event_name="attempt_started" の2行が同一transactionでINSERTされる
    And audit_logs に event_name="slot_launch_accepted" と event_name="slot_launch_attempted" の起動前監査イベントがINSERTされる

  Scenario: BLUE_MODEとGREEN_MODEが同時にforegroundでバリデーションエラーになる
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=foreground, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 2 で終了する
    And execution_specs・slot_execution_specs へのINSERTは発生しない

  Scenario: ジョブマップの必須フィールド欠落でバリデーションエラーになる
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And green のジョブマップの jobs."daily-settlement" に host が定義されていない
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 2 で終了する
    And 標準エラーに "ジョブマップの必須フィールドが欠落しています: slot_type=green path=/etc/relaygate/job-map.green.json field=jobs.daily-settlement.host" が出力される
    And execution_specs・slot_execution_specs・runner_results・audit_logs へのINSERTは発生しない

  Scenario: 起動前監査の追記失敗で外部slotを起動しない
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And audit_logs へのINSERTが失敗する状態になっている
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 1 で終了する
    And execution_specs・slot_execution_specs・runner_results・runner_result_events へのINSERTはrollbackされ残らない
    And 外部slotへの起動イベントは送出されない

  Scenario: 起動イベント送出失敗をFAILEDへ補償記録し監査イベントを追記する
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And attempt_id発番が green="att-green-0001" を返すよう固定されている
    And green実装ホスト green-host-01 へのSSH接続が失敗する状態である
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 1 で終了する
    And runner_results の green/background/att-green-0001 行が status="FAILED" へ更新され、runner_result_events に event_name="attempt_failed" の履歴が同一transactionでINSERTされる
    And audit_logs に (slot="green", attempt_id="att-green-0001", event_name="slot_launch_failed", outcome="failed", error_code="launch_event_send_failed") がINSERTされる
    And 標準出力には選択slotごとの status=STARTING 行が出力される

  Scenario: 起動イベント送出timeoutをUNKNOWNへ補償記録し推測でFAILEDにしない
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And attempt_id発番が blue="att-blue-0001" を返すよう固定されている
    And blue実装ホスト blue-host-01 へのSSH起動イベント送出がtimeoutする状態である
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 124 で終了する
    And runner_results の blue/foreground/att-blue-0001 行が status="UNKNOWN" へ更新され、runner_result_events に event_name="attempt_unknown" の履歴が同一transactionでINSERTされる
    And audit_logs に (slot="blue", attempt_id="att-blue-0001", event_name="slot_launch_timeout", outcome="timeout", error_code="launch_event_send_timeout") がINSERTされる

  Scenario: 追加引数をJSON配列で保存し要素順のままargvへ復元する
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=off, RAPID_CROSSCHECK_MODE=off, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    When 追加引数 `--note` と `a b "c"`（空白と二重引用符を含む1要素）を渡して `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then execution_specs の additional_args にJSON配列 ["--note","a b \"c\""] が保存される
    And blue実装への起動イベントのargvは fixed_args の要素に additional_args の要素を後置連結した ["--mode","batch","--note","a b \"c\""] である
