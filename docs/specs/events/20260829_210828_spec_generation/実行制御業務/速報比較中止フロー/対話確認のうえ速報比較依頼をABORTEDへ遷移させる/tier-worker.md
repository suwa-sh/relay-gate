# 対話確認のうえ速報比較依頼をABORTEDへ遷移させる - tier-worker仕様

## 変更概要

RUNNING中の速報比較依頼（E-003, AG-003）を、運用者の対話確認を経てABORTED状態へ明示的に遷移させるCLIコマンドをtier-workerに追加する。UPDATE時にWHERE句でstatus='RUNNING'を条件とすることで、対話確認中に他プロセスが状態を変化させた場合の競合を検知する。操作は監査イベント（abort_confirmed）としてhash-chain lock契約に従い記録する。

## CLI コマンド仕様

### abort rapid-crosscheck confirm

- **呼び出し形式**: `relaygate abort rapid-crosscheck confirm --run-id <run_id> [--yes]`
- **引数**:

  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --run-id | string | Yes | ABORTEDへ遷移させる対象の速報比較依頼のrun_id |
  | --yes | boolean(flag) | No（非TTY実行時は必須） | 対話確認をスキップし中止を実行する明示フラグ。TTY接続時は指定不要（対話プロンプトを提示する） |

- **環境変数**:

  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | rapid_crosscheck_requests / audit_logsへ接続するRDB接続文字列 |
  | RELAYGATE_OPERATOR | Yes | 監査イベントのactorへ記録する操作者識別子 |

- **標準入力**: TTY接続時のみ、対象run_id・現在状態・「取消不可」の明示を提示したうえで y/n の二択入力を受け付ける（--yes指定時は省略）
- **標準出力契約**: 遷移完了時は"速報比較依頼をABORTEDへ遷移させました run_id=..."、キャンセル時は"中止をキャンセルしました run_id=..."を1行で出力する
- **標準エラー契約**: 非TTYで--yes未指定、対象未存在、UPDATE時の状態競合（更新件数0）の場合、原因を1文で出力する
- **終了コード**:

  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（ABORTEDへ遷移完了、または対話確認によるキャンセル） |
  | 1 | 業務エラー（対象未存在、または対話確認前後での状態競合により更新件数0） |
  | 2 | バリデーションエラー（run_id未指定、非TTYで--yes未指定） |
  | 124 | タイムアウト（RDB接続タイムアウト） |
  | 130 | SIGINT中断（対話プロンプト中のCtrl+C） |

## データモデル変更

### rapid_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | string | 速報比較依頼状態。'RUNNING'から'ABORTED'へ更新する | 変更（UPDATE、WHERE status='RUNNING'で楽観的競合検知） |

### audit_logs（追記専用）

audit-event-contract.yaml のフィールド定義（actor / operation / outcome へ統一）に従う。イベント種別ごとの独自フィールド名（operator / aborted_at / action等）は使わない。

| イベント | operation | outcome | slot | attempt_id | タイミング |
|---------|-----------|---------|------|-----------|-----------|
| abort_confirmed | abort | succeeded \| rejected | '-'（slotに紐づかないrun単位イベント） | '-' | 対話確認後の状態遷移時（y以外の回答による中断はoutcome=rejectedで記録する） |

冪等キーは(run_id, slot, attempt_id, event_name)。認証情報・stdout/stderr本文は含めない。

### audit_chain_heads

audit_logsへの追記時に対象run_id行を排他ロック（SELECT ... FOR UPDATE）してprevious_hashを確定し、audit_logsのINSERTと同一transactionでhead_event_id / head_hash / chain_length / updated_atを更新する（hash-chain lock契約。run_id単位でチェーンの分岐・欠損を防ぐ）。

## ビジネスルール

