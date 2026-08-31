# 速報比較依頼だけを新規作成する - 実行監視・復旧ティア仕様

## 変更概要

`background-rerun.sh` の `--role rapid-crosscheck` 通過後の処理を定義する。新 run_id 発行 → parallel_runs / rapid_runs / rapid_crosscheck_requests の INSERT(1 トランザクション)→ parallel_runs を RUNNING → 終了コード 0。業務ジョブ(runner)は起動せず、background-rerun 自身は新 run_id の成果物ディレクトリを作らない(比較実行時に worker が `facade/<新 run_id>/rapid-crosscheck/` を作る。execution-spec.json と blue / green 節は持たない)。execution-spec.json を持たないこの run も、前段 UC「リラン対象を検証する」が `--role rapid-crosscheck` では依頼レコードだけで元実行を特定するため、再度 `--source-run-id` に指定できる(数珠つなぎリラン)。

## コマンド契約

### background-rerun.sh(UC「リラン対象を検証する」の契約を使う)

- **書式**: `background-rerun.sh --source-run-id <RUN_ID> --role rapid-crosscheck`
- **アクセス権**: ジョブスケジューラの専用ジョブ / 運用者。管理 DB への書き込み接続が必要

#### 引数・オプション

UC「リラン対象を検証する」の tier-ops.md と同一。

- **stdin**: なし

## 出力契約

- **stdout**(固定順):
  | 行順 | キー | 値 |
  |---|---|---|
  | 1 | `role` | `rapid-crosscheck` |
  | 2 | `job_id` | 元 run の job_id |
  | 3 | `request_status` | `REQUESTED` |
  | 4 | `blue_artifact_uri` | `key: value`。元 rapid_runs から引き継いだ値(`file://` 付き URI) |
  | 5 | `green_artifact_uri` | `key: value`。同上 |
  | 6 | `run_id` | 新 run_id |
  | 7 | `parent_run_id` | `--source-run-id` の値 |
- **stderr**: `error: source artifacts not found run_id=... role=rapid-crosscheck missing=blue_artifact_uri|green_artifact_uri` / `error: management db insert failed table=... run_id=...`
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 依頼を REQUESTED で作成し COMMIT した |
  | 3 | 業務エラー | 事前検証 NG(前段 UC)、元 run の成果物 URI が無い |
  | 6 | 実行エラー | 管理 DB 接続・INSERT・COMMIT 失敗、run_id 発行の再試行上限超過 |

## UC ロジック

- **バリデーション**: 前段 UC で済み。元 rapid_runs の blue_artifact_uri / green_artifact_uri が両方非 NULL であることを確認(欠けていれば 3)
- **確認プロンプト**: なし
- **処理順序(usecase。BEGIN 〜 COMMIT を 1 トランザクション)**:
  1. 元 run の `parallel_runs`(job_id / parameters / execution_spec_uri)と `rapid_runs`(blue_artifact_uri / green_artifact_uri)を SELECT
  2. 新 run_id を発行(既存 run_id と衝突すれば取り直す。最大 3 回)
  3. `parallel_runs` INSERT(run_id, parent_run_id=source_run_id, job_id, parameters, execution_spec_uri=元の値, status=STARTED, requested_at=now)
  4. `rapid_runs` INSERT(run_id, blue_status=SUCCEEDED, green_status=SUCCEEDED, blue_artifact_uri, green_artifact_uri, blue_completed_at / green_completed_at=元の値, completion_status=REQUEST_CREATED)
  5. `rapid_crosscheck_requests` INSERT(run_id, job_id, status=REQUESTED, requested_at=now。worker_id / lease_until / started_at / completed_at / exit_code / stdout / stderr / error_summary は NULL)— 列規則は tier-rapid-crosscheck.md の作成契約に従う
  6. `parallel_runs` UPDATE `status='RUNNING' WHERE run_id=? AND status='STARTED'`
  7. COMMIT。stdout を出して 0
