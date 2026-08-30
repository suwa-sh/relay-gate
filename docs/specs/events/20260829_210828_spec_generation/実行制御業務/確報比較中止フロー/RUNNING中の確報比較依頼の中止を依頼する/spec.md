# RUNNING中の確報比較依頼の中止を依頼する

## 概要

RUNNING中の確報比較依頼（E-005, AG-004）について、運用者が中止を発意するUC。確報クロスチェックは全テーブル・全ファイルを対象とする日次バッチであり、リリース判断の正本となるため、中止は慎重な二段階（依頼→対話確認）で行う。本UC自体は状態遷移を発生させず、対象がRUNNING状態であることを検証し中止依頼を受理する。中止依頼の受理・拒否は監査イベント（event_name=abort_requested、operation=abort、outcome=accepted/rejected）としてaudit_logsへ記録する（audit-event-contract.yaml）。実際のABORTEDへの遷移は後続UC「対話確認のうえ確報比較依頼をABORTEDへ遷移させる」が担う。

## データフロー

```mermaid
graph LR
  Actor["運用者\nCLI引数(--run-id)"] --> W_Pres
  subgraph W["tier-worker"]
    W_Pres["presentation\nAbortFinalCrosscheckRequest CLI"]
    W_UC["usecase\nRequestAbortFinalCrosscheckCommand"]
    W_Domain["domain\n確報比較依頼\nstatus=RUNNING検証"]
    W_GW["gateway\nFinalCrosscheckRequestRecord + AuditLogRecord"]
    W_Pres --> W_UC --> W_Domain
    W_UC --> W_GW
  end
  subgraph DB["RDB"]
    DB_Table[("final_crosscheck_requests\nrun_id/target_date/status/lease_expires_at/worker_id")]
    DB_Audit[("audit_logs\nevent_name=abort_requested\nactor/operation/outcome")]
    DB_Chain[("audit_chain_heads\nrun_id/head_hash")]
  end
  W_GW -->|"SELECT run_id, target_date, status WHERE run_id = ?"| DB_Table
  W_GW -->|"SELECT ... FOR UPDATE → INSERT（hash-chain lock契約）"| DB_Chain
  W_GW -->|"INSERT event_name='abort_requested', operation='abort', outcome='accepted'"| DB_Audit
  DB_Table --> W_GW --> W_Domain --> W_UC --> W_Pres -->|"stdout: 受理メッセージ / stderr: エラー詳細 / exit code"| Actor
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| CLI presentation | run_id（コマンド引数） | CLI引数解析 + バリデーション（run_id必須） → RequestAbortFinalCrosscheckCommand 変換 |
| usecase | RequestAbortFinalCrosscheckCommand | 確報比較依頼のstatus参照 → RUNNING以外なら業務エラー |
| domain | 確報比較依頼（AG-004） | RUNNING状態のみ中止依頼可能というルールの適用（状態遷移は起こさない） |
| gateway | final_crosscheck_requests への SELECT + audit_logsへのINSERT（abort_requested） | 対象確認と監査イベント記録 |
| stdout/stderr | 受理メッセージ／エラーメッセージ | 運用者への次アクション（対話確認コマンド）の提示 |

## 処理フロー

```mermaid
sequenceDiagram
  actor User as 運用者

  box rgb(240,255,240) tier-worker
    participant Pres as presentation
    participant UC as usecase
    participant Domain as domain
    participant GW as gateway
  end

  participant DB as RDB

  User->>Pres: relaygate abort final-crosscheck request --run-id e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f
  Pres->>Pres: CLI引数バリデーション（run_id必須）
  Pres->>UC: RequestAbortFinalCrosscheckCommand(run_id)
  UC->>GW: 対象取得
  GW->>DB: SELECT run_id, target_date, status FROM final_crosscheck_requests WHERE run_id = 'e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f'
  DB-->>GW: {target_date: 2026-08-18, status: RUNNING}
  GW-->>UC: 確報比較依頼エンティティ
  UC->>Domain: 中止依頼可否判定(status)
  alt statusがRUNNINGの場合
    Domain->>Domain: 中止依頼を受理可能と判定
    UC->>GW: 監査イベント記録
    GW->>DB: SELECT ... FOR UPDATE（audit_chain_headsのrun_id行。previous_hashを確定）
    GW->>DB: INSERT INTO audit_logs (event_name='abort_requested', run_id='e57a03c8-...', slot='-', attempt_id='-', actor='ops-tanaka', operation='abort', outcome='accepted', ...)
    GW->>DB: audit_chain_heads更新（同一transaction）
    UC-->>Pres: 受理結果（run_id, target_date, 次アクション: confirmコマンド案内）
    Pres-->>User: stdout: "中止依頼を受理しました run_id=e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f target_date=2026-08-18 status=RUNNING 次は 'relaygate abort final-crosscheck confirm --run-id e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f' を実行してください" / exit 0
  else statusがRUNNING以外の場合
    Domain->>Domain: 中止依頼不可と判定（監査イベントはoutcome='rejected'で記録）
    UC-->>Pres: 業務エラー（対象状態不一致）
    Pres-->>User: stderr: "中止依頼できません run_id=e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f status=SUCCEEDED（RUNNING状態のみ中止依頼可能です）" / exit 1
  end
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| クロスチェック種別 | 確報クロスチェック | 対象は確報比較依頼（final_crosscheck_requests）に限定する。速報比較依頼は対象外 | tier-worker | RequestAbortFinalCrosscheckCommand |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| 確報比較依頼状態 | 対象の確報比較依頼.statusがRUNNINGの場合のみ中止依頼を受理する。REQUESTED/CLAIMED/SUCCEEDED/FAILED/ABORTEDの場合は業務エラー（exit 1）とする | tier-worker | RequestAbortFinalCrosscheckCommand | 中止依頼を受理する / RUNNING以外の状態では中止依頼を拒否する |

