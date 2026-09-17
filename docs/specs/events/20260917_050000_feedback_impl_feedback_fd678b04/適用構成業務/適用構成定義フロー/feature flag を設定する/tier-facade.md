# feature flag を設定する - facade / slot runner ティア仕様

## 変更概要

feature flag 設定(env)の 9 キー定義・検証ルールを **設定契約** として定義し、`validate-config.sh --feature-flag <path>` の presentation / usecase / domain(検証表)/ repository(env 読み込み)を新規実装する。facade.sh は同じ repository と domain を `source` して起動時検証に使う(検証ロジックの二重化を防ぐ)。

## コマンド契約

### validate-config.sh --feature-flag

- **書式**: `validate-config.sh --feature-flag <path> [--verbose]`
- **アクセス権**: 基盤適用設計者の直接起動(relay-gate 配置ディレクトリの実行権限)。読み取りのみで副作用なし

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| --feature-flag | string(パス) | Yes(この検証種別を選ぶ) | なし | 検証する env ファイル。`--job-map` / `--crosscheck-job-map` / `--target-catalog` と排他(同時指定は終了コード 2) |
| --verbose | boolean | No | false | `info:` を stderr に出す(読み込んだキー一覧など) |
| --help | boolean | No | false | 使い方を stdout に出して終了コード 0 |

- **stdin**: なし

## 設定契約(feature flag env)

