# source: docs/usdm/latest/requirements.yaml#requirements[REQ-008].specifications[SPEC-008-06].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-008-06 ハング検知定期ジョブの管理 DB 接続参照名は、基盤適用設計者が所有するハング検知定期ジョブ設定(hang-detector 用 env 設定ファイル)で定義する。認証情報は値を置かず参照名のみとする。ハング検知定期ジョブ設定は、通知の宛先・送信コマンド・件名など、ハング検知ジョブの終了結果以外の手段で異常を送るための項目を持たない

  REQ-008: ハング検知が background 実行(background slot と速報比較依頼)を定期監視し、ジョブスケジューラの実行結果に現れない background 異常を、ハング検知ジョブ自身の終了結果と標準エラーで運用者へ知らせること

  @atdd_SPEC-008-06-1
  Scenario: SPEC-008-06-1
    Given ハング検知定期ジョブ設定
    When 設定項目を確認する
    Then 通知の宛先・送信コマンド・件名に関する項目は無く、管理 DB 接続参照名がある

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
