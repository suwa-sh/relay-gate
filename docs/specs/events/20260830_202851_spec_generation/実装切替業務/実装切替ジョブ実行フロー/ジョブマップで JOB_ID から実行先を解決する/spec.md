# ジョブマップで JOB_ID から実行先を解決する

## 概要

slot runner(`$BLUE_RUNNER` / `$GREEN_RUNNER`)が、自 slot のジョブマップ(TSV)から JOB_ID に対応するホスト・実行ユーザー・スクリプト・作業ディレクトリ・固定引数(JSON 配列)・hang_detect_limit_minutes・認証情報参照名・マップ版・実装版を解決する。固定引数の後ろに facade から渡された PARAM... を順序を変えずに連結する。ジョブマップに JOB_ID の行が無い場合も Runner Result の 3 ファイルを可能な限り出力して非 0 で終了する。

## データフロー

```mermaid
graph LR
  subgraph FACADE["tier-facade"]
    P["presentation\nRunnerInvocation(--run-id --job-id --role --mode -- PARAM...)"]
    U["usecase\nResolveExecutionTargetQuery"]
    D["domain\nExecutionTarget\nArgumentList(固定引数 + PARAM)"]
    R["repository\nJobMapRepository(slot ジョブマップ TSV)"]
    G["gateway\nFilesystemAdapter(stderr.log / exitcode.txt 出力)"]
    P -->|"引数"| U
    U -->|"function 呼び出し"| R
    R -->|"function 呼び出し"| D
    U -->|"function 呼び出し"| D
    U -->|"失敗時"| G
  end
  subgraph FS["FS(設定ファイル / 成果物ディレクトリ)"]
    MAP[("slot ジョブマップ TSV\njob_id host exec_user script_path work_dir fixed_args_json hang_detect_limit_minutes credential_ref map_version impl_version")]
    ART[("facade/run_id/role/\nstderr.log exitcode.txt(未定義時)")]
  end
  R -->|"ファイル読み込み"| MAP
  G -->|"ファイル書き込み(一時 → mv)"| ART
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| presentation | RunnerInvocation | runner IF の引数検証(`--run-id` / `--job-id` / `--role` / `--mode` 必須、`--` 以降を PARAM 列に保持) |
| usecase | ResolveExecutionTargetQuery | ジョブマップ読み込み → 行検索 → 引数連結 → ExecutionTarget を返す。未定義なら Runner Result 3 ファイルを揃えて非 0 終了 |
| domain | ExecutionTarget / ArgumentList | TSV 1 行 → 実行先。`fixed_args_json`(JSON 配列)を要素単位に展開し、PARAM... を末尾に順序保持で連結する純粋関数 |
| repository | JobMapRepository | `$RELAY_GATE_CONFIG_DIR/<slot>-job-map.tsv` をヘッダー行付き TSV として読む。job_id 完全一致で 1 行を返す |
| gateway | FilesystemAdapter | 未定義時の `stderr.log`(原因)/ `stdout.log`(空)/ `exitcode.txt`(`2`)の一時ファイル書き込みと `mv` |

## 処理フロー

```mermaid
sequenceDiagram
  actor Sched as ジョブスケジューラ(facade 経由)
  box rgb(240,255,240) tier-facade
    participant Pres as presentation(runner CLI)
    participant UC as usecase
    participant Dom as domain
    participant Repo as repository
    participant GW as gateway
  end
  participant FS as FS(ジョブマップ / 成果物)

  Sched->>Pres: <runner> --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background -- 20260830 full
  Pres->>Pres: 引数検証
  Pres->>UC: ResolveExecutionTargetQuery(JOB001, green, [20260830, full])
  UC->>Repo: green のジョブマップから JOB001 を探す
  Repo->>FS: green-job-map.tsv を読む
  FS-->>Repo: ヘッダー + 行
  alt ジョブマップ解決条件: job_id=JOB001 の行がある
    Repo->>Dom: 行 → ExecutionTarget
    Dom-->>UC: host / exec_user / script_path / work_dir / fixed_args / hang_detect_limit_minutes / credential_ref / map_version / impl_version
    UC->>Dom: 引数連結規則: fixed_args + PARAM
    Dom-->>UC: ArgumentList(["p1","p2 p3","20260830","full"])
    UC-->>Pres: ExecutionTarget(次 UC「execution-spec.json を確定保存する」へ)
  else 行が無い
    UC->>GW: stderr.log に原因、stdout.log 空、exitcode.txt=2 を書く
    GW->>FS: 一時ファイル → mv
    UC-->>Pres: 未定義エラー
    Pres-->>Sched: 終了コード 2(exitcode.txt と一致)
  end
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| 実装スロット | blue | `$RELAY_GATE_CONFIG_DIR/blue-job-map.tsv` を読む | tier-facade | repository `job_map_repo` |
| 実装スロット | green | `$RELAY_GATE_CONFIG_DIR/green-job-map.tsv` を読む | tier-facade | repository `job_map_repo` |
| 設定所有区分 | slot ジョブマップ | ホスト・実行ユーザー・スクリプト・作業ディレクトリ・固定引数・hang_detect_limit_minutes・認証情報参照名の正本 | tier-facade | repository `job_map_repo` |
| 設定所有区分 | feature flag | runner 実体と slot はこの UC では参照しない(facade が解決済み) | tier-facade | — |
| Runner Result 成果物種別 | stderr.log | 未定義時に `error: job_id=JOB001 not found in job map slot=green map=<path>` を書く | tier-facade | gateway `filesystem_adapter` |
| Runner Result 成果物種別 | exitcode.txt | 未定義時に `2` | tier-facade | gateway `filesystem_adapter` |
| Runner Result 成果物種別 | stdout.log | 未定義時に空ファイル | tier-facade | gateway `filesystem_adapter` |
| ハング検知上限設定 | 60 分(導入時既定) | 列 `hang_detect_limit_minutes` をそのまま解決結果に含める | tier-facade | domain `ExecutionTarget` |
| ハング検知上限設定 | 0(検知対象外) | foreground role 用。値の意味は監視側で解釈し、runner は変換しない | tier-facade | domain `ExecutionTarget` |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| ジョブマップ解決条件 | slot のジョブマップに `job_id` 列が JOB_ID と完全一致する行が 1 行あるときだけ解決できる。無ければ exitcode.txt=2 と原因を含む stderr.log を出力して終了。重複行は先頭行を採用し実行ログに WARN(仮採用: validate-config.sh が重複を拒否するため実行時は発生しない前提) | tier-facade | usecase `resolve_execution_target` / repository `job_map_repo` | ジョブマップ未定義でも 3 ファイルを揃えて非 0 終了する(SPEC-003-02) |
| 引数連結規則 | `fixed_args_json` を JSON 配列として要素ごとに 1 引数に展開し、その後ろに PARAM... を順序どおり追加する。要素内の空白・カンマは 1 引数のまま維持。`[]` なら PARAM... だけ | tier-facade | domain `build_argument_list` | 固定引数の後ろに PARAM を順序保持で連結する(SPEC-004-02) |
| 設定所有区分 | 実行先は slot ジョブマップからだけ読む。feature flag・ジョブスケジューラのジョブ定義・runner 引数からは読まない | tier-facade | repository `job_map_repo` | ジョブマップの行から実行先を解決する(SPEC-004-01) |
| Runner Result 完備条件 | 解決失敗でも `stdout.log` / `stderr.log` / `exitcode.txt` を揃える。exitcode.txt は runner の終了コードと一致 | tier-facade | gateway `filesystem_adapter` | ジョブマップ未定義でも 3 ファイルを揃えて非 0 終了する(SPEC-003-02) |

