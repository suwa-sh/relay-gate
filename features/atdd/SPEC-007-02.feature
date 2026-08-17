# source: docs/usdm/latest/requirements.yaml requirements[REQ-007].specifications[SPEC-007-02].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-007-02 abort-rapid-crosscheck.sh/abort-final-crosscheck.shは、対象比較依頼が

  @atdd_SPEC-007-02-1
  Scenario: SPEC-007-02-1
    Given 速報または確報比較依頼がRUNNINGである
    When 対話確認でyesと回答する
    Then 対象比較依頼がABORTEDへ遷移する
