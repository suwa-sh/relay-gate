# source: docs/usdm/latest/requirements.yaml requirements[REQ-007].specifications[SPEC-007-03].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-007-03 中止対話確認はyes以外の回答では状態を変更しない。いずれの中止スクリプトも実行プロセス・Pod・SSH接続先そのものは

  @atdd_SPEC-007-03-1
  Scenario: SPEC-007-03-1
    Given 対話確認でyes以外を回答する
    When 中止スクリプトが終了する
    Then 状態は変更されない
