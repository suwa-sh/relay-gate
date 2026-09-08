# slot ごとのジョブマップを定義する - facade / slot runner ティア仕様

## 変更概要

slot ジョブマップ(CSV)の列定義・CSV セルのクォート解析規則・検証ルールを **設定契約** として定義し、`validate-config.sh --job-map <path>` の usecase / domain(検証表)を新規実装する。CSV 読み込み関数(repository)は UC「ジョブマップで JOB_ID から実行先を解決する」と共有する。

## コマンド契約

### validate-config.sh --job-map

- **書式**: `validate-config.sh --job-map <path> [--verbose]`
- **アクセス権**: 基盤適用設計者の直接起動。読み取りのみ

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| --job-map | string(パス) | Yes(この検証種別を選ぶ) | なし | 検証する CSV。slot はファイル名(`<slot>-job-map.csv`)から推定しない(任意のパスを検証できる) |
| --verbose | boolean | No | false | 各行の解決結果を `info:` で出す |
| --help | boolean | No | false | 使い方 |

- **stdin**: なし

## 設定契約(slot ジョブマップ CSV)

- **所在**: `$RELAY_GATE_CONFIG_DIR/blue-job-map.csv` / `green-job-map.csv`(仮採用: _inference.md #5)
- **形式**: CSV(カンマ区切り)。1 行目はヘッダー行(列はヘッダー名で対応付ける。順序は元資料の並び `job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes` を推奨するが検証は名前で行う)。行頭 `#` の行と空行は無視。改行コードは LF。セル内に改行は置けない。文字コード UTF-8。1 ファイル 1 slot
- **CSV セルのクォート解析規則**(条件: ジョブマップ解決条件): セルはカンマ区切り。セルは二重引用符で囲める(囲まない場合はカンマ・二重引用符を含められない)。囲んだセル内の二重引用符は `""` と二重化する。`fixed_params` は JSON 配列文字列を格納するセルで、必ず二重引用符で囲む(例: `"[""p1"",""p2 p3""]"` → 固定引数 `p1` と `p2 p3` の 2 要素。空は `"[]"` または `[]`)。bash 単独(外部 CSV パーサ非依存)で 1 文字ずつ状態機械で解析できる範囲に限定する(ネスト・複数行セル不可)。閉じ引用符が無い・囲み外に二重引用符がある行は `error: csv quote is invalid line=N path: <path>`
- **設定所有区分**: 実行先とハング検知上限の正本。runner・mode・実装版(feature flag)、比較対象(クロスチェックジョブマップ)は置かない

| 列 | 型 | 必須 | 検証 | 違反時 stderr(行番号・job_id 付き) | 説明 |
|---|---|---|---|---|---|
| job_id | string | Yes | `^[A-Za-z0-9_-]+$`、ファイル内で一意 | `error: job_id is invalid line=N job_id=<v> value=<v>` / `error: duplicate job_id job_id=<v> lines=<n1,n2,...>`(2 回目以降の行番号をカンマ区切りで全部) | JOB_ID |
| host | string | No(列は user と対で置く) | 列があるとき、user と両方空ならローカル実行。host だけ空は違反 | `error: host is empty line=N job_id=<v> value=` | 実行先ホスト(SSH 設定の Host 別名可)。ローカル実行の slot では列ごと省略できる |
| user | string | No(列は host と対で置く) | 列があるとき、host と両方空ならローカル実行。user だけ空は違反 | `error: user is empty line=N job_id=<v> value=` | 実行ユーザー。ローカル実行の slot では列ごと省略できる |
| work_dir | string | Yes | 絶対パス | `error: work_dir is not absolute line=N job_id=<v> value=<v>` | 作業ディレクトリ(実行先側) |
| script | string | Yes | 絶対パス(`^/`) | `error: script is not absolute line=N job_id=<v> value=<v>` | 実装スクリプトパス(実行先側。存在確認はしない) |
| fixed_params | string | Yes | JSON 配列(文字列要素のみ)。空は `[]` | `error: fixed_params is not a json array of strings line=N job_id=<v> value=<v>` | 固定引数(二重引用符で囲んだ CSV セル) |
| hang_detect_limit_minutes | integer | Yes | `^[0-9]+$` | `error: hang_detect_limit_minutes is not a non-negative integer line=N job_id=<v> value=<v>` | ハング検知上限(分)。0 = 検知対象外。導入時 60 |
| credential_ref | string | No(末尾の任意列。空可) | `^[A-Za-z0-9_.-]*$`。`/` を含む・`BEGIN` を含むは warn | `warn: credential_ref looks like a secret or path line=N job_id=<v>` | 認証情報参照名。値は書かない |
| map_version | string | No(末尾の任意列。空可) | ファイル内で単一を推奨 | `warn: mixed map_version values=<a>,<b>` | マップ版。execution-spec.json の `slots.<role>.map_version` に転記(列が無ければ `null`) |

- **ヘッダー検証**: 必須 5 列(job_id / work_dir / script / fixed_params / hang_detect_limit_minutes)がすべて存在し、host / user は両方あるか両方無いこと。違反は `error: job map header mismatch missing=<col,...> path: <path>`(必須列の欠落、host / user の片方だけ)。上記 9 列以外は `warn: unknown column column=<name> path: <path>`(`impl_version` 列を含む。実装版は feature flag の `BLUE_IMPL` / `GREEN_IMPL` が所有)
- **列数検証**: データ行のセル数がヘッダーと一致しないと `error: column count mismatch line=N expected=<n> actual=<n>`
- **hang_detect_limit_minutes の運用**(条件: ハング検知上限の調整基準): 導入時は全ジョブ 60。foreground で動く slot のファイルは 0。警告傾向(`hang-detect-trend.sh`)を見てジョブごとに調整する。変更は次回以降の run の execution-spec.json にのみ反映される。調整記録(調整日時・調整根拠となる警告時経過時間)は適用構成文書に残す
- **サンプル**(`config/green-job-map.csv.example` として同梱):

```text
job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version
JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[""--mode"",""full""]",60,ssh-key-green,map-v3
JOB002,host-green-01,batch,/var/app/work,/opt/app/bin/job002.sh,"[]",60,ssh-key-green,map-v3
```

ローカル実行の slot(host / user 列なし)の例:

```text
job_id,work_dir,script,fixed_params,hang_detect_limit_minutes
JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",0
```

## 出力契約

- **stdout**(検証 OK 時、固定順):
  ```text
  map_path: /etc/relay-gate/green-job-map.csv
  rows=2
  map_version=map-v3
  ```
  (`map_version` 列が無い・全行空なら `map_version=-`)
  `--verbose` 時は stderr に 1 行 1 job_id で `info: resolved job_id=JOB001 host=host-green-01 user=batch exec=ssh work_dir=/var/app/work script=/opt/app/bin/job001.sh fixed_params=["--mode","full"] hang_detect_limit_minutes=60`(ローカル実行の行は `host=- user=- exec=local`。契約 validate-config.sh stderr の形式)
- **stderr**: 違反ごとに `error:` 1 行(全件、行番号付き)。`warn:` は認証情報らしい値・版の混在・未知列
- **終了コード**:

| コード | 意味 | 条件 |
|-------|------|------|
| 0 | 検証 OK | error 0 件 |
| 2 | 入力・設定検証エラー | 引数不正 / ファイルなし / ヘッダー不一致 / クォート不正 / 列数不一致 / 列検証違反 / job_id 重複 |

## UC ロジック

- **バリデーション**: 上表。全行を検査してから全件報告
- **確認プロンプト**: なし
- **冪等性**: 読み取り専用
- **エラーハンドリング**: ファイルなしは `error: config file not found path: <path>`、終了コード 2
- **クラッシュ耐性**: 副作用なし
- **CSV セルの解析**: 上記クォート解析規則。runner の解決関数と同じ実装を共有する
- **JSON 配列の判定**(仮採用、jq 非依存): クォート解除後のセルが先頭 `[` 末尾 `]`、要素は `"..."`(エスケープ `\"` `\\` `\/` `\n` `\t` を許可)をカンマ区切り。ネストした配列・オブジェクト・数値・真偽値は非対応(違反)。runner の解決関数と同じ実装を共有する

## データモデル変更

RDB テーブルは触らない(`tables: []`)。

### ファイル: `<slot>-job-map.csv`(情報: ジョブマップ + ハング検知上限設定)

上記「設定契約」の必須 5 列 + 任意 4 列。変更種別はすべて「追加」。arch E-003 の `fixed_params` は JSON 配列を格納する CSV セル。E-004(ハング検知上限設定)は `hang_detect_limit_minutes` 列のみ。調整記録(調整日時・調整根拠)はジョブマップ列に含めず、情報「適用構成文書」の属性「運用者の調整記録」に置く。実装版はジョブマップに持たない(feature flag の `BLUE_IMPL` / `GREEN_IMPL`)。

## ビジネスルール

- 実行先とハング検知上限は該当 slot のジョブマップが所有する。実装版は所有しない(条件: 設定所有区分)
- JOB_ID の行があるときのみ解決できる。job_id は一意。列はヘッダー名で対応付け、host / user は両方空でローカル実行(条件: ジョブマップ解決条件)
- 固定引数は JSON 配列で引数の数と空白・カンマを維持する。空は `[]`(条件: 引数連結規則)
- 認証情報は参照名で指定する(条件: 認証情報の非保存)
- hang_detect_limit_minutes は導入時 60、foreground role は 0、調整は次回以降の run に反映(条件: ハング検知上限の調整基準)

## ティア完了条件(BDD)

```gherkin
Feature: slot ごとのジョブマップを定義する - facade / slot runner ティア

  Scenario: validate-config_sh_job-map は有効な CSV に終了コード 0 と集計を返す
    Given 一時ファイル map.csv に契約どおりのヘッダー(9 列)と 2 行(JOB001 hang_detect_limit_minutes=60、JOB002 hang_detect_limit_minutes=0、map_version=map-v3)を書く
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 0 で stdout は "map_path: <path>" "rows=2" "map_version=map-v3" の 3 行である

  Scenario: validate-config_sh_job-map は元資料の 7 列だけのヘッダーを警告なしで受け付ける
    Given map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 0 で stdout に "map_version=-" が出て、stderr に "warn: unknown column" は出ない

  Scenario: validate-config_sh_job-map は列順が入れ替わったヘッダーを受け付ける
    Given map.csv のヘッダーが "host,job_id,user,script,work_dir,fixed_params,hang_detect_limit_minutes,credential_ref,map_version" の順である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 0 である

  Scenario: validate-config_sh_job-map は host / user 列の無いローカル実行用 CSV を受け付ける
    Given map.csv のヘッダーが "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" で、行 'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",0' がある
    When `validate-config.sh --job-map map.csv --verbose` を実行する
    Then 終了コード 0 で stderr に "info: resolved job_id=JOB001 host=- user=- exec=local" で始まる行が出る

  Scenario: validate-config_sh_job-map は二重化された引用符を含む fixed_params セルを解析する
    Given map.csv の JOB001 行の fixed_params セルが '"[""p2 p3"",""a,b""]"' である
    When `validate-config.sh --job-map map.csv --verbose` を実行する
    Then 終了コード 0 で stderr に 'info: resolved job_id=JOB001' と 'fixed_params=["p2 p3","a,b"]' を含む行が出る

  Scenario: validate-config_sh_job-map は fixed_params の不正を行番号付きで拒否する
    Given map.csv の 3 行目(JOB003)の fixed_params セルが '"p1,p2"' である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: fixed_params is not a json array of strings line=3 job_id=JOB003 value=p1,p2" が出る

  Scenario: validate-config_sh_job-map は閉じていない引用符を拒否する
    Given map.csv の 2 行目の fixed_params セルが '"[""p1""]' で閉じ引用符が無い
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: csv quote is invalid line=2 path: map.csv" が出る

  Scenario: validate-config_sh_job-map は job_id の重複を拒否する
    Given map.csv の 2 行目と 5 行目が job_id=JOB001 である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: duplicate job_id job_id=JOB001 lines=2,5" が出る

  Scenario: validate-config_sh_job-map は必須列の欠落を拒否する
    Given map.csv のヘッダーに script 列が無い
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: job map header mismatch missing=script path: map.csv" が出る

  Scenario: validate-config_sh_job-map は host と user の片方だけの列を拒否する
    Given map.csv のヘッダーが "job_id,host,work_dir,script,fixed_params,hang_detect_limit_minutes" で user 列が無い
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: job map header mismatch missing=user path: map.csv" が出る

  Scenario: validate-config_sh_job-map は host と user の片方だけが空の行を拒否する
    Given map.csv の 2 行目(JOB001)の host が空で user が batch である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: host is empty line=2 job_id=JOB001 value=" が出る

  Scenario: validate-config_sh_job-map は列数不一致を拒否する
    Given map.csv の 2 行目が 8 セル(ヘッダーは 9 列)である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: column count mismatch line=2 expected=9 actual=8" が出る

  Scenario: validate-config_sh_job-map は impl_version 列を未知列として warn で報告する
    Given map.csv のヘッダー末尾に impl_version 列がある
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 0 で stderr に "warn: unknown column column=impl_version path: map.csv" が出る

  Scenario: validate-config_sh_job-map は credential_ref のパス形式を warn で報告する
    Given map.csv の JOB001 行の credential_ref が /home/batch/.ssh/id_green である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 0 で stderr に "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" が出る
```
