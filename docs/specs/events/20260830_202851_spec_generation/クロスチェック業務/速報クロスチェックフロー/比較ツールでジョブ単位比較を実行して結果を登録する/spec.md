# 比較ツールでジョブ単位比較を実行して結果を登録する

## 概要

claim した速報クロスチェック worker が依頼を CLAIMED → RUNNING にし、クロスチェックジョブマップの job_id ごとの比較定義に従って比較ツールでジョブ単位比較を起動する。比較ツールの stdout / stderr / exit_code を依頼レコードへ保存し、exit_code 0 → SUCCEEDED、3(比較 NG)/ 6(実行エラー)/ その他非 0 → FAILED とし、comparison_results に status(OK / NG / FAILED)・difference_count・report_uri・compared_at を INSERT する。成果物ディレクトリ `facade/<run_id>/rapid-crosscheck/` にも started-at.txt / stdout.log / stderr.log / exitcode.txt を残す(hang-detector の走査対象)。結果はジョブスケジューラへの応答に影響させず、確報側(final_*)には触れない。

## データフロー

```mermaid
graph LR
  subgraph RAPID["tier-rapid-crosscheck(worker)"]
    R_UC["usecase\nExecuteComparison(run_id, job_id, worker_id)"]
    R_Dom["domain\nComparisonOutcome\n(exit_code → request_status / result_status)"]
    R_Repo["repository\nComparisonDefinitionRecord / RapidCrosscheckRequestRecord / ComparisonResultRecord / RunnerResultRecord"]
    R_GW_DB["gateway\nRDB クライアントアダプタ"]
    R_GW_CMP["gateway\n比較ツール起動アダプタ"]
    R_GW_FS["gateway\nファイルシステムアダプタ(.tmp → mv)"]
    R_UC --> R_Dom
    R_UC --> R_Repo
    R_Repo --> R_GW_DB
    R_Repo --> R_GW_CMP
    R_Repo --> R_GW_FS
  end
  subgraph CFG["FS(設定ファイル)"]
    MAP["クロスチェックジョブマップ TSV\njob_id, comparison_type, compare_targets, compare_command, compare_options, definition_version"]
  end
  subgraph ART["FS(成果物ディレクトリ)"]
    A["facade/<run_id>/rapid-crosscheck/\nstarted-at.txt, stdout.log, stderr.log, exitcode.txt"]
  end
  subgraph CMP["比較ツール"]
    TOOL["compare_command compare_options\n({blue} / {green} を成果物 URI に置換)"]
  end
  subgraph DB["RDB"]
    T_REQ[("rapid_crosscheck_requests\nstatus, started_at, completed_at, exit_code, stdout, stderr, error_summary")]
    T_RES[("comparison_results\ncomparison_result_id, run_id, comparison_type, status, difference_count, report_uri, compared_at")]
    T_RUN[("rapid_runs\nblue_artifact_uri, green_artifact_uri")]
  end
  MAP -->|"ファイル読み取り(job_id 行)"| R_Repo
  R_GW_DB -->|"SQL UPDATE status='RUNNING', started_at WHERE run_id=? AND status='CLAIMED' AND worker_id=?"| T_REQ
  R_GW_DB -->|"SQL SELECT artifact_uri"| T_RUN
  R_GW_CMP -->|"プロセス起動"| TOOL
  TOOL -->|"stdout / stderr / exit_code"| R_GW_CMP
  R_GW_FS -->|"ファイル書き込み"| A
  R_GW_DB -->|"SQL UPDATE status, exit_code, stdout, stderr, completed_at"| T_REQ
  R_GW_DB -->|"SQL INSERT"| T_RES
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| usecase | ExecuteComparison | RUNNING 遷移 → 比較定義解決 → 成果物 dir 作成 → 比較ツール起動 → 結果保存 → comparison_result 登録 |
| domain | ComparisonOutcome | exit_code → 依頼状態(0=SUCCEEDED / 非 0=FAILED)と結果ステータス(0=OK / 3=NG / 6・その他=FAILED)の対応表 |
| repository | ComparisonDefinitionRecord | TSV の job_id 行 → 起動コマンド・オプション・比較種別 |
| gateway(比較ツール) | プロセス起動 | `compare_command` + compare_options(`{blue}` / `{green}` プレースホルダを成果物 URI に置換)。引数の渡し方は比較定義の compare_options が決め、gateway は連結して実行するだけ |
| gateway(FS) | Runner Result(role=rapid-crosscheck) | `.tmp` → `mv` で確定名へ |

## 処理フロー

```mermaid
sequenceDiagram
  actor Sched as ジョブスケジューラ
  box rgb(240,255,240) tier-rapid-crosscheck(worker)
    participant Pres as presentation (rapid-crosscheck-worker.sh)
    participant UC as usecase (execute_comparison)
    participant Dom as domain (comparison_outcome)
    participant Repo as repository
    participant GWDB as gateway (rdb_exec)
    participant GWCMP as gateway (compare_tool_run)
    participant GWFS as gateway (artifact_write)
  end
  participant DB as RDB
  participant FS as FS(成果物)
  participant TOOL as 比較ツール

  Sched-)Pres: (claim 済み run_id を受け取る)
  Pres->>UC: ExecuteComparison(run_id, job_id, worker_id)
  UC->>Repo: rapid_request_mark_running(run_id, worker_id, now)
  Repo->>GWDB: UPDATE ... SET status='RUNNING', started_at=? WHERE run_id=? AND status='CLAIMED' AND worker_id=?
  GWDB->>DB: SQL
  DB-->>GWDB: 1 行
  UC->>Repo: crosscheck_job_map_find(job_id)
  alt 比較定義の選択: job_id 行なし
    UC->>GWFS: started-at.txt / stdout.log(空)/ stderr.log(comparison definition not found job_id=...)/ exitcode.txt(6)を .tmp → mv で公開
    GWFS->>FS: facade/<run_id>/rapid-crosscheck/
    UC->>Repo: rapid_request_save_result(run_id, exit_code=6, stderr="comparison definition not found job_id=...", FAILED)
    Note over UC,Repo: comparison_results は INSERT しない(comparison_type を決める定義行が無い)
  else 行あり
    UC->>Repo: rapid_run_find_artifacts(run_id)
    Repo->>GWDB: SELECT blue_artifact_uri, green_artifact_uri FROM rapid_runs WHERE run_id=?
    UC->>GWFS: started-at.txt を書く(facade/<run_id>/rapid-crosscheck/)
    GWFS->>FS: .tmp → mv
    UC->>GWCMP: compare_tool_run(compare_command, compare_options, blue_uri, green_uri)
    GWCMP->>TOOL: プロセス起動(stdout / stderr をファイルへ)
    alt 比較ツール起動失敗(exec 不可。終了コードを得られない)
      GWCMP-->>UC: launch failed
      UC->>GWFS: stdout.log(空)/ stderr.log(起動失敗の理由)/ exitcode.txt(6)を .tmp → mv
      UC->>Repo: rapid_request_save_result(run_id, exit_code=6, error_summary="launch failed", FAILED)
      Note over UC,Repo: comparison_results は INSERT しない(比較ツールが終了コードを返していない)。worker は 6
    end
    TOOL-->>GWCMP: exit_code(0 / 3 / 6 / その他)
    GWCMP->>FS: stdout.log / stderr.log / exitcode.txt を .tmp → mv
    UC->>Dom: comparison_outcome(exit_code, stdout)
    alt 比較ツール終了コードの対応: 0
      Dom-->>UC: request_status=SUCCEEDED, result_status=OK
    else 3
      Dom-->>UC: request_status=FAILED, result_status=NG
    else 6 / その他非 0
      Dom-->>UC: request_status=FAILED, result_status=FAILED
    end
    UC->>Repo: rapid_request_save_result(run_id, exit_code, stdout, stderr, request_status, completed_at)
    UC->>Repo: comparison_result_insert(run_id, comparison_type, result_status, difference_count, report_uri, compared_at)
    Repo->>GWDB: UPDATE rapid_crosscheck_requests(WHERE status='RUNNING' AND worker_id=?)/ INSERT comparison_results(1 トランザクション)
    GWDB->>DB: SQL
    alt 終端 UPDATE が 0 行(abort 等で既に終端)
      GWDB-->>UC: comparison_results を INSERT せず ROLLBACK。実行ログ WARN request already terminal(stdout は request_status=ABORTED)
    end
  end
  UC-->>Pres: 結果(request_status, result_status)
  Pres-->>Sched: stdout request_status= / result_status=(comparison_results を作らないケースは -)/ 終了コード 0
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| 比較ツール終了コード | 0(比較 OK) | 依頼 SUCCEEDED、comparison_result.status=OK | tier-rapid-crosscheck | comparison_outcome |
| 比較ツール終了コード | 3(比較 NG・警告終了) | 依頼 FAILED、status=NG | tier-rapid-crosscheck | comparison_outcome |
| 比較ツール終了コード | 6(実行エラー・エラー終了) | 依頼 FAILED、status=FAILED | tier-rapid-crosscheck | comparison_outcome |
| 比較結果ステータス | 比較 OK / 比較 NG / FAILED | comparison_results.status に OK / NG / FAILED を登録 | tier-rapid-crosscheck | comparison_result_insert |
| 比較種別 | ジョブ単位比較 | 比較定義の comparison_type を comparison_results.comparison_type に転記 | tier-rapid-crosscheck | comparison_result_insert |
| クロスチェック依頼状態 | RUNNING / SUCCEEDED / FAILED | 本 UC で遷移する状態 | tier-rapid-crosscheck | rapid_request_mark_running / rapid_request_save_result |
| run role(成果物ディレクトリ区分) | rapid-crosscheck | `facade/<run_id>/rapid-crosscheck/` に Runner Result を残す | tier-rapid-crosscheck | artifact_write |
| Runner Result 成果物種別 | started-at.txt / stdout.log / stderr.log / exitcode.txt | 4 ファイルを .tmp → mv で公開 | tier-rapid-crosscheck | artifact_write |
| 速報クロスチェックのプロセス役割 | worker | 本 UC の実行主体 | tier-rapid-crosscheck | rapid-crosscheck-worker.sh |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| 依頼状態遷移規則 | CLAIMED → RUNNING(started_at 設定)、RUNNING → SUCCEEDED(exit_code 0)/ FAILED(非 0 または起動失敗) | tier-rapid-crosscheck | execute_comparison(usecase) | 比較 OK で SUCCEEDED と OK を登録する |
| comparison_results の登録条件(spec 追加。RDRA 条件.tsv 未登録。「比較ツール終了コードの対応」の補足条件として rdra-feedback.md へ起票候補) | comparison_results は比較ツールを起動して終了コードを得たときだけ INSERT する。比較定義なし・比較ツール起動失敗(exec 不可)では依頼を FAILED(exit_code=6)で終端するだけで INSERT しない。終端 UPDATE 0 行(ABORTED 済み等)も INSERT しない | tier-rapid-crosscheck | comparison_result_insert(repository)/ execute_comparison | 比較ツールの起動に失敗する(実行権限なし) / 比較定義が無い job_id |
| 比較定義の選択 | クロスチェックジョブマップ TSV の job_id 行を使う。行が無ければ比較ツールを起動せず、依頼を exit_code=6, error_summary=`comparison definition not found job_id=...` で FAILED に終端する。comparison_results は INSERT しない(comparison_type を与える定義行が無いため) | tier-rapid-crosscheck | crosscheck_job_map_find(repository) | job_id の比較定義が使われる / 比較定義が無い job_id |
| 比較ツール終了コードの対応 | 0 → SUCCEEDED / OK、3 → FAILED / NG、6 → FAILED / FAILED、その他非 0 → FAILED / FAILED。値は変換せず保存 | tier-rapid-crosscheck | comparison_outcome(domain) | 比較 NG(3)で FAILED と NG を登録する |
| 速報結果の位置付け | 依頼の FAILED や worker の終了コードはジョブスケジューラ応答に影響しない。worker 自身は `--once` で処理できれば 0 | tier-rapid-crosscheck | rapid-crosscheck-worker.sh(presentation) | 比較 NG(3)で FAILED と NG を登録する |
| 速報と確報のモデル分離 | 書き込み先は rapid_crosscheck_requests / comparison_results のみ。final_* を触らない | tier-rapid-crosscheck | execute_comparison | 比較 OK で SUCCEEDED と OK を登録する |
| 成果物公開判定 | 4 ファイルは .tmp へ書いて mv。確定名があるときのみ完了 | tier-rapid-crosscheck | artifact_write(gateway) | 比較 OK で SUCCEEDED と OK を登録する |

