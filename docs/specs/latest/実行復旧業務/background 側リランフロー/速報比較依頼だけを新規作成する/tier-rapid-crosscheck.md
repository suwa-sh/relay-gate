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
| rapid_crosscheck_requests | job_id | 比較定義の選択キー | 元 run と同じ job_id(再作成時)。worker は job_id ごとの比較定義を使う(条件「比較定義の選択」) |
| rapid_crosscheck_requests | status | `REQUESTED` | 作成時はこの値のみ(条件「依頼状態遷移規則」) |
| rapid_crosscheck_requests | worker_id / lease_until | NULL | claim 時に worker が設定する(条件「claim 排他」) |
| rapid_crosscheck_requests | requested_at | 作成日時(UTC) | poll の並び順(`ORDER BY requested_at`) |
| rapid_crosscheck_requests | started_at / completed_at / exit_code / stdout / stderr / error_summary | NULL | worker が比較実行時に設定する |
| rapid_runs | run_id | 依頼と同じ run_id(PK) | 依頼と 1:1 |
| rapid_runs | blue_status / green_status | `SUCCEEDED` | 依頼作成の前提(両系成功) |
| rapid_runs | blue_artifact_uri / green_artifact_uri | 比較対象の成果物ディレクトリ | 再作成時は元 run の値を複製。worker はこの URI を比較ツールに渡す |
| rapid_runs | completion_status | `REQUEST_CREATED` | 依頼作成済み |

- 依頼作成と rapid_runs の作成 / 更新は **1 トランザクション**で行う(LP-009 と同じ原子性)
- 作成主体(dispatcher / background-rerun)を依頼レコードに記録しない。系譜は `parallel_runs.parent_run_id` で追跡する
- 再作成された依頼の比較対象は元 run の成果物であるため、`rapid_runs.blue_artifact_uri / green_artifact_uri` が指すディレクトリは元 run の `facade/<元 run_id>/blue|green`(`file://` 付き URI)である。blue / green の成果物は元 run のもの、rapid-crosscheck の成果物(`started-at.txt / stdout.log / stderr.log / exitcode.txt`)は worker が比較実行時に新 run_id 配下 `facade/<新 run_id>/rapid-crosscheck/` に書く(他 UC「比較ツールでジョブ単位比較を実行して結果を登録する」)。新 run_id の run ディレクトリは execution-spec.json と blue / green 節を持たない(この run を再度リラン元にする場合も、tier-ops の事前検証は依頼レコードだけで元実行を特定し execution-spec.json を要求しない)。worker・result 参照は blue / green についてこの URI を正として扱い、run_id からディレクトリを導出しない

## 非同期イベント

### rapid-crosscheck-requests

- **チャネル**: `rapid-crosscheck-requests`(管理 DB の `rapid_crosscheck_requests` をジョブキューとして poll / claim / lease)
- **方向**: publish(background-rerun → worker)
- **AsyncAPI**: [asyncapi.yaml](../../../_cross-cutting/api/asyncapi.yaml) の `channels.rapid-crosscheck-requests` を参照
- **メッセージ**: RapidCrosscheckRequestMessage(run_id / job_id / status=REQUESTED / requested_at)。payload は依頼レコード(`rapid_crosscheck_requests`)の列 + 参照先の成果物 URI(`rapid_runs.blue_artifact_uri / green_artifact_uri`、`parallel_runs.parent_run_id` は JOIN した派生値で依頼テーブルの列ではない)

## イベント処理仕様(worker 側。他 UC の契約を再掲)

### 再作成依頼の claim と比較実行

- **トリガー**: worker の poll(既定 30 秒間隔、`--once` で 1 回)
- **入力チャネル**: `rapid-crosscheck-requests`(`status = 'REQUESTED'` を `requested_at` 昇順で取得)
- **出力チャネル**: なし(結果は `comparison_results` と依頼レコードに保存)

#### 処理フロー

