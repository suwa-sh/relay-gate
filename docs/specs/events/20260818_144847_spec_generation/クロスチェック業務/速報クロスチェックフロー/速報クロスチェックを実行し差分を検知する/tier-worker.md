# 速報クロスチェックを実行し差分を検知する - バックエンドワーカーティア仕様

## 変更概要

REQUESTED状態の速報比較依頼をRDBのlease/claim機構で排他的に取得し、blue/green Runner実行結果を比較して差分を検知、速報比較依頼状態をSUCCEEDED/FAILEDへ確定し速報比較結果を新規作成する処理を追加する。

## イベント処理仕様

### 速報クロスチェック実行worker
- **トリガー**: CronJob定期実行（1分間隔想定）によるRDB lease/claim取得
- **入力**: `rapid_crosscheck_requests`（status='REQUESTED'の行、およびlease失効判定対象のCLAIMED行）、`runner_results`（依頼のblue_run_id/blue_attempt_id/green_run_id/green_attempt_idで特定した起動試行の実行結果）
- **出力**: `rapid_crosscheck_requests` の status/lease_expires_at/worker_id 更新、`rapid_crosscheck_results` への新規INSERT
- **処理フロー**:
  1. presentation層がCronJobトリガーを受け付ける
  2. usecase層が `RunRapidCrosscheckCommand` を発行する
  3. gateway層がREQUESTED状態の速報比較依頼を1件、`FOR UPDATE`相当の排他制御でCLAIMEDへlease取得する（worker_id・lease_expires_atを設定）
  4. 同時にlease失効かつ未着手（CLAIMEDのままlease_expires_at経過）の行をREQUESTEDへ差し戻す
  5. gateway層が比較対象のrunner_resultsを (blue_run_id, 'blue', 'background', blue_attempt_id) と (green_run_id, 'green', 'background', green_attempt_id) の起動試行identityで取得する
  6. domain層がstdout/stderr/exit_codeを比較し差分件数・OK/NG判定を算出する
  7. usecase層が速報比較依頼status（SUCCEEDED/FAILED）を確定しgateway層へ永続化を依頼する
  8. gateway層が `rapid_crosscheck_requests` を更新し `rapid_crosscheck_results` へINSERTする
  9. presentation層が処理結果を構造化ログへ出力する
- **エラーハンドリング**:

| エラー種別 | リトライ | 説明 |
|-----------|---------|------|
| lease失効かつ未着手 | Yes（自動差し戻し） | REQUESTEDへ差し戻し、次回CronJobで別workerが再取得できるようにする |
| 比較対象のRunner実行結果が片方未確定 | Yes（次回CronJobで再判定） | CLAIMEDのまま比較を行わず処理を終了し、lease失効判定に委ねる |
| 楽観ロック競合（複数workerの同時claim） | No（片方は0件取得として正常終了） | 楽観ロック競合ログを記録し処理を継続する（LR-008準拠） |
| RDB接続エラー | Yes（次回CronJob実行時に再試行） | 標準エラーへ記録し終了コード1で終了する |

## データモデル変更

### rapid_crosscheck_requests（速報比較依頼）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| blue_run_id / blue_attempt_id | UUID / VARCHAR | 比較対象のblue slot側background起動試行の特定キー | 参照のみ |
| green_run_id / green_attempt_id | UUID / VARCHAR | 比較対象のgreen slot側background起動試行の特定キー | 参照のみ |
| status | VARCHAR | REQUESTED→CLAIMED→RUNNING→SUCCEEDED/FAILED | 変更（本UCで更新） |
| lease_expires_at | DATETIME | lease期限 | 変更（claim時に設定、差し戻し時にクリア） |
| worker_id | VARCHAR | 取得中のworker識別子 | 変更（claim時に設定、差し戻し時にクリア） |

### runner_results（Runner実行結果、参照のみ）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id / slot_type / role_type / attempt_id | - | 起動試行のidentity（複合PK）。依頼の4項目で特定する | 参照のみ |
| stdout_path / stderr_path / exit_code / status | - | 比較対象データ。statusはSTARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED | 参照のみ |

