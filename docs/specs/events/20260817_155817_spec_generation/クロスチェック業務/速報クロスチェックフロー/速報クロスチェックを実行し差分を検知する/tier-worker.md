# 速報クロスチェックを実行し差分を検知する - バックエンドワーカーティア仕様

## 変更概要

REQUESTED状態の速報比較依頼をRDBのlease/claim機構で排他的に取得し、blue/green Runner実行結果を比較して差分を検知、速報比較依頼状態をSUCCEEDED/FAILEDへ確定し速報比較結果を新規作成する処理を追加する。

## イベント処理仕様

### 速報クロスチェック実行worker
- **トリガー**: CronJob定期実行（1分間隔想定）によるRDB lease/claim取得
- **入力**: `rapid_crosscheck_requests`（status='REQUESTED'の行、およびlease失効判定対象のCLAIMED行）、`runner_results`（run_id一致のblue/green実行結果）
- **出力**: `rapid_crosscheck_requests` の status/lease_expires_at/worker_id 更新、`rapid_crosscheck_results` への新規INSERT
- **処理フロー**:
  1. presentation層がCronJobトリガーを受け付ける
  2. usecase層が `RunRapidCrosscheckCommand` を発行する
  3. gateway層がREQUESTED状態の速報比較依頼を1件、`FOR UPDATE`相当の排他制御でCLAIMEDへlease取得する（worker_id・lease_expires_atを設定）
  4. 同時にlease失効かつ未着手（CLAIMEDのままlease_expires_at経過）の行をREQUESTEDへ差し戻す
  5. gateway層がblue/green双方のrunner_resultsをrun_idで取得する
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
| status | VARCHAR | REQUESTED→CLAIMED→RUNNING→SUCCEEDED/FAILED | 変更（本UCで更新） |
| lease_expires_at | DATETIME | lease期限 | 変更（claim時に設定、差し戻し時にクリア） |
| worker_id | VARCHAR | 取得中のworker識別子 | 変更（claim時に設定、差し戻し時にクリア） |

### rapid_crosscheck_results（速報比較結果）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | VARCHAR | 速報比較依頼のrun_idを参照するFK（PK） | 追加（INSERT対象） |
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

参照元: `docs/specs/events/20260817_155817_spec_generation/_cross-cutting/ux-ui/common-components.md`（実行結果ターミナル表示パターン）

| コンポーネント | インポートパス | variant | Props マッピング |
|---|---|---|---|
| RunnerResultPanel | src/components/domain/RunnerResultPanel.tsx | background | runId←run_id, slot←slot_type（blue/green）, role←'background', startedAt←started_at, stdout/stderr/exitCode←比較対象Runner実行結果 |
| StatusBadge | src/components/ui/StatusBadge.tsx | claimed/running/succeeded/failed | value←status（CLAIMED→RUNNING→SUCCEEDED/FAILEDの遷移を色分け表示） |

適用パターン: 実行結果ターミナル表示パターン（background variant。起動直後・実行中・完了時のrun_id/slot/role/started_at/状態を含めて表示し、キャッシュを持たず呼び出しごとに最新値を取得する）

## ティア完了条件（BDD）

```gherkin
Feature: 速報クロスチェックを実行し差分を検知する - バックエンドワーカーティア

  Scenario: REQUESTED行をlease取得し差分なしでSUCCEEDEDへ確定する
    Given rapid_crosscheck_requests に run_id "run-20260817-030" status "REQUESTED" が存在する
    And runner_results に run_id "run-20260817-030" のblue/green実行結果が完全一致で存在する
    When worker presentation層がCronJobトリガーを受け付ける
    Then gateway層はstatusを "CLAIMED"→"RUNNING"→"SUCCEEDED" の順に更新し、rapid_crosscheck_results へ comparison_result "OK" diff_count 0 をINSERTする
```
