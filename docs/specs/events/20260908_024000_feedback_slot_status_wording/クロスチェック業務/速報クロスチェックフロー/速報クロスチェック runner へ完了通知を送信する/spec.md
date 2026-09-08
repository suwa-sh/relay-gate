# 速報クロスチェック runner へ完了通知を送信する

## 概要

blue / green の slot runner が Runner Result(exitcode.txt)を公開した直後に、自系統の公開 function `<RAPID_CROSSCHECK_RUNNER> blue-completed|green-completed --run-id --job-id --exit-code --artifact-uri` を起動して完了結果を一方向に通知する。送信先の実体は feature flag の `RAPID_CROSSCHECK_RUNNER`(速報クロスチェック runner の絶対パス)で解決し、facade / background-rerun が環境変数で slot runner へ渡す。runner は相手側の状態や比較依頼の要否を判断せず、自 slot の中止状態(aborted.txt の有無)も判断しない(中止後に実装が走り切って exitcode.txt を公開した場合も通常どおり通知する。条件「完了通知の系統独立」)。`RAPID_CROSSCHECK_MODE` が off 以外(foreground / background。両値の挙動は同じ)のときだけ通知し、off のときは完了通知を送信せず、速報管理 DB への接続・書き込みも行わない。完了通知の送信失敗は自動検知せず、slot runner は実行ログに警告を残して Runner Result と終了コードを変更しない(条件「完了通知失敗の扱い」)。受信側(tier-rapid-crosscheck)は速報クロスチェック設定(rapid-crosscheck.env。情報「速報クロスチェック設定」)の管理 DB 接続参照名で管理 DB に接続し、引数を検証して rapid_runs の自系統の status / artifact_uri / completed_at を更新する(両系成功判定と依頼作成は UC「両系成功時に速報比較依頼を作成する」)。

## データフロー

```mermaid
graph LR
  subgraph FACADE["tier-facade(slot runner)"]
    F_UC["usecase\nPublishRunnerResult(run_id, role, exit_code)"]
    F_Dom["domain\nRapidModeGuard(環境変数 RAPID_CROSSCHECK_MODE)"]
    F_Repo["repository\nRunnerResultRecord"]
    F_GW["gateway\nRAPID_CROSSCHECK_RUNNER 呼び出しアダプタ\nSlotCompletedNotice"]
    F_UC --> F_Dom
    F_UC --> F_Repo
    F_UC --> F_GW
  end
  subgraph RAPID["tier-rapid-crosscheck(dispatcher)"]
    R_Pres["presentation\nSlotCompletedArgs(subcommand, run_id, job_id, exit_code, artifact_uri)"]
    R_UC["usecase\nRegisterCompletion"]
    R_Dom["domain\nSlotResult(exit_code → SUCCEEDED / FAILED)"]
    R_Repo["repository\nRapidRunRecord"]
    R_GW["gateway\nRDB クライアントアダプタ"]
    R_Pres --> R_UC --> R_Dom
    R_UC --> R_Repo --> R_GW
  end
  subgraph FS["FS(成果物ディレクトリ)"]
    A["facade/<run_id>/<role>/exitcode.txt"]
  end
  subgraph DB["内部データストア: ジョブキュー兼管理 DB(RDB)"]
    T_RUN[("rapid_runs\nblue_status / green_status\nblue_artifact_uri / green_artifact_uri\nblue_completed_at / green_completed_at")]
  end
  A -->|"ファイル読み取り"| F_Repo
  F_GW -->|"$RAPID_CROSSCHECK_RUNNER blue-completed|green-completed --run-id --job-id --exit-code --artifact-uri"| R_Pres
  R_GW -->|"SQL UPDATE rapid_runs SET {role}_status=?, {role}_artifact_uri=?, {role}_completed_at=? WHERE run_id=?"| T_RUN
  R_Pres -->|"終了コード 0 / 2 / 3 / 6"| F_GW
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| facade usecase | PublishRunnerResult | exitcode.txt 公開後、RapidModeGuard が off 以外(foreground / background)のときだけ gateway を呼ぶ。RAPID_CROSSCHECK_MODE / RAPID_CROSSCHECK_RUNNER は facade / background-rerun が feature-flag.env から環境変数で渡す(runner 自身は feature-flag.env を読まない) |
| facade gateway | SlotCompletedNotice(run_id, job_id, exit_code, artifact_uri) | 引数へシリアライズして `$RAPID_CROSSCHECK_RUNNER <role>-completed` を同期起動。終了コードを実行ログに記録し、slot runner 自身の終了コードには反映しない(条件「完了通知失敗の扱い」) |
| rapid presentation | SlotCompletedArgs | サブコマンド・引数の検証(欠落・形式・exit_code 整数・artifact_uri のスキーム `file://` と絶対パス形式。存在確認はしない) |
| rapid domain | SlotResult | exit_code 0 → SUCCEEDED、非 0 → FAILED |
| rapid repository | RapidRunRecord | 自系統列の条件付き UPDATE(先勝ち。既に値があれば上書きせず終了コード 0) |

