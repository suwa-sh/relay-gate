# source: docs/usdm/latest/requirements.yaml requirements[REQ-012].specifications[SPEC-012-01].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-012-01 blue/greenのrunnerを差し替えることで、異なる世代の実装を並行稼働できる

  @atdd_SPEC-012-01-1
  Scenario: SPEC-012-01-1
    Given 新しい世代の実装用runnerを追加する
    When BLUE_RUNNERまたはGREEN_RUNNERの設定を差し替える
    Then facade本体を変更せず新しい世代の実装を並行稼働できる
