# source: docs/usdm/latest/requirements.yaml requirements[REQ-001].specifications[SPEC-001-02].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-001-02 運用モード（並行稼働／新実装単独本番／次世代実装との並行稼働）を、ジョブ定義を変更せず設定だけで切り替えられる

  @atdd_SPEC-001-02-1
  Scenario: SPEC-001-02-1
    Given BLUE_MODE/GREEN_MODE/RAPID_CROSSCHECK_MODEの組み合わせを変更する
    When 同じジョブ定義でジョブを起動する
    Then ジョブ定義を変更せず運用モードが切り替わる
