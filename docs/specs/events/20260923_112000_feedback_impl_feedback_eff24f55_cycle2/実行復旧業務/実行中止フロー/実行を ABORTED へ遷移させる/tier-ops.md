# 実行を ABORTED へ遷移させる - 実行監視・復旧ティア仕様

## 変更概要

abort-* 4 スクリプトの後半(yes 応答後)を定義する。slot 系(abort-blue / abort-green)は成果物再確認 → `aborted.txt` の書き込み(`.tmp` → `mv`)→(RAPID_CROSSCHECK_MODE が off 以外)`slot_executions` / `parallel_runs` / `rapid_crosscheck_requests`(REQUESTED で未着手の速報比較依頼のみ。競合窓の保険)の条件付き UPDATE の順で処理する。依頼系は依頼テーブルの条件付き UPDATE(abort-rapid-crosscheck: `status IN ('REQUESTED','CLAIMED','RUNNING')`、abort-final-crosscheck: `status = 'RUNNING'`)と parallel_runs の併更新(速報のみ)を行う。コマンド契約(引数・対話・終了コード)は UC「現在状態を確認して停止確認に応答する」の tier-ops.md と共通である。

## コマンド契約

### abort-* 共通(前半 UC の契約を使う)

- **書式**: `abort-{blue|green|rapid-crosscheck|final-crosscheck}.sh --run-id <ID> [--yes] [--verbose]`
- **アクセス権**: 運用者の直接起動 / ジョブスケジューラ(`--yes`)

#### 引数・オプション

前半 UC の tier-ops.md と同一(`--run-id` 必須、`--yes` 任意)。abort-blue / abort-green の `--run-id` は「対象 run に REQUESTED で未着手の速報比較依頼があればそれも ABORTED にする(条件「slot 中止可否判定」。競合窓の保険)」を含む。abort-rapid-crosscheck の `--run-id` は「依頼が REQUESTED / CLAIMED / RUNNING のとき ABORTED へ」、abort-final-crosscheck の `--run-id` は「依頼が RUNNING のとき ABORTED へ」(条件「依頼中止可否判定」)。

- **stdin**: 前半 UC と同一

### スクリプトごとの対象と更新

| スクリプト | 中止の正本 | 可否条件(domain) | 更新(gateway) |
|---|---|---|---|
| `abort-blue.sh` | `facade/<run_id>/blue/aborted.txt` | `slots.blue.mode = background` かつ ファイル導出 status = RUNNING(exitcode.txt も aborted.txt も無い) | 1) `aborted.txt.tmp` に中止日時 1 行を書き `mv aborted.txt`。2) off 以外: `UPDATE slot_executions SET status = 'ABORTED', completed_at = ? WHERE run_id = ? AND slot = 'blue' AND status = 'RUNNING'` |
| `abort-green.sh` | `facade/<run_id>/green/aborted.txt` | 同上(green) | 同上(`slot = 'green'`) |
| `abort-rapid-crosscheck.sh` | `rapid_crosscheck_requests`(管理 DB) | `status IN ('REQUESTED', 'CLAIMED', 'RUNNING')`(速報比較依頼。SUCCEEDED / FAILED / ABORTED の終端状態は不可) | 現在状態 7 行の表示 → 停止確認(プロンプト文言は前半 UC のまま。REQUESTED の依頼には worker プロセスが無いが確認は省略しない)→ yes のときだけ `UPDATE rapid_crosscheck_requests SET status = 'ABORTED', completed_at = ? WHERE run_id = ? AND status IN ('REQUESTED', 'CLAIMED', 'RUNNING')`(更新件数 1 で 0。0 件 = 表示後に終端した競合で 3) |
| `abort-final-crosscheck.sh` | `final_crosscheck_requests`(管理 DB) | `status = 'RUNNING'`(確報比較依頼。REQUESTED / CLAIMED / 終端は不可) | `UPDATE final_crosscheck_requests SET status = 'ABORTED', completed_at = ? WHERE final_crosscheck_id = ? AND status = 'RUNNING'`(確報の未着手(REQUESTED / CLAIMED)依頼はジョブスケジューラの正規ジョブが同期 polling 中であり、runner 側の polling 上限 FINAL_POLL_LIMIT_SEC で扱う。条件「依頼中止可否判定」) |
| 共通(併更新。final を除く) | `parallel_runs` | slot: aborted.txt を公開した(off 以外)。依頼: 上の UPDATE が 1 件 | slot 系は条件付き UPDATE の前に `SELECT 1 FROM parallel_runs WHERE run_id = ? FOR UPDATE`(無条件の行ロック。COMPLETED でも取る。dispatcher(rapid-crosscheck-runner.sh)の FOR UPDATE と直列化するため。条件付き UPDATE だけでは COMPLETED の run で 0 件となり行ロックを取らない)を実行する。続けて `UPDATE parallel_runs SET status = 'ABORTED', completed_at = ? WHERE run_id = ? AND status IN ('STARTED', 'RUNNING')`(**COMPLETED の parallel_runs は更新しない。更新件数 0 で可**。通常 run の速報比較依頼を中止するときは foreground 中継完了で COMPLETED 済みのため 0 件になる。STARTED → ABORTED は状態モデル「並行稼働実行」の正規遷移で、facade / background-rerun が STARTED で作成した直後の中止を取りこぼさない) |
| slot 系のみ(未着手の速報比較依頼。off 以外) | `rapid_crosscheck_requests` | aborted.txt を公開した(off 以外)。依頼の状態は判定しない(WHERE 句に委ねる) | `UPDATE rapid_crosscheck_requests SET status = 'ABORTED', completed_at = ? WHERE run_id = ? AND status = 'REQUESTED'`(**0 件は正常**: 依頼が無い、または CLAIMED / RUNNING / 終端済み。CLAIMED / RUNNING の依頼は本コマンドでは変更しない。確報比較依頼(final_crosscheck_requests)には適用しない。条件「slot 中止可否判定」、状態「クロスチェック依頼」REQUESTED → ABORTED。**競合窓の保険**: 両系の完了通知で速報比較依頼が REQUESTED で作成された直後に運用者が slot を中止した場合の競合窓を塞ぐ。dispatcher 側の中止済み run 判定(rapid-crosscheck-runner.sh request_creation_matrix。対象 slot の slot 実行 ABORTED を判定キーに含む)と併用する。本コマンドは parallel_runs を無条件 FOR UPDATE でロックしてから条件付き UPDATE に進み、runner と直列化される。REQUESTED / CLAIMED / RUNNING の速報比較依頼の明示中止は abort-rapid-crosscheck.sh(条件「依頼中止可否判定」。status IN 条件付き UPDATE)で行う。CLAIMED のまま残すと lease 失効で REQUESTED に戻り再 claim されるため、中止済み run の依頼は abort-rapid-crosscheck.sh で止める) |

