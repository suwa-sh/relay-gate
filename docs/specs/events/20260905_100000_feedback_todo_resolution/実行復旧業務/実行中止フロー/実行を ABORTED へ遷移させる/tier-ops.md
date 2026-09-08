# 実行を ABORTED へ遷移させる - 実行監視・復旧ティア仕様

## 変更概要

abort-* 4 スクリプトの後半(yes 応答後)を定義する。slot 系(abort-blue / abort-green)は成果物再確認 → `aborted.txt` の書き込み(`.tmp` → `mv`)→(RAPID_CROSSCHECK_MODE が off 以外)`slot_executions` / `parallel_runs` の条件付き UPDATE の順で処理する。依頼系(abort-rapid-crosscheck / abort-final-crosscheck)は依頼テーブルの条件付き UPDATE と parallel_runs の併更新を行う。コマンド契約(引数・対話・終了コード)は UC「現在状態を確認して停止確認に応答する」の tier-ops.md と共通である。

## コマンド契約

### abort-* 共通(前半 UC の契約を使う)

- **書式**: `abort-{blue|green|rapid-crosscheck|final-crosscheck}.sh --run-id <ID> [--yes]`
- **アクセス権**: 運用者の直接起動 / ジョブスケジューラ(`--yes`)

#### 引数・オプション

前半 UC の tier-ops.md と同一(`--run-id` 必須、`--yes` 任意)。

- **stdin**: 前半 UC と同一

### スクリプトごとの対象と更新

| スクリプト | 中止の正本 | 可否条件(domain) | 更新(gateway) |
|---|---|---|---|
| `abort-blue.sh` | `facade/<run_id>/blue/aborted.txt` | `slots.blue.mode = background` かつ ファイル導出 status = RUNNING(exitcode.txt も aborted.txt も無い) | 1) `aborted.txt.tmp` に中止日時 1 行を書き `mv aborted.txt`。2) off 以外: `UPDATE slot_executions SET status = 'ABORTED', completed_at = ? WHERE run_id = ? AND slot = 'blue' AND status = 'RUNNING'` |
| `abort-green.sh` | `facade/<run_id>/green/aborted.txt` | 同上(green) | 同上(`slot = 'green'`) |
| `abort-rapid-crosscheck.sh` | `rapid_crosscheck_requests`(管理 DB) | `status = 'RUNNING'` | `UPDATE rapid_crosscheck_requests SET status = 'ABORTED', completed_at = ? WHERE run_id = ? AND status = 'RUNNING'` |
| `abort-final-crosscheck.sh` | `final_crosscheck_requests`(管理 DB) | `status = 'RUNNING'` | `UPDATE final_crosscheck_requests SET status = 'ABORTED', completed_at = ? WHERE final_crosscheck_id = ? AND status = 'RUNNING'` |
| 共通(併更新。final を除く) | `parallel_runs` | slot: aborted.txt を公開した(off 以外)。依頼: 上の UPDATE が 1 件 | `UPDATE parallel_runs SET status = 'ABORTED', completed_at = ? WHERE run_id = ? AND status IN ('STARTED', 'RUNNING')`(**COMPLETED の parallel_runs は更新しない。更新件数 0 で可**。通常 run の速報比較依頼を中止するときは foreground 中継完了で COMPLETED 済みのため 0 件になる。STARTED → ABORTED は状態モデル「並行稼働実行」の正規遷移で、facade / background-rerun が STARTED で作成した直後の中止を取りこぼさない) |

