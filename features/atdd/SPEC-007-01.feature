# source: docs/usdm/latest/requirements.yaml#requirements[REQ-007].specifications[SPEC-007-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-007-01 依頼は REQUESTED で作成され、worker が取得すると CLAIMED、比較開始で RUNNING、exitcode 0 で SUCCEEDED、非 0 または実行エラーで FAILED、停止確認後の中止で ABORTED に遷移する。CLAIMED で lease が失効しかつ未開始なら REQUESTED に戻る

  REQ-007: 速報・確報のクロスチェック依頼が同じライフサイクル(REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED)で管理され、worker の claim と lease で多重実行を防ぐこと

  @atdd_SPEC-007-01-1
  Scenario: SPEC-007-01-1
    Given CLAIMED の依頼の lease_until が経過し未開始
    When 別の worker が poll する
    Then 依頼は REQUESTED に戻り再取得できる

  @atdd_SPEC-007-01-2
  Scenario: SPEC-007-01-2
    Given RUNNING の依頼
    When worker が exitcode=0 で完了する
    Then SUCCEEDED になる
