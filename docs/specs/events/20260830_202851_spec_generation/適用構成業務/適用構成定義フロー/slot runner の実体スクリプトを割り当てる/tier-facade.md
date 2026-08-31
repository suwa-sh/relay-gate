# slot runner の実体スクリプトを割り当てる - facade / slot runner ティア仕様

## 変更概要

runner 実体が守る **runner IF** と **Runner Result Contract** を契約として定義し、`validate-config.sh --feature-flag` に runner 割当の検証項目(実体の存在・実行権限・絶対パス・runner IF 応答・ジョブマップ所在)を追加する。relay-gate は共通ライブラリ `lib/runner-*.sh` と参考実装 `runners/ssh-runner.sh`(仮採用: 汎用の SSH runner)を同梱し、適用側は参考実装をコピーまたは `source` して実装固有部分を書く。

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
- **環境変数(受け取る)**: `RELAY_GATE_CONFIG_DIR` / `RELAY_GATE_ARTIFACT_ROOT` / `RELAY_GATE_LOG_DIR` / `RAPID_CROSSCHECK_MODE` の 4 つ(facade.sh / background-rerun.sh が引き継ぐ。全 UC 共通)。共通ライブラリの所在は runner 実体が自身のパスから導出する(配置ディレクトリの環境変数は引き継ぎ対象にしない)。`RAPID_CROSSCHECK_MODE=on` のとき runner は `$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` の `RAPID_DB_CONN_REF` を自分で読む(不在は exitcode.txt=2。UC「実装スクリプトを実行して Runner Result を出力する」)

#### runner 実体の責務(Runner Result Contract)

| 責務 | 内容 | 提供元 |
|---|---|---|
| ジョブマップ解決 | `<role>-job-map.tsv` から JOB_ID を解決し引数を連結 | `lib/runner-resolve.sh`(UC「ジョブマップで JOB_ID から実行先を解決する」) |
| execution-spec 保存 | 一度きり保存 | `lib/runner-spec.sh`(UC「execution-spec.json を確定保存する」) |
| 実装の実行 | 実行先で実装を起動し stdout / stderr / 終了コードを得る。**接続方法・OS・プロトコルはここに閉じる** | runner 実体(参考実装: `ssh -o BatchMode=yes`) |
| Runner Result 公開 | started-at.txt を起動時、3 ファイルを終了後に一時 → mv で公開。exitcode.txt = 終了コード | `lib/runner-result.sh`(UC「実装スクリプトを実行して Runner Result を出力する」) |
| 完了通知 | `RAPID_CROSSCHECK_MODE=on` のとき `rapid-crosscheck-runner.sh <role>-completed ...` | `lib/runner-notify.sh`(UC「速報クロスチェック runner へ完了通知を送信する」) |
| 終了コード | exitcode.txt と一致させる | runner 実体 |

- runner 実体が守らなければならない不変条件: (1) 3 ファイルを揃える、(2) exitcode.txt = 終了コード、(3) stdout / stderr(プロセス)に出さない、(4) 相手 slot の状態を判断しない、(5) 認証情報の値を成果物に書かない

### validate-config.sh --feature-flag(runner 割当の検証項目)

UC「feature flag を設定する」の契約に以下を追加する。

| 検証 | 違反時 stderr | 終了コード |
|---|---|---|
| runner パスが絶対パス | `error: runner path must be absolute slot=<s> path=<p>` | 2 |
| runner が存在し実行可能 | `error: runner not executable slot=<s> path=<p>` | 2 |
| 対応するジョブマップ `<slot>-job-map.tsv` が存在し読める | `error: job map not found slot=<s> map=<p>` | 2 |
| `<runner> --help` が `runner-if-version=1` を含む | `warn: runner does not respond to --help slot=<s> runner=<p>`(契約 validate-config.sh stderr の文言。`--help` に応答しない場合と `runner-if-version=` 行を返さない場合の両方)(拒否しない。stdout の `<slot>_runner_if_version` は `-`) | 0 |

- mode=off の slot は検証しない

## 出力契約

