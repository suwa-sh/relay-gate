# source: docs/usdm/latest/requirements.yaml requirements[REQ-005].specifications[SPEC-005-01].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-005-01 確報クロスチェックはジョブスケジューラの別ジョブ定義から起動し、全テーブルと全ファイルを比較対象とする

  @atdd_SPEC-005-01-1
  Scenario: SPEC-005-01-1
    Given ジョブスケジューラが確報クロスチェック専用ジョブ定義を起動する
    When 確報クロスチェックが実行される
    Then 全テーブル・全ファイルが比較対象になる
