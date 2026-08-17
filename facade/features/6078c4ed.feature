# source: docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/tier-facade.md#ティア完了条件(BDD)
Feature: feature flag設定に基づきslotを選択して起動する - tier-facade

  Scenario: 排他制約を満たすfeature flag設定でexecution-spec.jsonを確定する
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on が設定されている
    And JOB_ID "JOB-2026-0817-001" がジョブマップで解決可能である
    When `relaygate concurrent-run select-slot --job-id JOB-2026-0817-001` を実行する
    Then 終了コード 0 で終了する
    And execution_specsテーブルに run_id を持つ1件のレコードがINSERTされる

  Scenario: BLUE_MODEとGREEN_MODEが同時にforegroundでバリデーションエラーになる
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=foreground が設定されている
    When `relaygate concurrent-run select-slot --job-id JOB-2026-0817-003` を実行する
    Then 終了コード 2 で終了する
    And execution_specsテーブルへのINSERTは発生しない
