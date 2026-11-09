# 比較ツールでジョブ単位比較を実行して結果を登録する - 速報クロスチェックティア仕様

## 変更概要

`rapid-crosscheck-worker.sh` の usecase `execute_comparison` を追加する。domain `comparison_outcome`(終了コード対応表)、repository `rapid_request_mark_running` / `rapid_launch_command_resolve` / `rapid_request_save_result` / `parallel_run_mark_completed`、gateway `compare_tool_run`(比較ツール起動アダプタ)を追加する。worker が読む入力は管理 DB の依頼レコード(rapid_crosscheck_requests)と自身の設定ファイル(rapid-crosscheck.env)だけで、runner と worker は別ネットワークセグメントで動き worker はファイルパス(成果物 URI)を読めない。起動コマンドは rapid-crosscheck.env の `RAPID_COMPARE_COMMAND` を CLI 契約 `shared_rules.compare_command_argv` に従って空白区切りで引数の並び(argv)に分け、各引数の中でプレースホルダを依頼レコードの値へ置換して組み立て、引数の並びをそのまま渡して起動する(文字列をシェルに解釈させない。`eval` / `bash -c` / `sh -c` / 引用符なし展開を使わない)。置換の前に job_id / run_id / parameters の形式を検査し、不適合なら比較ツールを起動せず依頼を FAILED にする。比較ツールの非 0 は例外ではなく結果として扱う(CLR-002)。比較ツールの stdout / stderr / exit_code は依頼レコードの列へそのまま保存し、別レコードや成果物ファイルは作らない。

## コマンド契約

### rapid-crosscheck-worker.sh(比較実行部分)

- **書式**: claim UC と同一(`rapid-crosscheck-worker.sh [--once] [--worker-id <id>]`)
- **アクセス権**: ジョブスケジューラの定期起動または常駐。比較ツールは worker と同じ OS ユーザーで起動する

#### 引数・オプション

claim UC(`../速報比較依頼を claim する/tier-rapid-crosscheck.md`)と同じ。追加なし。

- **stdin**: なし
- **設定**: 速報クロスチェック設定(`RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env`)の `RAPID_COMPARE_COMMAND`(速報の比較ツール起動コマンド 1 行の文字列。プレースホルダ `{job_id}` 必須、`{run_id}` / `{params}` / `{blue_exit_code}` / `{green_exit_code}` 任意。契約 `cli-command-contract.yaml` の config_files.rapid-crosscheck.env が正。設定と検証は適用構成定義フローの設定 UC で行う)

## 出力契約

- **stdout**(`--once` で claim できたとき、claim UC の 4 行に続けて): `request_status=`(SUCCEEDED / FAILED / ABORTED。RUNNING 遷移 0 件のときは再 SELECT した現在の status をそのまま出す。ABORTED 以外(REQUESTED / 他 worker の CLAIMED / RUNNING / 別 worker が終端まで進めた SUCCEEDED / FAILED)は lease 失効で回収済み = WARN request not owned)/ `exit_code=`(整数 / `-`)
  - 起動失敗のケースの値: `request_status=FAILED` `exit_code=6`(worker は 6 で終了するが stdout の 2 行は出す)。終端 UPDATE 0 行(ABORTED 検出)→ `request_status=ABORTED` `exit_code=-`。RUNNING 遷移の条件付き UPDATE 0 行(abort-rapid-crosscheck で ABORTED 済み / lease 失効で別 worker に回収された)→ 比較を行わず、claim UC の 4 行に続けて `request_status=<再 SELECT した現在の status>` `exit_code=-` を出して終了コード 0(実行ログは再 SELECT した status が ABORTED なら `WARN comparison not started run_id=... worker_id=... reason=request_aborted`、それ以外は `WARN request not owned run_id=... status=...`。stderr には出さない。契約 rapid-crosscheck-worker.sh stdout と同文)
  - 契約 `cli-command-contract.yaml` の `rapid-crosscheck-worker.sh.stdout` が正
