# 実装レビュー回答

## 2026-08-18 ユーザー回答

- 機能: 承認
- RDB: PostgreSQLを採用
- 監査: slot起動の監査ログを追記する

## 現在の扱い

機能の到達点は承認済み。ただし、PostgreSQL接続契約と監査ログ追記契約は現行仕様・実装へ
未反映のため、最終承認およびPR作成は保留する。仕様へ反映し、実装・テスト・独立検証を
更新した後、新しいレビュー資料で最終認識合わせを行う。

## 2026-08-18 13:05 ユーザー回答(訂正版 feedback request のレビュー)

回答: `公開=A / 再実行=A / 監査保存=A / 実行設定=A / 履歴=A / 補足=なし`(すべて推奨案を採用)

- 公開: 訂正版 feedback request(`20260818_113601_impl_feedback_6078c4ed`、
  supersedes: `20260817_234841_impl_feedback_6078c4ed`)の公開を承認
- 再実行の同一性: 新しい `run_id` を発行し `parent_run_id` で元依頼と関連付ける。既存履歴を上書きしない
- 監査テーブル保存構成: 初期は非 partition の `audit_logs` + `occurred_at` / `run_id` 索引 +
  専用保守権限による6か月保持。実測負荷の発生時に partition 設計へ移行
- slot 別実行設定と試行 identity: run 共通 execution spec と slot 別設定を分離。Runner 実行結果は
  slot + `attempt_id` を含む identity。`STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED` を正式状態とする
- 履歴方針: append-only の `runner_result_events` と現在状態 `runner_results` snapshot を
  同一 transaction で更新

回答は draft の推奨内容と exact 一致(新規の意味変更なし)のため、この承認を
「feedback 公開許可」として記録し、S8 publish へ進む。この承認は PR 許可ではない。
publish 後は blocked_on_spec で停止し、dist-pipeline 反映後に再開する。

## 2026-08-22 ユーザー回答(仕様還流後の再実装レビュー。S9 evidence 20260822_130000_s9_review_generated)

回答: `実装=A / CR-012=A / CR-011=A / CR-014=A / CR-015=A / CR-013=A / CR-016=A / CR-017=A / CR-018=C-1 / 補足=なし`

- 実装: 承認(還流後仕様に追随した slot 選択起動。PostgreSQL 経路・監査 hash chain・STARTING 固定)
- CR-012: A = 本 UC で起動イベント送出失敗時の補償記録を仕様化
- CR-011: A = 実装の仮置き形式(契約 fields 順 `|` 連結 + SHA-256 hex)を event_hash 正規化として契約化
- CR-014: A = additional_args / fixed_args は JSON 配列で保存
- CR-015: A = uuid→uuid / string,text→text / integer→integer / datetime→timestamptz(μs, UTC)
- CR-013: A = 並走 Scenario の Then を本 UC 責務内へ改め、元 Then は UC 横断の受け入れへ
- CR-016: A = USDM SPEC-009-03 文言を spec / rdb-schema に合わせる
- CR-017: A = credential_ref は認証情報ディレクトリ方式で解決
- CR-018: **C-1(draft の推奨案 A から変更)** = ジョブマップを slot ごとに独立ファイルで持つ
  (`RELAYGATE_JOB_MAP_PATH_BLUE` / `_GREEN` 相当。各ファイルが自分の version と job 別の
  host / exec_user / script_path / work_dir / fixed_args / impl_version / credential_ref /
  hang_detect_limit_minutes を持つ)。`job_map_version` は execution_specs(run 共通)から
  slot_execution_specs(slot 別)へ移動する(rdb-schema 変更、CR-005 と同型)。
  `hang_detect_limit_minutes` は background に選ばれた slot のジョブマップ値を採用する
  (RDRA 条件「background role ごと」と整合)。
  理由: blue / green は別ライフサイクルでメンテナンスされるため、1 ファイル共有はリリース競合を生む。
  UC 前提「runner 設定の差し替えだけで新世代を起動できる」とも整合。

扱い: CR-018 は draft の推奨案と異なるため、S8 refresh で draft を更新し S9 を再生成したうえで
公開許可(review_approved)を記録する。この承認は PR 許可ではない。publish 後は blocked_on_spec で停止し、
dist-pipeline 反映後に再開する。