## 処理フロー

```mermaid
sequenceDiagram
  actor Sched as ジョブスケジューラ
  box rgb(230,240,255) tier-facade(slot runner)
    participant FUC as usecase (publish_runner_result)
    participant FDom as domain (rapid_mode_enabled)
    participant FGW as gateway (notify_slot_completed)
  end
  box rgb(240,255,240) tier-rapid-crosscheck(dispatcher)
    participant RPres as presentation (rapid-crosscheck-runner.sh)
    participant RUC as usecase (register_completion)
    participant RDom as domain (slot_status_from_exit_code)
    participant RRepo as repository (rapid_run_update_slot)
    participant RGW as gateway (rdb_exec)
  end
  participant FS as FS(成果物)
  participant DB as 管理 DB(RDB。内部データストア)

  Sched-)FUC: (facade 経由で起動済みの slot runner が実装実行を終える)
  FUC->>FS: exitcode.txt を .tmp → mv で公開
  FUC->>FDom: rapid_mode_enabled(環境変数 RAPID_CROSSCHECK_MODE)
  alt 速報クロスチェック有効判定: off
    FDom-->>FUC: false
    FUC-->>Sched: 完了通知を送らず終了(管理 DB に触れない)
  else off 以外(foreground / background)
    FUC->>FGW: notify_slot_completed(role, run_id, job_id, exit_code, artifact_uri)
    FGW->>RPres: $RAPID_CROSSCHECK_RUNNER {role}-completed --run-id ... --job-id ... --exit-code ... --artifact-uri ...
    RPres->>RPres: 引数検証
    alt 引数不正
      RPres-->>FGW: stderr error / 終了コード 2
    end
    RPres->>RUC: RegisterCompletion(role, run_id, job_id, exit_code, artifact_uri)
    RUC->>RGW: BEGIN(dispatcher の判定・INSERT と同一トランザクション)
    RUC->>RDom: slot_status_from_exit_code(exit_code)
    RDom-->>RUC: SUCCEEDED / FAILED
    RUC->>RRepo: rapid_run_update_slot(run_id, role, status, artifact_uri, now)
    RRepo->>RGW: UPDATE rapid_runs ... WHERE run_id=? AND {role}_status IS NULL
    RGW->>DB: SQL
    DB-->>RGW: 更新行数
    RUC-->>RPres: 登録結果(同一トランザクション内で両系成功判定へ: UC「両系成功時に速報比較依頼を作成する」が COMMIT する)
    RPres-->>FGW: stdout run_id= / job_id= / role= / slot_status= / 終了コード 0
    FGW->>FUC: 実行ログ INFO notify finished exit_code=0
    alt 完了通知失敗の扱い: 通知先が非 0 で終了
      FGW->>FUC: 実行ログ WARN completion notice failed run_id=... role=... runner=<RAPID_CROSSCHECK_RUNNER> exit_code=N
      FUC-->>Sched: Runner Result と終了コードは exitcode.txt のまま(自動再通知・自動検知はしない)
    end
  end
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| 実装スロット | blue | `blue-completed` を起動し、`blue_status` / `blue_artifact_uri` / `blue_completed_at` を更新する | tier-facade / tier-rapid-crosscheck | notify_slot_completed / rapid_run_update_slot |
| 実装スロット | green | `green-completed` を起動し、`green_*` 列を更新する | tier-facade / tier-rapid-crosscheck | notify_slot_completed / rapid_run_update_slot |
| 速報クロスチェックモード | foreground / background | 完了通知を送信する(両値で同じ挙動。判定は「off か off 以外か」) | tier-facade | publish_runner_result |
| 速報クロスチェックモード | off | 完了通知を送信せず、管理 DB へ接続・書き込みしない | tier-facade | publish_runner_result |
| 速報クロスチェックのプロセス役割 | runner(dispatcher) | 完了通知の受け口。一回ごとの起動 | tier-rapid-crosscheck | rapid-crosscheck-runner.sh |
| slot 実行モード | foreground / background | どちらの mode でも完了通知を送る(通知の有無は RAPID_CROSSCHECK_MODE だけで決まる) | tier-facade | publish_runner_result |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| 速報クロスチェック有効判定 | `RAPID_CROSSCHECK_MODE` が off 以外(foreground / background)のとき通知を送り、速報管理 DB に完了結果を書き込む(foreground と background の挙動は同じ)。off なら gateway を呼ばず、管理 DB の接続設定が無くても slot 実行は成功する | tier-facade | publish_runner_result(usecase) | RAPID_CROSSCHECK_MODE=off では通知しない / RAPID_CROSSCHECK_MODE=foreground でも background と同じく通知する |
| 完了通知の系統独立 | runner は自系統のサブコマンド(blue → blue-completed、green → green-completed)だけを起動し、相手側の rapid_runs 列や依頼の存在を参照しない。自 slot の中止状態(aborted.txt の有無)も判断せず、中止後に実装が走り切って exitcode.txt を公開した場合も通常どおり通知する(比較依頼の要否は受信側 dispatcher が条件「中止済み run の比較依頼作成除外」で判断する) | tier-facade / tier-rapid-crosscheck | notify_slot_completed / register_completion | green 未完了でも blue の通知は完結する / aborted.txt がある slot でも完了通知は通常どおり送る |
| Runner Result 完備条件 | 通知の exit_code は公開済み exitcode.txt の値と一致させる。3 ファイルの公開(mv 完了)後にのみ通知する | tier-facade | publish_runner_result | blue の完了通知が rapid_runs に登録される |
| 完了通知失敗の扱い | 通知の失敗(RAPID_CROSSCHECK_RUNNER の非 0 終了)は自動検知しない。slot runner は実行ログに `WARN completion notice failed run_id=... role=... runner=<RAPID_CROSSCHECK_RUNNER> exit_code=N` を残し、Runner Result(stdout.log / stderr.log / exitcode.txt)と終了コードは実装スクリプトの exitcode のまま変更しない(stderr.log へは追記しない。foreground slot では facade が stderr.log を中継するため、追記するとジョブスケジューラへの応答が変わる)。復旧は運用者が速報クロスチェック runner(RAPID_CROSSCHECK_RUNNER)を同一引数で再実行する(受信側は先勝ちの冪等で完了結果は一度だけ登録される)。自動再通知は行わない | tier-facade | notify_slot_completed(gateway) | 通知先が終了コード 6 でも Runner Result は変わらない / 通知失敗を運用者が同じ引数の再実行で復旧する / 通知失敗はハング検知で自動検知されない |
| 速報結果の位置付け | 完了通知の成否・速報側の結果は slot runner の終了コード・ジョブスケジューラ応答に影響しない | tier-facade | notify_slot_completed(gateway) | 通知先が終了コード 6 でも Runner Result は変わらない |
| 速報と確報のモデル分離 | 受信側は rapid_runs のみを更新する。final_crosscheck_requests には触れない | tier-rapid-crosscheck | register_completion | blue の完了通知が rapid_runs に登録される |

## 計算ルール一覧

| 計算名 | 入力情報 | 計算式/ロジック | 出力情報 | 適用 tier |
|--------|---------|---------------|---------|----------|
| slot 結果の判定 | exit_code | 0 → SUCCEEDED、非 0 → FAILED | rapid_runs.{role}_status | tier-rapid-crosscheck |
| artifact_uri の組み立て | RELAY_GATE_ARTIFACT_ROOT, run_id, role | `file://<RELAY_GATE_ARTIFACT_ROOT>/facade/<run_id>/<role>` | 通知引数 `--artifact-uri` | tier-facade |
| 完了日時 | 通知受信時刻 | ホストのローカルタイムゾーンの ISO 8601 秒精度(タイムゾーン指示子なし。run_id の時刻部と同じ時刻軸) | rapid_runs.{role}_completed_at | tier-rapid-crosscheck |
| 管理 DB 接続先 | `RAPID_DB_CONN_REF`(速報クロスチェック設定 rapid-crosscheck.env の属性「管理 DB 接続参照名」) | 参照名から接続情報を解決する(値そのものは設定ファイルに置かない) | 受信側 gateway の接続先 | tier-rapid-crosscheck |

