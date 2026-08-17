# 対話確認のうえ確報比較依頼をABORTEDへ遷移させる

## 概要

前UC「RUNNING中の確報比較依頼の中止を依頼する」で中止依頼を受理したRUNNING中の確報比較依頼（E-005, AG-004）について、運用者の対話確認（y/nの二択）を経て、ABORTED状態へ明示的に遷移させるUC。確報クロスチェックはリリース判断の正本となるため、対話確認は省略できず、非TTY実行時は`--yes`フラグの明示指定を必須とする。

## データフロー

```mermaid
graph LR
  Actor["運用者\nCLI引数(--run-id)+対話入力(y/n)"] --> W_Pres
  subgraph W["tier-worker"]
    W_Pres["presentation\nAbortFinalCrosscheckConfirm CLI"]
    W_UC["usecase\nConfirmAbortFinalCrosscheckCommand"]
    W_Domain["domain\n確報比較依頼\nRUNNING→ABORTED遷移制御"]
    W_GW["gateway\nFinalCrosscheckRequestRecord"]
    W_Pres --> W_UC --> W_Domain
    W_UC --> W_GW
  end
  subgraph DB["RDB"]
    DB_Table[("final_crosscheck_requests\nrun_id/target_date/status")]
    DB_Audit[("audit_logs\noperator/操作日時/run_id/action")]
  end
  W_GW -->|"SELECT run_id, status WHERE run_id = ?"| DB_Table
  W_GW -->|"UPDATE status='ABORTED' WHERE run_id = ? AND status='RUNNING'"| DB_Table
  W_GW -->|"INSERT operator, aborted_at, run_id, action='abort_confirm'"| DB_Audit
  DB_Table --> W_GW --> W_Domain --> W_UC --> W_Pres -->|"stdout: 遷移完了メッセージ / stderr: エラー / exit code"| Actor
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| CLI presentation | run_id、--yesフラグ、対話入力(y/n) | CLI引数解析 + TTY判定（非TTYで--yes未指定はバリデーションエラー） → ConfirmAbortFinalCrosscheckCommand 変換 |
| usecase | ConfirmAbortFinalCrosscheckCommand | 対象の再取得（statusがRUNNINGであることの再確認） |
| domain | 確報比較依頼（AG-004） | RUNNING→ABORTEDへの明示的遷移制御。RUNNING以外からの遷移は不変条件違反として拒否する |
| gateway | final_crosscheck_requests への UPDATE + audit_logs への INSERT | 楽観的な条件付きUPDATE（WHERE status='RUNNING'）による整合性保証 |
| stdout/stderr | 遷移完了メッセージ／エラーメッセージ | ABORTEDへの遷移完了、またはキャンセル・エラーの通知 |

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

  User->>Pres: relaygate abort final-crosscheck confirm --run-id fc-2026-0817-001
  Pres->>Pres: TTY判定
  alt TTY接続時
    Pres->>User: "run_id=fc-2026-0817-001 target_date=2026-08-17 status=RUNNING を中止しますか？この操作は取消不可です。 [y/n]"
    User-->>Pres: 対話入力
  else 非TTY接続時
    Pres->>Pres: --yesフラグ有無を検証
    alt --yes未指定
      Pres-->>User: stderr: "非対話実行では --yes の明示指定が必要です" / exit 2
    end
  end
  Pres->>UC: ConfirmAbortFinalCrosscheckCommand(run_id, confirmed)
  UC->>GW: 対象再取得
  GW->>DB: SELECT run_id, status FROM final_crosscheck_requests WHERE run_id = 'fc-2026-0817-001'
  DB-->>GW: {status: RUNNING}
  GW-->>UC: 確報比較依頼エンティティ
  UC->>Domain: ABORTED遷移可否判定(status, confirmed)
  alt confirmed=trueかつstatus=RUNNINGの場合
    Domain->>Domain: RUNNING→ABORTED遷移を許可
    UC->>GW: 状態更新
    GW->>DB: UPDATE final_crosscheck_requests SET status='ABORTED' WHERE run_id='fc-2026-0817-001' AND status='RUNNING'
    DB-->>GW: 更新件数=1
    GW->>DB: INSERT INTO audit_logs (operator, aborted_at, run_id, action) VALUES ('opuser01', now(), 'fc-2026-0817-001', 'abort_confirm')
    DB-->>GW: 登録完了
    UC-->>Pres: 遷移完了結果
    Pres-->>User: stdout: "確報比較依頼をABORTEDへ遷移させました run_id=fc-2026-0817-001" / exit 0
  else confirmed=falseの場合（対話確認でnを選択）
    Domain->>Domain: 遷移をキャンセル
    UC-->>Pres: キャンセル結果
    Pres-->>User: stdout: "中止をキャンセルしました run_id=fc-2026-0817-001" / exit 0
  else 更新件数=0（他プロセスにより状態が変化済み）の場合
    Domain->>Domain: 不変条件違反として拒否
    UC-->>Pres: 業務エラー（競合検知）
    Pres-->>User: stderr: "状態が変化したため中止できません run_id=fc-2026-0817-001（他プロセスによりstatusが変更された可能性があります）" / exit 1
  end
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| クロスチェック種別 | 確報クロスチェック | 対象は確報比較依頼（final_crosscheck_requests）に限定する | tier-worker | ConfirmAbortFinalCrosscheckCommand |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| 確報比較依頼状態 | UPDATE時にWHERE句でstatus='RUNNING'を条件とし、更新件数が0の場合は他プロセスによる状態変化とみなし業務エラーとする | tier-worker | ConfirmAbortFinalCrosscheckCommand | 対話確認のうえABORTEDへ遷移する / 状態変化による競合を検知して拒否する |
| 対話確認結果 | TTY接続時はy/nの入力を受け、yのみ遷移を実行する。非TTY接続時は--yesフラグの明示指定がなければバリデーションエラーとする | tier-worker | AbortFinalCrosscheckConfirm CLI | 非TTY実行時に--yes未指定でエラーとする |

## 計算ルール一覧

該当なし（本UCは状態遷移の条件判定のみで計算ルールを持たない）

## 状態遷移一覧

| 状態モデル | 遷移元 | 遷移先 | トリガー | 事前条件 | 事後処理 | 適用 tier |
|-----------|--------|--------|---------|---------|---------|----------|
| 確報比較依頼状態 | RUNNING | ABORTED | 対話確認のうえ確報比較依頼をABORTEDへ遷移させる | 運用者の対話確認（y）または--yesフラグ指定、かつUPDATE時点でstatus='RUNNING'であること | audit_logsへ操作者・操作日時・run_idを含む監査ログを記録する | tier-worker |

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | 実行制御業務 | このUCが属する業務 |
| BUC | 確報比較中止フロー | このUCを含むBUC |
| アクター | 運用者 | 操作するアクター |
| 情報 | 確報比較依頼 | ABORTEDへ更新する情報 |
| 状態 | 確報比較依頼状態 | RUNNING→ABORTEDの遷移を扱う状態モデル |
| 条件 | 該当なし | - |
| 外部システム | 該当なし | - |

## E2E 完了条件（BDD）

### 正常系

```gherkin
Feature: 対話確認のうえ確報比較依頼をABORTEDへ遷移させる

  Scenario: 対話確認(y)によりABORTEDへ遷移する
    Given 確報比較依頼「fc-2026-0817-001」がtarget_date=2026-08-17、status=RUNNINGである
    When 運用者「opuser01」が relaygate abort final-crosscheck confirm --run-id fc-2026-0817-001 を実行し対話確認で "y" を入力する
    Then 確報比較依頼「fc-2026-0817-001」のstatusがABORTEDへ更新される
    And 標準出力に "確報比較依頼をABORTEDへ遷移させました run_id=fc-2026-0817-001" が出力され、終了コード0で終了する
    And audit_logsテーブルに operator="opuser01", run_id="fc-2026-0817-001", action="abort_confirm" が記録される

  Scenario: 非TTYバッチ実行で--yesフラグを指定してABORTEDへ遷移する
    Given 確報比較依頼「fc-2026-0816-002」がstatus=RUNNINGである
    When 非TTY環境で relaygate abort final-crosscheck confirm --run-id fc-2026-0816-002 --yes を実行する
    Then 確報比較依頼「fc-2026-0816-002」のstatusがABORTEDへ更新され、終了コード0で終了する
