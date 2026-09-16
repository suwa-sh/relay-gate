# source: docs/usdm/latest/requirements.yaml#requirements[REQ-002].specifications[SPEC-002-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-002-02 facade は foreground slot の Runner Result(stdout.log / stderr.log / exitcode.txt)を、そのまま標準出力・標準エラー・終了コードとしてジョブスケジューラへ中継する

  REQ-002: facade は background slot を先に起動してから foreground slot を起動し、foreground の結果だけを待機してジョブスケジューラへ返すこと

  @atdd_SPEC-002-02-1
  Scenario: SPEC-002-02-1
    Given foreground slot が終了し 3 ファイルが揃った
    When facade が応答する
    Then stdout.log が標準出力、stderr.log が標準エラー、exitcode.txt の値が終了コードとしてジョブスケジューラへ返る

  @atdd_SPEC-002-02-2
  Scenario: SPEC-002-02-2
    Given 速報クロスチェックが失敗した
    When foreground の結果を確認する
    Then ジョブスケジューラへの応答は変わらない

  @atdd_SPEC-002-02-3
  Scenario: SPEC-002-02-3
    Given facade が応答した
    When ジョブスケジューラ応答の内容を確認する
    Then 標準出力・標準エラー・終了コードだけで応答時刻を持たず、実行日時の履歴はジョブスケジューラが保持する
