# execution-spec.jsonの実行設定を保ったまま再実行する - tier-facade仕様

## 変更概要

終了状態（SUCCEEDED/FAILED/UNKNOWN/ABORTED）のbackground実行（Runner実行結果, E-002）について、元のrun共通execution spec（execution_specs, E-001, AG-001）とslot別実行設定（slot_execution_specs, E-007）を復元し、**新しいrun_id（parent_run_id=元run_id）の新規runとして**再実行するCLIコマンドをtier-facadeに追加する。元runのレコード・状態・履歴は一切変更しない。実行設定の複製、リラン起動トランザクション（起動前監査ゲートを含む）、blue/green実装へのSSH起動指示を担う。

## CLI コマンド仕様

### rerun run（--target background）

- **呼び出し形式**: `relaygate rerun run --target background --run-id <元run_id>`
- **引数**:

  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --target | string(enum: background\|rapid-crosscheck) | Yes | リラン対象種別。dispatch先のtierを決定する。facadeはbackground指定時のみ処理する |
  | --run-id | string | Yes | リラン元となる完了済み・中止済みのbackground実行のrun_id（「再実行対象のbackground実行・速報比較依頼を選択する」UCで選定） |

- **環境変数**（cli-command-contract.yaml の dispatch[target=background].env_vars に従う）:

  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | execution_specs / slot_execution_specs / runner_result_events / runner_results / audit_logs / audit_chain_headsへ接続するRDB接続文字列 |
  | RELAYGATE_OPERATOR | Yes | 監査イベントのactorへ記録する操作者識別子 |
  | RELAYGATE_CREDENTIAL_DIR | Yes | 認証情報ディレクトリ。slot_execution_specs.credential_ref から SSH 秘密鍵を解決する（cli-command-contract.yaml credential_resolution） |
  | RELAYGATE_SSH_KEY_PATH | No | credential_ref が null のときに用いる既定の SSH 秘密鍵パス |

- **標準入力**: なし
- **標準出力契約**: 再実行受理時のみ、新規run_id・parent_run_id・slot_type・attempt_id・attempt_no・status=STARTINGを1行で出力する
- **標準エラー契約**: 対象run_id未存在、元のslot modeがforegroundまたはoff、対象がSTARTING/RUNNING中、起動前監査の追記失敗、SSH起動失敗の場合に原因と次アクションを1文ずつ出力する
- **終了コード**:

  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（新規run_idでの再実行を開始） |
  | 1 | 業務エラー（元のexecution spec未存在、元のslot modeがforeground/off、対象がSTARTING/RUNNING中、起動前監査の追記失敗による起動中止、SSH起動失敗） |
  | 2 | バリデーションエラー（--target未指定、--run-id未指定、--run-idがUUID形式でない） |
  | 124 | タイムアウト（SSH起動タイムアウト。起動試行はUNKNOWNとして記録し推測でFAILEDを確定しない） |
  | 130 | SIGINT中断 |

## データモデル変更

### execution_specs（run共通execution spec）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | uuid | 新規発行するrun_id（PK） | 追加（INSERT） |
| parent_run_id | uuid | リラン元のrun_id | 追加（INSERT、元run_idを設定） |
| job_id | string | JOB_ID | 追加（元の値を複製） |
| additional_args | text | run共通の追加引数 | 追加（元の値を複製） |
| hang_detect_limit_minutes | integer | ハング検知しきい値（分。run共通の1値） | 追加（元の値を複製） |

### slot_execution_specs（slot別実行設定）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | uuid | 新規run_id（PK構成要素） | 追加（INSERT） |
| slot_type | string | 元のslot別実行設定から引き継ぐslot種別（blue/green、PK構成要素） | 追加（INSERT） |
| host | string | 実行ホスト | 追加（元の値を複製） |
| exec_user | string | 実行ユーザー | 追加（元の値を複製） |
| script_path | string | スクリプトパス | 追加（元の値を複製） |
| work_dir | string | 作業ディレクトリ | 追加（元の値を複製） |
| fixed_args | text | slot固有の固定引数 | 追加（元の値を複製） |
| impl_version | string | 実装版 | 追加（元の値を複製） |
| credential_ref | string | 認証情報参照名（実値は保存しない） | 追加（元の値を複製。実値は複製しない） |
| job_map_version | string | その slot のジョブマップ版 | 追加（元の値を複製） |

### runner_result_events（履歴、append-only）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| event_id | uuid | 履歴イベントID（PK） | 追加（INSERT） |
| run_id / slot_type / role_type / attempt_id | uuid / string / string / string | 起動試行identity。role_type='background'固定 | 追加（INSERT） |
| attempt_no | integer | 同一(run_id, slot_type, role_type)内の連番（新規runの初回試行=1） | 追加（INSERT） |
| event_name | string | 'attempt_started'固定 | 追加（INSERT） |
| status | string | 'STARTING'固定 | 追加（INSERT） |
| occurred_at | datetime | イベント発生時刻 | 追加（INSERT） |

