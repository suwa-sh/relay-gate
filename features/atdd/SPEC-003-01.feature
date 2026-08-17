# source: docs/usdm/latest/requirements.yaml requirements[REQ-003].specifications[SPEC-003-01].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-003-01 blue runnerとgreen runnerは、foreground・backgroundのいずれでも、starte

  @atdd_SPEC-003-01-1
  Scenario: SPEC-003-01-1
    Given blue runnerまたはgreen runnerの実行が終了する
    When 成果物を確認する
    Then execution-spec.json、started-at.txt、stdout.log、stderr.log、exitcode.txtが揃っている
