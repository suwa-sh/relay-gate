# source: docs/usdm/latest/requirements.yaml requirements[REQ-002].specifications[SPEC-002-01].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-002-01 facadeはforeground roleの標準出力・標準エラー・終了コードだけをジョブスケジューラへ中継する

  @atdd_SPEC-002-01-1
  Scenario: SPEC-002-01-1
    Given foreground roleの実行が完了する
    When facadeが応答を返す
    Then stdout.log/stderr.log/exitcode.txtの内容がそのままジョブスケジューラへ中継される
