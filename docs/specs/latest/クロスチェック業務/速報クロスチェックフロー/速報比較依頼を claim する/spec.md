# 速報比較依頼を claim する

## 概要

速報クロスチェック worker(`rapid-crosscheck-worker.sh [--once] [--worker-id]`)が管理 DB の rapid_crosscheck_requests をジョブキューとして poll(30 秒間隔)し、REQUESTED の依頼を条件付き UPDATE で worker_id と lease_until(now + 10 分)付きの CLAIMED にする。CLAIMED で lease が失効しかつ未開始(started_at IS NULL)の依頼は REQUESTED へ戻し、別の worker が再取得できるようにして多重実行を防ぐ。速報の処理はジョブスケジューラ応答に影響させず、確報側(final_*)には触れない。

## データフロー

```mermaid
graph LR
  subgraph RAPID["tier-rapid-crosscheck(worker)"]
    R_Pres["presentation\nWorkerArgs(once, worker_id, poll_interval)"]
    R_UC["usecase\nClaimNextRequest"]
    R_Dom["domain\nLeasePolicy(lease_until = now + 10min)\nis_lease_expired"]
    R_Repo["repository\nRapidCrosscheckRequestRecord"]
    R_GW["gateway\nRDB クライアントアダプタ(条件付き UPDATE)"]
    R_Pres --> R_UC --> R_Dom
    R_UC --> R_Repo --> R_GW
  end
  subgraph DB["RDB"]
    T_REQ[("rapid_crosscheck_requests\nstatus, worker_id, lease_until, started_at, requested_at")]
  end
  R_GW -->|"SQL UPDATE ... SET status='REQUESTED', worker_id=NULL, lease_until=NULL WHERE status='CLAIMED' AND lease_until < now AND started_at IS NULL"| T_REQ
  R_GW -->|"SQL UPDATE ... SET status='CLAIMED', worker_id=?, lease_until=? WHERE run_id=(SELECT run_id ... WHERE status='REQUESTED' ORDER BY requested_at LIMIT 1) AND status='REQUESTED'"| T_REQ
  T_REQ --> R_GW --> R_Repo --> R_UC
  R_UC -->|"stdout claimed run_id / 終了コード"| R_Pres
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| presentation | WorkerArgs(once=false, worker_id=`$(hostname | tr . -)-$$`(ホスト名の `.` は `-` に置換), poll_interval=30) | 引数解析・既定値適用 |
| usecase | ClaimNextRequest | lease 失効分の解放 → 1 件 claim → 結果を返す(claim できなければ次の poll) |
| domain | LeasePolicy | lease_until の算出、失効判定(now > lease_until AND started_at IS NULL) |
| repository / gateway | 条件付き UPDATE 2 本 | 排他は WHERE 句で担保(行ロック不要) |

## 処理フロー

```mermaid
sequenceDiagram
  actor Sched as ジョブスケジューラ
  box rgb(240,255,240) tier-rapid-crosscheck(worker)
    participant Pres as presentation (rapid-crosscheck-worker.sh)
    participant UC as usecase (claim_next_request)
    participant Dom as domain (lease_policy)
    participant Repo as repository
    participant GW as gateway (rdb_exec)
  end
  participant DB as RDB
  participant FS as FS(実行ログ)

  Sched->>Pres: rapid-crosscheck-worker.sh [--once] [--worker-id worker-01]
  Pres->>Pres: 引数検証・worker_id 既定値
  Pres->>Pres: feature-flag.env の RAPID_CROSSCHECK_MODE を読む
  alt 速報クロスチェック有効判定: off
    Pres-->>Sched: stderr error: management db is not configured mode=off / 終了コード 3(DB に接続しない)
  end
  Pres->>Pres: rapid-crosscheck.env の RAPID_DB_CONN_REF を読む(不在・欠落は終了コード 2)
  loop poll(--once なら 1 回)
    Pres->>UC: ClaimNextRequest(worker_id, now)
    UC->>Repo: rapid_request_release_expired(now)
    Repo->>GW: UPDATE ... WHERE status='CLAIMED' AND lease_until < now AND started_at IS NULL
    GW->>DB: SQL
    DB-->>GW: 解放行数 n
    UC->>FS: n>0 なら INFO lease expired released count=n
    UC->>Dom: lease_until = now + RAPID_LEASE_SEC(600 秒)
    UC->>Repo: rapid_request_claim(worker_id, lease_until)
    Repo->>GW: UPDATE ... SET status='CLAIMED', worker_id, lease_until WHERE run_id=(oldest REQUESTED) AND status='REQUESTED' RETURNING run_id, job_id
    GW->>DB: SQL
    alt claim 排他: 更新 1 行
      DB-->>GW: run_id, job_id
      UC->>FS: INFO claimed run_id=... worker_id=... lease_until=...
      UC-->>Pres: claimed(run_id) → 比較実行 UC へ
    else 更新 0 行(依頼なし / 他 worker が先取)
      DB-->>GW: 0 行
      UC-->>Pres: none
      Pres->>Pres: --once なら終了コード 0 / 常駐なら sleep 30 秒
    end
  end
  Pres-->>Sched: 終了コード 0(--once)
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| 速報クロスチェックのプロセス役割 | worker | 本 UC の実行主体 | tier-rapid-crosscheck | rapid-crosscheck-worker.sh |
| 速報クロスチェックのプロセス役割 | runner(dispatcher) | 依頼の作成元(本 UC は参照しない) | tier-rapid-crosscheck | — |
| クロスチェック依頼状態 | REQUESTED | claim 対象 | tier-rapid-crosscheck | rapid_request_claim |
| クロスチェック依頼状態 | CLAIMED | claim 後の状態。lease 失効かつ未開始なら REQUESTED に戻す | tier-rapid-crosscheck | rapid_request_release_expired |
| クロスチェック依頼状態 | RUNNING / SUCCEEDED / FAILED / ABORTED | claim 対象外。lease 解放対象外 | tier-rapid-crosscheck | rapid_request_claim |
| クロスチェック種別 | 速報クロスチェック | rapid_crosscheck_requests のみを poll する | tier-rapid-crosscheck | claim_next_request |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| claim 排他 | `UPDATE ... WHERE status='REQUESTED'` の更新行数が 1 のときだけ claim 成功。worker_id と lease_until が設定され、lease 有効中は他 worker の同 UPDATE が 0 行になる | tier-rapid-crosscheck | rapid_request_claim(repository) | 2 worker が同時に poll しても claim は 1 つ |
| lease 失効判定 | `status='CLAIMED' AND lease_until < now AND started_at IS NULL` の依頼を REQUESTED に戻す(worker_id / lease_until を NULL)。started_at が設定済み(RUNNING 移行済み)は戻さない | tier-rapid-crosscheck | rapid_request_release_expired(repository)/ is_lease_expired(domain) | lease 失効かつ未開始の依頼を再取得する |
| 依頼状態遷移規則 | REQUESTED → CLAIMED(claim)、CLAIMED → REQUESTED(lease 失効)。他の遷移は本 UC で行わない | tier-rapid-crosscheck | claim_next_request | REQUESTED の依頼を claim する |
| 速報結果の位置付け | worker の処理・終了コードはジョブスケジューラの業務ジョブ応答に影響しない(別プロセス) | tier-rapid-crosscheck | rapid-crosscheck-worker.sh | REQUESTED の依頼を claim する |
| 速報と確報のモデル分離 | rapid_crosscheck_requests のみを poll / UPDATE する。final_crosscheck_requests は対象外 | tier-rapid-crosscheck | claim_next_request | REQUESTED の依頼を claim する |
| 速報クロスチェック有効判定 | worker は起動時に feature-flag.env の `RAPID_CROSSCHECK_MODE` を読む。off なら管理 DB に接続せず `error: management db is not configured mode=off` で終了コード 3。on なら rapid-crosscheck.env の `RAPID_DB_CONN_REF` で接続する(不在・欠落は終了コード 2) | tier-rapid-crosscheck | rapid-crosscheck-worker.sh(presentation) | RAPID_CROSSCHECK_MODE=off では管理 DB に接続しない |

