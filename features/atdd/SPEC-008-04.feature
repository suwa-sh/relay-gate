# source: docs/usdm/latest/requirements.yaml#requirements[REQ-008].specifications[SPEC-008-04].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-008-04 ハング検知は RUNNING を ABORTED へ変更せず、実行プロセスを停止せず、新しい実行依頼を作成しない(自動中止・自動再実行をしない)

  REQ-008: ハング検知が background 実行(background slot と速報比較依頼)を定期監視し、ジョブスケジューラの実行結果に現れない background 異常を運用者へ通知すること

  @atdd_SPEC-008-04-1
  Scenario: SPEC-008-04-1
    Given ハング疑いを検知した
    When 検知ジョブが終了する
    Then 対象の状態は RUNNING のままで、プロセスは停止されず、新しい依頼も作られていない
