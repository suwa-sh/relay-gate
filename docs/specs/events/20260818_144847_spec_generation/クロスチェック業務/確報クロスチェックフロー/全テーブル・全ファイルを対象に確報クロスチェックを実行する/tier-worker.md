# 全テーブル・全ファイルを対象に確報クロスチェックを実行する - tier-workerティア仕様

## 変更概要

日次バッチで作成されたREQUESTED状態の確報比較依頼をworkerがlease/claim取得し、final_crosscheck_requestsのtarget_tables/target_files列が示す全テーブル・全ファイルを対象に整合性比較を実行する処理をtier-workerに追加する。

## イベント処理仕様

### 確報クロスチェック実行worker

- **トリガー**: CronJob定期実行（1分間隔ポーリング）
- **入力**: RDBの `final_crosscheck_requests` テーブル（status=REQUESTEDの依頼をポーリング。target_tables/target_filesは同テーブルの列として保持）
- **出力**: `final_crosscheck_requests` テーブルのstatus更新（CLAIMED→RUNNING→SUCCEEDED/FAILED）
- **処理フロー**:
  1. CronJobが起動し、status=REQUESTEDの確報比較依頼をSELECT FOR UPDATE相当のlease/claim取得（UPDATE ... WHERE status='REQUESTED'）で1件取得する
  2. claim成功後、statusをRUNNINGへ遷移させる
  3. claimしたfinal_crosscheck_requestsレコード自身のtarget_tables/target_files列を読み取る
  4. target_tables/target_filesの全項目についてblue/green実装のデータを突合し、全量比較を実行する
  5. 不一致0件ならstatusをSUCCEEDED、1件以上あればFAILEDへ遷移させ、完了日時を記録する
  6. claim時に取得したlease_expires_atを超過し、かつRUNNINGへ未到達（＝未着手）の場合は次回ポーリングでstatusをREQUESTEDへ差し戻す

#### エラーハンドリング

| エラー種別 | リトライ | 説明 |
|-----------|---------|------|
| lease取得競合（同時claim） | Yes（次回ポーリングで再試行） | UPDATE時の楽観ロック競合はログ記録のみ行い、該当依頼は次回ポーリングに委ねる |
| lease失効かつ未着手 | Yes（自動差し戻し） | statusをREQUESTEDへ差し戻し、worker_id/lease_expires_atをクリアして重複実行を防止する |
| RDB接続エラー | Yes（指数バックオフ3回まで） | usecase層で1回だけログ出力し、statusはRUNNINGのまま維持され次回lease失効判定に委ねる |
| 比較対象データ取得失敗 | No | statusをFAILEDへ遷移させ、監査ログに原因を記録する |

## データモデル変更

### final_crosscheck_requests

target_tables/target_filesは本テーブルの列として参照する。run共通実行設定を保持するexecution_specs（run_idのFK参照元）は、対象runの存在確認のためSELECTのみ行う（更新しない）。

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | VARCHAR | 確報比較依頼の一意識別子（PK） | 変更なし |
| status | VARCHAR | REQUESTED/CLAIMED/RUNNING/SUCCEEDED/FAILED/ABORTED | 更新（本UCで遷移） |
| lease_expires_at | DATETIME | lease期限 | 更新（claim時に設定、失効時にクリア） |
| worker_id | VARCHAR | lease取得worker識別子 | 更新（claim時に設定、失効時にクリア） |
| completed_at | DATETIME | 比較完了日時 | 追加（SUCCEEDED/FAILED確定時に設定） |
| target_tables | TEXT | 確報比較対象テーブル一覧（JSON配列） | 変更なし（参照のみ） |
| target_files | TEXT | 確報比較対象ファイル一覧（JSON配列） | 変更なし（参照のみ） |

## ビジネスルール

