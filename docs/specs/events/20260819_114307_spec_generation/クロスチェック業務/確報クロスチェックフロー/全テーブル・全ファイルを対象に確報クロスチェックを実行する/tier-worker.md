# 全テーブル・全ファイルを対象に確報クロスチェックを実行する - tier-workerティア仕様

## 変更概要

日次バッチで作成されたREQUESTED状態の確報比較依頼をworkerがlease/claim取得し、final_crosscheck_requestsのtarget_tables/target_files列が示す全テーブル・全ファイルを対象に整合性比較を実行する処理をtier-workerに追加する。

## イベント処理仕様

### 確報クロスチェック実行worker

- **トリガー**: CronJob定期実行（1分間隔ポーリング）
- **入力**: RDBの `final_crosscheck_requests` テーブル（status=REQUESTEDの依頼をポーリング。target_tables/target_filesは同テーブルの列として保持）と `comparison_definitions` テーブル（依頼が保持する (job_id, comparison_definition_valid_from) で該当世代をSELECT）
- **出力**: `final_crosscheck_requests` テーブルのstatus更新（CLAIMED→RUNNING→SUCCEEDED/FAILED）
- **処理フロー**:
  1. CronJobが起動し、status=REQUESTEDの確報比較依頼をSELECT FOR UPDATE相当のlease/claim取得（UPDATE ... WHERE status='REQUESTED'）で1件取得する
  2. claim成功後、statusをRUNNINGへ遷移させる
  3. claimしたfinal_crosscheck_requestsレコード自身のjob_id/comparison_definition_valid_from/target_tables/target_files列を読み取る
  4. 依頼が保持する (job_id, comparison_definition_valid_from) でcomparison_definitionsをSELECTし、該当世代を1件解決してcomparator_id（比較実装識別子）を取得する。該当世代が無い場合はstatusをFAILEDへ遷移させ、監査ログに原因を記録する
  5. 解決したcomparator_idを適用し、target_tables/target_filesの全項目についてblue/green実装のデータを突合し、全量比較を実行する
  6. 不一致0件ならstatusをSUCCEEDED、1件以上あればFAILEDへ遷移させ、完了日時を記録する
  7. claim時に取得したlease_expires_atを超過し、かつRUNNINGへ未到達（＝未着手）の場合は次回ポーリングでstatusをREQUESTEDへ差し戻す

#### エラーハンドリング

| エラー種別 | リトライ | 説明 |
|-----------|---------|------|
| lease取得競合（同時claim） | Yes（次回ポーリングで再試行） | UPDATE時の楽観ロック競合はログ記録のみ行い、該当依頼は次回ポーリングに委ねる |
| lease失効かつ未着手 | Yes（自動差し戻し） | statusをREQUESTEDへ差し戻し、worker_id/lease_expires_atをクリアして重複実行を防止する |
| RDB接続エラー | Yes（指数バックオフ3回まで） | usecase層で1回だけログ出力し、statusはRUNNINGのまま維持され次回lease失効判定に委ねる |
| 比較対象データ取得失敗 | No | statusをFAILEDへ遷移させ、監査ログに原因を記録する |
| 比較定義の該当世代なし | No | 依頼が保持する (job_id, comparison_definition_valid_from) に該当するcomparison_definitionsの世代が存在しない場合はstatusをFAILEDへ遷移させ、監査ログに原因を記録する |

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
| target_tables | TEXT | 確報比較対象テーブル一覧（JSON配列。依頼作成時に比較定義の該当世代から複写した解決済みの値） | 変更なし（参照のみ） |
| target_files | TEXT | 確報比較対象ファイル一覧（JSON配列。依頼作成時に比較定義の該当世代から複写した解決済みの値） | 変更なし（参照のみ） |
| job_id | VARCHAR | 確報専用ジョブ定義のJOB_ID（NOT NULL。comparison_definitionsへのFK構成要素） | 追加（参照のみ） |
| comparison_definition_valid_from | DATETIME | 依頼時点で解決した比較定義世代のvalid_from（NOT NULL。comparison_definitionsへのFK構成要素） | 追加（参照のみ） |

### comparison_definitions

比較定義を保持するテーブル。複合主キーは (job_id, valid_from)。本UCでは依頼が保持する (job_id, comparison_definition_valid_from) をキーに該当世代を1件SELECTするのみで、更新しない。

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| job_id | VARCHAR | 比較定義が適用されるJOB_ID（複合PK） | 変更なし（参照のみ） |
| valid_from | DATETIME | 有効期間開始（複合PK） | 変更なし（参照のみ） |
| valid_to | DATETIME | 有効期間終了（現行世代はNULL） | 変更なし（参照のみ） |
| comparator_id | VARCHAR | 比較実装識別子。全量比較に適用する | 変更なし（参照のみ） |

## ビジネスルール

- lease失効かつ未着手の場合はREQUESTEDへ差し戻す（AG-003/AG-004不変条件）
- 確報比較は全テーブル・全ファイルを対象とした全量比較であり、部分比較は許容しない（AG-004不変条件）
- 楽観ロック競合（同時claim）はログ記録のみ行い、業務エラーとして扱わない（LR-008準拠）
- 比較定義は依頼が保持する (job_id, comparison_definition_valid_from) で該当世代を1件に解決する。実行時に現行世代を再解決せず、依頼作成時点で固定した世代を適用する（SPEC-012-03準拠）
- 比較定義の該当世代が存在しない場合はエラーとしてstatusをFAILEDへ遷移させる（暗黙のデフォルト定義へフォールバックしない）

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

  Scenario: workerが依頼の保持する世代キーで比較定義を1件解決しcomparator_idを適用する
    Given comparison_definitions に job_id "final-crosscheck-daily" の旧世代として valid_from "2026-07-01T00:00:00+09:00" valid_to "2026-08-01T00:00:00+09:00" comparator_id "table-file-diff-v1" の行が存在する
    And comparison_definitions に job_id "final-crosscheck-daily" の現行世代として valid_from "2026-08-01T00:00:00+09:00" valid_to NULL comparator_id "table-file-diff-v2" の行が存在する
    And final_crosscheck_requests に run_id "e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f" target_date "2026-08-18" status "CLAIMED" worker_id "worker-01" job_id "final-crosscheck-daily" comparison_definition_valid_from "2026-08-01T00:00:00+09:00" のレコードが存在する
    When workerが SELECT comparator_id FROM comparison_definitions WHERE job_id='final-crosscheck-daily' AND valid_from='2026-08-01T00:00:00+09:00' で比較定義を解決し全量比較を実行する
    Then 解決結果は1件であり、comparator_id "table-file-diff-v2" が全量比較に適用され、旧世代の comparator_id "table-file-diff-v1" は適用されない
```
