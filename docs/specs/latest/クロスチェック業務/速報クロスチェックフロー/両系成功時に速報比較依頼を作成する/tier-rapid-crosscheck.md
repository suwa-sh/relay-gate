# 両系成功時に速報比較依頼を作成する - 速報クロスチェックティア仕様

## 変更概要

`rapid-crosscheck-runner.sh` の dispatcher フロー(usecase `dispatch_rapid_request`)を追加する。完了通知の登録(受信 UC)に続けて同一起動内で実行し、domain `next_completion_status` の判定表に従い rapid_runs.completion_status を更新し、両系成功のときだけ rapid_crosscheck_requests に REQUESTED を条件付き INSERT する。1 トランザクション(LP-009)。

## コマンド契約

### rapid-crosscheck-runner.sh blue-completed / green-completed(dispatcher 部分)

- **書式**: 受信 UC と同一(`rapid-crosscheck-runner.sh blue-completed|green-completed --run-id --job-id --exit-code --artifact-uri`)
- **アクセス権**: slot runner からの内部呼び出し

#### 引数・オプション

受信 UC(`../速報クロスチェック runner へ完了通知を送信する/tier-rapid-crosscheck.md`)と同じ。本 UC は追加の引数を持たない。

- **stdin**: なし

## 出力契約

