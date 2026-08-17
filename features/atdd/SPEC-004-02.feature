# source: docs/usdm/latest/requirements.yaml requirements[REQ-004].specifications[SPEC-004-02].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-004-02 RAPID_CROSSCHECK_MODE=offの場合、blue/green runnerは完了通知を送信せず、速報管

  @atdd_SPEC-004-02-1
  Scenario: SPEC-004-02-1
    Given RAPID_CROSSCHECK_MODE=offが設定されている
    When blue/greenが完了する
    Then 速報管理DBへの接続や書込みが発生しない