- slot 系の処理順(U3): 成果物再確認 → `aborted.txt` を `.tmp` → `mv` で公開 → (off 以外)**1 トランザクション**で `slot_executions` の条件付き UPDATE → `parallel_runs` の無条件行ロック(`SELECT 1 ... FOR UPDATE`)→ `parallel_runs` の条件付き UPDATE → `rapid_crosscheck_requests`(REQUESTED のみ)の条件付き UPDATE。off では管理 DB に接続しない(off では完了通知も依頼も存在しない)
- slot 系の管理 DB UPDATE が **0 件**(管理 DB 側が既に終端・中止済み): 実行ログに `WARN management db not updated run_id=... role=...` を残し終了コード 0(ファイル正本は成立。ただし runner の終端 UPDATE が先に COMMIT 済みの場合は aborted.txt が残っても状態導出は exitcode.txt を優先するため中止は成立していない。再確認: abort-<role>.sh の現在状態表示(ファイル正本から導出)。run-lineage.sh は run_status(parallel_runs 由来)のみで slot の状態は表示しない)。管理 DB **接続・SQL 失敗**: 終了コード 6(aborted.txt は公開済みのまま残す。stderr `error: management db update failed ...` と `hint: rerun abort-<role>.sh --run-id ... to reapply`)
- slot 系の再適用(冪等): aborted.txt が既にあり、RAPID_CROSSCHECK_MODE が off 以外で `slot_executions.status` が RUNNING(または `parallel_runs` が STARTED / RUNNING)のままなら、プロンプト(または `--yes`)の後に aborted.txt を書き直さず管理 DB だけ更新し(`rapid_crosscheck_requests` の REQUESTED 条件付き UPDATE も同じく試みる。0 件で可)、stdout `status=ABORTED` / stderr `warn: aborted.txt already published; management db updated` で終了コード 0。aborted.txt があり管理 DB も更新済み(または off)なら 3(`error: run is not abortable ... status=ABORTED`)
- 依頼系: 対象の UPDATE と parallel_runs の UPDATE(速報のみ)は **1 トランザクション**で行う。対象の更新件数が 0 なら ROLLBACK。parallel_runs の更新件数は 0 でも COMMIT する。ロック順は rapid_crosscheck_requests(条件付き UPDATE status IN)→ parallel_runs(条件付き UPDATE status IN ('STARTED','RUNNING'))。worker(rapid_crosscheck_requests UPDATE → parallel_runs UPDATE)と同じ順なのでデッドロックしない
- abort-rapid-crosscheck の可否判定表(domain `is_request_abortable`。arch LP-019。縦軸クロスチェック種別、横軸依頼状態):
  | 種別 | REQUESTED | CLAIMED | RUNNING | SUCCEEDED | FAILED | ABORTED |
  |---|---|---|---|---|---|---|
  | 速報(abort-rapid-crosscheck.sh) | 可 | 可 | 可 | 不可(3) | 不可(3) | 不可(3) |
  | 確報(abort-final-crosscheck.sh) | 不可(3) | 不可(3) | 可 | 不可(3) | 不可(3) | 不可(3) |
