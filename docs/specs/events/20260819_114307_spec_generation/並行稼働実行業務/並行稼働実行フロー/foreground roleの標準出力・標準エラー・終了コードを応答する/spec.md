# foreground roleの標準出力・標準エラー・終了コードを応答する

## 概要

facadeが、foreground役割に割り当てられたslot（blue/green）の実行結果（標準出力・標準エラー・終了コード）だけをジョブスケジューラへ中継する。比較結果・差分件数・レポートURIなどの詳細情報は一切含めず、Runner Result Contractに従って標準化された3項目のみを応答する。実行結果は起動試行identity（run_id, slot_type, role_type, attempt_id）で管理されたrunner_results snapshotから、対象run_idのforeground役割の最新試行（attempt_no最大）を参照する。

終了コードは **foregroundのexitcode.txtの値を0を含む全値そのままプロセス終了コードへ透過**する（丸め・再割り当てをしない）。relay-gate自身のエラーは業務ジョブの終了コードと衝突しないよう、業務ジョブが通常使用しない退避終了コードへ分離する（実行結果未確定・取得不能・中止済み = 125、relay-gateのバリデーションエラー = 124。bashが自動生成する126/127とは衝突させない）。relay-gateエラーで応答する場合の標準エラーには、取得可能な場合のforeground stderr.logの内容とrelay-gate自身のエラー内容（原因と次アクション）を併記する。

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
    DB_Table[("runner_results\nrun_id, slot_type, role_type=foreground, attempt_id, attempt_no, stdout_path, stderr_path, exit_code, status")]
  end
  CLI_GW -->|"SELECT stdout_path, stderr_path, exit_code, status FROM runner_results WHERE run_id = ? AND role_type = 'foreground'（最新attempt_no）"| DB_Table
  DB_Table --> CLI_GW --> CLI_Domain --> CLI_UC --> CLI_Pres -->|"標準出力=stdout.log内容、標準エラー=stderr.log内容、プロセス終了コード=exitcode.txt値を0含む全値そのまま透過（relay-gateエラー時のみ退避コード125/124）"| OUT_View
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| CLI presentation | RespondForegroundRequest(run_id) | foreground実行完了待機・引数解析 |
| CLI usecase | RespondForegroundResultCommand | foreground実行完了検知 → 結果限定抽出フロー制御 |
| CLI gateway | runner_resultsへのSELECT | foreground role実行結果（最新試行のsnapshot）の取得（stdout_path/stderr_path/exit_code/status） |
| Response | 標準出力・標準エラー・終了コードのみ | ジョブスケジューラが受け取る唯一の応答形式。exit_codeは0を含む全値をプロセス終了コードへそのまま透過する |
| Response（relay-gateエラー時） | 退避終了コード + 併記標準エラー | 実行結果未確定・取得不能・中止済み=125、バリデーションエラー=124。標準エラーはforeground stderr.log内容（取得可能な場合）とrelay-gateエラー内容（原因と次アクション）を併記する |

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

  Scheduler->>Pres: relaygate concurrent-run respond-foreground --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57
  Pres->>Pres: CLI引数バリデーション（run_id必須）
  Pres->>UC: RespondForegroundResultCommand(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57")
  UC->>GW: foreground実行結果取得
  GW->>DB: SELECT slot_type, attempt_id, attempt_no, stdout_path, stderr_path, exit_code, status FROM runner_results WHERE run_id = '3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57' AND role_type = 'foreground' ORDER BY attempt_no DESC LIMIT 1
  DB-->>GW: slot_type=blue, attempt_id=att-blue-0001, stdout_path, stderr_path, exit_code=0, status=SUCCEEDED
  GW->>FS: stdout.log / stderr.log の内容読み取り
  FS-->>GW: ログ本体
  GW-->>UC: RunnerExecutionResult(stdout, stderr, exit_code)
  UC->>Domain: 比較結果・差分件数等の非該当フィールドを除外し3項目のみ抽出
  Domain-->>UC: 限定済み応答（stdout, stderr, exit_code）
  UC-->>Pres: 応答データ
  Pres-->>Scheduler: 標準出力=stdout内容、標準エラー=stderr内容、プロセス終了コード=exit_code（0含む全値をそのまま透過）

  Note over Pres,Scheduler: relay-gateエラー時は業務終了コードと分離する
  Pres->>GW: 取得可能ならstderr.log内容を読み取る
  Pres-->>Scheduler: 標準エラー=stderr.log内容 + relay-gateエラー内容（原因と次アクション）、プロセス終了コード=125（未確定/取得不能/中止済み）または124（バリデーションエラー）
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| role区分 | foreground、background、rapid-crosscheck | role_type='foreground'のレコードのみを応答対象として抽出する | tier-facade | `relaygate concurrent-run respond-foreground` のクエリ条件 |
| 実行状態 | STARTING、RUNNING、SUCCEEDED、FAILED、UNKNOWN、ABORTED | SUCCEEDED/FAILEDのみexitcode.txt値を透過できる。STARTING/RUNNING/UNKNOWN/ABORTEDは未確定・取得不能・中止済みとして退避コード125で応答する | tier-facade | 応答可否判定 |
| 終了コード分類 | 業務ジョブ終了コード（exitcode.txt値、0含む全値）、退避コード125（未確定・取得不能・中止済み）、退避コード124（relay-gateバリデーションエラー） | 業務ジョブの終了コードとrelay-gate自身のエラーを値域で分離する。bash予約の126/127は使用しない | tier-facade | `relaygate concurrent-run respond-foreground` の終了コード決定 |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| 応答可否判定 | 最新試行のstatusがSUCCEEDED/FAILED（exitcode.txt回収済み）の場合のみexit_codeを透過する。STARTING/RUNNINGは未確定、UNKNOWNは結果取得不能、ABORTEDは中止済みとしていずれも退避コード125で応答する（UNKNOWNを推測でFAILED相当の業務終了コードに変換しない） | tier-facade | `relaygate concurrent-run respond-foreground` の応答判定 | foreground実行結果がまだ確定していない、foreground実行結果がUNKNOWN（結果取得不能）の場合は退避コード125で応答する |
| 終了コード透過 | statusがSUCCEEDED/FAILEDの場合、exitcode.txtの値（0を含む全値）をプロセス終了コードへそのまま設定する。一律の値へ丸めない | tier-facade | `relaygate concurrent-run respond-foreground` の終了コード決定 | foreground実行結果の非0終了コードをそのまま透過する |
| relay-gateエラー時のstderr併記 | 退避コード（125/124）で応答する場合、foreground stderr.logを取得できるときはその内容を出力し、続けてrelay-gate自身のエラー内容（原因と次アクション）を出力する。取得できないときはrelay-gateのエラー内容のみを出力する | tier-facade | `relaygate concurrent-run respond-foreground` の標準エラー構成 | foreground実行結果がUNKNOWN（結果取得不能）の場合は退避コード125で応答する、run_id未指定でバリデーションエラーになる |

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
| 条件 | relay-gateエラーの退避終了コード | 終了コードの透過範囲と退避コード（125/124）の分離を規定する条件 |
| 外部システム | ジョブスケジューラ | 連携する外部システム（応答先） |

## E2E 完了条件（BDD）

### 正常系

```gherkin
Feature: foreground roleの標準出力・標準エラー・終了コードを応答する

  Scenario: foreground実行結果を標準出力・標準エラー・終了コードのみで応答する
    Given execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement" の行が存在する
    And slot_execution_specs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", host="blue-host-01") の行が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="foreground", attempt_id="att-blue-0001", attempt_no=1, status="SUCCEEDED", exit_code=0) の行がstdout_path/stderr_path付きで存在する
    When ジョブスケジューラが `relaygate concurrent-run respond-foreground --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行する
    Then プロセス終了コードは 0 である
    And 標準出力にstdout.logの内容がそのまま出力される
    And 標準エラーにstderr.logの内容がそのまま出力される
    And 比較結果・差分件数・レポートURIなどの詳細情報は一切出力されない

  Scenario: foreground実行結果の非0終了コードをそのまま透過する
    Given execution_specs に run_id="7a1e4c60-2d93-4f18-8b52-c0e7a9d3b641", job_id="daily-settlement" の行が存在する
    And slot_execution_specs に (run_id="7a1e4c60-2d93-4f18-8b52-c0e7a9d3b641", slot_type="blue", host="blue-host-01") の行が存在する
    And runner_results に (run_id="7a1e4c60-2d93-4f18-8b52-c0e7a9d3b641", slot_type="blue", role_type="foreground", attempt_id="att-blue-0001", attempt_no=1, status="FAILED", exit_code=3) の行がstdout_path/stderr_path付きで存在する
    When ジョブスケジューラが `relaygate concurrent-run respond-foreground --run-id 7a1e4c60-2d93-4f18-8b52-c0e7a9d3b641` を実行する
    Then プロセス終了コードは 3 である
    And プロセス終了コードは 1 へ丸められない
    And 標準エラーにstderr.logの内容がそのまま出力される
    And 標準エラーにrelay-gateのエラー内容は付加されない
```

### 異常系

```gherkin
  Scenario: foreground実行結果がまだ確定していない
    Given execution_specs・slot_execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の blue slot 一式が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="foreground", attempt_id="att-blue-0001", attempt_no=1, status="RUNNING", exit_code=NULL) の行が存在する
    When ジョブスケジューラが `relaygate concurrent-run respond-foreground --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行する
    Then 終了コード 125 で終了する
    And 標準エラーに "foreground実行結果が未確定です: run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" が出力される
    And 標準エラーに次アクションとして "実行完了後に再実行してください" が出力される

  Scenario: foreground実行結果がUNKNOWN（結果取得不能）の場合は退避コード125で応答する
    Given execution_specs・slot_execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の blue slot 一式が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="foreground", attempt_id="att-blue-0001", attempt_no=1, status="UNKNOWN", exit_code=NULL) の行がstderr_path付きで存在する
    And stderr.log に "ssh: connect to host blue-host-01 port 22: Connection timed out" が記録されている
    When ジョブスケジューラが `relaygate concurrent-run respond-foreground --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行する
    Then 終了コード 125 で終了する
    And 終了コードは FAILED 相当の業務終了コードへ推測で変換されない
    And 標準エラーに stderr.log の内容 "ssh: connect to host blue-host-01 port 22: Connection timed out" が出力される
    And 同じ標準エラーに relay-gate のエラー内容 "foreground実行結果を取得できません（status=UNKNOWN）" と次アクション "実結果を回収するか `relaygate concurrent-run result --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` で状態を確認してください" が併記される

  Scenario: foreground実行結果がABORTED（中止済み）の場合は退避コード125で応答する
    Given execution_specs・slot_execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の blue slot 一式が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="foreground", attempt_id="att-blue-0001", attempt_no=1, status="ABORTED", exit_code=NULL) の行が存在する
    And stderr.log を取得できない
    When ジョブスケジューラが `relaygate concurrent-run respond-foreground --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行する
    Then 終了コード 125 で終了する
    And 標準エラーに relay-gate のエラー内容 "foreground実行は中止済みです（status=ABORTED）" と次アクション "リランするか正規ジョブで再実行してください" が出力される

  Scenario: run_id未指定でバリデーションエラーになる
    When ジョブスケジューラが `relaygate concurrent-run respond-foreground` を引数なしで実行する
    Then 終了コード 124 で終了する
    And 標準エラーに "run_id を指定してください" が出力される
    And 終了コードは 126 でも 127 でもない（bash予約コードと衝突しない）
```

## ティア別仕様

- [tier-facade](tier-facade.md)

### 統合 API Spec

- [CLI コマンド契約](../../_cross-cutting/api/cli-command-contract.yaml)（全 UC 統合、CLI/ファイル/DB契約の正本）
