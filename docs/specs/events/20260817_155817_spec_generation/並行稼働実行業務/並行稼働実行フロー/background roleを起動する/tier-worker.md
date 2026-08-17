# background roleを起動する - tier-worker仕様

## 変更概要

facadeからのbackground起動トリガーを受けて、tier-workerがRDBのlease/claim機構を用いてbackground role実行を開始し、Runner実行結果レコード（status=RUNNING）を作成したうえでblue/green実装をSSH経由で非同期起動する。

## CLI コマンド仕様

### relaygate worker start-background-execution

- **呼び出し形式**: `relaygate worker start-background-execution --run-id <run_id> --slot-type <blue|green>`（facadeからのトリガー呼び出し専用。運用者が直接手動実行することは想定しない）
- **引数**:
  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --run-id | string | Yes | facadeから引き継いだrun_id |
  | --slot-type | string(blue\|green) | Yes | 起動対象slot種別 |
- **環境変数**:
  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | RDB（ジョブキュー兼管理DB）接続文字列 |
  | RELAYGATE_SSH_KEY_PATH | Yes | blue/green実装ホストへのSSH接続鍵パス |
- **標準入力**: なし
- **標準出力契約**: `background実行開始: run_id={run_id} slot={blue|green} status=RUNNING` の1行（worker内部ログ、facadeへは起動完了フラグのみ応答）
- **標準エラー契約**: SSH接続失敗・RDB書込み失敗時のエラーメッセージ
- **終了コード**:
  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（Runner実行結果レコード作成・起動完了） |
  | 1 | 業務エラー（起動先実装への接続失敗） |
  | 2 | バリデーションエラー（run_id/slot-type未指定） |

## データモデル変更

### runner_results

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | VARCHAR | facadeから引き継いだrun_id（PK構成要素） | 追加 |
| slot_type | VARCHAR | blue/green | 追加 |
| role_type | VARCHAR | 固定値 'background'（PK構成要素） | 追加 |
| started_at | DATETIME | 起動開始時刻 | 追加 |
| stdout_path | VARCHAR | 実行開始時点ではnull（後続の非同期実行完了時に設定） | 追加（null） |
| stderr_path | VARCHAR | 同上 | 追加（null） |
| exit_code | INT | 同上（未出力） | 追加（null） |
| status | VARCHAR | 固定値 'RUNNING' | 追加 |

## ビジネスルール

- background role実行結果レコードのstatusは起動時点でRUNNING固定とし、hang-detector（UC「background実行の未完了・非0終了・速報比較異常を定期検知する」）による定期検知でSUCCEEDED/FAILEDへ遷移する
- run_idの一意性により冪等性を保証する（LR-003）。同一run_id・slot_type・role_typeの重複起動はRDBの一意制約で防止する
- 楽観ロック競合（同一run_idへの同時起動トリガー）はログに記録する（LR-008）

## CLI 出力/画面表示マッピング（design-event.yaml 参照）

### background role起動画面

- **route**: /cli/concurrent-run/start-background
- **表示要素とコンポーネントマッピング**:
  | 要素 | 種別 | デザインシステムコンポーネント | 説明 |
  |------|------|------------------------------|------|
  | 実行設定カード | カード | ExecutionSpecCard | worker起動時に参照するexecution-spec.jsonの内容 |
  | 起動結果パネル | ターミナル出力 | RunnerResultPanel（background variant, states: RUNNING） | worker側の起動完了状態を表示 |
- **デザイントークン参照**:
  | 用途 | トークン | 値 |
  |------|---------|---|
  | RUNNING状態色 | status-badge-running | background: var(--color-blue-100), foreground: var(--color-blue-600) |
- **UIロジック**:
  - **状態管理**: workerはCronJob/常駐プロセスとしてトリガーキューをポーリングし、lease/claim取得後に起動処理を実行する
  - **バリデーション**: run_id/slot-type必須をCLI引数解析時点で検証
  - **ローディング**: 該当なし（非同期実行のため、起動完了応答のみをfacadeへ返す）
  - **エラーハンドリング**: 起動先実装への接続失敗時はRunner実行結果レコードを作成せずエラー終了し、facade側へエラーを伝播する

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「実行結果ターミナル表示パターン（background variant）」を適用する。tier-facade側と同一コンポーネントを、worker側で確定した値で表示する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| ExecutionSpecCard | `@/components/domain/ExecutionSpecCard` | runId={run_id}（worker起動時に参照するexecution-spec.jsonの内容） |
| RunnerResultPanel | `@/components/domain/RunnerResultPanel` | variant="background", runId={run_id}, slot={slot_type}, status="RUNNING"（起動時点は固定値、hang-detectorによる後続遷移まで不変） |

## ティア完了条件（BDD）

```gherkin
Feature: background roleを起動する - tier-worker

  Scenario: green実装のbackground実行を開始しRunner実行結果を記録する
    Given facadeからrun_id "run-20260817-001", slot_type "green" の起動トリガーを受領した
    When `relaygate worker start-background-execution --run-id run-20260817-001 --slot-type green` を実行する
    Then 終了コード 0 で終了する
    And runner_resultsに run_id "run-20260817-001", slot_type "green", role_type "background", status "RUNNING" のレコードが作成される

  Scenario: green実装ホストへの接続に失敗する
    Given green実装ホストへのSSH接続が失敗する状態である
    When `relaygate worker start-background-execution --run-id run-20260817-004 --slot-type green` を実行する
    Then 終了コード 1 で終了する
    And runner_resultsにrun_id "run-20260817-004" のレコードは作成されない
    And 標準エラーに "green実装への接続に失敗しました" が出力される
```
