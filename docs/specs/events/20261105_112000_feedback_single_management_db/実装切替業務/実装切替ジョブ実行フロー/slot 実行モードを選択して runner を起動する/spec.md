# slot 実行モードを選択して runner を起動する

## 概要

ジョブスケジューラから `facade.sh JOB_ID [PARAM...]` で起動された facade が、feature flag 設定を起動のたびに読み込み、blue / green slot ごとに foreground / background / off の実行モードを選択して runner を起動する。両 slot foreground の構成は入力検証で拒否し、どの slot も起動しない。background slot をすべて起動してから foreground slot を起動し、foreground の PID だけを待機する。run_id はモードによらず常に発行し、`RAPID_CROSSCHECK_MODE` が off 以外(foreground / background)のときだけ parallel_run を STARTED → RUNNING へ遷移させ、off のときは管理 DB に一切触れない。

## データフロー

```mermaid
graph LR
  subgraph SCHED["ジョブスケジューラ"]
    JOB["業務ジョブ定義\nfacade.sh JOB_ID PARAM..."]
  end
  subgraph FACADE["tier-facade"]
    P["presentation\nJobLaunchRequest(JOB_ID, PARAM...)"]
    U["usecase\nLaunchSlotsCommand"]
    D["domain\nSlotLaunchPlan(起動可否表 / foreground 排他)\nParallelRun(STARTED → RUNNING)"]
    R1["repository\nFeatureFlagConfig(9 キー: BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE / BLUE_IMPL / GREEN_IMPL / BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)\nRapidCrosscheckConfig(速報クロスチェック設定: RAPID_DB_CONN_REF。off 以外のみ)"]
    R2["repository\nParallelRunRepository / SlotExecutionRepository / RapidRunRepository"]
    G1["gateway\nRunnerProcessAdapter($BLUE_RUNNER / $GREEN_RUNNER)"]
    G2["gateway\nRdbClientAdapter"]
    P -->|"引数"| U
    U -->|"function 呼び出し"| D
    U --> R1
    U --> R2
    R2 --> G2
    U -->|"function 呼び出し"| G1
  end
  subgraph FS["FS(設定ファイル / 成果物ディレクトリ)"]
    CFG[("feature flag env\n9 キー")]
    RCFG[("rapid-crosscheck.env\n速報クロスチェック設定(RAPID_DB_CONN_REF)")]
    ART[("facade/run_id/\nrole ディレクトリ")]
  end
  subgraph RDB["RDB(ジョブキュー兼管理 DB。relay-gate 内部データストア)"]
    PR[("parallel_runs\nstatus=STARTED → RUNNING")]
    SE[("slot_executions\nstatus=RUNNING")]
    RR[("rapid_runs\ncompletion_status=PENDING")]
  end
  JOB -->|"引数 JOB_ID PARAM..."| P
  R1 -->|"ファイル読み込み"| CFG
  R1 -->|"ファイル読み込み(off 以外のみ。参照名だけ)"| RCFG
  G1 -->|"プロセス起動 runner IF + 環境変数(RAPID_CROSSCHECK_MODE / RAPID_CROSSCHECK_RUNNER / BLUE_IMPL / GREEN_IMPL)"| ART
  G2 -->|"SQL INSERT / UPDATE(off 以外のみ)"| PR
  G2 -->|"SQL INSERT(起動前, pid=NULL)→ UPDATE pid(起動後)(off 以外のみ)"| SE
  G2 -->|"SQL INSERT(off 以外のみ。parallel_runs と同一トランザクション)"| RR
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| presentation | JobLaunchRequest(JOB_ID, PARAM...) | 引数検証(JOB_ID 必須・job_id 文字種)。feature flag の検証結果を終了コード 2 に変換 |
| usecase | LaunchSlotsCommand | feature flag 読み込み → 起動計画作成 → run_id 発行 → (off 以外) parallel_run INSERT → background 起動 → foreground 起動 → (off 以外) RUNNING 更新 → foreground 待機 |
| domain | SlotLaunchPlan | 実装スロット × slot 実行モードの起動可否表。foreground × foreground を拒否。起動順序(background 全部 → foreground)を決める純粋関数 |
| repository | FeatureFlagConfig / RapidCrosscheckConfig / ParallelRunRepository / SlotExecutionRepository / RapidRunRepository | env ファイルの読み込み(feature-flag.env。RAPID_CROSSCHECK_MODE が off 以外のときだけ速報クロスチェック設定 rapid-crosscheck.env の RAPID_DB_CONN_REF も読む。値は参照名のみ)。parallel_runs の INSERT(STARTED)+ rapid_runs の INSERT(PENDING)を同一トランザクションで、slot_executions の INSERT(RUNNING。runner 起動前に pid=NULL)と pid の UPDATE(起動後)、parallel_runs の条件付き UPDATE(RUNNING) |
| gateway | RunnerProcessAdapter / RdbClientAdapter | runner IF `<runner> --run-id --job-id --role --mode -- PARAM...` でのプロセス起動と PID 取得(feature flag の値は環境変数 `RAPID_CROSSCHECK_MODE` / `RAPID_CROSSCHECK_RUNNER` / `BLUE_IMPL` / `GREEN_IMPL` で runner へ渡す。runner は feature-flag.env を読まない)。RDB クライアント CLI 呼び出し(ジョブキュー兼管理 DB は relay-gate 内部のデータストア) |

## 処理フロー

```mermaid
sequenceDiagram
  actor Sched as ジョブスケジューラ
  box rgb(240,255,240) tier-facade
    participant Pres as presentation(facade.sh)
    participant UC as usecase
    participant Dom as domain
    participant Repo as repository
    participant GW as gateway
  end
  participant FS as FS(設定 / 成果物)
  participant DB as RDB(parallel_runs)
  participant Runner as slot runner(BLUE_RUNNER / GREEN_RUNNER)

  Sched->>Pres: facade.sh JOB001 20260830 full
  Pres->>Pres: 引数検証(JOB_ID 必須)
  Pres->>UC: LaunchSlotsCommand(JOB001, [20260830, full])
  UC->>Repo: feature flag を読み込む
  Repo->>FS: 9 キー(BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE / BLUE_IMPL / GREEN_IMPL / BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)
  FS-->>Repo: 設定値
  UC->>Dom: SlotLaunchPlan を作る
  alt foreground slot 排他: BLUE_MODE=foreground かつ GREEN_MODE=foreground
    Dom-->>UC: 検証エラー(both slots foreground)
    UC-->>Pres: error
    Pres-->>Sched: stderr error:, 終了コード 2(どの slot も起動しない)
  else 起動可否判定: off の slot は除外
    Dom-->>UC: 起動計画(background 一覧, foreground 1 つ以下)
  end
  UC->>UC: run_id を発行(モードによらず常に。ローカル TZ の時刻 + job_id + 8 桁 hex)
  alt 速報クロスチェック有効判定: RAPID_CROSSCHECK_MODE が off 以外(foreground / background)
    UC->>Repo: 速報クロスチェック設定を読み込む
    Repo->>FS: rapid-crosscheck.env の RAPID_DB_CONN_REF(参照名のみ)
    FS-->>Repo: 接続参照名(不在・欠落は終了コード 2)
    UC->>Repo: parallel_run を STARTED で作成、rapid_run を PENDING で作成
    Repo->>GW: RDB アダプタ
    GW->>DB: 同一トランザクションで INSERT parallel_runs(status=STARTED) と INSERT rapid_runs(completion_status=PENDING)
  else off
    UC->>UC: 管理 DB へ接続しない(速報クロスチェック設定も読まない)
  end
  loop slot 起動順序: background slot をすべて起動
    opt RAPID_CROSSCHECK_MODE≠off(runner 起動前)
      GW->>DB: INSERT slot_executions(status=RUNNING, mode=background, pid=NULL)
    end
    UC->>GW: runner を background で起動(環境変数 RAPID_CROSSCHECK_MODE / RAPID_CROSSCHECK_RUNNER / <ROLE>_IMPL を渡す)
    GW->>Runner: <runner> --run-id --job-id --role --mode background -- PARAM...
    Runner-->>GW: PID
    opt RAPID_CROSSCHECK_MODE≠off(runner 起動後)
      GW->>DB: UPDATE slot_executions SET pid=? WHERE run_id=? AND slot=?
    end
  end
  opt foreground slot がある
    opt RAPID_CROSSCHECK_MODE≠off(runner 起動前)
      GW->>DB: INSERT slot_executions(status=RUNNING, mode=foreground, pid=NULL)
    end
    UC->>GW: runner を foreground で起動(この時点では待機しない)
    GW->>Runner: <runner> ... --mode foreground -- PARAM...
    Runner-->>GW: PID
    opt RAPID_CROSSCHECK_MODE≠off(runner 起動後)
      GW->>DB: UPDATE slot_executions SET pid=? WHERE run_id=? AND slot=?
    end
  end
  alt RAPID_CROSSCHECK_MODE≠off
    UC->>Repo: STARTED → RUNNING
    Repo->>GW: RDB アダプタ
    GW->>DB: UPDATE parallel_runs SET status='RUNNING' WHERE run_id=? AND status='STARTED'
  end
  UC->>GW: foreground の PID だけを待機
  GW-->>UC: foreground 終了
  UC-->>Pres: foreground の Runner Result パス(以降は UC「foreground slot の結果をジョブスケジューラへ中継する」)
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| 実装スロット | blue | `BLUE_MODE` / `BLUE_RUNNER` で起動可否と runner を決める。role=blue で起動 | tier-facade | facade.sh / domain `plan_slot_launch` |
| 実装スロット | green | `GREEN_MODE` / `GREEN_RUNNER` で起動可否と runner を決める。role=green で起動 | tier-facade | facade.sh / domain `plan_slot_launch` |
| slot 実行モード | foreground | 最後に起動し、その PID だけを待機して結果を中継する。同時に 1 slot だけ | tier-facade | domain `plan_slot_launch` / usecase `launch_slots` |
| slot 実行モード | background | foreground より先に起動する。待機しない。成果物は同じ 3 ファイル | tier-facade | usecase `launch_slots` |
| slot 実行モード | off | runner を起動しない | tier-facade | domain `plan_slot_launch` |
| 運用モード | 並行稼働 | BLUE_MODE=foreground / GREEN_MODE=background / RAPID_CROSSCHECK_MODE=background。blue の結果を返す | tier-facade | facade.sh |
| 運用モード | 新実装の単独本番 | BLUE_MODE=off / GREEN_MODE=foreground / RAPID_CROSSCHECK_MODE=off。green の結果を返し、管理 DB に触れない | tier-facade | facade.sh |
| 運用モード | 次世代実装との並行稼働 | BLUE_MODE=background / GREEN_MODE=foreground / RAPID_CROSSCHECK_MODE=background。green の結果を返す | tier-facade | facade.sh |
| 速報クロスチェックモード | foreground | background と同じ。parallel_runs INSERT(STARTED)→ UPDATE(RUNNING)、rapid_runs INSERT、slot_executions INSERT / UPDATE を行う(両値の挙動差は RDRA に定義が無く、spec では区別しない) | tier-facade | usecase `launch_slots` / repository `parallel_run_repo` |
| 速報クロスチェックモード | background | parallel_runs INSERT(STARTED)→ UPDATE(RUNNING)、rapid_runs INSERT、slot_executions INSERT / UPDATE を行う | tier-facade | usecase `launch_slots` / repository `parallel_run_repo` |
| 速報クロスチェックモード | off | 管理 DB へ接続・書き込みしない(parallel_run も作らない)。run_id は成果物ディレクトリ用に発行する | tier-facade | usecase `launch_slots` |
| ジョブスケジューラ起動ジョブ種別 | 業務ジョブ(facade) | `facade.sh JOB_ID [PARAM...]` だけを渡す | tier-facade | facade.sh |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| foreground slot 排他 | `BLUE_MODE=foreground` かつ `GREEN_MODE=foreground` なら検証エラー。stderr に `error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground` を出し終了コード 2。どの slot も起動しない | tier-facade | facade.sh / domain `validate_feature_flag` | 両 slot foreground は入力検証で拒否する(SPEC-001-02) |
| slot 起動可否判定 | mode が `off` の slot は起動しない。`foreground` / `background` の slot だけを起動する | tier-facade | domain `plan_slot_launch` | off の slot は起動しない(SPEC-001-01) |
| slot 起動順序 | background の slot をすべて起動して PID と成果物ディレクトリを確定してから foreground slot を起動し、すべて起動後に foreground の PID だけを `wait` する。RAPID_CROSSCHECK_MODE が off 以外のとき parallel_run を STARTED → RUNNING | tier-facade | usecase `launch_slots` | background を先に起動し foreground だけを待機する(SPEC-002-01) |
| 速報クロスチェック有効判定 | `RAPID_CROSSCHECK_MODE` が `foreground` または `background` のとき速報クロスチェック設定(rapid-crosscheck.env)の `RAPID_DB_CONN_REF`(管理 DB 接続参照名。認証情報の値は含まない)で管理 DB に接続して parallel_run を作成し、runner に `RAPID_CROSSCHECK_RUNNER` を環境変数で渡す(両値は同じ挙動)。`off` のときは速報クロスチェック設定を読まず、管理 DB へ接続も書き込みもせず(repository を呼ばない)、parallel_run も作らない(速報クロスチェック設定が存在しなくても slot 実行できる) | tier-facade | usecase `launch_slots` | RAPID_CROSSCHECK_MODE=off では管理 DB に触れない(SPEC-005-04) / RAPID_CROSSCHECK_MODE=foreground でも background と同じく parallel_run を作成する(SPEC-005-04) / 速報クロスチェック設定には管理 DB 接続の参照名だけがあり認証情報の値は含まれない(SPEC-005-06) / RAPID_CROSSCHECK_MODE=off では速報クロスチェック設定が存在しなくても slot 実行できる(SPEC-005-06) |
| 確報クロスチェック非起動 | feature flag に確報の制御キーは無い。facade は final-crosscheck-runner.sh を起動しない | tier-facade | facade.sh | 確報クロスチェックを起動しない(SPEC-001-01) |
| facade の責務限定 | facade は JOB_ID と PARAM... だけを受け取り、比較対象・実行先・起動方式を判断しない。PARAM... を順序を変えず runner に渡す | tier-facade | facade.sh / usecase `launch_slots` | 並行稼働モードで blue foreground と green background を起動する |
| 実装固有事項の runner への閉じ込め | facade は `$BLUE_RUNNER` / `$GREEN_RUNNER` に設定された実体を runner IF で起動するだけ。実体の中身に依存しない | tier-facade | gateway `runner_process_adapter` | 並行稼働モードで blue foreground と green background を起動する |

