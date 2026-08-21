# source: docs/usdm/latest/requirements.yaml requirements[REQ-008].specifications[SPEC-008-03].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-008-03 roleにrapid-crosscheckを指定した場合、業務ジョブを再実行せず、新しいrun_idを発行した速報比較依

  @atdd_SPEC-008-03-1
  Scenario: SPEC-008-03-1
    Given roleにrapid-crosscheckを指定してbackground-rerun.shを実行する
    When 実行が成功する
    Then 業務ジョブは再実行されず、新しいrun_idの速報比較依頼がparent_run_idで元依頼に関連付けられて新規作成される

  @atdd_SPEC-008-03-2
  Scenario: SPEC-008-03-2
    Given rapid-crosscheckの再実行が完了する
    When 元の速報比較依頼のレコードを参照する
    Then 元依頼の状態・履歴は変更されていない
