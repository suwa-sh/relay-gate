# 速報クロスチェックを実行し差分を検知する

## 概要

workerがREQUESTED状態の速報比較依頼をlease/claim取得し、blue/green実装の実行結果を比較して差分を検知するUC。日次の全量比較（確報クロスチェック）を待たずにジョブ単位で早期に差分を検知し、速報比較依頼状態をSUCCEEDED/FAILEDへ、速報比較結果（OK/NG判定・差分件数）を確定する。比較対象は依頼レコードのblue_run_id/blue_attempt_id/green_run_id/green_attempt_idの4項目で特定した起動試行のRunner実行結果である。比較の範囲と実装は、依頼レコードが保持するjob_idとcomparison_definition_valid_fromでcomparison_definitionsの該当世代を1件解決し、その世代のtarget_tables/target_files/comparator_idを適用する。comparison_definition_valid_fromは依頼作成時に実行時点から解決された値であり、依頼作成後に比較定義が差し替わっても当該依頼の比較内容は世代固定のまま変わらない（SPEC-012-03）。

## データフロー

```mermaid
graph LR
  subgraph WK["tier-worker"]
    WK_Pres["presentation\nCronJobエントリポイント（lease/claim取得）"]
    WK_UC["usecase\nRunRapidCrosscheckCommand"]
    WK_Domain["domain\n速報比較依頼\nstatus=CLAIMED→RUNNING→SUCCEEDED-FAILED\n速報比較結果\ncomparisonResult/diffCount"]
    WK_GW["gateway\nRapidCrosscheckRequestRecord / RapidCrosscheckResultRecord / RunnerResultRecord / ComparisonDefinitionRecord"]
    WK_Pres --> WK_UC --> WK_Domain
    WK_UC --> WK_GW
  end
  subgraph DB["RDB"]
    DB_REQ[("rapid_crosscheck_requests\nrun_id, blue_run_id, blue_attempt_id, green_run_id, green_attempt_id, comparison_definition_valid_from, status, lease_expires_at, worker_id")]
    DB_RUN[("runner_results\nrun_id, slot_type, role_type, attempt_id, stdout/stderr/exit_code")]
    DB_DEF[("comparison_definitions\njob_id, valid_from, valid_to, target_tables, target_files, comparator_id")]
    DB_RES[("rapid_crosscheck_results\nrun_id, comparison_result, diff_count")]
  end
  subgraph OUT["CLI出力/確認画面"]
    OUT_View["速報クロスチェック実行画面\nRunnerResultPanel + StatusBadge"]
  end
  WK_GW -->|"SELECT status='REQUESTED' FOR UPDATE"| DB_REQ
  WK_GW -->|"UPDATE status='CLAIMED', worker_id, lease_expires_at"| DB_REQ
  DB_REQ --> WK_GW --> WK_Domain
  WK_GW -->|"SELECT 比較対象取得: (blue_run_id, 'blue', 'background', blue_attempt_id) と (green_run_id, 'green', 'background', green_attempt_id)"| DB_RUN
  DB_RUN --> WK_GW --> WK_Domain
  WK_GW -->|"SELECT 比較定義解決: (job_id, comparison_definition_valid_from) で該当世代1件"| DB_DEF
  DB_DEF --> WK_GW --> WK_Domain
  WK_Domain -->|"UPDATE status='RUNNING'"| WK_GW
  WK_GW -->|"UPDATE"| DB_REQ
  WK_Domain -->|"比較実行→OK-NG判定"| WK_UC
  WK_UC -->|"UPDATE status='SUCCEEDED'-'FAILED' / INSERT 速報比較結果"| WK_GW
  WK_GW -->|"UPDATE + INSERT"| DB_REQ
  WK_GW --> DB_RES
  WK_UC --> WK_Pres -->|"構造化ログ: run_id/判定/差分件数"| OUT_View
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| worker presentation | CronJobトリガー（引数なし） | 定期実行起点。lease/claim対象の走査開始 |
| worker gateway (claim) | rapid_crosscheck_requests への UPDATE（status=CLAIMED, worker_id, lease_expires_at） | REQUESTED行を排他的に取得し重複実行を防止 |
| worker gateway (definition) | comparison_definitions への SELECT（job_id, comparison_definition_valid_from の完全一致） | 依頼が保持する世代キーで比較定義を1件解決し、target_tables/target_files/comparator_idを比較処理へ引き渡す |
| worker domain | 速報比較依頼(RUNNING→SUCCEEDED/FAILED)、速報比較結果(comparisonResult/diffCount) | 依頼の4項目（blue_run_id/blue_attempt_id/green_run_id/green_attempt_id）で特定した起動試行のstdout/stderr/exit_codeを比較しOK/NG判定・差分件数を算出。比較範囲・比較実装は解決した比較定義のtarget_tables/target_files/comparator_idに従う |
| worker gateway (write) | rapid_crosscheck_requests UPDATE + rapid_crosscheck_results INSERT | 比較完了後の状態確定と結果永続化 |

## 処理フロー

```mermaid
sequenceDiagram
  actor Cron as CronJobスケジューラ

  box rgb(240,255,240) tier-worker
    participant Pres as presentation
    participant UC as usecase
    participant Domain as domain
    participant GW as gateway
  end

  participant DB as RDB

  Cron->>Pres: 定期実行トリガー（1分間隔想定）
  Pres->>UC: RunRapidCrosscheckCommand
  UC->>GW: REQUESTED状態の速報比較依頼を1件lease取得
  GW->>DB: UPDATE rapid_crosscheck_requests SET status='CLAIMED', worker_id='worker-01', lease_expires_at=now()+5m WHERE run_id=(SELECT run_id FROM rapid_crosscheck_requests WHERE status='REQUESTED' LIMIT 1 FOR UPDATE)
  DB-->>GW: 取得件数
  alt 取得件数0件
    GW-->>UC: 対象なし
    UC-->>Pres: 処理終了（対象なし）
  else 取得成功
    GW-->>UC: run_id
    UC->>GW: status='RUNNING'へ更新
    GW->>DB: UPDATE rapid_crosscheck_requests SET status='RUNNING' WHERE run_id=:run_id
    UC->>GW: blue/green Runner実行結果を取得（依頼の4項目で特定）
    GW->>DB: SELECT * FROM runner_results WHERE (run_id, slot_type, role_type, attempt_id) IN ((:blue_run_id, 'blue', 'background', :blue_attempt_id), (:green_run_id, 'green', 'background', :green_attempt_id))
    DB-->>GW: blue/green stdout/stderr/exit_code
    GW-->>UC: 比較対象データ
    UC->>GW: 比較定義を解決（依頼が保持する世代キーで固定）
    GW->>DB: SELECT target_tables, target_files, comparator_id FROM comparison_definitions WHERE job_id = :job_id AND valid_from = :comparison_definition_valid_from
    DB-->>GW: 該当世代1件（target_tables/target_files/comparator_id）
    GW-->>UC: 比較定義
    UC->>Domain: 比較実行（comparator_idの比較実装でtarget_tables/target_filesを比較）
    alt 差分なし
      Domain->>Domain: comparison_result='OK', diff_count=0
    else 差分あり
      Domain->>Domain: comparison_result='NG', diff_count=N, diff_detail_uri生成
    end
    Domain-->>UC: 比較結果
    UC->>GW: 速報比較依頼status確定＋速報比較結果永続化
    GW->>DB: UPDATE rapid_crosscheck_requests SET status='SUCCEEDED' or 'FAILED' + INSERT INTO rapid_crosscheck_results
    DB-->>GW: 登録完了
    GW-->>UC: 完了
    UC-->>Pres: 処理結果
    Pres-->>Cron: 構造化ログ出力, exit code 0
  end
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| クロスチェック種別 | 速報クロスチェック | ジョブ単位の非同期比較として実行し、確報クロスチェック（全量日次）とは独立して処理する | tier-worker | RunRapidCrosscheckCommand |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| 速報比較依頼状態（CLAIMED→RUNNING遷移判定） | workerがREQUESTED行をlease取得できた場合のみRUNNINGへ進む。lease失効かつ未着手の場合はREQUESTEDへ差し戻す | tier-worker | RunRapidCrosscheckCommand（lease/claim） | lease失効かつ未着手の速報比較依頼をREQUESTEDへ差し戻す |
| 比較判定（OK/NG） | blue/green runner_resultsのstdout/stderr/exit_codeが一致すればOK、差分があればNGとし差分件数をカウントする | tier-worker | 比較実行ロジック | 差分ありのためNG判定・FAILEDへ遷移する |
| 比較定義の解決 | 依頼が保持するjob_idとcomparison_definition_valid_fromでcomparison_definitionsの世代を1件に解決し、そのtarget_tables/target_files/comparator_idを比較に適用する（job_idと有効期間で1件に解決）。該当世代を解決できない場合はエラーとして比較を実行せず標準エラーへ記録する | tier-worker | RunRapidCrosscheckCommand（比較定義解決） | job_idに応じた比較定義が適用される |

