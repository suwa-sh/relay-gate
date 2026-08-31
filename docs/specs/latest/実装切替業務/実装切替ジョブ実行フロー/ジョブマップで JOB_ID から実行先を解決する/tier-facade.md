# ジョブマップで JOB_ID から実行先を解決する - facade / slot runner ティア仕様

## 変更概要

slot runner の presentation(runner IF の引数解析)、usecase(解決フロー)、domain(ExecutionTarget と引数連結の純粋関数)、repository(ジョブマップ TSV の読み込み)、gateway(未定義時の Runner Result 出力)を新規実装する。runner 実体は `$BLUE_RUNNER` / `$GREEN_RUNNER` として差し替え可能だが、本 UC の解決ロジックは relay-gate が提供する共通ライブラリ(`lib/runner-*.sh`)として runner 実体から `source` して使う(仮採用: 実装固有事項は runner 実体、共通契約はライブラリ)。

## コマンド契約

### $BLUE_RUNNER / $GREEN_RUNNER(runner IF。解決フェーズ)

- **書式**: `<runner> --run-id <run_id> --job-id <JOB_ID> --role blue|green --mode foreground|background [--execution-spec <path>] -- [PARAM...]`
- **アクセス権**: 内部呼び出し(facade.sh / background-rerun.sh)。運用者は直接起動しない

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| --run-id | string | Yes | なし | facade が発行した run_id。成果物ディレクトリ名 |
| --job-id | string | Yes | なし | JOB_ID。ジョブマップの検索キー |
| --role | enum(blue / green) | Yes | なし | 自 slot。ジョブマップの選択(`<role>-job-map.tsv`)と成果物ディレクトリ区分 |
| --mode | enum(foreground / background) | Yes | なし | 解決には使わない(execution-spec の `slots.<role>.mode` と完了通知で使う) |
| --execution-spec | string(パス) | No | なし | 指定時はジョブマップを読まず、このファイルの `slots.<role>` から実行先を復元する(UC「実装スクリプトを実行して Runner Result を出力する」の復元起動) |
| -- PARAM... | string[] | No | 0 個 | 追加引数。`--` 以降をすべて PARAM として順序保持 |
| --help | boolean | No | false | 使い方と `runner-if-version=1` を stdout に出して終了コード 0(解決は行わない。契約 runner IF) |

- **stdin**: なし

#### ジョブマップ(読み取り専用)

