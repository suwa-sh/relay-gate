# 再実行対象のbackground実行・速報比較依頼を選択する - tier-facade仕様

## 変更概要

完了済み（SUCCEEDED/FAILED）または中止済み（ABORTED）のbackground実行（Runner実行結果, E-002）から再実行対象を一覧提示するCLIコマンドをtier-facadeに追加する。本UCは状態遷移を発生させない読み取り専用の候補選定機能である。

## CLI コマンド仕様

### rerun select（--target background）

- **呼び出し形式**: `relaygate rerun select --target background [--status SUCCEEDED|FAILED|ABORTED] [--slot blue|green]`
- **引数**:

  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --target | string(enum: background\|rapid-crosscheck) | Yes | リラン対象種別。facadeはbackground指定時のみ処理する |
  | --status | string(enum: SUCCEEDED\|FAILED\|ABORTED) | No | 候補を絞り込む状態。未指定時はSUCCEEDED/FAILED/ABORTEDすべてを候補とする |
  | --slot | string(enum: blue\|green) | No | 候補を絞り込むslot種別。未指定時はblue/green両方を候補とする |

- **環境変数**:

  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | runner_resultsへ接続するRDB接続文字列 |

- **標準入力**: なし
- **標準出力契約**: 候補一覧を1候補1行で出力する（run_id、slot、status、started_at）。候補0件の場合は「該当するリラン候補はありません」を出力する
- **標準エラー契約**: --target未指定、--status/--slotの不正値の場合、原因を1文で出力する
- **終了コード**:

  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（候補0件を含む） |
  | 2 | バリデーションエラー（--target未指定、不正なenum値） |
  | 124 | タイムアウト（RDB接続タイムアウト） |
  | 130 | SIGINT中断 |

## データモデル変更

### runner_results

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | uuid | Runner実行結果の識別子（PK構成要素） | 変更なし（SELECT対象） |
| slot_type | string | blue/green | 変更なし（SELECT対象・フィルタ条件） |
| role_type | string | foreground/background/rapid-crosscheck（PK構成要素） | 変更なし（SELECT条件: 'background'固定） |
| started_at | datetime | 開始時刻 | 変更なし（SELECT対象） |
| status | string | RUNNING/SUCCEEDED/FAILED/ABORTED | 変更なし（SELECT条件: SUCCEEDED/FAILED/ABORTEDのみ） |

## ビジネスルール

- 候補として提示するのはrole_type='background'かつstatusがSUCCEEDED、FAILED、ABORTEDのいずれかのRunner実行結果に限定する。RUNNING状態（実行中）は二重起動防止のため候補から除外する
- 本UCは読み取り専用であり、Runner実行結果の状態を変更しない
- 選定した候補のrun_idは、後続UC「execution-spec.jsonの実行設定を保ったまま再実行する」の`--run-id`引数への入力として利用する

## CLI 出力/画面表示マッピング

design-event.yaml の「リラン対象選定画面」（route: `/cli/rerun/select`）に対応する。

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| background実行候補一覧 | テーブル（stdout相当） | RunnerResultPanel（variant: background） | run_id・slot・status（StatusBadge）・started_atを一覧表示する |
| 状態フィルタ | フィルタUI（CLIオプションに読み替え） | StatusBadge（variant: succeeded/failed/aborted） | `--status`オプションによる絞り込みに対応する |

デザイントークン参照: StatusBadgeは`var(--component-status-badge-succeeded)`（green）、`var(--component-status-badge-failed)`（red）、`var(--component-status-badge-aborted)`（gray）を候補一覧の状態表示に使用する。

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「状態一覧+フィルターパターン」「実行結果ターミナル表示パターン」に該当する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| RunnerResultPanel（variant: background） | `src/components/domain/RunnerResultPanel.tsx` | runId=run_id, slot=slot_type, role="background", startedAt=started_at（候補一覧のためstdout/stderr/exitCodeは非表示） |
| StatusBadge（variant: succeeded/failed/aborted） | `src/components/ui/StatusBadge.tsx` | variant=status（SUCCEEDED/FAILED/ABORTED）。`--status`オプションによる絞り込みに対応 |

状態管理はステートレス（CLI実行のたびにRDBから最新値を都度取得、クライアント側キャッシュ・楽観更新は行わない）。選定結果のrun_idは後続UC「execution-spec.jsonの実行設定を保ったまま再実行する」のExecutionSpecCardへ引き継ぐ。

## ティア完了条件（BDD）

```gherkin
Feature: 再実行対象のbackground実行・速報比較依頼を選択する - tier-facade

  Scenario: SUCCEEDED/FAILED/ABORTEDのbackground実行のみを候補として提示する
    Given runner_resultsテーブルにrun_id="rg-2026-0817-011", role_type="background", status="FAILED"、run_id="rg-2026-0817-012", role_type="background", status="RUNNING"のレコードが存在する
    When relaygate rerun select --target background を実行する
    Then 標準出力の候補一覧に run_id="rg-2026-0817-011" が含まれ、run_id="rg-2026-0817-012" は含まれない
    And 終了コード0で終了する
```