## 計算ルール一覧

該当なし（本UCは状態参照とバリデーションのみで計算ルールを持たない）

## 状態遷移一覧

| 状態モデル | 遷移元 | 遷移先 | トリガー | 事前条件 | 事後処理 | 適用 tier |
|-----------|--------|--------|---------|---------|---------|----------|
| 確報比較依頼状態 | - | - | 本UCでは状態遷移を発生させない（RUNNING状態の確認のみ） | statusがRUNNING | 監査イベント（abort_requested、operation=abort、outcome=accepted/rejected）をaudit_logsへ記録する | tier-worker |

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | 実行制御業務 | このUCが属する業務 |
| BUC | 確報比較中止フロー | このUCを含むBUC |
| アクター | 運用者 | 操作するアクター |
| 情報 | 確報比較依頼 | 参照する情報（run_id、対象日、状態、lease期限、worker識別子、対象テーブル・対象ファイル） |
| 状態 | 確報比較依頼状態 | RUNNING状態であることを確認する対象 |
| 条件 | 該当なし | - |
| 外部システム | 該当なし | - |

## E2E 完了条件（BDD）

### 正常系

```gherkin
Feature: RUNNING中の確報比較依頼の中止を依頼する

  Scenario: RUNNING中の確報比較依頼の中止を依頼する
    Given execution_specsテーブルにrun_id="e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f"、job_id="daily-settlement"、hang_detect_limit_minutes=30の行が存在する
    And final_crosscheck_requestsテーブルにrun_id="e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f"、target_date="2026-08-18"、status="RUNNING"、worker_id="worker-05"の行が存在する
    When 運用者「ops-tanaka」が relaygate abort final-crosscheck request --run-id e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f を実行する
    Then 標準出力に "中止依頼を受理しました run_id=e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f target_date=2026-08-18 status=RUNNING" が出力され、終了コード0で終了する
    And audit_logsテーブルにevent_name="abort_requested"、operation="abort"、outcome="accepted"、actor="ops-tanaka"、run_id="e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f"、slot="-"、attempt_id="-"、schema_version="1.0"の行が1件追加される
```

### 異常系

```gherkin
  Scenario: RUNNING以外の状態では中止依頼を拒否する
    Given execution_specsテーブルにrun_id="e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f"の行が存在する
    And final_crosscheck_requestsテーブルにrun_id="e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f"、target_date="2026-08-18"、status="SUCCEEDED"の行が存在する
    When 運用者「ops-tanaka」が relaygate abort final-crosscheck request --run-id e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f を実行する
    Then 標準エラーに "中止依頼できません run_id=e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f status=SUCCEEDED（RUNNING状態のみ中止依頼可能です）" が出力され、終了コード1で終了する

  Scenario: 対象run_idが存在しない
    Given final_crosscheck_requestsテーブルに run_id="e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f" の行が存在しない
    When 運用者「ops-tanaka」が relaygate abort final-crosscheck request --run-id e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f を実行する
    Then 標準エラーに "対象の確報比較依頼が見つかりません run_id=e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f" が出力され、終了コード1で終了する

  Scenario: run_id未指定でコマンドを実行する
    When 運用者「ops-tanaka」が relaygate abort final-crosscheck request を実行する
    Then 標準エラーに "run_id は必須です" が出力され、終了コード2で終了する
```

## ティア別仕様

- [tier-worker仕様](tier-worker.md)

### 統合 API Spec

- [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml)（全 UC 統合。HTTP API は存在しないため OpenAPI ではなく CLI コマンド契約を正本とする）
- [監査イベント契約](../../../_cross-cutting/api/audit-event-contract.yaml)（abort_requestedのフィールド定義・hash-chain lock契約の正本）
