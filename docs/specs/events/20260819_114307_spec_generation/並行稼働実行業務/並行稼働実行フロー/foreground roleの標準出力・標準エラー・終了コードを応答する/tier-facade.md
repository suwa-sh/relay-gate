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
- **標準エラー契約**: stderr.logの内容をそのまま標準エラーへ流す。relay-gateエラー（退避コード125/124）で応答する場合は、foreground stderr.logを取得できるときその内容を先に出力し、続けてrelay-gate自身のエラー内容（原因と次アクション）を併記する。取得できないときはrelay-gateのエラー内容のみを出力する
- **終了コード**:
  | コード | 意味 |
  |--------|------|
  | exitcode.txtの値（0を含む全値） | foreground実行結果のexit_codeをプロセス終了コードとしてそのまま透過する。丸め・再割り当てをしない（status=SUCCEEDED/FAILED時） |
  | 125 | relay-gate退避コード: 実行結果未確定（STARTING/RUNNING）・取得不能（UNKNOWN）・中止済み（ABORTED）。UNKNOWNを推測でFAILED相当の業務終了コードへ変換しない |
  | 124 | relay-gate退避コード: relay-gateのバリデーションエラー（run_id未指定等） |

  退避コードは業務ジョブが通常使用しない値を予約したものであり、bashが自動生成する126（実行不可）・127（コマンド未検出）とは衝突させない（SR-006）。

## データモデル変更

### runner_results（参照のみ、変更なし）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | UUID | 応答対象run_id（複合PKの一部） | 参照のみ |
| slot_type | VARCHAR | foreground役割が割り当てられたslot（blue/green、複合PKの一部） | 参照のみ |
| role_type | VARCHAR | 固定条件 'foreground'（複合PKの一部） | 参照のみ |
| attempt_id | VARCHAR | 起動試行の一意識別子（複合PKの一部）。最新試行はattempt_no最大の行 | 参照のみ |
| attempt_no | INT | 同一（run_id, slot_type, role_type）内の連番（1始まり） | 参照のみ |
| stdout_path | VARCHAR | stdout.logのファイルパス | 参照のみ |
| stderr_path | VARCHAR | stderr.logのファイルパス | 参照のみ |
| exit_code | INT | exitcode.txtの値（未完了・UNKNOWN時はNULL） | 参照のみ |
| status | VARCHAR | STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED | 参照のみ |

## ビジネスルール

- foreground roleの標準出力・標準エラー・終了コードだけをジョブスケジューラへ応答する（SP-002）。比較結果・差分件数・レポートURIなどを含めない
- 応答対象は対象run_idのrole_type='foreground'の最新試行（attempt_no最大）のsnapshotとする
- status=SUCCEEDED/FAILEDの場合、exitcode.txtの値を0を含む全値そのままプロセス終了コードへ透過する（SP-002）。一律の値へ丸めたり再割り当てしたりしない
- foreground実行結果（exitcode.txt）が未出力（status=STARTING/RUNNING）、結果取得不能（status=UNKNOWN）、中止済み（status=ABORTED）の場合は業務ジョブの終了コードを確定できないため、退避コード125で応答する（SR-006）。UNKNOWNを推測でFAILED相当の業務終了コードに変換しない
- relay-gateのバリデーションエラー（run_id未指定等）は退避コード124で応答する。126/127はbashの予約値であるため使用しない
- relay-gateエラーで応答する場合の標準エラーは、取得可能な場合のforeground stderr.log内容とrelay-gate自身のエラー内容（原因と次アクション）を併記する
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
    Given execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の行が、slot_execution_specs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue") の行が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="foreground", attempt_id="att-blue-0001", attempt_no=1, status="SUCCEEDED", exit_code=0) の行が存在する
    When `relaygate concurrent-run respond-foreground --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行する
    Then プロセス終了コードは 0 である
    And 標準出力・標準エラーにはstdout.log/stderr.logの内容のみが出力され、比較結果・差分件数は含まれない

  Scenario: 非0のexitcode.txt値を丸めずそのまま透過する
    Given execution_specs に run_id="7a1e4c60-2d93-4f18-8b52-c0e7a9d3b641" の行が、slot_execution_specs に (run_id="7a1e4c60-2d93-4f18-8b52-c0e7a9d3b641", slot_type="blue") の行が存在する
    And runner_results に (run_id="7a1e4c60-2d93-4f18-8b52-c0e7a9d3b641", slot_type="blue", role_type="foreground", attempt_id="att-blue-0001", attempt_no=1, status="FAILED", exit_code=3) の行が存在する
    When `relaygate concurrent-run respond-foreground --run-id 7a1e4c60-2d93-4f18-8b52-c0e7a9d3b641` を実行する
    Then プロセス終了コードは 3 である
    And プロセス終了コードは 1 や 125 へ変換されない

  Scenario: foreground実行結果が未確定で退避コード125を返す
    Given execution_specs・slot_execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の blue slot 一式が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="foreground", attempt_id="att-blue-0001", attempt_no=1, status="RUNNING", exit_code=NULL) の行が存在する
    When `relaygate concurrent-run respond-foreground --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行する
    Then 終了コード 125 で終了する
    And 標準エラーに "foreground実行結果が未確定です: run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" が出力される

  Scenario: relay-gateエラー時にstderr.log内容とrelay-gateエラー内容を併記する
    Given execution_specs・slot_execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の blue slot 一式が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="foreground", attempt_id="att-blue-0001", attempt_no=1, status="UNKNOWN", exit_code=NULL) の行がstderr_path付きで存在する
    And stderr.log に "ssh: connect to host blue-host-01 port 22: Connection timed out" が記録されている
    When `relaygate concurrent-run respond-foreground --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行する
    Then 終了コード 125 で終了する
    And 標準エラーに "ssh: connect to host blue-host-01 port 22: Connection timed out" が出力される
    And 同じ標準エラーに "foreground実行結果を取得できません（status=UNKNOWN）" と次アクションが併記される

  Scenario: run_id未指定で退避コード124を返す
    When `relaygate concurrent-run respond-foreground` を引数なしで実行する
    Then 終了コード 124 で終了する
    And 標準エラーに "run_id を指定してください" が出力される
```
