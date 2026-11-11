# source: docs/usdm/latest/requirements.yaml#requirements[REQ-014].specifications[SPEC-014-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-014-01 ハウスキープ専用のスクリプト(housekeep.sh)を追加し、ジョブスケジューラの定期ジョブとして 1 日 1 回起動する想定とする。業務ジョブの起動時には削除しない。保持日数は基盤適用設計者が所有するハウスキープ設定で持ち、既定は 90 日とする。値は正の整数とし、設定検証で検査する。削除したくない場合は定期ジョブを登録しない。設定のファイル名・キー名・終了コード・接続する管理 DB は仕様(CLI 契約・設定契約)で確定する

  REQ-014: ハウスキープが、ジョブスケジューラの定期ジョブ(1 日 1 回)から起動され、保持日数を過ぎた終了済みの実行の成果物と管理 DB の履歴、および終端した確報比較依頼を自動で削除すること

  @atdd_SPEC-014-01-1
  Scenario: SPEC-014-01-1
    Given ハウスキープ設定で保持日数を指定していない
    When ハウスキープを実行する
    Then 最も遅い終了日時から 90 日を過ぎた終了済みの実行は削除され、90 日以内の終了済みの実行は残る

  @atdd_SPEC-014-01-2
  Scenario: SPEC-014-01-2
    Given ハウスキープ設定の保持日数が 0・負の数・整数でない値のいずれかである
    When 設定検証を実行する
    Then 非 0 の終了コードで終わり、標準エラーに保持日数の値が不正である旨の行が出る

  @atdd_SPEC-014-01-3
  Scenario: SPEC-014-01-3
    Given 保持日数を過ぎた終了済みの実行がある
    When 業務ジョブ(facade)を起動する
    Then その実行の成果物と管理 DB の行は削除されずに残る

  @atdd_SPEC-014-01-4
  Scenario: SPEC-014-01-4
    Given 設定所有区分
    When ハウスキープ設定の所有者を確認する
    Then 基盤適用設計者である
