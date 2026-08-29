# 速報クロスチェック結果を確認する - バックエンドワーカーティア仕様

## 変更概要

速報比較依頼・速報比較結果をrun_id/job_id指定でSELECTし、CLI標準出力へ整形表示するクエリ処理を追加する。状態遷移・書き込みは伴わない参照専用処理。

## イベント処理仕様

### 速報クロスチェック結果照会
- **トリガー**: 障害調査担当者によるCLIコマンド `relaygate rapid-crosscheck result --job-id {job_id}` または `--run-id {run_id}` の手動実行
- **入力**: `rapid_crosscheck_requests` テーブル（job_id/run_id条件でSELECT）、`rapid_crosscheck_results` テーブル（run_idでLEFT JOIN）
- **出力**: 標準出力へ run_id/状態/comparison_result/diff_count/diff_detail_uri を整形表示（更新するテーブルなし）
- **処理フロー**:
  1. presentation層がCLI引数（`--job-id` または `--run-id`）を解析・バリデーションする
  2. usecase層が `GetRapidCrosscheckResultQuery` を発行する
  3. gateway層が `rapid_crosscheck_requests` を job_id/run_id で検索し、対応する `rapid_crosscheck_results` をLEFT JOINで取得する
  4. domain層が状態ラベル・OK/NG判定を整形する
  5. presentation層が標準出力へ結果を出力し、終了コード0で終了する
- **エラーハンドリング**:

| エラー種別 | リトライ | 説明 |
|-----------|---------|------|
| 対象job_id/run_idの速報比較依頼が存在しない | No | 標準エラーへメッセージを出力し終了コード1で終了する |
| job_id/run_idいずれも未指定 | No | presentation層のバリデーションで検知し終了コード2で終了する |
| RDB接続エラー | No（呼び出し元ジョブスケジューラの再実行に委ねる） | 標準エラーへ技術例外メッセージを出力し終了コード1で終了する |

## データモデル変更

### rapid_crosscheck_requests（速報比較依頼）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | UUID | 速報比較依頼の一意識別子（PK） | 参照のみ |
| parent_run_id | UUID | リラン元依頼のrun_id（nullable）。リラン系譜の表示に用いる | 参照のみ |
| job_id | VARCHAR | 対象ジョブID | 参照のみ |
| blue_run_id / blue_attempt_id | UUID / VARCHAR | 比較対象のblue slot側background起動試行の特定キー | 参照のみ |
| green_run_id / green_attempt_id | UUID / VARCHAR | 比較対象のgreen slot側background起動試行の特定キー | 参照のみ |
| status | VARCHAR | REQUESTED/CLAIMED/RUNNING/SUCCEEDED/FAILED/ABORTED | 参照のみ |
| lease_expires_at | DATETIME | lease期限（nullable） | 参照のみ |
| worker_id | VARCHAR | 取得中のworker識別子（nullable） | 参照のみ |

### rapid_crosscheck_results（速報比較結果）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | UUID | 速報比較依頼のrun_idを参照するFK（PK） | 参照のみ |
| comparison_result | VARCHAR | OK/NG判定 | 参照のみ |
| diff_count | INT | 差分件数 | 参照のみ |
| diff_detail_uri | VARCHAR | 差分詳細レポートURI（nullable） | 参照のみ |
| completed_at | DATETIME | 比較完了日時 | 参照のみ |

## ビジネスルール

- 本UCは速報比較依頼・速報比較結果の状態を変更しない（参照専用）
- リランで作成された依頼はparent_run_idで元依頼へ関連付いており、元依頼のレコード・状態・履歴は不変である。本UCはparent_run_idを表示してリラン系譜を追跡可能にする（CTP-004）
- CLI応答は10秒以内に返す（CTP-009準拠）
- comparison_result/diff_count/diff_detail_uriは確報クロスチェック結果とは独立したCrossCheckRequestRowのvariant（`rapid`）で表示し、確報側と混同しない

## CLI 出力/画面表示マッピング

### 速報クロスチェック結果確認画面

- **route**: /cli/rapid-crosscheck/result
- **表示要素とコンポーネントマッピング**:

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 速報比較依頼一覧行 | テーブル行 | CrossCheckRequestRow（variant: rapid） | run_id/job_id/状態/lease期限/worker識別子を表示 |
| 状態バッジ | バッジ | StatusBadge | REQUESTED〜ABORTEDの状態を色分け表示（label併記） |
| OK/NG判定・差分件数 | テキスト | ResultTable | comparison_result/diff_count/diff_detail_uriを表示。差分詳細は展開後段に配置（Progressive Disclosure） |

- **デザイントークン参照**:

| 用途 | トークン | 値 |
|------|---------|---|
| SUCCEEDED状態背景 | var(--color-green-100) | #DCFCE7 |
| FAILED状態文字色 | var(--color-red-600) | #DC2626 |
| REQUESTED状態背景 | var(--color-amber-100) | #FEF3C7 |

- **UIロジック**: 状態管理はCLI実行ごとにステートレス（DBから都度取得）。バリデーションはjob_id/run_idいずれか必須。ローディングは将来ダッシュボードでのみ表示（CLIは同期応答）。エラーハンドリングは標準エラー+終了コードで表現し、将来ダッシュボードではBannerのerror variantで表示する

## 共通コンポーネント参照

参照元: `docs/specs/events/20260818_144847_spec_generation/_cross-cutting/ux-ui/common-components.md`（状態一覧+フィルターパターン）

| コンポーネント | インポートパス | variant | Props マッピング |
|---|---|---|---|
| CrossCheckRequestRow | src/components/domain/CrossCheckRequestRow.tsx | rapid | runId←run_id, jobIdOrTargetDate←job_id, state←status, leaseExpiry←lease_expires_at, workerId←worker_id |
| StatusBadge | src/components/ui/StatusBadge.tsx | requested/claimed/running/succeeded/failed/aborted | value←status（REQUESTED〜ABORTEDを色トークンへマッピング） |
| ResultTable | src/components/ui/ResultTable.tsx | default | comparison_result/diff_count/diff_detail_uri をProgressive Disclosureで表示（OK/NG判定を最上部、diff_detail_uriは展開後段） |

適用パターン: 状態一覧+フィルターパターン（rapid/finalの区別はCrossCheckRequestRowのvariantで行い、状態カラートークンはStatusBadgeと共有する）

## ティア完了条件（BDD）

```gherkin
Feature: 速報クロスチェック結果を確認する - バックエンドワーカーティア

  Scenario: run_id指定でSUCCEEDED結果を取得する
    Given execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement" の行が存在する
    And rapid_crosscheck_requests に (run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", job_id="daily-settlement", blue_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", blue_attempt_id="att-blue-0001", green_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", green_attempt_id="att-green-0001", status="SUCCEEDED") の行が存在する
    And rapid_crosscheck_results に (run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", comparison_result="OK", diff_count=0) の行が存在する
    When worker presentation層が `relaygate rapid-crosscheck result --run-id c41d7e08-2b95-4f36-a8d1-5e7c93b204af` を受け付ける
    Then gateway層はrun_id "c41d7e08-2b95-4f36-a8d1-5e7c93b204af" でLEFT JOINしたSELECTを1回実行し、標準出力に comparison_result "OK" を出力して終了コード 0 で終了する
```
