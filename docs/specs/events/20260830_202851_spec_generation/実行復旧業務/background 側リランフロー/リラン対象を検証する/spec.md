# リラン対象を検証する

## 概要

ジョブスケジューラの background リラン専用ジョブから `background-rerun.sh --source-run-id <RUN_ID> --role blue|green|rapid-crosscheck` で起動された background-rerun が、元の実行を事前検証する。元実行の特定元は role で分岐する: `--role blue / green` は元 run の `execution-spec.json`(と管理 DB の slot_executions)を読み、元の slot mode が background かつ元の状態が終端(SUCCEEDED / FAILED / ABORTED)のときだけ可とする。`--role rapid-crosscheck` は `execution-spec.json` を要求せず、管理 DB(on が前提)の `rapid_crosscheck_requests`(と後続 UC が読む `rapid_runs`)だけで元実行を特定し、元 run の速報比較依頼が終端のときだけ可とする。これにより、rapid-crosscheck リランで作られた run(`execution-spec.json` を持たない)を再度 `--source-run-id` に指定でき、parent_run_id の数珠つなぎリランが成立する。foreground / off、RUNNING(中止未確認)、未対応 role、元実行なし(blue / green: execution-spec.json なし、rapid-crosscheck: 依頼なし)はリランせず終了コード 3 で終了し、foreground slot と確報クロスチェックはジョブスケジューラの正規ジョブを再実行する旨をヒントに出す。検証を通過した後の処理は UC「元の execution-spec.json から復元して新しい run_id で起動する」(blue / green)と UC「速報比較依頼だけを新規作成する」(rapid-crosscheck)が担う。

## データフロー

