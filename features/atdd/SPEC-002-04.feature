# source: docs/usdm/latest/requirements.yaml requirements[REQ-002].specifications[SPEC-002-04].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-002-04 relay-gateエラーで応答する場合の標準エラーは、foregroundのstderr.logの内容（取得可能な場合

  @atdd_SPEC-002-04-1
  Scenario: SPEC-002-04-1
    Given relay-gateエラーが発生しforegroundのstderr.logを取得できる
    When facadeが応答を返す
    Then 標準エラーにstderr.logの内容とrelay-gateのエラー内容（原因と次アクション）の両方が含まれる

  @atdd_SPEC-002-04-2
  Scenario: SPEC-002-04-2
    Given relay-gateエラーが発生しforegroundのstderr.logを取得できない
    When facadeが応答を返す
    Then 標準エラーにrelay-gateのエラー内容（原因と次アクション）が出力される