## 計算ルール一覧

| 計算名 | 入力情報 | 計算式/ロジック | 出力情報 | 適用 tier |
|--------|---------|---------------|---------|----------|
| 差分件数算出 | blue/green双方のrunner_results（stdout/stderr/exit_code） | blue実装とgreen実装の出力を行単位で比較し不一致行数をカウントする | 速報比較結果.diff_count | tier-worker |
| 比較判定結果算出 | 差分件数 | diff_count=0ならcomparison_result='OK'、1件以上なら'NG' | 速報比較結果.comparison_result | tier-worker |

## 状態遷移一覧

| 状態モデル | 遷移元 | 遷移先 | トリガー | 事前条件 | 事後処理 | 適用 tier |
|-----------|--------|--------|---------|---------|---------|----------|
| 速報比較依頼状態 | REQUESTED | CLAIMED | 速報クロスチェックを実行し差分を検知する（lease取得） | REQUESTED状態の行が存在する | worker_id/lease_expires_atを記録 | tier-worker |
| 速報比較依頼状態 | CLAIMED | RUNNING | 速報クロスチェックを実行し差分を検知する | lease取得成功 | 比較処理を開始 | tier-worker |
| 速報比較依頼状態 | RUNNING | SUCCEEDED | 速報クロスチェックを実行し差分を検知する | 比較処理のexit_codeが0 | 速報比較結果(OK/差分0件)を確定 | tier-worker |
| 速報比較依頼状態 | RUNNING | FAILED | 速報クロスチェックを実行し差分を検知する | 比較処理のexit_codeが非0または差分検出 | 速報比較結果(NG/差分件数)を確定しハング検知記録の対象とする | tier-worker |
| 速報比較依頼状態 | CLAIMED | REQUESTED | lease失効かつworker未着手 | lease_expires_atを経過しRUNNINGへの遷移が発生していない | worker_id/lease_expires_atをクリアし再取得可能にする | tier-worker |

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | クロスチェック業務 | このUCが属する業務 |
| BUC | 速報クロスチェックフロー | このUCを含むBUC |
| アクター | 運用者 | 速報クロスチェック実行画面を参照するアクター（社内・提供者） |
| 情報 | 速報比較依頼 | 更新する情報（status, lease期限, worker識別子） |
| 情報 | Runner実行結果（started-at.txt/stdout.log/stderr.log/exitcode.txt） | 比較対象として参照する情報 |
| 情報 | 速報比較結果 | 新規作成する情報 |
| 情報 | 比較定義 | 依頼が保持する世代キー（job_id, comparison_definition_valid_from）で1件解決し、比較対象テーブル・比較対象ファイル・比較実装識別子を比較実行に適用する情報 |
| 状態 | 速報比較依頼状態 | REQUESTED→CLAIMED→RUNNING→SUCCEEDED/FAILED、CLAIMED→REQUESTED差し戻し |
| 条件 | 該当なし | 本UCの実行トリガー自体には条件.tsvの条件は適用されない（作成時のRAPID_CROSSCHECK_MODEはUC2で判定済み） |
| 外部システム | 該当なし | 本UCは外部システムと直接連携しない（比較対象はRDB上のRunner実行結果） |

