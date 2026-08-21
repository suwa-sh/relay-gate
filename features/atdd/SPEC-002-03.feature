# source: docs/usdm/latest/requirements.yaml requirements[REQ-002].specifications[SPEC-002-03].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-002-03 relay-gate自身のエラーは、業務ジョブが通常使用しない専用の退避終了コードへ分離する。実行結果未確定・取得不能・

  @atdd_SPEC-002-03-1
  Scenario: SPEC-002-03-1
    Given foregroundの実行結果が未確定または取得不能である
    When facadeが応答を返す
    Then 終了コードは125であり、業務ジョブの終了コードとして解釈されない

  @atdd_SPEC-002-03-2
  Scenario: SPEC-002-03-2
    Given run_id未指定などrelay-gateのバリデーションエラーが発生する
    When facadeが応答を返す
    Then 終了コードは124である

  @atdd_SPEC-002-03-3
  Scenario: SPEC-002-03-3
    Given foregroundの実行状態がUNKNOWNである
    When facadeが終了コードを決定する
    Then FAILED相当の業務終了コードへ推測で変換されず退避コード125が使われる