- **stdout**(validate-config.sh。feature flag の出力に追記、固定順):
  ```text
  blue_job_map: /etc/relay-gate/blue-job-map.tsv
  green_job_map: /etc/relay-gate/green-job-map.tsv
  blue_runner_if_version=1
  green_runner_if_version=1
  ```
  (off の slot、および `--help` が応答しない・`runner-if-version=` を含まない slot の `<slot>_runner_if_version` は `-`)
- **stderr / 終了コード**: UC「feature flag を設定する」と同じ(0 / 2)

## UC ロジック

- **バリデーション**: 上表。`--help` の呼び出しは 5 秒でタイムアウト(応答なしは warn。仮採用)
- **確認プロンプト**: なし
- **冪等性**: 読み取り専用
- **エラーハンドリング**: 違反は全件収集して報告
- **クラッシュ耐性**: 副作用なし
- **世代交代の手順**(仮採用。適用文書に記述する内容の例): (1) 次世代 runner を作成 → (2) テスト環境で validate-config.sh → (3) `GREEN_RUNNER` を差し替え → (4) 必要なら `BLUE_RUNNER` に旧 green runner を割り当て → (5) feature flag で運用モードを切り替え。relay-gate のスクリプトは変更しない

## 設定契約

- feature flag の `BLUE_RUNNER` / `GREEN_RUNNER`(UC「feature flag を設定する」の契約)
- runner 実体の配置: relay-gate 配置ディレクトリ配下の `runners/`(推奨。適用文書が所在を記述)
- 共通ライブラリ: relay-gate 配置ディレクトリ配下の `lib/runner-resolve.sh` / `runner-spec.sh` / `runner-result.sh` / `runner-notify.sh`(relay-gate 同梱。runner 実体が `source`)

## データモデル変更

RDB テーブルは触らない(`tables: []`)。

### ファイル

| ファイル | 説明 | 変更種別 |
|---|---|---|
| `runners/ssh-runner.sh` | 参考実装(SSH 経由の汎用 runner) | 追加 |
| `lib/runner-*.sh` | 共通ライブラリ | 追加 |

## ビジネスルール

- 実装固有の起動方式・ホスト・OS・プロトコルは runner 実体に閉じ込め、facade は設定された runner を起動するだけ(条件: 実装固有事項の runner への閉じ込め / facade の責務限定)
- runner の割当は feature flag が所有(条件: 設定所有区分)

## ティア完了条件(BDD)

```gherkin
Feature: slot runner の実体スクリプトを割り当てる - facade / slot runner ティア

  Scenario: ssh-runner_sh の --help は runner-if-version=1 を返す
    When `runners/ssh-runner.sh --help` を実行する
    Then 終了コード 0 で stdout に "usage: " で始まる行と "runner-if-version=1" が出る

  Scenario: validate-config_sh_feature-flag は runner 割当とジョブマップ所在を出力する
    Given ff.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_RUNNER=<runners/ssh-runner.sh の絶対パス> GREEN_RUNNER=<同> RAPID_CROSSCHECK_MODE=off を書く
    And RELAY_GATE_CONFIG_DIR に blue-job-map.tsv と green-job-map.tsv がある
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stdout に "blue_job_map: <RELAY_GATE_CONFIG_DIR>/blue-job-map.tsv" と "green_runner_if_version=1" が出る

  Scenario: validate-config_sh_feature-flag は相対パスの runner を終了コード 2 で拒否する
    Given ff.env に GREEN_MODE=background GREEN_RUNNER=./green-runner.sh を書く
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: runner path must be absolute slot=green path=./green-runner.sh" が出る

  Scenario: validate-config_sh_feature-flag はジョブマップが無い slot を終了コード 2 で拒否する
    Given ff.env に GREEN_MODE=background GREEN_RUNNER=<実行可能> を書き RELAY_GATE_CONFIG_DIR/green-job-map.tsv が無い
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: job map not found slot=green map=<RELAY_GATE_CONFIG_DIR>/green-job-map.tsv" が出る

  Scenario: 差し替えた runner 実体は runner IF だけで facade から起動できる
    Given 起動引数を記録し Runner Result 3 ファイルを書く自作 runner を GREEN_RUNNER に割り当てる
    When `facade.sh JOB001 x` を BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off で実行する
    Then 自作 runner は "--run-id <run_id> --job-id JOB001 --role green --mode foreground -- x" で起動され、facade は exitcode.txt の値で終了する
```