## 状態遷移一覧

| 状態モデル | 遷移元 | 遷移先 | トリガー | 事前条件 | 事後処理 | 適用 tier |
|-----------|--------|--------|---------|---------|---------|----------|
| 該当なし(状態.tsv で本 UC を遷移 UC とする行は無い。slot 実行の RUNNING → SUCCEEDED / FAILED は UC「実装スクリプトを実行して Runner Result を出力する」、速報実行の完了状況の遷移は UC「両系成功時に速報比較依頼を作成する」が担う) | — | — | — | — | — | — |

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | クロスチェック業務 | この UC が属する業務 |
| BUC | 速報クロスチェックフロー | この UC を含む BUC(アクティビティ: 完了通知の送信) |
| アクター | 運用者 | 受益者(操作なし。自動) |
| 情報 | 完了通知 | 送信・受信する |
| 情報 | Runner Result | exit_code と artifact_uri の出所 |
| 情報 | slot 実行 | 通知元の slot |
| 情報 | feature flag 設定 | RAPID_CROSSCHECK_MODE(foreground / background / off)と RAPID_CROSSCHECK_RUNNER(完了通知の送信先)の参照(facade / background-rerun が環境変数で渡す) |
| 情報 | 実行ログ | 通知の開始・終了と `WARN completion notice failed` を残す |
| 情報 | 速報実行(rapid_run) | 受信側が更新する |
| 情報 | 速報クロスチェック設定 | 受信側が rapid-crosscheck.env を読む。属性: 管理 DB 接続参照名(RAPID_DB_CONN_REF。値は置かず参照名のみ)、lease 期間(秒。RAPID_LEASE_SEC)、worker の poll 間隔(秒。RAPID_POLL_INTERVAL_SEC)。本 UC は管理 DB 接続参照名だけを使う(tier-rapid-crosscheck) |
| 条件 | 速報クロスチェック有効判定 | 適用 |
| 条件 | 完了通知の系統独立 | 適用(自 slot の中止状態(aborted.txt)も判断しない) |
| 条件 | 完了通知失敗の扱い | 適用(送信失敗は自動検知しない。復旧は運用者の同一引数再実行) |
| 画面 | slot runner 完了通知出力(→ CLI 出力) | 速報クロスチェック runner の stdout / stderr / 終了コード(実行ログにのみ残る) |
| イベント | 完了結果の速報管理 DB 書き込み | rapid_runs の UPDATE |
| 内部データストア | ジョブキュー兼管理 DB(RDB) | 書き込み先(relay-gate 内部の構成要素。外部システムではない) |

