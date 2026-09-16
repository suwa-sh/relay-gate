# source: docs/usdm/latest/requirements.yaml#requirements[REQ-008].specifications[SPEC-008-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-008-01 ハング検知スクリプトはジョブスケジューラの定期ジョブ(5 分ごとなど)として起動され、未完了の background role について started-at.txt と execution-spec.json の hang_detect_limit_minutes から経過時間を判定する。exitcode.txt があり終了コード 0 なら対象外、非 0 なら background 実行エラーとして通知、exitcode.txt がなく経過時間が上限以内なら継続監視、上限超過ならハング疑いとして通知する

  REQ-008: ハング検知が background 実行(background slot と速報比較依頼)を定期監視し、ジョブスケジューラの実行結果に現れない background 異常を運用者へ通知すること

  @atdd_SPEC-008-01-1
  Scenario: SPEC-008-01-1
    Given background role の exitcode.txt がなく経過時間が hang_detect_limit_minutes を超過
    When 検知ジョブが実行される
    Then ハング疑いとして通知される

  @atdd_SPEC-008-01-2
  Scenario: SPEC-008-01-2
    Given background role の exitcode.txt が非 0
    When 検知ジョブが実行される
    Then background 実行エラーとして通知される

  @atdd_SPEC-008-01-3
  Scenario: SPEC-008-01-3
    Given exitcode.txt が 0
    When 検知ジョブが実行される
    Then 通知されない
