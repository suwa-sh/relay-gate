# source: docs/usdm/latest/requirements.yaml#requirements[REQ-008].specifications[SPEC-008-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-008-02 速報比較依頼については依頼状態と終了コードを確認し、FAILED または比較 NG を速報クロスチェック異常として通知する。速報比較依頼が RUNNING のときは状態を変更せずハング疑いとして通知する

  REQ-008: ハング検知が background 実行(background slot と速報比較依頼)を定期監視し、ジョブスケジューラの実行結果に現れない background 異常を運用者へ通知すること

  @atdd_SPEC-008-02-1
  Scenario: SPEC-008-02-1
    Given 速報比較依頼が FAILED
    When 検知ジョブが実行される
    Then 速報クロスチェック異常として通知される
