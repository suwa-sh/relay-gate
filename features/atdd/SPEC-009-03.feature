# source: docs/usdm/latest/requirements.yaml requirements[REQ-009].specifications[SPEC-009-03].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-009-03 起動時に解決済みのホスト・スクリプト・作業ディレクトリ・固定引数・追加引数・マップ版・実装版・roleごとのhang_d

  @atdd_SPEC-009-03-1
  Scenario: SPEC-009-03-1
    Given slot runnerが実行先を解決する
    When 起動する
    Then execution-spec.jsonに解決済み設定が一度だけ確定して保存され、認証情報そのものは含まれない
