# green background実行の中止を依頼する - tier-facade仕様

## 変更概要

RUNNING中のgreen background実行を対象に、運用者が中止依頼を発行するCLIコマンドを追加する。中止依頼はgreen実装への通知と監査イベント（abort_requested）の記録を行い、状態遷移（ABORTEDへの明示的遷移）は後続の対話確認UCで実施する。

## CLI コマンド仕様

### relaygate abort green request

- **呼び出し形式**: `relaygate abort green request --run-id <run_id>`
- **引数**:
  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --run-id | string | Yes | 中止依頼対象のgreen background実行run_id |
- **環境変数**:
  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | RDB（ジョブキュー兼管理DB）接続文字列 |
  | RELAYGATE_SSH_KEY_PATH | Yes | green実装ホストへのSSH接続鍵パス |
- **標準入力**: なし
- **標準出力契約**: `中止依頼受理: run_id={run_id}` の1行
- **標準エラー契約**: 対象なし・既に完了済みの場合のエラーメッセージ（原因を1文で明示）
- **終了コード**:
  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（中止依頼受理、green実装への通知完了） |
  | 1 | 業務エラー（対象run_id不在、既にRUNNING以外の状態） |
  | 2 | バリデーションエラー（run_id未指定） |

## データモデル変更

### runner_results（参照のみ、変更なし）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | uuid | 中止依頼対象run_id（PK構成要素） | 参照のみ |
| slot_type | string | 固定条件 'green'（PK構成要素） | 参照のみ |
| role_type | string | 固定条件 'background'（PK構成要素） | 参照のみ |
| attempt_id | string | 起動試行の一意識別子（PK構成要素） | 参照のみ |
| attempt_no | integer | 起動試行連番（1始まり） | 参照のみ |
| status | string | STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED。RUNNING以外の場合は中止依頼を拒否 | 参照のみ |

### audit_logs（追記専用）

audit-event-contract.yaml のフィールド定義（actor / operation / outcome へ統一）に従う。

| イベント | operation | outcome | slot | attempt_id | タイミング |
|---------|-----------|---------|------|-----------|-----------|
| abort_requested | abort | accepted \| rejected | 'green' | '-'（起動試行に紐づかない中止依頼イベント） | 中止依頼受理時（状態遷移は伴わない） |

冪等キーは(run_id, slot, attempt_id, event_name)。認証情報・起動引数の実値・stdout/stderr本文は含めない。

### audit_chain_heads

audit_logsへの追記時に対象run_id行を排他ロック（SELECT ... FOR UPDATE）してprevious_hashを確定し、audit_logsのINSERTと同一transactionでhead_event_id / head_hash / chain_length / updated_atを更新する（hash-chain lock契約）。

## ビジネスルール

- 停止確認済みのgreen background実行についてのみ中止を発意できる（対象起動試行のstatus=RUNNINGであることが前提。実行状態は6値: STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED）
- 本UCは中止の意思表示（依頼）のみを行い、状態遷移は発生させない。ABORTEDへの明示的遷移は後続UC「対話確認のうえgreen background実行をABORTEDへ遷移させる」の責務とする
- 中止依頼の受理はevent_name=abort_requested（operation=abort、outcome=accepted）、拒否はoutcome=rejectedとして監査イベントを記録する（audit-event-contract.yaml。イベント種別ごとの独自フィールド名は使わない）
- CLI応答は10秒以内（CTP-009）

## CLI 出力/画面表示マッピング（design-event.yaml 参照）

### green background中止依頼画面

- **route**: /cli/abort/green/request
- **表示要素とコンポーネントマッピング**:
  | 要素 | 種別 | デザインシステムコンポーネント | 説明 |
  |------|------|------------------------------|------|
  | 対象実行結果パネル | ターミナル出力 | RunnerResultPanel（background variant） | 中止依頼対象run_id・attempt_id・現在状態を依頼直前に再確認表示 |
  | 中止依頼ボタン | ボタン | Button（destructive） | 中止依頼を確定する操作 |
- **デザイントークン参照**:
  | 用途 | トークン | 値 |
  |------|---------|---|
  | 中止依頼ボタン | Button destructive variant | var(--semantic-destructive) = var(--color-red-600) |
  | RUNNING状態色 | status-badge-running | background: var(--color-blue-100), foreground: var(--color-blue-600) |
- **UIロジック**:
  - **状態管理**: 依頼発行のたびにRDBから最新のstatusを再取得し妥当性を判定する（キャッシュしない）
  - **バリデーション**: run_id必須をCLI引数解析時点で検証、status=RUNNING以外は業務エラー
  - **ローディング**: CLI応答10秒以内
  - **エラーハンドリング**: 対象なし・状態不整合は終了コード1で理由を明示。中止確認画面への遷移は本UC完了後のみ許可（ux-design.md: 直接遷移による対話確認スキップは許可しない）

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「二段階中止確認パターン（依頼→対話確認）」のうち①中止依頼画面を適用する。本UCは①のみを担当し、②対話確認画面（AbortConfirmDialog）は後続UC「対話確認のうえgreen background実行をABORTEDへ遷移させる」の責務であり、本UCを経由せず②へ直接遷移することは許可しない。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| RunnerResultPanel | `@/components/domain/RunnerResultPanel` | variant="background", runId={run_id}, slot="green", attemptId={attempt_id}, status={status}（中止依頼直前の再確認表示） |
| Button | `@/components/ui/Button` | variant="destructive", label="中止依頼", onClick=中止依頼確定操作 |
| Banner | `@/components/ui/Banner` | variant="info" \| "error"（受理/エラーの即時フィードバック。共通フロー定義に基づき追加） |

## ティア完了条件（BDD）

```gherkin
Feature: green background実行の中止を依頼する - tier-facade

  Scenario: abort_green_request_RUNNING中の対象の場合_中止依頼を受理し監査イベントを記録すること
    # Arrange
    Given execution_specsテーブルにrun_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement"の行が存在する
    And slot_execution_specsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green"), host="green-host-01", exec_user="batchuser", impl_version="green-0.9.0"の行が存在する
    And runner_resultsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001"), attempt_no=1, status="RUNNING"の行が存在する
    # Act
    When 環境変数RELAYGATE_OPERATOR="ops-tanaka"の下で `relaygate abort green request --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行する
    # Assert
    Then 終了コード 0 で終了する
    And 標準出力に "中止依頼受理: run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" が出力される
    And green実装中止依頼イベントが送出される
    And audit_logsテーブルにevent_name="abort_requested", operation="abort", outcome="accepted", actor="ops-tanaka", slot="green", attempt_id="-"の行が1件追加される

  Scenario: abort_green_request_対象が既にABORTED状態の場合_中止依頼が拒否されること
    # Arrange
    Given execution_specsテーブルにrun_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"の行とslot_execution_specsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green")の行が存在する
    And runner_resultsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001"), status="ABORTED"の行が存在する
    # Act & Assert
    When `relaygate abort green request --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行すると、標準エラーに "対象は既に完了しており中止依頼できません: run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57 status=ABORTED" が出力され終了コード1で終了する
```
