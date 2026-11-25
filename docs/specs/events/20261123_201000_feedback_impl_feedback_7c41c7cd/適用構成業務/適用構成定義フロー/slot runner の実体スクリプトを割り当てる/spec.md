# slot runner の実体スクリプトを割り当てる

## 概要

基盤適用設計者が、blue / green slot に現行実装・新実装・次世代実装の起動方式・ホスト・OS・プロトコルを閉じ込めた runner 実体スクリプトを `BLUE_RUNNER` / `GREEN_RUNNER` で割り当てる。runner 実体は relay-gate が定める **runner IF**(引数)と **Runner Result Contract**(成果物)に従う。runner の差し替えだけで、facade と比較規約を変更せずに異なる世代の実装を並行稼働できる。

relay-gate は、そのまま割り当てられる **標準の slot runner** `runners/standard-runner.sh` を正式に提供する(利用者決定 2026-11-16。正本は CLI 契約 commands「$BLUE_RUNNER / $GREEN_RUNNER」の `standard_runner`)。

| 割り当てる実体 | 使う場合 | 利用者が用意するもの |
|---|---|---|
| 標準の slot runner(実体は 1 つ。blue と green の両方に同じファイルを割り当てる) | ローカル実行と SSH 実行で足りる slot | feature flag と slot ジョブマップ(と実行先の実装)だけ。runner のスクリプトは書かない |
| 自作の runner | 標準の slot runner が扱わない起動方式・プロトコル(特殊な接続)の slot | 上記に加えて、runner IF を満たす runner(共通ライブラリ `lib/runner-*.sh` を `source` して使える) |

## データフロー

