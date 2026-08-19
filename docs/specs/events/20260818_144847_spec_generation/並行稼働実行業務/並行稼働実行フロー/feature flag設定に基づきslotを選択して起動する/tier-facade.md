# feature flag設定に基づきslotを選択して起動する - tier-facade仕様

## 変更概要

ジョブスケジューラから受け取ったJOB_ID・追加引数を起点に、feature flag設定（BLUE_MODE/GREEN_MODE/RAPID_CROSSCHECK_MODE）を判定してblue/greenのslot起動方式を決定し、run共通のexecution spec（execution_specs）とslot別実行設定（slot_execution_specs）を一度だけ確定して保存したうえでSSH経由でslotを起動するCLIコマンドを追加する。実行設定のINSERT・runner_results/runner_result_eventsのSTARTING記録・起動前監査イベント（slot_launch_accepted/slot_launch_attempted）の追記を同一transactionでcommitしてから外部slotを起動する。

## CLI コマンド仕様

### relaygate concurrent-run select-slot

- **呼び出し形式**: `relaygate concurrent-run select-slot --job-id <JOB_ID> [-- <追加引数...>]`
- **引数**:
  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --job-id | string | Yes | ジョブスケジューラから渡されるJOB_ID |
  | -- 追加引数 | string[] | No | ジョブ定義に付随するrun共通の追加引数。そのままexecution_specs.additional_argsに保存する |
- **環境変数**:
  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | RDB（ジョブキュー兼管理DB）接続文字列 |
  | RELAYGATE_JOB_MAP_PATH | Yes | ジョブマップ（実行先解決定義）のファイルパス |
  | BLUE_MODE | Yes | off/background/foreground のいずれか |
  | GREEN_MODE | Yes | off/background/foreground のいずれか |
  | RAPID_CROSSCHECK_MODE | Yes | on/off のいずれか |
  | RELAYGATE_OPERATOR | Yes | 監査イベントのactorへ記録する操作者識別子。省略時はfacadeを既定値としない（起動前監査ゲートのため必須） |
- **標準入力**: なし
- **標準出力契約**: run_id・slot_type・role・attempt_id・status=STARTINGを選択slotごとに1行で出力する
- **標準エラー契約**: feature flag違反（BLUE_MODEとGREEN_MODEの同時foreground）・ジョブマップ未解決・起動前監査の追記失敗時に原因と次アクションを1文ずつ出力する
- **終了コード**:
  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（slot選択・実行設定確定・起動完了） |
  | 1 | 業務エラー（ジョブマップ未解決・接続失敗・起動前監査の追記失敗による起動中止） |
  | 2 | バリデーションエラー（BLUE_MODE/GREEN_MODE同時foreground、JOB_ID未指定） |
  | 124 | タイムアウト（RDB接続タイムアウト） |
  | 130 | SIGINT中断 |

## データモデル変更

### execution_specs（run共通execution spec）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | UUID | 実行の一意識別子（PK）。起動時に新規発番する | 追加 |
| parent_run_id | UUID | リラン時の元run_id参照（nullable、自己参照FK） | 追加 |
| job_id | VARCHAR | ジョブスケジューラのJOB_ID | 追加 |
| additional_args | TEXT | ジョブスケジューラから渡されたrun共通の追加引数（nullable） | 追加 |
| job_map_version | VARCHAR | 実行先解決に使用したジョブマップのバージョン | 追加 |
| hang_detect_limit_minutes | INT | ハング検知しきい値（分） | 追加 |

### slot_execution_specs（slot別実行設定）