- **数珠つなぎ**: 手順 1 の SELECT は元 run が本 UC で作られた run でも成立する(parallel_runs / rapid_runs は本 UC が作成済み。execution-spec.json は読まない)。parent_run_id は直前のリラン元、成果物 URI / execution_spec_uri は元 run の値の複製(連鎖の先頭の実行を指し続ける)
- **冪等性**: 同じ `--source-run-id --role rapid-crosscheck` を再実行すると別の新 run_id でもう 1 件依頼を作る(各リランは独立)。同一 run_id の依頼は主キー制約で 1 件のみ(条件「比較依頼の一意性」)。元 run の依頼・rapid_runs は変更しない
- **エラーハンドリング**: INSERT 失敗は ROLLBACK して 6。エラーは 1 回だけ出す
- **クラッシュ耐性**: 1 トランザクションのため、COMMIT 前に落ちれば何も残らず再実行でやり直せる。COMMIT 後・stdout 出力前に落ちた場合は依頼は作成済み(worker が処理する)で、運用者は `run-lineage.sh --run-id {元 run_id}` で新 run_id を確認できる。新 run_id の run ディレクトリは worker が比較実行時に作るため、それまでは `facade/<新 run_id>/` が存在しない。hang-detector は `<role>/started-at.txt`(blue / green)が無い run ディレクトリを走査しない(他 UC「background 実行の経過時間と終了状態を判定する」走査手順 1)ので、新 run_id の成果物走査による誤検知は起きない
- **運用注記(parallel_runs の終端)**: 本 UC で作った parallel_runs は foreground 中継が無く COMPLETED 遷移が未定義のため、依頼が終端しても RUNNING のまま残る。`abort-rapid-crosscheck.sh` の併更新(`WHERE status IN ('STARTED','RUNNING')`)で ABORTED にできる(UC「実行を ABORTED へ遷移させる」と同文。rdra-feedback 対象)
- **実行ログ**(CLP-008): `INFO rapid request recreated operator={OS ユーザー} source_run_id=R1 new_run_id=R2 job_id=JOB001`。ログ行形式は `_cross-cutting/ux-ui/ui-design.md` の `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従い、情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する

## データモデル変更

### parallel_runs

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK。新 run_id | 追加 |
| parent_run_id | string | 元 run_id | 追加 |
| job_id | string | 元 run の job_id | 追加 |
| parameters | text | 元 run の parameters(複製) | 追加 |
| execution_spec_uri | string | 元 run の execution_spec_uri(複製。新 spec は作らない) | 追加 |
| status | string | STARTED → RUNNING | 追加 |
| requested_at | datetime | 作成日時 | 追加 |

### rapid_runs

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK。新 run_id | 追加 |
| blue_status / green_status | string | `SUCCEEDED`(元 run で両系成功済み) | 追加 |
| blue_artifact_uri / green_artifact_uri | string | 元 run から複製 | 追加 |
| blue_completed_at / green_completed_at | datetime | 元 run から複製 | 追加 |
| completion_status | string | `REQUEST_CREATED` | 追加 |

### rapid_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK。新 run_id | 追加 |
| job_id | string | 元 run の job_id(比較定義の選択キー) | 追加 |
| status | string | `REQUESTED` | 追加 |
| requested_at | datetime | 作成日時 | 追加 |
| worker_id / lease_until / started_at / completed_at / exit_code / stdout / stderr / error_summary | — | NULL | 追加 |

## 設定契約

- **環境変数**: `RELAY_GATE_CONFIG_DIR`(feature-flag.env / rapid-crosscheck.env の所在)/ `RELAY_GATE_LOG_DIR`(実行ログ)/ `RELAY_GATE_NOW`(テスト専用の現在時刻注入。契約 `environment_variables.RELAY_GATE_NOW`)
- **`RELAY_GATE_NOW` の適用先**: 新 run_id の時刻部、`parallel_runs.requested_at`、`rapid_crosscheck_requests.requested_at`(DB の now() を使う INSERT にもこの値を渡す)。未設定なら実時刻。runner を起動しないため環境変数の引き継ぎは無い
- **feature-flag.env**: `RAPID_CROSSCHECK_MODE`(off は前段 UC で 3)。on のとき `rapid-crosscheck.env` の `RAPID_DB_CONN_REF` で管理 DB に接続する

## ビジネスルール

- `--role rapid-crosscheck` は業務ジョブを再実行せず比較依頼だけを新規作成する(条件「リラン事前検証」)
- 新 run の parent_run_id に元 run_id を設定する(条件「リラン系譜の追跡」)
- 依頼は REQUESTED で作成し、以降は worker の通常の claim と比較実行に委ねる(条件「依頼状態遷移規則」)
- 1 run_id に 1 件(条件「比較依頼の一意性」)。元 run の依頼は変更しない
- 比較対象は元 run の blue / green 成果物(情報「リラン指示」)

## ティア完了条件(BDD)

```gherkin
Feature: 速報比較依頼だけを新規作成する - 実行監視・復旧ティア

  Scenario: 3 テーブルを 1 トランザクションで作成する
    Given 事前検証を通過した source_run_id=20260830T113000Z-JOB001-3f9a1c2e(依頼 ABORTED、rapid_runs に両系の artifact_uri あり、job_id=JOB001)がある
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role rapid-crosscheck` を実行する
    Then 終了コード 0 で stdout の 3 行目が `request_status=REQUESTED`、6 行目が `run_id=` で始まり 7 行目が `parent_run_id=20260830T113000Z-JOB001-3f9a1c2e` である
    And 新 run_id で parallel_runs(status=RUNNING)、rapid_runs(completion_status=REQUEST_CREATED)、rapid_crosscheck_requests(status=REQUESTED, job_id=JOB001, worker_id=NULL)が各 1 行ある

  Scenario: runner を起動せず、終了直後には新 run_id の成果物ディレクトリを作っていない
    When 上記を実行する
    Then $BLUE_RUNNER / $GREEN_RUNNER は起動されず、background-rerun.sh の終了直後には facade/{新 run_id}/ ディレクトリが存在しない(worker の比較実行前)

  Scenario: artifact_uri 欠落は終了コード 3 で何も作らない
    Given 元 rapid_runs の blue_artifact_uri が NULL である
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role rapid-crosscheck` を実行する
    Then 終了コード 3 で stderr に `error: source artifacts not found run_id=20260830T113000Z-JOB001-3f9a1c2e role=rapid-crosscheck missing=blue_artifact_uri` が出て、新しい行は 3 テーブルのいずれにも無い

  Scenario: INSERT 失敗で ROLLBACK する
    Given rapid_crosscheck_requests への INSERT が失敗する
    When 上記を実行する
    Then 終了コード 6 で parallel_runs / rapid_runs に新 run_id の行が残らない
```
