# source: docs/usdm/latest/requirements.yaml requirements[REQ-010].specifications[SPEC-010-02].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-010-02 確報クロスチェックは、final_crosscheck_requestを速報側のrapid_runやrapid_cros

  @atdd_SPEC-010-02-1
  Scenario: SPEC-010-02-1
    Given 確報比較依頼が作成される
    When データモデルを確認する
    Then 速報側のエンティティを参照・再利用していない
