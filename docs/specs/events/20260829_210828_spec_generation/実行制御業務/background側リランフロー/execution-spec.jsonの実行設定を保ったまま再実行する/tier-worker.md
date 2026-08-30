# execution-spec.jsonの実行設定を保ったまま再実行する - tier-worker仕様

## 変更概要

終了状態（SUCCEEDED/FAILED/ABORTED）の速報比較依頼（E-003, AG-003）について、業務ジョブを再実行せず、**新しいrun_idの速報比較依頼をREQUESTED状態で新規作成**し、parent_run_idで元依頼へ関連付けるCLIコマンドをtier-workerに追加する。**元依頼のレコード・状態・履歴は一切変更しない**。作成後は通常の速報クロスチェックフローと同様にworkerがlease/claim機構で新規依頼をクレームし処理する。

## CLI コマンド仕様

### rerun run（--target rapid-crosscheck）

- **呼び出し形式**: `relaygate rerun run --target rapid-crosscheck --run-id <元依頼run_id>`
- **引数**:

  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --target | string(enum: background\|rapid-crosscheck) | Yes | リラン対象種別。dispatch先のtierを決定する。workerはrapid-crosscheck指定時のみ処理する |
  | --run-id | string | Yes | リラン元となる完了済み・中止済みの速報比較依頼のrun_id（「再実行対象のbackground実行・速報比較依頼を選択する」UCで選定） |

- **環境変数**（cli-command-contract.yaml の dispatch[target=rapid-crosscheck].env_vars に従う。認証情報ディレクトリ・SSH鍵は参照しない）:

  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | rapid_crosscheck_requests / audit_logs / audit_chain_headsへ接続するRDB接続文字列 |
  | RELAYGATE_OPERATOR | Yes | 監査イベントのactorへ記録する操作者識別子 |

- **標準入力**: なし
- **標準出力契約**: 新規作成完了時のみ、新規run_id・parent_run_id・job_id・status=REQUESTEDを1行で出力する
- **標準エラー契約**: 対象未存在、対象がREQUESTED/CLAIMED/RUNNING中、監査イベントの追記失敗の場合に原因と次アクションを1文ずつ出力する
- **終了コード**:

  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（新規run_idの速報比較依頼を作成） |
  | 1 | 業務エラー（対象未存在、対象がREQUESTED/CLAIMED/RUNNING中、監査イベントの追記失敗による作成中止） |
  | 2 | バリデーションエラー（--target未指定、--run-id未指定、--run-idがUUID形式でない） |
  | 124 | タイムアウト（RDB接続タイムアウト） |
  | 130 | SIGINT中断 |

## データモデル変更

### rapid_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | uuid | 新規発行するrun_id（PK） | 追加（INSERT） |
| parent_run_id | uuid | リラン元依頼のrun_id | 追加（INSERT、元依頼run_idを設定） |
| job_id | string | 対象ジョブのjob_id | 追加（元依頼から複製） |
| blue_run_id / blue_attempt_id | uuid / string | 比較対象のblue slot側background起動試行 | 追加（元依頼から複製） |
| green_run_id / green_attempt_id | uuid / string | 比較対象のgreen slot側background起動試行 | 追加（元依頼から複製） |
| comparison_definition_valid_from | datetime | 適用する比較定義世代のvalid_from | 追加（元依頼から複製。適用世代を変更前のまま保持する） |
| requested_at | datetime | 新規依頼の作成日時 | 追加（INSERT） |
| status | string | 'REQUESTED'固定 | 追加（INSERT） |

元依頼の行は参照（SELECT）のみで、UPDATE/DELETEは行わない。

### audit_logs（追記専用）

audit-event-contract.yaml のフィールド定義（actor / operation / outcome へ統一）に従う。

| イベント | operation | outcome | slot | attempt_id | タイミング |
|---------|-----------|---------|------|-----------|-----------|
| rerun_requested | rerun | accepted \| rejected | '-' | '-' | リラン受付時 |
| rerun_accepted | rerun | succeeded \| failed | '-' | '-' | 新規依頼作成後 |

run_idには**新規発行したrun_id**、parent_run_idには元依頼run_idを格納する。冪等キーは(run_id, slot, attempt_id, event_name)。非該当のslot / attempt_idはNULLではなく '-' を格納する。

### audit_chain_heads

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | uuid | ハッシュチェーン直列化対象の新規run_id（PK） | 追加（SELECT ... FOR UPDATE → INSERT/UPDATE） |
| head_event_id / head_hash / chain_length / updated_at | uuid / string / integer / datetime | チェーン先頭の更新 | 変更（audit_logs INSERTと同一transaction） |

## ビジネスルール

