# 速報比較依頼を claim する - 速報クロスチェックティア仕様

## 変更概要

`rapid-crosscheck-worker.sh` を追加する。presentation(起動口・poll ループ)→ usecase `claim_next_request` → domain `lease_policy` → repository `rapid_request_release_expired` / `rapid_request_claim` → gateway(RDB 条件付き UPDATE)。本 UC は poll / claim / lease までを定義し、claim 後の比較実行は UC「比較ツールでジョブ単位比較を実行して結果を登録する」に続く。

## コマンド契約

### rapid-crosscheck-worker.sh

- **書式**: `rapid-crosscheck-worker.sh [--once] [--worker-id <id>] [--verbose] [--help]`
- **アクセス権**: ジョブスケジューラの定期起動(`--once`)または常駐プロセス。管理 DB は閉域セグメント内の OS 権限で接続(CTP-002)

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--once` | boolean | No | false | 1 回だけ poll / claim / 実行して終了する(定期ジョブ運転用) |
| `--worker-id` | string | No | `{hostname}-{pid}` | claim 時に記録する worker_id(英数字・`_`・`-`。既定値のホスト名に `.` が含まれる場合は `-` に置換して生成する。cli-command-contract.yaml `worker_id_default`) |
| `--verbose` | boolean | No | false | info を stderr に出す |

- **stdin**: なし
- **設定ファイル(読む順)**:
  1. `$RELAY_GATE_CONFIG_DIR/feature-flag.env` の `RAPID_CROSSCHECK_MODE`(on / off)。off なら管理 DB に接続せず `error: management db is not configured mode=off` で終了コード 3(rapid-crosscheck.env は読まない)。ファイル不在・値が on / off 以外は終了コード 2
  2. on のとき `$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env`(env 形式。確報の `final-crosscheck.env` / 監視の `hang-detector.env` と同じ流儀。契約 `cli-command-contract.yaml` の config_files が正)
  | キー | 必須 | 既定 | 説明 |
  |---|---|---|---|
  | `RAPID_DB_CONN_REF` | Yes(`RAPID_CROSSCHECK_MODE=on` のとき) | — | 速報管理 DB 接続情報の参照名(値は置かない。`HANG_DB_CONN_REF` と同じ参照名を指してよい)。rapid-crosscheck-runner.sh / rapid-crosscheck-worker.sh / rapid-crosscheck-result.sh が読む |
  | `RAPID_LEASE_SEC` | No | 600 | claim lease(秒)。lease_until = now + RAPID_LEASE_SEC |
  | `RAPID_POLL_INTERVAL_SEC` | No | 30 | 常駐時の poll 間隔(秒) |
  - on でファイル不在は `error: config file not found path: <path>`、`RAPID_DB_CONN_REF` 欠落は `error: option required option=RAPID_DB_CONN_REF path: <path>` で終了コード 2(ui-design.md の全コマンド共通定型文。管理 DB へは接続しない)。`management db is not configured` は off(3)専用。整数キーは 1 以上
- **環境変数(テスト専用)**: `RELAY_GATE_NOW`(テスト専用環境変数。ISO 8601 UTC。本番では未設定。設定されているときは now() の代わりにこの値を現在時刻として使う)。lease_until の算出と lease 失効判定に使う。契約 `cli-command-contract.yaml` の environment_variables が正

## 出力契約

- **stdout**: `--once` で claim できたとき `run_id=` / `job_id=` / `worker_id=` / `lease_until=` の 4 行(続けて比較実行 UC の行)。claim 0 件のとき 0 行。常駐時は stdout に出さず実行ログのみ
- **stderr**: `error: management db connection failed worker_id=... conn_ref=...`(6)、`error: config file not found path: ...`(2。on で rapid-crosscheck.env 不在)、`error: option required option=RAPID_DB_CONN_REF path: ...`(2)、`error: management db is not configured mode=off`(3)、`error: unknown option option=...`、`info: no request to claim worker_id=...`(--verbose)
- **実行ログ**(`RELAY_GATE_LOG_DIR/rapid-crosscheck-worker.sh.log`): `INFO claimed run_id=... worker_id=... lease_until=...` / `INFO lease expired released count=n` / `DEBUG no request to claim` / `ERROR management db connection failed worker_id=... conn_ref=...`。行形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {UTC 出力日時} {LEVEL} {message}`)に従い、情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する(run_id 未確定の行は `-`)
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | `--once` で 1 件処理できた、または依頼が無かった。常駐時は SIGTERM で 0 |
  | 2 | 入力エラー | 未知のオプション、`--worker-id` 形式不正、feature-flag.env 不在・`RAPID_CROSSCHECK_MODE` 列挙外、on で rapid-crosscheck.env 不在・`RAPID_DB_CONN_REF` 欠落・整数値不正 |
  | 3 | 業務エラー | `RAPID_CROSSCHECK_MODE=off`(管理 DB が構成されていない。DB に接続せず終了) |
  | 6 | 実行エラー | claim の条件付き UPDATE 失敗、DB 接続失敗(常駐時はリトライ後に継続。下記) |

