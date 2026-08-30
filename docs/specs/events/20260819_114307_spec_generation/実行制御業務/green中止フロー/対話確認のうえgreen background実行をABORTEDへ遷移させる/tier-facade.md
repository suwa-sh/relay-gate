# 対話確認のうえgreen background実行をABORTEDへ遷移させる - tier-facade仕様

## 変更概要

中止依頼済みのgreen background実行について、対話確認プロンプト（y/n二択）を経て明示的にABORTEDへ状態遷移させるCLIコマンドを追加する。遷移はrunner_result_eventsへの履歴INSERTとrunner_resultsのsnapshot更新を同一transactionで行い（LR-002 Event/Snapshot併用）、操作は監査イベント（abort_confirmed）としてhash-chain lock契約に従い記録する。

## CLI コマンド仕様

### relaygate abort green confirm

- **呼び出し形式**: `relaygate abort green confirm --run-id <run_id> [--yes]`
- **引数**:
  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --run-id | string | Yes | ABORTEDへ遷移させる対象run_id（中止依頼済みであること） |
  | --yes | flag | No（非TTY環境では必須） | 対話確認プロンプトをスキップせず、非TTY実行時に明示同意を表すフラグ |
- **環境変数**:
  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | RDB（ジョブキュー兼管理DB）接続文字列 |
  | RELAYGATE_SSH_KEY_PATH | Yes | green実装ホストへのSSH接続鍵パス |
  | RELAYGATE_OPERATOR | Yes | 監査イベントのactorへ記録する操作者識別子 |
- **標準入力**: TTY接続時、対象run_id・影響範囲・取消不可であることを明示したうえでy/nの二択を受け付ける対話確認プロンプト
- **標準出力契約**: `ABORTED遷移完了: run_id={run_id}` の1行（対話確認でy応答時のみ）
- **標準エラー契約**: n応答時は「中止操作を取り消しました: run_id={run_id}」、非TTY環境で--yes未指定時は「対話確認が必要です。非TTY環境では --yes フラグを指定してください」
- **終了コード**:
  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（y応答、ABORTEDへの遷移完了） |
  | 1 | 業務エラー（n応答による中断、中止依頼未済） |
  | 2 | バリデーションエラー（run_id未指定、非TTY環境で--yes未指定） |

## データモデル変更

### runner_result_events（履歴、append-only）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| event_id | uuid | 履歴イベントID（PK） | 追加（INSERT） |
| run_id / slot_type / role_type / attempt_id | uuid / string / string / string | 対象起動試行のidentity。slot_type='green'、role_type='background' | 追加（INSERT） |
| attempt_no | integer | 対象起動試行のattempt_no | 追加（INSERT） |
| event_name | string | 'attempt_aborted'固定 | 追加（INSERT） |
| status | string | 'ABORTED'固定 | 追加（INSERT） |
| occurred_at | datetime | 遷移時刻 | 追加（INSERT） |

### runner_results（snapshot）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | string | RUNNING/UNKNOWN → ABORTED へ更新（実行状態は6値: STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED） | 変更（UPDATE。WHERE (run_id, slot_type='green', role_type='background', attempt_id)。runner_result_eventsのINSERTと同一transaction） |
| updated_at | datetime | runner_result_events.occurred_atと一致させる | 変更（UPDATE） |

### audit_logs（追記専用）

audit-event-contract.yaml のフィールド定義（actor / operation / outcome へ統一）に従う。イベント種別ごとの独自フィールド名（operator / operated_at / action等）は使わない。

| イベント | operation | outcome | slot | attempt_id | タイミング |
|---------|-----------|---------|------|-----------|-----------|
| abort_confirmed | abort | succeeded \| rejected | 'green' | '-'（起動試行に紐づかない中止イベント） | 対話確認後の状態遷移時（y以外の回答による中断はoutcome=rejectedで記録する） |

冪等キーは(run_id, slot, attempt_id, event_name)。認証情報・起動引数の実値・stdout/stderr本文は含めない。

### audit_chain_heads

audit_logsへの追記時に対象run_id行を排他ロック（SELECT ... FOR UPDATE）してprevious_hashを確定し、audit_logsのINSERTと同一transactionでhead_event_id / head_hash / chain_length / updated_atを更新する（hash-chain lock契約。run_id単位でチェーンの分岐・欠損を防ぐ）。

## ビジネスルール

- 対話確認（対象・影響範囲・取消不可の明示）により実プロセスの停止を確認したうえで、green background slot実行状態を明示的にABORTEDへ遷移させる。ABORTEDへの遷移は対話確認による明示的操作でのみ発生する
- 中止確定の対象はstatusがRUNNINGまたはUNKNOWN（結果不明）のbackground起動試行とする。UNKNOWNからのABORTED確定は対話確認による回復処理としてのみ発生し、UNKNOWNを推測でFAILEDへ確定しない。SUCCEEDED/FAILED/ABORTEDの確定済み状態は対象外とする
- TTY接続時は対象・影響範囲・取消不可の明示とy/nの二択を標準出力/標準入力で提示する。非TTY（バッチ実行）時は対話確認をスキップせず、`--yes` 相当のフラグ未指定であればエラー終了する
- 中止依頼済み（UC「green background実行の中止を依頼する」完了済み）でない対象への直接遷移は許可しない
- runner_result_eventsへの履歴INSERT（attempt_aborted）とrunner_resultsのsnapshot UPDATEは必ず同一transactionで実行する（rdb-schema.yaml transaction_rules「Runner実行結果の履歴・snapshot同時更新」）
- 本操作はevent_name=abort_confirmed（operation=abort、outcome=succeeded/rejected）の監査イベントとして記録する。actorにはRELAYGATE_OPERATORの値を格納する（CTP-005準拠）
- CLI応答は10秒以内（CTP-009）

