# background roleを起動する - tier-worker仕様

## 変更概要

facadeからのbackground起動トリガーを受けて、tier-workerがRDBのlease/claim機構を用いてbackground role実行を開始する。起動試行のSTARTING記録（runner_result_eventsへの履歴INSERT + runner_resultsのsnapshot UPSERT）と起動前監査イベント（slot_launch_attempted）の追記を同一transactionでcommitする。background slotへの起動イベント（SSH）は起動UC「feature flag設定に基づきslotを選択して起動する」が送出済みであり、workerはSSH経由でstarted-at.txtを回収して起動確認しRUNNINGへ遷移させる（runner_results行が無い場合に限りworkerが起動イベントを送出する）。

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
  | RELAYGATE_CREDENTIAL_DIR | Yes | 認証情報ディレクトリ。slot_execution_specs.credential_ref から SSH 秘密鍵を解決する（cli-command-contract.yaml credential_resolution） |
  | RELAYGATE_SSH_KEY_PATH | No | credential_ref が null のときに用いる既定の SSH 秘密鍵パス |
  | RELAYGATE_OPERATOR | Yes | 監査イベントのactorへ記録する操作者識別子 |
- **標準入力**: なし
- **標準出力契約**: `background実行開始: run_id={run_id} slot_type={blue|green} attempt_id={attempt_id} attempt_no={attempt_no} status={STARTING|RUNNING}` の1行。statusはSTARTING（受付時）またはRUNNING（起動確認後）
- **標準エラー契約**: SSH接続失敗・RDB書込み失敗・起動前監査の追記失敗時に原因と次アクションを1文ずつ出力する
- **終了コード**:
  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（Runner実行結果記録・起動完了） |
  | 1 | 業務エラー（起動先接続失敗・起動前監査の追記失敗による起動中止） |
  | 2 | バリデーションエラー（run_id/slot-type未指定） |
  | 124 | タイムアウト（SSH起動確認タイムアウト。起動試行はUNKNOWNとして記録し推測でFAILEDを確定しない） |
  | 130 | SIGINT中断 |

## データモデル変更

### runner_result_events（履歴、append-only INSERT）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| event_id | UUID | 履歴イベントの一意識別子（PK） | 追加 |
| run_id | UUID | facadeから引き継いだrun_id | 追加 |
| slot_type | VARCHAR | blue/green | 追加 |
| role_type | VARCHAR | 固定値 'background' | 追加 |
| attempt_id | VARCHAR | 起動試行の一意識別子 | 追加 |
| attempt_no | INT | 同一（run_id, slot_type, role_type）内の連番（1始まり） | 追加 |
| event_name | VARCHAR | attempt_started / attempt_running / attempt_failed / attempt_unknown。(run_id, slot_type, role_type, attempt_id, event_name)の一意制約で再試行を冪等化 | 追加 |
| status | VARCHAR | 遷移後状態（STARTING/RUNNING/FAILED/UNKNOWN） | 追加 |
| occurred_at | DATETIME | イベント発生時刻 | 追加 |
| started_at | DATETIME | 実行開始時刻（attempt_running時に設定、それ以前はnull） | 追加（null許容） |

### runner_results（snapshot、UPSERT）

runner_result_eventsへの履歴INSERTと**同一transaction**でUPSERTする（LR-002 Event/Snapshot併用。片方だけがcommitされる状態を許容しない）。PK=(run_id, slot_type, role_type, attempt_id)。

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id / slot_type / role_type / attempt_id | - | 起動試行のidentity（複合PK） | 追加 |
| attempt_no | INT | 起動試行連番（1始まり）。(run_id, slot_type, role_type, attempt_no)の一意制約 | 追加 |
| accepted_at | DATETIME | 起動受付時刻（STARTING遷移時点。プロセス起動前でも必ず記録） | 追加 |
| started_at | DATETIME | 起動開始時刻（起動確認前はnull） | 追加（null許容） |
| stdout_path / stderr_path | VARCHAR | 実行開始時点ではnull（後続の非同期実行完了時に設定） | 追加（null） |
| exit_code | INT | 未完了・UNKNOWN時はnull | 追加（null） |
| status | VARCHAR | STARTING → RUNNING（起動確認成功）/ FAILED（起動失敗）/ UNKNOWN（タイムアウト等の結果取得不能） | 追加 |
| updated_at | DATETIME | snapshot最終更新時刻（対応するrunner_result_events.occurred_atと一致） | 追加 |

