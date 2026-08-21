# source: docs/usdm/latest/requirements.yaml requirements[REQ-001].specifications[SPEC-001-01].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-001-01 feature flag付きストラングラーファサード（facade）が、設定に基づきblueとgreenの実装（slot

  @atdd_SPEC-001-01-1 @uc_6078c4ed
  Scenario: SPEC-001-01-1
    Given feature flag設定（BLUE_MODE/GREEN_MODE）が投入されている
    When facadeがJOB_IDを受け取る
    Then 設定に従いblue・greenの各slotが起動される