## E2E 完了条件（BDD）

### 正常系

```gherkin
Feature: 速報クロスチェックを実行し差分を検知する

  Scenario: 差分なしでSUCCEEDEDへ遷移する
    Given execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement" の行と slot_execution_specs の blue/green 行が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="background", attempt_id="att-blue-0001", status="SUCCEEDED") と (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001", status="SUCCEEDED") の行が存在し、双方のstdout/stderr/exit_codeが一致している
    And rapid_crosscheck_requests に (run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", job_id="daily-settlement", blue_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", blue_attempt_id="att-blue-0001", green_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", green_attempt_id="att-green-0001", status="REQUESTED") の行が存在する
    When workerが `relaygate rapid-crosscheck run` を定期実行しrun_id "c41d7e08-2b95-4f36-a8d1-5e7c93b204af" をlease取得する
    Then rapid_crosscheck_requests の run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af" の status が "CLAIMED"→"RUNNING"→"SUCCEEDED" と遷移し、rapid_crosscheck_results に (run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", comparison_result="OK", diff_count=0) が作成される

  Scenario: 差分ありでFAILEDへ遷移する
    Given execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement" の行と slot_execution_specs の blue/green 行が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57") の blue/background/att-blue-0001 と green/background/att-green-0001 の実行結果が存在し、両者の出力に3行の差分がある
    And rapid_crosscheck_requests に (run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", blue_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", blue_attempt_id="att-blue-0001", green_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", green_attempt_id="att-green-0001", status="REQUESTED") の行が存在する
    When workerが `relaygate rapid-crosscheck run` を定期実行しrun_id "c41d7e08-2b95-4f36-a8d1-5e7c93b204af" をlease取得する
    Then rapid_crosscheck_requests の run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af" の status が "RUNNING"→"FAILED" と遷移し、rapid_crosscheck_results に (run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", comparison_result="NG", diff_count=3) が作成される

  Scenario: job_idに応じた比較定義が適用される
    Given comparison_definitions に (job_id="daily-settlement", valid_from="2026-08-01T00:00:00+09:00", valid_to=NULL, target_tables="settlement_summary,settlement_detail", target_files="settlement-report.csv", comparator_id="comparator-settlement-v1") の行が存在する
    And comparison_definitions に (job_id="nightly-inventory", valid_from="2026-08-01T00:00:00+09:00", valid_to=NULL, target_tables="inventory_stock", target_files="inventory-diff.tsv", comparator_id="comparator-inventory-v1") の行が存在する
    And rapid_crosscheck_requests に (run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", job_id="daily-settlement", comparison_definition_valid_from="2026-08-01T00:00:00+09:00", status="REQUESTED") の行と、対応するblue/green background試行一式（execution_specs・slot_execution_specs・runner_results）が存在する
    And rapid_crosscheck_requests に (run_id="d52e8f19-3ca6-4047-b9e2-6f8da4c315b0", job_id="nightly-inventory", comparison_definition_valid_from="2026-08-01T00:00:00+09:00", status="REQUESTED") の行と、対応するblue/green background試行一式が存在する
    When workerが `relaygate rapid-crosscheck run` を定期実行し両依頼を順にlease取得する
    Then run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af" の比較には (target_tables="settlement_summary,settlement_detail", target_files="settlement-report.csv", comparator_id="comparator-settlement-v1") が適用され、run_id="d52e8f19-3ca6-4047-b9e2-6f8da4c315b0" の比較には (target_tables="inventory_stock", target_files="inventory-diff.tsv", comparator_id="comparator-inventory-v1") が適用される

  Scenario: 有効期間に該当する比較定義が1件だけ適用される
    Given comparison_definitions に旧世代 (job_id="daily-settlement", valid_from="2026-07-01T00:00:00+09:00", valid_to="2026-08-01T00:00:00+09:00", comparator_id="comparator-settlement-v1") の行が存在する
    And comparison_definitions に現行世代 (job_id="daily-settlement", valid_from="2026-08-01T00:00:00+09:00", valid_to=NULL, comparator_id="comparator-settlement-v2") の行が存在する
    And rapid_crosscheck_requests に (run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", job_id="daily-settlement", comparison_definition_valid_from="2026-08-01T00:00:00+09:00", status="REQUESTED") の行（依頼作成時点 "2026-08-17T10:00:00+09:00" に有効期間から解決された世代）と、対応するblue/green background試行一式が存在する
    When workerが `relaygate rapid-crosscheck run` を定期実行しrun_id "c41d7e08-2b95-4f36-a8d1-5e7c93b204af" をlease取得する
    Then 比較には現行世代 (job_id="daily-settlement", valid_from="2026-08-01T00:00:00+09:00", comparator_id="comparator-settlement-v2") の1件だけが適用され、旧世代 comparator_id="comparator-settlement-v1" は適用されない
```