### audit_logs / audit_chain_heads

外部slot起動前にslot_launch_attempted、起動後にslot_launch_succeeded / slot_launch_failed / slot_launch_timeoutを追記する。追記はaudit_chain_headsのrun_id行を排他ロック（SELECT ... FOR UPDATE）してprevious_hashを確定し、audit_logs INSERTとaudit_chain_heads更新を同一transactionで完了する（正本: `_cross-cutting/api/audit-event-contract.yaml`）。

## ビジネスルール

- background slotへの起動イベント（SSH）の送出主体は起動UC「feature flag設定に基づきslotを選択して起動する」である。対象試行のrunner_results行がSTARTING（起動UCが送出済み）の場合は起動イベントを再送出せず、started-at.txtの回収による起動確認（STARTING→RUNNING）と回収不能時のFAILED/UNKNOWN判定だけを行う。行が存在しない場合に限りSTARTINGを冪等INSERTして起動イベントを送出する。対象試行が既にFAILED/UNKNOWN（起動UCの補償記録）またはRUNNING以降なら再送出せず終了コード1（stderr「background対象slotの起動試行がSTARTINGではありません: run_id=… slot_type=… status=…」）
- 起動試行のSTARTING記録と起動前監査イベント（slot_launch_attempted）の追記を同一transactionでcommitできない場合は、外部slotを起動しない（起動前監査ゲート、CTR-008）
- runner_result_eventsへの履歴INSERTとrunner_resultsのsnapshot UPSERTは必ず同一transactionで実行する（LR-002）。片方だけがcommitされる状態を許容しない
- SSH起動確認タイムアウト等で結果を取得できない場合はUNKNOWNとして記録し、推測でFAILEDを確定しない。UNKNOWNからの確定は実結果の回収または対話確認による回復処理でのみ行う
- background roleのRUNNING以降の完了判定（SUCCEEDED/FAILED）はhang-detector（UC「background実行の未完了・非0終了・速報比較異常を定期検知する」）が担う
- 冪等性は起動試行identity（run_id, slot_type, role_type, attempt_id）と(…, event_name)の一意制約で保証する（LR-003、CTP-006）。クラッシュ後の再試行は既存イベントとの一意制約衝突で冪等スキップする
- 外部slot起動後の監査イベント追記失敗は、元の起動結果と未記録状態を失わずローカル永続outboxへ退避し、冪等キー(run_id, slot, attempt_id, event_name)で照合して再試行する
- 楽観ロック競合（同一run_idへの同時起動トリガー）はログに記録する（LR-008）
- SSH秘密鍵はslot_execution_specs.credential_refからcli-command-contract.yaml credential_resolution（`RELAYGATE_CREDENTIAL_DIR/{credential_ref}`、nullなら`RELAYGATE_SSH_KEY_PATH`）で解決する。facade（起動UC）と同じ契約であり、鍵の実値はRDB・監査・標準出力・標準エラー・起動イベントに出さない
- 起動引数はslot_execution_specs.fixed_args（JSON配列）の要素の後ろにexecution_specs.additional_args（JSON配列）の要素を順序を変えず後置連結したargvとする（rdb-schema.yaml argument_serialization。要素の再分割・再結合・クォート付与をしない）
- ジョブマップは読まない（slot_execution_specsに保存済みの解決結果だけを用いる）

## CLI 出力/画面表示マッピング（design-event.yaml 参照）

### background role起動画面

- **route**: /cli/concurrent-run/start-background
- **表示要素とコンポーネントマッピング**:
  | 要素 | 種別 | デザインシステムコンポーネント | 説明 |
  |------|------|------------------------------|------|
  | 実行設定カード | カード | ExecutionSpecCard | worker起動時に参照するrun共通/slot別実行設定の内容 |
  | 起動結果パネル | ターミナル出力 | RunnerResultPanel（background variant, states: STARTING/RUNNING/FAILED/UNKNOWN） | worker側の起動試行状態を表示 |
- **デザイントークン参照**:
  | 用途 | トークン | 値 |
  |------|---------|---|
  | RUNNING状態色 | status-badge-running | background: var(--color-blue-100), foreground: var(--color-blue-600) |