## 計算ルール一覧

| 計算名 | 入力情報 | 計算式/ロジック | 出力情報 | 適用 tier |
|--------|---------|---------------|---------|----------|
| 引数連結 | fixed_args_json(JSON 配列文字列)、PARAM... | `args = parse_json_array(fixed_args_json) ++ PARAM...`。JSON 文字列要素のエスケープ(`\"` `\\`)を解除して 1 要素 = 1 引数。bash では配列 `"${args[@]}"` として保持する | ArgumentList | tier-facade |
| ジョブマップパス | RELAY_GATE_CONFIG_DIR、slot | `$RELAY_GATE_CONFIG_DIR/<slot>-job-map.tsv`(仮採用) | map path | tier-facade |
| TSV 行の分解 | ヘッダー行、データ行 | ヘッダー列名で位置を決める(列順に依存しない)。タブ区切り、10 列 | ExecutionTarget | tier-facade |

## 状態遷移一覧

| 状態モデル | 遷移元 | 遷移先 | トリガー | 事前条件 | 事後処理 | 適用 tier |
|-----------|--------|--------|---------|---------|---------|----------|
| 該当なし | — | — | この UC は状態を遷移させない(未定義時の slot 実行 FAILED は UC「実装スクリプトを実行して Runner Result を出力する」の exitcode 判定に含める) | — | — | — |

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | 実装切替業務 | この UC が属する業務 |
| BUC | 実装切替ジョブ実行フロー | この UC を含む BUC |
| アクター | 運用者 | 受益者 |
| 情報 | ジョブ起動要求 | JOB_ID と PARAM... |
| 情報 | ジョブマップ | 解決元 |
| 情報 | ハング検知上限設定 | 解決結果に含める hang_detect_limit_minutes |
| 情報 | Runner Result | 未定義時の 3 ファイル |
| 条件 | ジョブマップ解決条件 / 引数連結規則 / 設定所有区分 / Runner Result 完備条件 | 分岐条件一覧を参照 |
| 画面 | slot runner ジョブマップ解決出力(→ CLI 出力) | stderr.log / exitcode.txt / 実行ログ |

