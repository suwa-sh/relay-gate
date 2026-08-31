# 速報クロスチェック runner へ完了通知を送信する - 速報クロスチェックティア仕様(受信側)

## 変更概要

`rapid-crosscheck-runner.sh` の公開 function(サブコマンド)`blue-completed` / `green-completed` を追加する。presentation で引数を検証し、usecase `register_completion` が rapid_runs の自系統列を更新する。両系成功判定と依頼作成は同じ起動内で続けて行う(UC「両系成功時に速報比較依頼を作成する」)。本ファイルは受信と登録までの契約を定義する。

## コマンド契約

### rapid-crosscheck-runner.sh blue-completed / green-completed

- **書式**: `rapid-crosscheck-runner.sh blue-completed|green-completed --run-id <run_id> --job-id <job_id> --exit-code <n> --artifact-uri <uri> [--verbose] [--help]`
- **アクセス権**: slot runner からの内部呼び出し(RAPID_CROSSCHECK_MODE=on のみ)。運用者は直接起動しない

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| サブコマンド | enum(blue-completed / green-completed) | Yes | — | 通知元の系統。更新する列(blue_* / green_*)を決める |
| `--run-id` | string | Yes | — | run_id(形式検証あり) |
| `--job-id` | string | Yes | — | JOB_ID(英数字・`_`・`-`) |
| `--exit-code` | integer | Yes | — | 0〜255 の整数(exitcode.txt の値。範囲外・非整数は終了コード 2) |
| `--artifact-uri` | string | Yes | — | 成果物ディレクトリ URI(`file://` 絶対パス) |
| `--verbose` | boolean | No | false | info を stderr に出す |

- **stdin**: なし
- **設定ファイル**: `$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env`(契約 `cli-command-contract.yaml` の config_files が正。キー定義は UC「速報比較依頼を claim する」tier-rapid-crosscheck.md「設定ファイル」)
  | キー | 必須 | 説明 |
  |---|---|---|
  | `RAPID_DB_CONN_REF` | Yes | 速報管理 DB 接続情報の参照名。本コマンドは on のときだけ起動されるため常に必須 |
  - ファイル不在は `error: config file not found path: <path>`、`RAPID_DB_CONN_REF` 欠落は `error: option required option=RAPID_DB_CONN_REF path: <path>` で終了コード 2(ui-design.md の全コマンド共通定型文。管理 DB へは接続しない)。本コマンドは feature-flag.env を読まない(off では slot runner が起動しない)

## 出力契約

- **stdout**(順序固定): `run_id=` / `job_id=` / `role=`(blue / green)/ `slot_status=`(SUCCEEDED / FAILED)の 4 行。以降の 3 行(`completion_status=` / `request_status=` / `requested_at=`)は同一起動内で続く UC「両系成功時に速報比較依頼を作成する」が出す(契約の 7 行と合わせて 1 つの stdout)
- **実行ログ**(`RELAY_GATE_LOG_DIR/rapid-crosscheck-runner.sh.log`): `INFO completion registered run_id=... role=... slot_status=...` / `INFO completion already registered run_id=... role=...`(再通知)/ `ERROR management db update failed run_id=... role=...`。行形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {UTC 出力日時} {LEVEL} {message}`)に従い、情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する
- **stderr**: `error: option required option=--run-id` / `error: invalid exit_code value=abc` / `error: unknown subcommand subcommand=foo` / `error: config file not found path: ...`(2)/ `error: option required option=RAPID_DB_CONN_REF path: ...`(2)/ `error: rapid run not found run_id=...` / `error: management db update failed run_id=... role=...`
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 自系統列を更新した(既に登録済みの再通知は既存値を保持して 0。先勝ち) |
  | 2 | 入力エラー | サブコマンド不正、必須オプション欠落、run_id / exit_code / artifact_uri の形式不正、未知のオプション、`$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` 不在・`RAPID_DB_CONN_REF` 欠落 |
  | 3 | 業務エラー | run_id の rapid_runs 行が存在しない(facade が parallel_run / rapid_run を作成していない) |
  | 6 | 実行エラー | 管理 DB 接続・SQL 失敗 |

## UC ロジック

- **バリデーション**: presentation で上表の形式検証。`--artifact-uri` はスキーム `file://` と絶対パスのみ(存在確認は行わない。共有 FS でない配置を許容する)
- **確認プロンプト**: なし
- **冪等性(先勝ち。契約 idempotency と同じ)**: `UPDATE rapid_runs SET blue_status=?, blue_artifact_uri=?, blue_completed_at=? WHERE run_id=? AND blue_status IS NULL`。同一 run_id + role の 2 回目以降の通知は更新 0 行となり、既存値を変更せず終了コード 0(stderr には何も出さず、実行ログに `INFO completion already registered` を残す)。通知値が既存値と異なっても既存値を保持する(同一 run の同一 role が異なる結果で通知されることは Runner Result Contract 上あり得ない)。運用者が通知失敗の復旧として同じ引数で再実行する場合もこの規則で安全
- **エラーハンドリング**: DB 失敗は gateway が非 0 を返し usecase が 1 回ログして presentation が 6 を返す
- **クラッシュ耐性**: 本 UPDATE は dispatcher(UC「両系成功時に速報比較依頼を作成する」)の判定・INSERT と同一トランザクション内で行う。COMMIT 前に落ちれば自系統列は NULL のまま(通知が届かなかったのと同じ)。COMMIT 後は自系統列と完了状況・依頼が揃って確定する。再通知は冪等
- **速報と確報のモデル分離**: rapid_runs のみ更新。final_* に触れない

