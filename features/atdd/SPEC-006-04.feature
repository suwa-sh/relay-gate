# source: docs/usdm/latest/requirements.yaml requirements[REQ-006].specifications[SPEC-006-04].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-006-04 hang-detectorは実行状態をRUNNINGのまま保持し、自動でABORTEDへ変更しない。新しい実行依頼も作成

  @atdd_SPEC-006-04-1
  Scenario: SPEC-006-04-1
    Given ハング疑いを通知する
    When hang-detectorの処理が完了する
    Then 対象の実行状態はRUNNINGのまま変更されず、新しい実行依頼も作成されない
