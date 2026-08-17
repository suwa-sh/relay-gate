# source: docs/usdm/latest/requirements.yaml requirements[REQ-004].specifications[SPEC-004-01].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-004-01 blue runnerとgreen runnerからの完了通知（blue-completed/green-complet

  @atdd_SPEC-004-01-1
  Scenario: SPEC-004-01-1
    Given blueとgreenがどちらの順序で完了しても
    When 両系の完了結果が登録される
    Then 比較依頼は重複なく1件だけ作成される
