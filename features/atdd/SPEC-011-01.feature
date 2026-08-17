# source: docs/usdm/latest/requirements.yaml requirements[REQ-011].specifications[SPEC-011-01].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-011-01 クロスチェック依頼はREQUESTED→CLAIMED→RUNNING→SUCCEEDED/FAILED/ABORTED

  @atdd_SPEC-011-01-1
  Scenario: SPEC-011-01-1
    Given クロスチェック依頼がCLAIMED状態でleaseが失効し未開始である
    When workerが状態を確認する
    Then 依頼はREQUESTEDへ戻る