- **stdout**(受信 UC の 4 行に続けて): `completion_status=`(PENDING / ONE_COMPLETED / BOTH_SUCCEEDED / ANY_FAILED / REQUEST_CREATED)/ `request_status=`(REQUESTED。作成しないときは `-`)/ `requested_at=`(作成時のみ。それ以外は `-`)
- **stderr**: `warn: job_id mismatch run_id=... notified=JOB001 recorded=JOB002`、`info: request already exists run_id=...`(--verbose)、`error: management db transaction failed run_id=...`
- **実行ログ**(`RELAY_GATE_LOG_DIR/rapid-crosscheck-runner.sh.log`): `INFO completion status updated run_id=... from=... to=...` / `INFO request created run_id=... job_id=...` / `ERROR management db transaction failed run_id=...`。行形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {UTC 出力日時} {LEVEL} {message}`)に従い、情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 完了状況を更新した(依頼の作成有無を問わない。既存依頼ありも 0) |
  | 2 | 入力エラー | 受信 UC と同じ |
  | 3 | 業務エラー | rapid_runs に run_id の行が無い |
  | 6 | 実行エラー | トランザクション失敗(ROLLBACK 済み) |

## UC ロジック

- **バリデーション**: 受信 UC と同じ
- **確認プロンプト**: なし
- **冪等性**: 同じ通知を 2 回受けても `INSERT ... WHERE NOT EXISTS` により依頼は 1 件。completion_status は判定表から再計算するため同じ値に収束する。REQUEST_CREATED 以降は再判定しても REQUEST_CREATED を維持する
- **エラーハンドリング**: トランザクション内の失敗は ROLLBACK し、usecase が 1 回ログ、presentation が 6 を返す。通知元(slot runner)はこの非 0 を Runner Result に反映しない
- **クラッシュ耐性**: 受信 UC の UPDATE と本 UC の INSERT / UPDATE は同一トランザクション。COMMIT 前に落ちれば自系統列も NULL のまま(通知は届かなかったのと同じ)。COMMIT 後に落ちても stdout が出ないだけで DB は整合。rapid_runs の行ロック(FOR UPDATE)で両通知の同時到着を直列化する
- **速報と確報のモデル分離**: final_* に触れない
- **依頼作成と claim の原子性(LP-009)**: `INSERT INTO rapid_crosscheck_requests (run_id, job_id, status, requested_at) SELECT ?, ?, 'REQUESTED', ? WHERE NOT EXISTS (SELECT 1 FROM rapid_crosscheck_requests WHERE run_id = ?)`。主キー制約が最終防壁

## 非同期イベント

### rapid-crosscheck-requests

- **チャネル**: 管理 DB `rapid_crosscheck_requests`(RDB ジョブキュー。protocol `rdb-queue`)
- **方向**: publish(REQUESTED 行の INSERT)
- **メッセージ**: RapidCrosscheckRequestMessage(run_id, job_id, status=REQUESTED, requested_at)
- **AsyncAPI**: [asyncapi.yaml](../../../_cross-cutting/api/asyncapi.yaml) の `channels.rapid-crosscheck-requests`

## データモデル変更

### rapid_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | 主キー(parallel_runs.run_id への FK。rdb-schema.yaml の foreign_keys が正。rapid_runs とは同値だが FK は張らない)。1 run に 1 件 | 追加 |
| job_id | string | JOB_ID(比較定義の解決キー) | 追加 |
| status | string | REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED。作成時 REQUESTED | 追加 |
| worker_id | string | NULL(claim 時に設定) | 追加 |
| lease_until | datetime | NULL(claim 時に設定) | 追加 |
| requested_at | datetime | UTC。作成時刻 | 追加 |
| started_at / completed_at | datetime | NULL | 追加 |
| exit_code | integer | NULL | 追加 |
| stdout / stderr | text | NULL | 追加 |
| error_summary | string | NULL | 追加 |

### rapid_runs

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| completion_status | string | PENDING / ONE_COMPLETED / BOTH_SUCCEEDED / ANY_FAILED / REQUEST_CREATED | 追加(更新) |

## ビジネスルール

- 両系成功判定: SUCCEEDED × SUCCEEDED のみ依頼を作成する
- 比較依頼の一意性: 完了順にかかわらず run_id につき 1 件。後に完了した側の通知で作成する
- 依頼状態遷移規則: REQUESTED で作成する
- 速報と確報のモデル分離: final_crosscheck_requests を作成・変更しない
- 速報結果の位置付け: 依頼作成の成否はジョブスケジューラ応答に影響しない

## ティア完了条件(BDD)

```gherkin
Feature: 両系成功時に速報比較依頼を作成する - 速報クロスチェックティア

  Scenario: 両系成功で REQUESTED を 1 件 INSERT する
    Given parallel_runs に run_id=20260830T113000Z-JOB001-3f9a1c2e, job_id=JOB001 の行と、rapid_runs に同 run_id, blue_status=SUCCEEDED, green_status=NULL の行がある
    When `rapid-crosscheck-runner.sh green-completed --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/green` を実行する
    Then 終了コード 0 で stdout に `completion_status=REQUEST_CREATED`、`request_status=REQUESTED` が出て、rapid_crosscheck_requests に status=REQUESTED, job_id=JOB001 の行が 1 件ある

  Scenario: 片系完了では依頼を作成しない
    Given parallel_runs に run_id=20260830T113000Z-JOB001-3f9a1c2e, job_id=JOB001 の行と、rapid_runs に同 run_id, blue_status=NULL, green_status=NULL の行がある
    When `rapid-crosscheck-runner.sh blue-completed ... --exit-code 0 ...` を実行する
    Then 終了コード 0 で stdout に `completion_status=ONE_COMPLETED`、`request_status=-` が出て、rapid_crosscheck_requests に行は無い

  Scenario: いずれか失敗では依頼を作成しない
    Given parallel_runs と rapid_runs に run_id=20260830T113000Z-JOB001-3f9a1c2e の行(job_id=JOB001, blue_status=SUCCEEDED, green_status=NULL)がある
    When `rapid-crosscheck-runner.sh green-completed ... --exit-code 3 ...` を実行する
    Then 終了コード 0 で stdout に `completion_status=ANY_FAILED` が出て、rapid_crosscheck_requests に行は無い

  Scenario: 既に依頼がある run への再通知は重複しない
    Given parallel_runs に run_id=20260830T113000Z-JOB001-3f9a1c2e, job_id=JOB001 の行があり、rapid_runs に同 run_id の行(blue_status=SUCCEEDED, green_status=SUCCEEDED, completion_status=REQUEST_CREATED)があり、rapid_crosscheck_requests に同 run_id の行が 1 件ある
    When `rapid-crosscheck-runner.sh green-completed ... --exit-code 0 ...` を再実行する
    Then 終了コード 0 で rapid_crosscheck_requests の行数は 1 のままである
```