- slot 系の処理順(U3): 成果物再確認 → `aborted.txt` を `.tmp` → `mv` で公開 → (off 以外)`slot_executions` と `parallel_runs` を **1 トランザクション**で条件付き UPDATE。off では管理 DB に接続しない
- slot 系の管理 DB UPDATE が **0 件**(管理 DB 側が既に終端・中止済み): 実行ログに `WARN management db not updated run_id=... role=...` を残し終了コード 0(ファイル正本は成立)。管理 DB **接続・SQL 失敗**: 終了コード 6(aborted.txt は公開済みのまま残す。stderr `error: management db update failed ...` と `hint: rerun abort-<role>.sh --run-id ... to reapply`)
- slot 系の再適用(冪等): aborted.txt が既にあり、RAPID_CROSSCHECK_MODE が off 以外で `slot_executions.status` が RUNNING(または `parallel_runs` が STARTED / RUNNING)のままなら、プロンプト(または `--yes`)の後に aborted.txt を書き直さず管理 DB だけ更新し、stdout `status=ABORTED` / stderr `warn: aborted.txt already published; management db updated` で終了コード 0。aborted.txt があり管理 DB も更新済み(または off)なら 3(`error: run is not abortable ... status=ABORTED`)
- 依頼系: 対象の UPDATE と parallel_runs の UPDATE は **1 トランザクション**で行う。対象の更新件数が 0 なら ROLLBACK。parallel_runs の更新件数は 0 でも COMMIT する
- 運用注記(UC「速報比較依頼だけを新規作成する」と共通): `background-rerun.sh --role rapid-crosscheck` で作られた run の parallel_runs は依頼の終端時に worker が COMPLETED にする。依頼が RUNNING の間に abort-rapid-crosscheck.sh で中止した場合は併更新で parallel_runs も ABORTED になる
- 更新件数 0 の判定(依頼系)は「domain で不可と判定済み」なら `request is not abortable ... status=...`、「domain で可と判定したが UPDATE が 0 件」なら `... (state changed concurrently)` を出す。いずれも終了コード 3。slot 系は yes 応答直後の成果物再確認で exitcode.txt / aborted.txt を検出したときに `run is not abortable (state changed concurrently) ...` で 3
- `aborted_at` の値は 1 回の実行で 1 つ(UTC ISO 8601 秒精度 Z 付き)。`aborted.txt` の中身、`completed_at`、stdout の `aborted_at` に同じ値を書く。テスト専用環境変数 `RELAY_GATE_NOW`(ISO 8601 UTC。本番では未設定)が設定されていれば now() の代わりにその値を使う

## 出力契約

- **stdout**(前半の現在状態に続けて):
  | 行順 | キー | 値 |
  |---|---|---|
  | 1 | `status` | `ABORTED` |
  | 2 | `aborted_at` | UTC ISO 8601(aborted.txt の中身 / completed_at と同じ値) |
- **stderr**: `error: run is not abortable run_id=... role=... mode=... status=...`(slot)/ `error: request is not abortable run_id=... role=... status=...`(依頼)/ `error: run is not abortable (state changed concurrently) run_id=... role=...`(slot の競合)/ `error: request is not abortable (state changed concurrently) run_id=... role=...`(依頼の競合)/ `error: management db update failed ...` + `hint: rerun abort-<role>.sh --run-id ... to reapply`(slot の DB 失敗)/ `warn: aborted.txt already published; management db updated`(slot の再適用)
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | slot: aborted.txt を公開した(off 以外は加えて管理 DB を更新した。UPDATE 0 件は WARN のみ)。依頼: 対象を ABORTED に更新し COMMIT した |
  | 3 | 業務エラー(中止不可) | slot が background かつ RUNNING でない(終端済み・中止済み・未起動・foreground / off)/ 依頼が RUNNING でない / 競合(slot: 再確認で exitcode.txt または aborted.txt を検出。依頼: 条件付き UPDATE の更新件数 0)。状態は変更しない |
  | 6 | 実行エラー | aborted.txt の書き込み失敗、管理 DB 接続・SQL・COMMIT 失敗(slot は aborted.txt を残す)、更新件数 2 以上(内部エラー) |

## UC ロジック

