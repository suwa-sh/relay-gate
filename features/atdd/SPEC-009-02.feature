# source: docs/usdm/latest/requirements.yaml requirements[REQ-009].specifications[SPEC-009-02].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-009-02 job mapの固定引数の後ろに、ジョブスケジューラから渡された追加引数を順序を変えずに連結する

  @atdd_SPEC-009-02-1 @uc_6078c4ed
  Scenario: SPEC-009-02-1
    Given job mapに固定引数が定義されている
    When ジョブスケジューラから追加引数が渡される
    Then 固定引数の後ろに追加引数が順序どおり連結される