- パス: `$RELAY_GATE_CONFIG_DIR/<role>-job-map.tsv`(仮採用: _inference.md #5)
- 形式: タブ区切り、1 行目ヘッダー。列は `job_id host exec_user script_path work_dir fixed_args_json hang_detect_limit_minutes credential_ref map_version impl_version`。列定義・検証ルールの正本は UC「slot ごとのジョブマップを定義する」
- 読み方: ヘッダー列名で列位置を決める。`#` 始まりの行と空行は無視する。job_id 完全一致

## 出力契約

- **stdout / stderr**: runner はプロセスの stdout / stderr に出さない。すべて成果物ファイルと実行ログへ出す
- **実行ログの行形式**: `_cross-cutting/ux-ui/ui-design.md` のログ行形式 `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従う。情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する
- **実行ログ**: `INFO job map resolved job_id=... slot=... host=... map_version=...`(解決成功)/ `WARN duplicate job_id in job map job_id=... lines=...`(重複行は先頭採用)/ `ERROR job_id=... not found in job map slot=... map=...`(未定義。stderr.log と同文。exitcode.txt=2)/ `ERROR option required option=--job-id`
- **成果物(未定義・解決失敗時)**: `facade/<run_id>/<role>/stdout.log`(空)、`stderr.log`(`error:` 1 行)、`exitcode.txt`(`2`)。`started-at.txt` も出力する(起動時刻。ハング検知が「exitcode.txt あり・非 0」で実行エラーと判定できるように)
- **終了コード**:

| コード | 意味 | 条件 |
|-------|------|------|
| 0 | 解決成功 | 次フェーズ(execution-spec 保存)へ進む。runner プロセスとしての終了コードは最終的に実装の exitcode.txt と一致させる |
| 2 | 入力・設定検証エラー | runner IF の引数不足・列挙外、ジョブマップファイルなし、job_id 未定義、fixed_args_json 不正、hang_detect_limit_minutes が非負整数でない、列数不足。exitcode.txt にも `2` を書く |
| 6 | 実行エラー | 成果物ディレクトリへの書き込み失敗(3 ファイルを揃えられない場合。実行ログに ERROR) |

エラーメッセージ(stderr.log に書く。stderr ではない):

| 状況 | 文言 |
|---|---|
| job_id 未定義 | `error: job_id=JOB999 not found in job map slot=green map=/etc/relay-gate/green-job-map.tsv` |
| マップなし | `error: job map not found slot=green map=/etc/relay-gate/green-job-map.tsv` |
| 固定引数不正 | `error: fixed_args_json is not a json array job_id=JOB003 slot=green` |
| 上限不正 | `error: hang_detect_limit_minutes is not a non-negative integer job_id=JOB003 slot=green value=abc` |
| 必須オプション欠落 | `error: option required option=--job-id`(横断規約の定型文。run_id / role が不明なら成果物は書けないため実行ログにのみ残す) |

## UC ロジック

- **バリデーション**: (1) runner IF の必須オプション → (2) ジョブマップファイルの存在と読み取り権限 → (3) job_id 行の存在 → (4) 行の列数 10 → (5) `fixed_args_json` が JSON 配列 → (6) `hang_detect_limit_minutes` が `^[0-9]+$`。JSON 配列の解析は jq に依存せず、bash + `sed` / `awk` で文字列要素を抽出する(仮採用: エアーギャップ・jq 非依存。ネストした配列・オブジェクトは非対応で検証エラー)
- **確認プロンプト**: なし
- **冪等性**: 読み取りのみ。同じ入力なら同じ ExecutionTarget を返す。未定義時の 3 ファイルは既存があれば上書きしない(既にこの run の成果物がある = 二重起動。実行ログに WARN)
- **エラーハンドリング**: 解決失敗は usecase が 1 回だけ実行ログに ERROR を出し、gateway で 3 ファイルを揃えてから終了コード 2 で終了する。3 ファイルの書き込み自体に失敗したら終了コード 6(exitcode.txt が無い状態。ハング検知が上限超過でハング疑いとして拾う)
- **クラッシュ耐性**: 解決フェーズは副作用を持たない(ファイル書き込みは失敗時のみ)。途中で落ちても成果物は `started-at.txt` だけが残り、ハング検知の対象となる。再実行はジョブスケジューラの正規ジョブ(新 run_id)

## 設定契約

slot ジョブマップの列定義・検証ルール(`validate-config.sh --job-map`)は UC「slot ごとのジョブマップを定義する」の tier-facade.md を正本とする。この UC は読み取り専用で従う(arch CM-001)。

## データモデル変更

RDB テーブルは触らない。

### ファイル(読み込み)

| ファイル | 列 / 型 | 説明 | 変更種別 |
|---|---|---|---|
| `<role>-job-map.tsv` | 10 列(上記) | 解決元 | 追加(参照) |

### ファイル(失敗時の出力)

| ファイル | 型 | 説明 | 変更種別 |
|---|---|---|---|
| `facade/<run_id>/<role>/started-at.txt` | UTC ISO 8601 1 行 | 起動時刻 | 追加 |
| `facade/<run_id>/<role>/stdout.log` | 空 | 実装未実行 | 追加 |
| `facade/<run_id>/<role>/stderr.log` | text | `error:` 1 行 | 追加 |
| `facade/<run_id>/<role>/exitcode.txt` | 数値 1 行 | `2` | 追加 |

## ビジネスルール

- JOB_ID の行がジョブマップに存在するときのみ実行先を解決できる。未定義なら非 0 の exitcode.txt と原因を含む stderr.log を出力する(条件: ジョブマップ解決条件)
- 固定引数(JSON 配列)の後ろに PARAM... を順序を変えずに連結する。引数の数と各引数内の空白・カンマを維持する。空は `[]`(条件: 引数連結規則)
- 実行先の正本は該当 slot のジョブマップだけ(条件: 設定所有区分)
- 解決失敗でも stdout.log / stderr.log / exitcode.txt を揃える(条件: Runner Result 完備条件)

## ティア完了条件(BDD)

```gherkin
Feature: ジョブマップで JOB_ID から実行先を解決する - facade / slot runner ティア

  Scenario: runner はヘッダー列名で列位置を決めて実行先を解決する
    Given RELAY_GATE_CONFIG_DIR/green-job-map.tsv のヘッダーが "job_id	host	exec_user	script_path	work_dir	fixed_args_json	hang_detect_limit_minutes	credential_ref	map_version	impl_version" である
    And 行 "JOB001	host-green-01	batch	/opt/app/bin/job001.sh	/var/app/work	["--mode","full"]	60	ssh-key-green	map-v3	green-1.4.0" がある
    When `<runner> --run-id 20260830T113000Z-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background -- 20260830` を解決フェーズまで実行する
    Then 解決結果は host=host-green-01 exec_user=batch script_path=/opt/app/bin/job001.sh work_dir=/var/app/work hang_detect_limit_minutes=60 credential_ref=ssh-key-green map_version=map-v3 impl_version=green-1.4.0 である
    And 引数列は --mode / full / 20260830 の 3 個である

  Scenario: build_argument_list は空白とカンマを含む要素を 1 引数として維持する
    Given fixed_args_json が ["p1","p2 p3","a,b"] で PARAM が x y である
    When 引数連結関数を呼ぶ
    Then 引数列は p1 / "p2 p3" / "a,b" / x / y の 5 個である

  Scenario: runner は job_id 未定義のとき 3 ファイルと started-at.txt を揃えて終了コード 2 で終了する
    Given RELAY_GATE_CONFIG_DIR/green-job-map.tsv に JOB999 の行が無い
    When `<runner> --run-id 20260830T113000Z-JOB999-a1b2c3d4 --job-id JOB999 --role green --mode background` を実行する
    Then 終了コード 2 で終了する
    And RELAY_GATE_ARTIFACT_ROOT/facade/20260830T113000Z-JOB999-a1b2c3d4/green/ に started-at.txt stdout.log stderr.log exitcode.txt が揃う
    And exitcode.txt は "2" の 1 行、stderr.log は "error: job_id=JOB999 not found in job map slot=green map=<RELAY_GATE_CONFIG_DIR>/green-job-map.tsv" を含む
    And 同ディレクトリに .tmp サフィックスのファイルは残っていない

  Scenario: runner は --job-id 欠落を終了コード 2 で拒否する
    Given 正しいジョブマップがある
    When `<runner> --run-id 20260830T113000Z-JOB001-3f9a1c2e --role green --mode background` を実行する
    Then 終了コード 2 で終了し、実行ログに "ERROR option required option=--job-id" が出る
```
