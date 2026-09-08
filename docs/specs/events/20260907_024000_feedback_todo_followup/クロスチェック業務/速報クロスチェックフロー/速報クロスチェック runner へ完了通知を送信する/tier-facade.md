# 速報クロスチェック runner へ完了通知を送信する - facade / slot runner ティア仕様(送信側)

## 変更概要

slot runner(`$BLUE_RUNNER` / `$GREEN_RUNNER`)の usecase `publish_runner_result` に、Runner Result 公開後の完了通知ステップを追加する。gateway に `notify_slot_completed`(`RAPID_CROSSCHECK_RUNNER` 呼び出しアダプタ)を追加する。`RAPID_CROSSCHECK_MODE=off` のときは gateway を呼ばない(LP-004)。runner は feature-flag.env を読まず、facade.sh / background-rerun.sh が feature-flag.env から読んだ `RAPID_CROSSCHECK_MODE` と(off 以外のとき)`RAPID_CROSSCHECK_RUNNER` を環境変数で受け取る。

## コマンド契約

### 内部呼び出し: $RAPID_CROSSCHECK_RUNNER {blue|green}-completed(送信側の使用契約)

- **書式**: `$RAPID_CROSSCHECK_RUNNER <role>-completed --run-id <run_id> --job-id <job_id> --exit-code <n> --artifact-uri <uri>`(`RAPID_CROSSCHECK_RUNNER` は feature flag の速報クロスチェック runner 実体の絶対パス。`$RELAY_GATE_HOME` 等の固定パス解決は行わない)
- **アクセス権**: slot runner からの内部呼び出しのみ。運用者は直接起動しない(通知失敗の復旧時を除く。条件「完了通知失敗の扱い」)

#### 引数・オプション(送信側が組み立てる値)

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `<role>-completed` | enum(blue-completed / green-completed) | Yes | — | 自系統の role から決める。相手側のサブコマンドは起動しない |
| `--run-id` | string | Yes | — | runner 起動時に `--run-id` で受け取った値 |
| `--job-id` | string | Yes | — | runner 起動時の `--job-id` |
| `--exit-code` | integer | Yes | — | 公開済み `exitcode.txt` の値(数値 1 行) |
| `--artifact-uri` | string | Yes | — | `file://<RELAY_GATE_ARTIFACT_ROOT>/facade/<run_id>/<role>` |

- **stdin**: なし

## 出力契約

- **stdout / stderr**: slot runner は通知先の stdout / stderr を自身の stdout / stderr に流さない(実行ログに記録する)。stdout.log / stderr.log / exitcode.txt は実装の出力のまま変更しない。通知失敗時も stderr.log へは追記しない(foreground slot では facade が stderr.log をジョブスケジューラへ中継するため、追記は「速報クロスチェックの失敗は foreground の応答を変更しない」に反する。また exitcode.txt は 3 ファイル契約の完了マーカーとして最後に公開済みで、公開後の変更は認めない)。通知失敗は実行ログの `WARN completion notice failed run_id=... role=... runner=<RAPID_CROSSCHECK_RUNNER> exit_code=N` にのみ残す(条件「完了通知失敗の扱い」)
- **終了コード**: slot runner の終了コードは `exitcode.txt` と一致させる。通知の成否は反映しない
  | コード | 意味 | 条件 |
  |-------|------|------|
  | exitcode.txt の値 | 実装の結果 | 通知の成否にかかわらず同じ |

- **実行ログ**(`RELAY_GATE_LOG_DIR/<runner>.log`): `INFO notify started role=green run_id=... runner=<RAPID_CROSSCHECK_RUNNER>` / `INFO notify finished run_id=... role=green exit_code=0 duration_ms=...` / `WARN completion notice failed run_id=... role=green runner=<RAPID_CROSSCHECK_RUNNER> exit_code=6`
- **実行ログの行形式**: `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {ローカル日時} {LEVEL} {message}`)に従う。情報「実行ログ」の属性「出力日時」はこのローカル時刻列に対応する

