# green background実行の中止を依頼する

## 概要

運用者が、停止確認済みのgreen background実行について中止を発意し、中止依頼を発行する。本UCは中止の意思表示（依頼）のみを担い、実際のABORTEDへの状態遷移は後続UC「対話確認のうえgreen background実行をABORTEDへ遷移させる」で行う。中止依頼の受理・拒否は監査イベント（event_name=abort_requested、operation=abort、outcome=accepted|rejected）としてaudit_logsへ記録する（audit-event-contract.yaml）。

## データフロー

```mermaid
graph LR
  subgraph CLI["CLIエントリポイント（tier-facade）"]
    CLI_Pres["presentation\nRequestAbortGreenRequest（run_id）"]
    CLI_UC["usecase\nRequestAbortGreenCommand"]
    CLI_Domain["domain\nRunnerExecutionResult\n中止対象妥当性判定（status=RUNNING）"]
    CLI_GW["gateway\nRunnerResultRecord + GreenAbortRequestClient + AuditLogRecord"]
    CLI_Pres --> CLI_UC --> CLI_Domain
    CLI_UC --> CLI_GW
  end
  subgraph OUT["CLI出力/画面"]
    OUT_View["green background中止依頼画面\nRunnerResultPanel + Button"]
  end
  subgraph DB["RDB"]
    DB_Table[("runner_results\nrun_id, slot_type=green, role_type=background\nattempt_id, attempt_no, status")]
    DB_Audit[("audit_logs\nevent_name=abort_requested\nactor/operation/outcome")]
    DB_Chain[("audit_chain_heads\nrun_id/head_hash")]
  end
  CLI_GW -->|"SELECT ... FROM runner_results WHERE run_id = ? AND slot_type = 'green' AND role_type = 'background'"| DB_Table
  CLI_GW -->|"SELECT ... FOR UPDATE → INSERT（hash-chain lock契約）"| DB_Chain
  CLI_GW -->|"INSERT event_name='abort_requested', operation='abort', outcome='accepted'"| DB_Audit
  DB_Table --> CLI_GW --> CLI_Domain --> CLI_UC --> CLI_Pres -->|"標準出力: 中止依頼受理・対象run_id"| OUT_View
  CLI_GW -->|"イベント: green実装中止依頼イベント"| CLI_Domain
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| CLI presentation | RequestAbortGreenRequest(run_id) | 中止依頼対象run_idのCLI引数解析 |
| CLI usecase | RequestAbortGreenCommand | 停止確認済み・RUNNING状態の妥当性チェック → 中止依頼発行フロー制御 |
| CLI gateway | runner_resultsへのSELECT + audit_logsへのINSERT（abort_requested）+ green実装中止依頼イベント送出 | 対象起動試行（(run_id, slot_type='green', role_type='background', attempt_id)）の状態確認、監査イベント記録、green実装への中止依頼通知 |
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

  User->>Pres: relaygate abort green request --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57
  Pres->>Pres: CLI引数バリデーション（run_id必須）
  Pres->>UC: RequestAbortGreenCommand(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57")
  UC->>GW: 対象起動試行の状態取得
  GW->>DB: SELECT run_id, attempt_id, attempt_no, status FROM runner_results WHERE run_id = '3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57' AND slot_type = 'green' AND role_type = 'background'
  DB-->>GW: {attempt_id: att-green-0001, attempt_no: 1, status: RUNNING}
  GW-->>UC: RunnerExecutionResult(status=RUNNING)
  UC->>Domain: 中止対象妥当性判定
  alt status が RUNNING でない（STARTING/SUCCEEDED/FAILED/UNKNOWN/ABORTED）
    Domain->>Domain: 中止依頼不可と判定（監査イベントはoutcome='rejected'で記録）
  else status が RUNNING
    Domain->>Domain: 中止依頼受理可能と判定
  end
  UC->>GW: green実装中止依頼イベント送出 + 監査イベント記録
  GW->>Green: green実装中止依頼イベント（SSH経由）
  GW->>DB: SELECT ... FOR UPDATE（audit_chain_headsのrun_id行。previous_hashを確定）
  GW->>DB: INSERT INTO audit_logs (event_name='abort_requested', run_id='3f8c9d2e-...', slot='green', attempt_id='-', actor='ops-tanaka', operation='abort', outcome='accepted', ...)
  GW->>DB: audit_chain_heads更新（同一transaction）
  GW-->>UC: 依頼受理
  UC-->>Pres: 中止依頼受理結果
  Pres-->>User: 標準出力: "中止依頼受理: run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"、終了コード0
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
| background slot実行状態 | RUNNING | RUNNING（状態は変化しない。中止依頼のみ） | green background実行の中止を依頼する | 対象run_idのgreen background起動試行がRUNNING状態であること（停止確認済み） | green実装への中止依頼イベント送出と、監査イベント（abort_requested、operation=abort、outcome=accepted/rejected）のaudit_logsへの記録。状態変更は後続UCで実施 | tier-facade |

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | 実行制御業務 | このUCが属する業務 |
| BUC | green中止フロー | このUCを含むBUC |
| アクター | 運用者 | 操作するアクター |
| 情報 | Runner実行結果（started-at.txt/stdout.log/stderr.log/exitcode.txt） | 参照する情報 |
| 状態 | background slot実行状態 | 中止依頼対象の前提状態（RUNNING）を確認する（状態は6値: STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED） |
| 条件 | なし | - |
| 外部システム | green実装 | 連携する外部システム（中止依頼イベント送出先） |

## E2E 完了条件（BDD）

### 正常系

```gherkin
Feature: green background実行の中止を依頼する

  Scenario: RUNNING中のgreen background実行に中止を依頼する
    Given execution_specsテーブルにrun_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"、job_id "daily-settlement"、job_map_version "v1.4.0"、hang_detect_limit_minutes 30の行が存在する
    And slot_execution_specsテーブルに(run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type "green")、host "green-host-01"、exec_user "batchuser"、impl_version "green-0.9.0"の行が存在する
    And runner_resultsテーブルに(run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type "green", role_type "background", attempt_id "att-green-0001")、attempt_no 1、status "RUNNING"の行が存在する
    When 運用者「ops-tanaka」が `relaygate abort green request --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行する
    Then 終了コード 0 で終了する
    And 標準出力に "中止依頼受理: run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" が出力される
    And green実装へ中止依頼イベントが送出される
    And audit_logsテーブルにevent_name="abort_requested"、operation="abort"、outcome="accepted"、actor="ops-tanaka"、run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"、slot="green"、attempt_id="-"、schema_version="1.0"の行が1件追加される
```

