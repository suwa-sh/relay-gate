# feature flag を設定する - facade / slot runner ティア仕様

## 変更概要

feature flag 設定(env)の列定義・検証ルールを **設定契約** として定義し、`validate-config.sh --feature-flag <path>` の presentation / usecase / domain(検証表)/ repository(env 読み込み)を新規実装する。facade.sh は同じ repository と domain を `source` して起動時検証に使う(検証ロジックの二重化を防ぐ)。

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
- **設定所有区分**: feature flag が所有するのは下表のキーのみ

| キー | 型 | 必須 | 値 | 検証 | 説明 |
|---|---|---|---|---|---|
| BLUE_MODE | enum | Yes | foreground / background / off | 列挙外は `error: unknown slot mode slot=blue mode=<v>` | blue slot の実行モード |
| GREEN_MODE | enum | Yes | foreground / background / off | 列挙外は `error: unknown slot mode slot=green mode=<v>` | green slot の実行モード |
| BLUE_RUNNER | path | BLUE_MODE≠off のとき Yes | 絶対パス | 存在しない / 実行権限なしは `error: runner not executable slot=blue path=<v>`。相対パスは `error: runner path must be absolute slot=blue path=<v>` | blue runner 実体 |
| GREEN_RUNNER | path | GREEN_MODE≠off のとき Yes | 絶対パス | 同上(slot=green) | green runner 実体 |
| RAPID_CROSSCHECK_MODE | enum | Yes | on / off | 列挙外は `error: unknown rapid_crosscheck_mode value=<v>` + `hint: use on or off` | 速報クロスチェックの有効・無効 |
| CONFIG_VERSION | string | No | 任意 | なし(実行ログに記録) | 設定版 |

- **組合せ検証**:
  - `BLUE_MODE=foreground` かつ `GREEN_MODE=foreground` → `error: both slots are foreground blue_mode=foreground green_mode=foreground`
  - foreground が 0 個 → `error: no foreground slot blue_mode=<v> green_mode=<v>`(ジョブスケジューラへ返す結果が無い。仮採用)
  - `FINAL_CROSSCHECK_*` キー → `error: final crosscheck key is not allowed key=<k>`
  - 未知のキー → `warn: unknown key ignored key=<k>`(拒否しない)
  - 方針資料に記載の `BLUE_IMPL` / `GREEN_IMPL` / `RAPID_CROSSCHECK_RUNNER` / `RAPID_CROSSCHECK_WORKER` → 未知キー扱い(`warn:`)。RDRA の情報「feature flag 設定」の属性に無いため契約に含めない(矛盾 2)
- **運用モード表**(参考。検証は組合せ検証で行い、表に無い有効な組合せも `custom` として許可する):

| 運用モード | BLUE_MODE | GREEN_MODE | RAPID_CROSSCHECK_MODE | operation_mode |
|---|---|---|---|---|
| 並行稼働 | foreground | background | on | parallel |
| 新実装の単独本番 | off | foreground | off | green-only |
| 次世代実装との並行稼働 | background | foreground | on | next-parallel |

## 出力契約

- **stdout**(検証 OK 時。固定順、plain `key=value`):
  ```text
  config_path: /etc/relay-gate/feature-flag.env
  blue_mode=foreground
  green_mode=background
  blue_runner: /opt/relay-gate/runners/blue-runner.sh
  green_runner: /opt/relay-gate/runners/green-runner.sh
  rapid_crosscheck_mode=on
  config_version=cfg-v1
  operation_mode=parallel
  blue_job_map: /etc/relay-gate/blue-job-map.tsv
  green_job_map: /etc/relay-gate/green-job-map.tsv
  blue_runner_if_version=1
  green_runner_if_version=1
  ```
  (未設定の値は `-`。runner が `--help` に応答しない場合の `<slot>_runner_if_version` も `-`。12 キー固定順は契約 `cli-command-contract.yaml` の `validate-config.sh` stdout が正。末尾 4 行(blue_job_map / green_job_map / blue_runner_if_version / green_runner_if_version)は UC「slot runner の実体スクリプトを割り当てる」が定義する。mode=off の slot は runner_if_version を `-` にする)
