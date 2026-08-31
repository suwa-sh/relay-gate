# 確報比較依頼を claim する - 確報クロスチェックティア仕様

## 変更概要

`final-crosscheck-worker.sh` を追加する(起動口と poll / claim 部分)。presentation(引数検証・worker_id 決定)→ usecase(lease 失効回収 → 1 件 claim → 次 UC へ)→ domain(lease 失効判定・REQUESTED → CLAIMED)→ repository / gateway(条件付き UPDATE)。DB セグメント上で定期起動(`--once`)または常駐で動かす。claim 後の比較実行は UC「比較ツールで日次全量比較を実行して結果を保存する」の tier md に続く。

## コマンド契約

### final-crosscheck-worker.sh

- **書式**: `final-crosscheck-worker.sh [--once] [--worker-id <id>] [--verbose] [--help]`
- **アクセス権**: ジョブスケジューラの定期ジョブ(`--once`)、または DB セグメント上の常駐プロセス。管理 DB へは閉域セグメント内の OS 権限で接続する(CTP-002)。運用者が手動起動してもよい

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--once` | boolean | No | false | 1 回だけ poll / claim / 実行して終了する(定期ジョブ運転。NFR A.1.1.1) |
| `--worker-id` | string | No | `{hostname}-{pid}`(仮採用) | claim に記録する worker 識別子。英数字・`_`・`-` のみ(cli-command-contract.yaml `worker_id_default`。既定値のホスト名は `.` を `-` に置換して生成する) |
| `--verbose` | boolean | No | false | `info:` を stderr にも出す(既定は実行ログのみ) |
| `--help` | boolean | No | false | usage を stdout に出し終了コード 0 |

- **stdin**: なし

#### 設定契約(final-crosscheck.env。UC「確報比較依頼を登録して終端状態まで待機する」と共有)

| キー | 型 | 必須 | 既定値 | 検証ルール |
|------|---|------|-------|-----------|
| `FINAL_LEASE_MINUTES` | integer | No | 10 | 1 以上の整数 |
| `FINAL_WORKER_POLL_INTERVAL_SEC` | integer | No | 30 | 1 以上の整数(常駐時の poll 間隔) |
| `FINAL_DB_CONN_REF` | string | Yes | — | 管理 DB 接続情報の参照名 |

- 環境変数 `RELAY_GATE_NOW`(テスト専用。cli-command-contract.yaml environment_variables で宣言。ISO 8601 UTC。本番未設定): 設定時はシステム時刻の代わりに now として使う。lease_until の算出と lease 失効判定の now は worker がバインド値として SQL に渡す(DB の now() に依存しない)

## 出力契約

- **stdout**: 既定では何も出さない(常駐ログは実行ログへ。ui-design.md「大量出力」)。`--once` で claim できた場合も stdout には出さず、実行ログに残す
- **stderr**: `error: ...`(+ `hint:`)。`--verbose` 時は `info: claimed final_crosscheck_id=... worker_id=...` / `info: no request to claim worker_id=...`
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | `--once` で 1 サイクル完了(claim できた / 依頼が無かった、のどちらも 0)。常駐は SIGTERM で 0 |
  | 2 | 入力・設定検証エラー | 未知のオプション、`--worker-id` の文字種不正、`final-crosscheck.env` 不在または必須キー欠落 |
  | 6 | 実行エラー | 管理 DB 接続・SQL 失敗(lease 回収・claim の UPDATE)、比較ツール起動失敗(次 UC)、内部エラー |

- 実行ログ(`RELAY_GATE_LOG_DIR/final-crosscheck-worker.sh.log`、run_id 欄は final_crosscheck_id。claim 前は `-`):
  - ログ行の形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {UTC 出力日時} {LEVEL} {message}`)に従う。情報「実行ログ」の属性「出力日時」はこの UTC 出力日時の列に対応する
  - `INFO poll started worker_id=...`
  - `WARN lease expired requests reset count=n`
  - `INFO claimed final_crosscheck_id=... worker_id=... lease_until=...`
  - `INFO no request to claim worker_id=...`

## UC ロジック

- **バリデーション**: `--worker-id` は `^[A-Za-z0-9_-]{1,64}$`(契約どおり `.` は含めない。既定値 `{hostname}-{pid}` はホスト名の `.` を `-` に置換して生成する。仮採用)。`--once` と常駐は排他ではない(`--once` 省略で常駐)
- **確認プロンプト**: なし
- **冪等性**: claim は条件付き UPDATE(`WHERE status='REQUESTED'`)で更新件数 1 のときだけ成功するため、同時に複数 worker が動いても 1 依頼は 1 worker だけが取る。lease 回収も `WHERE status='CLAIMED' AND lease_until < now AND started_at IS NULL` で冪等
- **poll サイクル**: (1) lease 失効回収 → (2) REQUESTED を requested_at 昇順で 1 件 claim → (3) claim できたら次 UC(RUNNING → 比較 → 保存)→ (4) `--once` なら終了、常駐なら `FINAL_WORKER_POLL_INTERVAL_SEC` 待って (1) へ
- **エラーハンドリング**: DB 失敗は `error: management db connection failed worker_id=... conn_ref=...` 終了コード 6(常駐時も終了する。再起動はジョブスケジューラ / 監視側の責務)。1 サイクルで claim に失敗(更新件数 0)はエラーではない
- **クラッシュ耐性**: claim 直後(RUNNING 前)に worker が落ちると依頼は CLAIMED のまま残り、lease_until(10 分)経過後に別 worker の poll で REQUESTED に戻る。RUNNING に進んだ後(started_at あり)は戻さない(比較が動いている可能性があるため。中止は運用者の `abort-final-crosscheck.sh`)
- **速報と確報のモデル分離**: SQL の対象は `final_crosscheck_requests` のみ