```mermaid
graph LR
  STD["relay-gate の提供物\n標準の slot runner\n(ローカル実行と SSH 実行)"]
  IMPL["基盤適用設計者\n自作の runner の作成\n(特殊な接続の場合だけ)"]
  EDIT["基盤適用設計者\nfeature-flag.env の BLUE_RUNNER / GREEN_RUNNER 編集\n(両方に標準の slot runner を書く)"]
  subgraph FACADE["tier-facade"]
    P["presentation\nValidateConfigRequest(--feature-flag)"]
    U["usecase\nValidateRunnerAssignmentQuery"]
    D["domain\nSlotRunnerAssignment(slot, runner_script_path, job_map_location)\nRunnerInterfaceContract"]
    R["repository\nFeatureFlagConfig / JobMapRepository(所在確認)"]
    P -->|"引数"| U
    U -->|"function 呼び出し"| R
    R -->|"function 呼び出し"| D
  end
  subgraph FS["FS(設定ファイル / runner 実体)"]
    CFG[("feature-flag.env\nBLUE_RUNNER / GREEN_RUNNER")]
    RUN[("RELAY_GATE_HOME/runners/standard-runner.sh\n(1 つの実体を blue と green の両方に割り当てる)")]
    CUSTOM[("自作の runner\n(特殊な接続の slot だけ)")]
    MAP[("slot ジョブマップ\n(既定は blue-job-map.csv / green-job-map.csv)")]
  end
  STD -->|"配置済み"| RUN
  IMPL -.->|"ファイル書き込み(特殊な接続の場合だけ)"| CUSTOM
  R -.->|"存在確認(割り当てた場合)"| CUSTOM
  EDIT -->|"ファイル書き込み"| CFG
  R -->|"ファイル読み込み"| CFG
  R -->|"存在確認"| RUN
  R -->|"存在確認"| MAP
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| presentation | ValidateConfigRequest | `--feature-flag` の検証(UC「feature flag を設定する」と同じ入口)。runner 割当の検証項目は本 UC が追加する |
| usecase | ValidateRunnerAssignmentQuery | runner パスの解決(相対パスは設定ファイルのあるディレクトリが基準。CLI 契約 `config_files.feature-flag.env.runner_path_resolution`)と存在・実行権限、対応するジョブマップの所在(場所は CLI 契約 `config_files.feature-flag.env.job_map_location`)、runner IF への応答(`--help` で契約バージョンを返す。仮採用。問い合わせの待機上限・実行順・未応答判定は契約 `validate-config.sh` の `runner_help_probe`)を確認 |
| domain | SlotRunnerAssignment / RunnerInterfaceContract | slot → runner_script_path → job_map_location の対応。runner IF の契約定義 |
| repository | FeatureFlagConfig / JobMapRepository | env 読み込み、slot ジョブマップの存在確認(feature-flag.env の `BLUE_JOB_MAP_CSV` / `GREEN_JOB_MAP_CSV` で決めた場所。無い・空なら `$RELAY_GATE_CONFIG_DIR/<slot>-job-map.csv`) |
| 標準の slot runner | runners/standard-runner.sh | relay-gate が提供する runner 実体。runner IF をすべて満たし、slot ジョブマップの行に従ってローカル実行と SSH 実行を扱う。slot は `--role` で受け取るため、1 つの実体を blue と green の両方に割り当てる |
| 共通ライブラリ | lib/runner-*.sh | 標準の slot runner と自作の runner が `source` する relay-gate 提供の関数群(ジョブマップ解決・execution-spec 保存・3 ファイル公開・完了通知)。標準の slot runner が扱わない起動方式・プロトコルは、自作の runner 側に置く |

## 処理フロー

```mermaid
sequenceDiagram
  actor Designer as 基盤適用設計者
  box rgb(240,255,240) tier-facade
    participant Pres as presentation(validate-config.sh)
    participant UC as usecase
    participant Dom as domain
    participant Repo as repository
  end
  participant FS as FS(設定 / runner 実体)

  Designer->>FS: feature-flag.env の BLUE_RUNNER と GREEN_RUNNER に /opt/relay-gate/runners/standard-runner.sh を書く(標準の slot runner。runner は作らない)
  opt 標準の slot runner が扱わない接続の slot がある
    Designer->>FS: 自作の runner を作成(lib/runner-*.sh を source し、実装固有の接続方法を書く)し、その slot の RUNNER に書く
  end
  Designer->>Pres: validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env
  Pres->>UC: 検証
  UC->>Repo: BLUE_RUNNER / GREEN_RUNNER を読む
  Repo->>FS: env
  loop mode≠off の slot ごと
    UC->>Dom: SlotRunnerAssignment を構築
    UC->>Repo: runner 実体のパスを解決(相対パスは設定ファイルのあるディレクトリが基準)し、存在・実行権限を確認
    Repo->>FS: test -x
    alt 実装固有事項の runner への閉じ込め: runner IF に応答する
      UC->>FS: <runner> --help(契約バージョン確認。実行順・待機上限は契約 runner_help_probe)
      FS-->>UC: "usage: ... runner-if-version=1"
    else 応答しない(判定基準は契約 runner_help_probe.no_response_criteria)
      UC->>FS: 上限到達時は runner のプロセスグループを停止
      UC-->>Pres: warn: runner does not respond to --help
    else 問い合わせの準備に失敗
      UC-->>Pres: error: runner probe failed(終了コード 6 で即時終了)
    end
    UC->>Repo: 対応するジョブマップの所在(場所は feature-flag.env の任意の 2 キーで決める。無い・空なら <slot>-job-map.csv)
    Repo->>FS: test -r
  end
  alt 違反なし
    Pres-->>Designer: stdout に blue_runner / green_runner / blue_job_map / green_job_map、終了コード 0
  else 違反あり
    Pres-->>Designer: stderr error:、終了コード 2
  end
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| 実装スロット | blue | `BLUE_RUNNER` に現行実装(または前世代)を起動する runner を割り当てる(標準の slot runner、または自作の runner) | tier-facade | domain `SlotRunnerAssignment` |
| 実装スロット | green | `GREEN_RUNNER` に新実装(または次世代)を起動する runner を割り当てる(標準の slot runner、または自作の runner。blue と同じ実体でよい) | tier-facade | domain `SlotRunnerAssignment` |
| 設定所有区分 | feature flag | runner の割当を所有 | tier-facade | repository `feature_flag_config` |
| 設定所有区分 | 適用文書 | runner 実体の所在・ホスト配置・実行ユーザー方針を記述(relay-gate は読まない) | — | — |
| 運用モード | 並行稼働 / 新実装の単独本番 / 次世代実装との並行稼働 | 世代交代時は green に次世代実装を起動する runner を、blue に旧 green を起動する runner を割り当てる(自作の runner は差し替える。両 slot とも標準の slot runner なら割当は同じファイルのままで、slot ジョブマップと実装版を入れ替える。どちらも facade は変更しない) | tier-facade | feature-flag.env |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| 実装固有事項の runner への閉じ込め | runner 実体は runner IF を受け、Runner Result Contract を出力する。SSH の接続方法・OS 差異・プロトコルは runner 実体内に閉じる。ローカル実行と SSH 実行は relay-gate が提供する標準の slot runner が扱い、それ以外の起動方式・プロトコルは利用者が自作した runner に閉じる。facade / 速報 / 確報 / 監視 / 復旧のスクリプトは runner の差し替えで変更せず、割り当てられた実体が標準か自作かを区別しない。検証では runner IF(`--help` の応答)を確認する(仮採用) | tier-facade | domain `RunnerInterfaceContract` / usecase `validate_runner_assignment` | 標準の slot runner を blue と green の両方に割り当てた設定を検証する(SPEC-001-04) / runner 実体を差し替えても facade は変更不要である(SPEC-001-04) |
| facade の責務限定 | facade は `$BLUE_RUNNER` / `$GREEN_RUNNER` を runner IF で起動するだけ。実装固有の起動方式を判断しない | tier-facade | gateway `runner_process_adapter` | runner 実体を差し替えても facade は変更不要である |
| 設定所有区分 | runner の割当と、対応するジョブマップの場所は feature flag が所有。runner 実体の所在は適用文書が記述(標準の slot runner の所在は relay-gate の配置ディレクトリ配下で決まっている) | tier-facade | repository `feature_flag_config` | runner 割当を検証する |

