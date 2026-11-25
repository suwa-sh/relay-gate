# slot runner の実体スクリプトを割り当てる - facade / slot runner ティア仕様

## 変更概要

runner 実体が守る **runner IF** と **Runner Result Contract** を契約として定義し、`validate-config.sh --feature-flag` に runner 割当の検証項目(実体の存在・実行権限・runner IF 応答・ジョブマップ所在。相対パスの runner は設定ファイルのあるディレクトリを基準に解決する)を追加する。relay-gate は、そのまま `BLUE_RUNNER` / `GREEN_RUNNER` に割り当てられる標準の slot runner `runners/standard-runner.sh`(ローカル実行と SSH 実行)と、共通ライブラリ `lib/runner-*.sh` を正式に提供する(利用者決定 2026-11-16)。標準の slot runner を使う適用では、利用者は runner を書かない。標準の slot runner が扱わない起動方式・プロトコル(特殊な接続)の slot だけ、利用者が runner IF を満たす runner を自作して割り当てる。

## 標準の slot runner

規則の正本は CLI 契約 commands「$BLUE_RUNNER / $GREEN_RUNNER」の `standard_runner` で、下表はその要約(実装は契約の節だけに従う)。

| 項目 | 内容 |
|---|---|
| ファイル名 | `runners/standard-runner.sh` |
| 置き場所 | relay-gate の配置ディレクトリ配下(`$RELAY_GATE_HOME/runners/standard-runner.sh`)。facade.sh と同じ実行ホストに、実行可能なファイルとして配置する |
| 実体の数 | 1 つ。blue と green の両方に同じファイルを割り当てる。slot は起動時の引数 `--role` で受け取る(runner IF は変えない)。blue 用と green 用の別ファイルは提供しない |
| 扱う範囲 | ローカル実行(slot ジョブマップの行の host と user が両方無い・両方空)と SSH 実行(それ以外の行)。それ以外の起動方式・プロトコルは扱わない |
| feature flag への書き方の例 | relay-gate を /opt/relay-gate に配置した場合: `BLUE_RUNNER=/opt/relay-gate/runners/standard-runner.sh` / `GREEN_RUNNER=/opt/relay-gate/runners/standard-runner.sh`(値は環境変数を展開しないため、配置ディレクトリの実際のパスを書く)。相対パスでも書ける(基準は設定ファイルのあるディレクトリ) |
| 利用者が用意するもの | feature-flag.env と slot ジョブマップ(と実行先の実装)だけ |
| 配置ディレクトリと共通ライブラリ | 配置ディレクトリ(RELAY_GATE_HOME)は、自身のあるディレクトリ(起動されたパスの字面の `runners/`)の 1 つ上とし、環境変数では受け取らない。共通ライブラリはその `lib/` から読む。facade.sh を介さない起動では、設定ファイル置き場・成果物ルート・ログの既定もこの配置ディレクトリから決まる(契約 `standard_runner.home`) |
| 割り当てるパス | 配置ディレクトリの `runners/standard-runner.sh` のパス(絶対パスでも、そのファイルを指す相対パスでもよい)。別の場所に置いたシンボリックリンクやコピーを割り当てる使い方は対象外(契約 `standard_runner.assignment_path`) |
| SSH 実行の起動形 | `ssh -n -o BatchMode=yes {user}@{host} ...`。付けるオプションはこの 2 つだけで、ポート・鍵・known_hosts などの接続の設定は runner のプロセスユーザーの SSH 設定に任せる(契約 `standard_runner.ssh_launch` と external_interfaces「SSH(実装スクリプトの実行)」) |
| credential_ref の扱い | slot ジョブマップの `credential_ref` は ssh の引数にも接続先の決定にも使わず、execution-spec.json の `slots.<role>.credential_ref` へ転記するだけ(契約 `standard_runner.credential_ref_usage`) |
| 自作の runner | 標準の slot runner が扱わない接続の slot に、利用者が自作して割り当てる。runner IF を満たせばよく、共通ライブラリを `source` して使える。slot ごとに別の実体を割り当ててよい(例: blue に標準の slot runner、green に自作の runner) |

- facade.sh / background-rerun.sh / validate-config.sh は、割り当てられた実体が標準の slot runner か自作の runner かを区別しない(同じ runner IF で検査・起動する)

## コマンド契約