## イベント処理仕様

### final-crosscheck-requests(subscribe)

- **トリガー**: ジョブスケジューラの定期ジョブ(`--once`)または常駐 poll(`FINAL_WORKER_POLL_INTERVAL_SEC` 秒ごと)
- **入力チャネル**: 管理 DB `final_crosscheck_requests`(status=REQUESTED の行)
- **出力チャネル**: なし(同じテーブルの status 更新)
- **AsyncAPI**: [asyncapi.yaml](../../../_cross-cutting/api/asyncapi.yaml) の `channels.final-crosscheck-requests` を参照

#### 処理フロー

1. `UPDATE final_crosscheck_requests SET status='REQUESTED', worker_id=NULL, lease_until=NULL WHERE status='CLAIMED' AND lease_until < :now AND started_at IS NULL`(`:now` は worker が渡す現在時刻。`RELAY_GATE_NOW` 設定時はその値)
2. `UPDATE final_crosscheck_requests SET status='CLAIMED', worker_id=?, lease_until=:now + FINAL_LEASE_MINUTES WHERE final_crosscheck_id = (SELECT final_crosscheck_id FROM final_crosscheck_requests WHERE status='REQUESTED' ORDER BY requested_at LIMIT 1) AND status='REQUESTED'`(更新件数 1 のみ成功。RDB 方言の差異は gateway で吸収。CTR-003)
3. 更新件数 1 なら claim した依頼を UC「比較ツールで日次全量比較を実行して結果を保存する」へ渡す

#### エラーハンドリング

| エラー種別 | リトライ | DLQ | 説明 |
|-----------|---------|-----|------|
| DB 接続・SQL 失敗 | No(プロセス終了) | No | 終了コード 6。次回の定期起動 / 再起動で再開。依頼は変更されない |
| claim 競合(更新件数 0) | Yes(次サイクル) | No | エラーではない。`no request to claim` |
| lease 失効(worker クラッシュ) | Yes(別 worker が再取得) | No | REQUESTED へ戻す。DLQ は持たない(FAILED / ABORTED が終端。再実行はジョブスケジューラの正規ジョブ) |

## データモデル変更

### final_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | string | REQUESTED → CLAIMED(claim)、CLAIMED → REQUESTED(lease 回収) | 追加(更新) |
| worker_id | string | claim した worker。回収時 NULL | 追加(更新) |
| lease_until | datetime | now + FINAL_LEASE_MINUTES。回収時 NULL | 追加(更新) |
| started_at | datetime | NULL のときだけ回収対象(参照) | 追加(参照) |
| requested_at | datetime | claim 順序(参照) | 追加(参照) |

## ビジネスルール

- 依頼状態遷移規則: worker の取得で CLAIMED。速報と同じライフサイクル
- claim 排他: worker_id + lease_until。lease 有効中は他 worker が取得できない
- lease 失効判定: 失効かつ未開始(started_at IS NULL)なら REQUESTED に戻す
- 速報と確報のモデル分離: `rapid_crosscheck_requests` には触れない
- lease 10 分 / poll 30 秒は仮採用(_inference.md #6)。設定で上書き可

## ティア完了条件(BDD)

```gherkin
Feature: 確報比較依頼を claim する - 確報クロスチェックティア

  Scenario: --once で 1 件 claim して終了コード 0
    Given final_crosscheck_requests に status=REQUESTED の行が 2 件(requested_at=2026-08-30T21:00:00Z と 21:05:00Z)ある
    And crosscheck-job-map.tsv の確報行の compare_command が、起動後に停止シグナルを受けるまで待機するスタブを指す(claim 後の比較実行を止めて途中状態を観測する。--once は claim 後に同一プロセスで比較実行まで進むため、プロセス終了時点の status=CLAIMED は観測できない)
    And RELAY_GATE_NOW=2026-08-30T21:00:30Z である
    When `final-crosscheck-worker.sh --once --worker-id final-worker-01` を実行する
    Then スタブが待機している間、requested_at=2026-08-30T21:00:00Z の行だけが worker_id=final-worker-01 lease_until=2026-08-30T21:10:30Z で status は CLAIMED または RUNNING になり、21:05:00Z の行は status=REQUESTED のままである
    And スタブに停止シグナルを送ると終了コード 0 で終了し、stdout は 0 行である

  Scenario: 依頼が無くても終了コード 0
    Given final_crosscheck_requests に REQUESTED の行が無い
    When `final-crosscheck-worker.sh --once --verbose` を実行する
    Then 終了コード 0 で stderr に "info: no request to claim worker_id=" で始まる行が出る

  Scenario: lease 失効の回収
    Given status=CLAIMED lease_until=2026-08-30T21:10:30Z started_at=NULL の行がある
    And compare_command が停止シグナルを受けるまで待機するスタブを指す
    And RELAY_GATE_NOW=2026-08-30T21:11:00Z である
    When `final-crosscheck-worker.sh --once --worker-id final-worker-02` を実行する
    Then スタブが待機している間、該当行は worker_id=final-worker-02 lease_until=2026-08-30T21:21:00Z で status は CLAIMED または RUNNING である
    And 実行ログに "WARN lease expired requests reset count=1" が残る

  Scenario: --worker-id の文字種が不正
    When `final-crosscheck-worker.sh --once --worker-id "worker 01"` を実行する
    Then 終了コード 2 で stderr に "error: invalid worker_id value=worker 01" が出る
```
