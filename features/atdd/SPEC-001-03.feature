# source: docs/usdm/latest/requirements.yaml requirements[REQ-001].specifications[SPEC-001-03].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-001-03 blueとgreenの両方がforegroundになる構成は許可しない

  @atdd_SPEC-001-03-1
  Scenario: SPEC-001-03-1
    Given BLUE_MODEとGREEN_MODEの両方にforegroundを設定しようとする
    When facadeが設定を検証する
    Then 起動を許可しない