## 計算ルール一覧

| 計算名 | 入力情報 | 計算式/ロジック | 出力情報 | 適用 tier |
|--------|---------|---------------|---------|----------|
| ジョブマップ所在 | slot、feature-flag.env の BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV | キーに書いた場所(相対パスは設定ファイルのあるディレクトリが基準)。キーが無い・値が空なら `$RELAY_GATE_CONFIG_DIR/<slot>-job-map.csv`。これは要約で、正本は CLI 契約 `config_files.feature-flag.env.job_map_location`(検証の詳細は UC「feature flag を設定する」) | job_map_location | tier-facade |
| 標準の slot runner の所在 | relay-gate の配置ディレクトリ | `$RELAY_GATE_HOME/runners/standard-runner.sh`(/opt/relay-gate に配置した場合は `/opt/relay-gate/runners/standard-runner.sh`)。正本は CLI 契約 commands「$BLUE_RUNNER / $GREEN_RUNNER」の `standard_runner` | BLUE_RUNNER / GREEN_RUNNER に書く値 | tier-facade |

## 状態遷移一覧

| 状態モデル | 遷移元 | 遷移先 | トリガー | 事前条件 | 事後処理 | 適用 tier |
|-----------|--------|--------|---------|---------|---------|----------|
| 該当なし | — | — | 設定 UC。状態を遷移させない | — | — | — |

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | 適用構成業務 | この UC が属する業務 |
| BUC | 適用構成定義フロー | この UC を含む BUC |
| アクター | 基盤適用設計者 | 提供者 |
| 情報 | slot runner 割当 | 定義対象。属性: slot / runner 実体スクリプトパス(標準の slot runner、または自作の runner)/ 対応するジョブマップの所在 |
| 情報 | feature flag 設定 | BLUE_RUNNER / GREEN_RUNNER の所有元。runner が完了通知を送る先(RAPID_CROSSCHECK_RUNNER)、自 slot の実装版(BLUE_IMPL / GREEN_IMPL)、自 slot のジョブマップの場所(BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV。任意)も同じ feature flag が所有し、facade が runner へ環境変数で渡す |
| 情報 | 適用構成文書 | 属性: 案件識別 / 外部 IF の送受信方針 / ネットワーク制約 / ホスト配置 / 実行ユーザー方針 / DB セグメント構成 / runner 実体の所在 / 文書版。本 UC は「runner 実体の所在」「ホスト配置」を割当の根拠とし、runner が接続する管理 DB・業務 DB の接続設定の根拠として「DB セグメント構成」を参照する。「文書版」は適用構成文書側で版管理し、relay-gate は読み込まない |
| 条件 | 実装固有事項の runner への閉じ込め / facade の責務限定 / 設定所有区分 | 分岐条件一覧を参照 |
| 画面 | slot runner 割当検証出力(→ CLI 出力) | validate-config.sh の stdout / stderr / 終了コード |
| イベント | 現行実装 runner の割当 / 新実装 runner の割当 | 割当 |
| 外部システム | 現行実装(blue) / 新実装(green) | runner が起動する実装 |