## 計算ルール一覧

| 計算名 | 入力情報 | 計算式/ロジック | 出力情報 | 適用 tier |
|--------|---------|---------------|---------|----------|
| run_id 発行 | 起動日時(ホストのローカルタイムゾーン。プロセスの `TZ` に従う)、JOB_ID | `{ローカル yyyymmddThhmmss}-{job_id}-{8 桁 hex 乱数}`(例 `20260830T113000-JOB001-3f9a1c2e`)。時刻部にタイムゾーン指示子(`Z` / オフセット)は付けない。正規表現 `^[0-9]{8}T[0-9]{6}-{job_id}-[0-9a-f]{8}$`。`RELAY_GATE_NOW`(UTC)設定時はその値をローカルタイムゾーンへ変換した時刻を使う(本 spec の例示値は `TZ=UTC` 前提)。RAPID_CROSSCHECK_MODE によらず facade 単独で発行し、成果物ディレクトリ名と管理 DB の run_id は同じ値 | run_id | tier-facade |
| 起動計画 | BLUE_MODE、GREEN_MODE | background 集合 = {slot : mode=background}、foreground = {slot : mode=foreground}(要素数 0 または 1)、off は除外 | SlotLaunchPlan | tier-facade |
| 成果物ディレクトリ | RELAY_GATE_ARTIFACT_ROOT、run_id、role | `$RELAY_GATE_ARTIFACT_ROOT/facade/<run_id>/<role>/` | artifact_dir | tier-facade |
| parameters(JSON) | PARAM... | 各引数を順序どおり JSON 配列文字列にする(例 `["20260830","full"]`。空なら `[]`) | parallel_runs.parameters | tier-facade |
| 運用モード名 | BLUE_MODE、GREEN_MODE、RAPID_CROSSCHECK_MODE | UC「feature flag を設定する」の運用モード表に一致すれば `parallel` / `green_only` / `next_gen_parallel`、表に無い有効な組合せは `custom`(値の出所は契約 config_files.feature-flag.env.derived。validate-config.sh と同じ関数) | operation_mode(実行ログ `feature flag loaded` 行) | tier-facade |

