# source: docs/usdm/latest/requirements.yaml requirements[REQ-009].specifications[SPEC-009-04].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-009-04 job mapを変更しても、実行済みまたはリラン対象の設定は上書きされない

  @atdd_SPEC-009-04-1
  Scenario: SPEC-009-04-1
    Given job mapを変更する
    When 既存run_idのexecution-spec.jsonを参照する
    Then 変更前の設定内容が保持される