- lease失効かつ未着手の場合はREQUESTEDへ差し戻す（AG-003/AG-004不変条件）
- 確報比較は全テーブル・全ファイルを対象とした全量比較であり、部分比較は許容しない（AG-004不変条件）
- 楽観ロック競合（同時claim）はログ記録のみ行い、業務エラーとして扱わない（LR-008準拠）

## CLI 出力/画面表示マッピング

### 確報クロスチェック実行画面

- **route**: /cli/final-crosscheck/run
- **表示要素とコンポーネントマッピング**:

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 実行対象一覧 | テーブル | CrossCheckRequestRow（variant: final） | run_id/status/lease_expires_at/worker_idを表示 |
| 実行結果パネル | パネル | RunnerResultPanel | 全量比較実行中/完了時のログをターミナル調に表示 |

- **デザイントークン参照**:

| 用途 | トークン | 値 |
|------|---------|---|
| RUNNING表示色 | var(--color-blue-600) | blue-600 (#2563EB) |
| ターミナルパネル背景 | var(--color-slate-900) | slate-900 (#0F172A) |

- **UIロジック**: 状態管理はRDBのstatus値を都度反映（クライアント側での楽観更新は行わない）。バリデーションはCronJob起動時のlease/claim取得の排他制御に依存する。ローディングは全量比較実行中はRUNNING表示を継続する。エラーハンドリングはFAILED時にRunnerResultPanelへ異常終了を明示する（差分件数・レポートURIは表示しない）

## 共通コンポーネント参照

参照元: `docs/specs/events/20260818_144847_spec_generation/_cross-cutting/ux-ui/common-components.md`（状態一覧+フィルターパターン、実行結果ターミナル表示パターン）

| コンポーネント | インポートパス | variant | Props マッピング |
|---|---|---|---|
| CrossCheckRequestRow | src/components/domain/CrossCheckRequestRow.tsx | final | runId←run_id, jobIdOrTargetDate←final_crosscheck_requests.target_date, state←status, leaseExpiry←lease_expires_at, workerId←worker_id |
| RunnerResultPanel | src/components/domain/RunnerResultPanel.tsx | background | runId←run_id, stdout/stderr/exitCode←全量比較実行ログ（target_tables/target_filesの突合結果） |

適用パターン: 状態一覧+フィルターパターン（一覧表示）と実行結果ターミナル表示パターン（実行ログ表示）の併用。FAILED時はRunnerResultPanelで異常終了を明示し、差分件数・レポートURIは表示しない

## ティア完了条件（BDD）

```gherkin
Feature: 全テーブル・全ファイルを対象に確報クロスチェックを実行する - tier-worker

  Scenario: workerがREQUESTED状態の確報比較依頼をlease/claim取得しRUNNINGへ遷移させる
    Given execution_specs に run_id "e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f"、job_id "daily-settlement"、job_map_version "v1.4.0"、hang_detect_limit_minutes 30 の行が存在する
    And final_crosscheck_requests に run_id "e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f" target_date "2026-08-18" status "REQUESTED" のレコードが存在する
    When CronJobがworker_id "worker-01" として UPDATE final_crosscheck_requests SET status='CLAIMED', worker_id='worker-01', lease_expires_at=NOW()+10m WHERE run_id='e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f' AND status='REQUESTED' を実行する
    Then 更新件数が1件となり、statusは "CLAIMED" を経て "RUNNING" へ遷移する

  Scenario: lease失効かつ未着手の依頼が次回ポーリングでREQUESTEDへ差し戻される
    Given execution_specs に run_id "e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f"、job_id "daily-settlement"、job_map_version "v1.4.0"、hang_detect_limit_minutes 30 の行が存在する
    And final_crosscheck_requests に run_id "e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f" status "CLAIMED" worker_id "worker-02" lease_expires_at "2026-08-18T02:00:00+09:00" のレコードが存在し、現在時刻が "2026-08-18T02:15:00+09:00" である
    When CronJobが定期ポーリングを実行する
    Then run_id "e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f" のstatusが "REQUESTED" へ差し戻され、worker_idとlease_expires_atがNULLへ更新される