### runner IF($BLUE_RUNNER / $GREEN_RUNNER が満たす契約)

- **書式**: `<runner> --run-id <run_id> --job-id <JOB_ID> --role blue|green --mode foreground|background [--execution-spec <path>] -- [PARAM...]`
- **アクセス権**: 内部呼び出し(facade.sh / background-rerun.sh)。起動 OS ユーザーは facade と同じ。SSH 先は runner 実体が決める

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| --run-id | string | Yes | なし | run_id(成果物ディレクトリ名) |
| --job-id | string | Yes | なし | JOB_ID |
| --role | enum(blue / green) | Yes | なし | 自 slot |
| --mode | enum(foreground / background) | Yes | なし | 実行モード |
| --execution-spec | path | No | なし | 復元起動。指定時はジョブマップを再解決しない |
| --help | boolean | No | false | 使い方と `runner-if-version=1` を stdout に出して終了コード 0(検証で使う。仮採用) |
| -- PARAM... | string[] | No | 0 個 | 追加引数 |

- **stdin**: なし
- **環境変数(受け取る)**: runner は feature-flag.env を読まない。facade.sh / background-rerun.sh が feature-flag.env を読み、次を環境変数で渡す(全 UC 共通)
  - 常に: `RELAY_GATE_CONFIG_DIR` / `RELAY_GATE_ARTIFACT_ROOT` / `RELAY_GATE_LOG_DIR` / `RAPID_CROSSCHECK_MODE`(foreground / background / off)
  - `RAPID_CROSSCHECK_MODE` が off 以外のとき: `RAPID_CROSSCHECK_RUNNER`(完了通知の送信先実体)
  - 通常起動(`--execution-spec` なし)のとき: 自 slot の `BLUE_IMPL` / `GREEN_IMPL`(runner が execution-spec.json の `slots.<role>.impl_version` に転記)。復元起動(`--execution-spec`)では impl_version を spec から読むため渡さない
  - 通常起動(`--execution-spec` なし)のとき: 自 slot のジョブマップの場所 `BLUE_JOB_MAP_CSV`(role=blue)/ `GREEN_JOB_MAP_CSV`(role=green)。facade.sh が feature-flag.env の同名の任意のキーから決めた場所で、キーが無い・値が空のときも既定の場所が渡る。runner は受け取った値をジョブマップのパスとしてそのまま使い(相対パスの解決も正規化もしない)、未設定・空のとき(facade.sh を介さない起動)は既定の場所 `$RELAY_GATE_CONFIG_DIR/<role>-job-map.csv` を使う。復元起動ではジョブマップを読まないため渡さない(background-rerun.sh は 2 キーを読まない)。正本は CLI 契約 `config_files.feature-flag.env.job_map_location`
  - 配置ディレクトリ(RELAY_GATE_HOME)は引き継ぎ対象にしない。runner が自身の所在から決める(標準の slot runner の決め方と共通ライブラリの所在は契約 `standard_runner.home`)。`RAPID_CROSSCHECK_MODE` が off 以外のとき runner は `$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` の `RAPID_DB_CONN_REF` を自分で読む(不在は exitcode.txt=2。UC「実装スクリプトを実行して Runner Result を出力する」)

#### runner 実体の責務(Runner Result Contract)

