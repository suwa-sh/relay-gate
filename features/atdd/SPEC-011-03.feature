# source: docs/usdm/latest/requirements.yaml requirements[REQ-011].specifications[SPEC-011-03].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-011-03 確報クロスチェックのrunnerは、workerが保存したexitcodeをそのままジョブスケジューラへ中継する。依頼の

  @atdd_SPEC-011-03-1
  Scenario: SPEC-011-03-1
    Given 確報比較依頼がSUCCEEDEDまたはFAILEDで完了する
    When runnerがジョブスケジューラへ応答する
    Then 返す値はworkerが保存したexitcodeであり、状態名そのものは返さない
