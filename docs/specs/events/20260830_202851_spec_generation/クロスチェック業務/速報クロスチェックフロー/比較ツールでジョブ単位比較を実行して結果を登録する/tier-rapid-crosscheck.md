# 比較ツールでジョブ単位比較を実行して結果を登録する - 速報クロスチェックティア仕様

## 変更概要

`rapid-crosscheck-worker.sh` の usecase `execute_comparison` を追加する。domain `comparison_outcome`(終了コード対応表)、repository `crosscheck_job_map_find` / `rapid_request_mark_running` / `rapid_request_save_result` / `comparison_result_insert`、gateway `compare_tool_run`(比較ツール起動アダプタ)/ `artifact_write`(FS アダプタ)を追加する。比較ツールの非 0 は例外ではなく結果として扱う(CLR-002)。

## コマンド契約

### rapid-crosscheck-worker.sh(比較実行部分)

- **書式**: claim UC と同一(`rapid-crosscheck-worker.sh [--once] [--worker-id <id>]`)
- **アクセス権**: ジョブスケジューラの定期起動または常駐。比較ツールは worker と同じ OS ユーザーで起動する

#### 引数・オプション

claim UC(`../速報比較依頼を claim する/tier-rapid-crosscheck.md`)と同じ。追加なし。

- **stdin**: なし
- **設定**: クロスチェックジョブマップ TSV(`RELAY_GATE_CONFIG_DIR/crosscheck-job-map.tsv`。列定義は UC「クロスチェックのジョブマップと比較定義を定義する」)、`RELAY_GATE_ARTIFACT_ROOT`

## 出力契約

- **stdout**(`--once` で claim できたとき、claim UC の 4 行に続けて): `request_status=`(SUCCEEDED / FAILED / ABORTED)/ `result_status=`(OK / NG / FAILED / `-`)/ `exit_code=` / `comparison_result_id=`(8 hex / `-`)/ `artifact_dir: <絶対パス>`
  - comparison_results を作らないケースの値: 比較定義なし → `request_status=FAILED` `result_status=-` `exit_code=6` `comparison_result_id=-`。比較ツール起動失敗 → 同上(worker は 6 で終了するが stdout の 5 行は出す)。終端 UPDATE 0 行(ABORTED 検出)→ `request_status=ABORTED` `result_status=-` `exit_code=-` `comparison_result_id=-`(比較ツールの終了コードは exitcode.txt にのみ残す)。RUNNING 遷移の UPDATE 0 行(lease 失効で別 worker に回収された / 中止済み)→ 比較を行わず、claim UC の 4 行に続けて `request_status=<再 SELECT した現在の status>` `result_status=-` `exit_code=-` `comparison_result_id=-` `artifact_dir: -` を出して終了コード 0(実行ログ `WARN request not owned run_id=... status=...`。契約 rapid-crosscheck-worker.sh stdout と同文)
  - 契約 `cli-command-contract.yaml` の `rapid-crosscheck-worker.sh.stdout` が正
- **stderr**: `error: compare tool launch failed run_id=... command=...`、`error: management db update failed run_id=...`
- **終了コード**(worker 自身):
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 依頼を終端状態(SUCCEEDED / FAILED)まで処理した。比較 NG / 実行エラー(3 / 6)も 0 |
  | 6 | 実行エラー | 比較ツールの起動自体に失敗(exec 不可。依頼は FAILED で終端するが worker 側の実行エラーとして 6)、成果物 dir 作成不可、DB 更新失敗 |

