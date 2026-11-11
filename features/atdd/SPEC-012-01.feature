# source: docs/usdm/latest/requirements.yaml#requirements[REQ-012].specifications[SPEC-012-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-012-01 すべてのスクリプトは CLI として起動され、結果を標準出力・標準エラー・終了コードで返す。ハング検知の通知もハング検知ジョブの終了コードと標準エラーで行い(SPEC-008-07)、運用者はジョブスケジューラの障害通知を受けて静観または対処を判断する。relay-gate は CLI の出力以外の通知送信手段を持たない

  REQ-012: relay-gate は UI 画面を持たず、運用者への提示は CLI の標準出力・標準エラー・終了コードだけで行い、実行履歴・監査はジョブスケジューラの責務としてログファイルだけを残すこと

  @atdd_SPEC-012-01-1
  Scenario: SPEC-012-01-1
    Given 任意のスクリプトを起動
    When 結果を確認する
    Then GUI を必要とせず標準出力・標準エラー・終了コードで判定できる

  @atdd_SPEC-012-01-2
  Scenario: SPEC-012-01-2
    Given background 異常を検知
    When ジョブスケジューラでハング検知ジョブの結果を確認する
    Then 警告終了または失敗のジョブステータスと、標準エラーの warning / error の行で異常を判定できる

  @atdd_SPEC-012-01-3
  Scenario: SPEC-012-01-3
    Given relay-gate の設定ファイル一式
    When 通知の宛先・送信コマンドなど CLI の出力以外で運用者へ知らせるための設定項目を探す
    Then 存在しない
