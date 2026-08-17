# green background実行の中止を依頼する

## 概要

運用者が、停止確認済みのgreen background実行について中止を発意し、中止依頼を発行する。本UCは中止の意思表示（依頼）のみを担い、実際のABORTEDへの状態遷移は後続UC「対話確認のうえgreen background実行をABORTEDへ遷移させる」で行う。

## データフロー

```mermaid
graph LR
  subgraph CLI["CLIエントリポイント（tier-facade）"]
    CLI_Pres["presentation\nRequestAbortGreenRequest（run_id）"]
    CLI_UC["usecase\nRequestAbortGreenCommand"]
    CLI_Domain["domain\nRunnerExecutionResult\n中止対象妥当性判定（status=RUNNING）"]
    CLI_GW["gateway\nRunnerResultRecord + GreenAbortRequestClient"]
    CLI_Pres --> CLI_UC --> CLI_Domain
    CLI_UC --> CLI_GW
  end
  subgraph OUT["CLI出力/画面"]
    OUT_View["green background中止依頼画面\nRunnerResultPanel + Button"]
  end
  subgraph DB["RDB"]
    DB_Table[("runner_results\nrun_id, slot_type=green, role_type=background, status")]
  end
  CLI_GW -->|"SELECT run_id, status FROM runner_results WHERE run_id = ? AND slot_type = 'green' AND role_type = 'background'"| DB_Table
  DB_Table --> CLI_GW --> CLI_Domain --> CLI_UC --> CLI_Pres -->|"標準出力: 中止依頼受理・対象run_id"| OUT_View
  CLI_GW -->|"イベント: green実装中止依頼イベント"| CLI_Domain
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| CLI presentation | RequestAbortGreenRequest(run_id) | 中止依頼対象run_idのCLI引数解析 |
| CLI usecase | RequestAbortGreenCommand | 停止確認済み・RUNNING状態の妥当性チェック → 中止依頼発行フロー制御 |
| CLI gateway | runner_resultsへのSELECT + green実装中止依頼イベント送出 | 対象実行結果の状態確認、green実装への中止依頼通知 |
| Response | 中止依頼受理結果・対象run_id | 後続の対話確認UCへの入力となる |

## 処理フロー

```mermaid
sequenceDiagram
  actor User as 運用者

  box rgb(240,255,240) tier-facade
    participant Pres as presentation
    participant UC as usecase
    participant Domain as domain
    participant GW as gateway
  end

  participant DB as RDB
  participant Green as green実装

  User->>Pres: relaygate abort green request --run-id run-20260817-green-005
  Pres->>Pres: CLI引数バリデーション（run_id必須）
  Pres->>UC: RequestAbortGreenCommand(run_id="run-20260817-green-005")
  UC->>GW: 対象実行結果の状態取得
  GW->>DB: SELECT run_id, status FROM runner_results WHERE run_id = 'run-20260817-green-005' AND slot_type = 'green' AND role_type = 'background'
  DB-->>GW: status = 'RUNNING'
  GW-->>UC: RunnerExecutionResult(status=RUNNING)
  UC->>Domain: 中止対象妥当性判定
  alt status が RUNNING でない（既にSUCCEEDED/FAILED/ABORTED）
    Domain->>Domain: 中止依頼不可と判定
  else status が RUNNING
    Domain->>Domain: 中止依頼受理可能と判定
  end
  UC->>GW: green実装中止依頼イベント送出
  GW->>Green: green実装中止依頼イベント（SSH経由）
  GW-->>UC: 依頼受理
  UC-->>Pres: 中止依頼受理結果
  Pres-->>User: 標準出力: "中止依頼受理: run_id=run-20260817-green-005"、終了コード0
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| slot種別 | blue、green | 本UCはslot_type='green'のみを対象とする（blue側は別UC） | tier-facade | 中止依頼対象のフィルタ条件 |

## 分岐条件一覧

該当なし（中止依頼可否の判定は状態モデルの前提条件によるものであり、RDRA条件.tsvに定義された業務条件には該当しない。次節「状態遷移一覧」の事前条件として記載する）。

## 計算ルール一覧

該当なし。

## 状態遷移一覧

| 状態モデル | 遷移元 | 遷移先 | トリガー | 事前条件 | 事後処理 | 適用 tier |
|-----------|--------|--------|---------|---------|---------|----------|
| background slot実行状態 | RUNNING | RUNNING（状態は変化しない。中止依頼のみ） | green background実行の中止を依頼する | 対象run_idのgreen background実行がRUNNING状態であること（停止確認済み） | green実装への中止依頼イベント送出のみ。状態変更は後続UCで実施 | tier-facade |

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | 実行制御業務 | このUCが属する業務 |
| BUC | green中止フロー | このUCを含むBUC |
| アクター | 運用者 | 操作するアクター |
| 情報 | Runner実行結果（started-at.txt/stdout.log/stderr.log/exitcode.txt） | 参照する情報 |
| 状態 | background slot実行状態 | 中止依頼対象の前提状態（RUNNING）を確認する |
| 条件 | なし | - |
| 外部システム | green実装 | 連携する外部システム（中止依頼イベント送出先） |

## E2E 完了条件（BDD）

### 正常系

```gherkin
Feature: green background実行の中止を依頼する

  Scenario: RUNNING中のgreen background実行に中止を依頼する
    Given run_id "run-20260817-green-005" のgreen background実行がstatus "RUNNING" である
    When 運用者が `relaygate abort green request --run-id run-20260817-green-005` を実行する
    Then 終了コード 0 で終了する
    And 標準出力に "中止依頼受理: run_id=run-20260817-green-005" が出力される
    And green実装へ中止依頼イベントが送出される
```

### 異常系

```gherkin
  Scenario: 既にFAILEDのgreen background実行に中止を依頼する
    Given run_id "run-20260817-green-006" のgreen background実行がstatus "FAILED" である
    When 運用者が `relaygate abort green request --run-id run-20260817-green-006` を実行する
    Then 終了コード 1 で終了する
    And 標準エラーに "対象は既に完了しており中止依頼できません: run_id=run-20260817-green-006 status=FAILED" が出力される

  Scenario: 対象run_idが存在しない
    Given run_id "run-20260817-green-999" のRunner実行結果が存在しない
    When 運用者が `relaygate abort green request --run-id run-20260817-green-999` を実行する
    Then 終了コード 1 で終了する
    And 標準エラーに "該当するgreen background実行が見つかりません: run_id=run-20260817-green-999" が出力される
```

## ティア別仕様

- [tier-facade](tier-facade.md)

### 統合 API Spec

- [CLI コマンド契約](../../_cross-cutting/api/cli-command-contract.yaml)（全 UC 統合、CLI/ファイル/DB契約の正本）