1. `UPDATE rapid_crosscheck_requests SET status='CLAIMED', worker_id=?, lease_until=now+10min WHERE run_id=? AND status='REQUESTED'`(更新件数 1 で claim 成功)
2. `rapid_runs` の blue_artifact_uri / green_artifact_uri と `job_id` の比較定義で比較ツールを起動(RUNNING)
3. exit_code / stdout / stderr を保存し SUCCEEDED / FAILED、`comparison_results` を登録

#### エラーハンドリング

| エラー種別 | リトライ | DLQ | 説明 |
|-----------|---------|-----|------|
| lease 失効かつ未開始 | Yes(REQUESTED に戻す) | No | 他 UC「速報比較依頼を claim する」の規則 |
| 比較ツール非 0 | No | No | FAILED として保存。hang-detector が error 通知(他 UC) |
| 元成果物ディレクトリが無い | No | No | 比較ツールの実行エラー(6)として FAILED。再作成時に URI の存在を tier-ops が確認しないため、削除済み成果物は比較 FAILED となる(仮採用: 成果物の保持期間は運用に委ねる) |

## データモデル変更

### rapid_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK | 追加 |
| job_id | string | 比較定義の選択キー | 追加 |
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
| blue_artifact_uri / green_artifact_uri | string | 比較対象の成果物ディレクトリ | 追加 |
| blue_completed_at / green_completed_at | datetime | 完了通知の日時 | 追加 |
| completion_status | string | PENDING / ONE_COMPLETED / BOTH_SUCCEEDED / ANY_FAILED / REQUEST_CREATED | 追加 |

## ビジネスルール

- 依頼は REQUESTED で作成され、worker の取得で CLAIMED、比較開始で RUNNING に遷移する(条件「依頼状態遷移規則」)
- 1 run_id に 1 件(条件「比較依頼の一意性」)
- 比較は job_id ごとの比較定義に従う(条件「比較定義の選択」)
- claim は worker_id と lease_until で排他する(条件「claim 排他」)
- 速報の結果はジョブスケジューラ応答に影響しない(条件「速報結果の位置付け」)

## ティア完了条件(BDD)

```gherkin
Feature: 速報比較依頼だけを新規作成する - 速報クロスチェックティア

  Scenario: 再作成された依頼を worker が通常どおり claim する
    Given rapid_crosscheck_requests に run_id=20260830T130000Z-JOB001-a1b2c3d4 job_id=JOB001 status=REQUESTED worker_id=NULL があり rapid_runs の同 run_id に blue_artifact_uri=file:///var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/blue green_artifact_uri=file:///var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/green がある
    When `rapid-crosscheck-worker.sh --once --worker-id worker-01` を実行する
    Then 同依頼が status=CLAIMED worker_id=worker-01 lease_until=now+10分 を経て RUNNING になり、比較ツールに元 run の blue / green 成果物ディレクトリが渡される
    And 比較実行の成果物は facade/20260830T130000Z-JOB001-a1b2c3d4/rapid-crosscheck/ に書かれ、同 run ディレクトリに execution-spec.json は無い

  Scenario: 同じ元 run から 2 回再作成しても依頼は run_id ごとに 1 件ずつ増える
    Given `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role rapid-crosscheck` を 1 回実行し新 run_id(R2。`^[0-9]{8}T[0-9]{6}Z-JOB001-[0-9a-f]{8}$` に一致)の依頼が REQUESTED で作成されている
    When 同じコマンドをもう 1 回実行する
    Then 別の新 run_id(R3)の依頼が 1 件追加され、R2 の依頼は変更されず、同一 run_id の依頼は主キー制約により 1 件のままである

  Scenario: 元成果物が削除済みなら比較は FAILED になる
    Given 再作成依頼の blue_artifact_uri が指すディレクトリが存在しない
    When worker が比較を実行する
    Then 依頼は status=FAILED exit_code=6 で保存され、comparison_results に status=FAILED が登録される
```