## 関連 USDM

| REQ ID | SPEC ID | 対応 BDD Scenario |
|--------|---------|-----------------|
| REQ-001 | SPEC-001-01 | blue の完了通知が rapid_runs に登録される(SPEC-005-01)(AC「完了通知は RAPID_CROSSCHECK_RUNNER へ送る」の実行側。完了通知先 RAPID_CROSSCHECK_RUNNER) |
| REQ-005 | SPEC-005-01 | blue の完了通知が rapid_runs に登録される(SPEC-005-01) / green 未完了でも blue の通知は完結する(SPEC-005-01) / aborted.txt がある slot でも完了通知は通常どおり送る(SPEC-005-01) / 通知先が終了コード 6 でも Runner Result は変わらない(SPEC-005-01) / 通知失敗を運用者が同じ引数の再実行で復旧する(SPEC-005-01) / 通知失敗はハング検知で自動検知されない(SPEC-005-01) |
| REQ-005 | SPEC-005-06 | 設定された参照名で管理 DB に接続して完了結果を登録する(SPEC-005-06)(AC「設定された参照名で管理 DB に接続し…」の接続参照名側。lease / poll 側は UC「速報比較依頼を claim する」) |
| REQ-005 | SPEC-005-04 | blue の完了通知が rapid_runs に登録される(SPEC-005-01)(background で通知・DB 書き込み)/ RAPID_CROSSCHECK_MODE=foreground でも background と同じく通知する(SPEC-005-04) / RAPID_CROSSCHECK_MODE=off では通知しない(SPEC-005-04) |

