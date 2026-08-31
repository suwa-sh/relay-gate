# slot ごとのジョブマップを定義する - facade / slot runner ティア仕様

## 変更概要

slot ジョブマップ(TSV)の列定義・検証ルールを **設定契約** として定義し、`validate-config.sh --job-map <path>` の usecase / domain(検証表)を新規実装する。TSV 読み込み関数(repository)は UC「ジョブマップで JOB_ID から実行先を解決する」と共有する。

## コマンド契約

### validate-config.sh --job-map

- **書式**: `validate-config.sh --job-map <path> [--verbose]`
- **アクセス権**: 基盤適用設計者の直接起動。読み取りのみ

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| --job-map | string(パス) | Yes(この検証種別を選ぶ) | なし | 検証する TSV。slot はファイル名(`<slot>-job-map.tsv`)から推定しない(任意のパスを検証できる) |
| --verbose | boolean | No | false | 各行の解決結果を `info:` で出す |
| --help | boolean | No | false | 使い方 |

- **stdin**: なし

## 設定契約(slot ジョブマップ TSV)

- **所在**: `$RELAY_GATE_CONFIG_DIR/blue-job-map.tsv` / `green-job-map.tsv`(仮採用: _inference.md #5)
- **形式**: タブ区切り。1 行目はヘッダー行(列名は下表の順を推奨するが、読み手はヘッダー列名で位置を決めるため順序は任意)。`#` 始まりの行と空行は無視。値にタブ・改行を含めない。文字コード UTF-8。1 ファイル 1 slot
- **設定所有区分**: 実行先とハング検知上限の正本。runner・mode(feature flag)、比較対象(クロスチェックジョブマップ)は置かない

| 列 | 型 | 必須 | 検証 | 違反時 stderr(行番号・job_id 付き) | 説明 |
|---|---|---|---|---|---|
| job_id | string | Yes | `^[A-Za-z0-9_-]+$`、ファイル内で一意 | `error: job_id is invalid line=N job_id=<v> value=<v>` / `error: duplicate job_id job_id=<v> lines=<n1,n2,...>`(2 回目以降の行番号をカンマ区切りで全部) | JOB_ID |
| host | string | Yes | 空でない | `error: host is empty line=N job_id=<v> value=` | 実行先ホスト(SSH 設定の Host 別名可) |
| exec_user | string | Yes | 空でない | `error: exec_user is empty line=N job_id=<v> value=` | 実行ユーザー |
| script_path | string | Yes | 絶対パス(`^/`) | `error: script_path is not absolute line=N job_id=<v> value=<v>` | 実装スクリプトパス(リモート側。存在確認はしない) |
| work_dir | string | Yes | 絶対パス | `error: work_dir is not absolute line=N job_id=<v> value=<v>` | 作業ディレクトリ(リモート側) |
| fixed_args_json | string | Yes | JSON 配列(文字列要素のみ)。空は `[]` | `error: fixed_args_json is not a json array line=N job_id=<v> value=<v>` | 固定引数 |
| hang_detect_limit_minutes | integer | Yes | `^[0-9]+$` | `error: hang_detect_limit_minutes is not a non-negative integer line=N job_id=<v> value=<v>` | ハング検知上限(分)。0 = 検知対象外。導入時 60 |
| credential_ref | string | No(空可) | `^[A-Za-z0-9_.-]*$`。`/` を含む・`BEGIN` を含むは warn | `warn: credential_ref looks like a secret or path line=N job_id=<v>` | 認証情報参照名。値は書かない |
| map_version | string | Yes | 空でない。ファイル内で単一を推奨 | `error: map_version is empty line=N job_id=<v> value=` / `warn: mixed map_version values=<a>,<b>` | マップ版 |
| impl_version | string | Yes | 空でない | `error: impl_version is empty line=N job_id=<v> value=` | 実装版 |

- **ヘッダー検証**: 10 列名がすべて存在すること。不足は `error: header mismatch expected=<col1,...,col10> actual=<実際の列名> path: <path>`(契約 validate-config.sh の共通形式)、余分は `warn: unknown column ignored column=<col>`
- **列数検証**: データ行の列数がヘッダーと一致しないと `error: column count mismatch line=N expected=10 actual=<n>`
- **hang_detect_limit_minutes の運用**(条件: ハング検知上限の調整基準): 導入時は全ジョブ 60。foreground で動く slot のファイルは 0。警告傾向(`hang-detect-trend.sh`)を見てジョブごとに調整する。変更は次回以降の run の execution-spec.json にのみ反映される
- **サンプル**(`config/green-job-map.tsv.example` として同梱):

```text
job_id	host	exec_user	script_path	work_dir	fixed_args_json	hang_detect_limit_minutes	credential_ref	map_version	impl_version
JOB001	host-green-01	batch	/opt/app/bin/job001.sh	/var/app/work	["--mode","full"]	60	ssh-key-green	map-v3	green-1.4.0
JOB002	host-green-01	batch	/opt/app/bin/job002.sh	/var/app/work	[]	60	ssh-key-green	map-v3	green-1.4.0
```

## 出力契約

- **stdout**(検証 OK 時、固定順):
  ```text
  map_path: /etc/relay-gate/green-job-map.tsv
  rows=2
  map_version=map-v3
  impl_version=green-1.4.0
  ```
  `--verbose` 時は stderr に行ごとの `info: job_id=JOB001 host=host-green-01 hang_detect_limit_minutes=60`
- **stderr**: 違反ごとに `error:` 1 行(全件、行番号付き)。`warn:` は認証情報らしい値・版の混在・未知列
- **終了コード**:

| コード | 意味 | 条件 |
|-------|------|------|
| 0 | 検証 OK | error 0 件 |
| 2 | 入力・設定検証エラー | 引数不正 / ファイルなし / ヘッダー不一致 / 列検証違反 / job_id 重複 |

## UC ロジック

- **バリデーション**: 上表。全行を検査してから全件報告
- **確認プロンプト**: なし
- **冪等性**: 読み取り専用
- **エラーハンドリング**: ファイルなしは `error: config file not found path: <path>`、終了コード 2
- **クラッシュ耐性**: 副作用なし
- **JSON 配列の判定**(仮採用、jq 非依存): 先頭 `[` 末尾 `]`、要素は `"..."`(エスケープ `\"` `\\` `\/` `\n` `\t` を許可)をカンマ区切り。ネストした配列・オブジェクト・数値・真偽値は非対応(違反)。runner の解決関数と同じ実装を共有する

## データモデル変更

RDB テーブルは触らない(`tables: []`)。

### ファイル: `<slot>-job-map.tsv`(情報: ジョブマップ + ハング検知上限設定)

上記「設定契約」の 10 列。変更種別はすべて「追加」。arch E-003 の `fixed_args` は列名を `fixed_args_json` とする(JSON 配列であることを列名で示す。_inference.md #5 と guide の列定義に従う)。E-004(ハング検知上限設定)の `adjusted_at` / `adjustment_basis` はジョブマップ列に含めない(調整の記録は運用者の適用文書またはコミット履歴。仮採用)。

## ビジネスルール

- 実行先とハング検知上限は該当 slot のジョブマップが所有する(条件: 設定所有区分)
- JOB_ID の行があるときのみ解決できる。job_id は一意(条件: ジョブマップ解決条件)
- 固定引数は JSON 配列で引数の数と空白・カンマを維持する。空は `[]`(条件: 引数連結規則)
- 認証情報は参照名で指定する(条件: 認証情報の非保存)
- hang_detect_limit_minutes は導入時 60、foreground role は 0、調整は次回以降の run に反映(条件: ハング検知上限の調整基準)

## ティア完了条件(BDD)

```gherkin
Feature: slot ごとのジョブマップを定義する - facade / slot runner ティア

  Scenario: validate-config_sh_job-map は有効な TSV に終了コード 0 と集計を返す
    Given 一時ファイル map.tsv に契約どおりのヘッダーと 2 行(JOB001 hang_detect_limit_minutes=60、JOB002 hang_detect_limit_minutes=0、map_version=map-v3、impl_version=green-1.4.0)を書く
    When `validate-config.sh --job-map map.tsv` を実行する
    Then 終了コード 0 で stdout は "map_path: <path>" "rows=2" "map_version=map-v3" "impl_version=green-1.4.0" の 4 行である

  Scenario: validate-config_sh_job-map は列順が入れ替わったヘッダーを受け付ける
    Given map.tsv のヘッダーが "host	job_id	exec_user	script_path	work_dir	fixed_args_json	hang_detect_limit_minutes	credential_ref	map_version	impl_version" の順である
    When `validate-config.sh --job-map map.tsv` を実行する
    Then 終了コード 0 である

  Scenario: validate-config_sh_job-map は fixed_args_json の不正を行番号付きで拒否する
    Given map.tsv の 3 行目(JOB003)の fixed_args_json が "p1,p2" である
    When `validate-config.sh --job-map map.tsv` を実行する
    Then 終了コード 2 で stderr に "error: fixed_args_json is not a json array line=3 job_id=JOB003" が出る

  Scenario: validate-config_sh_job-map は空白とカンマを含む JSON 配列要素を受け付ける
    Given map.tsv の JOB001 行の fixed_args_json が ["p2 p3","a,b"] である
    When `validate-config.sh --job-map map.tsv --verbose` を実行する
    Then 終了コード 0 で stderr に "info: job_id=JOB001" を含む行が出る

  Scenario: validate-config_sh_job-map は job_id の重複を拒否する
    Given map.tsv の 2 行目と 5 行目が job_id=JOB001 である
    When `validate-config.sh --job-map map.tsv` を実行する
    Then 終了コード 2 で stderr に "error: duplicate job_id job_id=JOB001 lines=2,5" が出る

  Scenario: validate-config_sh_job-map はヘッダー不足を拒否する
    Given map.tsv のヘッダーに credential_ref 列が無い
    When `validate-config.sh --job-map map.tsv` を実行する
    Then 終了コード 2 で stderr に "error: header mismatch expected=job_id,host,exec_user,script_path,work_dir,fixed_args_json,hang_detect_limit_minutes,credential_ref,map_version,impl_version actual=job_id,host,exec_user,script_path,work_dir,fixed_args_json,hang_detect_limit_minutes,map_version,impl_version path: map.tsv" が出る

  Scenario: validate-config_sh_job-map は列数不一致を拒否する
    Given map.tsv の 2 行目が 9 列である
    When `validate-config.sh --job-map map.tsv` を実行する
    Then 終了コード 2 で stderr に "error: column count mismatch line=2 expected=10 actual=9" が出る

  Scenario: validate-config_sh_job-map は credential_ref のパス形式を warn で報告する
    Given map.tsv の JOB001 行の credential_ref が /home/batch/.ssh/id_green である
    When `validate-config.sh --job-map map.tsv` を実行する
    Then 終了コード 0 で stderr に "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" が出る
```