- **stderr**: `error: compare tool launch failed run_id=... command=...`、`error: management db update failed run_id=...`
- **終了コード**(worker 自身):
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 依頼を終端状態(SUCCEEDED / FAILED)まで処理した。比較 NG / 実行エラー(3 / 6)も 0。RUNNING 遷移の条件付き UPDATE(status='CLAIMED' AND worker_id=?)が 0 件(abort-rapid-crosscheck で ABORTED 済み / lease 失効で回収済み)で比較を開始せず終了した場合も 0(契約 rapid-crosscheck-worker.sh exit_codes[0] と同文) |
  | 6 | 実行エラー | 比較ツールの起動自体に失敗(exec 不可。依頼は FAILED で終端するが worker 側の実行エラーとして 6)、DB 更新失敗 |

- **実行ログ**(`RELAY_GATE_LOG_DIR/rapid-crosscheck-worker.sh.log`): `INFO compare started run_id=... command=...` / `INFO compare finished run_id=... exit_code=... duration_ms=...` / `WARN comparison not started run_id=... worker_id=... reason=request_aborted`(CLAIMED → RUNNING の条件付き UPDATE が 0 件で再 SELECT した status が ABORTED)/ `WARN request not owned run_id=... status=...`(同 0 件で status が ABORTED 以外 = lease 失効で回収済み)/ `WARN request already terminal run_id=... status=...` / `ERROR management db update failed run_id=...`。行形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {ローカル日時} {LEVEL} {message}`)に従い、情報「実行ログ」の属性「出力日時」はこのローカル時刻列に対応する

## イベント処理仕様

### rapid-crosscheck-requests(subscribe。claim 後の処理)

- **トリガー**: claim UC で CLAIMED を取得した直後(同一プロセス内)
- **入力チャネル**: 管理 DB `rapid_crosscheck_requests`(status=CLAIMED, worker_id=自分)
- **出力チャネル**: `rapid_crosscheck_requests`(自レコードの UPDATE。stdout / stderr / exit_code を保存)。hang-detector が FAILED を読んで通知する
- **AsyncAPI**: [asyncapi.yaml](../../../_cross-cutting/api/asyncapi.yaml) の `channels.rapid-crosscheck-requests`

#### 処理フロー

1. `UPDATE rapid_crosscheck_requests SET status='RUNNING', started_at=? WHERE run_id=? AND status='CLAIMED' AND worker_id=?`(条件付き UPDATE。条件「依頼中止可否判定」の worker 側の競合規則。arch LP-024)。更新件数 0 なら比較ツールを起動せず終了コード 0(手順 2 以降は行わない)。0 件のとき依頼を再 SELECT し、status=ABORTED(abort-rapid-crosscheck.sh で中止済み)なら実行ログ `WARN comparison not started run_id=... worker_id=... reason=request_aborted`、それ以外(lease 失効で回収済み: REQUESTED / 他 worker の CLAIMED / RUNNING / 別 worker が終端まで進めた SUCCEEDED / FAILED)は `WARN request not owned run_id=... status=...`。stderr には出さない。stdout は claim UC の 4 行に続けて `request_status=<再 SELECT した現在の status>` / `exit_code=-`
2. 依頼レコードの run_id / job_id / parameters / blue_exit_code / green_exit_code を SELECT する。置換の前に job_id(shared_rules.run_id.job_id_charset)/ run_id(shared_rules.run_id.format)/ parameters(JSON 配列として読めること)を検査し、いずれかに合わなければ比較ツールを起動せず、依頼を exit_code=6, error_summary=`invalid request value: <field>`, status=FAILED で終端し、stderr に `error: compare request value is invalid run_id=... field=<job_id|run_id|parameters>` を出して worker は 6 で終了する(手順 3 以降は行わない。別レコード・成果物ファイルは作らない)。検査を通ったら rapid-crosscheck.env の `RAPID_COMPARE_COMMAND`(1 行の文字列)を shared_rules.compare_command_argv に従って空白区切りで引数の並びに分け、各引数の中でプレースホルダ(`{job_id}` 必須、`{run_id}` / `{params}` / `{blue_exit_code}` / `{green_exit_code}` 任意。`{params}` は引数 1 つ全体のときだけ JSON 配列を 1 項目 1 引数へ展開)を依頼レコードの値で置換して起動コマンドの引数の並びを組み立てる。分割はシェルの記法(クォート・`$`・`;` 等)を解釈しない
3. 組み立てた引数の並びをそのまま渡して比較ツールを起動する(`"${argv[@]}"` 相当。`eval` / `bash -c` / `sh -c` / 引用符なしの変数展開による起動を禁止する。stdout / stderr を取り込む)。起動自体に失敗した(exec 不可で終了コードを得られない)ときは、依頼を exit_code=6, error_summary=`launch failed`, status=FAILED で終端し、stderr に `error: compare tool launch failed run_id=... command=...` を出して worker は 6 で終了する(手順 4 以降は行わない。別レコード・成果物ファイルは作らない)
4. domain で exit_code → request_status(0 → SUCCEEDED、非 0 → FAILED)。stdout / stderr は解析せずそのまま保持する
5. 依頼 UPDATE(status, exit_code, stdout, stderr, error_summary, completed_at。`WHERE run_id=? AND status='RUNNING' AND worker_id=?`)で比較ツールの stdout / stderr / exit_code を依頼レコードの列へ保存する(別レコード・成果物ファイルは作らない)。終端 UPDATE が 0 行(abort-rapid-crosscheck で ABORTED 済み等)なら終端結果を保存せず、実行ログに `WARN request already terminal run_id=... status=...` を残して終了コード 0
6. 依頼が終端(SUCCEEDED / FAILED)したら、`parallel_runs.parent_run_id IS NOT NULL` かつ当該 run_id の `slot_executions` 行が 0 件(速報比較依頼だけを新規作成したリラン由来 run。業務ジョブを再実行していない)のとき `UPDATE parallel_runs SET status='COMPLETED', completed_at=:now WHERE run_id=? AND status='RUNNING'` を発行する(状態「並行稼働実行」RUNNING → COMPLETED)。更新 0 行(通常 run / 既に ABORTED)は何もしない。実行ログ `INFO parallel_run status changed from=RUNNING to=COMPLETED run_id=...`(契約 rapid-crosscheck-worker.sh の文言)

#### エラーハンドリング

| エラー種別 | リトライ | DLQ | 説明 |
|-----------|---------|-----|------|
| 比較ツール exit_code 3 / 6 / その他非 0 | No | No | 結果として FAILED を保存。hang-detector が `rapid-crosscheck-error` の error メールを送る。再実行は background-rerun --role rapid-crosscheck |
| 比較ツール起動失敗(exec 不可) | No | No | 依頼 FAILED(exit_code=6, error_summary=launch failed)。別レコード・成果物ファイルは作らない。worker は 6 で終了 |
| 置換値の形式検査 NG(job_id / run_id / parameters が形式に合わない) | No | No | 比較ツールを起動しない。依頼 FAILED(exit_code=6, error_summary=`invalid request value: <field>`)。stderr `error: compare request value is invalid run_id=... field=...`。worker は 6 で終了 |
| RUNNING 遷移の条件付き UPDATE 0 行(abort-rapid-crosscheck で ABORTED 済み / lease 失効で回収済み) | No | No | 比較ツールを起動しない。実行ログ WARN(reason=request_aborted / request not owned)、worker は 0 |
| 終端 UPDATE 0 行(ABORTED 済み等) | No | No | 終端結果を保存しない。実行ログ WARN、worker は 0 |
| 管理 DB 更新失敗(結果保存) | Yes(同一起動内で 3 回、間隔 5 秒。仮採用) | No | 最終失敗は RUNNING のまま → hang-detector がハング疑い通知 → 運用者が abort → rerun |
| DLQ | — | なし | FAILED はハング検知が通知する |

## UC ロジック

- **バリデーション**: RAPID_COMPARE_COMMAND のコマンド部分(先頭の引数)の実行可能性・`{job_id}` の有無・`{params}` が引数 1 つ全体のときだけであることは `validate-config.sh --rapid-crosscheck` が事前検証する(設定と検証は適用構成定義フローの設定 UC で行う)。worker は env の値を shared_rules.compare_command_argv で引数の並びに分けて置換・起動するが、起動の直前に置換値(job_id / run_id / parameters)の形式を検査し、不適合なら起動せず FAILED にする(設定の検証とは別に、依頼レコードの値を信頼しない)
- **確認プロンプト**: なし
- **冪等性**: CLAIMED → RUNNING と RUNNING → 終端はいずれも status と worker_id を条件にした条件付き UPDATE。前者(`status='CLAIMED' AND worker_id=?`)が 0 件 = abort-rapid-crosscheck で中止済み、または lease 失効で回収済みで、比較を開始しない。後者(`status='RUNNING' AND worker_id=?`)が 0 件 = 比較中に中止済みで、終端結果を保存しない(ABORTED の依頼に比較結果が紐づく状態を作らない)。結果保存は 1 回だけ。リラン由来 run の COMPLETED 遷移も `status='RUNNING'` の条件付き UPDATE(既に COMPLETED / ABORTED なら 0 行で何もしない)
- **エラーハンドリング**: worker の終了コードは「比較ツールから結果を受け取れたか」で決める。比較ツールの非 0 は比較の結果であり依頼を FAILED で終端して 0。比較ツールの起動自体の失敗は依頼を FAILED(exit_code=6, error_summary=launch failed)で終端するが、worker 側の実行エラーとして 6 を返す。DB 更新失敗は終端できないため 6(ui-design.md の worker 規約)。比較ツールの非 0 は usecase でログ 1 回 + 結果保存。gateway の技術例外(exec 失敗・DB 失敗)は usecase で 1 回ログして presentation が 6
- **クラッシュ耐性**: RUNNING 移行後に worker が落ちると started_at 設定済みのため lease 解放されない(意図どおり)。依頼が RUNNING のまま終端しなければ hang-detector が経過時間でハング疑いを判定する。運用者は abort-rapid-crosscheck → background-rerun で復旧する
- **速報と確報のモデル分離**: final_* を触らない
- **速報結果の位置付け**: worker の終了コード・依頼状態はジョブスケジューラの業務ジョブ応答に影響しない

## データモデル変更

### rapid_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| job_id | string | 起動コマンドの `{job_id}` 置換に使う(参照) | 追加(参照) |
| parameters | text | 起動コマンドの `{params}` 置換に使う(参照) | 追加(参照) |
| blue_exit_code / green_exit_code | integer | 起動コマンドの `{blue_exit_code}` / `{green_exit_code}` 置換に使う(参照) | 追加(参照) |
| status | string | CLAIMED → RUNNING → SUCCEEDED / FAILED | 追加(更新) |
| started_at | datetime | RUNNING 遷移時(ホストのローカルタイムゾーン。タイムゾーン指示子なし。RDB のタイムスタンプ型に委ねる) | 追加(更新) |
| completed_at | datetime | 終端遷移時(同上) | 追加(更新) |
| exit_code | integer | 比較ツールの終了コード(起動失敗は 6) | 追加(更新) |
| stdout | text | 比較ツールの stdout 全文(そのまま保存。速報比較の結果はこの列で参照する) | 追加(更新) |
| stderr | text | 比較ツールの stderr 全文(そのまま保存) | 追加(更新) |
| error_summary | string | stderr 先頭 1 行(256 文字)または起動失敗の理由 `launch failed`。SUCCEEDED は NULL | 追加(更新) |

### parallel_runs(リラン由来 run のみ)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | string | RUNNING → COMPLETED(`parent_run_id IS NOT NULL` かつ当該 run_id の slot_executions が 0 件のとき、依頼終端時に条件付き UPDATE) | 追加(更新) |
| completed_at | datetime | COMPLETED 遷移時(ホストのローカルタイムゾーン。タイムゾーン指示子なし) | 追加(更新) |
| parent_run_id | string | 判定に参照(NULL なら本 UC は更新しない) | 追加(参照) |

## ビジネスルール

- 依頼状態遷移規則: CLAIMED → RUNNING(条件付き UPDATE)→ SUCCEEDED(0)/ FAILED(非 0・起動失敗)
- 依頼中止可否判定(worker 側の競合規則): CLAIMED → RUNNING の条件付き UPDATE が 0 件(abort-rapid-crosscheck で ABORTED 済み)なら比較を開始しない。運用者側の中止可否(速報 = REQUESTED / CLAIMED / RUNNING)は UC「実行を ABORTED へ遷移させる」
- 起動コマンドの解決: rapid-crosscheck.env の RAPID_COMPARE_COMMAND を引数の並びに分け、各引数の中でプレースホルダを依頼レコードの値で置換して起動する(`{job_id}` 必須。`{params}` は引数全体のときだけ 1 項目 1 引数。shared_rules.compare_command_argv)
- 起動方式(シェルに解釈させない): 分けた引数の並びをそのまま渡して起動する(`"${argv[@]}"` 相当)。クォート・`$`・`;` 等のシェル記法を解釈せず、`eval` / `bash -c` / `sh -c` / 引用符なし展開で起動しない。記号・空白を含むパラメータも 1 引数として届く
- 置換値の形式検査: 置換の前に job_id / run_id / parameters を検査し、不適合なら起動せず FAILED(exit_code=6, error_summary=`invalid request value: <field>`)
- 比較ツール終了コードの対応: 0=SUCCEEDED / 3・6・その他非 0=FAILED。値を変換しない
- 結果の保存条件: 比較ツールの stdout / stderr / exit_code を依頼レコードの列へそのまま保存する。起動失敗は依頼だけを FAILED(exit_code=6, error_summary=launch failed)で終端する。別レコード・成果物ファイルは作らない
- 速報結果の位置付け: 結果はジョブスケジューラ応答に影響しない

## ティア完了条件(BDD)

```gherkin
Feature: 比較ツールでジョブ単位比較を実行して結果を登録する - 速報クロスチェックティア

  Scenario: exit_code 0 で SUCCEEDED を保存する
    Given 依頼 run_id=20260830T113000-JOB001-3f9a1c2e, job_id=JOB001 が status=CLAIMED, worker_id=worker-01 で、rapid-crosscheck.env に RAPID_COMPARE_COMMAND が設定され、比較ツールが stdout に `result=OK rows=1000` を出して 0 を返す
    When worker-01 が execute_comparison を実行する
    Then 依頼は status=SUCCEEDED, exit_code=0, completed_at 設定済みで、stdout 列は `result=OK rows=1000` を含み、別レコードや成果物ファイルは作られない

  Scenario: 起動コマンドのプレースホルダを依頼レコードの値で置換する
    Given 依頼 run_id=20260830T113000-JOB001-3f9a1c2e, job_id=JOB001, parameters=`["--date","2026-08-30"]`, blue_exit_code=0, green_exit_code=0 が status=CLAIMED, worker_id=worker-01 で、rapid-crosscheck.env に `RAPID_COMPARE_COMMAND=/opt/compare/echo-args.sh {job_id} {run_id} {params} {blue_exit_code} {green_exit_code}` があり、比較ツールは受け取った引数を stdout に出して 0 を返す
    When worker-01 が execute_comparison を実行する
    Then 依頼の stdout 列は `JOB001`、`20260830T113000-JOB001-3f9a1c2e`、`["--date","2026-08-30"]`、`0`、`0` を順に含み、依頼は status=SUCCEEDED, exit_code=0 である

  Scenario: パラメータに記号や空白を含む値が入っても 1 引数として渡る
    Given 依頼 run_id=20260830T113000-JOB001-3f9a1c2e, job_id=JOB001, parameters=`["; touch /tmp/pwned","$(id)","a b c"]` が status=CLAIMED, worker_id=worker-01 で、rapid-crosscheck.env に `RAPID_COMPARE_COMMAND=/opt/compare/echo-args.sh --job {job_id} {params}` があり、比較ツールは受け取った引数を 1 行 1 引数で stdout に出して 0 を返す
    When worker-01 が execute_comparison を実行する
    Then 比較ツールは `--job`、`JOB001`、`; touch /tmp/pwned`、`$(id)`、`a b c` をそれぞれ 1 引数として受け取り、`/tmp/pwned` は作られず `$(id)` は展開されない(argv 配列で起動し eval / bash -c / sh -c を使わない)
    And 依頼は status=SUCCEEDED, exit_code=0 である

  Scenario: job_id が形式に合わないと比較ツールを起動せず FAILED にする
    Given 依頼 run_id=20260830T113000-JOB001-3f9a1c2e, job_id=`JOB 001; rm`(job_id_charset に合わない)が status=CLAIMED, worker_id=worker-01 で、RAPID_COMPARE_COMMAND が設定されている
    When worker-01 が execute_comparison を実行する
    Then 比較ツールは起動されず、依頼は status=FAILED, exit_code=6, error_summary=`invalid request value: job_id` になり、stderr に `error: compare request value is invalid run_id=20260830T113000-JOB001-3f9a1c2e field=job_id` が出て worker の終了コードは 6 である

  Scenario: parameters が JSON 配列でないと比較ツールを起動せず FAILED にする
    Given 依頼 run_id=20260830T113000-JOB001-3f9a1c2e, job_id=JOB001, parameters=`not-a-json-array` が status=CLAIMED, worker_id=worker-01 で、RAPID_COMPARE_COMMAND に `{params}` を含む
    When worker-01 が execute_comparison を実行する
    Then 比較ツールは起動されず、依頼は status=FAILED, exit_code=6, error_summary=`invalid request value: parameters` になり、stderr に `error: compare request value is invalid run_id=20260830T113000-JOB001-3f9a1c2e field=parameters` が出て worker の終了コードは 6 である

  Scenario: exit_code 3 で FAILED を保存する
    Given 同上で比較ツールが 3 を返し stdout に `result=NG mismatch=12`、stderr に `rows differ` を出す
    When worker-01 が execute_comparison を実行する
    Then 依頼は status=FAILED, exit_code=3、stdout 列は `result=NG mismatch=12`、stderr 列は `rows differ`、error_summary は `rows differ`、worker の終了コードは 0 である

  Scenario: exit_code 6 で FAILED を保存する
    Given 同上で比較ツールが 6 を返し stderr に `connection refused` を出す
    When worker-01 が execute_comparison を実行する
    Then 依頼は status=FAILED, exit_code=6, error_summary=`connection refused`、stderr 列は `connection refused` である

  Scenario: abort-rapid-crosscheck で ABORTED になった CLAIMED の依頼は RUNNING への条件付き UPDATE が 0 件で比較を開始しない
    Given 依頼 run_id=20260830T113000-JOB001-3f9a1c2e, job_id=JOB001 を worker-01 が claim(status=CLAIMED, worker_id=worker-01, started_at=NULL)した後、比較開始前に abort-rapid-crosscheck で status=ABORTED になっている
    When worker-01 が execute_comparison(run_id) を実行する
    Then `UPDATE rapid_crosscheck_requests SET status='RUNNING', started_at=? WHERE run_id=? AND status='CLAIMED' AND worker_id='worker-01'` の更新件数は 0 で、比較ツールは起動されない
    And 依頼は status=ABORTED, started_at=NULL のままで、stdout は claim の 4 行に続けて `request_status=ABORTED`、`exit_code=-` が出て、stderr には何も出ない
    And 実行ログに `WARN comparison not started run_id=20260830T113000-JOB001-3f9a1c2e worker_id=worker-01 reason=request_aborted` が残り、worker-01 の終了コードは 0 である

  Scenario: 他 worker に奪われた依頼は処理しない
    Given 依頼 run_id=20260830T113000-JOB001-3f9a1c2e が status=CLAIMED, worker_id=worker-02 である
    When worker-01 が execute_comparison(run_id) を実行する
    Then RUNNING への UPDATE は 0 行で、比較ツールは起動されず、stdout は claim の 4 行(`run_id=` / `job_id=` / `worker_id=` / `lease_until=`)に続けて `request_status=CLAIMED`(再 SELECT した現在の status)、`exit_code=-` が出て、実行ログに `WARN request not owned run_id=20260830T113000-JOB001-3f9a1c2e status=CLAIMED` が残り、worker-01 の終了コードは 0 である

  Scenario: 比較ツールの起動に失敗しても別レコードや成果物ファイルを作らない
    Given 依頼 run_id=20260830T113000-JOB001-3f9a1c2e, job_id=JOB001 が status=CLAIMED, worker_id=worker-01 で、RAPID_COMPARE_COMMAND のコマンド部分に実行権限が無い
    When worker-01 が execute_comparison を実行する
    Then 依頼は status=FAILED, exit_code=6, error_summary=`launch failed`、別レコードや成果物ファイルは作られず、stdout に `request_status=FAILED`、`exit_code=6` が出て、worker の終了コードは 6 である

  Scenario: 終端 UPDATE が 0 行なら終端結果を保存しない
    Given 依頼 run_id=20260830T113000-JOB001-3f9a1c2e が status=ABORTED(worker-01 の比較中に abort-rapid-crosscheck で中止)である
    When 比較ツールが 0 で終了し worker-01 が結果保存を実行する
    Then 終端 UPDATE(`WHERE status='RUNNING' AND worker_id=?`)は 0 行で、依頼は ABORTED のまま exit_code / stdout / stderr 列は保存されず、stdout に `request_status=ABORTED`、`exit_code=-` が出て、実行ログに `WARN request already terminal run_id=20260830T113000-JOB001-3f9a1c2e status=ABORTED` が残り、worker の終了コードは 0 である

  Scenario: 速報比較依頼だけのリラン由来 run を依頼終端で COMPLETED にする
    Given parallel_runs に run_id=20260830T150000-JOB001-5e5e5e5e, parent_run_id=20260830T113000-JOB001-3f9a1c2e, status=RUNNING の行があり、同 run_id の slot_executions 行は 0 件で、依頼 run_id=20260830T150000-JOB001-5e5e5e5e が status=CLAIMED, worker_id=worker-01 である
    When worker-01 が execute_comparison を実行し比較ツールが 3 を返す
    Then 依頼は status=FAILED、parallel_runs の run_id=20260830T150000-JOB001-5e5e5e5e は status=COMPLETED になり、実行ログに `INFO parallel_run status changed from=RUNNING to=COMPLETED run_id=20260830T150000-JOB001-5e5e5e5e` が残る

  Scenario: 通常 run(slot_executions あり)の parallel_run は worker が更新しない
    Given parallel_runs に run_id=20260830T113000-JOB001-3f9a1c2e, parent_run_id=NULL, status=RUNNING の行と同 run_id の slot_executions 行が 2 件あり、依頼が status=CLAIMED, worker_id=worker-01 である
    When worker-01 が execute_comparison を実行し比較ツールが 0 を返す
    Then 依頼は status=SUCCEEDED になるが、parallel_runs の status は RUNNING のまま(COMPLETED への遷移は facade の中継完了が担う)である
```
