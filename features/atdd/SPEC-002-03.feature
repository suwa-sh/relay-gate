# source: docs/usdm/latest/requirements.yaml#requirements[REQ-002].specifications[SPEC-002-03].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-002-03 ジョブスケジューラは facade に JOB_ID [PARAM...] だけを渡す。facade は比較対象や実装固有の起動方式を判断せず、slot と mode の選択と foreground 結果の応答だけを行う

  REQ-002: facade は background slot を先に起動してから foreground slot を起動し、foreground の結果だけを待機してジョブスケジューラへ返すこと

  @atdd_SPEC-002-03-1
  Scenario: SPEC-002-03-1
    Given ジョブスケジューラのジョブ定義が facade の呼び出しと JOB_ID・PARAM だけを持つ
    When ジョブを起動する
    Then facade は JOB_ID を runner に渡し、runner がジョブマップで実行先を解決する