### rapid_crosscheck_results（速報比較結果）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | UUID | 速報比較依頼のrun_idを参照するFK（PK、1:1関係） | 追加（INSERT対象） |
| comparison_result | VARCHAR | OK/NG判定 | 追加（比較結果） |
| diff_count | INT | 差分件数 | 追加（比較結果） |
| diff_detail_uri | VARCHAR | 差分詳細レポートURI（nullable、NG時のみ生成） | 追加 |
| completed_at | DATETIME | 比較完了日時 | 追加（比較完了時刻） |

## ビジネスルール

- CLAIMED状態でlease失効かつworkerが未着手の場合はREQUESTEDへ差し戻し、重複実行を防止する（AG-003不変条件）
- 速報比較依頼のRUNNING→SUCCEEDED/FAILEDへの遷移はworkerのexitcode判定に基づき、対話確認は不要（自動遷移）
- diff_countが1件以上の場合はcomparison_result='NG'とし、速報比較依頼状態をFAILEDへ確定してハング検知記録（速報クロスチェック異常）の検知対象とする
- run_id/parent_run_idを構造化ログの必須フィールドに含め実行系譜を追跡可能にする（CTP-004）
- CLI応答は10秒以内、スループットは10TPS程度を目安とする（CTP-009）

## CLI 出力/画面表示マッピング

### 速報クロスチェック実行画面

- **route**: /cli/rapid-crosscheck/run
- **表示要素とコンポーネントマッピング**:

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 実行対象のRunner実行結果 | ターミナル調パネル | RunnerResultPanel（variant: background） | 比較対象のstdout/stderr/exitCodeを表示 |
| 速報比較依頼の状態遷移 | バッジ | StatusBadge（running/succeeded/failed） | CLAIMED→RUNNING→SUCCEEDED/FAILEDの遷移を色分け表示 |

- **デザイントークン参照**:

| 用途 | トークン | 値 |
|------|---------|---|
| RUNNING状態背景 | var(--color-blue-100) | #DBEAFE |
| ターミナルパネル背景 | var(--color-slate-900) | #0F172A |
| ターミナルパネルフォント | var(--font-family-ff-mono) | JetBrains Mono, ui-monospace, SFMono-Regular, Menlo, monospace |

- **UIロジック**: 状態管理はlease/claim結果に基づきCronJob実行ごとに更新する。バリデーションは比較対象データ（blue/green双方）の存在確認。ローディングは将来ダッシュボードでRUNNING中の表示に用いる。エラーハンドリングはOK/NG判定をProgressive Disclosureで最上部に提示し、差分詳細は展開後段に配置する（ux-design.md準拠）

## 共通コンポーネント参照

参照元: `docs/specs/events/20260818_144847_spec_generation/_cross-cutting/ux-ui/common-components.md`（実行結果ターミナル表示パターン）

| コンポーネント | インポートパス | variant | Props マッピング |
|---|---|---|---|
| RunnerResultPanel | src/components/domain/RunnerResultPanel.tsx | background | runId←run_id, slot←slot_type（blue/green）, role←'background', startedAt←started_at, stdout/stderr/exitCode←比較対象Runner実行結果 |
| StatusBadge | src/components/ui/StatusBadge.tsx | claimed/running/succeeded/failed | value←status（CLAIMED→RUNNING→SUCCEEDED/FAILEDの遷移を色分け表示） |

適用パターン: 実行結果ターミナル表示パターン（background variant。起動直後・実行中・完了時のrun_id/slot/role/started_at/状態を含めて表示し、キャッシュを持たず呼び出しごとに最新値を取得する）

## ティア完了条件（BDD）

```gherkin
Feature: 速報クロスチェックを実行し差分を検知する - バックエンドワーカーティア

  Scenario: REQUESTED行をlease取得し差分なしでSUCCEEDEDへ確定する
    Given execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement" の行と slot_execution_specs の blue/green 行が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="background", attempt_id="att-blue-0001", status="SUCCEEDED") と (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001", status="SUCCEEDED") の行が完全一致の出力で存在する
    And rapid_crosscheck_requests に (run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", blue_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", blue_attempt_id="att-blue-0001", green_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", green_attempt_id="att-green-0001", status="REQUESTED") の行が存在する
    When worker presentation層がCronJobトリガーを受け付ける
    Then gateway層は run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af" のstatusを "CLAIMED"→"RUNNING"→"SUCCEEDED" の順に更新し、rapid_crosscheck_results へ (run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", comparison_result="OK", diff_count=0) をINSERTする
```