## 状態遷移一覧

| 状態モデル | 遷移元 | 遷移先 | トリガー | 事前条件 | 事後処理 | 適用 tier |
|-----------|--------|--------|---------|---------|---------|----------|
| 並行稼働実行 | `[*]` | STARTED | facade が run_id を発行して parallel_run を作成 | RAPID_CROSSCHECK_MODE が off 以外(foreground / background)、入力検証 OK | execution_spec_uri に `facade/<run_id>/execution-spec.json` を設定(保存は UC「execution-spec.json を確定保存する」) | tier-facade |
| 並行稼働実行 | STARTED | RUNNING | すべての slot を起動し foreground の PID 待機を開始 | parallel_runs.status=STARTED | 条件付き UPDATE(`WHERE run_id=? AND status='STARTED'`)。STARTED のまま運用者が中止した場合の STARTED → ABORTED は UC「実行を ABORTED へ遷移させる」 | tier-facade |
| slot 実行 | `[*]` | RUNNING | facade が runner を起動し、runner が started-at.txt を出力 | 起動計画に含まれる slot | RAPID_CROSSCHECK_MODE が off 以外のとき runner 起動「前」に slot_executions を mode / artifact_dir / status=RUNNING / pid=NULL で INSERT し、起動後に pid を UPDATE する(即時終了する runner の終端 UPDATE より INSERT が先に確定する順序を保証。仮採用: _inference.md #7)。状態の正本は成果物ファイル(条件「slot 実行の状態導出規則」: exitcode.txt も aborted.txt も無い = RUNNING)。管理 DB slot_executions.status は runner / abort-* の条件付き UPDATE(WHERE status='RUNNING')で一度だけ終端値を書き、abort 後に exitcode.txt を公開した経路だけ導出値と一致せず ABORTED のまま残る(正本: rdb-schema.yaml slot_executions.status) | tier-facade |
| 速報実行の完了状況 | `[*]` | 両系未完了(PENDING) | facade が run を開始し rapid_run を作成 | RAPID_CROSSCHECK_MODE が off 以外 | parallel_runs と同一トランザクションで rapid_runs を completion_status=PENDING で INSERT する(canonical C3。速報側の受信 UC は UPDATE のみ) | tier-facade |

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | 実装切替業務 | この UC が属する業務 |
| BUC | 実装切替ジョブ実行フロー | この UC を含む BUC |
| アクター | 運用者 | 受益者(ジョブ定義を変更せずに結果を受け取る) |
| 情報 | ジョブ起動要求 | JOB_ID / PARAM... の入力 |
| 情報 | feature flag 設定 | 起動のたびに読み込む。9 キー(BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE / BLUE_IMPL / GREEN_IMPL / BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)。設定版は持たない |
| 情報 | slot runner 割当 | BLUE_RUNNER / GREEN_RUNNER |
| 情報 | 速報クロスチェック設定 | 属性: 管理 DB 接続参照名(RAPID_DB_CONN_REF。値は置かず参照名のみ)/ lease 期間(秒。RAPID_LEASE_SEC)/ worker の poll 間隔(秒。RAPID_POLL_INTERVAL_SEC)。`$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env`。所有者は基盤適用設計者(設定所有区分)。facade は RAPID_CROSSCHECK_MODE が off 以外のとき RAPID_DB_CONN_REF だけを読む(lease / poll は速報クロスチェック worker が読む)。off では読まず、存在しなくても slot 実行できる。適用 tier: tier-facade |
| 情報 | 並行稼働実行(parallel_run) | RAPID_CROSSCHECK_MODE が off 以外のとき作成・更新。run_id 形式 `{ローカル yyyymmddThhmmss}-{job_id}-{8 桁 hex}`(off でも facade 単独で発行) |
| 情報 | slot 実行 | 起動した slot の mode / PID / 成果物ディレクトリ |
| 情報 | 速報実行(rapid_run) | RAPID_CROSSCHECK_MODE が off 以外のとき run 開始時に作成 |
| 情報 | 実行ログ | 起動・PID・待機を run_id 付きで記録 |
| 条件 | foreground slot 排他 / slot 起動可否判定 / slot 起動順序 / 速報クロスチェック有効判定 / 確報クロスチェック非起動 / facade の責務限定 / 実装固有事項の runner への閉じ込め | 分岐条件一覧を参照 |
| バリエーション | 実装スロット / slot 実行モード / 運用モード / 速報クロスチェックモード(foreground / background / off) | バリエーション一覧を参照 |
| 画面 | facade slot 起動出力(→ CLI 出力) | stderr の検証エラーと実行ログ |
| イベント | JOB_ID 付き facade 起動 / parallel_run の登録 | トリガー / 副作用 |
| 外部システム | ジョブスケジューラ | 起動元 |
| 内部データストア | ジョブキュー兼管理 DB(RDB) | RAPID_CROSSCHECK_MODE が off 以外のときの書き込み先(relay-gate 内部の構成要素。外部システムではない) |
| 状態 | 並行稼働実行 / slot 実行 / 速報実行の完了状況 | 状態遷移一覧を参照 |

## 関連 USDM

| REQ ID | SPEC ID | 対応 BDD Scenario |
|---|---|---|
| REQ-001 | SPEC-001-01 | 並行稼働モードで blue foreground と green background を起動する(SPEC-001-01) / off の slot は起動しない(SPEC-001-01) / 確報クロスチェックを起動しない(SPEC-001-01) |
| REQ-001 | SPEC-001-02 | 両 slot foreground は入力検証で拒否する(SPEC-001-02) |
| REQ-001 | SPEC-001-03 | 新実装の単独本番モードでは green だけを起動し管理 DB に触れない(SPEC-001-03) / 次世代並行稼働モードでは blue background と green foreground を起動する(SPEC-001-03) ※ 実行側。AC「ジョブ定義を変更しないで feature flag だけを変更すると並行稼働と単独本番を切り替えられる」の検証側(validate-config.sh --feature-flag が operation_mode=green_only を返す)は UC〈feature flag を設定する〉の Scenario「ジョブ定義を変えずに feature flag だけで運用モードを切り替える(SPEC-001-03)」で覆う |
| REQ-002 | SPEC-002-01 | background を先に起動し foreground だけを待機する(SPEC-002-01) |
| REQ-002 | SPEC-002-03 | 並行稼働モードで blue foreground と green background を起動する(SPEC-001-01) |
| REQ-005 | SPEC-005-04 | RAPID_CROSSCHECK_MODE=off では管理 DB に触れない(SPEC-005-04) / RAPID_CROSSCHECK_MODE=background では parallel_run を STARTED から RUNNING にする(SPEC-011-01) / RAPID_CROSSCHECK_MODE=foreground でも background と同じく parallel_run を作成する(SPEC-005-04) |
| REQ-005 | SPEC-005-06 | 速報クロスチェック設定には管理 DB 接続の参照名だけがあり認証情報の値は含まれない(SPEC-005-06) / RAPID_CROSSCHECK_MODE=off では速報クロスチェック設定が存在しなくても slot 実行できる(SPEC-005-06) |
| REQ-011 | SPEC-011-01 | RAPID_CROSSCHECK_MODE=background では parallel_run を STARTED から RUNNING にする(SPEC-011-01) |
| REQ-011 | SPEC-011-04 | run_id はローカルタイムゾーンの時刻と job_id と 8 桁 hex で発行され成果物と管理 DB で同値である(SPEC-011-04) / RAPID_CROSSCHECK_MODE=off では管理 DB に触れない(SPEC-005-04) ※ 2 件目は facade 単独で run_id を発行することの検証 |

> 機械可読の正本は `spec-event.yaml` の `use_cases[].usdm`(本表と同内容)。「対応 BDD Scenario」列は本 UC の `Scenario:` 名(接尾の SPEC ID を含む完全名)を「 / 」で区切って列挙し、Scenario 名以外の補足は「※」以降に置く。区切りは人が読む用で、Scenario 名自体に「 / 」を含むものがあるため機械分割には使わず、機械照合は `spec-event.yaml` の `scenarios[]` を使う。

## E2E 完了条件(BDD)

### 正常系

```gherkin
Feature: slot 実行モードを選択して runner を起動する

  Scenario: 並行稼働モードで blue foreground と green background を起動する(SPEC-001-01)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background BLUE_IMPL=v1 GREEN_IMPL=v2 BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=/opt/relay-gate/rapid-crosscheck-worker.sh が定義されている
    And 両 slot のジョブマップに job_id=JOB001 の行がある
    When ジョブスケジューラが facade.sh JOB001 20260830 full を実行する
    Then green runner が --role green --mode background -- 20260830 full で先に起動される
    And blue runner が --role blue --mode foreground -- 20260830 full でその後に起動される
    And 各 runner の環境変数に RAPID_CROSSCHECK_MODE=background RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh と自 slot の BLUE_IMPL=v1 または GREEN_IMPL=v2 が設定されている
    And facade は blue の PID だけを待機する
    And parallel_runs に run_id の行が status=RUNNING job_id=JOB001 parameters=["20260830","full"] で存在する

  Scenario: background を先に起動し foreground だけを待機する(SPEC-002-01)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background が定義されている
    And green の実装スクリプトは 600 秒、blue の実装スクリプトは 5 秒で終了する
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then facade は blue の終了後 10 秒以内に終了する
    And facade 終了時点で facade/<run_id>/green/exitcode.txt は存在しない(green は実行中)
    And 実行ログに "slot started slot=green mode=background" が "slot started slot=blue mode=foreground" より前に記録される

  Scenario: 新実装の単独本番モードでは green だけを起動し管理 DB に触れない(SPEC-001-03)
    Given ジョブスケジューラのジョブ定義は並行稼働モードのときと同じ facade.sh JOB001 のままで、変更していない
    And feature flag に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off が定義されている
    And 管理 DB の接続設定が存在しない
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then blue runner は起動されない
    And green runner が --role green --mode foreground で起動される
    And facade は管理 DB へ接続せず終了する
    And facade/<run_id>/green/ に started-at.txt が存在する

  Scenario: 次世代並行稼働モードでは blue background と green foreground を起動する(SPEC-001-03)
    Given feature flag に BLUE_MODE=background GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=background が定義されている
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then blue runner が --mode background で先に起動される
    And green runner が --mode foreground でその後に起動される
    And facade は green の PID だけを待機する

  Scenario: off の slot は起動しない(SPEC-001-01)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=off が定義されている
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then green runner は起動されない
    And facade/<run_id>/green/ ディレクトリは作成されない

  Scenario: RAPID_CROSSCHECK_MODE=background では parallel_run を STARTED から RUNNING にする(SPEC-011-01)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background が定義されている
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then parallel_runs に status=STARTED の行が INSERT された後に status=RUNNING へ更新される
    And execution_spec_uri が <RELAY_GATE_ARTIFACT_ROOT>/facade/<run_id>/execution-spec.json を指す
    And rapid_runs に run_id の行が completion_status=PENDING で存在する

  Scenario: RAPID_CROSSCHECK_MODE=off では管理 DB に触れない(SPEC-005-04)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off が定義されている
    And 管理 DB の接続設定が存在しない
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then blue と green の runner が起動される
    And 各 runner の環境変数に RAPID_CROSSCHECK_MODE=off が設定され RAPID_CROSSCHECK_RUNNER は設定されない
    And parallel_runs / slot_executions / rapid_runs に行は作成されない
    And facade 単独で発行した run_id 形式の成果物ディレクトリ facade/<run_id>/ が作成される

  Scenario: RAPID_CROSSCHECK_MODE=foreground でも background と同じく parallel_run を作成する(SPEC-005-04)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=foreground が定義されている
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then parallel_runs に run_id の行が status=RUNNING で存在する
    And rapid_runs に run_id の行が completion_status=PENDING で存在する
    And 各 runner の環境変数に RAPID_CROSSCHECK_MODE=foreground と RAPID_CROSSCHECK_RUNNER が設定されている

  Scenario: 速報クロスチェック設定には管理 DB 接続の参照名だけがあり認証情報の値は含まれない(SPEC-005-06)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background が定義されている
    And 速報クロスチェック設定 <RELAY_GATE_CONFIG_DIR>/rapid-crosscheck.env に RAPID_DB_CONN_REF=mgmt-db RAPID_LEASE_SEC=600 RAPID_POLL_INTERVAL_SEC=30 が定義されている
    When 運用者が速報クロスチェック設定の内容を確認し、ジョブスケジューラが facade.sh JOB001 を実行する
    Then rapid-crosscheck.env にはパスワード・接続文字列などの認証情報の値は無く、管理 DB 接続の参照名 RAPID_DB_CONN_REF だけがある
    And facade は参照名 mgmt-db で管理 DB に接続し parallel_runs に run_id の行を作成する
    And 実行ログにも stderr にも参照名から解決した接続情報の値は出ない

  Scenario: RAPID_CROSSCHECK_MODE=off では速報クロスチェック設定が存在しなくても slot 実行できる(SPEC-005-06)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off が定義されている
    And <RELAY_GATE_CONFIG_DIR>/rapid-crosscheck.env が存在しない
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then blue と green の runner が起動される
    And facade は rapid-crosscheck.env を読まず、終了コードは foreground の exitcode.txt の値である
    And facade/<run_id>/blue/ と facade/<run_id>/green/ に started-at.txt が存在する

  Scenario: run_id はローカルタイムゾーンの時刻と job_id と 8 桁 hex で発行され成果物と管理 DB で同値である(SPEC-011-04)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background が定義されている
    And TZ=UTC で RELAY_GATE_NOW=2026-08-30T11:30:00Z が設定されている
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then 発行された run_id は正規表現 ^20260830T113000-JOB001-[0-9a-f]{8}$ に一致し、末尾に Z を含まない
    And 成果物ディレクトリ名 facade/<run_id>/ と parallel_runs.run_id は同じ値である

  Scenario: 確報クロスチェックを起動しない(SPEC-001-01)
    Given feature flag に確報クロスチェックの制御キーは存在しない
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then final-crosscheck-runner.sh は起動されない
```

### 異常系

```gherkin
  Scenario: 両 slot foreground は入力検証で拒否する(SPEC-001-02)
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=background が定義されている
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then 終了コード 2 で終了する
    And stderr に "error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground" が出る
    And blue runner も green runner も起動されない
    And parallel_runs に行は作成されない

  Scenario: JOB_ID が無い起動は拒否する
    Given feature flag が正しく定義されている
    When ジョブスケジューラが facade.sh を引数なしで実行する
    Then 終了コード 2 で終了する
    And stderr に "error: JOB_ID required" が出る
    And どの runner も起動されない

  Scenario: 未知の実行モードは拒否する
    Given feature flag に BLUE_MODE=parallel GREEN_MODE=background が定義されている
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then 終了コード 2 で終了する
    And stderr に "error: invalid value key=BLUE_MODE value=parallel" が出る
    And stderr の次行に "hint: use foreground, background or off" が出る
    And どの runner も起動されない

  Scenario: RAPID_CROSSCHECK_MODE=background で管理 DB に接続できない
    Given feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background が定義されている
    And 管理 DB が停止している
    When ジョブスケジューラが facade.sh JOB001 を実行する
    Then 終了コード 6 で終了する
    And stderr に "error: management db connection failed run_id=" で始まり "conn_ref=" を含む行が出る
    And どの runner も起動されない
```

## ティア別仕様

- [facade / slot runner ティア](tier-facade.md)

### 統合契約

- [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml)(`facade.sh` を defines)
- [AsyncAPI Spec](../../../_cross-cutting/api/asyncapi.yaml)(この UC は publish / subscribe しない)
- 後続 UC: [ジョブマップで JOB_ID から実行先を解決する](../ジョブマップで%20JOB_ID%20から実行先を解決する/spec.md) / [foreground slot の結果をジョブスケジューラへ中継する](../foreground%20slot%20の結果をジョブスケジューラへ中継する/spec.md)
