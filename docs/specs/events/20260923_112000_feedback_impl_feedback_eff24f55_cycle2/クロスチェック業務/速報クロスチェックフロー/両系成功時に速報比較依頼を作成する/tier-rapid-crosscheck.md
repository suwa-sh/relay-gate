# 両系成功時に速報比較依頼を作成する - 速報クロスチェックティア仕様

## 変更概要

`rapid-crosscheck-runner.sh` の dispatcher フロー(usecase `dispatch_rapid_request`)を追加する。完了通知の登録(受信 UC)に続けて同一起動内で実行し、domain `next_completion_status` の判定表に従い rapid_runs.completion_status を更新し、両系成功のときだけ rapid_crosscheck_requests に REQUESTED を条件付き INSERT する。同一トランザクションで `parallel_runs.status`(`FOR UPDATE`。abort-blue / abort-green の parallel_runs 無条件行ロック(SELECT 1 ... FOR UPDATE)と直列化)と完了通知の対象 slot(通知元 role の slot)の `slot_executions.status`(SELECT のみ)を読み、run が中止済み(並行稼働実行 ABORTED、または対象 slot の slot 実行 ABORTED)なら両系成功でも INSERT しない(条件「中止済み run の比較依頼作成除外」。arch SP-009 / LP-010 / LP-023)。1 トランザクション(LP-009)。管理 DB への接続は速報クロスチェック設定(rapid-crosscheck.env。情報「速報クロスチェック設定」)の `RAPID_DB_CONN_REF` で解決する(受信 UC の設定ファイル節)。

## コマンド契約

### rapid-crosscheck-runner.sh blue-completed / green-completed(dispatcher 部分)

- **書式**: 受信 UC と同一(`rapid-crosscheck-runner.sh blue-completed|green-completed --run-id --job-id --exit-code --artifact-uri`)
- **アクセス権**: slot runner からの内部呼び出し

#### 引数・オプション

受信 UC(`../速報クロスチェック runner へ完了通知を送信する/tier-rapid-crosscheck.md`)と同じ。本 UC は追加の引数を持たない。

- **stdin**: なし

## 出力契約