- RUNNING状態の速報比較依頼のみABORTEDへ遷移可能とする。UPDATE文のWHERE句にstatus='RUNNING'を含め、更新件数が0の場合は他プロセスによる状態変化とみなし業務エラー（exit 1）とする（RDBのlease/claim状態遷移の整合性を保証する）
- ABORTEDへの遷移は対話確認による明示的操作でのみ発生する。TTY接続時は対象・影響範囲・取消不可であることを明示したうえでy/nの二択のみを許可する。非TTY（バッチ）実行時は対話確認をスキップせず、`--yes`フラグの明示指定がなければバリデーションエラー（exit 2）とする
- 対話確認でnを選択した場合は状態を変更せず正常終了（exit 0）とし、監査イベントをoutcome=rejectedで記録する
- 遷移完了はevent_name=abort_confirmed（operation=abort、outcome=succeeded）の監査イベントとして記録する。actorにはRELAYGATE_OPERATORの値を格納する（CTP-005準拠）
- ABORTEDへ遷移した依頼は、UC「execution-spec.jsonの実行設定を保ったまま再実行する」により新しいrun_idの依頼として再実行できる（元依頼はABORTEDのまま変更されない）

## CLI 出力/画面表示マッピング

design-event.yaml の「速報比較中止確認画面」（route: `/cli/abort/rapid-crosscheck/confirm`）に対応する。

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 対話確認プロンプト | フォーム（y/n二択） | AbortConfirmDialog | 対象run_id・影響範囲・取消不可であることを明示し、y/nの二択のみを許可する。誤操作防止のためショートカット確認は設けない |
| 遷移完了/エラーメッセージ | テキスト | Banner（variant: success/error） | 遷移完了時はsuccess、状態競合・バリデーションエラー時はerrorのトークンを用いる |

デザイントークン参照: AbortConfirmDialogは `var(--component-confirm-prompt-destructive-border)`（destructive-border: var(--color-red-600)）を用いて誤操作防止のdestructiveスタイルを強制する。

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「二段階中止確認パターン（依頼→対話確認）」における②対話確認画面に該当する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| AbortConfirmDialog | `src/components/domain/AbortConfirmDialog.tsx` | runId=run_id, target="速報比較依頼", impactSummary="ABORTEDへ遷移すると取消不可（再実行対象のbackground実行・速報比較依頼を選択するUCから新しいrun_idの依頼として再実行可能）" |
| Banner（variant: success/error） | `src/components/ui/Banner.tsx` | variant=success（ABORTED遷移完了時）/ error（状態競合・バリデーションエラー時） |

対話確認結果はプロセス内で一度だけ評価し（リトライ・再確認は行わない）、n応答・非TTY未同意は状態変更を発生させず終了コードで区別する（共通操作パターン準拠）。

## ティア完了条件（BDD）

```gherkin
Feature: 対話確認のうえ速報比較依頼をABORTEDへ遷移させる - tier-worker

  Scenario: abort_rapid_crosscheck_confirm_対話確認y応答の場合_ABORTEDへ更新し監査イベントを記録すること
    # Arrange
    Given execution_specsテーブルにrun_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement"の行が存在する
    And rapid_crosscheck_requestsテーブルにrun_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", job_id="daily-settlement", blue_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", blue_attempt_id="att-blue-0001", green_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", green_attempt_id="att-green-0001", status="RUNNING"の行が存在する
    # Act
    When 環境変数RELAYGATE_OPERATOR="ops-tanaka"の下でTTY接続から relaygate abort rapid-crosscheck confirm --run-id c41d7e08-2b95-4f36-a8d1-5e7c93b204af を実行し "y" を入力する
    # Assert
    Then rapid_crosscheck_requestsテーブルのrun_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af"のstatusが"ABORTED"に更新される
    And audit_logsテーブルにevent_name="abort_confirmed", operation="abort", outcome="succeeded", actor="ops-tanaka", slot="-", attempt_id="-"の行が1件追加され、audit_chain_headsのrun_id行が更新される
    And 終了コード0で終了する

  Scenario: abort_rapid_crosscheck_confirm_状態競合の場合_業務エラーとすること
    # Arrange
    Given execution_specsテーブルにrun_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement"の行が存在する
    And rapid_crosscheck_requestsテーブルのrun_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af"がconfirmコマンド呼び出し直前にworkerによりstatus="FAILED"へ更新されている
    # Act & Assert
    When relaygate abort rapid-crosscheck confirm --run-id c41d7e08-2b95-4f36-a8d1-5e7c93b204af --yes を実行すると、UPDATE文の更新件数が0となり、標準エラーに "状態が変化したため中止できません run_id=c41d7e08-2b95-4f36-a8d1-5e7c93b204af" が出力され終了コード1で終了する
```
