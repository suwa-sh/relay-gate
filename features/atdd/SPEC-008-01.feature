# source: docs/usdm/latest/requirements.yaml requirements[REQ-008].specifications[SPEC-008-01].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-008-01 background-rerun.shは、元のexecution-spec.jsonからホスト・実行ユーザー・スクリプト

  @atdd_SPEC-008-01-1
  Scenario: SPEC-008-01-1
    Given 元のbackground slot実行が完了済みまたは中止済みである
    When background-rerun.shを実行する
    Then 元のexecution-spec.jsonの設定で新しいrun_idの実行が開始され、parent_run_idが元のrun_idに設定される
