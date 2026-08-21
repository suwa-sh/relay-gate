# source: docs/usdm/latest/requirements.yaml requirements[REQ-009].specifications[SPEC-009-01].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-009-01 ジョブスケジューラはJOB_IDと追加引数（PARAM...）だけをfacadeへ渡し、実行先ホスト・実行ユーザー・スク

  @atdd_SPEC-009-01-1 @uc_6078c4ed
  Scenario: SPEC-009-01-1
    Given ジョブスケジューラがJOB_IDと追加引数だけを渡す
    When slot runnerがジョブマップを参照する
    Then 実行先の詳細が解決される
