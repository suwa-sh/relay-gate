# source: docs/usdm/latest/requirements.yaml requirements[REQ-006].specifications[SPEC-006-02].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-006-02 終了済みのbackground roleはexitcode.txtを確認し、非0終了をエラーとして通知する

  @atdd_SPEC-006-02-1
  Scenario: SPEC-006-02-1
    Given background roleのexitcode.txtが非0である
    When hang-detectorが走査する
    Then background実行エラーとして通知される