- **stderr**: 違反ごとに `error: ...` 1 行(全件)。`warn:` は未知キー。`hint:` は対処が明確な場合
- **実行ログ**(CONFIG_VERSION の記録先)の行形式: `_cross-cutting/ux-ui/ui-design.md` のログ行形式 `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従う。情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する
- **終了コード**:

| コード | 意味 | 条件 |
|-------|------|------|
| 0 | 検証 OK | 違反 0 件(warn はあってもよい) |
| 2 | 入力・設定検証エラー | 引数不正 / ファイルなし・読めない / 上記の検証違反が 1 件以上 |

## UC ロジック

- **バリデーション**: 上記の設定契約。違反は全件収集してから報告する(1 件目で止めない)
- **確認プロンプト**: なし
- **冪等性**: 読み取り専用。何度実行しても同じ結果
- **エラーハンドリング**: ファイル読み込み失敗は `error: config file not found path: <path>`、終了コード 2
- **クラッシュ耐性**: 副作用が無いため考慮不要
- **facade.sh との共有**: facade.sh は起動時に同じ検証を実行し、違反があれば runner を起動せず終了コード 2(UC「slot 実行モードを選択して runner を起動する」)。validate-config.sh はその検証を事前に単体で実行する手段

## データモデル変更

RDB テーブルは触らない(`tables: []`)。

### ファイル: `feature-flag.env`(情報: feature flag 設定)

上記「設定契約」の 6 キー。変更種別はすべて「追加」。

## ビジネスルール

- 両 slot foreground は許可しない(条件: foreground slot 排他)
- 実装スロットと runner の割当は feature flag が所有する。実行先・ハング検知上限・比較対象は所有しない(条件: 設定所有区分)
- RAPID_CROSSCHECK_MODE=on のときのみ速報が有効(条件: 速報クロスチェック有効判定)
- 確報の制御は feature flag に含めない(条件: 確報クロスチェック非起動)

## ティア完了条件(BDD)

```gherkin
Feature: feature flag を設定する - facade / slot runner ティア

  Scenario: validate-config_sh_feature-flag は有効な並行稼働設定に終了コード 0 と operation_mode=parallel を返す
    Given 一時ファイル ff.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=on BLUE_RUNNER=<実行可能な一時スクリプト> GREEN_RUNNER=<実行可能な一時スクリプト> CONFIG_VERSION=cfg-v1 を書く
    And 両スタブは --help で "runner-if-version=1" を返し、RELAY_GATE_CONFIG_DIR に blue-job-map.tsv と green-job-map.tsv がある
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stdout は 12 行で、8 行目は "operation_mode=parallel" である
    And stdout の 2 行目は "blue_mode=foreground" である
    And stdout の最終行は "green_runner_if_version=1" である(mode=off の slot なら "-")

  Scenario: validate-config_sh_feature-flag は両 slot foreground を終了コード 2 で拒否する
    Given ff.env に BLUE_MODE=foreground GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off を書く
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: both slots are foreground blue_mode=foreground green_mode=foreground" が出る

  Scenario: validate-config_sh_feature-flag は off の slot の runner を検証しない
    Given ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> を書き BLUE_RUNNER を書かない
    And RELAY_GATE_CONFIG_DIR に green-job-map.tsv がある(blue-job-map.tsv は無くてよい)
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stdout に "blue_runner: -" と "operation_mode=green-only" が出る

  Scenario: validate-config_sh_feature-flag は runner が実行不可なら終了コード 2 を返す
    Given ff.env に GREEN_MODE=foreground GREEN_RUNNER=/nonexistent/green.sh を書く
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: runner not executable slot=green path=/nonexistent/green.sh" が出る

  Scenario: validate-config_sh_feature-flag は未知キーを warn で報告し終了コード 0 を返す
    Given 有効な設定に加えて BLUE_IMPL=legacy を書く
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stderr に "warn: unknown key ignored key=BLUE_IMPL" が出る

  Scenario: validate-config_sh_feature-flag はファイルが無ければ終了コード 2 を返す
    When `validate-config.sh --feature-flag /nonexistent.env` を実行する
    Then 終了コード 2 で stderr に "error: config file not found path: /nonexistent.env" が出る
```
