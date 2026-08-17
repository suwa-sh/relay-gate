# 並行稼働実行結果を確認する - tier-facade仕様

## 変更概要

移行運用責任者がblue/green並行稼働の実行結果（Runner実行結果）を参照するCLIコマンドを追加する。RDBの `runner_results` テーブルへの読み取り専用アクセスのみを行い、状態遷移は発生しない。

## CLI コマンド仕様

### relaygate concurrent-run result

- **呼び出し形式**: `relaygate concurrent-run result [--job-id <JOB_ID> | --run-id <run_id>]`
- **引数**:
  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --job-id | string | いずれか必須（run-idと排他ではない。両方指定時はAND条件） | ジョブスケジューラのJOB_ID。同一JOB_IDのblue/green両slotの実行結果を取得する |
  | --run-id | string | いずれか必須 | 単一のRunner実行結果を特定するrun_id |
- **環境変数**:
  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | RDB（ジョブキュー兼管理DB）接続文字列 |
- **標準入力**: なし
- **標準出力契約**: slot_typeごとにセクション分割した実行結果一覧テキスト（各行: `slot: {blue|green} role: {foreground|background|rapid-crosscheck} run_id: {run_id} status: {RUNNING|SUCCEEDED|FAILED|ABORTED} exit_code: {exit_code|-} started_at: {ISO8601}`）
- **標準エラー契約**: 該当データなし・パラメータ不足時のエラーメッセージ（1行1メッセージ、原因を明示）
- **終了コード**:
  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（1件以上の実行結果を出力） |
  | 1 | 業務エラー（該当するRunner実行結果が存在しない） |
  | 2 | バリデーションエラー（job_id・run_idいずれも未指定） |

## データモデル変更

### runner_results

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | VARCHAR | Runner実行結果の一意識別子（PK） | 参照のみ |
| slot_type | VARCHAR | blue/green | 参照のみ |
| role_type | VARCHAR | foreground/background/rapid-crosscheck（PK構成要素） | 参照のみ |
| started_at | DATETIME | 実行開始時刻 | 参照のみ |
| stdout_path | VARCHAR | stdout.logのファイルパス（nullable） | 参照のみ |
| stderr_path | VARCHAR | stderr.logのファイルパス（nullable） | 参照のみ |
| exit_code | INT | exitcode.txtの値（nullable、未出力=RUNNING） | 参照のみ |
| status | VARCHAR | RUNNING/SUCCEEDED/FAILED/ABORTED | 参照のみ |

## ビジネスルール

- exitcode.txt の有無と値から実行状態（RUNNING/SUCCEEDED/FAILED）を判定する。ABORTEDは対話確認を経た明示的遷移でのみ設定される値であり、本UCではその結果を参照するのみで判定ロジックには関与しない
- foreground役割の応答は標準出力・標準エラー・終了コードのみに限定する運用ルール（SP-002）と異なり、本UCは移行運用責任者向けの参照UCであるため started_at・slot_type・role_type を含む詳細情報を出力してよい
- CLI応答は10秒以内（CTP-009）

## CLI 出力/画面表示マッピング（design-event.yaml 参照）

### 並行稼働実行結果確認画面

- **route**: /cli/concurrent-run/result
- **表示要素とコンポーネントマッピング**:
  | 要素 | 種別 | デザインシステムコンポーネント | 説明 |
  |------|------|------------------------------|------|
  | slot別実行結果パネル | ターミナル出力 | RunnerResultPanel | run_id/slot/role/startedAt/stdout/stderr/exitCodeを表示 |
  | 実行状態バッジ | ステータス表示 | StatusBadge（running/succeeded/failed/aborted） | 実行状態を色分け表示（将来ダッシュボード化時） |
- **デザイントークン参照**:
  | 用途 | トークン | 値 |
  |------|---------|---|
  | RUNNING状態色 | status-badge-running | background: var(--color-blue-100), foreground: var(--color-blue-600) |
  | SUCCEEDED状態色 | status-badge-succeeded | background: var(--color-green-100), foreground: var(--color-green-600) |
  | FAILED状態色 | status-badge-failed | background: var(--color-red-100), foreground: var(--color-red-600) |
  | ターミナル背景 | terminal-panel.background | var(--color-slate-900) |
- **UIロジック**:
  - **状態管理**: CLI実行のたびに最新のRunner実行結果をRDBから都度取得する（キャッシュしない）
  - **バリデーション**: job_id/run_idのいずれも未指定の場合は終了コード2でエラー表示（将来ダッシュボードではフォーム必須バリデーション）
  - **ローディング**: CLI応答10秒以内（CTP-009）。将来ダッシュボードではRunnerResultPanelにローディングスケルトンを表示
  - **エラーハンドリング**: 該当データなしの場合は終了コード1で標準エラーに理由を明示。CLIはstderrにのみエラーメッセージを出力しstdoutは汚さない

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「実行結果ターミナル表示パターン（background variant）」「共通状態表示パターン」を適用する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| RunnerResultPanel | `@/components/domain/RunnerResultPanel` | variant="background", runId={run_id}, slot={slot_type}, role={role_type}, startedAt={started_at}, stdout={stdout_path}, stderr={stderr_path}, exitCode={exit_code}, status={status} |
| StatusBadge | `@/components/ui/StatusBadge` | status={status}（RUNNING=blue/SUCCEEDED=green/FAILED=red/ABORTED=gray の共通カラートークン） |

## ティア完了条件（BDD）

```gherkin
Feature: 並行稼働実行結果を確認する - tier-facade

  Scenario: job_id指定でblue/green両slotの実行結果を取得する
    Given RDBの runner_results に job_id "JOB-2026-0817-001" で run_id "run-20260817-blue-001"（slot_type=blue, status=SUCCEEDED, exit_code=0）が存在する
    And 同一 job_id で run_id "run-20260817-green-001"（slot_type=green, status=RUNNING, exit_code=null）が存在する
    When `relaygate concurrent-run result --job-id JOB-2026-0817-001` を実行する
    Then 終了コード 0 で終了する
    And 標準出力に "slot: blue" を含む行と "slot: green" を含む行がそれぞれ1行以上出力される

  Scenario: 必須引数が未指定でバリデーションエラーになる
    When `relaygate concurrent-run result` を引数なしで実行する
    Then 終了コード 2 で終了する
    And 標準エラーに "job_id または run_id のいずれかを指定してください" が出力される
```
