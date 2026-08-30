# feature flag設定に基づきslotを選択して起動する - tier-facade仕様

## 変更概要

ジョブスケジューラから受け取ったJOB_ID・追加引数を起点に、feature flag設定（BLUE_MODE/GREEN_MODE/RAPID_CROSSCHECK_MODE）を判定してblue/greenのslot起動方式を決定し、slotごとの独立したジョブマップ（`RELAYGATE_JOB_MAP_PATH_BLUE` / `RELAYGATE_JOB_MAP_PATH_GREEN`）から実行先を解決して、run共通のexecution spec（execution_specs）とslot別実行設定（slot_execution_specs。job_map_versionを含む）を一度だけ確定して保存したうえでSSH経由の起動イベントを送出するCLIコマンドを追加する。実行設定のINSERT・runner_results/runner_result_eventsのSTARTING記録・起動前監査イベント（slot_launch_accepted/slot_launch_attempted）の追記を同一transactionでcommitしてから外部slotへ起動イベントを送出する。送出に失敗した試行はFAILED、timeoutした試行はUNKNOWNへ本コマンドが補償記録する。

## CLI コマンド仕様

### relaygate concurrent-run select-slot

- **呼び出し形式**: `relaygate concurrent-run select-slot --job-id <JOB_ID> [-- <追加引数...>]`
- **引数**:
  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --job-id | string | Yes | ジョブスケジューラから渡されるJOB_ID |
  | -- 追加引数 | string[] | No | ジョブ定義に付随するrun共通の追加引数。要素順のままJSON配列としてexecution_specs.additional_argsに保存する（`rdb-schema.yaml` argument_serialization） |
- **環境変数**:
  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | RDB（ジョブキュー兼管理DB）接続文字列 |
  | RELAYGATE_JOB_MAP_PATH_BLUE | BLUE_MODE が off 以外のとき必須 | blue slotのジョブマップ（JSON）のファイルパス。形式は `cli-command-contract.yaml` job_map_contract |
  | RELAYGATE_JOB_MAP_PATH_GREEN | GREEN_MODE が off 以外のとき必須 | green slotのジョブマップ（JSON）のファイルパス。同上 |
  | RELAYGATE_CREDENTIAL_DIR | Yes | 認証情報ディレクトリ。`{RELAYGATE_CREDENTIAL_DIR}/{credential_ref}` をSSH秘密鍵として解決する（`cli-command-contract.yaml` credential_resolution） |
  | RELAYGATE_SSH_KEY_PATH | No | credential_ref が null のslotに用いる既定のSSH秘密鍵パス |
  | BLUE_MODE | Yes | off/background/foreground のいずれか |
  | GREEN_MODE | Yes | off/background/foreground のいずれか |
  | RAPID_CROSSCHECK_MODE | Yes | on/off のいずれか |
  | RELAYGATE_OPERATOR | Yes | 監査イベントのactorへ記録する操作者識別子。省略時はfacadeを既定値としない（起動前監査ゲートのため必須） |
- **標準入力**: なし
- **標準出力契約**: run_id・slot_type・role・attempt_id・status=STARTINGを選択slotごとに1行で出力する。起動受付の記録であり、起動イベント送出に失敗・timeoutした場合も維持する（実行状態の正本はrunner_results）
- **標準エラー契約**: feature flag違反（BLUE_MODEとGREEN_MODEの同時foreground）・ジョブマップ未解決/不正・認証情報の解決失敗・起動前監査の追記失敗・起動イベント送出失敗/timeout時に原因と次アクションを1文ずつ出力する。送出失敗/timeoutでは `slot_type={blue|green} attempt_id={attempt_id} を {FAILED|UNKNOWN} として記録しました` を含める
- **終了コード**:
  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（slot選択・実行設定確定・全起動対象slotへの起動イベント送出完了） |
  | 1 | 業務エラー（JOB_ID未解決・SSH認証情報の解決失敗・起動前監査の追記失敗による起動中止・起動イベント送出失敗（当該試行をFAILEDへ補償記録）） |
  | 2 | バリデーションエラー（BLUE_MODE/GREEN_MODE同時foreground、JOB_ID未指定、ジョブマップの欠落/不正、credential_ref の書式不正） |
  | 124 | タイムアウト（RDB接続タイムアウト、または起動イベント送出timeout。送出timeoutの試行はUNKNOWNへ補償記録し推測でFAILEDを確定しない。送出失敗と混在した場合は1） |
  | 130 | SIGINT中断 |

