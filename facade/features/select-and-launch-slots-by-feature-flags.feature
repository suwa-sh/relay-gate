# source: docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/tier-facade.md#ティア完了条件(BDD)
# 転写: spec 20260819_114307 還流後の tier-facade.md から意訳せず転写(S2 scoped 再実行)
Feature: feature flag設定に基づきslotを選択して起動する - tier-facade

  Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And ジョブマップ v1.4.0 で job_id "daily-settlement" が blue（host=blue-host-01, impl_version=blue-2.3.1）と green（host=green-host-01, impl_version=green-0.9.0）に解決できる
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を返すよう固定されている
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 0 で終了する
    And execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の1行がINSERTされる
    And slot_execution_specs に slot_type="blue" と slot_type="green" の2行がINSERTされる
    And runner_results に status="STARTING" の2行と、runner_result_events に event_name="attempt_started" の2行が同一transactionでINSERTされる
    And audit_logs に event_name="slot_launch_accepted" と event_name="slot_launch_attempted" の起動前監査イベントがINSERTされる

  Scenario: BLUE_MODEとGREEN_MODEが同時にforegroundでバリデーションエラーになる
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=foreground, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 2 で終了する
    And execution_specs・slot_execution_specs へのINSERTは発生しない

  Scenario: 起動前監査の追記失敗で外部slotを起動しない
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And ジョブマップ v1.4.0 で job_id "daily-settlement" が解決できる
    And audit_logs へのINSERTが失敗する状態になっている
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 1 で終了する
    And execution_specs・slot_execution_specs・runner_results・runner_result_events へのINSERTはrollbackされ残らない
    And 外部slotへの起動イベントは送出されない
