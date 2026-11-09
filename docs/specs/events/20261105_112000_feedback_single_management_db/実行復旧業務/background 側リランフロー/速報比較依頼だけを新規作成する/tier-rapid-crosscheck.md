# 速報比較依頼だけを新規作成する - 速報クロスチェックティア仕様

## 変更概要

速報クロスチェックティアが所有する `rapid_runs` / `rapid_crosscheck_requests` への **依頼レコード作成契約**を定義する。通常は `rapid-crosscheck-runner.sh`(dispatcher)が両系成功時に作成するが、background-rerun(tier-ops)も同じ契約で作成できるようにする。worker はどちらが作成した依頼も区別せず通常の poll / claim で処理する。新しいコマンドは追加しない。

## コマンド契約

### rapid-crosscheck-worker.sh(他 UC「速報比較依頼を claim する」の契約を使う)

- **書式**: `rapid-crosscheck-worker.sh [--once] [--worker-id <ID>]`
- **アクセス権**: ジョブスケジューラ / 常駐

#### 引数・オプション

他 UC の契約に従う。本 UC では、再作成された依頼が通常の依頼と同じ条件(`status = 'REQUESTED'`)で claim されることだけを規定する。

- **stdin**: なし

## 出力契約

worker の出力契約は他 UC に従う。本 UC で追加する出力は無い。

## 依頼レコード作成契約(repository)

dispatcher と background-rerun が共通に守る `rapid_crosscheck_requests` / `rapid_runs` の作成規則:

| テーブル | 列 | 作成時の値 | 規則 |
|---|---|---|---|
| rapid_crosscheck_requests | run_id | 依頼の run_id(PK) | 1 run_id に 1 件。重複は主キー制約で拒否(条件「比較依頼の一意性」) |
| rapid_crosscheck_requests | job_id | 起動コマンドの {job_id} 置換に使う | 元 run と同じ job_id(再作成時)。worker は依頼の job_id で起動コマンドのプレースホルダを置換する |
| rapid_crosscheck_requests | parameters | 起動コマンドの {params} 置換に使う PARAM の JSON 配列文字列 | 再作成時は元依頼の値を複製する |
| rapid_crosscheck_requests | blue_exit_code / green_exit_code | 起動コマンドの {blue_exit_code} / {green_exit_code} 置換に使う | 依頼は両系成功時のみ作成されるため作成時ともに 0。再作成時は元依頼の値を複製する |
| rapid_crosscheck_requests | status | `REQUESTED` | 作成時はこの値のみ(条件「依頼状態遷移規則」) |
| rapid_crosscheck_requests | worker_id / lease_until | NULL | claim 時に worker が設定する(条件「claim 排他」) |
| rapid_crosscheck_requests | requested_at | 作成日時(ローカル時刻) | poll の並び順(`ORDER BY requested_at`) |
| rapid_crosscheck_requests | started_at / completed_at / exit_code / stdout / stderr / error_summary | NULL | worker が比較実行時に設定する |
| rapid_runs | run_id | 依頼と同じ run_id(PK) | 依頼と 1:1 |
| rapid_runs | blue_status / green_status | `SUCCEEDED` | 依頼作成の前提(両系成功) |
| rapid_runs | completion_status | `REQUEST_CREATED` | 依頼作成済み |

- 依頼作成と rapid_runs の作成 / 更新は **1 トランザクション**で行う(LP-009 と同じ原子性)
- 作成主体(dispatcher / background-rerun)を依頼レコードに記録しない。系譜は `parallel_runs.parent_run_id` で追跡する
- 再作成された依頼は元依頼の job_id / parameters / blue_exit_code / green_exit_code を引き継ぐ。worker はこれらの値で起動コマンド(rapid-crosscheck.env の RAPID_COMPARE_COMMAND)のプレースホルダを置換して比較ツールを起動する(他 UC「比較ツールでジョブ単位比較を実行して結果を登録する」)。worker は依頼レコードと自身の設定だけで動くため、成果物のパスを受け取らない。比較実行の成果物ディレクトリは作らない(この run ディレクトリは execution-spec.json と blue / green 節を持たない。この run を再度リラン元にする場合も、tier-ops の事前検証は依頼レコードだけで元実行を特定し execution-spec.json を要求しない)

