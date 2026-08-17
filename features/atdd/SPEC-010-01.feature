# source: docs/usdm/latest/requirements.yaml requirements[REQ-010].specifications[SPEC-010-01].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-010-01 速報クロスチェックは、parallel_run・rapid_run・rapid_crosscheck_request・c

  @atdd_SPEC-010-01-1
  Scenario: SPEC-010-01-1
    Given 並行稼働run_idが発行される
    When 速報クロスチェックの各エンティティを参照する
    Then すべて同一run_idで相関付けられている