### runner_results（snapshot）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id / slot_type / role_type / attempt_id | uuid / string / string / string | 起動試行identity（複合PK）。role_type='background'固定 | 追加（INSERT） |
| attempt_no | integer | 起動試行連番（新規runの初回試行=1） | 追加（INSERT） |
| accepted_at | datetime | 起動受付時刻（STARTING遷移時点） | 追加（INSERT） |
| status | string | 'STARTING'固定（プロセス起動確認後にRUNNINGへ遷移） | 追加（INSERT。runner_result_eventsと同一transactionでUPSERT） |
| updated_at | datetime | snapshot更新時刻（runner_result_events.occurred_atと一致） | 追加（INSERT） |

### audit_logs（追記専用）

audit-event-contract.yaml のフィールド定義（actor / operation / outcome へ統一）に従う。

| イベント | operation | outcome | slot | attempt_id | タイミング |
|---------|-----------|---------|------|-----------|-----------|
| rerun_requested | rerun | accepted \| rejected | '-' | '-' | リラン受付時（起動前。同一transaction） |
| slot_launch_attempted | slot_launch | accepted | 対象slot | 新attempt_id | 外部slot起動前（同一transaction） |
| rerun_accepted | rerun | succeeded \| failed | 対象slot | 新attempt_id | リラン起動後 |

run_idには**新規発行したrun_id**、parent_run_idには元run_idを格納する。冪等キーは(run_id, slot, attempt_id, event_name)。認証情報・起動引数の実値・stdout/stderr本文は含めない。

### audit_chain_heads

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | uuid | ハッシュチェーン直列化対象の新規run_id（PK） | 追加（SELECT ... FOR UPDATE → INSERT/UPDATE） |
| head_event_id / head_hash / chain_length / updated_at | uuid / string / integer / datetime | チェーン先頭の更新 | 変更（audit_logs INSERTと同一transaction） |

## ビジネスルール

- 元のrun共通execution spec（job_id/additional_args/hang_detect_limit_minutes）とslot別実行設定（host/exec_user/script_path/work_dir/fixed_args/impl_version/credential_ref/job_map_version）を一切変更せず新規run_idへ複製する。リランはジョブマップ（RELAYGATE_JOB_MAP_PATH_BLUE / _GREEN）を読まない（「実行設定を保ったまま再実行する」というUC名の制約）。認証情報は参照名のみを複製し、実値は取り扱わない
- **新規run_idを発行し新規runとして実行する。元runのレコード・状態・履歴は一切変更しない**。新runのparent_run_idに元run_idを設定し、複数回リランでは各新規実行のparent_run_idに直前のリラン元run_idを設定する。最新run_idからparent_run_idをたどって元の実行まで数珠つなぎに追跡できる（CTP-004実行系譜トレーサビリティ）
- リラン不可条件: (1)対象の起動試行がSTARTING/RUNNING中、(2)元のslot modeがforegroundまたはoff、(3)未対応role（background以外）、(4)元の実行が見つからない場合は、リランせずエラー終了（exit 1）する
- リラン起動では、execution_specs / slot_execution_specs のINSERT、runner_result_events + runner_results のSTARTING記録、起動前監査イベント（slot_launch_attempted / rerun_requested）のaudit_logs INSERTとaudit_chain_heads更新を、**すべて同一transactionでcommitしてから**外部slotを起動する。commitできない場合は起動しない（起動前監査ゲート、rdb-schema.yaml transaction_rules「slot起動トランザクション」）
- 監査イベントの追記は、対象run_idのaudit_chain_heads行を排他ロック（SELECT ... FOR UPDATE）してprevious_hashを確定してからaudit_logsへINSERTし、同一transactionでaudit_chain_headsを更新する（hash-chain lock契約。run_id単位でチェーンの分岐・欠損を防ぐ）
- runner_result_eventsの(run_id, slot_type, role_type, attempt_id, event_name)一意制約とaudit_logsの(run_id, slot, attempt_id, event_name)一意制約により、クラッシュ後の再試行を冪等化する（CTP-006冪等性方針）
- SSH秘密鍵は複製したslot_execution_specs.credential_refからcli-command-contract.yaml credential_resolution（`RELAYGATE_CREDENTIAL_DIR/{credential_ref}`、nullなら`RELAYGATE_SSH_KEY_PATH`）で解決する。鍵の実値はRDB・監査・標準出力・標準エラー・起動イベントに出さない
- 起動引数はslot_execution_specs.fixed_args（JSON配列）の要素の後ろにexecution_specs.additional_args（JSON配列）の要素を順序を変えず後置連結したargvとする（rdb-schema.yaml argument_serialization。要素の再分割・再結合・クォート付与をしない）