## 関連 USDM

| REQ ID | SPEC ID | 対応 BDD Scenario |
|---|---|---|
| REQ-001 | SPEC-001-04 | runner 割当を検証する(SPEC-001-04) / 標準の slot runner を blue と green の両方に割り当てた設定を検証する(SPEC-001-04) / runner 実体を差し替えても facade は変更不要である(SPEC-001-04) ※ 割当と検証の側。AC「標準の slot runner がローカル実行の行・SSH 実行の行を解決して実行する」の実行側は UC〈ジョブマップで JOB_ID から実行先を解決する〉〈実装スクリプトを実行して Runner Result を出力する〉で覆う。AC「提供物の一覧で、標準の slot runner は正式な提供物として載っており、参考実装(仮採用)という扱いの runner は無い」は提供物の記載を問う条件で、CLI 契約 commands「$BLUE_RUNNER / $GREEN_RUNNER」の `standard_runner` と照合し、配置ディレクトリの中身は tier-facade.md のティア完了条件「配置ディレクトリの runners には標準の slot runner があり ssh-runner_sh は無い」で判定する |
| REQ-002 | SPEC-002-03 | facade は設定された runner を runner IF で起動するだけである(SPEC-002-03) / runner 実体を差し替えても facade は変更不要である(SPEC-001-04) ※ 受け入れ条件「facade は JOB_ID を runner に渡し、runner がジョブマップで解決する」に直接対応するのは 1 件目。2 件目は差し替え側の補強 |
| REQ-013 | SPEC-013-01 | 標準の slot runner を blue と green の両方に割り当てた設定を検証する(SPEC-001-04) / runner 実体を差し替えても facade は変更不要である(SPEC-001-04) ※ 1 件目は「標準の slot runner を割り当てる適用では runner を書かない」側、2 件目は「自作の runner を割り当てても relay-gate のスクリプトは変更不要」側 |

> 機械可読の正本は `spec-event.yaml` の `use_cases[].usdm`(本表と同内容)。「対応 BDD Scenario」列は本 UC の `Scenario:` 名(接尾の SPEC ID を含む完全名)を「 / 」で区切って列挙し、Scenario 名以外の補足は「※」以降に置く。区切りは人が読む用で、Scenario 名自体に「 / 」を含むものがあるため機械分割には使わず、機械照合は `spec-event.yaml` の `scenarios[]` を使う。

## E2E 完了条件(BDD)

### 正常系