## 計算ルール一覧

| 計算名 | 入力情報 | 計算式/ロジック | 出力情報 | 適用 tier |
|--------|---------|---------------|---------|----------|
| 依頼状態の決定 | exit_code | 0 → SUCCEEDED、それ以外 → FAILED | rapid_crosscheck_requests.status | tier-rapid-crosscheck |
| 結果ステータスの決定 | exit_code | 0 → OK、3 → NG、6 / その他 → FAILED | comparison_results.status | tier-rapid-crosscheck |
| 比較コマンドの連結 | compare_command, compare_options, blue_artifact_uri, green_artifact_uri | `compare_command` + compare_options(空白区切り。`{blue}` / `{green}` プレースホルダを URI に置換。仮採用) | 起動コマンド | tier-rapid-crosscheck |
| difference_count / report_uri | 比較ツールの stdout | stdout の `difference_count=N` / `report_uri=...` 行があれば転記、無ければ NULL(`-`)(仮採用: 比較ツール契約に stdout 形式の定めが無いため) | comparison_results | tier-rapid-crosscheck |
| comparison_result_id | 乱数 | 8 桁 hex 乱数(主キー。全体で一意。衝突時は取り直す。契約 shared_rules.comparison_result_id と同じ) | comparison_results.comparison_result_id | tier-rapid-crosscheck |
| error_summary | stderr | stderr の先頭 1 行(256 文字まで)。exit_code 0 なら NULL | rapid_crosscheck_requests.error_summary | tier-rapid-crosscheck |
| compared_at / completed_at | 比較ツール終了時刻 | UTC ISO 8601 秒精度 | 各列 | tier-rapid-crosscheck |

