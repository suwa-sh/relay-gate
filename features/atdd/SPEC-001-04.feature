# source: docs/usdm/latest/requirements.yaml requirements[REQ-001].specifications[SPEC-001-04].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-001-04 実装固有の起動方式・接続先ホスト・OS・プロトコルは、facade本体ではなくslotのrunnerに閉じ込める

  @atdd_SPEC-001-04-1
  Scenario: SPEC-001-04-1
    Given 新しい実装世代のrunnerを追加する
    When facade本体を変更せずrunnerだけを差し替える
    Then 実装固有の起動方式の差異がfacadeに影響しない
