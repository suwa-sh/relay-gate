# 確報クロスチェック結果を確認する - tier-workerティア仕様

## 変更概要

リリース判断者向けに、確報比較依頼（final_crosscheck_requests）を対象日で照会するCLI照会コマンドをtier-workerに追加する。CronJobではなくオンデマンドのCLI実行がトリガーとなる読み取り専用のユースケースである。

## イベント処理仕様

### 確報クロスチェック結果照会

- **トリガー**: CLIコマンド実行（`relaygate final-crosscheck result --target-date {YYYY-MM-DD}`。リリース判断者または運用者によるオンデマンド照会。CronJob/定期実行ではない）
- **入力**: RDBの `final_crosscheck_requests` テーブル（対象日でフィルタ）
- **出力**: CLI標準出力への確報比較依頼一覧（run_id/target_date/status/lease_expires_at/worker_id）
- **処理フロー**:
  1. CLI引数（--target-date）をパースし形式（YYYY-MM-DD）を検証する
  2. `final_crosscheck_requests` テーブルを target_date で SELECT する
  3. 該当レコードが存在しない場合はエラー終了する
  4. 取得したレコードの status を表示用ラベル（SUCCEEDED=正常終了、FAILED=異常終了、RUNNING=実行中 等）に変換する
  5. 標準出力へrun_id/target_date/status/lease_expires_at/worker_idを整形出力し、終了コード0で終了する

#### エラーハンドリング

| エラー種別 | リトライ | 説明 |
|-----------|---------|------|
| 対象日の確報比較依頼が存在しない | No | 標準エラーへ「確報比較依頼が見つかりません」を出力し終了コード1で終了する（業務エラー） |
| target-date形式不正 | No | 標準エラーへバリデーションエラーメッセージを出力し終了コード2で終了する |
| RDB接続エラー | Yes（3回まで指数バックオフ） | 技術例外としてgatewayでスローされusecaseで集約キャッチ、終了コード1で終了する |

## データモデル変更

### final_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | VARCHAR | 確報比較依頼の一意識別子（PK） | 変更なし（参照のみ） |
| target_date | DATE | 確報クロスチェックの対象日 | 変更なし（参照のみ） |
| status | VARCHAR | REQUESTED/CLAIMED/RUNNING/SUCCEEDED/FAILED/ABORTED | 変更なし（参照のみ） |
| lease_expires_at | DATETIME | lease期限（nullable） | 変更なし（参照のみ） |
| worker_id | VARCHAR | lease取得worker識別子（nullable） | 変更なし（参照のみ） |

## ビジネスルール

- 確報比較依頼の応答契約（比較結果・差分件数・レポートURIを含めない）は本UCの照会結果にも適用され、statusおよびlease関連情報のみを表示する。差分件数・レポートURI等の詳細は保持しない
- 確報クロスチェック結果確認画面は速報クロスチェック結果確認画面とは独立した動線とし、混同を避ける
- 対象日にレコードが存在しない場合は業務エラー（終了コード1）として扱う

## CLI 出力/画面表示マッピング

### 確報クロスチェック結果確認画面

- **route**: /cli/final-crosscheck/result
- **表示要素とコンポーネントマッピング**:

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 確報比較依頼一覧 | テーブル | CrossCheckRequestRow（variant: final） | run_id/target_date/status/lease_expires_at/worker_idを一覧表示 |
| 状態バッジ | バッジ | StatusBadge | status（REQUESTED/CLAIMED/RUNNING/SUCCEEDED/FAILED/ABORTED）を色分け表示 |

- **デザイントークン参照**:

| 用途 | トークン | 値 |
|------|---------|---|
| SUCCEEDED表示色 | var(--color-green-600) | green-600 (#16A34A) |
| FAILED表示色 | var(--color-red-600) | red-600 (#DC2626) |
| REQUESTED表示色 | var(--color-amber-600) | amber-600 (#D97706) |

- **UIロジック**: 状態管理はCLI実行ごとにステートレス（都度RDBから最新値を取得）。バリデーションはtarget-date形式チェックのみ。ローディングはCLI実行中のため概念上該当なし（将来ダッシュボードではスケルトン表示）。エラーハンドリングは標準エラー出力+終了コードで表現し、将来ダッシュボードではBanner（error variant）で表示する

## 共通コンポーネント参照

参照元: `docs/specs/events/20260818_144847_spec_generation/_cross-cutting/ux-ui/common-components.md`（状態一覧+フィルターパターン）

| コンポーネント | インポートパス | variant | Props マッピング |
|---|---|---|---|
| CrossCheckRequestRow | src/components/domain/CrossCheckRequestRow.tsx | final | runId←run_id, jobIdOrTargetDate←target_date, state←status, leaseExpiry←lease_expires_at, workerId←worker_id |
| StatusBadge | src/components/ui/StatusBadge.tsx | requested/claimed/running/succeeded/failed/aborted | value←status（REQUESTED〜ABORTEDを色分け表示） |

適用パターン: 状態一覧+フィルターパターン（rapid/finalの区別はCrossCheckRequestRowのvariantで行う。比較結果・差分件数・レポートURIは応答契約により表示しない）

## ティア完了条件（BDD）

```gherkin
Feature: 確報クロスチェック結果を確認する - tier-worker

  Scenario: worker presentation層が対象日の確報比較依頼を返す
    Given execution_specs に run_id "e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f"、job_id "daily-settlement"、job_map_version "v1.4.0"、hang_detect_limit_minutes 30 の行が存在する
    And run_id "e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f" の確報比較依頼が target_date "2026-08-18" status "SUCCEEDED" で final_crosscheck_requests に存在する
    When tier-workerのpresentation層が GetFinalCrossCheckResultQuery(target_date="2026-08-18") を受け取る
    Then gatewayは final_crosscheck_requests から run_id "e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f" のレコードを1件取得し、presentation層は終了コード 0 で標準出力へ status "SUCCEEDED" を返す
```