## 状態遷移一覧

| 状態モデル | 遷移元 | 遷移先 | トリガー | 事前条件 | 事後処理 | 適用 tier |
|-----------|--------|--------|---------|---------|---------|----------|
| クロスチェック依頼 | CLAIMED | RUNNING | 比較開始 | 自 worker が claim 済み(worker_id 一致) | started_at 設定、started-at.txt 出力 | tier-rapid-crosscheck |
| クロスチェック依頼 | RUNNING | SUCCEEDED | 比較ツール exit_code 0 | — | stdout / stderr / exit_code 保存、comparison_result OK 登録 | tier-rapid-crosscheck |
| クロスチェック依頼 | RUNNING | FAILED | 比較ツール exit_code 非 0(3 / 6 / その他)、起動失敗、または比較定義なし | — | 結果保存、comparison_result NG / FAILED 登録(比較定義なし・起動失敗は登録しない)。hang-detector が error 通知 | tier-rapid-crosscheck |

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | クロスチェック業務 | この UC が属する業務 |
| BUC | 速報クロスチェックフロー | この UC を含む BUC(アクティビティ: ジョブ単位比較の実行) |
| アクター | 運用者 | 受益者(自動) |
| 情報 | 速報比較依頼(rapid_crosscheck_request) | 更新する |
| 情報 | クロスチェックジョブマップ | 参照する |
| 情報 | 比較定義 | 参照する(job_id 行) |
| 情報 | 比較ツール実行結果 | 依頼レコードの列と成果物ファイルに保存 |
| 情報 | 比較結果(comparison_result) | 登録する |
| 情報 | 実行ログ | worker の実行ログ |
| 状態 | クロスチェック依頼 | CLAIMED → RUNNING → SUCCEEDED / FAILED |
| 条件 | 依頼状態遷移規則 | 適用 |
| 条件 | 比較定義の選択 | 適用 |
| 条件 | 比較ツール終了コードの対応 | 適用 |
| 条件 | 速報結果の位置付け | 適用 |
| 画面 | rapid-crosscheck worker 比較実行出力(→ CLI 出力) | stdout / 実行ログ |
| イベント | ジョブ単位比較の起動 | 比較ツールのプロセス起動 |
| イベント | comparison_result の登録 | 管理 DB(RDB)への INSERT |
| 外部システム | 比較ツール | 起動する |
| 外部システム | 管理 DB(RDB) | 書き込み先 |

