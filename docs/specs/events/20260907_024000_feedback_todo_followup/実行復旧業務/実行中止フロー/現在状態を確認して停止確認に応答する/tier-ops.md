# 現在状態を確認して停止確認に応答する - 実行監視・復旧ティア仕様

## 変更概要

`abort-blue.sh` / `abort-green.sh` / `abort-rapid-crosscheck.sh` / `abort-final-crosscheck.sh` の **4 スクリプト共通のコマンド契約**(引数・現在状態の表示・停止確認の対話・終了コード)を定義する。4 スクリプトは同じ presentation 関数(`parse_args` / `print_current_state` / `confirm_stop`)を共有し、対象の更新(後半: aborted.txt の書き込みと条件付き UPDATE)は UC「実行を ABORTED へ遷移させる」の tier-ops.md に書く。slot 系の現在状態は成果物ファイル(execution-spec.json / started-at.txt / exitcode.txt / aborted.txt)から導出し、管理 DB は RAPID_CROSSCHECK_MODE が off 以外のときに PID を補うためだけに読む。

## コマンド契約

### abort-blue.sh / abort-green.sh / abort-rapid-crosscheck.sh / abort-final-crosscheck.sh(共通)

- **書式**: `abort-{blue|green|rapid-crosscheck|final-crosscheck}.sh --run-id <RUN_ID> [--yes] [--verbose] [--help]`
- **アクセス権**: 運用者の直接起動(relay-gate 配置ディレクトリ)。ジョブスケジューラからの非対話起動は `--yes` 付きに限る。slot 系は成果物ディレクトリへの読み書き権限(off 以外は加えて管理 DB への読み書き接続)、依頼系は管理 DB への読み書き接続が必要

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--run-id` | string | Yes | なし | 対象 run_id(`{ローカル yyyymmddThhmmss}-{job_id}-{8 hex}`)。`abort-final-crosscheck.sh` では値を `final_crosscheck_id` として解釈する(方針資料が 4 スクリプトとも `--run-id` を用いるため引数名を揃える)。`abort-blue.sh` / `abort-green.sh` では、対象 run に REQUESTED で未着手の速報比較依頼があればそれも ABORTED にする(条件「slot 中止可否判定」。後半 UC) |
| `--yes` | boolean | No | false | 停止確認プロンプトを省略して `yes` とみなす。実行ログに `answer=yes(--yes)` |
| `--verbose` | boolean | No | false | `info:` を stderr に出す |
| `--help` | boolean | No | false | 使い方を stdout に出して終了コード 0 |

- **stdin**: 停止確認の応答 1 行(`--yes` 指定時は読まない)。stdin が TTY でなく `--yes` も無い場合は読まずに終了コード 2

## 出力契約

- **stdout**: 現在状態を plain(`key=value`、パスは `key: value`)で固定順に出す。応答が yes 以外のときは末尾に `status={現在状態}` を 1 行追加する

  slot 系(`abort-blue.sh` / `abort-green.sh`。出典は成果物ファイル):
  | 行順 | キー | 出典 |
  |---|---|---|
  | 1 | `run_id` | 引数 |
  | 2 | `job_id` | `facade/<run_id>/execution-spec.json` の `job_id` |
  | 3 | `role` | スクリプト名(blue / green) |
  | 4 | `mode` | `execution-spec.json` の `slots.<role>.mode`(節が無ければ `off`) |
  | 5 | `status` | 条件「slot 実行の状態導出規則」: `exitcode.txt` あり → `0` = SUCCEEDED / 非 0 = FAILED、無く `aborted.txt` あり → ABORTED、どちらも無し → RUNNING、`started-at.txt` 無し → `-`(未起動) |
  | 6 | `pid` | RAPID_CROSSCHECK_MODE が off 以外: `slot_executions.pid`(行なし・NULL は `-`)。off: `-` |
  | 7 | `started_at` | `facade/<run_id>/<role>/started-at.txt` の中身(UTC ISO 8601 Z 付き)をホストのローカルタイムゾーンへ変換した値(ISO 8601 秒精度、指示子なし。無ければ `-`) |
  | 8 | `artifact_dir` | `$RELAY_GATE_ARTIFACT_ROOT/facade/<run_id>/<role>`(`key: value` 形式) |

  依頼系(`abort-rapid-crosscheck.sh` / `abort-final-crosscheck.sh`。出典は管理 DB):
  | 行順 | キー | 出典 |
  |---|---|---|
  | 1 | `run_id` | 引数(final は final_crosscheck_id) |
  | 2 | `job_id` | rapid: rapid_crosscheck_requests.job_id / final: `-` |
  | 3 | `role` | rapid-crosscheck / final-crosscheck |
  | 4 | `status` | 依頼の status |
  | 5 | `worker_id` | 依頼の worker_id(NULL は `-`) |
  | 6 | `lease_until` | 依頼の lease_until(ローカル時刻、指示子なし。NULL は `-`) |
  | 7 | `started_at` | 依頼の started_at(ローカル時刻、指示子なし。NULL は `-`) |

- **stderr**: プロンプト `対象ジョブのプロセスは強制終了してありますか？ [yes/no]: `(改行なし、stderr のみ)。エラーは `error: ...`、否定応答時は `info: aborted by operator; status not changed`
- **終了コード**(4 スクリプト共通。後半の中止不可 3 / DB 失敗 6 は後半 UC に記載):
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | yes 応答後に後半の状態更新が完了した(abort-blue / abort-green: RAPID_CROSSCHECK_MODE が off 以外なら加えて `rapid_crosscheck_requests` を条件付き UPDATE(`WHERE run_id=? AND status='REQUESTED'`)で ABORTED(completed_at=now)にする。0 件は正常(依頼が無い、または CLAIMED / RUNNING / 終端済み)。CLAIMED / RUNNING の依頼は変更せず abort-rapid-crosscheck.sh の対象のまま。詳細は後半 UC) |
  | 2 | 入力エラー | `--run-id` 欠落・形式不正、未知のオプション、非 TTY で `--yes` なし |
  | 3 | 業務エラー | 対象が存在しない(slot 系: `error: run not found run_id=... role=...`(`facade/<run_id>/execution-spec.json` が無い)。依頼系: `error: request not found run_id=...`(依頼レコードが無い))、応答が yes 以外(状態不変)、RAPID_CROSSCHECK_MODE=off で abort-rapid-crosscheck(依頼レコードが管理 DB にしか無い。`error: management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=...`)、`final-crosscheck.env` / FINAL_DB_CONN_REF が無い(abort-final-crosscheck のみ。`error: management db is not configured run_id=...`) |
  | 6 | 実行エラー | 成果物ファイルの読み取り失敗(存在するが読めない / execution-spec.json が JSON 不正)、管理 DB 接続・SQL 失敗 |

## UC ロジック

- **バリデーション**: presentation で `--run-id` 必須・形式(先頭 16 文字 `yyyymmddThhmmss`、末尾 8 文字 hex)を検証。`--key=value` 形式・短縮形は不可
- **確認プロンプト**: 現在状態を stdout に出し切ってから、stderr にプロンプトを出し stdin を 1 行読む。`yes`(小文字完全一致)のみ肯定。空 Enter・`y`・`YES`・`no` は否定(意図的な壁)。`--yes` でプロンプト省略。非 TTY(`[ ! -t 0 ]`)かつ `--yes` なしは `error: interactive confirmation required (use --yes for non-interactive)`、終了コード 2(現在状態も出さずに終了する)
- **冪等性**: 前半は読み取りのみ。否定応答は何度実行しても状態を変えない
- **エラーハンドリング**: 対象不在・管理 DB なし(依頼系)は状態を読む段階で終了コード 3。ファイル読み取り失敗・DB 障害は 6。エラーは 1 回だけ出す(CLR-004)
- **クラッシュ耐性**: 前半で落ちても書き込みは無い。再実行でそのままやり直す
- **実行ログ**(CLP-008 / NFR E.7.1.1): `RELAY_GATE_LOG_DIR/abort-{role}.sh.log` に、起動 `INFO abort requested operator={OS ユーザー名} run_id=... role=...`、現在状態 `INFO current state status=... mode=...`、応答 `INFO operator answered operator=ops01 answer=yes|no|yes(--yes) run_id=... role=...` を残す。否定応答は `INFO status not changed`。ログ行形式は `_cross-cutting/ux-ui/ui-design.md` の `{script} {run_id} {ローカル出力日時} {LEVEL} {message}` に従い、情報「実行ログ」の属性「出力日時」はこの ローカル時刻列に対応する
- **現在状態の出典(スクリプトごとに異なる)**:
  - abort-blue / abort-green: 成果物ファイルが正本。`facade/<run_id>/execution-spec.json`(無ければ `error: run not found run_id=... role=...` で 3)→ `slots.<role>` 節(無ければ mode=off)→ `facade/<run_id>/<role>/started-at.txt` / `exitcode.txt` / `aborted.txt` の有無と値(条件「slot 実行の状態導出規則」)。`RELAY_GATE_CONFIG_DIR/feature-flag.env` の `RAPID_CROSSCHECK_MODE` が off 以外なら `slot_executions(run_id, slot)` の `pid` を表示に補う(行が無くても 3 にしない。`pid=-`)。off では管理 DB に接続しない
  - abort-rapid-crosscheck: `RAPID_CROSSCHECK_MODE` を参照し、off では依頼レコードが存在しないため管理 DB 接続前に `error: management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=...`、終了コード 3。off 以外は `rapid_crosscheck_requests(run_id)` を読む
  - abort-final-crosscheck: **`RAPID_CROSSCHECK_MODE` を参照しない**(確報クロスチェックは速報モードに依存しない。方針資料の設定契約・契約 `config_files.final-crosscheck.env.readers`)。管理 DB 有無は `final-crosscheck.env` の `FINAL_DB_CONN_REF` のみで判定し、ファイルまたはキーが無ければ管理 DB 接続前に `error: management db is not configured run_id=...`(`(RAPID_CROSSCHECK_MODE=off)` の付記なし)、終了コード 3。RAPID_CROSSCHECK_MODE=off の環境でも `final-crosscheck.env` があれば通常どおり動作する

## データモデル変更

読み取りのみ(列定義は後半 UC の tier-ops.md「データモデル変更」を正本とする)。

| テーブル / ファイル | 読む列・キー | 変更種別 |
|---|---|---|
| `facade/<run_id>/execution-spec.json` | job_id, slots.<role>.mode(slot 系。存在確認を兼ねる) | 追加(参照) |
| `facade/<run_id>/<role>/started-at.txt` | 有無と中身(slot 系。started_at 表示と未起動判定) | 追加(参照) |
| `facade/<run_id>/<role>/exitcode.txt` | 有無と中身(slot 系。SUCCEEDED / FAILED の導出) | 追加(参照) |
| `facade/<run_id>/<role>/aborted.txt` | 有無(slot 系。ABORTED の導出) | 追加(参照) |
| slot_executions | run_id, slot, pid(slot 系。off 以外のみ) | 追加(参照) |
| rapid_crosscheck_requests | run_id, job_id, status, worker_id, lease_until, started_at | 追加(参照) |
| final_crosscheck_requests | final_crosscheck_id, status, worker_id, lease_until, started_at | 追加(参照) |

## ビジネスルール

- 現在状態を表示した後に対話確認し、yes 以外は状態を変更せず終了する(条件「停止確認応答」)
- slot 実行の現在状態は成果物のファイル正本から導出する(条件「slot 実行の状態導出規則」)。RAPID_CROSSCHECK_MODE=off でも表示できる
- スクリプト自身はプロセス・Pod・SSH 接続先の処理を停止しない。停止は運用者が行う
- プロンプトは stderr、現在状態は stdout(条件「CLI とメールによる提示」、ui-design.md)
- 中止操作は指示者(OS ユーザー名)と応答を実行ログに残す(arch CLP-008、NFR E.7.1.1)
- 引数値は `--key value` 形式のみ。未知オプションは終了コード 2

## ティア完了条件(BDD)

```gherkin
Feature: 現在状態を確認して停止確認に応答する - 実行監視・復旧ティア

  Scenario: abort-green.sh が現在状態を固定順で出しプロンプトを stderr に出す
    Given facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の job_id が JOB001、slots.green.mode が background で、green/started-at.txt の中身が 2026-08-30T11:30:05Z、exitcode.txt と aborted.txt は無い
    And RAPID_CROSSCHECK_MODE=background で slot_executions(run_id, green).pid=12345 である
    When TTY から `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行し stdin に `no` を入力する
    Then stdout の 1〜8 行目のキーが run_id, job_id, role, mode, status, pid, started_at, artifact_dir の順で、5 行目が `status=RUNNING`、6 行目が `pid=12345`、7 行目が `started_at=2026-08-30T11:30:05`(started-at.txt の UTC 値をローカルへ変換。TZ=UTC 前提)、9 行目が `status=RUNNING` である
    And stderr に `対象ジョブのプロセスは強制終了してありますか？ [yes/no]: ` と `info: aborted by operator; status not changed` が出て終了コード 3 である

  Scenario: abort-blue.sh は RAPID_CROSSCHECK_MODE=off でも成果物ファイルから現在状態を出す
    Given RAPID_CROSSCHECK_MODE=off で facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.blue.mode が background、blue/started-at.txt があり exitcode.txt と aborted.txt は無い
    When TTY から `abort-blue.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行し stdin に `no` を入力する
    Then stdout の 4〜6 行目が `mode=background` / `status=RUNNING` / `pid=-` で、管理 DB への接続は行われない

  Scenario: abort-green.sh は exitcode.txt がある slot を終端済みとして表示する
    Given facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.green.mode が background で、green/ に started-at.txt と exitcode.txt(中身 0)がある
    When `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then stdout の 5 行目が `status=SUCCEEDED` で、後半 UC が中止不可として終了コード 3 で終了する

  Scenario: abort-green.sh は slots.green 節が無い run を mode=off として表示する
    Given facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json に slots.green 節が無い(GREEN_MODE=off で起動された run)
    When `abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then stdout の 4〜5 行目が `mode=off` / `status=-` で、後半 UC が中止不可として終了コード 3 で終了する

  Scenario: abort-final-crosscheck.sh が依頼の現在状態を出す
    Given final_crosscheck_requests に final_crosscheck_id=20260830T020000-final-1a2b3c4d status=RUNNING worker_id=worker-db-01 lease_until=2026-08-30T02:15:00 started_at=2026-08-30T02:05:00 がある(日時はローカル時刻。TZ=UTC 前提)
    When `abort-final-crosscheck.sh --run-id 20260830T020000-final-1a2b3c4d --yes` を実行する
    Then stdout の 1〜7 行目が run_id=20260830T020000-final-1a2b3c4d / job_id=- / role=final-crosscheck / status=RUNNING / worker_id=worker-db-01 / lease_until=2026-08-30T02:15:00 / started_at=2026-08-30T02:05:00 である

  Scenario: abort-final-crosscheck.sh は RAPID_CROSSCHECK_MODE=off でも final-crosscheck.env があれば動く
    Given RAPID_CROSSCHECK_MODE=off で final-crosscheck.env に FINAL_DB_CONN_REF が設定され、final_crosscheck_requests に final_crosscheck_id=20260830T020000-final-1a2b3c4d status=RUNNING がある
    When `abort-final-crosscheck.sh --run-id 20260830T020000-final-1a2b3c4d --yes` を実行する
    Then 終了コード 0 で stdout の 1 行目が `run_id=20260830T020000-final-1a2b3c4d`、stderr に `management db is not configured` は出ない

  Scenario: abort-final-crosscheck.sh は final-crosscheck.env が無ければ終了コード 3
    Given RAPID_CROSSCHECK_MODE=background で final-crosscheck.env が存在しない
    When `abort-final-crosscheck.sh --run-id 20260830T020000-final-1a2b3c4d --yes` を実行する
    Then 終了コード 3 で stderr の 1 行目が `error: management db is not configured run_id=20260830T020000-final-1a2b3c4d` で、管理 DB への接続は行われない

  Scenario: abort-rapid-crosscheck.sh は RAPID_CROSSCHECK_MODE=off では終了コード 3
    Given RAPID_CROSSCHECK_MODE=off である
    When `abort-rapid-crosscheck.sh --run-id 20260830T113000-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 3 で stderr の 1 行目が `error: management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=20260830T113000-JOB001-3f9a1c2e` で、管理 DB への接続は行われない

  Scenario: YES(大文字)は否定として扱う
    Given facade/20260830T113000-JOB001-3f9a1c2e/execution-spec.json の slots.blue.mode が background で blue/ に started-at.txt だけがある
    When TTY から `abort-blue.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行し stdin に `YES` を入力する
    Then 終了コード 3 で blue/aborted.txt は作成されない

  Scenario: --run-id 欠落は終了コード 2
    When `abort-green.sh` を引数なしで実行する
    Then 終了コード 2 で stderr に `error: option required option=--run-id` が出る

  Scenario: 非 TTY で --yes なしは現在状態を出さずに終了コード 2
    When stdin をパイプにして `abort-rapid-crosscheck.sh --run-id 20260830T113000-JOB001-3f9a1c2e` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr に `error: interactive confirmation required (use --yes for non-interactive)` が出る
```
