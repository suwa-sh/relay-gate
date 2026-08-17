# source: docs/usdm/latest/requirements.yaml requirements[REQ-012].specifications[SPEC-012-02].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-012-02 RAPID_CROSSCHECK_MODE=offにより、facadeから起動する速報クロスチェックを停止できる

  @atdd_SPEC-012-02-1
  Scenario: SPEC-012-02-1
    Given RAPID_CROSSCHECK_MODE=offを設定する
    When facadeがジョブを起動する
    Then 速報クロスチェックの完了通知・DB接続・書込みが発生しない
