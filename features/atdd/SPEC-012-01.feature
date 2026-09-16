# source: docs/usdm/latest/requirements.yaml#requirements[REQ-012].specifications[SPEC-012-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-012-01 すべてのスクリプトは CLI として起動され、結果を標準出力・標準エラー・終了コードで返す。ハング検知の通知は warning / error のメール送信で行い、運用者は静観または対処を判断する

  REQ-012: relay-gate は UI 画面を持たず、運用者への提示は CLI の標準出力・標準エラー・終了コードと通知メールで行い、実行履歴・監査はジョブスケジューラの責務としてログファイルだけを残すこと

  @atdd_SPEC-012-01-1
  Scenario: SPEC-012-01-1
    Given 任意のスクリプトを起動
    When 結果を確認する
    Then GUI を必要とせず標準出力・標準エラー・終了コードで判定できる

  @atdd_SPEC-012-01-2
  Scenario: SPEC-012-01-2
    Given background 異常を検知
    When 通知を確認する
    Then warning / error のメールが運用者に届く
