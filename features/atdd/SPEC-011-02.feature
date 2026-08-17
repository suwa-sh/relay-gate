# source: docs/usdm/latest/requirements.yaml requirements[REQ-011].specifications[SPEC-011-02].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-011-02 workerは終了時にexitcodeが0ならSUCCEEDED、非0または実行エラーならFAILEDとして依頼状態を更

  @atdd_SPEC-011-02-1
  Scenario: SPEC-011-02-1
    Given workerが比較を実行して終了する
    When exitcodeが0である
    Then 依頼状態はSUCCEEDEDになる

  @atdd_SPEC-011-02-2
  Scenario: SPEC-011-02-2
    Given workerが比較を実行して終了する
    When exitcodeが非0または実行エラーである
    Then 依頼状態はFAILEDになる