- **UIロジック**:
  - **状態管理**: workerはCronJob/常駐プロセスとしてトリガーキューをポーリングし、lease/claim取得後に起動処理を実行する
  - **バリデーション**: run_id/slot-type必須をCLI引数解析時点で検証
  - **ローディング**: 該当なし（非同期実行のため、起動完了応答のみをfacadeへ返す）
  - **エラーハンドリング**: 起動先実装への接続失敗はFAILED、タイムアウトはUNKNOWNとして履歴+snapshotを同一transactionで記録したうえでエラー終了し、facade側へエラーを伝播する

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「実行結果ターミナル表示パターン（background variant）」を適用する。tier-facade側と同一コンポーネントを、worker側で確定した値で表示する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| ExecutionSpecCard | `@/components/domain/ExecutionSpecCard` | runId={run_id}（worker起動時に参照するrun共通/slot別実行設定の内容） |
| RunnerResultPanel | `@/components/domain/RunnerResultPanel` | variant="background", runId={run_id}, slot={slot_type}, status={STARTING\|RUNNING\|FAILED\|UNKNOWN} |

## ティア完了条件（BDD）

```gherkin
Feature: background roleを起動する - tier-worker

  Scenario: green実装のbackground実行を開始しRunner実行結果を記録する
    Given execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の行が、slot_execution_specs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", host="green-host-01") の行が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001", attempt_no=1, status="STARTING") の行が存在する
    And 環境変数に RELAYGATE_OPERATOR=ops-tanaka が設定されている
    When `relaygate worker start-background-execution --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57 --slot-type green` を実行する
    Then 終了コード 0 で終了する
    And runner_results の att-green-0001 行が status="RUNNING", started_at 記録済みへ更新される
    And runner_result_events に event_name="attempt_running", status="RUNNING" の履歴が同一transactionでINSERTされる
    And audit_logs に (slot="green", attempt_id="att-green-0001", event_name="slot_launch_succeeded", outcome="succeeded") がINSERTされる

  Scenario: green実装ホストへの接続に失敗しFAILEDとして記録する
    Given execution_specs・slot_execution_specs・runner_results に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の green/background/att-green-0001（status="STARTING"）一式が存在する
    And green実装ホスト green-host-01 への起動確認のSSH接続が失敗する状態である
    When `relaygate worker start-background-execution --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57 --slot-type green` を実行する
    Then 終了コード 1 で終了する
    And runner_results の att-green-0001 行が status="FAILED" へ更新され、runner_result_events に event_name="attempt_failed" の履歴が同一transactionでINSERTされる
    And 標準エラーに "green実装への接続に失敗しました" が出力される

  Scenario: SSH起動タイムアウトでUNKNOWNとして記録する
    Given execution_specs・slot_execution_specs・runner_results に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の green/background/att-green-0001（status="STARTING"）一式が存在する
    And green実装ホスト green-host-01 へのSSH起動確認がタイムアウトする状態である
    When `relaygate worker start-background-execution --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57 --slot-type green` を実行する
    Then 終了コード 124 で終了する
    And runner_results の att-green-0001 行が status="UNKNOWN" へ更新される（推測でFAILEDを確定しない）
    And audit_logs に event_name="slot_launch_timeout", outcome="timeout" がINSERTされる

  Scenario: credential_refからSSH秘密鍵を解決し空白を含む引数を要素順のまま起動する
    Given execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement", additional_args=["--note","a b \"c\""] の行が存在する
    And slot_execution_specs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", host="green-host-01", credential_ref="cred-green-batch", fixed_args=["--mode","batch"]) の行が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background") の行が存在しない（起動UCを経ない起動トリガー。workerがSTARTINGを冪等INSERTして起動イベントを送出する経路）
    And attempt_id発番が "att-green-0001" を返すよう固定されている
    And 環境変数に RELAYGATE_CREDENTIAL_DIR=/etc/relaygate/credentials が設定され、/etc/relaygate/credentials/cred-green-batch に固有の識別文字列を含むSSH秘密鍵が配置されている
    When `relaygate worker start-background-execution --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57 --slot-type green` を実行する
    Then SSH は /etc/relaygate/credentials/cred-green-batch を秘密鍵として green-host-01 へ接続する
    And 起動イベントの argv は ["--mode","batch","--note","a b \"c\""] である（要素の再分割・再結合・クォート付与をしない）
    And 鍵の識別文字列は標準出力・標準エラー・RDB（runner_results / runner_result_events / audit_logs）のいずれにも現れない
```