- **成果物**(`<RELAY_GATE_ARTIFACT_ROOT>/facade/<run_id>/rapid-crosscheck/`): `started-at.txt`(UTC ISO 8601)、`stdout.log`、`stderr.log`、`exitcode.txt`(数値 1 行)。`.tmp` → `mv`
- **実行ログ**(`RELAY_GATE_LOG_DIR/rapid-crosscheck-worker.sh.log`): `INFO compare started run_id=... command=...` / `INFO compare finished run_id=... exit_code=... duration_ms=...` / `WARN request already terminal run_id=... status=...` / `ERROR management db update failed run_id=...`。行形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {UTC 出力日時} {LEVEL} {message}`)に従い、情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する

## イベント処理仕様

### rapid-crosscheck-requests(subscribe。claim 後の処理)

- **トリガー**: claim UC で CLAIMED を取得した直後(同一プロセス内)
- **入力チャネル**: 管理 DB `rapid_crosscheck_requests`(status=CLAIMED, worker_id=自分)
- **出力チャネル**: `comparison_results`(INSERT)。hang-detector が FAILED / NG を読んで通知する
- **AsyncAPI**: [asyncapi.yaml](../../../_cross-cutting/api/asyncapi.yaml) の `channels.rapid-crosscheck-requests`

#### 処理フロー

1. `UPDATE rapid_crosscheck_requests SET status='RUNNING', started_at=? WHERE run_id=? AND status='CLAIMED' AND worker_id=?`(0 行なら lease 失効で別 worker に回収された / 中止済み。比較を行わず終了コード 0。stdout は claim UC の 4 行に続けて `request_status=<再 SELECT した現在の status>` / `result_status=-` / `exit_code=-` / `comparison_result_id=-` / `artifact_dir: -`。実行ログ `WARN request not owned run_id=... status=...`)
2. クロスチェックジョブマップ TSV から job_id 行を読む。無ければ成果物 dir に started-at.txt / stdout.log(空)/ stderr.log(`comparison definition not found job_id=...`)/ exitcode.txt(`6`)を .tmp → mv で出してから手順 7 へ(exit_code=6, error_summary=`comparison definition not found job_id=...`, status=FAILED)。このとき comparison_results は INSERT しない(comparison_type を与える定義行が無い)
3. rapid_runs から blue_artifact_uri / green_artifact_uri を読む
4. 成果物 dir を作り `started-at.txt` を出す
5. 比較ツールを起動(stdout / stderr を `.tmp` ファイルへ)。終了後 `exitcode.txt.tmp` を書き、3 ファイルを `mv`。起動自体に失敗した(exec 不可で終了コードを得られない)ときは stdout.log(空)/ stderr.log(起動失敗の理由)/ exitcode.txt(`6`)を公開し、依頼を exit_code=6, error_summary=`launch failed`, status=FAILED で終端する。comparison_results は INSERT せず、stderr に `error: compare tool launch failed run_id=... command=...` を出して worker は 6 で終了する(手順 6 以降は行わない)
6. domain で exit_code → (request_status, result_status)。stdout から difference_count / report_uri を抽出
7. 1 トランザクションで依頼 UPDATE(status, exit_code, stdout, stderr, error_summary, completed_at。`WHERE run_id=? AND status='RUNNING' AND worker_id=?`)と comparison_results INSERT(比較ツールを起動して終了コードを得たときのみ。比較定義なし・起動失敗では INSERT しない)。終端 UPDATE が 0 行(abort-rapid-crosscheck で ABORTED 済み等)なら comparison_results を INSERT せず ROLLBACK し、実行ログに `WARN request already terminal run_id=... status=...` を残して終了コード 0(成果物ファイルは残す)

#### エラーハンドリング

| エラー種別 | リトライ | DLQ | 説明 |
|-----------|---------|-----|------|
| 比較ツール exit_code 3 / 6 / その他非 0 | No | No | 結果として FAILED を保存。hang-detector が `rapid-crosscheck-error` の error メールを送る。再実行は background-rerun --role rapid-crosscheck |
| 比較ツール起動失敗(exec 不可) | No | No | 依頼 FAILED(exit_code=6, error_summary=launch failed)。comparison_results は INSERT しない(終了コードを得ていない)。worker は 6 で終了 |
| 比較定義なし | No | No | 依頼 FAILED(exit_code=6, error_summary=`comparison definition not found job_id=...`)。comparison_results は INSERT しない。設定修正後に background-rerun |
| 終端 UPDATE 0 行(ABORTED 済み等) | No | No | comparison_results を INSERT せず ROLLBACK。実行ログ WARN、worker は 0 |
| 管理 DB 更新失敗(結果保存) | Yes(同一起動内で 3 回、間隔 5 秒。仮採用) | No | 成果物ファイルは残る。最終失敗は RUNNING のまま → hang-detector がハング疑い通知 → 運用者が abort → rerun |
| 成果物 dir 書き込み不可 | No | No | 依頼 FAILED(exit_code=6)を試み、worker は 6 |
| DLQ | — | なし | FAILED はハング検知が通知する |

## UC ロジック

- **バリデーション**: 比較定義行の列数・compare_command の実行可能性は `validate-config.sh --crosscheck-job-map` が事前検証する。worker は行の有無だけを見る
- **確認プロンプト**: なし
- **冪等性**: RUNNING 遷移は `status='CLAIMED' AND worker_id=?` の条件付き UPDATE。結果保存は `status='RUNNING' AND worker_id=?` 条件で 1 回だけ。この UPDATE が 0 行なら comparison_results を INSERT しない(ABORTED の依頼に比較結果が紐づく状態を作らない)。comparison_results は依頼 1 件につき本 UC で最大 1 行(比較定義なし・起動失敗・終端 UPDATE 0 行は 0 行。再作成は新 run_id で行う)
- **エラーハンドリング**: worker の終了コードは「比較ツールから結果を受け取れたか」で決める。比較ツールの非 0 と比較定義なしは比較の結果(または設定の欠落)であり依頼を FAILED で終端して 0。比較ツールの起動自体の失敗は依頼を FAILED(exit_code=6, error_summary=launch failed)で終端するが、worker 側の実行エラーとして 6 を返す。成果物 dir 作成不可・DB 更新失敗は終端できないため 6(ui-design.md の worker 規約)。比較ツールの非 0 は usecase でログ 1 回 + 結果保存。gateway の技術例外(exec 失敗・DB 失敗)は usecase で 1 回ログして presentation が 6
- **クラッシュ耐性**: RUNNING 移行後に worker が落ちると started_at 設定済みのため lease 解放されない(意図どおり)。`exitcode.txt` 未出力なら hang-detector が経過時間で ハング疑い、出力済みなら成果物から結果が分かる。運用者は abort-rapid-crosscheck → background-rerun で復旧。`.tmp` ファイルが残っても確定名が無いため未完了と判定される
- **速報と確報のモデル分離**: final_* を触らない
- **速報結果の位置付け**: worker の終了コード・依頼状態はジョブスケジューラの業務ジョブ応答に影響しない

## データモデル変更

### rapid_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | string | CLAIMED → RUNNING → SUCCEEDED / FAILED | 追加(更新) |
| started_at | datetime | UTC。RUNNING 遷移時 | 追加(更新) |
| completed_at | datetime | UTC。終端遷移時 | 追加(更新) |
| exit_code | integer | 比較ツールの終了コード(比較定義なし・起動失敗は 6) | 追加(更新) |
| stdout | text | 比較ツールの stdout 全文 | 追加(更新) |
| stderr | text | 比較ツールの stderr 全文 | 追加(更新) |
| error_summary | string | stderr 先頭 1 行(256 文字)。SUCCEEDED は NULL | 追加(更新) |

### comparison_results

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| comparison_result_id | string | 主キー(8 桁 hex 乱数。全体で一意。衝突時は取り直す) | 追加 |
| run_id | string | rapid_crosscheck_requests.run_id への FK | 追加 |
| comparison_type | string | 比較定義の comparison_type | 追加 |
| status | string | OK / NG / FAILED | 追加 |
| difference_count | integer | 差分件数(比較ツール stdout から。無ければ NULL) | 追加 |
| report_uri | string | レポート URI(同上) | 追加 |
| compared_at | datetime | UTC。比較ツール終了時刻 | 追加 |

### 成果物ファイル(role=rapid-crosscheck)

| ファイル | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| started-at.txt | UTC ISO 8601 1 行 | hang-detector の経過時間判定 | 追加 |
| stdout.log / stderr.log | text | 比較ツール出力 | 追加 |
| exitcode.txt | 数値 1 行 | 比較ツール終了コード | 追加 |

## ビジネスルール

- 依頼状態遷移規則: CLAIMED → RUNNING → SUCCEEDED(0)/ FAILED(非 0・実行エラー)
- 比較定義の選択: job_id ごとの比較定義に従う。差し替えられていればその job_id の定義を使う
- 比較ツール終了コードの対応: 0=OK / 3=NG / 6=FAILED。値を変換しない
- 速報結果の位置付け: 結果はジョブスケジューラ応答に影響しない
- Runner Result Contract: role=rapid-crosscheck の成果物を同じ 4 ファイル構成で残す

## ティア完了条件(BDD)

```gherkin
Feature: 比較ツールでジョブ単位比較を実行して結果を登録する - 速報クロスチェックティア

  Scenario: exit_code 0 で SUCCEEDED / OK を保存する
    Given 依頼 run_id=20260830T113000Z-JOB001-3f9a1c2e, job_id=JOB001 が status=CLAIMED, worker_id=worker-01 で、JOB001 の比較定義があり、比較ツールが 0 を返す
    When worker-01 が execute_comparison を実行する
    Then 依頼は status=SUCCEEDED, exit_code=0, completed_at 設定済み、comparison_results に status=OK の行が 1 件あり、rapid-crosscheck/exitcode.txt の中身は `0` である

  Scenario: exit_code 3 で FAILED / NG を保存する
    Given 同上で比較ツールが 3 を返し stdout に `difference_count=12` を出す
    When worker-01 が execute_comparison を実行する
    Then 依頼は status=FAILED, exit_code=3、comparison_results は status=NG, difference_count=12、worker の終了コードは 0 である

  Scenario: exit_code 6 で FAILED / FAILED を保存する
    Given 同上で比較ツールが 6 を返し stderr に `connection refused` を出す
    When worker-01 が execute_comparison を実行する
    Then 依頼は status=FAILED, exit_code=6, error_summary=`connection refused`、comparison_results は status=FAILED である

  Scenario: 他 worker に奪われた依頼は処理しない
    Given 依頼 run_id=20260830T113000Z-JOB001-3f9a1c2e が status=CLAIMED, worker_id=worker-02 である
    When worker-01 が execute_comparison(run_id) を実行する
    Then RUNNING への UPDATE は 0 行で、比較ツールは起動されず、stdout は claim の 4 行(`run_id=` / `job_id=` / `worker_id=` / `lease_until=`)に続けて `request_status=<再 SELECT した現在の status>`、`result_status=-`、`exit_code=-`、`comparison_result_id=-`、`artifact_dir: -` が出て、実行ログに `WARN request not owned run_id=20260830T113000Z-JOB001-3f9a1c2e status=...` が残り、worker-01 の終了コードは 0 である

  Scenario: 成果物を一時ファイル経由で公開する
    Given 比較ツールが 0 を返す
    When worker-01 が execute_comparison を実行する
    Then facade/20260830T113000Z-JOB001-3f9a1c2e/rapid-crosscheck/ に stdout.log, stderr.log, exitcode.txt が揃い、`*.tmp` は存在しない

  Scenario: 比較定義が無い job_id は comparison_results を作らない
    Given 依頼 run_id=20260830T114000Z-JOB009-9f9f9f9f, job_id=JOB009 が status=CLAIMED, worker_id=worker-01 で、クロスチェックジョブマップに JOB009 の行が無い
    When worker-01 が execute_comparison を実行する
    Then 依頼は status=FAILED, exit_code=6, error_summary=`comparison definition not found job_id=JOB009`、comparison_results に同 run_id の行は無く、stdout に `result_status=-` と `comparison_result_id=-` が出て、worker の終了コードは 0 である

  Scenario: 比較ツールの起動に失敗しても comparison_results を作らない
    Given 依頼 run_id=20260830T113000Z-JOB001-3f9a1c2e, job_id=JOB001 が status=CLAIMED, worker_id=worker-01 で、JOB001 の比較定義の compare_command に実行権限が無い
    When worker-01 が execute_comparison を実行する
    Then 依頼は status=FAILED, exit_code=6, error_summary=`launch failed`、comparison_results に同 run_id の行は無く、rapid-crosscheck/exitcode.txt の中身は `6`、stdout に `request_status=FAILED`、`result_status=-`、`comparison_result_id=-` が出て、worker の終了コードは 6 である

  Scenario: 終端 UPDATE が 0 行なら comparison_results を INSERT しない
    Given 依頼 run_id=20260830T113000Z-JOB001-3f9a1c2e が status=ABORTED(worker-01 の比較中に abort-rapid-crosscheck で中止)である
    When 比較ツールが 0 で終了し worker-01 が結果保存を実行する
    Then 依頼は ABORTED のまま、comparison_results に同 run_id の行は無く、stdout に `request_status=ABORTED`、`result_status=-`、`exit_code=-`、`comparison_result_id=-` が出て、実行ログに `WARN request already terminal run_id=20260830T113000Z-JOB001-3f9a1c2e status=ABORTED` が残り、worker の終了コードは 0 である
```