- CLAIMED の速報比較依頼を中止すると、claim 済み worker の RUNNING への条件付き UPDATE(`WHERE run_id=? AND status='CLAIMED' AND worker_id=?`)が 0 件になり比較を開始しない(rapid-crosscheck-worker.sh。UC「比較ツールでジョブ単位比較を実行して結果を登録する」)。CLAIMED を放置すると lease 失効で REQUESTED に戻り別 worker が再 claim して比較が実行されるため、中止済み run の依頼は本コマンドで止める
- 運用注記(UC「速報比較依頼だけを新規作成する」と共通): `background-rerun.sh --role rapid-crosscheck` で作られた run の parallel_runs は依頼の終端時に worker が COMPLETED にする。依頼が RUNNING の間に abort-rapid-crosscheck.sh で中止した場合は併更新で parallel_runs も ABORTED になる
- 更新件数 0 の判定(依頼系)は「domain で不可と判定済み(速報: 終端状態、確報: RUNNING 以外)」なら `request is not abortable ... status=...`(速報は SUCCEEDED / FAILED / ABORTED の終端状態のとき、確報は RUNNING 以外のときに出る)、「domain で可と判定したが UPDATE が 0 件(表示後に終端した競合)」なら `... (state changed concurrently)` を出す。いずれも終了コード 3 で状態は変更しない。slot 系は yes 応答直後の成果物再確認で exitcode.txt / aborted.txt を検出したときに `run is not abortable (state changed concurrently) ...` で 3
- `aborted_at` の中止時刻は 1 回の実行で 1 つ。`aborted.txt` の中身は UTC ISO 8601 秒精度 Z 付き(Runner Result Contract。変えない)。`completed_at`(slot_executions / parallel_runs / rapid_crosscheck_requests)と stdout の `aborted_at` には同時刻をホストのローカルタイムゾーン(ISO 8601 秒精度、指示子なし)へ変換して書く。テスト専用環境変数 `RELAY_GATE_NOW`(UTC ISO 8601 Z 付き。本番では未設定)が設定されていれば now() の代わりにその値を使い、内部でローカル時刻へ変換する(BDD の例示は TZ=UTC 前提)

## 出力契約

- **stdout**(前半の現在状態に続けて):
  | 行順 | キー | 値 |
  |---|---|---|
  | 1 | `status` | `ABORTED` |
  | 2 | `aborted_at` | ローカル ISO 8601 秒精度、指示子なし(aborted.txt の中止時刻(UTC Z 付き)をローカルへ変換した同時刻。completed_at と同じ値)。依頼の状態は出さない |
- **stderr**: `error: run is not abortable run_id=... role=... mode=... status=...`(slot)/ `error: request is not abortable run_id=... role=... status=...`(依頼。速報は SUCCEEDED / FAILED / ABORTED の終端状態のときだけ、確報は RUNNING 以外のときに出る)/ `error: run is not abortable (state changed concurrently) run_id=... role=...`(slot の競合)/ `error: request is not abortable (state changed concurrently) run_id=... role=... status=<再 SELECT した status>`(依頼の競合。速報。確報は契約どおり)/ `error: management db update failed ...` + `hint: rerun abort-<role>.sh --run-id ... to reapply`(slot の DB 失敗)/ `warn: aborted.txt already published; management db updated`(slot の再適用)
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | slot: aborted.txt を公開した(off 以外は加えて管理 DB を更新した。slot_executions の UPDATE 0 件は WARN のみ。RAPID_CROSSCHECK_MODE が off 以外なら加えて `rapid_crosscheck_requests` を条件付き UPDATE(`WHERE run_id=? AND status='REQUESTED'`)で ABORTED(completed_at=now)にする。0 件は正常(依頼が無い、または CLAIMED / RUNNING / 終端済み)。CLAIMED / RUNNING の依頼は変更しない)。依頼: 対象を ABORTED に更新し COMMIT した(abort-rapid-crosscheck: `UPDATE rapid_crosscheck_requests SET status='ABORTED', completed_at=? WHERE run_id=? AND status IN ('REQUESTED','CLAIMED','RUNNING')` が 1 件。REQUESTED / CLAIMED / RUNNING のいずれからでも ABORTED にする(条件「依頼中止可否判定」)。abort-final-crosscheck: `status='RUNNING'` 条件の UPDATE が 1 件) |
  | 3 | 業務エラー(中止不可) | slot が background かつ RUNNING でない(終端済み・中止済み・未起動・foreground / off)/ 速報比較依頼が SUCCEEDED / FAILED / ABORTED の終端状態(abort-rapid-crosscheck。状態を変更せずエラー終了)/ 確報比較依頼が RUNNING でない(REQUESTED / CLAIMED / 終端。abort-final-crosscheck。状態を変更せずエラー終了)/ 競合(slot: 再確認で exitcode.txt または aborted.txt を検出。依頼: 条件付き UPDATE の更新件数 0 = 表示後に終端した競合)。状態は変更しない(対象依頼が無い / 応答が yes 以外 / 管理 DB なし(RAPID_CROSSCHECK_MODE=off)の 3 は前半 UC) |
  | 6 | 実行エラー | aborted.txt の書き込み失敗、管理 DB 接続・SQL・COMMIT 失敗(slot は aborted.txt を残す)、更新件数 2 以上(内部エラー) |