## 関連 USDM

| REQ ID | SPEC ID | 対応 BDD Scenario |
|--------|---------|-----------------|
| REQ-005 | SPEC-005-03 | 比較 OK で SUCCEEDED と OK を登録する(SPEC-005-03) / job_id の比較定義が使われる(SPEC-005-03) |
| REQ-007 | SPEC-007-01 | 比較 OK で SUCCEEDED と OK を登録する(SPEC-005-03)(RUNNING → SUCCEEDED) |
| REQ-007 | SPEC-007-03 | 比較 NG(3)で FAILED と NG を登録する(SPEC-007-03) |
| REQ-011 | SPEC-011-02 | 比較 OK で SUCCEEDED と OK を登録する(SPEC-005-03)(comparison_result の列) |

## E2E 完了条件(BDD)

### 正常系

```gherkin
Feature: 比較ツールでジョブ単位比較を実行して結果を登録する

  Scenario: 比較 OK で SUCCEEDED と OK を登録する(SPEC-005-03)
    Given RAPID_CROSSCHECK_MODE=on で rapid_crosscheck_requests に run_id=20260830T113000Z-JOB001-3f9a1c2e, job_id=JOB001, status=REQUESTED の行がある
    And rapid_runs の同 run_id に blue_artifact_uri=file:///var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/blue, green_artifact_uri=file:///var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/green がある
    And クロスチェックジョブマップに `JOB001	job	output.csv	/opt/compare/compare.sh	--blue {blue} --green {green}	v1` の行がある
    And 比較ツール /opt/compare/compare.sh は終了コード 0、stdout に `difference_count=0` を返す
    When ジョブスケジューラが `rapid-crosscheck-worker.sh --once --worker-id worker-01` を起動する
    Then 終了コードは 0 で stdout に `request_status=SUCCEEDED` と `result_status=OK` が出る
    And 依頼の status は `SUCCEEDED`、exit_code は 0、started_at と completed_at は UTC ISO 8601 の値である
    And 依頼の stdout 列は `difference_count=0` を含み、stderr 列は空である(比較ツールの出力を依頼レコードへ保存する)
    And comparison_results に run_id=20260830T113000Z-JOB001-3f9a1c2e, comparison_type=job, status=OK, difference_count=0 の行が 1 件ある
    And facade/20260830T113000Z-JOB001-3f9a1c2e/rapid-crosscheck/ に started-at.txt, stdout.log, stderr.log, exitcode.txt(中身 `0`)が揃い `.tmp` ファイルは残っていない
    And final_crosscheck_requests は変更されない

  Scenario: job_id の比較定義が使われる(SPEC-005-03)
    Given クロスチェックジョブマップに JOB001 の行(compare_command=/opt/compare/compare.sh)と JOB002 の行(compare_command=/opt/compare/compare-v2.sh)がある
    And status=REQUESTED の依頼 run_id=20260830T113500Z-JOB002-1a2b3c4d, job_id=JOB002 がある
    When `rapid-crosscheck-worker.sh --once --worker-id worker-01` を起動する
    Then 起動される比較ツールは /opt/compare/compare-v2.sh であり、/opt/compare/compare.sh は起動されない
```

