# green background実行の中止を依頼する - tier-facade仕様

## 変更概要

RUNNING中のgreen background実行を対象に、運用者が中止依頼を発行するCLIコマンドを追加する。中止依頼はgreen実装への通知のみを行い、状態遷移（ABORTEDへの明示的遷移）は後続の対話確認UCで実施する。

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
| run_id | VARCHAR | 中止依頼対象run_id | 参照のみ |
| slot_type | VARCHAR | 固定条件 'green' | 参照のみ |
| role_type | VARCHAR | 固定条件 'background' | 参照のみ |
| status | VARCHAR | RUNNING以外の場合は中止依頼を拒否 | 参照のみ |

## ビジネスルール

- 停止確認済みのgreen background実行についてのみ中止を発意できる（status=RUNNINGであることが前提）
- 本UCは中止の意思表示（依頼）のみを行い、状態遷移は発生させない。ABORTEDへの明示的遷移は後続UC「対話確認のうえgreen background実行をABORTEDへ遷移させる」の責務とする
- 監査ログの記録は本UCの責務ではない。CTP-005に基づき、対話確認を経てABORTEDへ遷移させる後続UC側でのみ操作者・操作日時・対象run_idを含む監査ログとして記録する
- CLI応答は10秒以内（CTP-009）

## CLI 出力/画面表示マッピング（design-event.yaml 参照）

### green background中止依頼画面

- **route**: /cli/abort/green/request
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

`_cross-cutting/ux-ui/common-components.md` の「二段階中止確認パターン（依頼→対話確認）」のうち①中止依頼画面を適用する。本UCは①のみを担当し、②対話確認画面（AbortConfirmDialog）は後続UC「対話確認のうえgreen background実行をABORTEDへ遷移させる」の責務であり、本UCを経由せず②へ直接遷移することは許可しない。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| RunnerResultPanel | `@/components/domain/RunnerResultPanel` | variant="background", runId={run_id}, slot="green", status={status}（中止依頼直前の再確認表示） |
| Button | `@/components/ui/Button` | variant="destructive", label="中止依頼", onClick=中止依頼確定操作 |
| Banner | `@/components/ui/Banner` | variant="info" \| "error"（受理/エラーの即時フィードバック。共通フロー定義に基づき追加） |

## ティア完了条件（BDD）

```gherkin
Feature: green background実行の中止を依頼する - tier-facade

  Scenario: RUNNING中の対象へ中止依頼を発行する
    Given run_id "run-20260817-green-005" がstatus "RUNNING" である
    When `relaygate abort green request --run-id run-20260817-green-005` を実行する
    Then 終了コード 0 で終了する
    And 標準出力に "中止依頼受理: run_id=run-20260817-green-005" が出力される
    And green実装中止依頼イベントが送出される

  Scenario: 対象が既にABORTED状態で中止依頼が拒否される
    Given run_id "run-20260817-green-007" がstatus "ABORTED" である
    When `relaygate abort green request --run-id run-20260817-green-007` を実行する
    Then 終了コード 1 で終了する
    And 標準エラーに "対象は既に完了しており中止依頼できません: run_id=run-20260817-green-007 status=ABORTED" が出力される
```