```gherkin
Feature: slot runner の実体スクリプトを割り当てる

  Scenario: runner 割当を検証する(SPEC-001-04)
    Given /opt/relay-gate/runners/blue-runner.sh と /opt/relay-gate/runners/green-runner.sh が実行可能で、--help に "runner-if-version=1" を返す
    And /etc/relay-gate/blue-job-map.csv と green-job-map.csv が存在する
    And feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh がある
    When 基盤適用設計者が validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 0 で stdout に "blue_runner: /opt/relay-gate/runners/blue-runner.sh" "green_runner: /opt/relay-gate/runners/green-runner.sh" "blue_job_map: /etc/relay-gate/blue-job-map.csv" "green_job_map: /etc/relay-gate/green-job-map.csv" が出る

  Scenario: 標準の slot runner を blue と green の両方に割り当てた設定を検証する(SPEC-001-04)
    Given relay-gate を /opt/relay-gate に配置してあり、relay-gate が提供する標準の slot runner /opt/relay-gate/runners/standard-runner.sh は実行可能である
    And /etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=/opt/relay-gate/runners/standard-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/standard-runner.sh がある
    And /etc/relay-gate/blue-job-map.csv と /etc/relay-gate/green-job-map.csv が存在する(基盤適用設計者が用意したのは feature-flag.env と 2 つの slot ジョブマップだけで、runner のスクリプトは書いていない)
    When 基盤適用設計者が RELAY_GATE_CONFIG_DIR=/etc/relay-gate で validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 0 で stderr に "error:" で始まる行も "warn:" で始まる行も出ない
    And stdout に "blue_runner: /opt/relay-gate/runners/standard-runner.sh" "green_runner: /opt/relay-gate/runners/standard-runner.sh"(同じパス)と "blue_runner_if_version=1" "green_runner_if_version=1" が出る

  Scenario: 設定ファイルと同じディレクトリに置いた runner を相対パスで割り当てる
    Given /etc/relay-gate/blue-runner.sh と /etc/relay-gate/green-runner.sh が実行可能で、--help に "runner-if-version=1" を返す
    And /etc/relay-gate/blue-job-map.csv と green-job-map.csv が存在する
    And /etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 RAPID_CROSSCHECK_MODE=off BLUE_RUNNER=./blue-runner.sh GREEN_RUNNER=./green-runner.sh がある
    When 基盤適用設計者が作業ディレクトリ /tmp で validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する
    Then 終了コード 0 で stdout に "blue_runner: /etc/relay-gate/./blue-runner.sh" "green_runner: /etc/relay-gate/./green-runner.sh" "blue_runner_if_version=1" "green_runner_if_version=1" が出る

  Scenario: runner 実体を差し替えても facade は変更不要である(SPEC-001-04)
    Given 並行稼働モードで green runner が新実装 green-1.x 用である
    And 次世代実装は標準の slot runner が扱わない接続で動くため、次世代実装用の自作の runner /opt/relay-gate/runners/green-next-runner.sh を作成し、runner IF と Runner Result Contract に従う
    When feature-flag.env の GREEN_RUNNER を /opt/relay-gate/runners/green-next-runner.sh に変更し validate-config.sh が終了コード 0 を返した後、ジョブスケジューラが facade.sh JOB001 を実行する
    Then facade.sh・速報クロスチェック runner(RAPID_CROSSCHECK_RUNNER の実体)・速報クロスチェック worker(RAPID_CROSSCHECK_WORKER の実体)・hang-detector.sh・background-rerun.sh・abort-green.sh・標準の slot runner(runners/standard-runner.sh)・共通ライブラリ(lib/runner-*.sh)のファイルは変更されていない
    And green/ に Runner Result の 3 ファイルが揃う

  Scenario: facade は設定された runner を runner IF で起動するだけである(SPEC-002-03)
    Given feature-flag.env に BLUE_MODE=foreground BLUE_IMPL=blue-2.3.1 BLUE_RUNNER=<Runner Result 3 ファイルを書くスタブ runner> GREEN_MODE=background GREEN_IMPL=green-1.4.0 RAPID_CROSSCHECK_MODE=off がある
    And GREEN_RUNNER に起動引数と環境変数を記録するスタブ runner を割り当てた
    And 両スタブは --help で "runner-if-version=1" を返し、両 slot のジョブマップに JOB001 の行がある
    When ジョブスケジューラが facade.sh JOB001 x y を実行する
    Then スタブは "--run-id <run_id> --job-id JOB001 --role green --mode background -- x y" で起動され、facade は実装固有の引数を追加していない
    And スタブの環境変数に GREEN_IMPL=green-1.4.0 があり、RAPID_CROSSCHECK_RUNNER は渡されていない(RAPID_CROSSCHECK_MODE=off)
```

