# RUNNING中の確報比較依頼の中止を依頼する - tier-worker仕様

## 変更概要

RUNNING中の確報比較依頼（E-005, AG-004）に対する中止依頼を受理するCLIコマンドをtier-workerに追加する。確報クロスチェックは全テーブル・全ファイルを対象とする日次バッチでリリース判断の正本となるため、本UCは状態遷移を発生させず対象の状態検証と監査イベント（abort_requested）の記録のみを行う。実際のABORTEDへの遷移は次UC「対話確認のうえ確報比較依頼をABORTEDへ遷移させる」が担う。

## CLI コマンド仕様

### abort final-crosscheck request

- **呼び出し形式**: `relaygate abort final-crosscheck request --run-id <run_id>`
- **引数**:

  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --run-id | string | Yes | 中止依頼対象の確報比較依頼のrun_id |

- **環境変数**:

  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | final_crosscheck_requestsへ接続するRDB接続文字列 |

- **標準入力**: なし（対話確認は次UC「対話確認のうえ確報比較依頼をABORTEDへ遷移させる」で実施する）
- **標準出力契約**: 受理時のみ、対象run_id・対象日（target_date）・現在状態（RUNNING）・次アクション（confirmコマンド）を1行で出力する
- **標準エラー契約**: 対象未存在・状態不一致・引数不正の場合、原因と次アクションを1文ずつ出力する
- **終了コード**:

  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（中止依頼を受理） |
  | 1 | 業務エラー（対象未存在、またはstatusがRUNNING以外） |
  | 2 | バリデーションエラー（run_id未指定） |
  | 124 | タイムアウト（RDB接続タイムアウト） |
  | 130 | SIGINT中断 |

## データモデル変更

### final_crosscheck_requests（参照のみ、変更なし）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | uuid | 確報比較依頼の識別子（PK。execution_specs.run_idへのFK） | 変更なし（SELECT対象） |
| target_date | date | 確報比較の対象日 | 変更なし（SELECT対象） |
| status | string | 確報比較依頼状態（REQUESTED/CLAIMED/RUNNING/SUCCEEDED/FAILED/ABORTED） | 変更なし（SELECT対象。本UCではUPDATEしない） |
| lease_expires_at | datetime | lease期限 | 変更なし（SELECT対象） |
| worker_id | string | 処理中のworker識別子 | 変更なし（SELECT対象） |

### audit_logs（追記専用）

audit-event-contract.yaml のフィールド定義（actor / operation / outcome へ統一）に従う。

| イベント | operation | outcome | slot | attempt_id | タイミング |
|---------|-----------|---------|------|-----------|-----------|
| abort_requested | abort | accepted \| rejected | '-'（slotに紐づかないrun単位イベント） | '-' | 中止依頼受理時（状態遷移は伴わない） |

冪等キーは(run_id, slot, attempt_id, event_name)。audit_chain_headsの対象run_id行を排他ロック（SELECT ... FOR UPDATE）してprevious_hashを確定し、audit_logsのINSERTと同一transactionでaudit_chain_headsを更新する（hash-chain lock契約）。

## ビジネスルール

- 中止依頼はstatus=RUNNINGの確報比較依頼に対してのみ受理する。REQUESTED/CLAIMED/SUCCEEDED/FAILED/ABORTEDの場合は業務エラー（exit 1）として拒否する
- 本UCは確報比較依頼のstatusを変更しない。ABORTEDへの遷移は対話確認を経た次UCでのみ行う（リリース判断の正本となるバッチであるため誤操作防止を最優先する）
- 対象run_idが確報比較依頼テーブルに存在しない場合は業務エラー（exit 1）とする
- 中止依頼の受理はevent_name=abort_requested（operation=abort、outcome=accepted）、拒否はoutcome=rejectedとして監査イベントを記録する（イベント種別ごとの独自フィールド名は使わない）

## CLI 出力/画面表示マッピング

design-event.yaml の「確報比較中止依頼画面」（route: `/cli/abort/final-crosscheck/request`）に対応する。

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 対象run_id・対象日・現在状態表示 | テキスト（stdout相当） | CrossCheckRequestRow（variant: final） | 中止依頼対象の確報比較依頼のrun_id・target_date・状態バッジ（RUNNING=blue）・lease期限・worker識別子を表示する |
| 中止依頼ボタン相当 | ボタン（CLIコマンド呼び出しに読み替え） | Button（variant: destructive） | `relaygate abort final-crosscheck request` コマンドの実行操作に対応する |
| 受理/エラーメッセージ | テキスト | Banner（variant: info/error） | 受理時はinfo、状態不一致・未存在エラー時はerrorのトークンを用いる |

デザイントークン参照: 状態バッジは `var(--component-status-badge-running)`（background: var(--color-blue-100), foreground: var(--color-blue-600)）を使用する。CrossCheckRequestRowのvariant='final'により速報比較（rapid）との混同を避ける。

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「二段階中止確認パターン（依頼→対話確認）」における①中止依頼画面に該当する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| CrossCheckRequestRow（variant: final） | `src/components/domain/CrossCheckRequestRow.tsx` | runId=run_id, jobIdOrTargetDate=target_date, state=status（RUNNING）, leaseExpiry=lease_expires_at, workerId=worker_id |
| Button（variant: destructive） | `src/components/ui/Button.tsx` | onClick相当=`relaygate abort final-crosscheck request`コマンド実行 |
| Banner（variant: info/error） | `src/components/ui/Banner.tsx` | variant=info（受理時）/ error（状態不一致・未存在時） |

本UCは「対話確認画面へ直接遷移することは許可しない」制約（共通操作パターン参照）に従い、次UC「対話確認のうえ確報比較依頼をABORTEDへ遷移させる」のAbortConfirmDialogへ処理を引き継ぐ。

## ティア完了条件（BDD）

```gherkin
Feature: RUNNING中の確報比較依頼の中止を依頼する - tier-worker

  Scenario: abort_final_crosscheck_request_RUNNING中の対象の場合_中止依頼を受理すること
    # Arrange
    Given execution_specsテーブルにrun_id="e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f", job_id="daily-settlement"の行が存在する
    And final_crosscheck_requestsテーブルにrun_id="e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f", target_date="2026-08-18", status="RUNNING", worker_id="worker-05"の行が存在する
    # Act
    When 環境変数RELAYGATE_OPERATOR="ops-tanaka"の下で relaygate abort final-crosscheck request --run-id e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f を実行する
    # Assert
    Then 標準出力に "中止依頼を受理しました run_id=e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f target_date=2026-08-18 status=RUNNING" が出力され終了コード0で終了する
    And audit_logsテーブルにevent_name="abort_requested", operation="abort", outcome="accepted", actor="ops-tanaka", slot="-", attempt_id="-"の行が1件追加される

  Scenario: abort_final_crosscheck_request_RUNNING以外の状態の場合_中止依頼を拒否すること
    # Arrange
    Given execution_specsテーブルにrun_id="e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f"の行が存在する
    And final_crosscheck_requestsテーブルにrun_id="e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f", target_date="2026-08-18", status="CLAIMED"の行が存在する
    # Act & Assert
    When relaygate abort final-crosscheck request --run-id e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f を実行すると、標準エラーに "中止依頼できません run_id=e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f status=CLAIMED（RUNNING状態のみ中止依頼可能です）" が出力され終了コード1で終了する
```