## CLI 出力/画面表示マッピング

design-event.yaml の「リラン実行画面」（route: `/cli/rerun/run`）に対応する。

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 元の実行設定確認表示 | カード（stdout相当） | ExecutionSpecCard | 実行前に元のrun共通execution spec + slot別実行設定の内容（run_id/job_id/host/script/mapVersion/implVersion/hangDetectLimitMinutes/credentialRef）を確認表示し、設定の意図しない変化がないことを保証する |
| 再実行開始結果表示 | パネル（stdout相当） | RunnerResultPanel（variant: background） | 新規run_id・parent_run_id・attempt_id・attempt_no・status=STARTINGを表示する |

デザイントークン参照: ExecutionSpecCardのcredentialRefは参照名のみを表示するpropとし、実値表示用のpropを設けない（nfr_decisions記載のセキュリティ方針に準拠）。

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「状態一覧+フィルターパターン」「実行結果ターミナル表示パターン」に該当する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| ExecutionSpecCard | `src/components/domain/ExecutionSpecCard.tsx` | run_id=run_id, job_id=job_id, host=host, script=script_path, mapVersion=slot_execution_specs.job_map_version, implVersion=impl_version, hangDetectLimitMinutes=hang_detect_limit_minutes, credentialRef=credential_ref（参照名のみ表示。実値表示用propは設けない） |
| RunnerResultPanel（variant: background） | `src/components/domain/RunnerResultPanel.tsx` | runId=新規run_id, slot=slot_type, role="background", attemptId=attempt_id, attemptNo=attempt_no, acceptedAt=accepted_at, status=STARTING（起動受付直後のためstdout/stderr/exitCodeは未確定） |

ExecutionSpecCardのcredentialRefはnfr_decisions記載のセキュリティ方針に準拠し参照名のみを表示する（デザイントークン参照節と同一の制約）。

## ティア完了条件（BDD）

```gherkin
Feature: execution-spec.jsonの実行設定を保ったまま再実行する - tier-facade

  Scenario: rerun_run_facadeが元の実行設定を保ったまま新規run_idでbackground roleを再起動すること
    # Arrange
    Given execution_specsテーブルにrun_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", parent_run_id=NULL, job_id="daily-settlement", hang_detect_limit_minutes=30の行が存在する
    And slot_execution_specsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue"), host="blue-host-01", exec_user="batchuser", script_path="/opt/blue/run.sh", work_dir="/opt/relaygate/work", impl_version="blue-2.3.1", job_map_version="v1.4.0"の行が存在する
    And runner_resultsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="background", attempt_id="att-blue-0001"), attempt_no=1, status="FAILED"の行が存在する
    # Act
    When 環境変数RELAYGATE_OPERATOR="ops-tanaka"の下で relaygate rerun run --target background --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57 を実行する
    # Assert
    Then execution_specsテーブルに新規run_id（parent_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"）でjob_id="daily-settlement", hang_detect_limit_minutes=30の行が追加される
    And slot_execution_specsテーブルに新規run_idのslot_type="blue"でhost="blue-host-01", script_path="/opt/blue/run.sh", impl_version="blue-2.3.1", job_map_version="v1.4.0"の行が追加される
    And runner_result_eventsテーブルに新規run_idのevent_name="attempt_started", status="STARTING", attempt_no=1の行が追加され、runner_resultsテーブルに新規run_idのrole_type="background", attempt_no=1, status="STARTING", accepted_atが設定された行が同一transactionで追加される
    And 元のrun_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"の行はいずれのテーブルでも変更されない
    And audit_logsテーブルにevent_name="rerun_requested"（operation="rerun", outcome="accepted", actor="ops-tanaka", slot="-", attempt_id="-"）とevent_name="slot_launch_attempted"（operation="slot_launch", outcome="accepted", slot="blue"）の行が追加され、audit_chain_headsの新規run_id行が更新される
    And 終了コード0で終了する

  Scenario: rerun_run_STARTING中の対象を指定した場合_リランせずエラー終了すること
    # Arrange
    Given execution_specsテーブルにrun_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement"の行とslot_execution_specsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue")の行が存在する
    And runner_resultsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="background", attempt_id="att-blue-0001"), attempt_no=1, status="STARTING"の行が存在する
    # Act & Assert
    When relaygate rerun run --target background --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57 を実行すると、標準エラーに "リランできません run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57 status=STARTING（STARTING/RUNNING中はリランできません）" が出力され終了コード1で終了する
```