- **バリデーション**: 前半 UC で済んでいる。本 UC は現在状態を domain の判定表に通す(slot 系は yes 応答直後に成果物を再確認する)
- **確認プロンプト**: 前半 UC で済んでいる(`yes` のみ本 UC へ)
- **冪等性**: 既に ABORTED の対象(slot: aborted.txt あり、依頼: status=ABORTED)に再実行すると可否判定で不可(終了コード 3)となり二重更新しない。例外は slot の再適用(aborted.txt あり + 管理 DB が未更新)で、管理 DB だけを更新して 0。同じ run_id に対する 2 つの abort が同時に走った場合、管理 DB は WHERE 句の `status = 'RUNNING'` により片方だけが更新件数 1 になり(LP-021)、他方は再確認で aborted.txt を検出して 3 か、UPDATE 0 件を WARN として 0 で終わる。aborted.txt は `mv` の原子性により 1 つだけ存在する
- **エラーハンドリング**: 不可・競合は状態を変えず 3。DB 障害は 6(slot は aborted.txt を残し再適用を案内)。エラー出力は 1 回(CLR-004)
- **クラッシュ耐性**: slot: `mv` 前に落ちれば `.tmp` だけが残り状態は RUNNING のまま(再実行でやり直す。`.tmp` は上書き)。`mv` 後・管理 DB 更新前に落ちれば aborted.txt が正本として成立しており、再実行は再適用として管理 DB だけを更新する。依頼: UPDATE と parallel_runs 併更新は 1 トランザクション。COMMIT 前に落ちれば何も変わらず、再実行で同じ手順をやり直せる。COMMIT 後・ログ書き込み前に落ちた場合は状態は ABORTED、実行ログの `status changed` 行だけが欠ける(ログ欠落は監査の正本がジョブスケジューラである前提で許容)
- **プロセス停止**: スクリプトは `kill` / SSH による停止・Pod 停止を一切行わない
- **実行ログ**(CLP-008): `INFO status changed from=RUNNING to=ABORTED operator={OS ユーザー} answer=yes|yes(--yes) run_id=... role=...`。不可は `INFO abort rejected reason=mode|status mode=... status=...`、競合は `WARN abort conflict updated_rows=0`(依頼)/ `WARN abort conflict artifact=exitcode.txt|aborted.txt`(slot)、slot の DB UPDATE 0 件は `WARN management db not updated run_id=... role=...`。ログ行形式は `_cross-cutting/ux-ui/ui-design.md` の `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従い、情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する

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
| status | string | RUNNING / SUCCEEDED / FAILED / ABORTED。RUNNING → ABORTED。ファイル正本と同じ値を保持する二重マッピング | 追加 |
| started_at | datetime | 開始時刻 | 追加 |
| completed_at | datetime | 終了時刻。ABORTED 時に中止日時(aborted.txt と同値)を書く | 追加 |

### rapid_crosscheck_requests(abort-rapid-crosscheck)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK | 追加 |
| status | string | REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED。RUNNING → ABORTED | 追加 |
| completed_at | datetime | ABORTED 時に中止日時を書く | 追加 |

### final_crosscheck_requests(abort-final-crosscheck)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| final_crosscheck_id | string | PK(`--run-id` の値) | 追加 |
| status | string | 同上。RUNNING → ABORTED | 追加 |
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
- abort-rapid-crosscheck / abort-final-crosscheck は依頼が RUNNING のときだけ ABORTED にできる(条件「依頼中止可否判定」「依頼状態遷移規則」)
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
    Then 終了コード 0 で stdout の末尾が `status=ABORTED` と `aborted_at=2026-08-30T12:40:00Z` の 2 行である
    And green/aborted.txt の中身が `2026-08-30T12:40:00Z` の 1 行で aborted.txt.tmp は無く、実行ログ上で aborted.txt の mv が管理 DB の UPDATE より前に記録されている
    And slot_executions(run_id, green).status=ABORTED, completed_at=2026-08-30T12:40:00Z かつ parallel_runs(run_id).status=ABORTED である

  Scenario: abort-blue.sh は RAPID_CROSSCHECK_MODE=off では aborted.txt だけを書いて終了コード 0
    Given RAPID_CROSSCHECK_MODE=off で facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.blue.mode が background、blue/ に started-at.txt だけがある
    And テスト専用環境変数 RELAY_GATE_NOW=2026-08-30T12:40:00Z が設定されている
    When `abort-blue.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 0 で stdout の末尾が `status=ABORTED` と `aborted_at=2026-08-30T12:40:00Z` で、blue/aborted.txt の中身が `2026-08-30T12:40:00Z` である
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

  Scenario: abort-rapid-crosscheck.sh は CLAIMED の依頼を拒否する
    Given rapid_crosscheck_requests に run_id=20260830T113000-JOB001-3f9a1c2e status=CLAIMED がある
    When `abort-rapid-crosscheck.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 3 で stderr に `error: request is not abortable run_id=20260830T113000-JOB001-3f9a1c2e role=rapid-crosscheck status=CLAIMED` が出る
    And status は CLAIMED のままである

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