| 責務 | 内容 | 提供元 |
|---|---|---|
| ジョブマップ解決 | 自 slot のジョブマップ(場所は環境変数 `BLUE_JOB_MAP_CSV` / `GREEN_JOB_MAP_CSV` の値。未設定・空なら `$RELAY_GATE_CONFIG_DIR/<role>-job-map.csv`。CSV。列はヘッダー名で対応付け、host / user が両方空ならローカル実行)から JOB_ID を解決し引数を連結 | `lib/runner-resolve.sh`(UC「ジョブマップで JOB_ID から実行先を解決する」) |
| execution-spec 保存 | 一度きり保存。`slots.<role>.impl_version` は環境変数 `BLUE_IMPL` / `GREEN_IMPL`、`map_version` はジョブマップの任意列(無ければ `null`) | `lib/runner-spec.sh`(UC「execution-spec.json を確定保存する」) |
| 実装の実行 | 実行先で実装を起動し stdout / stderr / 終了コードを得る。**接続方法・OS・プロトコルはここに閉じる** | 標準の slot runner(`runners/standard-runner.sh`。SSH 実行の起動形は契約 `standard_runner.ssh_launch` の `ssh -n -o BatchMode=yes {user}@{host} ...`、host / user が空の行はローカル実行)。それ以外の起動方式・プロトコルは自作の runner(接続方法は自作の runner の中に閉じる) |
| Runner Result 公開 | started-at.txt を起動時、3 ファイルを終了後に一時 → mv で公開。exitcode.txt = 終了コード(slot 実行の状態は exitcode.txt / aborted.txt のファイル正本から導出する。aborted.txt の writer は abort-blue.sh / abort-green.sh) | `lib/runner-result.sh`(UC「実装スクリプトを実行して Runner Result を出力する」) |
| 完了通知 | `RAPID_CROSSCHECK_MODE` が off 以外(foreground / background)のとき `$RAPID_CROSSCHECK_RUNNER <role>-completed ...`(送信先は環境変数 `RAPID_CROSSCHECK_RUNNER` で解決。固定パス解決はしない)。送信失敗の扱いは条件「完了通知失敗の扱い」 | `lib/runner-notify.sh`(UC「速報クロスチェック runner へ完了通知を送信する」) |
| 終了コード | exitcode.txt と一致させる | 標準の slot runner / 自作の runner |

- 「提供元」列の `lib/runner-*.sh` は共通ライブラリである。標準の slot runner はこれを `source` して使う。自作の runner も `source` して使える(使うかどうかは自作の runner が決める。runner IF を満たせばよい)
- runner 実体(標準の slot runner と自作の runner のどちらも)が守らなければならない不変条件: (1) 3 ファイルを揃える、(2) exitcode.txt = 終了コード、(3) stdout / stderr(プロセス)に出さない、(4) 相手 slot の状態を判断しない、(5) 認証情報の値を成果物に書かない

### validate-config.sh --feature-flag(runner 割当の検証項目)

UC「feature flag を設定する」の契約に以下を追加する。

| 検証 | 違反時 stderr | 終了コード |
|---|---|---|
| runner が存在し実行可能(値は絶対パスでも相対パスでもよい。相対パスは設定ファイルのあるディレクトリを基準に解決し、解決後のパスで検査する。CLI 契約 `config_files.feature-flag.env.runner_path_resolution`) | `error: file not executable key=<SLOT>_RUNNER path=<解決後のパス>` | 2 |
| 対応するジョブマップが、決めた場所(feature-flag.env の `BLUE_JOB_MAP_CSV` / `GREEN_JOB_MAP_CSV` の値を解決したパス。キーが無い・値が空なら `$RELAY_GATE_CONFIG_DIR/<slot>-job-map.csv`。CLI 契約 `config_files.feature-flag.env.job_map_location`)に存在し読める(何も無い → 見つからない、あるが読めない・通常のファイルでない → 読めない。契約 `job_map_location.presence_report`) | 何も無い: `error: job map not found slot=<s> map=<決めた場所>` / あるが読めない・通常のファイルでない(ディレクトリなど): `error: config file is not readable path: <決めた場所>`(全コマンド共通の定型文。行の位置は同じ) | 2 |
| `<runner> --help` が `runner-if-version=1` を返す(問い合わせ規則は契約 `cli-command-contract.yaml` の `validate-config.sh` `runner_help_probe`: 1 slot あたりの待機上限・実行順・上限到達時の停止・「応答しない」の判定基準・版行の採用規則) | `warn: runner does not respond to --help slot=<s> runner=<p>`(「応答しない」の判定基準は契約 `runner_help_probe.no_response_criteria`)(拒否しない。stdout の `<slot>_runner_if_version` は `-`) | 0 |
| 問い合わせの準備(一時ファイルの作成・プロセスグループでの起動)が成功する | `error: runner probe failed slot=<s> reason=<r>`(runner の未応答とは区別する。契約 `runner_help_probe.preparation_failure`) | 6 |

