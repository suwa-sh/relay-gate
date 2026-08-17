# source: docs/usdm/latest/requirements.yaml requirements[REQ-008].specifications[SPEC-008-02].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-008-02 対象がRUNNINGの実行、元のslot modeがforegroundまたはoff、未対応role、または元の実行が見

  @atdd_SPEC-008-02-1
  Scenario: SPEC-008-02-1
    Given 対象実行がRUNNING中である
    When background-rerun.shを実行する
    Then リランせずエラー終了する

  @atdd_SPEC-008-02-2
  Scenario: SPEC-008-02-2
    Given 元のslot modeがforegroundまたはoffである
    When 該当roleを指定してbackground-rerun.shを実行する
    Then リランせずエラー終了する
