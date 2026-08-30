# background roleを起動する - tier-facade仕様

## 変更概要

execution spec（execution_specs + slot_execution_specs）で確定済みのbackground対象slotについて、facadeがworkerへ起動トリガーを送出するCLIコマンドを追加する。実際のbackground実行開始・Runner実行結果（履歴 + snapshot）の永続化・監査イベント追記はtier-workerが担う。

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
  | RELAYGATE_OPERATOR | Yes | 監査イベントのactorへ記録する操作者識別子 |
- **標準入力**: なし
- **標準出力契約**: `background起動: run_id={run_id} slot_type={blue|green} attempt_id={attempt_id} attempt_no={attempt_no} status=STARTING` の1行
- **標準エラー契約**: background対象slotなし・接続失敗・起動前監査の追記失敗時に原因と次アクションを1文ずつ出力する
- **終了コード**:
  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（background起動トリガー送出完了） |
  | 1 | 業務エラー（background対象slotなし・接続失敗・起動前監査の追記失敗による起動中止） |
  | 2 | バリデーションエラー（run_id未指定） |
  | 124 | タイムアウト（RDB接続タイムアウト） |
  | 130 | SIGINT中断 |

## データモデル変更

### execution_specs / slot_execution_specs（参照のみ、変更なし）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| execution_specs.run_id | UUID | 起動対象run_id | 参照のみ |
| slot_execution_specs.run_id, slot_type, host, exec_user, script_path, work_dir, fixed_args, impl_version, credential_ref | - | background対象slotのslot別実行設定 | 参照のみ |

## ビジネスルール

- execution spec で確定済みのbackground対象slot（BLUE_MODE/GREEN_MODEのうちbackground指定されたもの）のみを起動対象とする
- foreground roleの実行に先立ちbackground roleを起動する（BUC.tsvのアクティビティ順序に準拠）
- 起動試行のidentityは (run_id, slot_type, role_type, attempt_id)。標準出力にはattempt_id・attempt_no（同一run_id+slot_type+role_type内の連番、1始まり）を含める
- CLI応答は10秒以内（CTP-009）。ただし実際のbackground実行完了はCLI応答対象外であり、起動トリガー送出完了をもって正常終了とする

## CLI 出力/画面表示マッピング（design-event.yaml 参照）

### background role起動画面

- **route**: /cli/concurrent-run/start-background
- **表示要素とコンポーネントマッピング**:
  | 要素 | 種別 | デザインシステムコンポーネント | 説明 |
  |------|------|------------------------------|------|
  | 実行設定カード | カード | ExecutionSpecCard | 起動対象run_id・run共通/slot別実行設定の内容を表示 |
  | 起動結果パネル | ターミナル出力 | RunnerResultPanel（background variant） | 起動直後のrun_id・attempt_id・status=STARTINGを表示 |
- **デザイントークン参照**:
  | 用途 | トークン | 値 |
  |------|---------|---|
  | RUNNING状態色 | status-badge-running | background: var(--color-blue-100), foreground: var(--color-blue-600) |
- **UIロジック**:
  - **状態管理**: 起動トリガー送出のたびにworkerからの起動完了応答を待機する（同期呼び出し）
  - **バリデーション**: run_id必須、execution spec存在確認をCLI引数解析時点で実施
  - **ローディング**: worker側の起動処理完了までの応答待ち。CLI応答10秒以内
  - **エラーハンドリング**: background対象slotなし・起動前監査の追記失敗は終了コード1、run_id未指定は終了コード2で区別

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「実行結果ターミナル表示パターン（background variant）」を適用する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| ExecutionSpecCard | `@/components/domain/ExecutionSpecCard` | runId={run_id}（run共通execution specとslot別実行設定の内容を表示） |
| RunnerResultPanel | `@/components/domain/RunnerResultPanel` | variant="background", runId={run_id}, slot={slot_type}, status="STARTING" |

## ティア完了条件（BDD）

```gherkin
Feature: background roleを起動する - tier-facade

  Scenario: background起動トリガーをworkerへ送出する
    Given execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement" の行が存在する
    And slot_execution_specs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", host="green-host-01") の行が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001", attempt_no=1, status="STARTING") の行が存在する
    When `relaygate concurrent-run start-background --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行する
    Then 終了コード 0 で終了する
    And 標準出力に "background起動: run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57 slot_type=green attempt_id=att-green-0001 attempt_no=1 status=STARTING" が出力される

  Scenario: run_id未指定でバリデーションエラーになる
    When `relaygate concurrent-run start-background` を引数なしで実行する
    Then 終了コード 2 で終了する
    And 標準エラーに "run_id を指定してください" が出力される
```