### 異常系

```gherkin
  Scenario: 既にFAILEDのgreen background実行に中止を依頼する
    Given execution_specsテーブルにrun_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の行とslot_execution_specsテーブルに(run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type "green")の行が存在する
    And runner_resultsテーブルに(run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type "green", role_type "background", attempt_id "att-green-0001")、status "FAILED"の行が存在する
    When 運用者「ops-tanaka」が `relaygate abort green request --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行する
    Then 終了コード 1 で終了する
    And 標準エラーに "対象は既に完了しており中止依頼できません: run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57 status=FAILED" が出力される
    And audit_logsテーブルにevent_name="abort_requested"、operation="abort"、outcome="rejected"の行が1件追加される

  Scenario: 対象run_idが存在しない
    Given runner_resultsテーブルにrun_id "7a2e4b91-8c63-4d5f-b012-9e3c7a1d6b84" の行が存在しない
    When 運用者「ops-tanaka」が `relaygate abort green request --run-id 7a2e4b91-8c63-4d5f-b012-9e3c7a1d6b84` を実行する
    Then 終了コード 1 で終了する
    And 標準エラーに "該当するgreen background実行が見つかりません: run_id=7a2e4b91-8c63-4d5f-b012-9e3c7a1d6b84" が出力される
```

## ティア別仕様

- [tier-facade](tier-facade.md)

### 統合 API Spec

- [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml)（全 UC 統合、CLI/ファイル/DB契約の正本）
- [監査イベント契約](../../../_cross-cutting/api/audit-event-contract.yaml)（abort_requestedのフィールド定義・hash-chain lock契約の正本）