## CLI 出力/画面表示マッピング（design-event.yaml 参照）

### green background中止確認画面

- **route**: /cli/abort/green/confirm
- **表示要素とコンポーネントマッピング**:
  | 要素 | 種別 | デザインシステムコンポーネント | 説明 |
  |------|------|------------------------------|------|
  | 対話確認ダイアログ | ダイアログ | AbortConfirmDialog | 対象run_id・影響範囲を明示し、y/nの二択のみ許可 |
- **デザイントークン参照**:
  | 用途 | トークン | 値 |
  |------|---------|---|
  | 対話確認境界線 | confirm-prompt.destructive-border | var(--color-red-600) |
  | 対話確認背景 | confirm-prompt.background | var(--color-slate-50) |
- **UIロジック**:
  - **状態管理**: 対話確認結果（y/n）はプロセス内で一度だけ評価し、リトライ・再確認は行わない（誤操作防止のためショートカット確認を設けない）
  - **バリデーション**: run_id必須、対象が中止依頼済み（かつstatus=RUNNINGまたはUNKNOWN）であることをCLI引数解析後に検証
  - **ローディング**: CLI応答10秒以内
  - **エラーハンドリング**: n応答・非TTY未同意は終了コード1/2で明確に区別し、いずれも状態変更は発生させない。中止確認画面への直接遷移（対話確認スキップ）は許可しない

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「二段階中止確認パターン（依頼→対話確認）」のうち②対話確認画面を適用する。前段①中止依頼画面（UC「green background実行の中止を依頼する」）を経由していない対象への直接遷移は許可しない。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| AbortConfirmDialog | `@/components/domain/AbortConfirmDialog` | runId={run_id}, impactScope={影響範囲（green background実行の停止）}, irreversible=true, onConfirm={y/n二択、プロセス内で一度だけ評価} |
| Banner | `@/components/ui/Banner` | variant="success" \| "error"（遷移完了/エラーの表示） |

## ティア完了条件（BDD）

```gherkin
Feature: 対話確認のうえgreen background実行をABORTEDへ遷移させる - tier-facade

  Scenario: abort_green_confirm_対話確認y応答の場合_ABORTEDへ遷移し監査イベントを記録すること
    # Arrange
    Given execution_specsテーブルにrun_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement"の行とslot_execution_specsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green")の行が存在する
    And runner_resultsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001"), attempt_no=1, status="RUNNING"の中止依頼済みの行が存在する
    # Act
    When 環境変数RELAYGATE_OPERATOR="ops-tanaka"の下で `relaygate abort green confirm --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行し対話確認で "y" と応答する
    # Assert
    Then 終了コード 0 で終了する
    And runner_resultsの該当行のstatusが "ABORTED" に更新され、runner_result_eventsにevent_name="attempt_aborted", status="ABORTED"の行が同一transactionで1件追加される
    And audit_logsテーブルにevent_name="abort_confirmed", operation="abort", outcome="succeeded", actor="ops-tanaka", slot="green", attempt_id="-"の行が1件追加され、audit_chain_headsのrun_id行が更新される

  Scenario: abort_green_confirm_対象がUNKNOWNの場合_対話確認yでABORTEDへ確定すること
    # Arrange
    Given execution_specsテーブルにrun_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"の行とslot_execution_specsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green")の行が存在する
    And runner_resultsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001"), attempt_no=1, status="UNKNOWN"の中止依頼済みの行（timeoutにより結果取得不能）が存在する
    # Act
    When 環境変数RELAYGATE_OPERATOR="ops-tanaka"の下で `relaygate abort green confirm --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行し対話確認で "y" と応答する
    # Assert
    Then 終了コード 0 で終了する
    And runner_resultsの該当行のstatusが "UNKNOWN" から "ABORTED" に更新され（推測でFAILEDへは確定しない）、runner_result_eventsにevent_name="attempt_aborted", status="ABORTED"の行が同一transactionで1件追加される
    And audit_logsテーブルにevent_name="abort_confirmed", operation="abort", outcome="succeeded", actor="ops-tanaka", slot="green"の行が1件追加される

  Scenario: abort_green_confirm_対話確認n応答の場合_状態変更を行わないこと
    # Arrange
    Given execution_specsテーブルにrun_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"の行とslot_execution_specsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green")の行が存在する
    And runner_resultsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001"), status="RUNNING"の中止依頼済みの行が存在する
    # Act
    When `relaygate abort green confirm --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行し対話確認で "n" と応答する
    # Assert
    Then 終了コード 1 で終了する
    And runner_resultsの該当行のstatusは "RUNNING" のまま変化しない
    And audit_logsテーブルにevent_name="abort_confirmed", operation="abort", outcome="rejected"の行が1件追加される
```
