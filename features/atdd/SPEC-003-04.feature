# source: docs/usdm/latest/requirements.yaml requirements[REQ-003].specifications[SPEC-003-04].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-003-04 Runner実行結果は起動試行（attempt）単位で識別し、attempt_id・attempt_no・accepte

  @atdd_SPEC-003-04-1
  Scenario: SPEC-003-04-1
    Given 同一run_id・slot種別・role区分で複数回起動する
    When Runner実行結果を参照する
    Then attempt_idにより起動試行が一意に識別され、attempt_noが同一組内の連番になっている

  @atdd_SPEC-003-04-2
  Scenario: SPEC-003-04-2
    Given 起動を受け付ける
    When Runner実行結果を参照する
    Then accepted_atが記録され実行状態がSTARTINGである

  @atdd_SPEC-003-04-3
  Scenario: SPEC-003-04-3
    Given timeoutにより実行結果を取得できない
    When 実行状態を確定する
    Then 実行状態はUNKNOWNとなりFAILEDへ推測で確定されない

  @atdd_SPEC-003-04-4
  Scenario: SPEC-003-04-4
    Given 実行状態がUNKNOWNである
    When 実結果を回収するまたは対話確認による回復を行う
    Then SUCCEEDED・FAILED・ABORTEDのいずれかへ確定する