### 異常系

```gherkin
  Scenario: lease失効かつ未着手のためREQUESTEDへ差し戻す
    Given execution_specs・slot_execution_specs・runner_results に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の blue/green background試行一式が存在する
    And rapid_crosscheck_requests に (run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", status="CLAIMED", worker_id="worker-01", lease_expires_at="2026-08-17T15:00:00+09:00") の行が存在する
    And 現在時刻が "2026-08-17T15:10:00+09:00" でありlease_expires_atを経過し、かつstatusがRUNNINGへ遷移していない
    When workerが `relaygate rapid-crosscheck run` を定期実行しlease失効を検知する
    Then run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af" の status が "REQUESTED" へ差し戻され worker_id・lease_expires_at がNULLにクリアされる

  Scenario: 比較対象のRunner実行結果が未確定（片方未完了）の場合
    Given execution_specs・slot_execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の blue/green 行が存在する
    And runner_results に blue/background/att-blue-0001（status="SUCCEEDED"）の行は存在するが、green/background/att-green-0001 は status="RUNNING" で未確定である
    And rapid_crosscheck_requests に (run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", blue_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", blue_attempt_id="att-blue-0001", green_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", green_attempt_id="att-green-0001", status="REQUESTED") の行が存在する
    When workerが `relaygate rapid-crosscheck run` を実行しrun_id "c41d7e08-2b95-4f36-a8d1-5e7c93b204af" をlease取得する
    Then 比較処理は実行されず、標準エラーに "比較対象のRunner実行結果が揃っていません: c41d7e08-2b95-4f36-a8d1-5e7c93b204af" が記録され、status は "CLAIMED" のまま次回lease失効判定に委ねられる
```

## ティア別仕様

- [バックエンドワーカーティア](tier-worker.md)

### 統合 API Spec

- 本プロジェクトはHTTP APIを持たない。コマンド契約は `_cross-cutting/api/cli-command-contract.yaml`（全UC統合、Contract First開発用）を参照