## 非同期イベント

### rapid-crosscheck-requests

- **チャネル**: `rapid-crosscheck-requests`(管理 DB の `rapid_crosscheck_requests` をジョブキューとして poll / claim / lease)
- **方向**: publish(background-rerun → worker)
- **AsyncAPI**: [asyncapi.yaml](../../../_cross-cutting/api/asyncapi.yaml) の `channels.rapid-crosscheck-requests` を参照
- **メッセージ**: RapidCrosscheckRequestMessage(run_id / job_id / status=REQUESTED / requested_at)。payload は依頼レコード(`rapid_crosscheck_requests`)の列(`parallel_runs.parent_run_id` は JOIN した派生値で依頼テーブルの列ではない)

## イベント処理仕様(worker 側。他 UC の契約を再掲)

### 再作成依頼の claim と比較実行

- **トリガー**: worker の poll(既定 30 秒間隔、`--once` で 1 回)
- **入力チャネル**: `rapid-crosscheck-requests`(`status = 'REQUESTED'` を `requested_at` 昇順で取得)
- **出力チャネル**: なし(結果は依頼レコードの stdout / stderr / exit_code に保存)

#### 処理フロー

1. `UPDATE rapid_crosscheck_requests SET status='CLAIMED', worker_id=?, lease_until=now+10min WHERE run_id=? AND status='REQUESTED'`(更新件数 1 で claim 成功)
2. rapid-crosscheck.env の RAPID_COMPARE_COMMAND を依頼の run_id / job_id / parameters / blue_exit_code / green_exit_code で置換して比較ツールを起動(RUNNING)
3. exit_code / stdout / stderr を依頼レコードに保存し SUCCEEDED / FAILED にする
4. 依頼が終端したとき、`parallel_runs.parent_run_id IS NOT NULL` かつ当該 run_id の `slot_executions` 行が 0 件(業務ジョブを再実行していないリラン由来 run)なら `UPDATE parallel_runs SET status='COMPLETED', completed_at=now WHERE run_id=? AND status='RUNNING'` で並行稼働実行を終端する(状態「並行稼働実行」RUNNING → COMPLETED。更新 0 件 = 既に ABORTED 等は許容)。通常 run(parent_run_id が NULL)は foreground 中継完了で COMPLETED 済みのため対象外

#### エラーハンドリング

| エラー種別 | リトライ | DLQ | 説明 |
|-----------|---------|-----|------|
| lease 失効かつ未開始 | Yes(REQUESTED に戻す) | No | 他 UC「速報比較依頼を claim する」の規則 |
| 比較ツール非 0 | No | No | FAILED として保存。hang-detector が error 通知(他 UC) |
| 比較ツール起動失敗 | No | No | 実行エラー(exit_code=6)として FAILED にする(他 UC「比較ツールでジョブ単位比較を実行して結果を登録する」) |

## データモデル変更

### rapid_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK | 追加 |
| job_id | string | 起動コマンドの {job_id} 置換に使う | 追加 |
| parameters | text | 起動コマンドの {params} 置換に使う | 追加 |
| blue_exit_code / green_exit_code | integer | 起動コマンドの {blue_exit_code} / {green_exit_code} 置換に使う | 追加 |
| status | string | REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED | 追加 |
| worker_id | string | claim した worker | 追加 |
| lease_until | datetime | lease 期限 | 追加 |
| requested_at / started_at / completed_at | datetime | 各時刻 | 追加 |
| exit_code | integer | 比較ツール終了コード | 追加 |
| stdout / stderr | text | 比較ツール出力 | 追加 |
| error_summary | string | 失敗要約 | 追加 |

### rapid_runs

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK | 追加 |
| blue_status / green_status | string | SUCCEEDED / FAILED | 追加 |
| blue_completed_at / green_completed_at | datetime | 完了通知の日時 | 追加 |
| completion_status | string | PENDING / ONE_COMPLETED / BOTH_SUCCEEDED / ANY_FAILED / REQUEST_CREATED | 追加 |