## UC ロジック

- **バリデーション**: 前半 UC で済んでいる。本 UC は現在状態を domain の判定表に通す(slot 系は yes 応答直後に成果物を再確認する)
- **確認プロンプト**: 前半 UC で済んでいる(`yes` のみ本 UC へ)
- **冪等性**: 既に ABORTED の対象(slot: aborted.txt あり、依頼: status=ABORTED)に再実行すると可否判定で不可(終了コード 3)となり二重更新しない。abort-rapid-crosscheck は条件付き UPDATE(`status IN ('REQUESTED','CLAIMED','RUNNING')`)で、再実行は終端済みで 3。CLAIMED を中止すると claim 済み worker の RUNNING 遷移(条件付き UPDATE)が 0 件になり比較を開始しない(rapid-crosscheck-worker.sh)。例外は slot の再適用(aborted.txt あり + 管理 DB が未更新)で、管理 DB だけを更新して 0。同じ run_id に対する 2 つの abort が同時に走った場合、管理 DB は WHERE 句の `status = 'RUNNING'` により片方だけが更新件数 1 になり(LP-021)、他方は再確認で aborted.txt を検出して 3 か、UPDATE 0 件を WARN として 0 で終わる。aborted.txt は `mv` の原子性により 1 つだけ存在する
- **エラーハンドリング**: 不可・競合は状態を変えず 3。DB 障害は 6(slot は aborted.txt を残し再適用を案内)。エラー出力は 1 回(CLR-004)
- **クラッシュ耐性**: slot: `mv` 前に落ちれば `.tmp` だけが残り状態は RUNNING のまま(再実行でやり直す。`.tmp` は上書き)。`mv` 後・管理 DB 更新前に落ちれば aborted.txt が正本として成立しており、再実行は再適用として管理 DB だけを更新する。依頼: UPDATE と parallel_runs 併更新は 1 トランザクション。COMMIT 前に落ちれば何も変わらず、再実行で同じ手順をやり直せる。COMMIT 後・ログ書き込み前に落ちた場合は状態は ABORTED、実行ログの `status changed` 行だけが欠ける(ログ欠落は監査の正本がジョブスケジューラである前提で許容)
- **プロセス停止**: スクリプトは `kill` / SSH による停止・Pod 停止を一切行わない
- **実行ログ**(CLP-008): `INFO status changed from=RUNNING to=ABORTED operator={OS ユーザー} answer=yes|yes(--yes) run_id=... role=...`(abort-rapid-crosscheck の from は表示時の現在状態 `REQUESTED|CLAIMED|RUNNING`)。不可は `INFO abort rejected reason=mode|status mode=... status=...`、競合は `WARN abort conflict updated_rows=0`(依頼)/ `WARN abort conflict artifact=exitcode.txt|aborted.txt`(slot)、slot の DB UPDATE 0 件は `WARN management db not updated run_id=... role=...`。未着手の速報比較依頼を ABORTED にしたときは `INFO rapid request aborted run_id=... from=REQUESTED to=ABORTED operator=... answer=yes|yes(--yes)`(answer の表記は `status changed` 行と同じ規則。0 件のときはログを出さない。`--verbose` 時は stderr に `info: rapid request aborted run_id=...`)。ログ行形式は `_cross-cutting/ux-ui/ui-design.md` の `{script} {run_id} {ローカル出力日時} {LEVEL} {message}` に従い、情報「実行ログ」の属性「出力日時」はこの ローカル時刻列に対応する

## データモデル変更

### Runner Result(ファイル。abort-blue / abort-green が書く)

| ファイル | 説明 | 変更種別 |
|---|---|---|
| `facade/<run_id>/<role>/aborted.txt` | 中止日時 1 行(UTC ISO 8601 秒精度 Z 付き。`RELAY_GATE_NOW` 設定時はその値)。`.tmp` に書いてから `mv`。中止時のみ生成。exitcode.txt が無いときの ABORTED 判定に用いる(条件「slot 実行の状態導出規則」) | 追加 |
| `facade/<run_id>/<role>/started-at.txt` / `exitcode.txt` | 再確認の読み取りのみ(書かない) | 追加(参照) |

### slot_executions(abort-blue / abort-green。RAPID_CROSSCHECK_MODE が off 以外)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK 1 | 追加 |
| slot | string | PK 2。blue / green | 追加 |
| mode | string | foreground / background。表示のみ(可否判定の正本は execution-spec.json の mode。UPDATE の WHERE 句には使わない) | 追加 |
| pid | integer | runner の PID(表示のみ) | 追加 |
| artifact_dir | string | 成果物ディレクトリ(表示のみ) | 追加 |
| status | string | RUNNING / SUCCEEDED / FAILED / ABORTED。RUNNING → ABORTED。条件付き UPDATE(WHERE status='RUNNING')で一度だけ終端値を書く列。abort 後に実装が走り切って exitcode.txt を公開した経路だけファイル正本の導出値と一致せず ABORTED のまま残る(再同期しない。正本: rdb-schema.yaml slot_executions.status) | 追加 |
| started_at | datetime | 開始時刻 | 追加 |
| completed_at | datetime | 終了時刻(ローカル時刻)。ABORTED 時に aborted.txt の中止時刻(UTC)をローカルへ変換した同時刻を書く | 追加 |

