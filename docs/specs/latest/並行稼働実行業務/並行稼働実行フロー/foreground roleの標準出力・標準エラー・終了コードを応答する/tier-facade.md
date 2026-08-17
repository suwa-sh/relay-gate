# foreground roleの標準出力・標準エラー・終了コードを応答する - tier-facade仕様

## 変更概要

foreground役割のRunner実行結果から標準出力・標準エラー・終了コードの3項目のみを抽出し、ジョブスケジューラへ中継するCLIコマンドを追加する。SP-002（foreground結果限定応答）を厳格に適用し、比較結果・差分件数・レポートURI等は一切含めない。

## CLI コマンド仕様

### relaygate concurrent-run respond-foreground

- **呼び出し形式**: `relaygate concurrent-run respond-foreground --run-id <run_id>`
- **引数**:
  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --run-id | string | Yes | foreground役割のRunner実行結果を特定するrun_id |
- **環境変数**:
  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | RDB（ジョブキュー兼管理DB）接続文字列 |
  | RELAYGATE_LOG_ROOT | Yes | stdout.log/stderr.logが格納されるログルートディレクトリ |
- **標準入力**: なし
- **標準出力契約**: stdout.logの内容をそのまま標準出力へ流す（整形は行末改行以外加えない。ジョブスケジューラ側でのパース可能性を損なわないため）
- **標準エラー契約**: stderr.logの内容をそのまま標準エラーへ流す。foreground実行結果未確定時はエラーメッセージ「foreground実行結果が未確定です: run_id={run_id}」を出力
- **終了コード**:
  | コード | 意味 |
  |--------|------|
  | 0-255（exitcode.txtの値をそのまま反映） | foreground実行結果のexit_codeをプロセス終了コードとして返す（0=正常、1=業務エラー等はforeground実行対象の意味に従う） |
  | 1 | 本コマンド自体の業務エラー（foreground実行結果未確定） |
  | 2 | バリデーションエラー（run_id未指定） |

## データモデル変更

### runner_results（参照のみ、変更なし）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | VARCHAR | 応答対象run_id | 参照のみ |
| role_type | VARCHAR | 固定条件 'foreground' | 参照のみ |
| stdout_path | VARCHAR | stdout.logのファイルパス | 参照のみ |
| stderr_path | VARCHAR | stderr.logのファイルパス | 参照のみ |
| exit_code | INT | exitcode.txtの値 | 参照のみ |

## ビジネスルール

- foreground roleの標準出力・標準エラー・終了コードだけをジョブスケジューラへ応答する（SP-002）。比較結果・差分件数・レポートURIなどを含めない
- foreground実行結果（exitcode.txt）が未出力（status=RUNNING）の場合は応答できないため業務エラーとする
- 標準出力・標準エラーの整形は行末の改行以外加えない（ジョブスケジューラ側でのパース可能性を損なわないため）
- CLI応答は10秒以内（CTP-009）

## CLI 出力/画面表示マッピング（design-event.yaml 参照）

### 実行結果応答管理画面

- **route**: /cli/concurrent-run/respond-foreground
- **表示要素とコンポーネントマッピング**:
  | 要素 | 種別 | デザインシステムコンポーネント | 説明 |
  |------|------|------------------------------|------|
  | 応答結果パネル | ターミナル出力 | RunnerResultPanel（foreground variant） | stdout/stderr/exitCodeのみをレンダリングし、詳細を表示しない |
- **デザイントークン参照**:
  | 用途 | トークン | 値 |
  |------|---------|---|
  | ターミナル背景 | terminal-panel.background | var(--color-slate-900) |
  | ターミナル文字色 | terminal-panel.foreground | var(--color-slate-100) |
  | ターミナルフォント | terminal-panel.font | var(--font-family-ff-mono) |
- **UIロジック**:
  - **状態管理**: 呼び出しごとにRDB・ファイルシステムから最新の実行結果を取得する（キャッシュしない）
  - **バリデーション**: run_id必須をCLI引数解析時点で検証
  - **ローディング**: CLI応答10秒以内。foreground実行未完了の場合は即時エラー終了（待機しない）
  - **エラーハンドリング**: 比較結果・差分件数・レポートURIなどの詳細を表示しない制約をRunnerResultPanel（foreground variant）のprops設計で強制する

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「実行結果ターミナル表示パターン（foreground variant）」を適用する。foreground variant は SP-002 を props 設計で強制し、stdout/stderr/exitCode 以外の詳細を一切レンダリングしない。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| RunnerResultPanel | `@/components/domain/RunnerResultPanel` | variant="foreground", runId={run_id}（内部取得キーのみ、非表示）, stdout={stdout_path内容}, stderr={stderr_path内容}, exitCode={exit_code} |

## ティア完了条件（BDD）

```gherkin
Feature: foreground roleの標準出力・標準エラー・終了コードを応答する - tier-facade

  Scenario: 確定済みforeground実行結果を3項目のみで応答する
    Given run_id "run-20260817-blue-001" のforeground役割Runner実行結果がexit_code=0, status=SUCCEEDEDで確定している
    When `relaygate concurrent-run respond-foreground --run-id run-20260817-blue-001` を実行する
    Then プロセス終了コードは 0 である
    And 標準出力・標準エラーにはstdout.log/stderr.logの内容のみが出力され、比較結果・差分件数は含まれない

  Scenario: foreground実行結果が未確定で業務エラーになる
    Given run_id "run-20260817-blue-002" のforeground役割Runner実行結果がstatus "RUNNING" である
    When `relaygate concurrent-run respond-foreground --run-id run-20260817-blue-002` を実行する
    Then 終了コード 1 で終了する
    And 標準エラーに "foreground実行結果が未確定です: run_id=run-20260817-blue-002" が出力される
```
