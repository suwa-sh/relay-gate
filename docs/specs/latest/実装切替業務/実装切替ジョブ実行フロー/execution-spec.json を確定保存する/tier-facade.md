# execution-spec.json を確定保存する - facade / slot runner ティア仕様

## 変更概要

slot runner の usecase(保存フェーズ)、domain(ExecutionSpec / SlotSpec の JSON 化と節追加)、repository(lock 付きの一度きり追加)、gateway(`mkdir` lock、一時ファイル → `mv`)を新規実装する。CLI の入口は runner IF(UC「ジョブマップで JOB_ID から実行先を解決する」)と共通で、本 UC は解決直後・実装実行前に呼ばれる内部フェーズ。execution-spec.json は **run 単位で 1 ファイル**、slot ごとの `slots.<role>` 節を各 runner が書く(canonical C1)。

## コマンド契約

### $BLUE_RUNNER / $GREEN_RUNNER(runner IF。保存フェーズ)

- **書式**: `<runner> --run-id <run_id> --job-id <JOB_ID> --role blue|green --mode foreground|background [--execution-spec <path>] -- [PARAM...]`
- **アクセス権**: 内部呼び出し(facade.sh / background-rerun.sh)

#### 引数・オプション(本フェーズで使う項目)

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| --run-id | string | Yes | なし | 保存先 `facade/<run_id>/` と run 単位キー `run_id` |
| --job-id | string | Yes | なし | run 単位キー `job_id` |
| --role | enum | Yes | なし | `slots.<role>` のキー |
| --mode | enum | Yes | なし | `slots.<role>.mode` |
| --execution-spec | string | No | なし | 指定時は本フェーズをスキップする |
| -- PARAM... | string[] | No | 0 個 | run 単位キー `params`(最初の runner が書く) |

- **stdin**: なし
- **環境変数**: `RAPID_CROSSCHECK_MODE`(run 単位キー `rapid_crosscheck_mode`)

## 出力契約