### 異常系

```gherkin
  Scenario: 比較 NG(3)で FAILED と NG を登録する(SPEC-007-03)
    Given status=REQUESTED の依頼 run_id=20260830T113000Z-JOB001-3f9a1c2e, job_id=JOB001 と JOB001 の比較定義がある
    And 比較ツールは終了コード 3、stdout に `difference_count=12` と `report_uri=file:///var/relay-gate/reports/20260830T113000Z-JOB001-3f9a1c2e/job.html` を返す
    When `rapid-crosscheck-worker.sh --once --worker-id worker-01` を起動する
    Then worker の終了コードは 0 で stdout に `request_status=FAILED` と `result_status=NG` が出て、依頼の status は `FAILED`、exit_code は 3 である
    And 依頼の stdout 列は `difference_count=12` と `report_uri=...` の行を含む
    And comparison_results に status=NG, difference_count=12, report_uri=file:///var/relay-gate/reports/20260830T113000Z-JOB001-3f9a1c2e/job.html の行がある
    And facade/20260830T113000Z-JOB001-3f9a1c2e/blue/exitcode.txt と業務ジョブのジョブスケジューラ応答は変わらない

  Scenario: 比較定義が無い job_id
    Given status=REQUESTED の依頼 run_id=20260830T114000Z-JOB009-9f9f9f9f, job_id=JOB009 があり、クロスチェックジョブマップに JOB009 の行が無い
    When `rapid-crosscheck-worker.sh --once --worker-id worker-01` を起動する
    Then 比較ツールは起動されず、依頼の status は `FAILED`、exit_code は 6、error_summary は `comparison definition not found job_id=JOB009` である
    And facade/20260830T114000Z-JOB009-9f9f9f9f/rapid-crosscheck/ に started-at.txt、stderr.log(`comparison definition not found job_id=JOB009`)、exitcode.txt(中身 `6`)が揃う
    And comparison_results に run_id=20260830T114000Z-JOB009-9f9f9f9f の行は無く、stdout に `request_status=FAILED`、`result_status=-`、`exit_code=6`、`comparison_result_id=-` が出て、worker の終了コードは 0 である(依頼を終端状態まで処理できたため。worker の 6 は比較ツールの起動自体の失敗など worker 側の実行エラーに限る)

  Scenario: 比較ツールの起動に失敗する(実行権限なし)
    Given JOB001 の比較定義の compare_command が実行できない
    When `rapid-crosscheck-worker.sh --once --worker-id worker-01` を起動する
    Then 依頼の status は `FAILED`、exit_code は 6、error_summary は `launch failed`、facade/<run_id>/rapid-crosscheck/stderr.log に起動失敗の理由が残る
    And comparison_results に同 run_id の行は無い(比較ツールが終了コードを返していないため INSERT しない)
    And stdout に `request_status=FAILED`、`result_status=-`、`exit_code=6`、`comparison_result_id=-` が出て、stderr に `error: compare tool launch failed run_id=... command=/opt/compare/compare.sh` が出て、worker の終了コードは 6 である

  Scenario: 比較中に依頼が中止されていたら結果を登録しない
    Given worker-01 が run_id=20260830T113000Z-JOB001-3f9a1c2e を RUNNING にして比較ツールを起動中に、依頼が abort-rapid-crosscheck で ABORTED になっている
    When 比較ツールが終了コード 0 で終了する
    Then 依頼の status は `ABORTED` のまま、comparison_results に同 run_id の行は無く、成果物 dir の stdout.log / stderr.log / exitcode.txt は残る
    And stdout に `request_status=ABORTED`、`result_status=-`、`exit_code=-`、`comparison_result_id=-` が出る
    And worker-01 の実行ログに `WARN request already terminal run_id=20260830T113000Z-JOB001-3f9a1c2e status=ABORTED` が残り、終了コードは 0 である
```

## ティア別仕様

- [速報クロスチェックティア](tier-rapid-crosscheck.md)

### 統合 API Spec

- [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml)(`rapid-crosscheck-worker.sh`)
- [AsyncAPI Spec](../../../_cross-cutting/api/asyncapi.yaml)(channel `rapid-crosscheck-requests` を subscribe)
