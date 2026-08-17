# source: docs/usdm/latest/requirements.yaml requirements[REQ-008].specifications[SPEC-008-03].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-008-03 roleにrapid-crosscheckを指定した場合、業務ジョブを再実行せず、比較依頼だけを新規作成する

  @atdd_SPEC-008-03-1
  Scenario: SPEC-008-03-1
    Given roleにrapid-crosscheckを指定してbackground-rerun.shを実行する
    When 実行が成功する
    Then 業務ジョブは再実行されず比較依頼だけが新規作成される