- **所在**: `$RELAY_GATE_CONFIG_DIR/feature-flag.env`(facade.sh が起動のたびに読む。仮採用: _inference.md #5)
- **形式**: 1 行 1 キー `KEY=value`。`#` 始まりはコメント、空行は無視。値のクォートは不要(クォートは値の一部とみなさず、先頭末尾の `"` / `'` は除去する。仮採用)。シェル変数展開・コマンド置換は行わない(`source` しない。`grep` / `cut` で読む)
- **設定所有区分**: feature flag が所有するのは下表の 9 キーのみ(元の方針資料の設定契約と同じ)。設定版は持たない

| キー | 型 | 必須 | 値 | 検証 | 説明 |
|---|---|---|---|---|---|
| BLUE_MODE | enum | Yes | foreground / background / off | 列挙外は `error: invalid value key=BLUE_MODE value=<v>` + `hint: use foreground, background or off` | blue slot の実行モード |
| GREEN_MODE | enum | Yes | foreground / background / off | 列挙外は `error: invalid value key=GREEN_MODE value=<v>` + `hint: use foreground, background or off` | green slot の実行モード |
| RAPID_CROSSCHECK_MODE | enum | Yes | foreground / background / off | 列挙外は `error: invalid value key=RAPID_CROSSCHECK_MODE value=<v>` + `hint: use foreground, background or off` | 速報クロスチェックの制御。off 以外(foreground / background)は runner が完了通知を送信し速報管理 DB へ書き込む。off は完了通知を送信せず速報管理 DB へ接続も書込みもしない(parallel_run も作らない) |
| BLUE_IMPL | string(非空) | BLUE_MODE≠off のとき Yes | 任意の文字列 | 欠落・空は `error: option required option=BLUE_IMPL path: <path>` | blue の実装版。execution-spec.json の `slots.blue.impl_version` の出所 |
| GREEN_IMPL | string(非空) | GREEN_MODE≠off のとき Yes | 任意の文字列 | 欠落・空は `error: option required option=GREEN_IMPL path: <path>` | green の実装版。`slots.green.impl_version` の出所 |
| BLUE_RUNNER | path | BLUE_MODE≠off のとき Yes | 絶対パス | 欠落は `error: option required option=BLUE_RUNNER path: <path>`。相対パスは `error: path is not absolute key=BLUE_RUNNER path=<v>`。存在しない / 実行権限なしは `error: file not executable key=BLUE_RUNNER path=<v>` | blue slot runner 実体 |
| GREEN_RUNNER | path | GREEN_MODE≠off のとき Yes | 絶対パス | 同上(key=GREEN_RUNNER) | green slot runner 実体 |
| RAPID_CROSSCHECK_RUNNER | path | RAPID_CROSSCHECK_MODE≠off のとき Yes | 絶対パス | 同上(key=RAPID_CROSSCHECK_RUNNER) | slot runner が完了通知(blue-completed / green-completed)を送る速報クロスチェック runner の実体 |
| RAPID_CROSSCHECK_WORKER | path | RAPID_CROSSCHECK_MODE≠off のとき Yes | 絶対パス | 同上(key=RAPID_CROSSCHECK_WORKER) | 速報クロスチェック worker の実体(ジョブスケジューラの worker ジョブ定義 / 常駐起動が参照する実体) |

- **組合せ検証**:
  - foreground が 2 個(`BLUE_MODE=foreground` かつ `GREEN_MODE=foreground`)または 0 個 → `error: foreground slot must be exactly one blue_mode=<v> green_mode=<v>`(条件: foreground slot 排他)
  - `FINAL_CROSSCHECK_*` キー → `error: final crosscheck key is not allowed key=<k>`
  - 上記 9 キー以外のキー → `warn: unknown key key=<k> path: <path>`(拒否しない)。9 キーは未知キーとして扱わない
  - 上記 9 キー以外に必須キーは無い
- **運用モード表**(参考。検証は組合せ検証で行い、表に無い有効な組合せも `custom` として許可する。RDRA バリエーション「運用モード」):

| 運用モード | BLUE_MODE | GREEN_MODE | RAPID_CROSSCHECK_MODE | operation_mode |
|---|---|---|---|---|
| 並行稼働 | foreground | background | background | parallel |
| 新実装の単独本番 | off | foreground | off | green_only |
| 次世代実装との並行稼働 | background | foreground | background | next_gen_parallel |

## 出力契約

- **stdout**(検証 OK 時。固定順、plain `key=value`):
  ```text
  config_path: /etc/relay-gate/feature-flag.env
  blue_mode=foreground
  green_mode=background
  blue_impl=blue-2.3.1
  green_impl=green-1.4.0
  blue_runner: /opt/relay-gate/runners/blue-runner.sh
  green_runner: /opt/relay-gate/runners/green-runner.sh
  rapid_crosscheck_mode=background
  rapid_crosscheck_runner: /opt/relay-gate/bin/rapid-crosscheck-runner.sh
  rapid_crosscheck_worker: /opt/relay-gate/bin/rapid-crosscheck-worker.sh
  operation_mode=parallel
  blue_job_map: /etc/relay-gate/blue-job-map.csv
  green_job_map: /etc/relay-gate/green-job-map.csv
  blue_runner_if_version=1
  green_runner_if_version=1
  ```
  (未設定の値は `-`。runner が `--help` に応答しない場合の `<slot>_runner_if_version` も `-`(問い合わせの待機上限・実行順・未応答判定・準備失敗の扱いは契約 `validate-config.sh` の `runner_help_probe` が正)。15 キー固定順は契約 `cli-command-contract.yaml` の `validate-config.sh` stdout が正。末尾 4 行(blue_job_map / green_job_map / blue_runner_if_version / green_runner_if_version)は UC「slot runner の実体スクリプトを割り当てる」が定義する。mode=off の slot は `<slot>_impl` / `<slot>_runner` / `<slot>_job_map` / `<slot>_runner_if_version` を `-` にする。RAPID_CROSSCHECK_MODE=off では rapid_crosscheck_runner / rapid_crosscheck_worker を `-` にする)
- **stderr**: 違反ごとに `error: ...` 1 行(全件)。`warn:` は未知キー。`hint:` は対処が明確な場合
- **実行ログ**(facade.sh が起動のたびに残す行。定義元は UC「slot 実行モードを選択して runner を起動する」): `INFO feature flag loaded blue_mode=... green_mode=... rapid_crosscheck_mode=... blue_impl=... green_impl=... operation_mode=...`。行形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式 `{script} {run_id} {ローカル出力日時} {LEVEL} {message}` に従う。情報「実行ログ」の属性「出力日時」はこの ローカル時刻列に対応する
- **終了コード**:

| コード | 意味 | 条件 |
|-------|------|------|
| 0 | 検証 OK | 違反 0 件(warn はあってもよい) |
| 2 | 入力・設定検証エラー | 引数不正 / ファイルなし・読めない / 上記の検証違反が 1 件以上 |
| 6 | 実行エラー | runner `--help` 問い合わせの準備(一時ファイルの作成・プロセスグループでの起動)に失敗した。`error: runner probe failed slot=<s> reason=<r>` を出して即時終了(契約 `validate-config.sh` の `runner_help_probe.preparation_failure`。runner の未応答は warn で継続し 6 にしない) |

## UC ロジック

- **バリデーション**: 上記の設定契約。違反は全件収集してから報告する(1 件目で止めない)。runner `--help` の問い合わせ規則(待機上限・実行順・未応答判定)は契約 `validate-config.sh` の `runner_help_probe` に従う
- **確認プロンプト**: なし
- **冪等性**: 読み取り専用。何度実行しても同じ結果
- **エラーハンドリング**: ファイル読み込み失敗は `error: config file not found path: <path>`、終了コード 2。runner `--help` 問い合わせの準備失敗は終了コード 6(上表)
- **クラッシュ耐性**: 副作用が無いため考慮不要
- **facade.sh との共有**: facade.sh は起動時に同じ検証を実行し、違反があれば runner を起動せず終了コード 2(UC「slot 実行モードを選択して runner を起動する」)。validate-config.sh はその検証を事前に単体で実行する手段
- **runner への受け渡し**: slot runner は feature-flag.env を読まない。facade.sh / background-rerun.sh が読み、runner へ環境変数で渡す(`RAPID_CROSSCHECK_MODE`、off 以外のとき `RAPID_CROSSCHECK_RUNNER`、通常起動では自 slot の `BLUE_IMPL` / `GREEN_IMPL`。契約は UC「slot runner の実体スクリプトを割り当てる」の runner IF)

## データモデル変更

RDB テーブルは触らない(`tables: []`)。

### ファイル: `feature-flag.env`(情報: feature flag 設定)

上記「設定契約」の 9 キー。変更種別はすべて「追加」。

## ビジネスルール

- foreground はちょうど 1 slot(条件: foreground slot 排他)
- 実装スロットと runner の割当・実装版・速報クロスチェックの制御と実体は feature flag が所有する。実行先・ハング検知上限・比較対象は所有しない(条件: 設定所有区分)
- RAPID_CROSSCHECK_MODE が off 以外(foreground / background)のときのみ速報が有効。判定は「off か off 以外か」で行う(条件: 速報クロスチェック有効判定)
- 確報の制御は feature flag に含めない(条件: 確報クロスチェック非起動)

## ティア完了条件(BDD)

```gherkin
Feature: feature flag を設定する - facade / slot runner ティア

  Scenario: validate-config_sh_feature-flag は有効な並行稼働設定に終了コード 0 と operation_mode=parallel を返す
    Given 一時ファイル ff.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=<実行可能な一時スクリプト> GREEN_RUNNER=<実行可能な一時スクリプト> RAPID_CROSSCHECK_RUNNER=<実行可能な一時スクリプト> RAPID_CROSSCHECK_WORKER=<実行可能な一時スクリプト> を書く
    And 両 runner スタブは --help で "runner-if-version=1" を返し、RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stdout は 15 行で、11 行目は "operation_mode=parallel" である
    And stdout の 2 行目は "blue_mode=foreground"、4 行目は "blue_impl=blue-2.3.1" である
    And stdout の最終行は "green_runner_if_version=1" である(mode=off の slot なら "-")
    And stderr に "warn: unknown key" で始まる行は出ない

  Scenario: validate-config_sh_feature-flag は両 slot foreground を終了コード 2 で拒否する
    Given ff.env に BLUE_MODE=foreground GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off を書く
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground" が出る

  Scenario: validate-config_sh_feature-flag は off の slot の実装版と runner を検証しない
    Given ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> を書き BLUE_IMPL / BLUE_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER を書かない
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv がある(blue-job-map.csv は無くてよい)
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stdout に "blue_impl=-" "blue_runner: -" "rapid_crosscheck_runner: -" と "operation_mode=green_only" が出る

  Scenario: validate-config_sh_feature-flag は runner が実行不可なら終了コード 2 を返す
    Given ff.env に GREEN_MODE=foreground GREEN_IMPL=green-1.4.0 GREEN_RUNNER=/nonexistent/green.sh を書く
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: file not executable key=GREEN_RUNNER path=/nonexistent/green.sh" が出る

  Scenario: validate-config_sh_feature-flag は off でない slot の実装版の欠落を終了コード 2 で拒否する
    Given ff.env に GREEN_MODE=foreground GREEN_RUNNER=<実行可能> を書き GREEN_IMPL を書かない
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: option required option=GREEN_IMPL path: ff.env" が出る

  Scenario: validate-config_sh_feature-flag は速報有効時に速報 runner と worker の実体を検証する
    Given 有効な並行稼働設定の RAPID_CROSSCHECK_WORKER を /nonexistent/worker.sh に書き換える
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: file not executable key=RAPID_CROSSCHECK_WORKER path=/nonexistent/worker.sh" が出る

  Scenario: validate-config_sh_feature-flag は未知キーを warn で報告し終了コード 0 を返す
    Given 有効な設定に加えて CONFIG_VERSION=cfg-v1 を書く
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stderr に "warn: unknown key key=CONFIG_VERSION path: ff.env" が出る

  Scenario: validate-config_sh_feature-flag はファイルが無ければ終了コード 2 を返す
    When `validate-config.sh --feature-flag /nonexistent.env` を実行する
    Then 終了コード 2 で stderr に "error: config file not found path: /nonexistent.env" が出る
```
