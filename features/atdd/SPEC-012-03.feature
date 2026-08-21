# source: docs/usdm/latest/requirements.yaml requirements[REQ-012].specifications[SPEC-012-03].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-012-03 比較定義はjob_idごとに差し替えられる。比較定義はJOB_ID・比較対象テーブル・比較対象ファイル・比較実装識別子・

  @atdd_SPEC-012-03-1
  Scenario: SPEC-012-03-1
    Given job_idごとに異なる比較対象・比較実装を定義する
    When 速報・確報クロスチェックが実行される
    Then job_idに応じた比較定義が適用される

  @atdd_SPEC-012-03-2
  Scenario: SPEC-012-03-2
    Given 同一JOB_IDに対して有効期間の異なる比較定義が登録されている
    When 実行時点に対応する比較定義を解決する
    Then 有効期間に該当する比較定義が1件適用される
