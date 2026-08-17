# source: docs/usdm/latest/requirements.yaml requirements[REQ-006].specifications[SPEC-006-03].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-006-03 速報クロスチェックの依頼状態と終了コードを確認し、FAILEDまたは比較NGを異常として通知する

  @atdd_SPEC-006-03-1
  Scenario: SPEC-006-03-1
    Given 速報比較依頼がFAILEDまたは比較NGである
    When hang-detectorが走査する
    Then 速報クロスチェック異常として通知される
