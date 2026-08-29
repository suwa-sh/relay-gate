# 再実行対象のbackground実行・速報比較依頼を選択する - tier-worker仕様

## 変更概要

終了状態（SUCCEEDED/FAILED/ABORTED）の速報比較依頼（E-003, AG-003）から再実行対象を一覧提示するCLIコマンドをtier-workerに追加する。速報比較依頼はparent_run_idによりリラン系譜を保持するため、候補一覧にparent_run_idを含める。本UCは状態遷移を発生させない読み取り専用の候補選定機能である。

## CLI コマンド仕様

### rerun select（--target rapid-crosscheck）

- **呼び出し形式**: `relaygate rerun select --target rapid-crosscheck [--status SUCCEEDED|FAILED|ABORTED]`
- **引数**:

  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --target | string(enum: background\|rapid-crosscheck) | Yes | リラン対象種別。dispatch先のtierを決定する。workerはrapid-crosscheck指定時のみ処理する |
  | --status | string(enum: SUCCEEDED\|FAILED\|ABORTED) | No | 候補を絞り込む状態。未指定時はSUCCEEDED/FAILED/ABORTEDすべてを候補とする。UNKNOWNは指定できない（速報比較依頼状態にUNKNOWNは存在しない） |

  --slot は --target background 専用であり、rapid-crosscheckで指定した場合はバリデーションエラー（exit 2）とする。

- **環境変数**（cli-command-contract.yaml の dispatch[target=rapid-crosscheck].env_vars に従う）:

  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | rapid_crosscheck_requestsへ接続するRDB接続文字列 |

- **標準入力**: なし
- **標準出力契約**: 候補一覧を1候補1行で出力する（run_id/parent_run_id/job_id/status/requested_at）。候補0件の場合は「該当するリラン候補はありません」を出力する
- **標準エラー契約**: --target未指定、不正なenum値の場合、および--slotをrapid-crosscheckに指定した場合に原因と次アクションを1文ずつ出力する
- **終了コード**:

  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（候補0件を含む） |
  | 1 | 業務エラー（RDB接続失敗） |
  | 2 | バリデーションエラー（--target未指定、--statusの不正なenum値、rapid-crosscheckで--slot指定） |
  | 124 | タイムアウト（RDB接続タイムアウト） |
  | 130 | SIGINT中断 |

## データモデル変更

### rapid_crosscheck_requests（参照のみ、変更なし）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | uuid | 速報比較依頼の識別子（PK） | 変更なし（SELECT対象） |
| parent_run_id | uuid | リラン元依頼のrun_id（通常作成時はNULL） | 変更なし（SELECT対象。系譜表示に使用） |
| job_id | string | 対象のJOB_ID | 変更なし（SELECT対象） |
| requested_at | datetime | 依頼日時 | 変更なし（SELECT対象） |
| status | string | REQUESTED/CLAIMED/RUNNING/SUCCEEDED/FAILED/ABORTED | 変更なし（SELECT条件: SUCCEEDED/FAILED/ABORTEDのみ） |

## ビジネスルール

- 候補として提示するのはstatusがSUCCEEDED、FAILED、ABORTEDのいずれかの速報比較依頼に限定する。REQUESTED/CLAIMED/RUNNING状態（処理中または処理待ち）は二重起動防止のため候補から除外する（RDBのlease/claim状態遷移の整合性を保証する）
- 速報比較依頼状態にUNKNOWNは存在しないため、--status UNKNOWNの指定はバリデーションエラー（exit 2）とする
- 本UCは読み取り専用であり、速報比較依頼の状態を変更しない
- 選定した候補のrun_idは、後続UC「execution-spec.jsonの実行設定を保ったまま再実行する」の`--run-id`引数への入力として利用する（後続UCは新しいrun_idの速報比較依頼を新規作成し、元依頼のレコード・状態・履歴は変更しない）

## CLI 出力/画面表示マッピング

design-event.yaml の「リラン対象選定画面」（route: `/cli/rerun/select`）に対応する。

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 速報比較依頼候補一覧 | テーブル（stdout相当） | CrossCheckRequestRow（variant: rapid） | run_id・parent_run_id・job_id・状態バッジ・依頼日時を一覧表示する（フィルタでSUCCEEDED/FAILED/ABORTEDが選択しやすいようにする） |

デザイントークン参照: StatusBadgeは`var(--component-status-badge-succeeded)`（green）、`var(--component-status-badge-failed)`（red）、`var(--component-status-badge-aborted)`（gray）を候補一覧の状態表示に使用する。

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「状態一覧+フィルターパターン」に該当する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| CrossCheckRequestRow（variant: rapid） | `src/components/domain/CrossCheckRequestRow.tsx` | runId=run_id, jobIdOrTargetDate=job_id, state=status（SUCCEEDED/FAILED/ABORTED）。`--status`オプションによる絞り込みに対応（leaseExpiry/workerIdは終了状態のため非表示） |

状態管理はステートレス（CLI実行のたびにRDBから最新値を都度取得、クライアント側キャッシュ・楽観更新は行わない）。選定結果のrun_idは後続UC「execution-spec.jsonの実行設定を保ったまま再実行する」のCrossCheckRequestRowへ引き継ぐ。

## ティア完了条件（BDD）

```gherkin
Feature: 再実行対象のbackground実行・速報比較依頼を選択する - tier-worker

  Scenario: rerun_select_処理中の依頼を除外し終了状態の速報比較依頼のみを候補として提示すること
    # Arrange
    Given execution_specsテーブルにrun_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement"の行が存在する
    And rapid_crosscheck_requestsテーブルにrun_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", parent_run_id=NULL, job_id="daily-settlement", blue_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", blue_attempt_id="att-blue-0001", green_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", green_attempt_id="att-green-0001", status="ABORTED"の行が存在する
    And rapid_crosscheck_requestsテーブルにrun_id="d92b6f13-4a08-4c57-91e6-2f8a5d3c7b60", parent_run_id=NULL, job_id="daily-settlement", blue_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", blue_attempt_id="att-blue-0001", green_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", green_attempt_id="att-green-0001", status="CLAIMED"の行が存在する
    # Act
    When relaygate rerun select --target rapid-crosscheck を実行する
    # Assert
    Then 標準出力の候補一覧に run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af" が含まれ、run_id="d92b6f13-4a08-4c57-91e6-2f8a5d3c7b60" は含まれない
    And 終了コード0で終了する
```
