# source: docs/usdm/latest/requirements.yaml#requirements[REQ-014].specifications[SPEC-014-06].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-014-06 ハウスキープは削除した件数を標準出力に出し、失敗は標準エラーに出して非 0 で終わる

  REQ-014: ハウスキープが、ジョブスケジューラの定期ジョブ(1 日 1 回)から起動され、保持日数を過ぎた終了済みの実行の成果物と管理 DB の履歴、および終端した確報比較依頼を自動で削除すること

  @atdd_SPEC-014-06-1
  Scenario: SPEC-014-06-1
    Given 保持日数を過ぎた実行の単位と確報比較依頼がある
    When ハウスキープが成功する
    Then 標準出力に削除した件数が出て、終了コード 0 で終わる

  @atdd_SPEC-014-06-2
  Scenario: SPEC-014-06-2
    Given 成果物を削除待ちの置き場へ移したあとに処理が失敗する
    When ハウスキープが終わる
    Then 標準エラーに失敗の内容が出て、非 0 の終了コードで終わる

  @atdd_SPEC-014-06-3
  Scenario: SPEC-014-06-3
    Given 管理 DB の行の削除が失敗する
    When ハウスキープが終わる
    Then 標準エラーに失敗の内容が出て、非 0 の終了コードで終わる
