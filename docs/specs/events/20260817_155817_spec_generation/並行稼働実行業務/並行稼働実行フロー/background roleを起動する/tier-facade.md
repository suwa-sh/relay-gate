# background roleを起動する - tier-facade仕様

## 変更概要

execution-spec.jsonで確定済みのbackground対象slotについて、facadeがworkerへ起動トリガーを送出するCLIコマンドを追加する。実際のbackground実行開始・Runner実行結果の永続化はtier-workerが担う。

## CLI コマンド仕様

### relaygate concurrent-run start-background

- **呼び出し形式**: `relaygate concurrent-run start-background --run-id <run_id>`
- **引数**:
  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --run-id | string | Yes | UC「feature flag設定に基づきslotを選択して起動する」で確定したrun_id |
- **環境変数**:
  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | RDB（ジョブキュー兼管理DB）接続文字列 |
  | RELAYGATE_WORKER_TRIGGER_ENDPOINT | Yes | tier-workerへの起動トリガー送出先（RDBキュー投入 or ローカルプロセス起動） |
- **標準入力**: なし
- **標準出力契約**: `background起動: slot={blue|green} run_id={run_id} status=RUNNING` の1行
- **標準エラー契約**: background対象slotなし・接続失敗時のエラーメッセージ
- **終了コード**:
  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（background起動トリガー送出完了） |
  | 1 | 業務エラー（background対象slotなし、起動先接続失敗） |
  | 2 | バリデーションエラー（run_id未指定） |

## データモデル変更

### execution_specs（参照のみ、変更なし）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | VARCHAR | 起動対象run_id | 参照のみ |

## ビジネスルール

- execution-spec.jsonで確定済みのbackground対象slot（BLUE_MODE/GREEN_MODEのうちbackground指定されたもの）のみを起動対象とする
- foreground roleの実行に先立ちbackground roleを起動する（BUC.tsvのアクティビティ順序に準拠）
- CLI応答は10秒以内（CTP-009）。ただし実際のbackground実行完了はCLI応答対象外であり、起動トリガー送出完了をもって正常終了とする

## CLI 出力/画面表示マッピング（design-event.yaml 参照）

### background role起動画面

- **route**: /cli/concurrent-run/start-background
- **表示要素とコンポーネントマッピング**:
  | 要素 | 種別 | デザインシステムコンポーネント | 説明 |
  |------|------|------------------------------|------|
  | 実行設定カード | カード | ExecutionSpecCard | 起動対象run_id・execution-spec.json内容を表示 |
  | 起動結果パネル | ターミナル出力 | RunnerResultPanel（background variant） | 起動直後のrun_id・status=RUNNINGを表示 |
- **デザイントークン参照**:
  | 用途 | トークン | 値 |
  |------|---------|---|
  | RUNNING状態色 | status-badge-running | background: var(--color-blue-100), foreground: var(--color-blue-600) |
- **UIロジック**:
  - **状態管理**: 起動トリガー送出のたびにworkerからの起動完了応答を待機する（同期呼び出し）
  - **バリデーション**: run_id必須、execution-spec.json存在確認をCLI引数解析時点で実施
  - **ローディング**: worker側の起動処理完了までの応答待ち。CLI応答10秒以内
  - **エラーハンドリング**: background対象slotなしは終了コード1、run_id未指定は終了コード2で区別

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「実行結果ターミナル表示パターン（background variant）」を適用する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| ExecutionSpecCard | `@/components/domain/ExecutionSpecCard` | runId={run_id}（execution-spec.jsonの内容を表示） |
| RunnerResultPanel | `@/components/domain/RunnerResultPanel` | variant="background", runId={run_id}, slot={slot_type}, status="RUNNING" |

## ティア完了条件（BDD）

```gherkin
Feature: background roleを起動する - tier-facade

  Scenario: background起動トリガーをworkerへ送出する
    Given run_id "run-20260817-001" のexecution-spec.jsonでGREEN_MODE=backgroundが確定している
    When `relaygate concurrent-run start-background --run-id run-20260817-001` を実行する
    Then 終了コード 0 で終了する
    And 標準出力に "background起動: slot=green run_id=run-20260817-001 status=RUNNING" が出力される

  Scenario: run_id未指定でバリデーションエラーになる
    When `relaygate concurrent-run start-background` を引数なしで実行する
    Then 終了コード 2 で終了する
    And 標準エラーに "run_id を指定してください" が出力される
```
