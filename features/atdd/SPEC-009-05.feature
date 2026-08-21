# source: docs/usdm/latest/requirements.yaml requirements[REQ-009].specifications[SPEC-009-05].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-009-05 実行設定は、run共通の実行設定（run_id・parent_run_id・JOB_ID・追加引数・マップ版・hang_

  @atdd_SPEC-009-05-1
  Scenario: SPEC-009-05-1
    Given blueとgreenで異なるホスト・スクリプトが解決される
    When 起動時の実行設定を参照する
    Then run共通の実行設定とslot別実行設定が分離して保存され、slot別実行設定がrun_idとslot種別で一意に識別される

  @atdd_SPEC-009-05-2
  Scenario: SPEC-009-05-2
    Given slot別実行設定を保存する
    When 内容を確認する
    Then 認証情報は参照名のみが保存され実値は含まれない
