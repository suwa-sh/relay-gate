# 対話確認のうえblue background実行をABORTEDへ遷移させる - tier-facade仕様

## 変更概要

中止依頼済みのblue background実行について、対話確認プロンプト（y/n二択）を経て明示的にABORTEDへ状態遷移させるCLIコマンドを追加する。操作は監査ログとして記録する。

## CLI コマンド仕様

### relaygate abort blue confirm

- **呼び出し形式**: `relaygate abort blue confirm --run-id <run_id> [--yes]`
- **引数**:
  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --run-id | string | Yes | ABORTEDへ遷移させる対象run_id（中止依頼済みであること） |
  | --yes | flag | No（非TTY環境では必須） | 対話確認プロンプトをスキップせず、非TTY実行時に明示同意を表すフラグ |
- **環境変数**:
  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | RDB（ジョブキュー兼管理DB）接続文字列 |
  | RELAYGATE_SSH_KEY_PATH | Yes | blue実装ホストへのSSH接続鍵パス |
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

### runner_results（snapshot）

起動試行は (run_id, slot_type, role_type, attempt_id) で一意に識別する（複合主キー）。

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | VARCHAR | RUNNING → ABORTED へ更新（runner_result_eventsへの履歴INSERTと同一transactionでUPSERT） | 変更 |

### runner_result_events（履歴）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| event_name / status | VARCHAR | event_name='attempt_aborted'、status='ABORTED' をappend-onlyでINSERTする。runner_resultsのUPSERTと同一transaction（LR-002。片方だけのcommitを許容しない） | 追加（本UCでINSERT） |

### audit_logs（監査イベント。audit-event-contract.yamlが正本）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| event_id | UUID | 監査イベントの一意識別子（PK） | 追加 |
| event_name | VARCHAR | 'abort_confirmed' | 追加 |
| actor | VARCHAR | 操作主体（RELAYGATE_OPERATOR環境変数の値） | 追加 |
| operation | VARCHAR | 'abort' | 追加 |
| outcome | VARCHAR | 'succeeded'（y応答で遷移完了）/ 'rejected'（y以外の回答による中断） | 追加 |
| slot / attempt_id | VARCHAR | 'blue' / 対象起動試行のattempt_id（冪等キー (run_id, slot, attempt_id, event_name) の構成要素。非該当時は '-' を格納しNULLとしない） | 追加 |
| occurred_at | DATETIME | イベント発生時刻 | 追加 |
| previous_hash / event_hash | VARCHAR | run_id単位のhash-chain。audit_chain_headsのrun_id行を排他ロック（SELECT ... FOR UPDATE）してprevious_hashを確定し、INSERTとaudit_chain_heads更新を同一transactionで行う | 追加 |

## ビジネスルール

- 対話確認（対象・影響範囲・取消不可の明示）により実プロセスの停止を確認したうえで、blue background slot実行状態を明示的にABORTEDへ遷移させる。ABORTEDへの遷移は対話確認を経た場合のみ許可される
- TTY接続時は対象・影響範囲・取消不可の明示とy/nの二択を標準出力/標準入力で提示する。非TTY（バッチ実行）時は対話確認をスキップせず、`--yes` 相当のフラグ未指定であればエラー終了する
- 中止依頼済み（UC「blue background実行の中止を依頼する」完了済み）でない対象への直接遷移は許可しない
- ABORTEDへの遷移は本UCの対話確認による明示的操作でのみ発生する。hang-detector等のシステム自動処理はABORTEDへ遷移させない（SPEC-006-04）
- 状態遷移の永続化は runner_result_events への履歴INSERT（attempt_aborted）と runner_results のsnapshot UPSERTを同一transactionで実行し、片方だけがcommitされる状態を許容しない（LR-002）
- 本操作は監査イベント event_name=abort_confirmed（operation=abort、outcome=succeeded|rejected、actor=RELAYGATE_OPERATORの値）として audit_logs へ追記する。y以外の回答による中断は outcome=rejected で記録する。追記時は audit_chain_heads の対象run_id行を排他ロックしてhash-chainを直列化する
- 監査イベントには認証情報・起動引数の実値・stdout/stderr本文を含めない
- CLI応答は10秒以内（CTP-009）

## CLI 出力/画面表示マッピング（design-event.yaml 参照）

### blue background中止確認画面

- **route**: /cli/abort/blue/confirm
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
  - **バリデーション**: run_id必須、対象が中止依頼済み（かつstatus=RUNNING）であることをCLI引数解析後に検証
  - **ローディング**: CLI応答10秒以内
  - **エラーハンドリング**: n応答・非TTY未同意は終了コード1/2で明確に区別し、いずれも状態変更は発生させない。中止確認画面への直接遷移（対話確認スキップ）は許可しない

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「二段階中止確認パターン（依頼→対話確認）」のうち②対話確認画面を適用する。前段①中止依頼画面（UC「blue background実行の中止を依頼する」）を経由していない対象への直接遷移は許可しない。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| AbortConfirmDialog | `@/components/domain/AbortConfirmDialog` | runId={run_id}, impactScope={影響範囲（blue background実行の停止）}, irreversible=true, onConfirm={y/n二択、プロセス内で一度だけ評価} |
| Banner | `@/components/ui/Banner` | variant="success" \| "error"（遷移完了/エラーの表示） |

## ティア完了条件（BDD）

```gherkin
Feature: 対話確認のうえblue background実行をABORTEDへ遷移させる - tier-facade

  Scenario: 対話確認y応答でABORTEDへ状態遷移し監査イベントを記録する
    Given execution_specs に run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の行と slot_execution_specs の (run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type "blue") の行が存在する
    And runner_results に (run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type "blue", role_type "background", attempt_id "att-blue-0001")、status "RUNNING" の起動試行が中止依頼済みで存在する
    And 環境変数 RELAYGATE_OPERATOR が "ops-tanaka" に設定されている
    When `relaygate abort blue confirm --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行し対話確認で "y" と応答する
    Then 終了コード 0 で終了する
    And runner_result_events に event_name "attempt_aborted" の履歴が追加され、同一transactionで runner_results の status が "ABORTED" に更新される
    And audit_logs に event_name "abort_confirmed"、operation "abort"、outcome "succeeded"、actor "ops-tanaka" のレコードが1件追加される

  Scenario: 対話確認n応答で状態変更を行わない
    Given execution_specs に run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の行と slot_execution_specs の (run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type "blue") の行が存在する
    And runner_results に (run_id "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type "blue", role_type "background", attempt_id "att-blue-0001")、status "RUNNING" の起動試行が中止依頼済みで存在する
    When `relaygate abort blue confirm --run-id 3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57` を実行し対話確認で "n" と応答する
    Then 終了コード 1 で終了する
    And runner_results の status は "RUNNING" のまま変化しない
    And audit_logs に event_name "abort_confirmed"、outcome "rejected" のレコードが1件追加される
```