```

### 異常系

```gherkin
  Scenario: 対話確認で拒否(n)した場合は遷移させない
    Given 確報比較依頼「fc-2026-0817-001」がstatus=RUNNINGである
    When 運用者「opuser01」が relaygate abort final-crosscheck confirm --run-id fc-2026-0817-001 を実行し対話確認で "n" を入力する
    Then 確報比較依頼「fc-2026-0817-001」のstatusはRUNNINGのまま変化せず、標準出力に "中止をキャンセルしました run_id=fc-2026-0817-001" が出力され、終了コード0で終了する

  Scenario: 非TTYバッチ実行で--yes未指定の場合はエラーとする
    Given 非TTY環境で relaygate abort final-crosscheck confirm --run-id fc-2026-0816-003 が--yesフラグなしで呼び出される
    When コマンドが実行される
    Then 標準エラーに "非対話実行では --yes の明示指定が必要です" が出力され、終了コード2で終了する

  Scenario: 対話確認前に他プロセスにより状態が変化した場合は競合として拒否する
    Given 確報比較依頼「fc-2026-0816-004」がstatus=RUNNINGとして表示された後、hang-detectorによりstatus=FAILEDへ更新済みである
    When 運用者「opuser01」が relaygate abort final-crosscheck confirm --run-id fc-2026-0816-004 を実行し対話確認で "y" を入力する
    Then 標準エラーに "状態が変化したため中止できません run_id=fc-2026-0816-004" が出力され、終了コード1で終了する
```

## ティア別仕様

- [tier-worker仕様](tier-worker.md)

### 統合 API Spec

- [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml)（全 UC 統合。HTTP API は存在しないため OpenAPI ではなく CLI コマンド契約を正本とする）