## UC ロジック

- **バリデーション**: 環境変数 `RAPID_CROSSCHECK_MODE` は foreground / background / off のみ(feature-flag.env の検証は facade / background-rerun の起動時に行い、列挙外は終了コード 2。UC「feature flag を設定する」)。判定は「off か off 以外か」だけで、foreground と background を区別しない。`RAPID_CROSSCHECK_RUNNER` の存在・実行可能性も同じ検証で確認済み。runner 起動後に `RAPID_CROSSCHECK_RUNNER` を起動できなかった場合は通知失敗として扱い、WARN を残して Runner Result は変えない(条件「完了通知失敗の扱い」)
- **確認プロンプト**: なし
- **冪等性**: 通知は 1 回だけ送る。受信側の条件付き UPDATE(先勝ち。既に値があれば更新せず 0)で二重通知・運用者の手動再実行は無害
- **エラーハンドリング**: 通知先の非 0 終了は技術例外として gateway が非 0 を返すが、usecase は WARN を 1 回ログに出して正常継続する(CLR-001。速報結果の位置付け)
- **クラッシュ耐性**: 通知前に落ちた場合、exitcode.txt は公開済みで rapid_runs の自系統列は NULL のまま。hang-detector が exitcode.txt から実行エラー / 正常終了を判定でき、rapid_runs は「片系未完了」として残る。通知後に落ちても DB 側は更新済みで副作用は無い
- **通知失敗時の復旧(条件「完了通知失敗の扱い」)**: 通知(RAPID_CROSSCHECK_RUNNER の非 0 終了、または通知前のクラッシュ)が失敗しても slot runner は自動再通知しない。実行ログに `WARN completion notice failed run_id=... role=... runner=<RAPID_CROSSCHECK_RUNNER> exit_code=N` を 1 行残し(Runner Result の 3 ファイルは変更しない)、自身の終了コードは実装スクリプトの exitcode(Runner Result が正本)のまま変えない。復旧手段は「運用者が速報クロスチェック runner(RAPID_CROSSCHECK_RUNNER)を同一引数 `<role>-completed --run-id ... --job-id ... --exit-code <exitcode.txt の値> --artifact-uri ...` で再実行する」(受信側は先勝ちの冪等。完了結果は一度だけ登録され、既に登録済みなら既存値を保持して 0)。background-rerun / ジョブスケジューラの再実行は新しい run_id の実行になるため通知失敗の復旧手段ではない。通知失敗は自動検知しない(exitcode.txt=0 の slot は hang-detector が正常終了として扱う)
- **速報クロスチェック有効判定**: off のとき usecase は gateway も RDB repository も呼ばない。管理 DB の接続設定ファイルが無くても動く。off 以外(foreground / background)は同じ挙動で通知する
- **完了通知の系統独立(自 slot の中止状態を判断しない)**: usecase は `aborted.txt` の有無を読まず、判断もしない。運用者の abort-blue / abort-green で aborted.txt が公開された後に実装スクリプトが走り切って exitcode.txt を公開した場合も、通常どおり自系統の完了通知を送る。比較依頼の要否(中止済み run では作成しない)は受信側の dispatcher が parallel_runs.status で判断する(条件「中止済み run の比較依頼作成除外」。UC「両系成功時に速報比較依頼を作成する」)

## データモデル変更

該当なし(送信側はファイルを読むだけ。書き込みは受信側)

### 参照ファイル

| ファイル | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| `facade/<run_id>/<role>/exitcode.txt` | 数値 1 行 | `--exit-code` の値 | 追加(参照) |
| 環境変数 `RAPID_CROSSCHECK_MODE`(facade / background-rerun が feature-flag.env から渡す) | foreground / background / off | 通知の有無(off か off 以外か) | 追加(参照) |
| 環境変数 `RAPID_CROSSCHECK_RUNNER`(同上。off 以外のときだけ渡される) | 絶対パス | 完了通知の送信先実体 | 追加(参照) |

## ビジネスルール