- `<runner> --help` の `<runner>`、warn 行の `runner=<p>`、stdout の `blue_runner:` / `green_runner:` は、どれも解決後のパス。相対パスの runner に `error: path is not absolute` は出さない
- 検証は、割り当てられた実体が標準の slot runner か自作の runner かを区別しない。`BLUE_RUNNER` と `GREEN_RUNNER` に同じファイルを書いた設定(標準の slot runner)は、slot ごとに上表の検証と問い合わせを行う(同じ実体へ blue → green の順に 1 回ずつ問い合わせる)
- mode=off の slot は検証しない(ジョブマップの場所のキーも解決せず、所在も検査しない)。mode の値が列挙外・欠落・空の slot は「off でない」として扱い、上表の検証と runner への問い合わせを行う(CLI 契約 `config_files.feature-flag.env.validation_rules`)
- 上表の error 行と、UC「feature flag を設定する」の error 行が合わせて 2 行以上出るときの順は、CLI 契約 `config_files.feature-flag.env.error_order` に従う
- runner の応答待ちは、設定ファイルの検査の性能の目標値とは別に数える(CLI 契約 `runner_help_probe.response_time_budget`、`config_input_rules.performance_target`)

## 出力契約

- **stdout**(validate-config.sh。feature flag の出力に追記、固定順):
  ```text
  blue_job_map: /etc/relay-gate/blue-job-map.csv
  green_job_map: /etc/relay-gate/green-job-map.csv
  blue_runner_if_version=1
  green_runner_if_version=1
  ```
  (`blue_job_map` / `green_job_map` は決めた場所。例は feature-flag.env にジョブマップの場所のキーを書かない設定で、書いた設定では値を解決したパスが出る。off の slot の `<slot>_job_map` は `-`。off の slot、および `--help` の問い合わせで「応答しない」と判定した slot の `<slot>_runner_if_version` は `-`。標準の slot runner を両 slot に割り当てた設定では、`blue_runner:` と `green_runner:` に同じパスが出る)
- **stderr / 終了コード**: UC「feature flag を設定する」と同じ(0 / 2。`--help` 問い合わせの準備失敗だけ 6)

## UC ロジック

- **バリデーション**: 上表。`--help` 問い合わせの待機上限(秒)・実行順・上限到達時の停止・未応答の判定基準・準備失敗の扱いは契約 `validate-config.sh` の `runner_help_probe` に従う(値は契約だけが持つ)
- **確認プロンプト**: なし
- **冪等性**: 読み取り専用
- **エラーハンドリング**: 違反は全件収集して報告
- **クラッシュ耐性**: 副作用なし
- **世代交代の手順**(仮採用。適用文書に記述する内容の例): (1) 次世代実装を起動する runner を決める(標準の slot runner で足りれば作らない。特殊な接続なら自作する)→ (2) テスト環境で validate-config.sh → (3) runner が変わるなら `GREEN_RUNNER` を差し替え → (4) 必要なら `BLUE_RUNNER` に旧 green を起動する runner を割り当て → (5) feature flag で運用モードを切り替え。relay-gate のスクリプトは変更しない

## 設定契約

- feature flag の `BLUE_RUNNER` / `GREEN_RUNNER`(UC「feature flag を設定する」の契約)
- 標準の slot runner の割当: `BLUE_RUNNER` と `GREEN_RUNNER` の両方に `$RELAY_GATE_HOME/runners/standard-runner.sh` の実際のパスを書く(例: `BLUE_RUNNER=/opt/relay-gate/runners/standard-runner.sh` / `GREEN_RUNNER=/opt/relay-gate/runners/standard-runner.sh`。設定ファイルが /opt/relay-gate/config/feature-flag.env なら相対パス `../runners/standard-runner.sh` でも書ける)
- 自作の runner の配置: relay-gate 配置ディレクトリ配下の `runners/`(推奨。適用文書が所在を記述)。feature flag には絶対パスでも、設定ファイルのあるディレクトリからの相対パスでも書ける(例: 設定ファイルと同じディレクトリに置いて `BLUE_RUNNER=./blue-runner.sh`)
- 対応するジョブマップの場所: feature flag の任意のキー `BLUE_JOB_MAP_CSV` / `GREEN_JOB_MAP_CSV`。無い・空なら `$RELAY_GATE_CONFIG_DIR/<slot>-job-map.csv`(UC「feature flag を設定する」の契約と CLI 契約 `config_files.feature-flag.env.job_map_location`)
- 共通ライブラリ: relay-gate 配置ディレクトリ配下の `lib/runner-resolve.sh` / `runner-spec.sh` / `runner-result.sh` / `runner-notify.sh`(relay-gate が提供。標準の slot runner と自作の runner が `source`)

## データモデル変更

