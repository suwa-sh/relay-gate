# foreground roleの標準出力・標準エラー・終了コードを応答する

## 概要

facadeが、foreground役割に割り当てられたslot（blue/green）の実行結果（標準出力・標準エラー・終了コード）だけをジョブスケジューラへ中継する。比較結果・差分件数・レポートURIなどの詳細情報は一切含めず、Runner Result Contractに従って標準化された3項目のみを応答する。

## データフロー

```mermaid
graph LR
  subgraph CLI["CLIエントリポイント（tier-facade）"]
    CLI_Pres["presentation\nRespondForegroundRequest（run_id）"]
    CLI_UC["usecase\nRespondForegroundResultCommand"]
    CLI_Domain["domain\nRunnerExecutionResult\nstdout/stderr/exit_code限定抽出"]
    CLI_GW["gateway\nRunnerResultRecord"]
    CLI_Pres --> CLI_UC --> CLI_Domain
    CLI_UC --> CLI_GW
  end
  subgraph OUT["CLI出力/画面"]
    OUT_View["実行結果応答管理画面\nRunnerResultPanel（foreground variant）"]
  end
  subgraph DB["RDB"]
    DB_Table[("runner_results\nrun_id, role_type=foreground, stdout_path, stderr_path, exit_code")]
  end
  CLI_GW -->|"SELECT stdout_path, stderr_path, exit_code, status FROM runner_results WHERE run_id = ? AND role_type = 'foreground'"| DB_Table
  DB_Table --> CLI_GW --> CLI_Domain --> CLI_UC --> CLI_Pres -->|"標準出力=stdout.log内容、標準エラー=stderr.log内容、プロセス終了コード=exitcode.txt値"| OUT_View
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| CLI presentation | RespondForegroundRequest(run_id) | foreground実行完了待機・引数解析 |
| CLI usecase | RespondForegroundResultCommand | foreground実行完了検知 → 結果限定抽出フロー制御 |
| CLI gateway | runner_resultsへのSELECT | foreground role実行結果の取得（stdout_path/stderr_path/exit_code） |
| Response | 標準出力・標準エラー・終了コードのみ | ジョブスケジューラが受け取る唯一の応答形式 |

## 処理フロー

```mermaid
sequenceDiagram
  actor Scheduler as ジョブスケジューラ

  box rgb(240,255,240) tier-facade
    participant Pres as presentation
    participant UC as usecase
    participant Domain as domain
    participant GW as gateway
  end

  participant DB as RDB
  participant FS as ファイルシステム

  Scheduler->>Pres: relaygate concurrent-run respond-foreground --run-id run-20260817-blue-001
  Pres->>Pres: CLI引数バリデーション（run_id必須）
  Pres->>UC: RespondForegroundResultCommand(run_id="run-20260817-blue-001")
  UC->>GW: foreground実行結果取得
  GW->>DB: SELECT stdout_path, stderr_path, exit_code, status FROM runner_results WHERE run_id = 'run-20260817-blue-001' AND role_type = 'foreground'
  DB-->>GW: stdout_path, stderr_path, exit_code=0, status=SUCCEEDED
  GW->>FS: stdout.log / stderr.log の内容読み取り
  FS-->>GW: ログ本体
  GW-->>UC: RunnerExecutionResult(stdout, stderr, exit_code)
  UC->>Domain: 比較結果・差分件数等の非該当フィールドを除外し3項目のみ抽出
  Domain-->>UC: 限定済み応答（stdout, stderr, exit_code）
  UC-->>Pres: 応答データ
  Pres-->>Scheduler: 標準出力=stdout内容、標準エラー=stderr内容、プロセス終了コード=exit_code
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| role区分 | foreground、background、rapid-crosscheck | role_type='foreground'のレコードのみを応答対象として抽出する | tier-facade | `relaygate concurrent-run respond-foreground` のクエリ条件 |

## 分岐条件一覧

該当なし（本UCはforeground役割の実行結果を限定抽出して応答するのみであり、業務条件による分岐は発生しない）。

## 計算ルール一覧

該当なし。

## 状態遷移一覧

該当なし（本UCはforeground役割のRunner実行結果を参照・応答するのみであり、RDRA BUC.tsv上も状態モデルとの関連はない）。

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | 並行稼働実行業務 | このUCが属する業務 |
| BUC | 並行稼働実行フロー | このUCを含むBUC |
| アクター | 運用者 | 操作するアクター |
| 情報 | Runner実行結果（started-at.txt/stdout.log/stderr.log/exitcode.txt） | 参照する情報 |
| 状態 | なし | - |
| 条件 | なし | - |
| 外部システム | ジョブスケジューラ | 連携する外部システム（応答先） |

## E2E 完了条件（BDD）

### 正常系

```gherkin
Feature: foreground roleの標準出力・標準エラー・終了コードを応答する

  Scenario: foreground実行結果を標準出力・標準エラー・終了コードのみで応答する
    Given run_id "run-20260817-blue-001" のforeground役割Runner実行結果がstdout_path/stderr_path/exit_code=0で確定している
    When ジョブスケジューラが `relaygate concurrent-run respond-foreground --run-id run-20260817-blue-001` を実行する
    Then プロセス終了コードは 0 である
    And 標準出力にstdout.logの内容がそのまま出力される
    And 標準エラーにstderr.logの内容がそのまま出力される
    And 比較結果・差分件数・レポートURIなどの詳細情報は一切出力されない
```

### 異常系

```gherkin
  Scenario: foreground実行結果がまだ確定していない
    Given run_id "run-20260817-blue-002" のforeground役割Runner実行結果がstatus "RUNNING"（exitcode.txt未出力）である
    When ジョブスケジューラが `relaygate concurrent-run respond-foreground --run-id run-20260817-blue-002` を実行する
    Then 終了コード 1 で終了する
    And 標準エラーに "foreground実行結果が未確定です: run_id=run-20260817-blue-002" が出力される

  Scenario: run_id未指定でバリデーションエラーになる
    When ジョブスケジューラが `relaygate concurrent-run respond-foreground` を引数なしで実行する
    Then 終了コード 2 で終了する
    And 標準エラーに "run_id を指定してください" が出力される
```

## ティア別仕様

- [tier-facade](tier-facade.md)

### 統合 API Spec

- [CLI コマンド契約](../../_cross-cutting/api/cli-command-contract.yaml)（全 UC 統合、CLI/ファイル/DB契約の正本）