### 異常系

```gherkin
  Scenario: runner 実体が存在しない割当は拒否される
    Given feature-flag.env に GREEN_MODE=background GREEN_RUNNER=/opt/relay-gate/runners/missing.sh がある
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 2 で stderr に "error: file not executable key=GREEN_RUNNER path=/opt/relay-gate/runners/missing.sh" が出る

  Scenario: 対応するジョブマップが無い割当は拒否される
    Given feature-flag.env に GREEN_MODE=background GREEN_RUNNER=<実行可能> があり /etc/relay-gate/green-job-map.csv が無い
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 2 で stderr に "error: job map not found slot=green map=/etc/relay-gate/green-job-map.csv" が出る

  Scenario: runner IF に応答しない実体は警告される
    Given GREEN_RUNNER が --help に "runner-if-version=" を含まない実行可能ファイルである
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 0 で stderr に "warn: runner does not respond to --help slot=green runner=<path>" が出る
    And stdout の green_runner_if_version は "-" である

  Scenario: --help に応答しない runner の問い合わせは待機上限で打ち切られ 10 秒以内に復帰する
    Given BLUE_RUNNER と GREEN_RUNNER が --help を受けると応答せずに 30 秒間終了しない実行可能ファイルである
    And feature-flag.env は BLUE_MODE=foreground GREEN_MODE=background の並行稼働の組合せで、runner 以外の検証はすべて通過する
    When validate-config.sh --feature-flag を実行する
    Then 終了コード 0 で、起動から終了までの経過時間は 10 秒以内である(契約 runner_help_probe.response_time_budget の問い合わせの上限 9.2 秒に、数行の設定の検査の時間を加えた、この入力での確認)
    And stderr に "warn: runner does not respond to --help slot=blue runner=<path>" と "warn: runner does not respond to --help slot=green runner=<path>" の両方が出る
    And stdout の blue_runner_if_version と green_runner_if_version は "-" で、終了時点で runner のプロセスは残っていない
```

> 本 UC の Scenario が判定するのは、割当と検証(`validate-config.sh --feature-flag` の出力、facade が runner IF だけで起動すること)である。標準の slot runner がローカル実行の行・SSH 実行の行を解決して実行する場面は、UC「ジョブマップで JOB_ID から実行先を解決する」「実装スクリプトを実行して Runner Result を出力する」で判定する。

## ティア別仕様

- [facade / slot runner ティア](tier-facade.md)

### 統合契約

- [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml)(runner IF を defines、`validate-config.sh --feature-flag` を uses。標準の slot runner は commands「$BLUE_RUNNER / $GREEN_RUNNER」の `standard_runner`、ジョブマップの場所は `config_files.feature-flag.env.job_map_location`)
- [AsyncAPI Spec](../../../_cross-cutting/api/asyncapi.yaml)(runner 実体が publish する `slot-completed` は UC「速報クロスチェック runner へ完了通知を送信する」)
- 関連: [feature flag を設定する](../feature%20flag%20を設定する/spec.md) / [実装スクリプトを実行して Runner Result を出力する](../../../実装切替業務/実装切替ジョブ実行フロー/実装スクリプトを実行して%20Runner%20Result%20を出力する/spec.md)