## 計算ルール一覧

| 計算名 | 入力情報 | 計算式/ロジック | 出力情報 | 適用 tier |
|--------|---------|---------------|---------|----------|
| lease_until | now(UTC), `RAPID_LEASE_SEC`(rapid-crosscheck.env。既定 600) | now + RAPID_LEASE_SEC 秒(既定 10 分) | rapid_crosscheck_requests.lease_until | tier-rapid-crosscheck |
| 現在時刻(now) | システム時刻(UTC)、`RELAY_GATE_NOW`(テスト専用環境変数。ISO 8601 UTC。本番では未設定。設定されているときは now() の代わりにこの値を現在時刻として使う) | RELAY_GATE_NOW が設定されていればその値、無ければシステム時刻。lease_until の算出と lease 失効判定の両方に同じ now を使う | now | tier-rapid-crosscheck |
| lease 失効 | lease_until, now, started_at | `lease_until < now AND started_at IS NULL` → true | 解放対象 | tier-rapid-crosscheck |
| poll 間隔 | `RAPID_POLL_INTERVAL_SEC`(rapid-crosscheck.env。既定 30) | claim 0 件のとき sleep する秒数(常駐時) | 待機時間 | tier-rapid-crosscheck |
| 管理 DB 接続先 | `RAPID_DB_CONN_REF`(rapid-crosscheck.env) | 参照名から接続情報を解決する(値そのものは設定ファイルに置かない) | gateway の接続先 | tier-rapid-crosscheck |
| worker_id 既定値 | hostname, PID | `--worker-id` 未指定なら `{hostname}-{pid}` | rapid_crosscheck_requests.worker_id | tier-rapid-crosscheck |
| claim 順序 | requested_at | REQUESTED のうち requested_at 昇順で 1 件 | 対象 run_id | tier-rapid-crosscheck |