### rapid_crosscheck_requests(abort-rapid-crosscheck。abort-blue / abort-green は REQUESTED のみ)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK | 追加 |
| status | string | REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED。REQUESTED / CLAIMED / RUNNING → ABORTED(abort-rapid-crosscheck。条件付き UPDATE `status IN ('REQUESTED','CLAIMED','RUNNING')`。0 件 = 終端済みで 3)/ REQUESTED → ABORTED(abort-blue / abort-green による未着手依頼の中止。競合窓の保険。条件付き UPDATE `status = 'REQUESTED'`。off 以外。0 件は正常) | 追加 |
| completed_at | datetime | ABORTED 時に中止日時(ローカル時刻)を書く | 追加 |

### final_crosscheck_requests(abort-final-crosscheck)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| final_crosscheck_id | string | PK(`--run-id` の値) | 追加 |
| status | string | 同上。RUNNING → ABORTED(RUNNING のみ。条件付き UPDATE `status = 'RUNNING'`。REQUESTED / CLAIMED / 終端は状態を変更せず 3) | 追加 |
| completed_at | datetime | ABORTED 時に中止日時を書く | 追加 |

### parallel_runs(共通。final を除く。slot 系は off 以外)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK | 追加 |
| status | string | STARTED / RUNNING / COMPLETED / ABORTED。STARTED または RUNNING → ABORTED | 追加 |
| completed_at | datetime | ABORTED 時に中止日時を書く | 追加 |

## 設定契約

- **feature-flag.env**(`RELAY_GATE_CONFIG_DIR`): `RAPID_CROSSCHECK_MODE`(off 以外なら管理 DB も更新。abort-blue / abort-green / abort-rapid-crosscheck が読む。abort-final-crosscheck は読まない)
- **rapid-crosscheck.env**: `RAPID_DB_CONN_REF`(off 以外のときの管理 DB 接続参照名)。**final-crosscheck.env**: `FINAL_DB_CONN_REF`(abort-final-crosscheck のみ)
- **環境変数**: `RELAY_GATE_ARTIFACT_ROOT`(`facade/<run_id>/<role>/aborted.txt` の親)/ `RELAY_GATE_LOG_DIR`(実行ログ)/ `RELAY_GATE_NOW`(テスト専用。aborted_at に使う)

## ビジネスルール

- abort-blue / abort-green は対象 slot が background かつ RUNNING のときだけ ABORTED にできる。foreground / off は状態を変更せずエラー終了(条件「slot 中止可否判定」)。RUNNING の判定はファイル正本(条件「slot 実行の状態導出規則」)
- slot の中止は成果物ディレクトリへの `aborted.txt` 書き込みを正本とし、RAPID_CROSSCHECK_MODE が off でも成立する。off 以外なら管理 DB の状態も ABORTED に更新する(条件「slot 中止可否判定」「速報クロスチェック有効判定」、情報「Runner Result」)
- abort-rapid-crosscheck は速報比較依頼が REQUESTED / CLAIMED / RUNNING のいずれかのとき ABORTED にできる(停止確認 yes 後の `status IN` 条件付き UPDATE。終端状態は状態を変更せずエラー終了)。abort-final-crosscheck は確報比較依頼が RUNNING のときだけ ABORTED にできる(REQUESTED / CLAIMED / 終端は状態を変更せずエラー終了。確報の未着手依頼はジョブスケジューラの正規ジョブが同期 polling 中で、runner 側の polling 上限で扱う)。CLAIMED の速報比較依頼を中止すると claim 済み worker は RUNNING への条件付き UPDATE が 0 件になり比較を開始しない(条件「依頼中止可否判定」「依頼状態遷移規則」、状態「クロスチェック依頼」REQUESTED / CLAIMED / RUNNING → ABORTED)
- abort-blue / abort-green は yes で slot を ABORTED にするとき、対象 run に REQUESTED で未着手(worker が claim していない)の速報比較依頼があればそれも ABORTED にする(off 以外。条件付き UPDATE `status = 'REQUESTED'`。0 件は正常)。確報比較依頼には適用しない。この REQUESTED → ABORTED は競合窓の保険である: 両系の完了通知で速報比較依頼が REQUESTED で作成された直後に運用者が slot を中止した場合の競合窓を塞ぐ。dispatcher 側の中止済み run 判定(rapid-crosscheck-runner.sh request_creation_matrix。対象 slot の slot 実行 ABORTED を判定キーに含む。UC「両系成功時に速報比較依頼を作成する」の条件「中止済み run の比較依頼作成除外」)と併用する。CLAIMED / RUNNING の依頼は本コマンドでは変更しない。REQUESTED / CLAIMED / RUNNING の速報比較依頼の明示中止は abort-rapid-crosscheck.sh(条件「依頼中止可否判定」。status IN 条件付き UPDATE)で行う。CLAIMED のまま残すと lease 失効で REQUESTED に戻り再 claim されるため、中止済み run の依頼は abort-rapid-crosscheck.sh で止める(条件「slot 中止可否判定」、状態「クロスチェック依頼」REQUESTED → ABORTED、情報「中止指示」「速報比較依頼」)
- yes のときに限り更新し、並行稼働実行が STARTED / RUNNING なら併せて ABORTED にする。COMPLETED は変更しない(条件「停止確認応答」、状態「並行稼働実行」)
- ABORTED への管理 DB 更新は WHERE 句で現在状態を条件にし、競合時に二重更新しない(arch LP-021)
- スクリプト自身はプロセスを停止せず状態更新だけを行い、二重実行を防ぐ(情報「中止指示」)
- ハング検知(hang-detector)はこの遷移を行わない(条件「監視は通知のみ」)。aborted.txt がある対象は中止済みとして監視記録を終端する(他 UC)