同一runでもblue/greenでhost・実装版などが異なりうるため、run共通のexecution_specsから分離してslotごとに保存する。PK=(run_id, slot_type)。

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | UUID | execution_specs.run_idへのFK（複合PKの一部） | 追加 |
| slot_type | VARCHAR | slot種別（blue/green、複合PKの一部） | 追加 |
| host | VARCHAR | ジョブマップ解決済みの実行先ホスト（slotごとに異なりうる） | 追加 |
| exec_user | VARCHAR | 実行ユーザー | 追加 |
| script_path | VARCHAR | 実行スクリプトパス | 追加 |
| work_dir | VARCHAR | 作業ディレクトリ | 追加 |
| fixed_args | TEXT | ジョブマップに固定された起動引数（nullable） | 追加 |
| impl_version | VARCHAR | 当該slotの実装バージョン | 追加 |
| credential_ref | VARCHAR | 認証情報参照名（実値は保存しない、nullable） | 追加 |

### runner_result_events / runner_results

選択したslotごとに、起動受付（STARTING）を履歴（runner_result_events INSERT）とsnapshot（runner_results INSERT）へ同一transactionで記録する。起動試行のidentityは (run_id, slot_type, role_type, attempt_id)。

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | UUID | 本UCで新規発番したrun_id（execution_specs.run_idと同一） | 追加 |
| slot_type | VARCHAR | 選択されたslot（blue/green） | 追加 |
| role_type | VARCHAR | feature flagで決定した役割（foreground/background） | 追加 |
| attempt_id | VARCHAR | 起動試行の一意識別子 | 追加 |
| attempt_no | INT | 同一（run_id, slot_type, role_type）内の連番。初回起動は1 | 追加 |
| accepted_at | DATETIME | 起動受付時刻（STARTING遷移時点） | 追加 |
| status | VARCHAR | 固定値 STARTING（本UC時点。RUNNING以降への遷移は後続UCが担う） | 追加 |

### audit_logs / audit_chain_heads

起動前監査イベント（slot_launch_accepted: slot='-'/attempt_id='-'、slot_launch_attempted: slotごと）を、audit_chain_headsのrun_id行を排他ロック（SELECT ... FOR UPDATE）してprevious_hashを確定したうえでaudit_logsへINSERTし、同一transactionでaudit_chain_headsを更新する。フィールドはactor/operation/outcomeに統一する（正本: `_cross-cutting/api/audit-event-contract.yaml`）。

## ビジネスルール

- BLUE_MODEとGREEN_MODEを同時にforegroundにする組み合わせは拒否する（SR-001 排他的foreground制約）
- execution_specs / slot_execution_specs のINSERT、選択slotごとのrunner_result_events + runner_resultsのSTARTING記録、起動前監査イベント（slot_launch_accepted / slot_launch_attempted）のaudit_logs INSERTとaudit_chain_heads更新は、すべて同一transactionでcommitしてから外部slotを起動する。このtransactionがcommitできない場合は外部slotを起動しない（起動前監査ゲート、CTR-008）
- RAPID_CROSSCHECK_MODE=offの場合、blue/green実装からの完了通知送信・速報管理DBへの接続/書込みは一切行わない
- run共通実行設定（run_id/parent_run_id/job_id/追加引数/マップ版/hang_detect_limit_minutes）とslot別実行設定（host/実行ユーザー/スクリプト/作業ディレクトリ/固定引数/実装版/認証情報参照名）は起動時に一度だけ確定して保存する。リランは新しいrun_idの新規runとして作成しparent_run_idで元runへ関連付ける（元runのレコードは変更しない）
- 認証情報は参照名のみを保存し実値は保存しない
- 監査イベントの冪等キーは (run_id, slot, attempt_id, event_name)。slot/attempt_idが非該当のイベントはNULLではなく '-' を格納する
- CLI応答は10秒以内（CTP-009）

## CLI 出力/画面表示マッピング（design-event.yaml 参照）

### 起動slot選択画面

