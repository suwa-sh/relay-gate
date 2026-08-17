# execution-spec.jsonの実行設定を保ったまま再実行する - tier-facade仕様

## 変更概要

完了済み（SUCCEEDED/FAILED）または中止済み（ABORTED）のbackground実行（Runner実行結果, E-002）について、元のexecution-spec.json（E-001, AG-001）の実行設定を保ったまま新しいrun_id（parent_run_id=元run_id）で再実行するCLIコマンドをtier-facadeに追加する。実行設定の複製と、blue/green実装へのSSH起動指示を担う。

## CLI コマンド仕様

### rerun run（--target background）

- **呼び出し形式**: `relaygate rerun run --target background --run-id <元run_id>`
- **引数**:

  | 引数名 | 型 | 必須 | 説明 |
  |--------|---|------|------|
  | --target | string(enum: background\|rapid-crosscheck) | Yes | リラン対象種別。facadeはbackground指定時のみ処理する |
  | --run-id | string | Yes | リラン元となる完了済み・中止済みのbackground実行のrun_id（「再実行対象のbackground実行・速報比較依頼を選択する」UCで選定） |

- **環境変数**:

  | 変数名 | 必須 | 説明 |
  |--------|------|------|
  | RELAYGATE_RDB_DSN | Yes | execution_specs / runner_results / audit_logsへ接続するRDB接続文字列 |
  | RELAYGATE_OPERATOR | Yes | 監査ログに記録する操作者識別子 |
  | RELAYGATE_SSH_KEY_PATH | Yes | blue/green実装への起動に用いるSSH秘密鍵のパス |

- **標準入力**: なし
- **標準出力契約**: 再実行受理時のみ、新規run_id・parent_run_id・status=RUNNINGを1行で出力する
- **標準エラー契約**: 対象run_id未存在、SSH起動失敗の場合、原因を1文で出力する
- **終了コード**:

  | コード | 意味 |
  |--------|------|
  | 0 | 正常終了（再実行を開始） |
  | 1 | 業務エラー（元のexecution-spec.json未存在、SSH起動失敗） |
  | 2 | バリデーションエラー（--run-id未指定） |
  | 124 | タイムアウト（SSH起動タイムアウト） |
  | 130 | SIGINT中断 |

## データモデル変更

### execution_specs

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | uuid | 新規発行するrun_id（PK） | 追加（INSERT） |
| parent_run_id | uuid | リラン元のrun_id | 追加（INSERT、元run_idを設定） |
| job_id | string | JOB_ID | 追加（元の値を複製） |
| host | string | 実行ホスト | 追加（元の値を複製） |
| exec_user | string | 実行ユーザー | 追加（元の値を複製） |
| script_path | string | スクリプトパス | 追加（元の値を複製） |
| work_dir | string | 作業ディレクトリ | 追加（元の値を複製） |
| fixed_args | text | 固定引数 | 追加（元の値を複製） |
| additional_args | text | 追加引数 | 追加（元の値を複製） |
| job_map_version | string | マップ版 | 追加（元の値を複製） |
| impl_version | string | 実装版 | 追加（元の値を複製） |
| hang_detect_limit_minutes | integer | ハング検知しきい値（分） | 追加（元の値を複製） |
| credential_ref | string | 認証情報参照名（実値は保存しない） | 追加（元の値を複製。実値は複製しない） |

### runner_results

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | uuid | 新規run_id（PK構成要素） | 追加（INSERT） |
| slot_type | string | 元のexecution-spec.jsonから引き継ぐslot種別（blue/green） | 追加（INSERT） |
| role_type | string | 'background'固定（PK構成要素） | 追加（INSERT） |
| status | string | 'RUNNING'固定 | 追加（INSERT） |
| started_at | datetime | 再実行開始時刻 | 追加（INSERT） |

### audit_logs

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| operator | string | リランを実行した運用者識別子 | 追加（INSERT） |
| run_id | uuid | 新規発行したrun_id | 追加（INSERT） |
| action | string | 操作種別（"rerun"固定） | 追加（INSERT） |

## ビジネスルール

