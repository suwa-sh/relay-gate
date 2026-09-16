# source: docs/usdm/latest/requirements.yaml#requirements[REQ-008].specifications[SPEC-008-03].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-008-03 監視は monitor_status、hang_suspected_at、alerted_at を記録して運用者へ通知する。通知後に正常終了した実行についても警告した経過時間を記録し、通常処理の警告傾向を確認できるようにする。RAPID_CROSSCHECK_MODE=off の場合も slot 成果物だけで監視する。monitor_status の値は監視対象外 / 監視中 / ハング疑い通知済み / 実行エラー通知済み / 比較異常通知済み / 正常終了の 6 値とし、ハング疑い通知後に対象が終端した場合は再判定して比較異常通知済み / 実行エラー通知済み / 正常終了へ遷移する。監視対象が ABORTED になった場合は中止済みとして正常終了で終端する

  REQ-008: ハング検知が background 実行(background slot と速報比較依頼)を定期監視し、ジョブスケジューラの実行結果に現れない background 異常を運用者へ通知すること

  @atdd_SPEC-008-03-1
  Scenario: SPEC-008-03-1
    Given ハング疑いを通知した実行がその後正常終了した
    When 監視記録を確認する
    Then 警告時の経過時間が記録されている

  @atdd_SPEC-008-03-2
  Scenario: SPEC-008-03-2
    Given RAPID_CROSSCHECK_MODE=off
    When 検知ジョブが実行される
    Then 管理 DB なしで slot 成果物を走査して監視する

  @atdd_SPEC-008-03-3
  Scenario: SPEC-008-03-3
    Given ハング疑いを通知した速報比較依頼がその後 FAILED または比較 NG になった
    When 検知ジョブが実行される
    Then 監視状態は比較異常通知済みへ遷移し error メールが送られる

  @atdd_SPEC-008-03-4
  Scenario: SPEC-008-03-4
    Given ハング疑いを通知した background slot がその後 ABORTED になった
    When 検知ジョブが実行される
    Then 監視記録は中止済みとして正常終了で終端し、以後再判定されない

  @atdd_SPEC-008-03-5
  Scenario: SPEC-008-03-5
    Given バリエーション「監視状態」と状態モデル「監視状態」
    When 値集合を比較する
    Then 同じ 6 値である