- 速報クロスチェック有効判定: off 以外(foreground / background)のときのみ通知する
- 完了通知の系統独立: 自系統の公開 function だけを起動し、相手側の状態や依頼の要否を判断しない。自 slot の中止状態(aborted.txt の有無)も判断せず、中止後に実装が走り切って exitcode.txt を公開した場合も通常どおり通知する
- 完了通知失敗の扱い: 送信失敗は自動検知せず、実行ログに警告を残して Runner Result と終了コードを変更しない。復旧は運用者の同一引数再実行
- 速報結果の位置付け: 通知の失敗を slot runner の終了コード・Runner Result に反映しない
- Runner Result 完備条件: 3 ファイル公開後に通知する。`--exit-code` は exitcode.txt と一致

## ティア完了条件(BDD)

```gherkin
Feature: 速報クロスチェック runner へ完了通知を送信する - facade / slot runner ティア

  Scenario: off 以外(background)のとき自系統の完了通知を起動する
    Given 環境変数 RAPID_CROSSCHECK_MODE=background RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh で run_id=20260830T113000-JOB001-3f9a1c2e, role=green, exitcode.txt=`0`
    When green runner が publish_runner_result を実行する
    Then `/opt/relay-gate/rapid-crosscheck-runner.sh green-completed --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/green` が 1 回起動され、blue-completed は起動されない

  Scenario: foreground でも background と同じく完了通知を起動する
    Given 環境変数 RAPID_CROSSCHECK_MODE=foreground RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh で role=green, exitcode.txt=`0`
    When green runner が publish_runner_result を実行する
    Then `/opt/relay-gate/rapid-crosscheck-runner.sh green-completed ...` が 1 回起動される(background のときと同じ)

  Scenario: off のとき通知を起動しない
    Given 環境変数 RAPID_CROSSCHECK_MODE=off(RAPID_CROSSCHECK_RUNNER は渡されない)で role=blue, exitcode.txt=`0`
    When blue runner が publish_runner_result を実行する
    Then 速報クロスチェック runner は起動されず、blue runner は終了コード 0 で終了する

  Scenario: aborted.txt がある slot でも自系統の完了通知を起動する(完了通知の系統独立)
    Given 環境変数 RAPID_CROSSCHECK_MODE=background RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh で run_id=20260830T113000-JOB001-3f9a1c2e, role=green
    And facade/20260830T113000-JOB001-3f9a1c2e/green/aborted.txt が公開済みで、実装スクリプトが走り切り exitcode.txt=`0` を公開した
    When green runner が publish_runner_result を実行する
    Then aborted.txt は読まれず、`/opt/relay-gate/rapid-crosscheck-runner.sh green-completed --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/green` が 1 回起動され、green runner は比較依頼の要否を判断しない

  Scenario: 通知先の失敗を runner の終了コードに反映しない(完了通知失敗の扱い)
    Given RAPID_CROSSCHECK_MODE=background RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh で速報クロスチェック runner が終了コード 6 を返す
    And exitcode.txt=`0`
    When blue runner が publish_runner_result を実行する
    Then blue runner の終了コードは 0 で、実行ログに `WARN completion notice failed run_id=20260830T113000-JOB001-3f9a1c2e role=blue runner=/opt/relay-gate/rapid-crosscheck-runner.sh exit_code=6` が 1 行残り、facade/<run_id>/blue/ の stdout.log / stderr.log / exitcode.txt は通知前と同一(stderr.log への追記なし)で exitcode.txt は `0` のままである

  Scenario: 通知失敗を運用者が同じ引数の再実行で復旧する
    Given run_id=20260830T113000-JOB001-3f9a1c2e の blue の通知が終了コード 6 で失敗し、rapid_runs.blue_status が NULL である
    When 運用者が `/opt/relay-gate/rapid-crosscheck-runner.sh blue-completed --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/blue` を再実行する
    Then 速報クロスチェック runner は終了コード 0 で rapid_runs.blue_status は `SUCCEEDED` になり、blue runner は再起動されない
```
