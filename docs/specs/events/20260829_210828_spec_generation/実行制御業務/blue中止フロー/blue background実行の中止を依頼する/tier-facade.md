# blue background実行の中止を依頼する - tier-facade仕様

## 変更概要

RUNNING中のblue background実行を対象に、運用者が中止依頼を発行するCLIコマンドを追加する。中止依頼はblue実装への通知のみを行い、状態遷移（ABORTEDへの明示的遷移）は後続の対話確認UCで実施する。

## CLI コマンド仕様

### relaygate abort blue request

- **呼び出し形式**: `relaygate abort blue request --run-id <run_id>`
- **引数**:
  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --run-id | string | Yes | 中止依頼対象のblue background実行run_id |
- **環境変数**:
  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | RDB（ジョブキュー兼管理DB）接続文字列 |
  | RELAYGATE_CREDENTIAL_DIR | Yes | 認証情報ディレクトリ。対象runのblue slot_execution_specs.credential_ref からSSH秘密鍵を解決する（`cli-command-contract.yaml` credential_resolution） |
  | RELAYGATE_SSH_KEY_PATH | No | credential_ref が null のときに用いる既定のSSH秘密鍵パス |
- **標準入力**: なし
- **標準出力契約**: `中止依頼受理: run_id={run_id}` の1行
- **標準エラー契約**: 対象なし・既に完了済みの場合のエラーメッセージ（原因を1文で明示）
- **終了コード**:
  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（中止依頼受理、blue実装への通知完了） |
  | 1 | 業務エラー（対象run_id不在、既にRUNNING以外の状態） |
  | 2 | バリデーションエラー（run_id未指定） |

## データモデル変更

### runner_results（参照のみ、変更なし）

起動試行は (run_id, slot_type, role_type, attempt_id) で一意に識別する（複合主キー）。

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | UUID | 中止依頼対象run_id | 参照のみ |
| slot_type | VARCHAR | 固定条件 'blue' | 参照のみ |
| role_type | VARCHAR | 固定条件 'background' | 参照のみ |
| attempt_id / attempt_no | VARCHAR / INTEGER | 対象起動試行の識別子・連番（監査イベントのattempt_idに記録） | 参照のみ |
| status | VARCHAR | STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED。RUNNING以外の場合は中止依頼を拒否 | 参照のみ |

### audit_logs / audit_chain_heads（監査イベント）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| event_name / operation / outcome | VARCHAR | abort_requested / abort / accepted・rejected を追記する。冪等キーは (run_id, slot, attempt_id, event_name) | 追加（本UCでINSERT） |

## ビジネスルール

- 停止確認済みのblue background実行についてのみ中止を発意できる（status=RUNNINGであることが前提）
- 本UCは中止の意思表示（依頼）のみを行い、状態遷移は発生させない。ABORTEDへの明示的遷移は後続UC「対話確認のうえblue background実行をABORTEDへ遷移させる」の責務とする
- 中止依頼の受理・拒否は監査イベント event_name=abort_requested（operation=abort、outcome=accepted|rejected）として audit_logs へ追記する（audit-event-contract.yaml）。追記時は audit_chain_heads の対象run_id行を排他ロック（SELECT ... FOR UPDATE）してprevious_hashを確定し、audit_logs のINSERTと audit_chain_heads の更新を同一transactionで行う。actor には環境変数 RELAYGATE_OPERATOR の値を記録し、slot='blue'、attempt_id には対象起動試行のattempt_idを記録する
- 監査イベントには認証情報・起動引数の実値・stdout/stderr本文を含めない
- CLI応答は10秒以内（CTP-009）

## CLI 出力/画面表示マッピング（design-event.yaml 参照）

### blue background中止依頼画面

- **route**: /cli/abort/blue/request
- **表示要素とコンポーネントマッピング**:
  | 要素 | 種別 | デザインシステムコンポーネント | 説明 |
  |------|------|------------------------------|------|
  | 対象実行結果パネル | ターミナル出力 | RunnerResultPanel（background variant） | 中止依頼対象run_id・現在状態を依頼直前に再確認表示 |
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

`_cross-cutting/ux-ui/common-components.md` の「二段階中止確認パターン（依頼→対話確認）」のうち①中止依頼画面を適用する。本UCは①のみを担当し、②対話確認画面（AbortConfirmDialog）は後続UC「対話確認のうえblue background実行をABORTEDへ遷移させる」の責務であり、本UCを経由せず②へ直接遷移することは許可しない。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| RunnerResultPanel | `@/components/domain/RunnerResultPanel` | variant="background", runId={run_id}, slot="blue", status={status}（中止依頼直前の再確認表示） |
| Button | `@/components/ui/Button` | variant="destructive", label="中止依頼", onClick=中止依頼確定操作 |
| Banner | `@/components/ui/Banner` | variant="info" \| "error"（受理/エラーの即時フィードバック。共通フロー定義に基づき追加） |

## ティア完了条件（BDD）

```gherkin
Feature: blue background実行の中止を依頼する - tier-facade

  Scenario: RUNNING中の対象へ中止依頼を発行する
    Given execution_specs に run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の行と slot_execution_specs の (run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type "blue") の行が存在する
    And runner_results に (run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type "blue", role_type "background", attempt_id "att-blue-0001")、status "RUNNING" の起動試行が存在する
    When `relaygate abort blue request --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行する
    Then 終了コード 0 で終了する
    And 標準出力に "中止依頼受理: run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" が出力される
    And blue実装中止依頼イベントが送出される
    And audit_logs に event_name "abort_requested"、operation "abort"、outcome "accepted" の監査イベントが追記される

  Scenario: 対象が既にABORTED状態で中止依頼が拒否される
    Given execution_specs に run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の行と slot_execution_specs の (run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type "blue") の行が存在する
    And runner_results に (run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type "blue", role_type "background", attempt_id "att-blue-0001")、status "ABORTED" の起動試行が存在する
    When `relaygate abort blue request --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行する
    Then 終了コード 1 で終了する
    And 標準エラーに "対象は既に完了しており中止依頼できません: run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57 status=ABORTED" が出力される
    And audit_logs に event_name "abort_requested"、operation "abort"、outcome "rejected" の監査イベントが追記される
```
