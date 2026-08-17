# execution-spec.jsonの実行設定を保ったまま再実行する - tier-worker仕様

## 変更概要

完了済み（SUCCEEDED/FAILED）または中止済み（ABORTED）の速報比較依頼（E-003, AG-003）を、同一run_idのままREQUESTED状態へ差し戻すCLIコマンドをtier-workerに追加する。差し戻し後は通常の速報クロスチェックフロー（`blue/green runnerの完了通知を受けて速報比較依頼を作成する`以降）と同様にworkerがlease/claim機構で再クレームし処理する。

## CLI コマンド仕様

### rerun run（--target rapid-crosscheck）

- **呼び出し形式**: `relaygate rerun run --target rapid-crosscheck --run-id <run_id>`
- **引数**:

  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --target | string(enum: background\|rapid-crosscheck) | Yes | リラン対象種別。workerはrapid-crosscheck指定時のみ処理する |
  | --run-id | string | Yes | REQUESTEDへ差し戻す対象の速報比較依頼のrun_id（「再実行対象のbackground実行・速報比較依頼を選択する」UCで選定） |

- **環境変数**:

  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | rapid_crosscheck_requests / audit_logsへ接続するRDB接続文字列 |
  | RELAYGATE_OPERATOR | Yes | 監査ログに記録する操作者識別子 |

- **標準入力**: なし
- **標準出力契約**: 差し戻し完了時のみ、対象run_id・遷移先状態（REQUESTED）を1行で出力する
- **標準エラー契約**: 対象未存在、状態不一致（REQUESTED/CLAIMED/RUNNING中の対象を指定）の場合、原因を1文で出力する
- **終了コード**:

  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（REQUESTEDへの差し戻し完了） |
  | 1 | 業務エラー（対象未存在、またはstatusがSUCCEEDED/FAILED/ABORTED以外） |
  | 2 | バリデーションエラー（run_id未指定） |
  | 124 | タイムアウト（RDB接続タイムアウト） |
  | 130 | SIGINT中断 |

## データモデル変更

### rapid_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | string | 'SUCCEEDED'/'FAILED'/'ABORTED'から'REQUESTED'へ更新する | 変更（UPDATE、WHERE status IN ('SUCCEEDED','FAILED','ABORTED')で重複起動を防止） |
| lease_expires_at | datetime | lease期限。NULLへクリアする | 変更（UPDATE） |
| worker_id | string | 処理中worker識別子。NULLへクリアする | 変更（UPDATE） |

### audit_logs

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| operator | string | リランを実行した運用者識別子 | 追加（INSERT） |
| run_id | uuid | 対象の速報比較依頼のrun_id | 追加（INSERT） |
| action | string | 操作種別（"rerun"固定） | 追加（INSERT） |

## ビジネスルール

- REQUESTEDへの差し戻しはstatusがSUCCEEDED、FAILED、ABORTEDのいずれかの速報比較依頼に対してのみ許可する。UPDATE文のWHERE句にstatus IN ('SUCCEEDED','FAILED','ABORTED')を含め、更新件数が0の場合は業務エラー（exit 1）とする（REQUESTED/CLAIMED/RUNNING中の対象への二重差し戻しによる重複起動を防止する。RDBのlease/claim状態遷移の整合性保証）
- 差し戻し時にlease_expires_atとworker_idをクリアし、既存のlease/claim情報を持ち越さない。これによりhang-detectorの「CLAIMED状態でlease失効かつ未着手はREQUESTEDへ差し戻す」ルールとの整合性を保つ
- run_idは変更しない（速報比較依頼のリランは同一run_idの状態を差し戻すのみで、新規run_idは発行しない。background実行側のリランとは異なる点に注意する）
- 操作者・操作日時・対象run_idを含む監査ログとして記録する（CTP-005準拠）

## CLI 出力/画面表示マッピング

design-event.yaml の「リラン実行画面」（route: `/cli/rerun/run`）に対応する。

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 対象速報比較依頼の状態表示 | パネル（stdout相当） | RunnerResultPanel、CrossCheckRequestRow（variant: rapid） | 対象run_id・遷移前状態（SUCCEEDED/FAILED/ABORTED）・遷移後状態（REQUESTED）を表示する |

デザイントークン参照: StatusBadgeの遷移先表示は`var(--component-status-badge-requested)`（background: var(--color-amber-100), foreground: var(--color-amber-600)）を用いる。

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「状態一覧+フィルターパターン」「実行結果ターミナル表示パターン」に該当する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| RunnerResultPanel | `src/components/domain/RunnerResultPanel.tsx` | runId=run_id, startedAt=（差し戻し実行時刻）。遷移前状態（SUCCEEDED/FAILED/ABORTED）から遷移後状態（REQUESTED）への変化を示す |
| CrossCheckRequestRow（variant: rapid） | `src/components/domain/CrossCheckRequestRow.tsx` | runId=run_id, state=status（遷移後REQUESTED）, leaseExpiry=lease_expires_at（NULLへクリア）, workerId=worker_id（NULLへクリア） |

状態バッジの遷移先表示は`var(--component-status-badge-requested)`トークンを用いる（CLI 出力/画面表示マッピング節のデザイントークン参照と同一）。

## ティア完了条件（BDD）

```gherkin
Feature: execution-spec.jsonの実行設定を保ったまま再実行する - tier-worker

  Scenario: workerが中止済みの速報比較依頼をREQUESTEDへ差し戻す
    Given rapid_crosscheck_requestsテーブルにrun_id="rg-2026-0817-013", status="ABORTED", lease_expires_at="2026-08-17T10:20:00", worker_id="worker-03"のレコードが存在する
    When 環境変数RELAYGATE_OPERATOR="opuser01"の下で relaygate rerun run --target rapid-crosscheck --run-id rg-2026-0817-013 を実行する
    Then rapid_crosscheck_requestsテーブルのrun_id="rg-2026-0817-013"がstatus="REQUESTED", lease_expires_at=NULL, worker_id=NULLに更新される
    And audit_logsテーブルに operator="opuser01", run_id="rg-2026-0817-013", action="rerun" のレコードが1件追加される
    And 終了コード0で終了する

  Scenario: RUNNING中の対象への差し戻しを重複起動防止のため拒否する
    Given rapid_crosscheck_requestsテーブルにrun_id="rg-2026-0817-016", status="RUNNING"のレコードが存在する
    When relaygate rerun run --target rapid-crosscheck --run-id rg-2026-0817-016 を実行する
    Then UPDATE文の更新件数が0となり、標準エラーに "リランできません run_id=rg-2026-0817-016 status=RUNNING（SUCCEEDED/FAILED/ABORTEDのみリラン可能です）" が出力され終了コード1で終了する
```