## ジョブマップ（外部入力ファイル）

正本は `_cross-cutting/api/cli-command-contract.yaml` の `job_map_contract`。本tierは次のとおり読む。

- 起動対象（mode が background / foreground）のslotのファイルだけを読む。mode=off のslotは読まず、環境変数未設定でもエラーにしない
- 検証（必須フィールド・型・`slot_type` と環境変数の一致・`jobs[job_id]` の存在）はtransaction開始前に起動対象の全slot分を行い、1つでも失敗したらRDBへ書き込まず外部slotを起動しない
- 未知のフィールドは無視し、その値をRDB・監査・標準出力・標準エラー・起動イベントへ出さない
- `job_map_version` はslot別に `slot_execution_specs.job_map_version` へ保存する。run共通の `execution_specs.hang_detect_limit_minutes` にはbackground roleに選ばれたslotの値を採用する（両slotがbackgroundなら大きい方、backgroundが無ければ起動対象の唯一のslotの値）

## データモデル変更

### execution_specs（run共通execution spec）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | UUID | 実行の一意識別子（PK）。起動時にRFC 4122 v4で新規発番する | 追加 |
| parent_run_id | UUID | リラン時の元run_id参照（nullable、自己参照FK） | 追加 |
| job_id | VARCHAR | ジョブスケジューラのJOB_ID | 追加 |
| additional_args | TEXT | ジョブスケジューラから渡されたrun共通の追加引数。JSON配列（要素は文字列）で保存する（nullable。未指定は空配列 [] と同じ扱い） | 追加 |
| hang_detect_limit_minutes | INT | ハング検知しきい値（分）。run共通の1値。background roleに選ばれたslotのジョブマップ値 | 追加 |

物理型は `rdb-schema.yaml` の physical_type_mapping（uuid→uuid、string→text、text→text、integer→integer、datetime→timestamptz）に従う。job_map_version は本テーブルには持たない（slot_execution_specsへ移動）。

### slot_execution_specs（slot別実行設定）

同一runでもblue/greenでhost・実装版・ジョブマップ版などが異なりうるため、run共通のexecution_specsから分離してslotごとに保存する。PK=(run_id, slot_type)。

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | UUID | execution_specs.run_idへのFK（複合PKの一部） | 追加 |
| slot_type | VARCHAR | slot種別（blue/green、複合PKの一部） | 追加 |
| host | VARCHAR | ジョブマップ解決済みの実行先ホスト（slotごとに異なりうる） | 追加 |
| exec_user | VARCHAR | 実行ユーザー | 追加 |
| script_path | VARCHAR | 実行スクリプトパス | 追加 |
| work_dir | VARCHAR | 作業ディレクトリ | 追加 |
| fixed_args | TEXT | ジョブマップに固定された起動引数。JSON配列（要素は文字列）で保存する（nullable。省略時は []） | 追加 |
| impl_version | VARCHAR | 当該slotの実装バージョン | 追加 |
| credential_ref | VARCHAR | 認証情報参照名（実値は保存しない、nullable）。書式 `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$` | 追加 |
| job_map_version | VARCHAR | その slot の実行先解決に使用したジョブマップ（slotごとの独立ファイル）の版 | 追加 |

### runner_result_events / runner_results

選択したslotごとに、起動受付（STARTING）を履歴（runner_result_events INSERT）とsnapshot（runner_results INSERT）へ同一transactionで記録する。起動試行のidentityは (run_id, slot_type, role_type, attempt_id)。起動イベント送出に失敗した試行はFAILED、timeoutした試行はUNKNOWNへ、履歴INSERT + snapshot UPDATEを同一transactionで補償記録する。

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | UUID | 本UCで新規発番したrun_id（execution_specs.run_idと同一） | 追加 |
| slot_type | VARCHAR | 選択されたslot（blue/green） | 追加 |
| role_type | VARCHAR | feature flagで決定した役割（foreground/background） | 追加 |
| attempt_id | VARCHAR | 起動試行の一意識別子 | 追加 |
| attempt_no | INT | 同一（run_id, slot_type, role_type）内の連番。初回起動は1 | 追加 |
| accepted_at | DATETIME | 起動受付時刻（STARTING遷移時点）。同一transactionのoccurred_at / updated_atと同一値（マイクロ秒精度・UTC） | 追加 |
| status | VARCHAR | 起動受付時はSTARTING。送出失敗はFAILED（event_name=attempt_failed）、送出timeoutはUNKNOWN（event_name=attempt_unknown）へ本UCが更新する。送出成功後のRUNNING以降への遷移は後続UCが担う | 追加 / 更新 |
| exit_code / stdout_path / stderr_path | INT / VARCHAR | 補償記録ではNULLのまま（実行結果は存在しない） | - |

