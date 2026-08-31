# 実行を ABORTED へ遷移させる - 実行監視・復旧ティア仕様

## 変更概要

abort-* 4 スクリプトの後半(yes 応答後)を定義する。各スクリプトの対象テーブル・可否判定・条件付き UPDATE・parallel_runs の併更新・実行ログを規定する。コマンド契約(引数・対話・終了コード)は UC「現在状態を確認して停止確認に応答する」の tier-ops.md と共通である。

## コマンド契約

### abort-* 共通(前半 UC の契約を使う)

- **書式**: `abort-{blue|green|rapid-crosscheck|final-crosscheck}.sh --run-id <ID> [--yes]`
- **アクセス権**: 運用者の直接起動 / ジョブスケジューラ(`--yes`)

#### 引数・オプション

前半 UC の tier-ops.md と同一(`--run-id` 必須、`--yes` 任意)。

- **stdin**: 前半 UC と同一

### スクリプトごとの対象と条件付き UPDATE

| スクリプト | 対象テーブル | キー | 可否条件(domain) | 条件付き UPDATE(gateway) |
|---|---|---|---|---|
| `abort-blue.sh` | `slot_executions` | `run_id = ? AND slot = 'blue'` | `mode = 'background' AND status = 'RUNNING'` | `UPDATE slot_executions SET status = 'ABORTED', completed_at = ? WHERE run_id = ? AND slot = 'blue' AND status = 'RUNNING' AND mode = 'background'` |
| `abort-green.sh` | `slot_executions` | `run_id = ? AND slot = 'green'` | 同上 | `UPDATE slot_executions SET status = 'ABORTED', completed_at = ? WHERE run_id = ? AND slot = 'green' AND status = 'RUNNING' AND mode = 'background'` |
| `abort-rapid-crosscheck.sh` | `rapid_crosscheck_requests` | `run_id = ?` | `status = 'RUNNING'` | `UPDATE rapid_crosscheck_requests SET status = 'ABORTED', completed_at = ? WHERE run_id = ? AND status = 'RUNNING'` |
| `abort-final-crosscheck.sh` | `final_crosscheck_requests` | `final_crosscheck_id = ?` | `status = 'RUNNING'` | `UPDATE final_crosscheck_requests SET status = 'ABORTED', completed_at = ? WHERE final_crosscheck_id = ? AND status = 'RUNNING'` |
| 共通(併更新) | `parallel_runs` | `run_id = ?` | 上の UPDATE が 1 件のとき | `UPDATE parallel_runs SET status = 'ABORTED', completed_at = ? WHERE run_id = ? AND status IN ('STARTED', 'RUNNING')`(**COMPLETED の parallel_runs は更新しない。更新件数 0 で可**。通常 run の速報比較依頼を中止するときは foreground 中継完了で COMPLETED 済みのため 0 件になる。final は parallel_runs を持たないため実行しない。STARTED → ABORTED は状態.tsv に無い遷移で rdra-feedback 対象) |

- 対象の UPDATE と parallel_runs の UPDATE は **1 トランザクション**で行う。対象の更新件数が 0 なら ROLLBACK。parallel_runs の更新件数は 0 でも COMMIT する
- 運用注記(UC「速報比較依頼だけを新規作成する」と共通): `background-rerun.sh --role rapid-crosscheck` で作られた run の parallel_runs は COMPLETED 遷移が未定義で RUNNING のまま残る。その依頼を abort-rapid-crosscheck.sh で中止した場合に限り、併更新で parallel_runs も ABORTED になる(rdra-feedback 対象)
- 更新件数 0 の判定は「domain で不可と判定済み」なら `run is not abortable ... mode=... status=...`、「domain で可と判定したが UPDATE が 0 件」なら `... (state changed concurrently)` を出す。いずれも終了コード 3
- `completed_at` に書く値は 1 回の実行で 1 つ(UTC 秒精度)。stdout の `aborted_at` に同じ値を出す。テスト専用環境変数 `RELAY_GATE_NOW`(ISO 8601 UTC。本番では未設定)が設定されていれば now() の代わりにその値を使う