## ティア完了条件(BDD)

```gherkin
Feature: 実行を ABORTED へ遷移させる - 実行監視・復旧ティア

  Scenario: abort-green.sh が aborted.txt を公開してから slot と parallel_run を ABORTED にする
    Given RAPID_CROSSCHECK_MODE=background で facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.green.mode が background、green/ に started-at.txt だけがある
    And slot_executions に run_id=20260830T113000-JOB001-3f9a1c2e slot=green mode=background status=RUNNING があり parallel_runs の同 run_id が RUNNING である
    And テスト専用環境変数 RELAY_GATE_NOW=2026-08-30T12:40:00Z が設定されている
    When `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 0 で stdout の末尾が `status=ABORTED` と `aborted_at=2026-08-30T12:40:00` の 2 行である
    And green/aborted.txt の中身が `2026-08-30T12:40:00Z` の 1 行で aborted.txt.tmp は無く、実行ログ上で aborted.txt の mv が管理 DB の UPDATE より前に記録されている
    And slot_executions(run_id, green).status=ABORTED, completed_at=2026-08-30T12:40:00 かつ parallel_runs(run_id).status=ABORTED である

  Scenario: abort-green.sh は REQUESTED の速報比較依頼を同一トランザクションで ABORTED にする(SPEC-010-01)
    # 競合窓の保険: 両系の完了通知で依頼が REQUESTED で作成された直後に slot を中止した競合窓を塞ぐ。dispatcher 側の中止済み run 判定と併用する
    Given RAPID_CROSSCHECK_MODE=background で green slot が RUNNING(green/ に started-at.txt あり・exitcode.txt なし)、slot_executions(run_id, green).status=RUNNING、parallel_runs(run_id).status=RUNNING である
    And その run に rapid_crosscheck_requests(run_id).status=REQUESTED worker_id=NULL の速報比較依頼がある(dispatcher が中止直前に作成した競合ケース)
    And テスト専用環境変数 RELAY_GATE_NOW=2026-08-30T12:40:00Z が設定されている
    When `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes --verbose` を実行する
    Then 終了コード 0 で rapid_crosscheck_requests(run_id).status=ABORTED, completed_at=2026-08-30T12:40:00 であり、slot_executions / parallel_runs / rapid_crosscheck_requests の UPDATE は 1 つのトランザクションで COMMIT されている
    And 実行ログに `INFO rapid request aborted run_id=20260830T113000-JOB001-3f9a1c2e from=REQUESTED to=ABORTED operator=ops01 answer=yes(--yes)` を含む行が残り、stderr に `info: rapid request aborted run_id=20260830T113000-JOB001-3f9a1c2e` が出る
    And stdout の末尾は `status=ABORTED` と `aborted_at=2026-08-30T12:40:00` の 2 行で、依頼の状態を示す行は無い

  Scenario Outline: abort-blue.sh は CLAIMED / RUNNING の速報比較依頼を変更せず 0 件を正常とする(SPEC-010-01)
    Given RAPID_CROSSCHECK_MODE=background で blue/ に started-at.txt だけがあり、slot_executions(run_id, blue).status=RUNNING である
    And rapid_crosscheck_requests(run_id).status=<status> worker_id=<worker_id> started_at=<started_at> である
    When `abort-blue.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 0 で blue/aborted.txt が公開され、slot_executions(run_id, blue).status=ABORTED である
    And rapid_crosscheck_requests(run_id).status は <status> のまま(条件付き UPDATE の更新件数 0)で completed_at は NULL のまま、実行ログに `rapid request aborted` を含む行も `WARN` 行も残らない

    Examples:
      | status  | worker_id | started_at          |
      | CLAIMED | worker-01 | NULL                |
      | RUNNING | worker-01 | 2026-08-30T11:46:00 |

  Scenario: abort-green.sh は速報比較依頼が無い run でも 0 件を正常として終了コード 0
    Given RAPID_CROSSCHECK_MODE=background で green/ に started-at.txt だけがあり、slot_executions(run_id, green).status=RUNNING で、rapid_crosscheck_requests に同 run_id の行が無い(両系完了前)
    When `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 0 で green/aborted.txt が公開され、実行ログに `rapid request aborted` を含む行は残らない

  Scenario: abort-blue.sh は RAPID_CROSSCHECK_MODE=off では aborted.txt だけを書いて終了コード 0
    Given RAPID_CROSSCHECK_MODE=off で facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.blue.mode が background、blue/ に started-at.txt だけがある
    And テスト専用環境変数 RELAY_GATE_NOW=2026-08-30T12:40:00Z が設定されている
    When `abort-blue.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 0 で stdout の末尾が `status=ABORTED` と `aborted_at=2026-08-30T12:40:00` で、blue/aborted.txt の中身が `2026-08-30T12:40:00Z` である
    And 管理 DB への接続は行われない

  Scenario: abort-blue.sh は slots.blue 節が無い(off の)slot を拒否する
    Given facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json に slots.blue 節が無い(BLUE_MODE=off で起動された run)
    When `abort-blue.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 3 で stderr に `error: run is not abortable run_id=20260830T113000-JOB001-3f9a1c2e role=blue mode=off status=-` が出て、blue/aborted.txt は作成されない

  Scenario: abort-green.sh は started-at.txt が無い(未起動の)slot を拒否する
    Given facade/20260830T124500-JOB001-7b2d9e01/execution-spec.json の slots.green.mode が background で、green/ に started-at.txt が無い
    When `abort-green.sh --run-id 20260830T124500-JOB001-7b2d9e01 --yes` を実行する
    Then 終了コード 3 で stderr に `error: run is not abortable run_id=20260830T124500-JOB001-7b2d9e01 role=green mode=background status=-` が出て、aborted.txt は作成されない

  Scenario: abort-green.sh は管理 DB の UPDATE が 0 件でも aborted.txt を正本として終了コード 0
    Given RAPID_CROSSCHECK_MODE=background で green/ に started-at.txt だけがあり、slot_executions(run_id, green).status が SUCCEEDED(管理 DB 側だけ先に終端していた)である
    When `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 0 で green/aborted.txt が公開され、実行ログに `WARN management db not updated run_id=20260830T113000-JOB001-3f9a1c2e role=green` が残る

  Scenario: abort-green.sh は管理 DB 失敗でも aborted.txt を残して終了コード 6
    Given RAPID_CROSSCHECK_MODE=background で green/ に started-at.txt だけがあり、管理 DB が接続を拒否する
    When `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 6 で stderr に `error: management db update failed` で始まる 1 行と `hint: rerun abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e to reapply` が出て、green/aborted.txt は残る

  Scenario: abort-green.sh は aborted.txt 公開済みで管理 DB が RUNNING のままなら管理 DB だけを再適用する
    Given RAPID_CROSSCHECK_MODE=background で green/ に started-at.txt と aborted.txt(中身 2026-08-30T12:40:00Z)があり、slot_executions(run_id, green).status が RUNNING である
    When `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 0 で stdout の末尾に `status=ABORTED`、stderr に `warn: aborted.txt already published; management db updated` が出る
    And green/aborted.txt の mtime と中身は変わらず、slot_executions(run_id, green).status=ABORTED である

  Scenario: abort-rapid-crosscheck.sh は COMPLETED の parallel_runs を変更しない
    Given rapid_crosscheck_requests に run_id=20260830T113000-JOB001-3f9a1c2e status=RUNNING があり parallel_runs の同 run_id が COMPLETED である
    When `abort-rapid-crosscheck.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 0 で rapid_crosscheck_requests(run_id).status=ABORTED かつ parallel_runs(run_id).status=COMPLETED のまま(併更新 0 件で COMMIT)である

  Scenario Outline: abort-rapid-crosscheck.sh は REQUESTED / CLAIMED の依頼を status IN 条件付き UPDATE で ABORTED にする(SPEC-010-02)
    Given RAPID_CROSSCHECK_MODE=background で rapid_crosscheck_requests に run_id=20260830T113000-JOB001-3f9a1c2e job_id=JOB001 status=<status> worker_id=<worker_id> lease_until=<lease_until> started_at=NULL があり parallel_runs の同 run_id が COMPLETED である
    And テスト専用環境変数 RELAY_GATE_NOW=2026-08-30T12:40:00Z が設定されている
    When TTY から `abort-rapid-crosscheck.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行し、現在状態 7 行の表示後のプロンプトに `yes` と入力する
    Then 終了コード 0 で発行された SQL が `UPDATE rapid_crosscheck_requests SET status = 'ABORTED', completed_at = ? WHERE run_id = ? AND status IN ('REQUESTED', 'CLAIMED', 'RUNNING')` と `UPDATE parallel_runs ... WHERE run_id = ? AND status IN ('STARTED', 'RUNNING')` の順で 1 トランザクションに含まれ、前者の更新件数が 1、後者が 0 で COMMIT されている
    And rapid_crosscheck_requests(run_id).status=ABORTED, completed_at=2026-08-30T12:40:00 で、実行ログに `INFO status changed from=<status> to=ABORTED operator=ops01 answer=yes run_id=20260830T113000-JOB001-3f9a1c2e role=rapid-crosscheck` が残る
    And <worker_check> の更新件数は 0 で、比較ツールは起動されない

    Examples:
      | status    | worker_id | lease_until         | worker_check |
      | REQUESTED | NULL      | NULL                | 別 worker worker-02 がその後に発行する claim `UPDATE rapid_crosscheck_requests SET status = 'CLAIMED', worker_id = 'worker-02', lease_until = ? WHERE run_id = ? AND status = 'REQUESTED'` |
      | CLAIMED   | worker-01 | 2026-08-30T12:10:00 | claim 済み worker-01 がその後に発行する `UPDATE rapid_crosscheck_requests SET status = 'RUNNING', started_at = ? WHERE run_id = ? AND status = 'CLAIMED' AND worker_id = 'worker-01'` |

  Scenario: abort-rapid-crosscheck.sh は REQUESTED の依頼でも停止確認を省略しない
    Given RAPID_CROSSCHECK_MODE=background で rapid_crosscheck_requests に run_id=20260830T113000-JOB001-3f9a1c2e status=REQUESTED worker_id=NULL がある
    When TTY から `abort-rapid-crosscheck.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行し stdin に `no` を入力する
    Then stderr に `対象ジョブのプロセスは強制終了してありますか？ [yes/no]: ` が出て終了コード 3 で、rapid_crosscheck_requests(run_id).status は REQUESTED のままである

  Scenario Outline: abort-rapid-crosscheck.sh は終端状態の依頼を状態を変更せず拒否する(SPEC-010-02)
    Given RAPID_CROSSCHECK_MODE=background で rapid_crosscheck_requests に run_id=20260830T113000-JOB001-3f9a1c2e status=<status> completed_at=2026-08-30T12:00:00 がある
    When `abort-rapid-crosscheck.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 3 で stderr に `error: request is not abortable run_id=20260830T113000-JOB001-3f9a1c2e role=rapid-crosscheck status=<status>` が出る
    And UPDATE は発行されず、status は <status>、completed_at は 2026-08-30T12:00:00 のままである

    Examples:
      | status    |
      | SUCCEEDED |
      | FAILED    |
      | ABORTED   |

  Scenario: abort-rapid-crosscheck.sh は表示後に終端した依頼を競合として拒否する
    Given RAPID_CROSSCHECK_MODE=background で rapid_crosscheck_requests に run_id=20260830T113000-JOB001-3f9a1c2e status=RUNNING worker_id=worker-01 があり、現在状態の表示後・応答入力の前に worker が同行を SUCCEEDED に終端した
    When 運用者がプロンプトに `yes` と入力する
    Then 条件付き UPDATE(`status IN ('REQUESTED', 'CLAIMED', 'RUNNING')`)の更新件数が 0 で ROLLBACK され、終了コード 3 で stderr に `error: request is not abortable (state changed concurrently) run_id=20260830T113000-JOB001-3f9a1c2e role=rapid-crosscheck status=SUCCEEDED` が出る
    And 実行ログに `WARN abort conflict updated_rows=0` が残り、status は SUCCEEDED のままである

  Scenario Outline: abort-final-crosscheck.sh は RUNNING でない確報比較依頼を状態を変更せず拒否する(SPEC-010-02)
    Given final_crosscheck_requests に final_crosscheck_id=20260830T020000-final-1a2b3c4d status=<status> がある
    When `abort-final-crosscheck.sh --run-id 20260830T020000-final-1a2b3c4d --yes` を実行する
    Then 終了コード 3 で stderr に `error: request is not abortable run_id=20260830T020000-final-1a2b3c4d role=final-crosscheck status=<status>` が出て、UPDATE は発行されず status は <status> のままである

    Examples:
      | status    |
      | REQUESTED |
      | CLAIMED   |
      | SUCCEEDED |

  Scenario: 同じ run に 2 つの abort-green.sh が同時に走っても管理 DB の更新は 1 回だけ
    Given RAPID_CROSSCHECK_MODE=background で green/ に started-at.txt だけがあり slot_executions(run_id, green).status=RUNNING である
    When `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を 2 プロセス同時に実行する
    Then green/aborted.txt は 1 つだけ存在し、slot_executions の UPDATE の更新件数の合計は 1 で、実行ログに `status changed from=RUNNING to=ABORTED` は 1 行だけ残る
    And 他方は終了コード 3(再確認で aborted.txt を検出。stderr に `(state changed concurrently)`)または終了コード 0(実行ログに `WARN management db not updated`)のいずれかで終わる

  Scenario: 管理 DB の UPDATE 失敗は終了コード 6(依頼系)
    Given 管理 DB が接続を拒否する
    When `abort-final-crosscheck.sh --run-id 20260830T020000-final-1a2b3c4d --yes` を実行する
    Then 終了コード 6 で stderr に `error: management db` で始まる 1 行が出る
```