### audit_logs / audit_chain_heads

起動前監査イベント（slot_launch_accepted: slot='-'/attempt_id='-'、slot_launch_attempted: slotごと）を、audit_chain_headsのrun_id行を排他ロック（SELECT ... FOR UPDATE）してprevious_hashを確定したうえでaudit_logsへINSERTし、同一transactionでaudit_chain_headsを更新する。起動イベント送出失敗/timeoutの補償記録後は slot_launch_failed（error_code=launch_event_send_failed）/ slot_launch_timeout（error_code=launch_event_send_timeout）を同じlock契約で追記し、追記に失敗した場合はローカル永続outboxへ退避する（post_launch契約）。event_hashは `audit-event-contract.yaml` の hash_chain.canonical_form（13項目を `|` 連結、nullは空文字、`\` と `|` をエスケープ、末尾に `|previous_hash`、SHA-256 16進小文字64桁）で算出する。フィールドはactor/operation/outcomeに統一する（正本: `_cross-cutting/api/audit-event-contract.yaml`）。

## ビジネスルール

- BLUE_MODEとGREEN_MODEを同時にforegroundにする組み合わせは拒否する（SR-001 排他的foreground制約）
- ジョブマップはslotごとの独立ファイルであり、起動対象slotの分だけを読み、transaction開始前に検証する。検証失敗時はRDBへ書き込まず外部slotを起動しない
- execution_specs / slot_execution_specs のINSERT、選択slotごとのrunner_result_events + runner_resultsのSTARTING記録、起動前監査イベント（slot_launch_accepted / slot_launch_attempted）のaudit_logs INSERTとaudit_chain_heads更新は、すべて同一transactionでcommitしてから外部slotへ起動イベントを送出する。このtransactionがcommitできない場合は外部slotを起動しない（起動前監査ゲート、CTR-008）
- 起動イベントの送出順序はbackground roleのslotが先、foreground roleのslotが後。foreground実行の完了は待たない（完了待機は「foreground roleの標準出力・標準エラー・終了コードを応答する」の wait_contract）
- 起動イベント送出の結果はslotごとに独立に判定する。送出失敗はFAILED（attempt_failed）、送出timeoutはUNKNOWN（attempt_unknown。推測でFAILEDにしない）へ、履歴INSERT + snapshot UPDATEを同一transactionで補償記録し、続けて slot_launch_failed / slot_launch_timeout を追記する。他slotの送出は続行する。終了コードは送出失敗ありなら1、timeoutのみなら124
- RAPID_CROSSCHECK_MODE=offの場合、blue/green実装からの完了通知送信・速報管理DBへの接続/書込みは一切行わない
- run共通実行設定（run_id/parent_run_id/job_id/追加引数/hang_detect_limit_minutes）とslot別実行設定（host/実行ユーザー/スクリプト/作業ディレクトリ/固定引数/実装版/認証情報参照名/ジョブマップ版）は起動時に一度だけ確定して保存する。リランは新しいrun_idの新規runとして作成しparent_run_idで元runへ関連付ける（元runのレコードは変更しない）
- hang_detect_limit_minutes はrun共通の1値としてbackground roleに選ばれたslotのジョブマップ値を採用する（両slotがbackgroundなら大きい方、backgroundが無ければ起動対象の唯一のslotの値）
- 起動引数は fixed_args の要素の後ろに additional_args の要素を順序を変えず後置連結したargvとして送出する。保存形式はJSON配列であり、空白・引用符・改行を含む要素も往復で同一になる（bash の %q 連結は採用しない）
- 認証情報は参照名（credential_ref）のみを保存し、SSH秘密鍵は `RELAYGATE_CREDENTIAL_DIR/{credential_ref}`（nullなら `RELAYGATE_SSH_KEY_PATH`）から解決する。鍵の実値はRDB・監査・標準出力・標準エラー・起動イベントに出さない
- 監査イベントの冪等キーは (run_id, slot, attempt_id, event_name)。slot/attempt_idが非該当のイベントはNULLではなく '-' を格納する
- 同一transactionで記録する時刻カラム（accepted_at / occurred_at / updated_at、audit_logs.occurred_at / audit_chain_heads.updated_at）は同一値にする。時刻はUTC・マイクロ秒精度（`rdb-schema.yaml` datetime_rules）
- CLI応答は10秒以内（CTP-009）。対象は起動受付（transaction commitと起動イベント送出）までの応答であり、foreground実行の完了待機を含まない

## CLI 出力/画面表示マッピング（design-event.yaml 参照）

### 起動slot選択画面

- **route**: /cli/concurrent-run/select-slot
- **表示要素とコンポーネントマッピング**:
  | 要素 | 種別 | デザインシステムコンポーネント | 説明 |
  |------|------|------------------------------|------|
  | 実行設定カード | カード | ExecutionSpecCard | run_id/job_id/host/script/mapVersion/implVersion/hangDetectLimitMinutes/credentialRefを表示。host/script/implVersion/mapVersion/credentialRefはslot別実行設定（slot_execution_specs）由来。credentialRefは参照名のみ |
  | エラー・警告バナー | バナー | Banner（error/warning） | BLUE_MODE/GREEN_MODE同時foreground拒否理由・ジョブマップ検証エラー・起動前監査の追記失敗・起動イベント送出失敗/timeoutを即時表示 |
- **デザイントークン参照**:
  | 用途 | トークン | 値 |
  |------|---------|---|
  | 拒否理由バナー | banner-error | background: var(--color-red-100), foreground: var(--color-red-600) |
  | 実行設定カード背景 | var(--semantic-background) | var(--color-white) |
- **UIロジック**:
  - **状態管理**: JOB_ID起動ごとに新規のrun共通execution spec 1件とslot別実行設定（選択slot分）が確定される（キャッシュしない、冪等性はrun_idの一意性と(run_id, slot_type, role_type, attempt_id)のidentityで担保: LR-003）
  - **バリデーション**: CLI引数解析時点でBLUE_MODE/GREEN_MODEの組み合わせ・JOB_ID必須を全て検証し、続けて起動対象slotのジョブマップを検証する（LP-001）
  - **ローディング**: CLI応答10秒以内（起動受付まで）。将来ダッシュボードではExecutionSpecCard表示前にローディング表示
  - **エラーハンドリング**: feature flag違反・ジョブマップ不正は終了コード2、JOB_ID未解決・認証情報解決失敗・起動前監査の追記失敗による起動中止・起動イベント送出失敗は終了コード1、送出timeoutは124で区別する

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「共通状態表示パターン」（エラー表示は Banner の error variant）を適用する。ExecutionSpecCard は design-event.yaml 既存コンポーネントをそのまま利用する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| ExecutionSpecCard | `@/components/domain/ExecutionSpecCard` | runId={run_id}, jobId={job_id}, host={slot_execution_specs.host}, script={slot_execution_specs.script_path}, workDir={slot_execution_specs.work_dir}, fixedArgs={slot_execution_specs.fixed_args}, additionalArgs={execution_specs.additional_args}, mapVersion={slot_execution_specs.job_map_version}, implVersion={slot_execution_specs.impl_version}, hangDetectLimitMinutes={execution_specs.hang_detect_limit_minutes}, credentialRef={slot_execution_specs.credential_ref}（参照名のみ） |
| Banner | `@/components/ui/Banner` | variant="error" \| "warning", message={BLUE_MODE/GREEN_MODE同時foreground拒否理由 or ジョブマップ検証エラー or 起動前監査の追記失敗理由 or 起動イベント送出失敗/timeout} |

## ティア完了条件（BDD）

```gherkin
Feature: feature flag設定に基づきslotを選択して起動する - tier-facade

  Background:
    Given 環境変数 RELAYGATE_JOB_MAP_PATH_BLUE=/etc/relaygate/job-map.blue.json, RELAYGATE_JOB_MAP_PATH_GREEN=/etc/relaygate/job-map.green.json, RELAYGATE_CREDENTIAL_DIR=/etc/relaygate/credentials が設定されている
    And blue のジョブマップは job_map_version="v1.4.0", slot_type="blue" で job_id "daily-settlement" が host=blue-host-01, impl_version=blue-2.3.1, fixed_args=["--mode","batch"], credential_ref=cred-blue-batch, hang_detect_limit_minutes=30 に解決できる
    And green のジョブマップは job_map_version="v1.4.0", slot_type="green" で job_id "daily-settlement" が host=green-host-01, impl_version=green-0.9.0, credential_ref=cred-green-batch, hang_detect_limit_minutes=45 に解決できる

  Scenario: 排他制約を満たすfeature flag設定でrun共通・slot別実行設定を確定する
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を返すよう固定されている
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 0 で終了する
    And execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", hang_detect_limit_minutes=45 の1行がINSERTされる
    And slot_execution_specs に slot_type="blue" と slot_type="green" の2行が job_map_version="v1.4.0" でINSERTされる
    And runner_results に status="STARTING" の2行と、runner_result_events に event_name="attempt_started" の2行が同一transactionでINSERTされる
    And audit_logs に event_name="slot_launch_accepted" と event_name="slot_launch_attempted" の起動前監査イベントがINSERTされる

  Scenario: BLUE_MODEとGREEN_MODEが同時にforegroundでバリデーションエラーになる
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=foreground, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 2 で終了する
    And execution_specs・slot_execution_specs へのINSERTは発生しない

  Scenario: ジョブマップの必須フィールド欠落でバリデーションエラーになる
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And green のジョブマップの jobs."daily-settlement" に host が定義されていない
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 2 で終了する
    And 標準エラーに "ジョブマップの必須フィールドが欠落しています: slot_type=green path=/etc/relaygate/job-map.green.json field=jobs.daily-settlement.host" が出力される
    And execution_specs・slot_execution_specs・runner_results・audit_logs へのINSERTは発生しない

  Scenario: 起動前監査の追記失敗で外部slotを起動しない
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And audit_logs へのINSERTが失敗する状態になっている
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 1 で終了する
    And execution_specs・slot_execution_specs・runner_results・runner_result_events へのINSERTはrollbackされ残らない
    And 外部slotへの起動イベントは送出されない

  Scenario: 起動イベント送出失敗をFAILEDへ補償記録し監査イベントを追記する
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And attempt_id発番が green="att-green-0001" を返すよう固定されている
    And green実装ホスト green-host-01 へのSSH接続が失敗する状態である
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 1 で終了する
    And runner_results の green/background/att-green-0001 行が status="FAILED" へ更新され、runner_result_events に event_name="attempt_failed" の履歴が同一transactionでINSERTされる
    And audit_logs に (slot="green", attempt_id="att-green-0001", event_name="slot_launch_failed", outcome="failed", error_code="launch_event_send_failed") がINSERTされる
    And 標準出力には選択slotごとの status=STARTING 行が出力される

  Scenario: 起動イベント送出timeoutをUNKNOWNへ補償記録し推測でFAILEDにしない
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And attempt_id発番が blue="att-blue-0001" を返すよう固定されている
    And blue実装ホスト blue-host-01 へのSSH起動イベント送出がtimeoutする状態である
    When `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 124 で終了する
    And runner_results の blue/foreground/att-blue-0001 行が status="UNKNOWN" へ更新され、runner_result_events に event_name="attempt_unknown" の履歴が同一transactionでINSERTされる
    And audit_logs に (slot="blue", attempt_id="att-blue-0001", event_name="slot_launch_timeout", outcome="timeout", error_code="launch_event_send_timeout") がINSERTされる

  Scenario: 追加引数をJSON配列で保存し要素順のままargvへ復元する
    Given 環境変数 BLUE_MODE=foreground, GREEN_MODE=off, RAPID_CROSSCHECK_MODE=off, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    When 追加引数 `--note` と `a b "c"`（空白と二重引用符を含む1要素）を渡して `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then execution_specs の additional_args にJSON配列 ["--note","a b \"c\""] が保存される
    And blue実装への起動イベントのargvは fixed_args の要素に additional_args の要素を後置連結した ["--mode","batch","--note","a b \"c\""] である
```