## イベント処理仕様

### rapid-crosscheck-requests(subscribe)

- **トリガー**: ジョブスケジューラの定期起動(`--once`)または常駐(poll 間隔 30 秒)
- **入力チャネル**: 管理 DB `rapid_crosscheck_requests`(status=REQUESTED)
- **出力チャネル**: なし(同テーブルの状態更新のみ)
- **AsyncAPI**: [asyncapi.yaml](../../../_cross-cutting/api/asyncapi.yaml) の `channels.rapid-crosscheck-requests`

#### 処理フロー

1. lease 失効分の解放: `UPDATE rapid_crosscheck_requests SET status='REQUESTED', worker_id=NULL, lease_until=NULL WHERE status='CLAIMED' AND lease_until < ? AND started_at IS NULL`
2. claim: `UPDATE rapid_crosscheck_requests SET status='CLAIMED', worker_id=?, lease_until=? WHERE run_id = (SELECT run_id FROM rapid_crosscheck_requests WHERE status='REQUESTED' ORDER BY requested_at LIMIT 1) AND status='REQUESTED'`(RETURNING run_id, job_id。RDB 方言差は gateway で吸収)
3. 更新 1 行なら比較実行 UC へ。0 行なら `--once` は終了、常駐は sleep して 1 へ

#### エラーハンドリング

| エラー種別 | リトライ | DLQ | 説明 |
|-----------|---------|-----|------|
| 管理 DB 接続失敗 | Yes(常駐: 次 poll で再試行。`--once`: 終了コード 6) | No | 実行ログ ERROR。定期起動なら次回起動で回復 |
| 条件付き UPDATE 0 行(競合) | No(正常。次 poll) | No | 他 worker が先取。ログ DEBUG |
| lease 失効の解放失敗 | Yes(次 poll) | No | claim へ進まず終了コード 6(`--once`) |
| DLQ | — | なし | FAILED はハング検知の error 通知で運用者に届き、background-rerun で再作成する |

## UC ロジック

- **バリデーション**: `--worker-id` は英数字・`_`・`-`(64 文字以内)。rapid-crosscheck.env の整数値は 1 以上、`RAPID_DB_CONN_REF` は非空
- **確認プロンプト**: なし
- **冪等性**: 同じ worker が `--once` を繰り返しても、各回は「REQUESTED があれば 1 件 claim」。claim 済みの依頼を再 claim しない
- **エラーハンドリング**: DB 失敗は gateway → usecase(1 回ログ)→ presentation で 6。常駐時は ERROR ログ後に poll 間隔で継続する
- **クラッシュ耐性**: claim 直後に worker が落ちても、started_at IS NULL のため lease 失効(10 分)後に別 worker が再取得する。RUNNING 移行後(started_at 設定済み)は解放しない(hang-detector がハング疑いとして通知し、運用者が abort-rapid-crosscheck → background-rerun で復旧)
- **速報と確報のモデル分離**: final_crosscheck_requests を poll しない

## データモデル変更

### 設定ファイル

| ファイル | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| `$RELAY_GATE_CONFIG_DIR/feature-flag.env` | env | `RAPID_CROSSCHECK_MODE`(off なら DB に接続せず 3) | 追加(参照) |
| `$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` | env | `RAPID_DB_CONN_REF` / `RAPID_LEASE_SEC` / `RAPID_POLL_INTERVAL_SEC`(上記「設定ファイル」。on のときのみ読む) | 追加 |

