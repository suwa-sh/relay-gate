# source: docs/usdm/latest/requirements.yaml requirements[REQ-010].specifications[SPEC-010-03].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-010-03 複数回リランする場合、各新規実行のparent_run_idには直前にリラン元として指定したrun_idを設定し、最新r

  @atdd_SPEC-010-03-1
  Scenario: SPEC-010-03-1
    Given background実行を複数回リランする
    When 最新run_idからparent_run_idを順にたどる
    Then 元の実行まで追跡できる