## 状態遷移一覧

| 状態モデル | 遷移元 | 遷移先 | トリガー | 事前条件 | 事後処理 | 適用 tier |
|-----------|--------|--------|---------|---------|---------|----------|
| クロスチェック依頼 | REQUESTED | CLAIMED | worker の poll / claim | 条件付き UPDATE が 1 行 | worker_id / lease_until 設定。比較実行 UC へ | tier-rapid-crosscheck |
| クロスチェック依頼 | CLAIMED | REQUESTED | lease 失効 | lease_until < now かつ started_at IS NULL | worker_id / lease_until を NULL。別 worker が再取得可 | tier-rapid-crosscheck |

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | クロスチェック業務 | この UC が属する業務 |
| BUC | 速報クロスチェックフロー | この UC を含む BUC(アクティビティ: 比較依頼の取得) |
| アクター | 運用者 | 受益者(自動) |
| 情報 | 速報比較依頼(rapid_crosscheck_request) | poll / claim / lease 更新 |
| 情報 | feature flag 設定 | RAPID_CROSSCHECK_MODE の参照(off なら DB に接続しない) |
| 状態 | クロスチェック依頼 | REQUESTED ⇄ CLAIMED |
| 条件 | 依頼状態遷移規則 | 適用 |
| 条件 | claim 排他 | 適用 |
| 条件 | lease 失効判定 | 適用 |
| 画面 | rapid-crosscheck worker claim 出力(→ CLI 出力) | stdout / 実行ログ |
| イベント | 速報比較依頼の claim と lease 更新 | 管理 DB(RDB)への条件付き UPDATE |
| 外部システム | 管理 DB(RDB) | ジョブキュー |

## 関連 USDM

| REQ ID | SPEC ID | 対応 BDD Scenario |
|--------|---------|-----------------|
| REQ-005 | SPEC-005-03 | REQUESTED の依頼を claim する(SPEC-005-03) |
| REQ-007 | SPEC-007-01 | lease 失効かつ未開始の依頼を再取得する(SPEC-007-01) |
| REQ-007 | SPEC-007-02 | REQUESTED の依頼を claim する(SPEC-005-03)(worker_id / lease_until の設定) |