## データモデル変更

### rapid_runs

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | 主キー(parallel_runs.run_id への FK) | 追加 |
| blue_status | string | SUCCEEDED / FAILED / NULL(未完了) | 追加 |
| green_status | string | SUCCEEDED / FAILED / NULL | 追加 |
| blue_artifact_uri | string | blue 成果物ディレクトリ URI | 追加 |
| green_artifact_uri | string | green 成果物ディレクトリ URI | 追加 |
| blue_completed_at | datetime | UTC。通知受信時刻 | 追加 |
| green_completed_at | datetime | UTC | 追加 |
| completion_status | string | PENDING / ONE_COMPLETED / BOTH_SUCCEEDED / ANY_FAILED / REQUEST_CREATED(次 UC で更新) | 追加 |

## ビジネスルール

- 完了通知の系統独立: サブコマンドが示す系統の列だけを更新する
- Runner Result 完備条件: exit_code 0 → SUCCEEDED、非 0 → FAILED
- 速報クロスチェック有効判定: 本コマンドは on のときだけ起動される前提。自身は feature flag を読まない
- 速報と確報のモデル分離

## ティア完了条件(BDD)

```gherkin
Feature: 速報クロスチェック runner へ完了通知を送信する - 速報クロスチェックティア

  Scenario: blue-completed で blue 列を更新する
    Given rapid_runs に run_id=20260830T113000Z-JOB001-3f9a1c2e, blue_status=NULL の行がある
    When `rapid-crosscheck-runner.sh blue-completed --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/blue` を実行する
    Then 終了コード 0 で stdout に `role=blue` と `slot_status=SUCCEEDED` が出て、rapid_runs.blue_status は SUCCEEDED、green_status は NULL のままである

  Scenario: exit_code が非 0 なら FAILED として登録する
    Given rapid_runs に run_id=20260830T113000Z-JOB001-3f9a1c2e, green_status=NULL の行がある
    When `rapid-crosscheck-runner.sh green-completed --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --exit-code 6 --artifact-uri file:///var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/green` を実行する
    Then 終了コード 0 で rapid_runs.green_status は FAILED である

  Scenario: 必須オプションが欠落している
    When `rapid-crosscheck-runner.sh blue-completed --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001` を実行する
    Then 終了コード 2 で stderr に `error: option required option=--exit-code` が出て、管理 DB は更新されない

  Scenario: rapid-crosscheck.env に RAPID_DB_CONN_REF が無い
    Given $RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env に RAPID_DB_CONN_REF の行が無い
    When `rapid-crosscheck-runner.sh blue-completed --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/blue` を実行する
    Then 終了コード 2 で stderr に `error: option required option=RAPID_DB_CONN_REF path: $RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` が出て、管理 DB へは接続しない

  Scenario: rapid-crosscheck.env が無い
    Given $RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env が存在しない
    When `rapid-crosscheck-runner.sh blue-completed --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/blue` を実行する
    Then 終了コード 2 で stderr に `error: config file not found path: $RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` が出て、管理 DB へは接続しない

  Scenario: rapid_runs に行が無い
    Given rapid_runs に run_id=20260830T113000Z-JOB002-aaaaaaaa の行が無い
    When `rapid-crosscheck-runner.sh blue-completed --run-id 20260830T113000Z-JOB002-aaaaaaaa --job-id JOB002 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000Z-JOB002-aaaaaaaa/blue` を実行する
    Then 終了コード 3 で stderr に `error: rapid run not found run_id=20260830T113000Z-JOB002-aaaaaaaa` が出る

  Scenario: 再通知は既存値を保持して 0 で終了する(先勝ち)
    Given rapid_runs に run_id=20260830T113000Z-JOB001-3f9a1c2e, blue_status=SUCCEEDED, blue_completed_at=2026-08-30T11:46:00Z の行がある
    When `rapid-crosscheck-runner.sh blue-completed --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --exit-code 3 --artifact-uri file:///var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/blue` を実行する
    Then 終了コード 0 で stderr は 0 行、rapid_runs.blue_status は SUCCEEDED、blue_completed_at は 2026-08-30T11:46:00Z のままである
```