- リランは元依頼のstatusがSUCCEEDED、FAILED、ABORTEDのいずれかの場合のみ許可する。REQUESTED/CLAIMED/RUNNING中の対象は業務エラー（exit 1）として拒否する（重複起動防止。RDBのlease/claim状態遷移の整合性保証）
- **業務ジョブは再実行しない**。新しいrun_idの速報比較依頼をREQUESTED状態で新規作成し、parent_run_idで元依頼へ関連付ける。**元依頼のレコード・状態・履歴は一切変更しない**（「同一run_idのままREQUESTEDへ差し戻す」処理は行わない）
- 比較対象は元依頼のblue_run_id / blue_attempt_id / green_run_id / green_attempt_id の4項目とcomparison_definition_valid_from（適用比較定義世代）を複製して特定する。重複防止は(job_id, blue_run_id, blue_attempt_id, green_run_id, green_attempt_id)のユニーク制約ではなく新run_id発行により回避される（同一の比較対象試行ペアへの重複「作成」はCronJob側のユニーク制約が防ぎ、リランの新規依頼は別run_idの明示操作として許容される）
- 複数回リランでは、各新規依頼のparent_run_idに直前のリラン元run_idを設定し、最新run_idからparent_run_idをたどって元依頼まで数珠つなぎに追跡できる（CTP-004実行系譜トレーサビリティ）
- 監査イベント（rerun_requested / rerun_accepted）は、新規run_idのaudit_chain_heads行を排他ロック（SELECT ... FOR UPDATE）してprevious_hashを確定したうえでaudit_logsへINSERTし、同一transactionでaudit_chain_headsを更新する（hash-chain lock契約）。新規依頼のINSERTと監査イベントの追記は同一transactionでcommitし、commitできない場合は依頼を作成しない

## CLI 出力/画面表示マッピング

design-event.yaml の「リラン実行画面」（route: `/cli/rerun/run`）に対応する。

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 新規速報比較依頼の作成結果表示 | パネル（stdout相当） | CrossCheckRequestRow（variant: rapid） | 新規run_id・parent_run_id（元依頼）・job_id・status=REQUESTEDを表示する |

デザイントークン参照: StatusBadgeのREQUESTED表示は`var(--component-status-badge-requested)`（background: var(--color-amber-100), foreground: var(--color-amber-600)）を用いる。

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「状態一覧+フィルターパターン」「実行結果ターミナル表示パターン」に該当する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| CrossCheckRequestRow（variant: rapid） | `src/components/domain/CrossCheckRequestRow.tsx` | runId=新規run_id, jobIdOrTargetDate=job_id, state=status（REQUESTED）。parent_run_id（元依頼）を系譜情報として併記する（leaseExpiry/workerIdは未クレームのため非表示） |

状態バッジのREQUESTED表示は`var(--component-status-badge-requested)`トークンを用いる（CLI 出力/画面表示マッピング節のデザイントークン参照と同一）。

## ティア完了条件（BDD）

```gherkin
Feature: execution-spec.jsonの実行設定を保ったまま再実行する - tier-worker

  Scenario: rerun_run_workerが中止済みの速報比較依頼から新run_idの依頼を新規作成すること
    # Arrange
    Given execution_specsテーブルにrun_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement"の行が存在する
    And rapid_crosscheck_requestsテーブルにrun_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", parent_run_id=NULL, job_id="daily-settlement", blue_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", blue_attempt_id="att-blue-0001", green_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", green_attempt_id="att-green-0001", comparison_definition_valid_from="2026-08-01T00:00:00+09:00", status="ABORTED"の行が存在する
    # Act
    When 環境変数RELAYGATE_OPERATOR="ops-tanaka"の下で relaygate rerun run --target rapid-crosscheck --run-id c41d7e08-2b95-4f36-a8d1-5e7c93b204af を実行する
    # Assert
    Then rapid_crosscheck_requestsテーブルに新規run_id（parent_run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af"）でjob_id="daily-settlement", blue_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", blue_attempt_id="att-blue-0001", green_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", green_attempt_id="att-green-0001", comparison_definition_valid_from="2026-08-01T00:00:00+09:00", status="REQUESTED"の行が追加される
    And run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af"の行はstatus="ABORTED", lease_expires_at, worker_idを含め一切変更されない
    And audit_logsテーブルにevent_name="rerun_requested"（operation="rerun", outcome="accepted"）とevent_name="rerun_accepted"（operation="rerun", outcome="succeeded"）の行がactor="ops-tanaka", slot="-", attempt_id="-", parent_run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af"で追加され、audit_chain_headsの新規run_id行が更新される
    And 終了コード0で終了する

  Scenario: rerun_run_RUNNING中の対象を指定した場合_重複起動防止のため拒否すること
    # Arrange
    Given execution_specsテーブルにrun_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement"の行が存在する
    And rapid_crosscheck_requestsテーブルにrun_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", job_id="daily-settlement", blue_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", blue_attempt_id="att-blue-0001", green_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", green_attempt_id="att-green-0001", status="RUNNING"の行が存在する
    # Act & Assert
    When relaygate rerun run --target rapid-crosscheck --run-id c41d7e08-2b95-4f36-a8d1-5e7c93b204af を実行すると、rapid_crosscheck_requestsテーブルに新規行は追加されず、標準エラーに "リランできません run_id=c41d7e08-2b95-4f36-a8d1-5e7c93b204af status=RUNNING（SUCCEEDED/FAILED/ABORTEDのみリラン可能です）" が出力され終了コード1で終了する
```