## E2E 完了条件(BDD)

### 正常系

```gherkin
Feature: 速報クロスチェック runner へ完了通知を送信する

  Scenario: blue の完了通知が rapid_runs に登録される(SPEC-005-01)
    Given feature flag 設定に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh が定義されている
    And rapid_runs に run_id=20260830T113000-JOB001-3f9a1c2e, blue_status=NULL, green_status=NULL の行がある
    And facade/20260830T113000-JOB001-3f9a1c2e/blue/exitcode.txt の中身が `0` である
    When blue runner が実装実行を終えて Runner Result を公開する
    Then blue runner は `/opt/relay-gate/rapid-crosscheck-runner.sh blue-completed --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/blue` を起動する(送信先は環境変数 RAPID_CROSSCHECK_RUNNER の値)
    And rapid_runs の blue_status は `SUCCEEDED`、blue_artifact_uri は `file:///var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/blue`、blue_completed_at はローカル ISO 8601(タイムゾーン指示子なし)の値である
    And green_status は NULL のままである

  Scenario: 設定された参照名で管理 DB に接続して完了結果を登録する(SPEC-005-06)
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=background RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh が定義されている
    And 速報クロスチェック設定 $RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env に `RAPID_DB_CONN_REF=relaygate-db` の行があり、認証情報の値は含まれない
    And rapid_runs に run_id=20260830T113000-JOB001-3f9a1c2e, blue_status=NULL の行がある
    When blue runner が exit_code=0 で実装実行を終えて完了通知を送る
    Then 速報クロスチェック runner は参照名 `relaygate-db` から解決した接続情報で管理 DB に接続し、rapid_runs.blue_status は `SUCCEEDED` になる
    And 速報クロスチェック runner の終了コードは 0 で、rapid-crosscheck.env 以外から接続先を解決しない

  Scenario: RAPID_CROSSCHECK_MODE=foreground でも background と同じく通知する(SPEC-005-04)
    Given feature flag 設定に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=foreground RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh が定義されている
    And rapid_runs に run_id=20260830T113000-JOB001-3f9a1c2e, green_status=NULL の行がある
    When green runner が exit_code=0 で実装実行を終えて Runner Result を公開する
    Then green runner は `/opt/relay-gate/rapid-crosscheck-runner.sh green-completed --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/green` を起動する
    And rapid_runs の green_status は `SUCCEEDED` になる(background のときと同じ)

  Scenario: green 未完了でも blue の通知は完結する(SPEC-005-01)
    Given RAPID_CROSSCHECK_MODE=background で run_id=20260830T113000-JOB001-3f9a1c2e の green slot が RUNNING である
    When blue runner が exit_code=3 で完了通知を送る
    Then rapid-crosscheck-runner.sh は終了コード 0 で終了し rapid_runs.blue_status は `FAILED` になる
    And blue runner は green の状態を参照せず、blue runner の終了コードは exitcode.txt の `3` のままである

  Scenario: aborted.txt がある slot でも完了通知は通常どおり送る(SPEC-005-01)
    Given RAPID_CROSSCHECK_MODE=background RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh で run_id=20260830T113000-JOB001-3f9a1c2e の green slot(background)に対して運用者が abort-green を実行し、facade/20260830T113000-JOB001-3f9a1c2e/green/aborted.txt が公開されている
    And 中止後も green の実装スクリプトが走り切り、facade/20260830T113000-JOB001-3f9a1c2e/green/exitcode.txt が `0` で公開された
    When green runner が Runner Result の公開に続けて完了通知を送る
    Then green runner は aborted.txt の有無を判断せず `/opt/relay-gate/rapid-crosscheck-runner.sh green-completed --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/green` を通常どおり起動する
    And rapid_runs.green_status は `SUCCEEDED` になり、比較依頼の要否は green runner ではなく速報クロスチェック runner(dispatcher)が判断する(条件「中止済み run の比較依頼作成除外」。UC「両系成功時に速報比較依頼を作成する」)