- 元のexecution-spec.jsonの実行設定（host/exec_user/script_path/work_dir/固定引数・追加引数/job_map_version/impl_version/hang_detect_limit_minutes/credential_ref）を一切変更せず新規run_idへ複製する（「実行設定を保ったまま再実行する」というUC名の制約）。認証情報は参照名のみを複製し、実値は取り扱わない
- 新規run_idを発行し、parent_run_idに元run_idを設定する。run_id/parent_run_idの相関により実行系譜を追跡し、RDBのlease/claim機構と合わせて重複起動を検知・防止する（CTP-006冪等性方針）
- リラン対象は「再実行対象のbackground実行・速報比較依頼を選択する」UCで既にstatusがSUCCEEDED/FAILED/ABORTEDに絞り込まれた候補であることを前提とする。RUNNING中のbackground実行を対象にリランを試みた場合は、元のexecution-spec.jsonのrun_idに紐づくRunner実行結果の状態と矛盾しないことをusecase層で再確認する
- 操作者・操作日時・対象run_id（新規発行run_id）を含む監査ログとして記録する（CTP-005準拠）

## CLI 出力/画面表示マッピング

design-event.yaml の「リラン実行画面」（route: `/cli/rerun/run`）に対応する。

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 元の実行設定確認表示 | カード（stdout相当） | ExecutionSpecCard | 実行前に元のexecution-spec.jsonの内容（run_id/job_id/host/script/mapVersion/implVersion/hangDetectLimitMinutes/credentialRef）を確認表示し、設定の意図しない変化がないことを保証する |
| 再実行開始結果表示 | パネル（stdout相当） | RunnerResultPanel（variant: background） | 新規run_id・status=RUNNINGを表示する |

デザイントークン参照: ExecutionSpecCardのcredentialRefは参照名のみを表示するpropとし、実値表示用のpropを設けない（nfr_decisions記載のセキュリティ方針に準拠）。

## 共通コンポーネント参照

`_cross-cutting/ux-ui/common-components.md` の「状態一覧+フィルターパターン」「実行結果ターミナル表示パターン」に該当する。

| コンポーネント | インポートパス | Props マッピング |
|---|---|---|
| ExecutionSpecCard | `src/components/domain/ExecutionSpecCard.tsx` | run_id=run_id, job_id=job_id, host=host, script=script_path, mapVersion=job_map_version, implVersion=impl_version, hangDetectLimitMinutes=hang_detect_limit_minutes, credentialRef=credential_ref（参照名のみ表示。実値表示用propは設けない） |
| RunnerResultPanel（variant: background） | `src/components/domain/RunnerResultPanel.tsx` | runId=新規run_id, slot=slot_type, role="background", startedAt=started_at, status=RUNNING（起動直後のためstdout/stderr/exitCodeは未確定） |

ExecutionSpecCardのcredentialRefはnfr_decisions記載のセキュリティ方針に準拠し参照名のみを表示する（デザイントークン参照節と同一の制約）。

## ティア完了条件（BDD）

```gherkin
Feature: execution-spec.jsonの実行設定を保ったまま再実行する - tier-facade

  Scenario: facadeが元の実行設定を保ったまま新規run_idでbackground roleを再起動する
    Given execution_specsテーブルにrun_id="rg-2026-0817-011", host="host-a", script_path="/opt/blue/run.sh", hang_detect_limit_minutes=30のレコードが存在する
    And runner_resultsテーブルにrun_id="rg-2026-0817-011", role_type="background", status="FAILED"のレコードが存在する
    When 環境変数RELAYGATE_OPERATOR="opuser01"の下で relaygate rerun run --target background --run-id rg-2026-0817-011 を実行する
    Then execution_specsテーブルに新規run_id（parent_run_id="rg-2026-0817-011"）でhost="host-a", script_path="/opt/blue/run.sh", hang_detect_limit_minutes=30のレコードが追加される
    And runner_resultsテーブルに新規run_idでrole_type="background", status="RUNNING"のレコードが追加される
    And audit_logsテーブルに operator="opuser01", action="rerun" のレコードが1件追加される
    And 終了コード0で終了する
```
