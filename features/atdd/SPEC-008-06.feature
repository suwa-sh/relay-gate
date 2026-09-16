# source: docs/usdm/latest/requirements.yaml#requirements[REQ-008].specifications[SPEC-008-06].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-008-06 ハング検知定期ジョブの通知先メールアドレス・送信コマンド・件名プレフィックス・管理 DB 接続参照名は、基盤適用設計者が所有するハング検知定期ジョブ設定(hang-detector 用 env 設定ファイル)で定義する。認証情報は値を置かず参照名のみとする。通知 UC はこの設定を入力として通知メールを送る

  REQ-008: ハング検知が background 実行(background slot と速報比較依頼)を定期監視し、ジョブスケジューラの実行結果に現れない background 異常を運用者へ通知すること

  @atdd_SPEC-008-06-1
  Scenario: SPEC-008-06-1
    Given ハング検知定期ジョブ設定に通知先と送信コマンドが定義されている
    When 異常を通知する
    Then 設定された送信コマンドで設定された宛先へメールが送られる

  @atdd_SPEC-008-06-2
  Scenario: SPEC-008-06-2
    Given 設定所有区分
    When ハング検知定期ジョブ設定の所有者を確認する
    Then 基盤適用設計者である

  @atdd_SPEC-008-06-3
  Scenario: SPEC-008-06-3
    Given ハング検知定期ジョブ設定
    When 内容を確認する
    Then 認証情報の値は含まれず管理 DB 接続の参照名だけがある
