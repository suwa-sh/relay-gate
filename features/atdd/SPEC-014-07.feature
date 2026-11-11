# source: docs/usdm/latest/requirements.yaml#requirements[REQ-014].specifications[SPEC-014-07].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-014-07 管理 DB の行の削除には、ハウスキープ専用の DB ロールを使う。権限は対象テーブル(parallel_runs / slot_executions / rapid_runs / rapid_crosscheck_requests / final_crosscheck_requests / monitor_records)の SELECT と DELETE だけとし、業務用接続ロールには DELETE を足さない。接続はハング検知と同じく接続参照名で解決し、認証情報の値を設定に置かない。ハウスキープ設定の管理 DB 接続参照名は、管理 DB を使う機能が 1 つでもある設置、すなわち RAPID_CROSSCHECK_MODE が off 以外の設置と、確報クロスチェックを使う設置(確報クロスチェック worker の設定がある設置)では必須とし、無い・空なら設定エラーとして非 0 で終わり、成果物・管理 DB の行・確報比較依頼のいずれも削除しない。省略できるのは、どちらにも当てはまらない設置(管理 DB を一切使わない設置)だけで、そのときの振る舞いは SPEC-014-08 に従う。インフラ実装の正本と PostgreSQL 構築ロールに、このロールの作成と権限付与を加える。ロール名・キー名・確報クロスチェック worker の設定があるとみなす判定方法(既存の確報系コマンドの判定と揃える)・終了コードは仕様で確定する

  REQ-014: ハウスキープが、ジョブスケジューラの定期ジョブ(1 日 1 回)から起動され、保持日数を過ぎた終了済みの実行の成果物と管理 DB の履歴、および終端した確報比較依頼を自動で削除すること

  @atdd_SPEC-014-07-1
  Scenario: SPEC-014-07-1
    Given 構築済みの管理 DB
    When ハウスキープ専用の DB ロールの権限を確認する
    Then 対象 6 テーブル(parallel_runs / slot_executions / rapid_runs / rapid_crosscheck_requests / final_crosscheck_requests / monitor_records)の SELECT と DELETE だけを持つ

  @atdd_SPEC-014-07-2
  Scenario: SPEC-014-07-2
    Given 構築済みの管理 DB
    When 業務用接続ロールの権限を確認する
    Then どのテーブルにも DELETE 権限を持たない

  @atdd_SPEC-014-07-3
  Scenario: SPEC-014-07-3
    Given ハウスキープ設定
    When 内容を確認する
    Then 認証情報の値は含まれず管理 DB 接続の参照名だけがある

  @atdd_SPEC-014-07-4
  Scenario: SPEC-014-07-4
    Given RAPID_CROSSCHECK_MODE=off で、確報クロスチェックを使う設置(確報クロスチェック worker の設定がある設置)で、ハウスキープ設定の管理 DB 接続参照名が無い・空で、保持日数を過ぎた成果物だけの実行と終端した確報比較依頼がある
    When ハウスキープを実行する
    Then 非 0 の終了コードで終わり、標準エラーに設定エラーの行が出て、成果物・管理 DB の行・確報比較依頼のいずれも削除されずに残る

  @atdd_SPEC-014-07-5
  Scenario: SPEC-014-07-5
    Given RAPID_CROSSCHECK_MODE が off 以外で、ハウスキープ設定の管理 DB 接続参照名が無い・空
    When ハウスキープを実行する
    Then 非 0 の終了コードで終わり、標準エラーに設定エラーの行が出て、成果物・管理 DB の行・確報比較依頼のいずれも削除されずに残る
