# source: docs/usdm/latest/requirements.yaml#requirements[REQ-012].specifications[SPEC-012-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-012-02 ジョブの実行履歴・監査はジョブスケジューラの責務とし、relay-gate は Runner Result Contract の成果物と各スクリプトの実行ログをファイルとして残す

  REQ-012: relay-gate は UI 画面を持たず、運用者への提示は CLI の標準出力・標準エラー・終了コードと通知メールで行い、実行履歴・監査はジョブスケジューラの責務としてログファイルだけを残すこと

  @atdd_SPEC-012-02-1
  Scenario: SPEC-012-02-1
    Given ジョブが実行された
    When 履歴を調べる
    Then ジョブスケジューラの実行履歴と relay-gate の成果物・実行ログで追跡できる