### parallel_runs(worker が依頼終端時に更新)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK | 追加(参照) |
| parent_run_id | string | 非 NULL がリラン由来の判定条件 | 追加(参照) |
| status | string | RUNNING → COMPLETED(リラン由来で slot_executions 0 件の run のみ) | 追加 |
| completed_at | datetime | 依頼終端時に設定 | 追加 |

## ビジネスルール

- 依頼は REQUESTED で作成され、worker の取得で CLAIMED、比較開始で RUNNING に遷移する(条件「依頼状態遷移規則」)
- 1 run_id に 1 件(条件「比較依頼の一意性」)
- worker は依頼の job_id / parameters / blue_exit_code / green_exit_code で起動コマンドのプレースホルダを置換して比較ツールを起動する(他 UC「比較ツールでジョブ単位比較を実行して結果を登録する」)
- claim は worker_id と lease_until で排他する(条件「claim 排他」)
- 速報の結果はジョブスケジューラ応答に影響しない(条件「速報結果の位置付け」)
- 速報比較依頼だけを新規作成したリラン由来 run の parallel_run は、依頼の終端時に worker が COMPLETED にする(状態「並行稼働実行」RUNNING → COMPLETED)

## ティア完了条件(BDD)

```gherkin
Feature: 速報比較依頼だけを新規作成する - 速報クロスチェックティア

  Scenario: 再作成された依頼を worker が通常どおり claim する
    Given rapid_crosscheck_requests に run_id=20260830T130000-JOB001-a1b2c3d4 job_id=JOB001 parameters=["2026-08-30"] blue_exit_code=0 green_exit_code=0 status=REQUESTED worker_id=NULL がある
    When `rapid-crosscheck-worker.sh --once --worker-id worker-01` を実行する
    Then 同依頼が status=CLAIMED worker_id=worker-01 lease_until=now+10分 を経て RUNNING になり、worker が依頼の run_id / job_id / parameters / blue_exit_code / green_exit_code で起動コマンドを置換して比較ツールを起動する
    And 比較実行は成果物ディレクトリを作らず、結果は依頼レコードの stdout / stderr / exit_code に保存される

  Scenario: 同じ元 run から 2 回再作成しても依頼は run_id ごとに 1 件ずつ増える
    Given `background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role rapid-crosscheck` を 1 回実行し新 run_id(R2。`^[0-9]{8}T[0-9]{6}-JOB001-[0-9a-f]{8}$` に一致)の依頼が REQUESTED で作成されている
    When 同じコマンドをもう 1 回実行する
    Then 別の新 run_id(R3)の依頼が 1 件追加され、R2 の依頼は変更されず、同一 run_id の依頼は主キー制約により 1 件のままである

  Scenario: 比較ツールが起動できなければ依頼は FAILED になる
    Given 再作成依頼を claim した worker が比較ツールを起動できない
    When worker が比較を実行する
    Then 依頼は status=FAILED exit_code=6 で保存され、error_summary に起動失敗の理由が入る

  Scenario: 再作成依頼の終端時に worker が parallel_runs を COMPLETED にする
    Given rapid_crosscheck_requests に run_id=20260830T130000-JOB001-a1b2c3d4 status=RUNNING があり、parallel_runs の同 run_id が parent_run_id=20260830T113000-JOB001-3f9a1c2e status=RUNNING で、slot_executions に同 run_id の行が無い
    When worker が比較ツールの終了コード 0 を得て依頼を SUCCEEDED にする
    Then parallel_runs(20260830T130000-JOB001-a1b2c3d4).status が COMPLETED になり completed_at が設定される

  Scenario: 通常 run の依頼終端では parallel_runs を変更しない
    Given rapid_crosscheck_requests に run_id=20260830T113000-JOB001-3f9a1c2e status=RUNNING があり、parallel_runs の同 run_id が parent_run_id=NULL status=COMPLETED である
    When worker が依頼を SUCCEEDED にする
    Then parallel_runs(20260830T113000-JOB001-3f9a1c2e) は COMPLETED のまま completed_at も変わらない
```
