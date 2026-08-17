# 対話確認のうえ確報比較依頼をABORTEDへ遷移させる - tier-worker仕様

## 変更概要

RUNNING中の確報比較依頼（E-005, AG-004）を、運用者の対話確認を経てABORTED状態へ明示的に遷移させるCLIコマンドをtier-workerに追加する。UPDATE時にWHERE句でstatus='RUNNING'を条件とすることで、対話確認中に他プロセス（hang-detector等）が状態を変化させた場合の競合を検知する。

## CLI コマンド仕様

### abort final-crosscheck confirm

- **呼び出し形式**: `relaygate abort final-crosscheck confirm --run-id <run_id> [--yes]`
- **引数**:

  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --run-id | string | Yes | ABORTEDへ遷移させる対象の確報比較依頼のrun_id |
  | --yes | boolean(flag) | No（非TTY実行時は必須） | 対話確認をスキップし中止を実行する明示フラグ。TTY接続時は指定不要（対話プロンプトを提示する） |

- **環境変数**:

  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | final_crosscheck_requests / audit_logsへ接続するRDB接続文字列 |
  | RELAYGATE_OPERATOR | Yes | 監査ログに記録する操作者識別子 |

- **標準入力**: TTY接続時のみ、対象run_id・対象日・現在状態・「取消不可」の明示を提示したうえで y/n の二択入力を受け付ける（--yes指定時は省略）
- **標準出力契約**: 遷移完了時は"確報比較依頼をABORTEDへ遷移させました run_id=..."、キャンセル時は"中止をキャンセルしました run_id=..."を1行で出力する
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

### final_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | string | 確報比較依頼状態。'RUNNING'から'ABORTED'へ更新する | 変更（UPDATE、WHERE status='RUNNING'で楽観的競合検知） |

### audit_logs

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| operator | string | ABORTEDへの遷移を実行した運用者識別子 | 追加（INSERT） |
| aborted_at | datetime | ABORTEDへの遷移日時 | 追加（INSERT） |
| run_id | uuid | 対象の確報比較依頼のrun_id | 追加（INSERT） |
| action | string | 操作種別（"abort_confirm"固定） | 追加（INSERT） |

## ビジネスルール

- RUNNING状態の確報比較依頼のみABORTEDへ遷移可能とする。UPDATE文のWHERE句にstatus='RUNNING'を含め、更新件数が0の場合は他プロセスによる状態変化とみなし業務エラー（exit 1）とする（RDBのlease/claim状態遷移の整合性を保証する）
- TTY接続時は対象・影響範囲・取消不可であることを明示したうえでy/nの二択のみを許可する。非TTY（バッチ）実行時は対話確認をスキップせず、`--yes`フラグの明示指定がなければバリデーションエラー（exit 2）とする
- 対話確認でnを選択した場合は状態を変更せず正常終了（exit 0）とする
- 操作者・操作日時・対象run_idを含む監査ログとして記録する（CTP-005準拠）
- 確報クロスチェックはリリース判断の正本となるため、ABORTED遷移後は該当日次バッチのリリース判断材料として利用できないことを運用者へ明示する（次アクションとしてリラン実行を案内する）

## CLI 出力/画面表示マッピング

design-event.yaml の「確報比較中止確認画面」（route: `/cli/abort/final-crosscheck/confirm`）に対応する。

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 対話確認プロンプト | フォーム（y/n二択） | AbortConfirmDialog | 対象run_id・影響範囲・取消不可であることを明示し、y/nの二択のみを許可する。誤操作防止のためショートカット確認は設けない |
| 遷移完了/エラーメッセージ | テキスト | Banner（variant: success/error） | 遷移完了時はsuccess、状態競合・バリデーションエラー時はerrorのトークンを用いる |

デザイントークン参照: AbortConfirmDialogは `var(--component-confirm-prompt-destructive-border)`（destructive-border: var(--color-red-600)）を用いて誤操作防止のdestructiveスタイルを強制する。

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「二段階中止確認パターン（依頼→対話確認）」における②対話確認画面に該当する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| AbortConfirmDialog | `src/components/domain/AbortConfirmDialog.tsx` | runId=run_id, target="確報比較依頼", impactSummary="ABORTEDへ遷移すると取消不可。リリース判断材料として利用できなくなり、再実行対象のbackground実行・速報比較依頼を選択するUCから再実行が必要" |
| Banner（variant: success/error） | `src/components/ui/Banner.tsx` | variant=success（ABORTED遷移完了時）/ error（状態競合・バリデーションエラー時） |

対話確認結果はプロセス内で一度だけ評価し（リトライ・再確認は行わない）、n応答・非TTY未同意は状態変更を発生させず終了コードで区別する（共通操作パターン準拠）。

## ティア完了条件（BDD）

```gherkin
Feature: 対話確認のうえ確報比較依頼をABORTEDへ遷移させる - tier-worker

  Scenario: 対話確認(y)によりworkerがABORTEDへ更新する
    Given final_crosscheck_requestsテーブルにrun_id="fc-2026-0817-001", status="RUNNING"のレコードが存在する
    When 環境変数RELAYGATE_OPERATOR="opuser01"の下でTTY接続からrelaygate abort final-crosscheck confirm --run-id fc-2026-0817-001 を実行し "y" を入力する
    Then final_crosscheck_requestsテーブルのrun_id="fc-2026-0817-001"のstatusが"ABORTED"に更新される
    And audit_logsテーブルに operator="opuser01", run_id="fc-2026-0817-001", action="abort_confirm" のレコードが1件追加される
    And 終了コード0で終了する

  Scenario: UPDATE時の状態競合を検知して業務エラーとする
    Given final_crosscheck_requestsテーブルのrun_id="fc-2026-0816-004"がconfirmコマンド呼び出し直前にhang-detectorによりstatus="FAILED"へ更新されている
    When relaygate abort final-crosscheck confirm --run-id fc-2026-0816-004 --yes を実行する
    Then UPDATE文の更新件数が0となり、標準エラーに "状態が変化したため中止できません run_id=fc-2026-0816-004" が出力され終了コード1で終了する
```