## 出力契約

- **stdout**(前半の現在状態に続けて):
  | 行順 | キー | 値 |
  |---|---|---|
  | 1 | `status` | `ABORTED` |
  | 2 | `aborted_at` | UTC ISO 8601(completed_at と同じ値) |
- **stderr**: `error: run is not abortable run_id=... role=... mode=... status=...`(slot)/ `error: request is not abortable run_id=... role=... status=...`(依頼)/ `error: run is not abortable (state changed concurrently) run_id=... role=...`(競合)/ `error: management db update failed ...`(DB)
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 対象を ABORTED に更新し COMMIT した |
  | 3 | 業務エラー(中止不可) | slot が background かつ RUNNING でない / 依頼が RUNNING でない / 条件付き UPDATE の更新件数 0。状態は変更しない |
  | 6 | 実行エラー | 管理 DB 接続・SQL・COMMIT 失敗、更新件数 2 以上(内部エラー) |

## UC ロジック

- **バリデーション**: 前半 UC で済んでいる。本 UC は現在状態(前半で取得)を domain の判定表に通す
- **確認プロンプト**: 前半 UC で済んでいる(`yes` のみ本 UC へ)
- **冪等性**: 既に ABORTED の対象に再実行すると可否判定で不可(終了コード 3)となり二重更新しない。同じ run_id に対する 2 つの abort が同時に走っても、WHERE 句の `status = 'RUNNING'` により片方だけが更新件数 1 になる(LP-021)
- **エラーハンドリング**: 不可・競合は状態を変えず 3。DB 障害は 6。エラー出力は 1 回(CLR-004)
- **クラッシュ耐性**: UPDATE と parallel_runs 併更新は 1 トランザクション。COMMIT 前に落ちれば何も変わらず、再実行で同じ手順をやり直せる。COMMIT 後・ログ書き込み前に落ちた場合は状態は ABORTED、実行ログの `status changed` 行だけが欠ける(再実行は不可判定で 3 になる。ログ欠落は監査の正本がジョブスケジューラである前提で許容)
- **プロセス停止**: スクリプトは `kill` / SSH による停止・Pod 停止を一切行わない
- **実行ログ**(CLP-008): `INFO status changed from=RUNNING to=ABORTED operator={OS ユーザー} answer=yes|yes(--yes) run_id=... role=...`。不可は `INFO abort rejected reason=mode|status mode=... status=...`、競合は `WARN abort conflict updated_rows=0`。ログ行形式は `_cross-cutting/ux-ui/ui-design.md` の `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従い、情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する

## データモデル変更

### slot_executions(abort-blue / abort-green)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK 1 | 追加 |
| slot | string | PK 2。blue / green | 追加 |
| mode | string | foreground / background / off。可否判定と WHERE 句に使う | 追加 |
| pid | integer | runner の PID(表示のみ) | 追加 |
| artifact_dir | string | 成果物ディレクトリ(表示のみ) | 追加 |
| status | string | RUNNING / SUCCEEDED / FAILED / ABORTED。RUNNING → ABORTED | 追加 |
| started_at | datetime | 開始時刻(表示のみ) | 追加 |
| completed_at | datetime | 終了時刻。ABORTED 時に中止日時を書く | 追加 |

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

### parallel_runs(共通)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK | 追加 |
| status | string | STARTED / RUNNING / COMPLETED / ABORTED。STARTED または RUNNING → ABORTED | 追加 |
| completed_at | datetime | ABORTED 時に中止日時を書く | 追加 |

## ビジネスルール

- abort-blue / abort-green は対象 slot が background かつ RUNNING のときだけ ABORTED にできる。foreground / off は状態を変更せずエラー終了(条件「slot 中止可否判定」)
- abort-rapid-crosscheck / abort-final-crosscheck は依頼が RUNNING のときだけ ABORTED にできる(条件「依頼中止可否判定」「依頼状態遷移規則」)
- yes のときに限り更新し、並行稼働実行が STARTED / RUNNING なら併せて ABORTED にする。COMPLETED は変更しない(条件「停止確認応答」、状態「並行稼働実行」)
- ABORTED への更新は WHERE 句で現在状態を条件にし、競合時は更新件数 0 をエラーとする(arch LP-021)
- スクリプト自身はプロセスを停止せず状態更新だけを行い、二重実行を防ぐ(情報「中止指示」)
- ハング検知(hang-detector)はこの遷移を行わない(条件「監視は通知のみ」)

## ティア完了条件(BDD)

```gherkin
Feature: 実行を ABORTED へ遷移させる - 実行監視・復旧ティア

  Scenario: abort-green.sh が条件付き UPDATE で slot と parallel_run を ABORTED にする
    Given slot_executions に run_id=20260830T113000Z-JOB001-3f9a1c2e slot=green mode=background status=RUNNING があり parallel_runs の同 run_id が RUNNING である
    And テスト専用環境変数 RELAY_GATE_NOW=2026-08-30T12:40:00Z が設定されている
    When `abort-green.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 0 で stdout の末尾が `status=ABORTED` と `aborted_at=2026-08-30T12:40:00Z` の 2 行である
    And slot_executions(run_id, green).status=ABORTED, completed_at=2026-08-30T12:40:00Z かつ parallel_runs(run_id).status=ABORTED である

  Scenario: abort-blue.sh は off の slot を拒否する
    Given slot_executions に run_id=20260830T113000Z-JOB001-3f9a1c2e slot=blue が無い(BLUE_MODE=off で起動されていない)
    When `abort-blue.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 3 で stderr に `error: run not found run_id=20260830T113000Z-JOB001-3f9a1c2e role=blue` が出る

  Scenario: abort-rapid-crosscheck.sh は COMPLETED の parallel_runs を変更しない
    Given rapid_crosscheck_requests に run_id=20260830T113000Z-JOB001-3f9a1c2e status=RUNNING があり parallel_runs の同 run_id が COMPLETED である
    When `abort-rapid-crosscheck.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 0 で rapid_crosscheck_requests(run_id).status=ABORTED かつ parallel_runs(run_id).status=COMPLETED のまま(併更新 0 件で COMMIT)である

  Scenario: abort-rapid-crosscheck.sh は CLAIMED の依頼を拒否する
    Given rapid_crosscheck_requests に run_id=20260830T113000Z-JOB001-3f9a1c2e status=CLAIMED がある
    When `abort-rapid-crosscheck.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e --yes` を実行する
    Then 終了コード 3 で stderr に `error: request is not abortable run_id=20260830T113000Z-JOB001-3f9a1c2e role=rapid-crosscheck status=CLAIMED` が出る
    And status は CLAIMED のままである

  Scenario: 同じ run に 2 つの abort-green.sh が同時に走っても更新は 1 回だけ
    Given slot_executions に run_id=20260830T113000Z-JOB001-3f9a1c2e slot=green mode=background status=RUNNING がある
    When `abort-green.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e --yes` を 2 プロセス同時に実行する
    Then 一方は終了コード 0、他方は終了コード 3 で stderr に `(state changed concurrently)` を含むエラーが出る
    And 実行ログに `status changed from=RUNNING to=ABORTED` は 1 行だけ残る

  Scenario: 管理 DB の UPDATE 失敗は終了コード 6
    Given 管理 DB が接続を拒否する
    When `abort-final-crosscheck.sh --run-id 20260830T020000Z-final-1a2b3c4d --yes` を実行する
    Then 終了コード 6 で stderr に `error: management db` で始まる 1 行が出る
```