- **stdout / stderr**: なし(実行ログのみ)
- **実行ログの行形式**: `_cross-cutting/ux-ui/ui-design.md` のログ行形式 `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従う。情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する
- **成果物**: `facade/<run_id>/execution-spec.json`(UTF-8、末尾改行、パーミッション 0640。仮採用)。一時的に `execution-spec.lock`(ディレクトリ)と `execution-spec.json.tmp` が現れる
- **終了コード**:

| コード | 意味 | 条件 |
|-------|------|------|
| 0 | 保存完了 または 自 slot 節が既存(何もしない) または 復元起動でスキップ | 次フェーズへ |
| 2 | 入力・設定検証エラー(復元起動) | `--execution-spec` のファイルなし / spec の run_id・job_id が引数と不一致 / 必須フィールド欠落(exitcode.txt=2。検証の正本は UC「実装スクリプトを実行して Runner Result を出力する」) |
| 6 | 実行エラー | lock 取得のタイムアウト(30 秒。仮採用)、一時ファイル書き込み失敗、`mv` 失敗、既存 JSON の解析失敗。このとき Runner Result 3 ファイル(`exitcode.txt=6`、stderr.log に `error: execution-spec write failed run_id=... role=... path=...`)を可能な限り揃える |

## UC ロジック

- **書き込み手順**(repository `save_slot_spec_once`):
  1. `mkdir <run_dir>/execution-spec.lock` で排他を取得する。失敗したら 0.5 秒待って再試行(最大 30 秒)。lock の mtime が 60 秒より古ければ残留とみなして強制取得する(`rmdir` → `mkdir`。実行ログに `WARN stale execution-spec lock reclaimed run_id=... age_seconds=...`。仮採用)
  2. `execution-spec.json` があれば読む。無ければ run 単位キー(`schema_version` / `run_id` / `parent_run_id=null` / `job_id` / `params` / `rapid_crosscheck_mode`)と空の `slots` で新規作成する
  3. `slots.<role>` が既にあれば何もしない(実行ログに `INFO execution-spec slot already exists`)。無ければ自 slot の節を追加する。他 slot の節と run 単位キーは変更しない
  4. `execution-spec.json.tmp` へ全体を書き、`mv` で `execution-spec.json` を置換する
  5. `rmdir execution-spec.lock` で解放する(手順 2〜4 が失敗しても必ず解放する)
- **バリデーション**: ExecutionTarget が揃っていること(前フェーズで検証済み)。`credential_ref` が空なら `null`。既存 JSON が `slots` を持たない・`run_id` が `--run-id` と一致しない場合は設定検証エラーとして exitcode.txt=2(stderr.log `error: execution-spec invalid path=... run_id=...`。契約 runner IF exit_codes 2「spec なし・run_id 不一致・欠落」と統一。6 は lock タイムアウト・書き込み失敗のみ)
- **確認プロンプト**: なし
- **冪等性**: 同一 run・同一 role で何度起動しても節は増えない(内容比較なし)。blue / green が同時に保存しても lock により逐次化され、両節が揃う
- **エラーハンドリング**: 書き込み失敗は usecase が 1 回だけ実行ログに ERROR を出し、gateway で Runner Result 3 ファイルを揃えて終了コード 6 で終了する。実装スクリプトは起動しない
- **クラッシュ耐性**:
  - lock 取得後・`mv` 前に落ちた場合: `.tmp` と `lock` が残る。確定名は変更されていない(前の内容のまま、または未作成)。次の runner が lock の mtime(60 秒超)で残留を検出して強制取得し、`.tmp` は上書きする
  - `mv` 後・`rmdir` 前に落ちた場合: 確定名は正しい。lock 残留は同様に回収される
  - 同一 run_id での再起動: 自 slot 節があれば何もしないため安全

## 設定契約

参照する設定は前 UC で解決済みの ExecutionTarget と環境変数 `RAPID_CROSSCHECK_MODE` のみ。設定ファイルを直接読まない。

## データモデル変更

RDB テーブルは触らない(`parallel_runs.execution_spec_uri` は facade が起動時に決めた URI を書き済み。本 UC は URI どおりの場所に保存する)。

### ファイル: `facade/<run_id>/execution-spec.json`(情報: 実行設定(execution-spec)。canonical C1)

run 単位キー:

| フィールド | 型 | 説明 | 書き手 | 変更種別 |
|--------|---|------|---|---------|
| schema_version | string | `"1"` | 最初の runner | 追加 |
| run_id | string | run_id | 最初の runner | 追加 |
| parent_run_id | string / null | リラン元。facade 起動では null(rerun がコピー時に書き換える) | 最初の runner | 追加 |
| job_id | string | JOB_ID | 最初の runner | 追加 |
| params | string[] | PARAM...(順序保持) | 最初の runner | 追加 |
| rapid_crosscheck_mode | string | on / off | 最初の runner | 追加 |
| slots | object | role → SlotSpec。mode=off の slot は節を持たない | 各 runner | 追加 |

`slots.<role>`(SlotSpec):

| フィールド | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| mode | string | foreground / background | 追加 |
| host | string | 実行先ホスト | 追加 |
| exec_user | string | 実行ユーザー | 追加 |
| script_path | string | 実装スクリプトパス | 追加 |
| work_dir | string | 作業ディレクトリ | 追加 |
| fixed_args | string[] | 固定引数(JSON 配列そのまま) | 追加 |
| hang_detect_limit_minutes | integer | この role のハング検知上限 | 追加 |
| credential_ref | string / null | 認証情報参照名。値は書かない | 追加 |
| map_version | string | マップ版 | 追加 |
| impl_version | string | 実装版 | 追加 |
| finalized_at | string | 節の確定保存日時(UTC ISO 8601) | 追加 |

## ビジネスルール

- run 開始時に自 slot の節を一度だけ保存し、以後ジョブマップを変更しても上書きしない(条件: 実行設定の確定条件)
- 認証情報は参照名だけを保存する(条件: 認証情報の非保存)
- lock で排他し、一時ファイルへ書いてから確定名へリネームする(条件: 成果物公開判定)
- `--execution-spec` 指定の復元起動では保存しない(条件: リランの実行設定復元)

## ティア完了条件(BDD)

```gherkin
Feature: execution-spec.json を確定保存する - facade / slot runner ティア

  Scenario: save_slot_spec_once はファイルが無ければ run 単位キーと自 slot 節で新規作成する
    Given RELAY_GATE_ARTIFACT_ROOT/facade/20260830T113000Z-JOB001-3f9a1c2e/ が空である
    And RELAY_GATE_CONFIG_DIR/green-job-map.tsv に JOB001 の行(hang_detect_limit_minutes=60)がある
    When `<runner> --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background -- 20260830` を RAPID_CROSSCHECK_MODE=off で保存フェーズまで実行する
    Then execution-spec.json が存在し、.tmp と .lock は存在しない
    And JSON の run_id は "20260830T113000Z-JOB001-3f9a1c2e"、parent_run_id は null、params は ["20260830"]、rapid_crosscheck_mode は "off" である
    And slots.green.mode は "background"、slots.green.hang_detect_limit_minutes は 60 であり、slots.blue は無い

  Scenario: save_slot_spec_once は既存ファイルに自 slot 節を追加し他 slot 節を変更しない
    Given execution-spec.json に slots.blue(host=host-blue-01)だけがある
    When green runner の保存フェーズを実行する
    Then slots.blue.host は host-blue-01 のままで、slots.green が追加されている
    And run_id / job_id / params は変わっていない

  Scenario: save_slot_spec_once は同 run 同 role で再起動しても節を増やさない
    Given execution-spec.json に slots.green(host=host-green-01)がある
    And ジョブマップの host を host-green-02 に変更した
    When 同じ run_id で green runner の保存フェーズを実行する
    Then 終了コード 0 で、slots.green.host は host-green-01 のままで slots.green は 1 つだけである
    And 実行ログに "INFO execution-spec slot already exists run_id=20260830T113000Z-JOB001-3f9a1c2e role=green" が出る

  Scenario: save_slot_spec_once は blue と green の同時保存で両節を揃える
    Given 空の run ディレクトリがある
    When blue runner と green runner の保存フェーズを同時に起動する
    Then 両方が終了コード 0 で終了し、execution-spec.json に slots.blue と slots.green が両方あり lock は残っていない

  Scenario: save_slot_spec_once は credential_ref に参照名だけを書く
    Given ジョブマップの credential_ref が ssh-key-green である
    When 保存フェーズを実行する
    Then slots.green.credential_ref は "ssh-key-green" であり、ファイル全体に "/home/" や "BEGIN" を含む文字列は無い

  Scenario: 保存フェーズは --execution-spec 指定時に何も書かない
    Given execution-spec.json が 2026-08-30T11:30:01Z の更新日時で存在する
    When `<runner> --run-id 20260830T150000Z-JOB001-9b8c7d6e --job-id JOB001 --role green --mode background --execution-spec <path>` を保存フェーズまで実行する
    Then execution-spec.json の更新日時は変わらない

  Scenario: save_slot_spec_once は 60 秒より古い lock を強制取得する
    Given run ディレクトリに mtime が 120 秒前の execution-spec.lock がある
    When green runner の保存フェーズを実行する
    Then 終了コード 0 で保存が完了し、実行ログに "WARN stale execution-spec lock reclaimed run_id=<run_id> age_seconds=120" が出る

  Scenario: 保存フェーズは書き込み失敗で終了コード 6 と 3 ファイルを出す
    Given facade/<run_id>/ が読み取り専用である
    When 保存フェーズを実行する
    Then 終了コード 6 で終了し、実行ログに "ERROR execution-spec write failed" が出る
```