## 関連 USDM

| REQ ID | SPEC ID | 対応 BDD Scenario |
|---|---|---|
| REQ-004 | SPEC-004-01 | ジョブマップの行から実行先を解決する |
| REQ-004 | SPEC-004-02 | 固定引数の後ろに PARAM を順序保持で連結する |
| REQ-003 | SPEC-003-02 | ジョブマップ未定義でも 3 ファイルを揃えて非 0 終了する |

## E2E 完了条件(BDD)

### 正常系

```gherkin
Feature: ジョブマップで JOB_ID から実行先を解決する

  Scenario: ジョブマップの行から実行先を解決する(SPEC-004-01)
    Given green-job-map.tsv に行 "JOB001	host-green-01	batch	/opt/app/bin/job001.sh	/var/app/work	[]	60	ssh-key-green	map-v3	green-1.4.0" がある
    When facade が green runner を --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する
    Then runner は host=host-green-01 exec_user=batch script_path=/opt/app/bin/job001.sh work_dir=/var/app/work hang_detect_limit_minutes=60 credential_ref=ssh-key-green map_version=map-v3 impl_version=green-1.4.0 を解決する
    And 実行ログに "job map resolved job_id=JOB001 slot=green host=host-green-01 map_version=map-v3" が出る

  Scenario: 固定引数の後ろに PARAM を順序保持で連結する(SPEC-004-02)
    Given blue-job-map.tsv の JOB001 行の fixed_args_json が ["p1","p2 p3"] である
    When facade が blue runner を --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --role blue --mode foreground -- a b で起動する
    Then 実装へ渡す引数は 4 個で、順に p1 / "p2 p3" / a / b である

  Scenario: 空の固定引数は PARAM だけを渡す
    Given blue-job-map.tsv の JOB002 行の fixed_args_json が [] である
    When facade が blue runner を --run-id 20260830T113000Z-JOB002-5c7d9e0f --job-id JOB002 --role blue --mode foreground -- 20260830 で起動する
    Then 実装へ渡す引数は 1 個で 20260830 である
```

### 異常系

```gherkin
  Scenario: ジョブマップ未定義でも 3 ファイルを揃えて非 0 終了する(SPEC-003-02)
    Given RELAY_GATE_CONFIG_DIR は /etc/relay-gate である
    And green-job-map.tsv に job_id=JOB999 の行が無い
    When facade が green runner を --run-id 20260830T113000Z-JOB999-a1b2c3d4 --job-id JOB999 --role green --mode background で起動する
    Then runner は終了コード 2 で終了する
    And facade/20260830T113000Z-JOB999-a1b2c3d4/green/ に stdout.log(空)・stderr.log・exitcode.txt が揃う
    And exitcode.txt の中身は "2" である
    And stderr.log に "error: job_id=JOB999 not found in job map slot=green map=/etc/relay-gate/green-job-map.tsv" が含まれる

  Scenario: ジョブマップファイルが無い場合も 3 ファイルを揃える
    Given RELAY_GATE_CONFIG_DIR は /etc/relay-gate である
    And /etc/relay-gate/green-job-map.tsv が存在しない
    When facade が green runner を --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する
    Then runner は終了コード 2 で終了し、exitcode.txt の中身は "2" である
    And stderr.log に "error: job map not found slot=green map=/etc/relay-gate/green-job-map.tsv" が含まれる

  Scenario: fixed_args_json が JSON 配列でない行は解決失敗にする
    Given green-job-map.tsv の JOB003 行の fixed_args_json が "p1,p2"(配列でない)である
    When facade が green runner を --run-id 20260830T113000Z-JOB003-6d8e0f1a --job-id JOB003 --role green --mode background で起動する
    Then runner は終了コード 2 で終了し、stderr.log に "error: fixed_args_json is not a json array job_id=JOB003 slot=green" が含まれる
```

## ティア別仕様

- [facade / slot runner ティア](tier-facade.md)

### 統合契約

- [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml)(runner IF を uses)
- [AsyncAPI Spec](../../../_cross-cutting/api/asyncapi.yaml)(この UC は publish / subscribe しない)
- 設定契約の正本: [slot ごとのジョブマップを定義する](../../../適用構成業務/適用構成定義フロー/slot%20ごとのジョブマップを定義する/tier-facade.md)