## E2E 完了条件(BDD)

### 正常系

```gherkin
Feature: 速報比較依頼を claim する

  Scenario: REQUESTED の依頼を claim する(SPEC-005-03)
    Given RAPID_CROSSCHECK_MODE=on で rapid_crosscheck_requests に run_id=20260830T113000Z-JOB001-3f9a1c2e, status=REQUESTED, requested_at=2026-08-30T11:45:10Z の行がある
    And テスト専用環境変数 RELAY_GATE_NOW=2026-08-30T11:45:40Z が設定されている(worker はこれを now として使う)
    When ジョブスケジューラが `rapid-crosscheck-worker.sh --once --worker-id worker-01` を起動する
    Then 依頼の status は `CLAIMED`、worker_id は `worker-01`、lease_until は `2026-08-30T11:55:40Z` である
    And 実行ログに `INFO claimed run_id=20260830T113000Z-JOB001-3f9a1c2e worker_id=worker-01 lease_until=2026-08-30T11:55:40Z` が残る
    And final_crosscheck_requests は変更されない

  Scenario: lease 失効かつ未開始の依頼を再取得する(SPEC-007-01)
    Given rapid_crosscheck_requests に run_id=20260830T113000Z-JOB001-3f9a1c2e, status=CLAIMED, worker_id=worker-01, lease_until=2026-08-30T11:55:40Z, started_at=NULL の行がある
    And RELAY_GATE_NOW=2026-08-30T11:56:00Z が設定されている
    When `rapid-crosscheck-worker.sh --once --worker-id worker-02` を起動する
    Then 依頼はいったん REQUESTED に戻された後 `CLAIMED` になり、worker_id は `worker-02`、lease_until は `2026-08-30T12:06:00Z` である

  Scenario: 2 worker が同時に poll しても claim は 1 つ
    Given rapid_crosscheck_requests に status=REQUESTED の行が 1 件だけある
    When `rapid-crosscheck-worker.sh --once --worker-id worker-01` と `rapid-crosscheck-worker.sh --once --worker-id worker-02` を同時に起動する
    Then 依頼の worker_id は worker-01 か worker-02 のどちらか一方で、両 worker の終了コードは 0 である
```

### 異常系

```gherkin
  Scenario: lease 有効中の依頼は他 worker が取得できない
    Given rapid_crosscheck_requests に status=CLAIMED, worker_id=worker-01, lease_until=2026-08-30T11:55:40Z, started_at=NULL の行がある
    And RELAY_GATE_NOW=2026-08-30T11:50:00Z が設定されている
    When `rapid-crosscheck-worker.sh --once --worker-id worker-02` を起動する
    Then 依頼の status は `CLAIMED`、worker_id は `worker-01` のままで、worker-02 は終了コード 0 で終了する

  Scenario: 管理 DB に接続できない
    Given RAPID_CROSSCHECK_MODE=on で rapid-crosscheck.env の RAPID_DB_CONN_REF=relaygate-db が指す管理 DB が停止している
    When `rapid-crosscheck-worker.sh --once --worker-id worker-01` を起動する
    Then 終了コードは 6 で stderr に `error: management db connection failed worker_id=worker-01 conn_ref=relaygate-db` が出る

  Scenario: RAPID_CROSSCHECK_MODE=off では管理 DB に接続しない
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off が定義されている
    And rapid-crosscheck.env が存在しない
    When `rapid-crosscheck-worker.sh --once --worker-id worker-01` を起動する
    Then 終了コードは 3 で stderr に `error: management db is not configured mode=off` が出る
    And 管理 DB への接続は行われず、rapid_crosscheck_requests は変更されない
```

## ティア別仕様

- [速報クロスチェックティア](tier-rapid-crosscheck.md)

### 統合 API Spec

- [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml)(`rapid-crosscheck-worker.sh`)
- [AsyncAPI Spec](../../../_cross-cutting/api/asyncapi.yaml)(channel `rapid-crosscheck-requests` を subscribe)