### rapid_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | string | REQUESTED → CLAIMED(claim)、CLAIMED → REQUESTED(lease 失効) | 追加(更新) |
| worker_id | string | claim した worker。解放時 NULL | 追加(更新) |
| lease_until | datetime | UTC。claim 時 now + 10 分。解放時 NULL | 追加(更新) |
| started_at | datetime | 解放判定に使う(NULL = 未開始) | 追加(参照) |
| requested_at | datetime | claim 順序 | 追加(参照) |

## ビジネスルール

- claim 排他: worker_id と lease_until を設定し、lease 有効中は他 worker が取得できない
- lease 失効判定: lease_until 経過かつ未開始なら REQUESTED に戻す
- 依頼状態遷移規則: 速報と確報で同じライフサイクル(本 tier は速報のみ扱う)
- 計画停止(NFR A.1.1.1): `--once` で定期ジョブ運転でき常駐前提にしない
- 速報クロスチェック有効判定: off のとき管理 DB に接続しない(終了コード 3)

## ティア完了条件(BDD)

```gherkin
Feature: 速報比較依頼を claim する - 速報クロスチェックティア

  Scenario: --once で REQUESTED を 1 件 claim する
    Given rapid_crosscheck_requests に status=REQUESTED の行が run_id=20260830T113000Z-JOB001-3f9a1c2e(requested_at=2026-08-30T11:45:10Z)と run_id=20260830T113500Z-JOB002-1a2b3c4d(requested_at=2026-08-30T11:50:10Z)の 2 件ある
    When `rapid-crosscheck-worker.sh --once --worker-id worker-01` を実行する
    Then 終了コード 0 で stdout に `run_id=20260830T113000Z-JOB001-3f9a1c2e` と `worker_id=worker-01` が出て、JOB002 の依頼は REQUESTED のままである

  Scenario: 依頼が無いときは 0 で終了する
    Given rapid_crosscheck_requests に status=REQUESTED の行が無い
    When `rapid-crosscheck-worker.sh --once` を実行する
    Then 終了コード 0 で stdout は 0 行である

  Scenario: lease 失効かつ未開始を REQUESTED に戻してから claim する
    Given rapid_crosscheck_requests に status=CLAIMED, worker_id=worker-01, lease_until=2026-08-30T11:55:40Z, started_at=NULL の行があり、RELAY_GATE_NOW=2026-08-30T11:56:00Z が設定されている
    When `rapid-crosscheck-worker.sh --once --worker-id worker-02` を実行する
    Then 終了コード 0 で依頼の worker_id は worker-02、lease_until は 2026-08-30T12:06:00Z である

  Scenario: RUNNING(started_at 設定済み)は lease 失効しても解放しない
    Given rapid_crosscheck_requests に status=RUNNING, worker_id=worker-01, lease_until=2026-08-30T11:55:40Z, started_at=2026-08-30T11:46:00Z の行があり、RELAY_GATE_NOW=2026-08-30T12:30:00Z が設定されている
    When `rapid-crosscheck-worker.sh --once --worker-id worker-02` を実行する
    Then 依頼は RUNNING, worker_id=worker-01 のままで、終了コードは 0 である

  Scenario: worker_id の形式が不正
    When `rapid-crosscheck-worker.sh --once --worker-id "w 1"` を実行する
    Then 終了コード 2 で stderr に `error: invalid worker_id value=w 1` が出る

  Scenario: rapid-crosscheck.env に RAPID_DB_CONN_REF が無い
    Given feature-flag.env に RAPID_CROSSCHECK_MODE=on があり、$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env に RAPID_DB_CONN_REF の行が無い
    When `rapid-crosscheck-worker.sh --once` を実行する
    Then 終了コード 2 で stderr に `error: option required option=RAPID_DB_CONN_REF path: $RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` が出て、管理 DB へは接続しない

  Scenario: rapid-crosscheck.env が無い
    Given feature-flag.env に RAPID_CROSSCHECK_MODE=on があり、$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env が存在しない
    When `rapid-crosscheck-worker.sh --once` を実行する
    Then 終了コード 2 で stderr に `error: config file not found path: $RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` が出て、管理 DB へは接続しない

  Scenario: RAPID_CROSSCHECK_MODE=off では DB に接続せず 3 で終了する
    Given feature-flag.env に RAPID_CROSSCHECK_MODE=off があり、rapid-crosscheck.env が存在しない
    When `rapid-crosscheck-worker.sh --once` を実行する
    Then 終了コード 3 で stderr に `error: management db is not configured mode=off` が出て、管理 DB へは接続しない
```
