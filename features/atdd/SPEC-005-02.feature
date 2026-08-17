# source: docs/usdm/latest/requirements.yaml requirements[REQ-005].specifications[SPEC-005-02].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-005-02 確報クロスチェックのrunnerは比較依頼の完了を同期pollingし、依頼に保存されたstdout・stderr・ex

  @atdd_SPEC-005-02-1
  Scenario: SPEC-005-02-1
    Given 確報比較依頼がSUCCEEDEDまたはFAILEDで完了する
    When runnerがジョブスケジューラへ応答する
    Then 応答内容はstdout・stderr・exitcodeだけである
