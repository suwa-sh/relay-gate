# source: docs/usdm/latest/requirements.yaml#requirements[REQ-004].specifications[SPEC-004-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-004-02 ジョブマップの固定引数の後ろに、ジョブスケジューラから渡された PARAM... を順序を変えずに連結して実装へ渡す。固定引数は JSON 配列として保持し、引数の数と各引数内の空白・カンマを維持する。空の固定引数は [] とする

  REQ-004: ジョブスケジューラのジョブ定義に実行先(ホスト・実行ユーザー・スクリプトパス)を持たせず、slot runner が実装固有のジョブマップで JOB_ID から実行先を解決し、解決結果を execution-spec.json として保存すること

  @atdd_SPEC-004-02-1
  Scenario: SPEC-004-02-1
    Given 固定引数 ["p1","p2 p3"] と追加引数 a b
    When 実装へ渡す引数を確認する
    Then p1, "p2 p3", a, b の順で 4 引数として渡される