```mermaid
graph LR
  subgraph OPS["tier-ops"]
    OPS_Pres["presentation\nbackground-rerun.sh 引数 (--source-run-id / --role)"]
    OPS_UC["usecase\nRerunPrecheck"]
    OPS_Domain["domain\nRerunEligibility\n(role x 元 mode x 元状態 の判定表)"]
    OPS_Repo["repository\nExecutionSpecRepository / SlotExecutionRepository / CrosscheckRequestRepository / ParallelRunRepository"]
    OPS_GW["gateway\nファイルシステム走査 / RDB クライアント"]
    OPS_Pres --> OPS_UC --> OPS_Domain
    OPS_UC --> OPS_Repo --> OPS_GW
  end
  subgraph DB["RDB"]
    DB_PR[("parallel_runs\nrun_id / job_id / status")]
    DB_SE[("slot_executions\nmode / status")]
    DB_RR[("rapid_crosscheck_requests\nstatus")]
  end
  subgraph FS["FS(成果物ディレクトリ)"]
    FS_Spec["facade/<source_run_id>/execution-spec.json"]
    FS_Art["facade/<source_run_id>/<role>/started-at.txt / exitcode.txt"]
  end
  OPS_GW -->|"ファイル読み取り(blue / green のみ)"| FS_Spec
  OPS_GW -->|"ファイル読み取り(blue / green の off 時の状態導出)"| FS_Art
  OPS_GW -->|"SQL: SELECT WHERE run_id = ?"| DB_PR
  OPS_GW -->|"SQL: SELECT WHERE run_id = ? AND slot = ?(blue / green)"| DB_SE
  OPS_GW -->|"SQL: SELECT WHERE run_id = ?(rapid-crosscheck。execution-spec.json は読まない)"| DB_RR
  FS_Spec --> OPS_GW --> OPS_Repo --> OPS_Domain --> OPS_UC --> OPS_Pres
  OPS_Pres -->|"stderr: error + hint / 終了コード 3"| Sched["ジョブスケジューラ(専用ジョブ)"]
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| ops presentation | 引数(`--source-run-id 20260830T113000Z-JOB001-3f9a1c2e`, `--role green`) | 引数検証(role 列挙・run_id 形式)→ RerunPrecheck |
| ops repository / gateway | blue / green: execution-spec.json(`slots.{role}` 節の有無と mode / host / exec_user / script_path / work_dir / args)、slot_executions(mode / status)。rapid-crosscheck: rapid_crosscheck_requests(存在 / status)。共通: parallel_runs(job_id) | 元実行の存在確認と状態取得(特定元は role で分岐) |
| ops domain | RerunEligibility: role × 元 mode × 元状態 の判定表 | 可 / 不可(理由コード) |
| ops presentation(出力) | 不可: `error: source run is not rerunnable ...` + `hint: ...`、終了コード 3。可: 後続 UC へ | 判定結果の提示 |

## 処理フロー

```mermaid
sequenceDiagram
  actor Sched as ジョブスケジューラ(background リラン専用ジョブ)
  box rgb(240,255,240) tier-ops
    participant Pres as presentation
    participant UC as usecase
    participant Domain as domain
    participant Repo as repository
    participant GW as gateway
  end
  participant FS as FS(成果物ディレクトリ)
  participant DB as RDB

  Sched->>Pres: background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role green
  Pres->>Pres: 引数検証(--source-run-id / --role 必須。role は blue / green / rapid-crosscheck → 他は 2)
  Pres->>UC: RerunPrecheck(source_run_id, role)
  alt role = blue / green
    UC->>Repo: 元の execution-spec.json を読む
    Repo->>GW: ファイル読み取り facade/<source_run_id>/execution-spec.json
    GW->>FS: read
    alt ファイルなし
      FS-->>GW: なし
      UC-->>Pres: 業務エラー
      Pres-->>Sched: stderr error: execution-spec not found run_id=... path: ... / 終了コード 3
    else あり
      FS-->>GW: execution-spec(slots.{role} 節。節が無ければ mode=off とみなす)
      UC->>Repo: 元 slot の状態(on: slot_executions / off: started-at.txt と exitcode.txt から導出)
      Repo->>GW: SELECT slot_executions WHERE run_id = ? AND slot = ?
      GW->>DB: SQL
      DB-->>GW: 行(mode / status)
    end
  else role = rapid-crosscheck(execution-spec.json は読まない)
    alt RAPID_CROSSCHECK_MODE=off
      UC-->>Pres: 業務エラー(管理 DB 接続前)
      Pres-->>Sched: stderr error: management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=... role=rapid-crosscheck / 終了コード 3
    else on
      UC->>Repo: 元 run の速報比較依頼の状態
      Repo->>GW: SELECT rapid_crosscheck_requests WHERE run_id = ?
      GW->>DB: SQL
      DB-->>GW: 行(status)or 0 行
      alt 0 行
        UC-->>Pres: 業務エラー
        Pres-->>Sched: stderr error: source request not found run_id=... role=rapid-crosscheck / hint: ... / 終了コード 3
      end
    end
  end
  opt 元実行が特定できた
    UC->>Domain: RerunEligibility(role, 元 mode, 元状態)
    alt 不可
      Domain-->>UC: 理由(mode_not_background / source_running / request_not_terminal / source_not_found / ...)
      UC-->>Pres: 業務エラー
      Pres-->>Sched: stderr error: source run is not rerunnable run_id=... role=... mode=... status=... / hint: ... / 終了コード 3
      Note over UC: 実行ログ INFO rerun rejected operator=... reason=...
    else 可
      Domain-->>UC: 可
      Note over UC,Pres: blue / green → UC「元の execution-spec.json から復元して新しい run_id で起動する」/ rapid-crosscheck → UC「速報比較依頼だけを新規作成する」
    end
  end
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| リラン対象 role | blue | 元 slot(blue)の mode が background かつ状態が終端なら可 | tier-ops | domain `is_rerunnable` |
| リラン対象 role | green | 同上(green) | tier-ops | domain `is_rerunnable` |
| リラン対象 role | rapid-crosscheck | 元 run の速報比較依頼が SUCCEEDED / FAILED / ABORTED なら可。RUNNING / CLAIMED / REQUESTED は不可 | tier-ops | domain `is_rerunnable` |
| slot 実行モード | background | リラン可の前提 | tier-ops | domain `is_rerunnable` |
| slot 実行モード | foreground | 不可。ヒント: ジョブスケジューラの正規ジョブを再実行 | tier-ops | domain `is_rerunnable` |
| slot 実行モード | off | 不可(元の実行が存在しない。execution-spec.json に `slots.{role}` 節が無いことで判定する) | tier-ops | domain `is_rerunnable` |
| 再実行経路 | background 側リラン | background slot と速報比較依頼 | tier-ops | background-rerun.sh |
| 再実行経路 | ジョブスケジューラ正規ジョブ再実行 | foreground slot と確報クロスチェック(`--role final-crosscheck` は run role として存在するが background-rerun.sh の enum 外。`foo` 等と同じく引数不正 = 2) | tier-ops | background-rerun.sh の hint |
| クロスチェック依頼状態 | SUCCEEDED / FAILED / ABORTED | rapid-crosscheck リラン可 | tier-ops | domain `is_rerunnable` |
| クロスチェック依頼状態 | REQUESTED / CLAIMED / RUNNING | rapid-crosscheck リラン不可(RUNNING は中止を促す) | tier-ops | domain `is_rerunnable` |
| 速報クロスチェックモード | on / off | on は slot_executions で、off は `started-at.txt` の有無と `exitcode.txt` の有無・値で元状態を導出する(started-at.txt なし = 未起動 → 不可。ABORTED は導出不可 → RUNNING 扱い。仮採用 #7)。off かつ `--role rapid-crosscheck` は管理 DB が無いため終了コード 3 | tier-ops | repository `resolve_source_state` / usecase の管理 DB 接続前判定 |
| 元実行の特定元 | blue / green | `facade/<source_run_id>/execution-spec.json`(必須)+ slot_executions(on) | tier-ops | repository `ExecutionSpecRepository` / `SlotExecutionRepository` |
| 元実行の特定元 | rapid-crosscheck | `rapid_crosscheck_requests`(必須。execution-spec.json は読まない。rapid-crosscheck リランで作られた run も元にできる) | tier-ops | repository `CrosscheckRequestRepository` |
| ジョブスケジューラ起動ジョブ種別 | background リラン専用ジョブ | `background-rerun.sh` を業務ジョブとは別の専用ジョブ定義から起動する(run_id と role を引数に渡す) | tier-ops | background-rerun.sh の起動元 |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| リラン事前検証 | 縦軸 role(blue / green / rapid-crosscheck)× 横軸 元 mode(foreground / background / off)× 元状態。blue / green: `background × {SUCCEEDED, FAILED, ABORTED}` のみ可。`background × RUNNING` は中止未確認として不可(hint に abort-{role}.sh)。foreground / off は不可。rapid-crosscheck: 依頼 `{SUCCEEDED, FAILED, ABORTED}` のみ可。`final-crosscheck`(run role としては存在するが background-rerun.sh の enum 外。確報は正規ジョブで再実行)と enum に無い文字列(`foo` 等)は引数不正(2。事前検証に入らない)。元実行なしは不可(3)。元実行の特定元は role で分岐: blue / green は execution-spec.json(なしは `execution-spec not found`)、rapid-crosscheck は rapid_crosscheck_requests(なしは `source request not found`。execution-spec.json は要求しない) | tier-ops | domain `is_rerunnable`(判定表)、presentation `parse_args`(role 列挙)、usecase の特定元分岐 | background で完了した green は検証を通過する / foreground の blue は拒否する / RUNNING の green は中止を促して拒否する / ABORTED の速報比較依頼は検証を通過する / rapid-crosscheck リランで作られた run を再度リラン元にできる |
| 復旧手段の選択 | foreground slot と確報クロスチェックは background-rerun を使わずジョブスケジューラの正規ジョブを直接再実行する。該当時は stderr の hint に `rerun the scheduler job instead (foreground slot / final crosscheck are not handled by background-rerun.sh)` を出す | tier-ops | presentation のエラーヒント | foreground の blue は拒否する |
| 速報クロスチェック有効判定 | RAPID_CROSSCHECK_MODE=off では管理 DB(依頼)が存在しないため、`--role rapid-crosscheck` は管理 DB 接続前に `error: management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=... role=rapid-crosscheck` で終了コード 3(abort-* の off 時と同じ文言)。blue / green は成果物ファイルだけで元状態を導出する | tier-ops | usecase の管理 DB 接続前判定 | RAPID_CROSSCHECK_MODE=off の rapid-crosscheck は管理 DB 無しとして拒否する |

## 計算ルール一覧

| 計算名 | 入力情報 | 計算式/ロジック | 出力情報 | 適用 tier |
|--------|---------|---------------|---------|----------|
| 元 mode の解決(blue / green) | execution-spec.json の `slots` | `slots.{role}` 節が存在しない → mode=off とみなす(契約 execution_spec_rules「mode が off の slot は節を持たない」)。存在すれば `slots.{role}.mode`(foreground / background。C1 の構造) | mode | tier-ops |
| 元状態の解決(on) | slot_executions.status | `SELECT status WHERE run_id = ? AND slot = ?` | status | tier-ops |
| 元状態の解決(off) | `facade/<run_id>/<role>/started-at.txt`、`facade/<run_id>/<role>/exitcode.txt` | started-at.txt 無し → 未起動(status=`-`。不可 `source_not_started`)。started-at.txt あり かつ exitcode.txt 無し → RUNNING(中止未確認扱い)、`0` → SUCCEEDED、非 0 → FAILED | status | tier-ops |
| 元実行の特定(rapid-crosscheck) | rapid_crosscheck_requests | `SELECT status WHERE run_id = ?`。0 行 → `request_not_found`。execution-spec.json とファイルシステムは読まない(元 run が rapid-crosscheck リランで作られた run でも成立する) | 存在 / status | tier-ops |
| 可否判定 | role, mode, status | 判定表(分岐条件「リラン事前検証」) | eligible / reason | tier-ops |
| 指示日時 | now(UTC) | 情報「リラン指示」の属性「指示日時」= 後続 UC が作成する新 run の `parallel_runs.requested_at` および実行ログ行(`INFO rerun requested` / `INFO precheck passed`)の UTC 時刻列 | requested_at / 実行ログ | tier-ops |

## 状態遷移一覧

| 状態モデル | 遷移元 | 遷移先 | トリガー | 事前条件 | 事後処理 | 適用 tier |
|-----------|--------|--------|---------|---------|---------|----------|
| 該当なし(検証のみ。状態.tsv にこの UC を遷移 UC とする行は無い。通過後の遷移は後続 2 UC に載せる) | — | — | — | — | — | — |

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | 実行復旧業務 | この UC が属する業務 |
| BUC | background 側リランフロー | この UC を含む BUC(アクティビティ: リラン対象の事前検証) |
| アクター | 運用者 | 専用ジョブを起動し検証結果を読む(受益者) |
| 情報 | リラン指示 | source_run_id / role / 事前検証結果(元の mode / 元の状態 / role 妥当性) |
| 情報 | 実行設定(execution-spec) | 元 run の execution-spec.json の存在と mode の確認(blue / green のみ。rapid-crosscheck は読まない) |
| 情報 | 並行稼働実行(parallel_run) | 元実行の存在確認 |
| 情報 | slot 実行 | 元 slot の mode / status |
| 情報 | 速報比較依頼(rapid_crosscheck_request) | 元 run の依頼 status |
| 条件 | リラン事前検証 | 判定表 |
| 条件 | 復旧手段の選択 | foreground / 確報はジョブスケジューラで再実行 |
| 条件 | 速報クロスチェック有効判定 | off かつ rapid-crosscheck は管理 DB 無しとして 3 |
| バリエーション | 速報クロスチェックモード | on / off で元状態の解決元が異なる |
| バリエーション | ジョブスケジューラ起動ジョブ種別 | background リラン専用ジョブから起動 |
| 画面 | background-rerun 事前検証出力(→ CLI 出力: stderr の error / hint と終了コード) | 運用者が読む出力 |
| イベント | リラン専用ジョブの起動 | 外部システム: ジョブスケジューラ |
| イベント | 元実行の状態確認 | 外部システム: 管理 DB(RDB) |
| 外部システム | ジョブスケジューラ | 専用ジョブの起動元 |
| 外部システム | 管理 DB(RDB) | 元実行の状態参照先 |

## 関連 USDM

| REQ ID | SPEC ID | 対応 BDD Scenario |
|---|---|---|
| REQ-009 | SPEC-009-01 | rapid-crosscheck リランで作られた run を再度リラン元にできる(SPEC-009-01)(parent_run_id の数珠つなぎ) |
| REQ-009 | SPEC-009-03 | foreground の blue は拒否する(SPEC-009-03 / SPEC-009-04) / RUNNING の green は中止を促して拒否する(SPEC-009-03) / ABORTED の速報比較依頼は検証を通過する(SPEC-009-03) |
| REQ-009 | SPEC-009-04 | foreground の blue は拒否する(SPEC-009-03 / SPEC-009-04)(hint で正規ジョブ再実行を案内) |

## E2E 完了条件(BDD)

### 正常系

```gherkin
Feature: リラン対象を検証する

  Scenario: background で完了した green は検証を通過する
    Given facade/20260830T113000Z-JOB001-3f9a1c2e/execution-spec.json が存在し green の mode が background である
    And RAPID_CROSSCHECK_MODE=on で slot_executions に run_id=20260830T113000Z-JOB001-3f9a1c2e slot=green mode=background status=ABORTED がある
    When ジョブスケジューラが `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role green` を起動する
    Then 事前検証を通過し UC「元の execution-spec.json から復元して新しい run_id で起動する」へ進む
    And 実行ログ background-rerun.sh.log に `INFO precheck passed source_run_id=20260830T113000Z-JOB001-3f9a1c2e role=green mode=background status=ABORTED` が残る

  Scenario: ABORTED の速報比較依頼は検証を通過する(SPEC-009-03)
    Given RAPID_CROSSCHECK_MODE=on で rapid_crosscheck_requests に run_id=20260830T113000Z-JOB001-3f9a1c2e status=ABORTED がある
    When ジョブスケジューラが `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role rapid-crosscheck` を起動する
    Then 事前検証を通過し UC「速報比較依頼だけを新規作成する」へ進む
    And facade/20260830T113000Z-JOB001-3f9a1c2e/execution-spec.json は開かれない

  Scenario: rapid-crosscheck リランで作られた run を再度リラン元にできる(SPEC-009-01)
    Given RAPID_CROSSCHECK_MODE=on で run_id=20260830T130000Z-JOB001-a1b2c3d4 は `background-rerun.sh --role rapid-crosscheck` で作られた run であり、facade/20260830T130000Z-JOB001-a1b2c3d4/execution-spec.json は存在しない
    And rapid_crosscheck_requests に run_id=20260830T130000Z-JOB001-a1b2c3d4 status=FAILED があり、parallel_runs の同 run_id の parent_run_id が 20260830T113000Z-JOB001-3f9a1c2e である
    When ジョブスケジューラが `background-rerun.sh --source-run-id 20260830T130000Z-JOB001-a1b2c3d4 --role rapid-crosscheck` を起動する
    Then 事前検証を通過し UC「速報比較依頼だけを新規作成する」へ進む(新 run の parent_run_id は 20260830T130000Z-JOB001-a1b2c3d4 になる)
    And stderr に `execution-spec not found` は出ない

  Scenario: RAPID_CROSSCHECK_MODE=off でも exitcode.txt から元状態を導出して通過する
    Given RAPID_CROSSCHECK_MODE=off で facade/20260830T113000Z-JOB001-3f9a1c2e/execution-spec.json の green の mode が background、facade/20260830T113000Z-JOB001-3f9a1c2e/green/started-at.txt が存在し exitcode.txt の中身が 6 である
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role green` を起動する
    Then 元状態 FAILED として事前検証を通過する
```

### 異常系

```gherkin
  Scenario: foreground の blue は拒否する(SPEC-009-03 / SPEC-009-04)
    Given facade/20260830T113000Z-JOB001-3f9a1c2e/execution-spec.json の blue の mode が foreground で slot_executions に run_id=20260830T113000Z-JOB001-3f9a1c2e slot=blue mode=foreground status=SUCCEEDED がある
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role blue` を起動する
    Then 終了コード 3 で stderr に `error: source run is not rerunnable run_id=20260830T113000Z-JOB001-3f9a1c2e role=blue mode=foreground status=SUCCEEDED` と `hint: rerun the scheduler job instead (foreground slot / final crosscheck are not handled by background-rerun.sh)` が出る
    And 新しい run_id は発行されない

  Scenario: RUNNING の green は中止を促して拒否する(SPEC-009-03)
    Given facade/20260830T113000Z-JOB001-3f9a1c2e/execution-spec.json の green の mode が background で slot_executions に run_id=20260830T113000Z-JOB001-3f9a1c2e slot=green mode=background status=RUNNING がある
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role green` を起動する
    Then 終了コード 3 で stderr に `error: source run is not rerunnable run_id=20260830T113000Z-JOB001-3f9a1c2e role=green status=RUNNING` と `hint: abort the run with abort-green.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e before rerun` が出る

  Scenario: enum 外の role(final-crosscheck)は引数エラー
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role final-crosscheck` を起動する
    Then 終了コード 2 で stderr に `error: invalid value option=--role value=final-crosscheck` が出る(確報はジョブスケジューラの正規ジョブで再実行する)

  Scenario: 列挙外の role 文字列は引数エラー
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role foo` を起動する
    Then 終了コード 2 で stderr に `error: invalid value option=--role value=foo` が出る

  Scenario: 元の実行が見つからない(blue / green は execution-spec.json で特定する)
    Given facade/20260830T000000Z-JOB999-00000000/execution-spec.json が存在しない
    When `background-rerun.sh --source-run-id 20260830T000000Z-JOB999-00000000 --role green` を起動する
    Then 終了コード 3 で stderr に `error: execution-spec not found run_id=20260830T000000Z-JOB999-00000000 path: /var/relay-gate/facade/20260830T000000Z-JOB999-00000000/execution-spec.json` が出る

  Scenario: 元の速報比較依頼が見つからない(rapid-crosscheck は依頼レコードで特定する)
    Given RAPID_CROSSCHECK_MODE=on で rapid_crosscheck_requests に run_id=20260830T000000Z-JOB999-00000000 の行が無い
    When `background-rerun.sh --source-run-id 20260830T000000Z-JOB999-00000000 --role rapid-crosscheck` を起動する
    Then 終了コード 3 で stderr に `error: source request not found run_id=20260830T000000Z-JOB999-00000000 role=rapid-crosscheck` と `hint: rapid crosscheck request is created only when both slots succeeded` が出る
    And facade/20260830T000000Z-JOB999-00000000/execution-spec.json は開かれない

  Scenario: RAPID_CROSSCHECK_MODE=off で started-at.txt が無い元 run は未起動として拒否する
    Given RAPID_CROSSCHECK_MODE=off で facade/20260830T113000Z-JOB001-3f9a1c2e/execution-spec.json の green の mode が background、facade/20260830T113000Z-JOB001-3f9a1c2e/green/started-at.txt が存在しない
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role green` を起動する
    Then 終了コード 3 で stderr に `error: source run is not rerunnable run_id=20260830T113000Z-JOB001-3f9a1c2e role=green mode=background status=-` と `hint: source run has not started; rerun the scheduler job instead` が出る

  Scenario: RUNNING の速報比較依頼は拒否する
    Given rapid_crosscheck_requests に run_id=20260830T113000Z-JOB001-3f9a1c2e status=RUNNING がある
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role rapid-crosscheck` を起動する
    Then 終了コード 3 で stderr に `error: source request is not rerunnable run_id=20260830T113000Z-JOB001-3f9a1c2e role=rapid-crosscheck status=RUNNING` と `hint: abort the request with abort-rapid-crosscheck.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e before rerun` が出る

  Scenario: RAPID_CROSSCHECK_MODE=off の rapid-crosscheck は管理 DB 無しとして拒否する
    Given RAPID_CROSSCHECK_MODE=off である
    When `background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role rapid-crosscheck` を起動する
    Then 終了コード 3 で stderr に `error: management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=20260830T113000Z-JOB001-3f9a1c2e role=rapid-crosscheck` が出て、管理 DB への接続は行われない
```

## ティア別仕様

- [tier-ops](tier-ops.md)(`background-rerun.sh` の事前検証表)

### 統合契約

- [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml)
- [AsyncAPI Spec](../../../_cross-cutting/api/asyncapi.yaml)(この UC は publish / subscribe しない)