- **stdout**(受信 UC の 4 行に続けて。固定順): `completion_status=`(PENDING / ONE_COMPLETED / BOTH_SUCCEEDED / ANY_FAILED / REQUEST_CREATED)/ `request_status=`(REQUESTED。作成しないときは `-`)/ `requested_at=`(作成時のみ。ローカル日時(指示子なし)。それ以外は `-`)。中止済み run で両系成功のときは `completion_status=BOTH_SUCCEEDED` / `request_status=-` / `requested_at=-`
- **stderr**: `warn: job_id mismatch run_id=... notified=JOB001 recorded=JOB002`、`warn: rapid request not created run_id=... reason=parallel_run_aborted`(並行稼働実行 ABORTED)/ `warn: rapid request not created run_id=... role=... reason=slot_execution_aborted`(対象 slot の slot 実行 ABORTED)(いずれも継続。終了コード 0。reason の値は実行ログと同じで空白を含まない)、`info: request already exists run_id=...`(--verbose)、`error: management db transaction failed run_id=...`
- **実行ログ**(`RELAY_GATE_LOG_DIR/rapid-crosscheck-runner.sh.log`): `INFO completion status updated run_id=... from=... to=...` / `INFO request created run_id=... job_id=...` / `WARN rapid request not created run_id=... reason=parallel_run_aborted`(並行稼働実行 ABORTED)/ `WARN rapid request not created run_id=... role=... reason=slot_execution_aborted`(対象 slot の slot 実行 ABORTED)/ `ERROR management db transaction failed run_id=...`。行形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {ローカル日時} {LEVEL} {message}`)に従い、情報「実行ログ」の属性「出力日時」はこのローカル時刻列に対応する
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 完了状況を更新した(依頼の作成有無を問わない。既存依頼ありも 0)。中止済みの run(並行稼働実行 ABORTED、または対象 slot の slot 実行 ABORTED)では両系成功でも依頼を作成せず 0(条件「中止済み run の比較依頼作成除外」) |
  | 2 | 入力エラー | 受信 UC と同じ |
  | 3 | 業務エラー | rapid_runs に run_id の行が無い |
  | 6 | 実行エラー | トランザクション失敗(ROLLBACK 済み) |

## UC ロジック

- **設定ファイルの読み込み(共通規約の参照)**: 読む設定ファイル(env / CSV)の入力の守備範囲は CLI 契約 `config_input_rules` に従う(形式(UTF-8 / LF)から外れた NUL バイト・不正な文字コード・BOM・CR は契約と同文の error 行で拒否して終了コード 2、読み込みは 1 時点の内容だけで判定、補助コマンドの失敗は終了コード 6。値は本 tier に複写しない。判定する BDD は UC「slot ごとのジョブマップを定義する」に置く)。stdout / stderr / 実行ログ / メール本文に出す任意入力の制御文字は `ui-design.md`「制御文字の表記」の可視表記にする。bash の最低版は 5.0(契約 `conventions.runtime_prerequisites`)
- **バリデーション**: 受信 UC と同じ
- **確認プロンプト**: なし
- **冪等性**: 同じ通知を 2 回受けても `INSERT ... WHERE NOT EXISTS` により依頼は 1 件。completion_status は判定表から再計算するため同じ値に収束する。REQUEST_CREATED 以降は再判定しても REQUEST_CREATED を維持する
- **エラーハンドリング**: トランザクション内の失敗は ROLLBACK し、usecase が 1 回ログ、presentation が 6 を返す。通知元(slot runner)はこの非 0 を Runner Result に反映しない
- **クラッシュ耐性**: 受信 UC の UPDATE と本 UC の INSERT / UPDATE は同一トランザクション。COMMIT 前に落ちれば自系統列も NULL のまま(通知は届かなかったのと同じ)。COMMIT 後に落ちても stdout が出ないだけで DB は整合。rapid_runs の行ロック(FOR UPDATE)で両通知の同時到着を直列化する
- **速報と確報のモデル分離**: final_* に触れない
- **依頼作成と claim の原子性(LP-009)**: `INSERT INTO rapid_crosscheck_requests (run_id, job_id, status, requested_at) SELECT ?, ?, 'REQUESTED', ? WHERE NOT EXISTS (SELECT 1 FROM rapid_crosscheck_requests WHERE run_id = ?)`。主キー制約が最終防壁
- **中止済み run の比較依頼作成除外(LP-010 / LP-023)**: 処理順はトランザクション内で「rapid_runs の自系統列を更新(先勝ち。受信 UC。rapid_runs は FOR UPDATE で行ロック済み)→ `SELECT job_id, status FROM parallel_runs WHERE run_id = ? FOR UPDATE` を同一トランザクションで読む → `SELECT status FROM slot_executions WHERE run_id = ? AND slot = ?`(slot = 通知元 role。SELECT のみ)を読む → 両系成功判定 → run が中止済み(`parallel_runs.status = 'ABORTED'` **または** 対象 slot の `slot_executions.status = 'ABORTED'`)なら INSERT しない → COMMIT」。並行稼働実行は foreground slot の結果を中継した時点で COMPLETED になるため、foreground 完了後に background slot を abort-blue / abort-green で中止した典型経路は対象 slot の slot 実行 ABORTED の側で除外する。中止済み run で両系成功のとき completion_status は BOTH_SUCCEEDED のまま(REQUEST_CREATED へ進めない)。完了事実(blue_status / green_status / 成果物 URI / 受信日時)は記録して COMMIT する。実行ログと stderr の reason は判定キーで分ける: 並行稼働実行 ABORTED なら `WARN rapid request not created run_id=... reason=parallel_run_aborted` / `warn: rapid request not created run_id=... reason=parallel_run_aborted`、対象 slot の slot 実行 ABORTED なら `WARN rapid request not created run_id=... role=... reason=slot_execution_aborted` / `warn: rapid request not created run_id=... role=... reason=slot_execution_aborted`。いずれも終了コード 0。判断主体は本コマンドで、slot runner は自 slot の中止状態(aborted.txt)を判断せず通常どおり通知する(条件「完了通知の系統独立」)。RAPID_CROSSCHECK_MODE=off では完了通知も依頼も存在しないため速報有効時だけに適用する。中止した run を background-rerun --role rapid-crosscheck でリランした場合は新 run_id(parallel_runs RUNNING、slot_executions 行なし)で依頼が作成される。判定表(縦軸 3 値 × 横軸 3 値。依頼を作成するのは「いずれでもない × 両系成功」だけ):

  | run の中止済み判定 \ 両系成功判定 | 両系成功 | いずれか失敗 | 片系未完了 |
  |---|---|---|---|
  | 並行稼働実行 ABORTED(parallel_runs.status = 'ABORTED') | 作成しない(BOTH_SUCCEEDED のまま。WARN reason=parallel_run_aborted) | 作成しない(ANY_FAILED) | 作成しない(ONE_COMPLETED) |
  | 対象 slot の slot 実行 ABORTED(対象 slot の slot_executions.status = 'ABORTED') | 作成しない(BOTH_SUCCEEDED のまま。WARN role=... reason=slot_execution_aborted) | 作成しない(ANY_FAILED) | 作成しない(ONE_COMPLETED) |
  | いずれでもない(parallel_runs が ABORTED でなく、対象 slot の slot_executions も ABORTED でない。行なしを含む) | 依頼を INSERT(REQUEST_CREATED) | 作成しない(ANY_FAILED) | 作成しない(ONE_COMPLETED) |

- **abort との直列化(FOR UPDATE。LP-021)**: parallel_runs の行を `FOR UPDATE` でロックすることで abort-blue / abort-green の parallel_runs 無条件行ロック(`SELECT 1 FROM parallel_runs WHERE run_id = ? FOR UPDATE`。abort 側は条件付き UPDATE の前にこれを取る。parallel_runs が COMPLETED(foreground 中継済み)でも取るため、条件付き UPDATE が 0 件になる run でも直列化が成り立つ)と直列化する。abort が先に COMMIT すれば本コマンドは COMMIT 後の状態(parallel_runs ABORTED または対象 slot の slot_executions ABORTED)を読んで依頼を作らず、本コマンドが先なら abort の parallel_runs 行ロックが本コマンドの COMMIT を待ち、その後の `UPDATE rapid_crosscheck_requests ... WHERE status='REQUESTED'` が作成済みの依頼を 1 件 ABORTED にする(競合窓の保険。本条件と併用)。「abort が先なら作らない」は abort の slot_executions UPDATE が 1 件(slot が RUNNING のまま中止できた)ときの保証で、0 件(runner の終端 UPDATE が先に COMMIT 済み)のときは slot はファイル正本でも SUCCEEDED / FAILED(exitcode.txt 優先)であり、完了通知で依頼が作成されるのは正しい振る舞い。ロック順は dispatcher: rapid_runs → parallel_runs → slot_executions(対象 slot の行の SELECT)→ rapid_crosscheck_requests、abort: slot_executions → parallel_runs(FOR UPDATE)→ parallel_runs 条件付き UPDATE → rapid_crosscheck_requests、worker: rapid_crosscheck_requests → parallel_runs(デッドロックなし。正本は `_cross-cutting/datastore/rdb-schema.yaml` の `_review_notes`)

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
| requested_at | datetime | 作成時刻(ホストのローカルタイムゾーン。タイムゾーン指示子なし。RDB のタイムスタンプ型に委ねる) | 追加 |
| started_at / completed_at | datetime | NULL | 追加 |
| exit_code | integer | NULL | 追加 |
| stdout / stderr | text | NULL | 追加 |
| error_summary | string | NULL | 追加 |

### rapid_runs

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| completion_status | string | PENDING / ONE_COMPLETED / BOTH_SUCCEEDED / ANY_FAILED / REQUEST_CREATED。中止済みの run(並行稼働実行 ABORTED、または対象 slot の slot 実行 ABORTED)では両系成功でも REQUEST_CREATED へ進めない(BOTH_SUCCEEDED のまま) | 追加(更新) |

### parallel_runs(参照)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | 主キー | 追加(参照) |
| job_id | string | 依頼の job_id の正本 | 追加(参照) |
| status | string | ABORTED なら依頼を作成しない(同一トランザクションで `SELECT ... FOR UPDATE`。abort-blue / abort-green の parallel_runs 無条件行ロック(SELECT 1 ... FOR UPDATE)と直列化) | 追加(参照) |

### slot_executions(参照)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id / slot | string | 主キー。完了通知の対象 slot(通知元 role。blue-completed なら slot='blue')の行だけを読む(`WHERE run_id = ? AND slot = ?`)。行なし(速報比較依頼だけのリラン由来 run)は ABORTED ではない | 追加(参照) |
| status | string | 対象 slot が ABORTED(aborted.txt 公開済みのミラー。abort-blue / abort-green が同一トランザクションで更新済み)なら依頼を作成しない(同一トランザクションで SELECT。ロックしない)。判定材料は管理 DB の本列(条件「slot 実行の状態導出規則」の管理 DB 側の規則に従い、runner / abort-* が aborted.txt または exitcode.txt の公開時点の状態を条件付き UPDATE(WHERE status='RUNNING')で一度だけ書く): 中止後に実装が走り切って exitcode.txt を公開しても runner の終端 UPDATE は 0 件で本列は ABORTED のまま残るため、ファイル正本の導出値(exitcode.txt 優先で SUCCEEDED / FAILED)とは異なりうる(SPEC-005-02 AC6 / AC9) | 追加(参照) |

### 設定ファイル

| ファイル | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| `$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` | env | 情報「速報クロスチェック設定」。`RAPID_DB_CONN_REF`(属性「管理 DB 接続参照名」)で管理 DB へ接続する(受信 UC の設定ファイル節と同じ。本 UC は同一起動) | 追加(参照) |

## ビジネスルール

- 両系成功判定: SUCCEEDED × SUCCEEDED のみ依頼を作成する
- 中止済み run の比較依頼作成除外: run が中止済み(並行稼働実行 ABORTED、または完了通知の対象 slot の slot 実行 ABORTED。判定材料は同一トランザクションで読む parallel_runs.status と slot_executions.status)なら両系成功でも依頼を作成せず、完了事実だけを記録して実行ログに警告を残す。判断主体は本 dispatcher
- 比較依頼の一意性: 完了順にかかわらず run_id につき 1 件。後に完了した側の通知で作成する
- 依頼状態遷移規則: REQUESTED で作成する
- 速報と確報のモデル分離: final_crosscheck_requests を作成・変更しない
- 速報結果の位置付け: 依頼作成の成否はジョブスケジューラ応答に影響しない

## ティア完了条件(BDD)

```gherkin
Feature: 両系成功時に速報比較依頼を作成する - 速報クロスチェックティア

  Scenario: 両系成功で REQUESTED を 1 件 INSERT する
    Given parallel_runs に run_id=20260830T113000-JOB001-3f9a1c2e, job_id=JOB001 の行と、rapid_runs に同 run_id, blue_status=SUCCEEDED, green_status=NULL の行がある
    When `rapid-crosscheck-runner.sh green-completed --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/green` を実行する
    Then 終了コード 0 で stdout に `completion_status=REQUEST_CREATED`、`request_status=REQUESTED` が出て、rapid_crosscheck_requests に status=REQUESTED, job_id=JOB001 の行が 1 件ある

  Scenario: 片系完了では依頼を作成しない
    Given parallel_runs に run_id=20260830T113000-JOB001-3f9a1c2e, job_id=JOB001 の行と、rapid_runs に同 run_id, blue_status=NULL, green_status=NULL の行がある
    When `rapid-crosscheck-runner.sh blue-completed ... --exit-code 0 ...` を実行する
    Then 終了コード 0 で stdout に `completion_status=ONE_COMPLETED`、`request_status=-` が出て、rapid_crosscheck_requests に行は無い

  Scenario: いずれか失敗では依頼を作成しない
    Given parallel_runs と rapid_runs に run_id=20260830T113000-JOB001-3f9a1c2e の行(job_id=JOB001, blue_status=SUCCEEDED, green_status=NULL)がある
    When `rapid-crosscheck-runner.sh green-completed ... --exit-code 3 ...` を実行する
    Then 終了コード 0 で stdout に `completion_status=ANY_FAILED` が出て、rapid_crosscheck_requests に行は無い

  Scenario: 既に依頼がある run への再通知は重複しない
    Given parallel_runs に run_id=20260830T113000-JOB001-3f9a1c2e, job_id=JOB001 の行があり、rapid_runs に同 run_id の行(blue_status=SUCCEEDED, green_status=SUCCEEDED, completion_status=REQUEST_CREATED)があり、rapid_crosscheck_requests に同 run_id の行が 1 件ある
    When `rapid-crosscheck-runner.sh green-completed ... --exit-code 0 ...` を再実行する
    Then 終了コード 0 で rapid_crosscheck_requests の行数は 1 のままである

  Scenario: parallel_runs が ABORTED なら両系成功でも INSERT しない
    Given parallel_runs に run_id=20260830T113000-JOB001-3f9a1c2e, job_id=JOB001, status=ABORTED の行と、rapid_runs に同 run_id, blue_status=SUCCEEDED, green_status=NULL の行があり、rapid_crosscheck_requests に同 run_id の行は無い
    When `rapid-crosscheck-runner.sh green-completed --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/green` を実行する
    Then 終了コード 0 で stdout に `completion_status=BOTH_SUCCEEDED`、`request_status=-`、`requested_at=-` が出て、stderr に `warn: rapid request not created run_id=20260830T113000-JOB001-3f9a1c2e reason=parallel_run_aborted` が出る
    And rapid_runs.green_status は SUCCEEDED、completion_status は BOTH_SUCCEEDED で、rapid_crosscheck_requests に行は無く、実行ログに `WARN rapid request not created run_id=20260830T113000-JOB001-3f9a1c2e reason=parallel_run_aborted` が残る

  Scenario: parallel_runs が COMPLETED でも対象 slot の slot_executions が ABORTED なら両系成功でも INSERT しない
    Given parallel_runs に run_id=20260830T113000-JOB001-3f9a1c2e, job_id=JOB001, status=COMPLETED の行と、slot_executions に同 run_id の slot=blue status=SUCCEEDED と slot=green status=ABORTED の行と、rapid_runs に同 run_id, blue_status=SUCCEEDED, green_status=NULL の行があり、rapid_crosscheck_requests に同 run_id の行は無い
    When `rapid-crosscheck-runner.sh green-completed --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/green` を実行する
    Then 終了コード 0 で stdout に `completion_status=BOTH_SUCCEEDED`、`request_status=-`、`requested_at=-` が出て、stderr に `warn: rapid request not created run_id=20260830T113000-JOB001-3f9a1c2e role=green reason=slot_execution_aborted` が出る
    And rapid_crosscheck_requests に行は無く、rapid_runs.green_status は SUCCEEDED、completion_status は BOTH_SUCCEEDED で、実行ログに `WARN rapid request not created run_id=20260830T113000-JOB001-3f9a1c2e role=green reason=slot_execution_aborted` が残る

  Scenario: 判定材料を同一トランザクションで読む(rapid_runs FOR UPDATE → parallel_runs FOR UPDATE → 対象 slot の slot_executions SELECT)
    Given parallel_runs に run_id=20260830T113000-JOB001-3f9a1c2e, job_id=JOB001, status=COMPLETED の行と、slot_executions に同 run_id の slot=blue status=SUCCEEDED, slot=green status=RUNNING の行と、rapid_runs に同 run_id, blue_status=SUCCEEDED, green_status=NULL の行がある
    When `rapid-crosscheck-runner.sh green-completed ... --exit-code 0 ...` を実行する
    Then 1 トランザクション内で `SELECT ... FROM rapid_runs ... FOR UPDATE` → `SELECT job_id, status FROM parallel_runs WHERE run_id = ? FOR UPDATE` → `SELECT status FROM slot_executions WHERE run_id = ? AND slot = 'green'`(FOR UPDATE なし)の順に発行され、slot='blue' の行は判定に使われず、依頼が INSERT されて COMMIT される

  Scenario: parallel_runs の行ロックで abort-green.sh と直列化される
    Given parallel_runs に run_id=20260830T113000-JOB001-3f9a1c2e, job_id=JOB001, status=RUNNING の行と、rapid_runs に同 run_id, blue_status=SUCCEEDED, green_status=NULL の行があり、slot_executions(run_id, green).status=RUNNING である
    When `rapid-crosscheck-runner.sh green-completed ... --exit-code 0 ...` と `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を同時に実行する
    Then 両者の COMMIT 後、rapid_crosscheck_requests に同 run_id の REQUESTED の行は残らない(dispatcher が先なら abort が REQUESTED → ABORTED に更新し、abort が先なら dispatcher は ABORTED を読んで INSERT しない)

  Scenario: parallel_runs が COMPLETED でも abort-green.sh の無条件行ロックで直列化される(foreground 中継済みの典型経路)
    Given parallel_runs に run_id=20260830T113000-JOB001-3f9a1c2e, job_id=JOB001, status=COMPLETED の行と、rapid_runs に同 run_id, blue_status=SUCCEEDED, green_status=NULL の行があり、slot_executions(run_id, green).status=RUNNING である
    When `rapid-crosscheck-runner.sh green-completed ... --exit-code 0 ...` と `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を同時に実行する
    Then 両者の COMMIT 後、parallel_runs の同 run_id は COMPLETED のままで、rapid_crosscheck_requests に同 run_id の REQUESTED の行は残らない(dispatcher が先なら abort の `SELECT 1 FROM parallel_runs ... FOR UPDATE` が dispatcher の COMMIT を待ってから REQUESTED → ABORTED に更新し、abort が先なら dispatcher は slot_executions(run_id, green).status=ABORTED を読んで INSERT しない)

  Scenario: parallel_runs が ABORTED でも片系完了の完了事実は記録する
    Given parallel_runs に run_id=20260830T113000-JOB001-3f9a1c2e, status=ABORTED の行と、rapid_runs に同 run_id, blue_status=NULL, green_status=NULL の行がある
    When `rapid-crosscheck-runner.sh blue-completed ... --exit-code 0 ...` を実行する
    Then 終了コード 0 で stdout に `completion_status=ONE_COMPLETED`、`request_status=-` が出て、rapid_runs.blue_status は SUCCEEDED、blue_completed_at はローカル ISO 8601 の値で、rapid_crosscheck_requests に行は無い
```