RDB テーブルは触らない(`tables: []`)。

### ファイル

| ファイル | 説明 | 変更種別 |
|---|---|---|
| `runners/standard-runner.sh` | 標準の slot runner(ローカル実行と SSH 実行。1 つの実体を blue と green の両方に割り当てる。relay-gate の正式な提供物) | 追加 |
| `lib/runner-*.sh` | 共通ライブラリ(標準の slot runner と自作の runner が `source` する) | 追加 |

## ビジネスルール

- 実装固有の起動方式・ホスト・OS・プロトコルは runner 実体に閉じ込め、facade は設定された runner を起動するだけ(条件: 実装固有事項の runner への閉じ込め / facade の責務限定)
- ローカル実行と SSH 実行で足りる slot には、relay-gate が提供する標準の slot runner をそのまま割り当てる(利用者は runner を書かない)。標準の slot runner が扱わない起動方式・プロトコルの slot だけ、利用者が runner を自作する(条件: 実装固有事項の runner への閉じ込め)
- runner の割当と、対応するジョブマップの場所は feature flag が所有(条件: 設定所有区分)

## ティア完了条件(BDD)

```gherkin
Feature: slot runner の実体スクリプトを割り当てる - facade / slot runner ティア

  Scenario: standard-runner_sh の --help は runner-if-version=1 を返す
    When `runners/standard-runner.sh --help` を実行する
    Then 終了コード 0 で stdout に "usage: " で始まる行と "runner-if-version=1" が出る

  Scenario: 配置ディレクトリの runners には標準の slot runner があり ssh-runner_sh は無い
    Given relay-gate を配置したディレクトリ <home> がある
    When <home>/runners/ のファイルを確かめる
    Then <home>/runners/standard-runner.sh は通常ファイルで実行権限がある
    And <home>/runners/ssh-runner.sh は存在しない
    And <home>/lib/ に runner-resolve.sh / runner-spec.sh / runner-result.sh / runner-notify.sh がある

  Scenario: validate-config_sh_feature-flag は標準の slot runner を両 slot に割り当てた設定の runner 割当とジョブマップ所在を出力する
    Given ff.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=<runners/standard-runner.sh の絶対パス> GREEN_RUNNER=<同じ絶対パス> RAPID_CROSSCHECK_MODE=off を書く
    And RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stderr は 0 行である
    And stdout は 15 行で、6 行目は "blue_runner: <runners/standard-runner.sh の絶対パス>"、7 行目は "green_runner: <runners/standard-runner.sh の絶対パス>"(同じパス)である
    And stdout の 12 行目は "blue_job_map: <RELAY_GATE_CONFIG_DIR>/blue-job-map.csv"、14 行目は "blue_runner_if_version=1"、15 行目は "green_runner_if_version=1" である

  Scenario: validate-config_sh_feature-flag は設定ファイルからの相対パスで書いた標準の slot runner を受理する
    Given relay-gate の配置ディレクトリ <home> の下の config/ff.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=../runners/standard-runner.sh GREEN_RUNNER=../runners/standard-runner.sh RAPID_CROSSCHECK_MODE=off を書く
    And RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある
    When <home> とは別のディレクトリを作業ディレクトリにして `validate-config.sh --feature-flag <home の絶対パス>/config/ff.env` を実行する
    Then 終了コード 0 で stdout の 6 行目は "blue_runner: <home の絶対パス>/config/../runners/standard-runner.sh"、7 行目は "green_runner: <home の絶対パス>/config/../runners/standard-runner.sh" である
    And stdout の 14 行目は "blue_runner_if_version=1"、15 行目は "green_runner_if_version=1" である

  Scenario: validate-config_sh_feature-flag は blue に標準の slot runner、green に自作の runner を割り当てた設定を受理する
    Given ff.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=<runners/standard-runner.sh の絶対パス> GREEN_RUNNER=<--help で "runner-if-version=1" を返す実行可能な自作 runner スタブの絶対パス> RAPID_CROSSCHECK_MODE=off を書く
    And RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stderr は 0 行である(割り当てられた実体が標準か自作かを区別しない)
    And stdout の 6 行目は "blue_runner: <runners/standard-runner.sh の絶対パス>"、7 行目は "green_runner: <自作 runner スタブの絶対パス>"、14 行目は "blue_runner_if_version=1"、15 行目は "green_runner_if_version=1" である

  Scenario: validate-config_sh_feature-flag は相対パスの runner を設定ファイルのあるディレクトリ基準で解決して問い合わせる
    Given 一時ディレクトリ conf の ff.env に BLUE_MODE=off GREEN_MODE=foreground GREEN_IMPL=green-1.4.0 GREEN_RUNNER=./green-runner.sh RAPID_CROSSCHECK_MODE=off を書く
    And conf/green-runner.sh は、起動されるたびに引数を記録し --help で "runner-if-version=1" を返す実行可能なスタブである
    And 作業ディレクトリにするディレクトリ work(conf とは別)に、起動されたら記録を残す別の実行可能な green-runner.sh がある
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv がある
    When work を作業ディレクトリにして `validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する
    Then 終了コード 0 で stdout に "green_runner: <conf の絶対パス>/./green-runner.sh" と "green_runner_if_version=1" が出て、stderr に "path is not absolute" を含む行は出ない
    And conf のスタブは引数 --help で 1 回起動され、work の green-runner.sh は起動されていない

  Scenario: validate-config_sh_feature-flag は応答しない相対パスの runner を解決後のパスで警告する
    Given 一時ディレクトリ conf の ff.env に BLUE_MODE=off GREEN_MODE=foreground GREEN_IMPL=green-1.4.0 GREEN_RUNNER=./green-runner.sh RAPID_CROSSCHECK_MODE=off を書く
    And conf/green-runner.sh は --help に "runner-if-version=" を含まない出力を返す実行可能ファイルである
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv がある
    When `validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する
    Then 終了コード 0 で stderr に "warn: runner does not respond to --help slot=green runner=<conf の絶対パス>/./green-runner.sh" が出る

  Scenario: validate-config_sh_feature-flag はジョブマップが無い slot を終了コード 2 で拒否する
    Given ff.env に GREEN_MODE=background GREEN_RUNNER=<実行可能> を書き RELAY_GATE_CONFIG_DIR/green-job-map.csv が無い
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: job map not found slot=green map=<RELAY_GATE_CONFIG_DIR>/green-job-map.csv" が出る

  Scenario: validate-config_sh_feature-flag は --help に応答しない runner を待機上限で打ち切り両 slot 未応答でも 10 秒以内に復帰する
    Given ff.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 RAPID_CROSSCHECK_MODE=off と、--help を受けると 30 秒 sleep する実行可能なスタブ runner を BLUE_RUNNER / GREEN_RUNNER に書く
    And RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で、起動から終了までの経過時間は 10 秒以内である(契約 runner_help_probe.response_time_budget の問い合わせの上限 9.2 秒に、数行の設定の検査の時間を加えた、この入力での確認)
    And stderr に "warn: runner does not respond to --help slot=blue runner=" で始まる行と "warn: runner does not respond to --help slot=green runner=" で始まる行が出る
    And stdout に "blue_runner_if_version=-" と "green_runner_if_version=-" が出る
    And 終了時点でスタブ runner のプロセスは残っていない

  Scenario: validate-config_sh_feature-flag は --help 問い合わせの準備に失敗すると終了コード 6 で止まる
    Given 有効な並行稼働設定の ff.env があり、一時ファイルの作成先(環境変数 TMPDIR)が存在しないディレクトリ /nonexistent/tmp を指す
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 6 で stderr に "error: runner probe failed slot=blue reason=" で始まる行が出る
    And stderr に "warn: runner does not respond to --help" で始まる行は出ず、stdout は 0 行である

  Scenario: 差し替えた runner 実体は runner IF だけで facade から起動できる
    Given 起動引数と環境変数を記録し Runner Result 3 ファイルを書く自作 runner を GREEN_RUNNER に割り当てる
    When `facade.sh JOB001 x` を BLUE_MODE=off GREEN_MODE=foreground GREEN_IMPL=green-1.4.0 RAPID_CROSSCHECK_MODE=off で実行する
    Then 自作 runner は "--run-id <run_id> --job-id JOB001 --role green --mode foreground -- x" で起動され、facade は exitcode.txt の値で終了する
    And 自作 runner の環境変数に RAPID_CROSSCHECK_MODE=off と GREEN_IMPL=green-1.4.0 があり、RAPID_CROSSCHECK_RUNNER は無い
```