- **route**: /cli/concurrent-run/select-slot
- **表示要素とコンポーネントマッピング**:
  | 要素 | 種別 | デザインシステムコンポーネント | 説明 |
  |------|------|------------------------------|------|
  | 実行設定カード | カード | ExecutionSpecCard | run_id/job_id/host/script/mapVersion/implVersion/hangDetectLimitMinutes/credentialRefを表示。host/script/implVersion/credentialRefはslot別実行設定（slot_execution_specs）由来。credentialRefは参照名のみ |
  | エラー・警告バナー | バナー | Banner（error/warning） | BLUE_MODE/GREEN_MODE同時foreground拒否理由・起動前監査の追記失敗を即時表示 |
- **デザイントークン参照**:
  | 用途 | トークン | 値 |
  |------|---------|---|
  | 拒否理由バナー | banner-error | background: var(--color-red-100), foreground: var(--color-red-600) |
  | 実行設定カード背景 | var(--semantic-background) | var(--color-white) |
- **UIロジック**:
  - **状態管理**: JOB_ID起動ごとに新規のrun共通execution spec 1件とslot別実行設定（選択slot分）が確定される（キャッシュしない、冪等性はrun_idの一意性と(run_id, slot_type, role_type, attempt_id)のidentityで担保: LR-003）
  - **バリデーション**: CLI引数解析時点でBLUE_MODE/GREEN_MODEの組み合わせ・JOB_ID必須を全て検証する（LP-001）
  - **ローディング**: CLI応答10秒以内。将来ダッシュボードではExecutionSpecCard表示前にローディング表示
  - **エラーハンドリング**: feature flag違反は終了コード2、ジョブマップ未解決・起動先接続失敗・起動前監査の追記失敗による起動中止は終了コード1で区別する

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「共通状態表示パターン」（エラー表示は Banner の error variant）を適用する。ExecutionSpecCard は design-event.yaml 既存コンポーネントをそのまま利用する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| ExecutionSpecCard | `@/components/domain/ExecutionSpecCard` | runId={run_id}, jobId={job_id}, host={slot_execution_specs.host}, script={slot_execution_specs.script_path}, workDir={slot_execution_specs.work_dir}, fixedArgs={slot_execution_specs.fixed_args}, additionalArgs={execution_specs.additional_args}, mapVersion={job_map_version}, implVersion={slot_execution_specs.impl_version}, hangDetectLimitMinutes={hang_detect_limit_minutes}, credentialRef={slot_execution_specs.credential_ref}（参照名のみ） |
| Banner | `@/components/ui/Banner` | variant="error" \| "warning", message={BLUE_MODE/GREEN_MODE同時foreground拒否理由 or 起動前監査の追記失敗理由} |

## ティア完了条件（BDD）

```gherkin
Feature: feature flag設定に基づきslotを選択して起動する - tier-facade

  Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And ジョブマップ v1.4.0 で job_id "daily-settlement" が blue（host=blue-host-01, impl_version=blue-2.3.1）と green（host=green-host-01, impl_version=green-0.9.0）に解決できる
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を返すよう固定されている
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 0 で終了する
    And execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の1行がINSERTされる
    And slot_execution_specs に slot_type="blue" と slot_type="green" の2行がINSERTされる
    And runner_results に status="STARTING" の2行と、runner_result_events に event_name="attempt_started" の2行が同一transactionでINSERTされる
    And audit_logs に event_name="slot_launch_accepted" と event_name="slot_launch_attempted" の起動前監査イベントがINSERTされる

  Scenario: BLUE_MODEとGREEN_MODEが同時にforegroundでバリデーションエラーになる
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=foreground, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 2 で終了する
    And execution_specs・slot_execution_specs へのINSERTは発生しない

  Scenario: 起動前監査の追記失敗で外部slotを起動しない
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And ジョブマップ v1.4.0 で job_id "daily-settlement" が解決できる
    And audit_logs へのINSERTが失敗する状態になっている
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 1 で終了する
    And execution_specs・slot_execution_specs・runner_results・runner_result_events へのINSERTはrollbackされ残らない
    And 外部slotへの起動イベントは送出されない
```
