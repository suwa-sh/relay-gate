# source: docs/usdm/latest/requirements.yaml requirements[REQ-007].specifications[SPEC-007-01].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-007-01 abort-blue.sh/abort-green.shは、対象slotがbackgroundかつRUNNINGの場合だ

  @atdd_SPEC-007-01-1
  Scenario: SPEC-007-01-1
    Given 対象slotがbackgroundかつRUNNINGである
    When 対話確認でyesと回答する
    Then 対象slotがABORTEDへ遷移する

  @atdd_SPEC-007-01-2
  Scenario: SPEC-007-01-2
    Given 対象slotがforegroundまたはoffである
    When abort-blue.shまたはabort-green.shを実行する
    Then 状態を変更せずエラー終了する
