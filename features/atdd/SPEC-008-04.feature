# source: docs/usdm/latest/requirements.yaml requirements[REQ-008].specifications[SPEC-008-04].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-008-04 foreground slot実行と確報クロスチェックは、background-rerun.shを使用せず、ジョブスケジ

  @atdd_SPEC-008-04-1
  Scenario: SPEC-008-04-1
    Given foreground slotまたは確報クロスチェックを再実行したい
    When 運用者が対応を行う
    Then background-rerun.shではなくジョブスケジューラの正規ジョブが再実行される