```

### 異常系

```gherkin
  Scenario: RAPID_CROSSCHECK_MODE=off では通知しない(SPEC-005-04)
    Given feature flag 設定に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off が定義されている
    And 管理 DB の接続設定が存在しない
    When green runner が exit_code=0 で実装実行を終える
    Then 速報クロスチェック runner(RAPID_CROSSCHECK_RUNNER)は起動されない
    And 管理 DB への接続は行われず、green runner は終了コード 0 で終了する

  Scenario: 通知先が終了コード 6 でも Runner Result は変わらない(SPEC-005-01)
    Given RAPID_CROSSCHECK_MODE=background RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh で rapid_runs の UPDATE が SQL エラーになる(例: green_status 列に対する権限が無い)
    And facade/20260830T113000-JOB001-3f9a1c2e/green/exitcode.txt の中身が `0` である
    When green runner が完了通知を送る
    Then 速報クロスチェック runner は stderr に `error: management db update failed run_id=20260830T113000-JOB001-3f9a1c2e role=green` を出し終了コード 6 で終了する
    And green runner の実行ログに `WARN completion notice failed run_id=20260830T113000-JOB001-3f9a1c2e role=green runner=/opt/relay-gate/rapid-crosscheck-runner.sh exit_code=6` が残る
    And facade/20260830T113000-JOB001-3f9a1c2e/green/ の stdout.log / stderr.log / exitcode.txt は通知前と同一で(stderr.log への追記なし)、exitcode.txt は `0` のまま、green runner の終了コードは 0 である

  Scenario: 通知失敗を運用者が同じ引数の再実行で復旧する(SPEC-005-01)
    Given run_id=20260830T113000-JOB001-3f9a1c2e の green の完了通知が終了コード 6 で失敗し、rapid_runs.green_status が NULL、exitcode.txt が `0` である
    And 管理 DB が復旧している
    When 運用者が `/opt/relay-gate/rapid-crosscheck-runner.sh green-completed --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --exit-code 0 --artifact-uri file:///var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/green` を再実行する
    Then 終了コードは 0 で rapid_runs.green_status は `SUCCEEDED` になり、green の Runner Result と業務ジョブのジョブスケジューラ応答は変わらない
    And 同じコマンドをもう 1 回実行しても終了コードは 0 で rapid_runs の green_* 列は変わらない(先勝ち。完了結果は一度だけ登録される)

  Scenario: 通知失敗はハング検知で自動検知されない(SPEC-005-01)
    Given run_id=20260830T113000-JOB001-3f9a1c2e の green(background)の完了通知が終了コード 6 で失敗し、rapid_runs.green_status が NULL、facade/20260830T113000-JOB001-3f9a1c2e/green/exitcode.txt が `0` である
    When ジョブスケジューラが hang-detector.sh を起動する
    Then green の監視対象は exitcode.txt=0 により正常終了と判定され、通知失敗を理由にした通知メールは送られない(条件「完了通知失敗の扱い」: 自動検知しない。復旧は運用者の同一引数再実行)
```

## ティア別仕様

- [facade / slot runner ティア](tier-facade.md)(送信側)
- [速報クロスチェックティア](tier-rapid-crosscheck.md)(受信側)

### 統合 API Spec

- [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml)(`rapid-crosscheck-runner.sh blue-completed|green-completed`)
- [AsyncAPI Spec](../../../_cross-cutting/api/asyncapi.yaml)(channel `slot-completed`)
