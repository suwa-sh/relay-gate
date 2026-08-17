# source: docs/usdm/latest/requirements.yaml requirements[REQ-004].specifications[SPEC-004-03].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-004-03 速報クロスチェックの失敗は、foreground結果としてジョブスケジューラへ返す応答を変更しない

  @atdd_SPEC-004-03-1
  Scenario: SPEC-004-03-1
    Given 速報クロスチェックの比較がFAILEDになる
    When foreground結果がジョブスケジューラへ返される
    Then foreground応答の内容は速報クロスチェックの失敗の影響を受けない
