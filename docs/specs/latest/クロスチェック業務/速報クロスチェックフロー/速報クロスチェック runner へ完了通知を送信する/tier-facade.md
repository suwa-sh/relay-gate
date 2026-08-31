# 速報クロスチェック runner へ完了通知を送信する - facade / slot runner ティア仕様(送信側)

## 変更概要

slot runner(`$BLUE_RUNNER` / `$GREEN_RUNNER`)の usecase `publish_runner_result` に、Runner Result 公開後の完了通知ステップを追加する。gateway に `notify_slot_completed`(rapid-crosscheck-runner 呼び出しアダプタ)を追加する。`RAPID_CROSSCHECK_MODE=off` のときは gateway を呼ばない(LP-004)。

## コマンド契約

### 内部呼び出し: rapid-crosscheck-runner.sh {blue|green}-completed(送信側の使用契約)

- **書式**: `<relay-gate 配置ディレクトリ>/rapid-crosscheck-runner.sh <role>-completed --run-id <run_id> --job-id <job_id> --exit-code <n> --artifact-uri <uri>`
- **アクセス権**: slot runner からの内部呼び出しのみ。運用者は直接起動しない

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

- **stdout / stderr**: slot runner は通知先の stdout / stderr を自身の stdout / stderr に流さない(実行ログに記録する)。stdout.log / stderr.log / exitcode.txt は実装の出力のまま変更しない。通知失敗時も stderr.log へは追記しない(foreground slot では facade が stderr.log をジョブスケジューラへ中継するため、追記は「速報クロスチェックの失敗は foreground の応答を変更しない」に反する。また exitcode.txt は 3 ファイル契約の完了マーカーとして最後に公開済みで、公開後の変更は認めない)。通知失敗は実行ログの `WARN completion notice failed run_id=... role=... exit_code=N` にのみ残す
- **終了コード**: slot runner の終了コードは `exitcode.txt` と一致させる。通知の成否は反映しない
  | コード | 意味 | 条件 |
  |-------|------|------|
  | exitcode.txt の値 | 実装の結果 | 通知の成否にかかわらず同じ |

- **実行ログ**(`RELAY_GATE_LOG_DIR/<runner>.log`): `INFO notify started role=green run_id=... exit_code=0` / `INFO notify finished exit_code=0 duration_ms=...` / `WARN completion notice failed run_id=... role=green exit_code=6`
- **実行ログの行形式**: `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {UTC 出力日時} {LEVEL} {message}`)に従う。情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する

## UC ロジック

- **バリデーション**: `RAPID_CROSSCHECK_MODE` は on / off のみ(それ以外は runner 起動時の設定検証で終了コード 2。UC「feature flag を設定する」)。配置ディレクトリ(runner 実体が自身のパスから導出)の `rapid-crosscheck-runner.sh` が実行可能でないときは WARN を残して通知をスキップする(Runner Result は変えない)
- **確認プロンプト**: なし
- **冪等性**: 通知は 1 回だけ送る。受信側の条件付き UPDATE(先勝ち。既に値があれば更新せず 0)で二重通知・運用者の手動再実行は無害
- **エラーハンドリング**: 通知先の非 0 終了は技術例外として gateway が非 0 を返すが、usecase は WARN を 1 回ログに出して正常継続する(CLR-001。速報結果の位置付け)
- **クラッシュ耐性**: 通知前に落ちた場合、exitcode.txt は公開済みで rapid_runs の自系統列は NULL のまま。hang-detector が exitcode.txt から実行エラー / 正常終了を判定でき、rapid_runs は「片系未完了」として残る。通知後に落ちても DB 側は更新済みで副作用は無い
- **通知失敗時の復旧**: 通知(rapid-crosscheck-runner の非 0 終了、または通知前のクラッシュ)が失敗しても slot runner は自動再通知しない。実行ログに `WARN completion notice failed run_id=... role=... exit_code=N` を 1 行残し(Runner Result の 3 ファイルは変更しない)、自身の終了コードは実装スクリプトの exitcode(Runner Result が正本)のまま変えない。復旧手段は「運用者が同じ引数で `rapid-crosscheck-runner.sh <role>-completed --run-id ... --job-id ... --exit-code <exitcode.txt の値> --artifact-uri ...` を再実行する」(受信側は先勝ちの冪等。既に登録済みなら既存値を保持して 0)。background-rerun / ジョブスケジューラの再実行は新しい run_id の実行になるため通知失敗の復旧手段ではない。通知失敗の自動検知はスコープ外(制約: exitcode.txt=0 の slot は hang-detector が正常終了として扱うため、通知失敗は自動では検知されない)
- **速報クロスチェック有効判定**: off のとき usecase は gateway も RDB repository も呼ばない。管理 DB の接続設定ファイルが無くても動く

## データモデル変更

該当なし(送信側はファイルを読むだけ。書き込みは受信側)

### 参照ファイル

| ファイル | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| `facade/<run_id>/<role>/exitcode.txt` | 数値 1 行 | `--exit-code` の値 | 追加(参照) |
| feature flag 設定(env) `RAPID_CROSSCHECK_MODE` | on / off | 通知の有無 | 追加(参照) |

## ビジネスルール

- 速報クロスチェック有効判定: on のときのみ通知する
- 完了通知の系統独立: 自系統の公開 function だけを起動し、相手側の状態や依頼の要否を判断しない
- 速報結果の位置付け: 通知の失敗を slot runner の終了コード・Runner Result に反映しない
- Runner Result 完備条件: 3 ファイル公開後に通知する。`--exit-code` は exitcode.txt と一致

## ティア完了条件(BDD)

```gherkin
Feature: 速報クロスチェック runner へ完了通知を送信する - facade / slot runner ティア

  Scenario: on のとき自系統の完了通知を起動する
    Given RAPID_CROSSCHECK_MODE=on で run_id=20260830T113000Z-JOB001-3f9a1c2e, role=green, exitcode.txt=`0`
    When green runner が publish_runner_result を実行する
    Then `rapid-crosscheck-runner.sh green-completed --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/green` が 1 回起動され、blue-completed は起動されない

  Scenario: off のとき通知を起動しない
    Given RAPID_CROSSCHECK_MODE=off で role=blue, exitcode.txt=`0`
    When blue runner が publish_runner_result を実行する
    Then rapid-crosscheck-runner.sh は起動されず、blue runner は終了コード 0 で終了する

  Scenario: 通知先の失敗を runner の終了コードに反映しない
    Given RAPID_CROSSCHECK_MODE=on で rapid-crosscheck-runner.sh が終了コード 6 を返す
    And exitcode.txt=`0`
    When blue runner が publish_runner_result を実行する
    Then blue runner の終了コードは 0 で、実行ログに `WARN completion notice failed run_id=20260830T113000Z-JOB001-3f9a1c2e role=blue exit_code=6` が 1 行残り、facade/<run_id>/blue/ の stdout.log / stderr.log / exitcode.txt は通知前と同一(stderr.log への追記なし)で exitcode.txt は `0` のままである

  Scenario: 通知失敗を運用者が同じ引数の再実行で復旧する
    Given run_id=20260830T113000Z-JOB001-3f9a1c2e の blue の通知が終了コード 6 で失敗し、rapid_runs.blue_status が NULL である
    When 運用者が `rapid-crosscheck-runner.sh blue-completed --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/blue` を再実行する
    Then rapid-crosscheck-runner.sh は終了コード 0 で rapid_runs.blue_status は `SUCCEEDED` になり、blue runner は再起動されない
```
