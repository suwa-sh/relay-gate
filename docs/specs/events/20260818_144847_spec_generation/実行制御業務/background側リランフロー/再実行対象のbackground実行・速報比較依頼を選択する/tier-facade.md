# 再実行対象のbackground実行・速報比較依頼を選択する - tier-facade仕様

## 変更概要

終了状態（SUCCEEDED/FAILED/UNKNOWN/ABORTED）のbackground実行（Runner実行結果, E-002）から再実行対象を一覧提示するCLIコマンドをtier-facadeに追加する。起動試行のidentityは(run_id, slot_type, role_type, attempt_id)であり、attempt_no・accepted_atを候補一覧に含める。本UCは状態遷移を発生させない読み取り専用の候補選定機能である。

## CLI コマンド仕様

### rerun select（--target background）

- **呼び出し形式**: `relaygate rerun select --target background [--status SUCCEEDED|FAILED|UNKNOWN|ABORTED] [--slot blue|green]`
- **引数**:

  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --target | string(enum: background\|rapid-crosscheck) | Yes | リラン対象種別。dispatch先のtierを決定する。facadeはbackground指定時のみ処理する |
  | --status | string(enum: SUCCEEDED\|FAILED\|UNKNOWN\|ABORTED) | No | 候補を絞り込む状態。未指定時はSUCCEEDED/FAILED/UNKNOWN/ABORTEDすべてを候補とする |
  | --slot | string(enum: blue\|green) | No | 候補を絞り込むslot種別。--target backgroundでのみ指定できる。未指定時はblue/green両方を候補とする |

- **環境変数**（cli-command-contract.yaml の dispatch[target=background].env_vars に従う）:

  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | execution_specs / slot_execution_specs / runner_resultsへ接続するRDB接続文字列 |

- **標準入力**: なし
- **標準出力契約**: 候補一覧を1候補1行で出力する（run_id/slot_type/role_type/attempt_id/attempt_no/status/accepted_at）。候補0件の場合は「該当するリラン候補はありません」を出力する
- **標準エラー契約**: --target未指定、--status/--slotの不正なenum値の場合に原因と次アクションを1文ずつ出力する
- **終了コード**:

  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（候補0件を含む） |
  | 1 | 業務エラー（RDB接続失敗） |
  | 2 | バリデーションエラー（--target未指定、--status/--slotの不正なenum値） |
  | 124 | タイムアウト（RDB接続タイムアウト） |
  | 130 | SIGINT中断 |

## データモデル変更

### runner_results（参照のみ、変更なし）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | uuid | 対象実行のrun_id（PK構成要素） | 変更なし（SELECT対象） |
| slot_type | string | blue/green（PK構成要素） | 変更なし（SELECT対象・--slotフィルタ条件） |
| role_type | string | foreground/background/rapid-crosscheck（PK構成要素） | 変更なし（SELECT条件: 'background'固定） |
| attempt_id | string | 起動試行の一意識別子（PK構成要素） | 変更なし（SELECT対象） |
| attempt_no | integer | 同一(run_id, slot_type, role_type)内の起動試行連番（1始まり） | 変更なし（SELECT対象） |
| accepted_at | datetime | 起動受付時刻（STARTING遷移時点） | 変更なし（SELECT対象） |
| status | string | STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED | 変更なし（SELECT条件: SUCCEEDED/FAILED/UNKNOWN/ABORTEDのみ） |

## ビジネスルール

- 候補として提示するのはrole_type='background'かつstatusがSUCCEEDED、FAILED、UNKNOWN、ABORTEDのいずれかのRunner実行結果（起動試行）に限定する。STARTING/RUNNING状態（起動受付中・実行中）は二重起動防止のため候補から除外する（リラン不可条件）
- timeoutや結果取得不能でUNKNOWNとなった起動試行もリラン候補に含める（UNKNOWNは推測でFAILEDを確定しない状態であり、再実行による回復対象とする）
- 本UCは読み取り専用であり、Runner実行結果の状態を変更しない
- 選定した候補のrun_idは、後続UC「execution-spec.jsonの実行設定を保ったまま再実行する」の`--run-id`引数への入力として利用する（後続UCは新しいrun_idを発行し、元runのレコード・状態・履歴は変更しない）

## CLI 出力/画面表示マッピング

design-event.yaml の「リラン対象選定画面」（route: `/cli/rerun/select`）に対応する。

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| background実行候補一覧 | テーブル（stdout相当） | RunnerResultPanel（variant: background） | run_id・slot_type・attempt_id・attempt_no・status（StatusBadge）・accepted_atを一覧表示する |
| 状態フィルタ | フィルタUI（CLIオプションに読み替え） | StatusBadge（variant: succeeded/failed/unknown/aborted） | `--status`オプションによる絞り込みに対応する |

デザイントークン参照: StatusBadgeは`var(--component-status-badge-succeeded)`（green）、`var(--component-status-badge-failed)`（red）、`var(--component-status-badge-unknown)`（amber）、`var(--component-status-badge-aborted)`（gray）を候補一覧の状態表示に使用する。

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「状態一覧+フィルターパターン」「実行結果ターミナル表示パターン」に該当する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| RunnerResultPanel（variant: background） | `src/components/domain/RunnerResultPanel.tsx` | runId=run_id, slot=slot_type, role="background", attemptId=attempt_id, attemptNo=attempt_no, acceptedAt=accepted_at（候補一覧のためstdout/stderr/exitCodeは非表示） |
| StatusBadge（variant: succeeded/failed/unknown/aborted） | `src/components/ui/StatusBadge.tsx` | variant=status（SUCCEEDED/FAILED/UNKNOWN/ABORTED）。`--status`オプションによる絞り込みに対応 |

状態管理はステートレス（CLI実行のたびにRDBから最新値を都度取得、クライアント側キャッシュ・楽観更新は行わない）。選定結果のrun_idは後続UC「execution-spec.jsonの実行設定を保ったまま再実行する」のExecutionSpecCardへ引き継ぐ。

## ティア完了条件（BDD）

```gherkin
Feature: 再実行対象のbackground実行・速報比較依頼を選択する - tier-facade

  Scenario: rerun_select_STARTINGとRUNNINGを除外し終了状態のbackground実行のみを候補として提示すること
    # Arrange
    Given execution_specsテーブルにrun_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement", job_map_version="v1.4.0", hang_detect_limit_minutes=30の行が存在する
    And slot_execution_specsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue"), host="blue-host-01", exec_user="batchuser", impl_version="blue-2.3.1"の行と(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green"), host="green-host-01", exec_user="batchuser", impl_version="green-0.9.0"の行が存在する
    And runner_resultsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="background", attempt_id="att-blue-0001"), attempt_no=1, status="FAILED"の行が存在する
    And runner_resultsテーブルに(run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001"), attempt_no=1, status="RUNNING"の行が存在する
    # Act
    When relaygate rerun select --target background を実行する
    # Assert
    Then 標準出力の候補一覧に attempt_id="att-blue-0001" の行が含まれ、attempt_id="att-green-0001" の行は含まれない
    And 終了コード0で終了する
```
