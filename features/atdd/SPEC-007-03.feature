# source: docs/usdm/latest/requirements.yaml#requirements[REQ-007].specifications[SPEC-007-03].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-007-03 比較ツールの終了コードと依頼状態の対応は比較ツールの契約に従う(例: 比較 OK=0→SUCCEEDED、比較 NG=3→FAILED(警告終了)、実行エラー=6→FAILED(エラー終了))。確報は worker が保存した exitcode をそのままジョブスケジューラへ中継する

  REQ-007: 速報・確報のクロスチェック依頼が同じライフサイクル(REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED)で管理され、worker の claim と lease で多重実行を防ぐこと

  @atdd_SPEC-007-03-1
  Scenario: SPEC-007-03-1
    Given 比較ツールが 3 で終了
    When 確報 runner が応答する
    Then 依頼は FAILED、ジョブスケジューラへの終了コードは 3
