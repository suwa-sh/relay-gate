# source: docs/usdm/latest/requirements.yaml requirements[REQ-006].specifications[SPEC-006-01].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-006-01 定期起動のhang-detectorが、未完了background roleの成果物についてstarted-at.txt

  @atdd_SPEC-006-01-1
  Scenario: SPEC-006-01-1
    Given background roleがexitcode.txtを出力していない
    When 経過時間がhang_detect_limit_minutesを超過する
    Then ハング疑いとして運用者へ通知される
