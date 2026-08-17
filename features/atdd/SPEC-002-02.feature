# source: docs/usdm/latest/requirements.yaml requirements[REQ-002].specifications[SPEC-002-02].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-002-02 実行順序は、background roleを先にすべて起動してPIDと成果物ディレクトリを確定した後、foregroun

  @atdd_SPEC-002-02-1
  Scenario: SPEC-002-02-1
    Given background roleとforeground roleが両方設定されている
    When facadeがジョブを起動する
    Then background roleが先に起動し、foreground待機中もbackground roleは並走して実行される
