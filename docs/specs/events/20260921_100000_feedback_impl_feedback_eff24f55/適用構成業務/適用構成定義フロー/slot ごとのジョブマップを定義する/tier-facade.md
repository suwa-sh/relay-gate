# slot ごとのジョブマップを定義する - facade / slot runner ティア仕様

## 変更概要

slot ジョブマップ(CSV)の列定義・CSV セルのクォート解析規則・検証ルールを **設定契約** として定義し、`validate-config.sh --job-map <path>` の usecase / domain(検証表)を新規実装する。CSV 読み込み関数(repository)は UC「ジョブマップで JOB_ID から実行先を解決する」と共有する。設定ファイル共通の「入力の守備範囲」(バイト・行・構造の異常の扱い、読み込み中の差し替えに対する保証、検証器の内部障害)は CLI 契約 `config_input_rules` を正本とし、本 UC はその適用先の第 1 号として BDD で判定する。

## 実装の前提

- **bash の最低版**: 5.0(CLI 契約 `conventions.runtime_prerequisites`。インフラ設計の「bash 5」と同じ値)。連想配列などを使ってよい
- **性能**: 1 ファイルあたりの想定最大行数・内容の最悪条件・応答時間の目標は NFR B.1.1.2 / B.2.1.1 の共通前提(`docs/nfr/latest/nfr-grade.yaml`)を参照する。本 UC は数値を再定義しない。行数に比例する時間で処理できる実装(job_id 重複検査・map_version 集計を全組合せ比較にしない)を前提とする
- **外部コマンド**: セルの解析は bash 単独で行う。行単位の外部コマンド利用(`sort` による重複検査、`grep` による候補行の絞り込み、`tr` / `sed` によるバイト点検)は許容する(CLI 契約 `conventions.runtime_prerequisites.external_commands`)

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
- **形式**: CSV(カンマ区切り)。1 行目はヘッダー行(列はヘッダー名で対応付ける。順序は元資料の並び `job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes` を推奨するが検証は名前で行う)。行頭 `#` の行と空行(0 バイトの行)は無視。改行コードは LF。セル内に改行は置けない。文字コード UTF-8。1 ファイル 1 slot。形式から外れた入力(NUL バイト・不正な文字コード・BOM・CR・ヘッダー列名の重複)の扱いは下記「入力の守備範囲」
- **CSV セルのクォート解析規則**(条件: ジョブマップ解決条件): セルはカンマ区切り。セルは二重引用符で囲める(囲まない場合はカンマ・二重引用符を含められない)。囲んだセル内の二重引用符は `""` と二重化する。`fixed_params` は JSON 配列文字列を格納するセルで、必ず二重引用符で囲む(例: `"[""p1"",""p2 p3""]"` → 固定引数 `p1` と `p2 p3` の 2 要素。空は `"[]"` または `[]`)。bash 単独(外部 CSV パーサ非依存)で 1 文字ずつ状態機械で解析できる範囲に限定する(ネスト・複数行セル不可。これは形式の制約で、行単位の外部コマンド利用は禁じない)。閉じ引用符が無い・囲み外に二重引用符がある行は `error: csv quote is invalid line=N path: <path>`。セルの値に含まれるタブ・ESC などの制御文字(改行・CR・NUL 以外)は値の一部として受理し、出力時に可視表記へ置き換える(`ui-design.md`「制御文字の表記」)
- **設定所有区分**: 実行先とハング検知上限の正本。runner・mode・実装版(feature flag)、比較対象(クロスチェックジョブマップ)は置かない

| 列 | 型 | 必須 | 検証 | 違反時 stderr(行番号・job_id 付き) | 説明 |
|---|---|---|---|---|---|
| job_id | string | Yes | `^[A-Za-z0-9_-]+$`、ファイル内で一意 | `error: job_id is invalid line=N job_id=<v> value=<v>` / `error: duplicate job_id job_id=<v> lines=<n1,n2,...>`(2 回目以降の行番号をカンマ区切りで全部) | JOB_ID |
| host | string | No(列は user と対で置く) | 列があるとき、user と両方空ならローカル実行。host だけ空は違反 | `error: host is empty line=N job_id=<v> value=` | 実行先ホスト(SSH 設定の Host 別名可)。ローカル実行の slot では列ごと省略できる |
| user | string | No(列は host と対で置く) | 列があるとき、host と両方空ならローカル実行。user だけ空は違反 | `error: user is empty line=N job_id=<v> value=` | 実行ユーザー。ローカル実行の slot では列ごと省略できる |
| work_dir | string | Yes | 非空のみ(パスの形式は検査しない) | `error: work_dir is empty line=N job_id=<v> value=` | 作業ディレクトリ(実行先側)。Linux 形式(`/var/app/work`)/ Windows 形式(`G:\scripts`。ドライブ文字 + バックスラッシュ)/ 相対パス(`./beam-batches`)のどれでも受理する。理由: ジョブマップは Windows / Linux 両対応のフルパス / 相対パス指定を受け取れる必要がある(利用者決定 2026-09-22。方針資料のジョブマップ例)。relay-gate はパスを解釈も正規化もせず実行先へそのまま渡す |
| script | string | Yes | 非空のみ(パスの形式は検査しない) | `error: script is empty line=N job_id=<v> value=` | 実装スクリプトパス(実行先側。存在確認はしない)。work_dir と同じく形式は実行先の OS・シェルが解釈する |
| fixed_params | string | Yes | JSON 配列(文字列要素のみ)。空は `[]` | `error: fixed_params is not a json array of strings line=N job_id=<v> value=<v>` | 固定引数(二重引用符で囲んだ CSV セル) |
| hang_detect_limit_minutes | integer | Yes | `^[0-9]+$` | `error: hang_detect_limit_minutes is not a non-negative integer line=N job_id=<v> value=<v>` | ハング検知上限(分)。0 = 検知対象外。導入時 60 |
| credential_ref | string | No(末尾の任意列。空可) | `^[A-Za-z0-9_.-]*$`。`/` を含む・`BEGIN` を含むは warn | `warn: credential_ref looks like a secret or path line=N job_id=<v>` | 認証情報参照名。値は書かない |
| map_version | string | No(末尾の任意列。空可) | ファイル内で単一を推奨 | `warn: mixed map_version values=<a>,<b>` | マップ版。execution-spec.json の `slots.<role>.map_version` に転記(列が無ければ `null`) |

- **ヘッダー検証**: 必須 5 列(job_id / work_dir / script / fixed_params / hang_detect_limit_minutes)がすべて存在し、host / user は両方あるか両方無いこと。違反は `error: job map header mismatch missing=<col,...> path: <path>`(必須列の欠落、host / user の片方だけ)。上記 9 列以外は `warn: unknown column column=<name> path: <path>`(`impl_version` 列を含む。実装版は feature flag の `BLUE_IMPL` / `GREEN_IMPL` が所有)
- **列数検証**: データ行のセル数がヘッダーと一致しないと `error: column count mismatch line=N expected=<n> actual=<n>`(空白だけの行も 1 セルのデータ行としてこの違反になる)
- **入力の守備範囲**(CLI 契約 `config_input_rules` が正本。本 UC は値を複写せず、判定する BDD を持つ)。原則: 形式(UTF-8 / LF / 1 行目ヘッダー)から外れた入力は拒否する(終了コード 2)。形式の内側の値はそのまま受理する。「警告して受理」は設けない

| 論点 | 扱い | stderr(終了コード) |
|---|---|---|
| NUL バイト(コメント行を含む) | 拒否 | `error: nul byte is not allowed line=N path: <path>`(2) |
| UTF-8 として不正なバイト列(コメント行を含む) | 拒否 | `error: encoding is not utf-8 line=N path: <path>`(2) |
| BOM | 拒否 | `error: byte order mark is not allowed line=1 path: <path>`(2) |
| CR(CRLF 改行・行末 CR・セル内 CR) | 拒否 | `error: carriage return is not allowed line=N path: <path>` + `hint: use LF line endings`(2) |
| 最終行の改行なし | 受理(例外) | なし |
| 空白だけの行 | 拒否 | `error: column count mismatch line=N expected=<n> actual=1`(2) |
| 空のファイル・コメントだけ | 拒否 | `error: job map header mismatch missing=job_id,work_dir,script,fixed_params,hang_detect_limit_minutes path: <path>`(2) |
| データ行 0 件(ヘッダーだけ) | 受理(例外) | なし。stdout `rows=0` |
| ヘッダー列名の重複 | 拒否 | `error: duplicate column column=<name> path: <path>`(2) |
| 行・セルの長さ | 上限なし | なし |
| 5,000 行超 | 対象外(拒否しない。NFR の性能保証の範囲外) | なし |
| 非 ASCII の値・空白とカンマを含む固定引数・Windows 形式や相対パスの work_dir / script | 値として受理 | なし |

- **読み込み中の差し替えに対する保証**(`config_input_rules.snapshot`): 検証結果は検証開始時の 1 時点のファイル内容だけに基づく。旧内容と新内容を混ぜた結果を返さない。差し替えは検知も報告もしない。実現: 検証開始時に入力を一時ファイルへ 1 回だけ複製し、バイト点検と解析は複製だけを読む。置き場所は `TMPDIR`(未設定なら `/tmp`)、ファイル名は `relay-gate-` で始まり、作業名(末尾 `.part`。mktemp で作るのはこの作業名)へ書き終えてから最終名へ rename する(最終名は rename までディレクトリに存在させない。最終名が現れた時点で複製は完了)、権限 0600、成功・失敗を問わず読み込み後に削除、HUP / INT / TERM 受信時は削除して終了コード 129 / 130 / 143。出力の `map_path:` / `path:` には利用者が指定したパスを出す。SIGKILL で複製が残り得ること、意図的な関数・コマンドの差し替えは対象外
- **検証器の内部障害**(`config_input_rules.internal_failure`): 複製の工程(一時ファイルの作成・複製先への書き込み・最終名への rename)で起きた失敗はコマンド名を問わず `error: config snapshot failed path: <path>` + `hint: check TMPDIR is writable`、複製完了後の補助コマンド(tr / sed / sort / cat 等)の失敗は `error: internal command failed commands=<name,...> path: <path>`。いずれも終了コード 6 で、stdout を出さず、検証 OK も違反も返さない(他の error / warn 行も出さない)
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

方針資料のジョブマップ例(非 ASCII のホスト名、Windows 形式のパス、相対パス。いずれも検証 OK で、表示も変わらない):

```text
job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes
TOMM0410010100,督促AP,saiken,G:\scripts,G:\scripts\xxx.bat,"[""param1"",""param2"",""param3""]",60
```

```text
job_id,work_dir,script,fixed_params,hang_detect_limit_minutes
TOMM0410010100,./beam-batches,./beam-batches/TOMM0410010100.sh,"[""param1"",""param2"",""param3""]",60
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
- **stderr**: 違反ごとに `error:` 1 行(全件、行番号付き)。`warn:` は認証情報らしい値・版の混在・未知列。`value=` / `column=` / `path:` に出す任意入力(セルの値・列名・パス)は `ui-design.md`「制御文字の表記」の可視表記にする(改行 `\n`、タブ `\t`、その他の制御文字 `\u00XX`。バックスラッシュは置き換えない。`key=value` / `key: value` の選択は元の値で判定)。`--verbose` の `fixed_params=[...]` だけは JSON の文字列規則でエスケープする
- **終了コード**:

| コード | 意味 | 条件 |
|-------|------|------|
| 0 | 検証 OK | error 0 件(データ行 0 件も OK) |
| 2 | 入力・設定検証エラー | 引数不正 / ファイルなし / 入力の守備範囲の違反(NUL・不正な文字コード・BOM・CR)/ ヘッダー不一致 / ヘッダー列名の重複 / クォート不正 / 列数不一致 / 列検証違反 / job_id 重複 |
| 6 | 実行エラー | 検証器の内部障害(入力の複製の失敗、補助コマンドの失敗)。stdout なし、error 行 1 つ(+ hint)だけ |

## UC ロジック

- **バリデーション**: (1) 入力の複製(単一スナップショット)→ (2) バイト点検(NUL / UTF-8 / BOM / CR。行番号を記録)→ (3) ヘッダー(必須列・host / user の対・列名の重複・未知列)→ (4) 行ごと(クォート・列数・列の値)→ (5) job_id 重複 → (6) 集計。全行を検査してから全件報告。(1)(2)(5) の補助コマンドが失敗したら以降を行わず終了コード 6
- **確認プロンプト**: なし
- **冪等性**: 読み取り専用(一時ファイルは TMPDIR 配下に作り、終了時に削除する)
- **エラーハンドリング**: ファイルなしは `error: config file not found path: <path>`、終了コード 2。内部障害は終了コード 6(上表)
- **クラッシュ耐性**: 副作用なし(HUP / INT / TERM 受信時は一時ファイルを削除して 129 / 130 / 143)
- **CSV セルの解析**: 上記クォート解析規則。runner の解決関数と同じ実装を共有する。読み込み中の差し替えに対する保証(1 時点の内容だけで判定)は runner 側も同じ(実現手段は縛らない)
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

  Scenario: validate-config_sh_job-map は方針資料の Windows 形式パスと非 ASCII の値を受理し表示を変えない
    Given map.csv がヘッダー "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" と行 'TOMM0410010100,督促AP,saiken,G:\scripts,G:\scripts\xxx.bat,"[""param1"",""param2"",""param3""]",60' である
    When `validate-config.sh --job-map map.csv --verbose` を実行する
    Then 終了コード 0 で stdout に "rows=1" が出る
    And stderr に 'info: resolved job_id=TOMM0410010100 host=督促AP user=saiken exec=ssh work_dir=G:\scripts script=G:\scripts\xxx.bat fixed_params=["param1","param2","param3"] hang_detect_limit_minutes=60' が出る
    And stderr に "error:" で始まる行は出ない

  Scenario: validate-config_sh_job-map は方針資料の相対パスを受理する
    Given map.csv がヘッダー "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" と行 'TOMM0410010100,./beam-batches,./beam-batches/TOMM0410010100.sh,"[""param1""]",60' である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 0 で stdout に "rows=1" が出て、stderr に "error:" で始まる行は出ない

  Scenario: validate-config_sh_job-map は work_dir が空の行を拒否する
    Given map.csv の 2 行目(JOB001)の work_dir セルが空である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: work_dir is empty line=2 job_id=JOB001 value=" が出る

  Scenario: validate-config_sh_job-map はデータ行 0 件のジョブマップを受理する
    Given map.csv がヘッダー行 "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" とコメント行 "# empty" だけである
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 0 で stdout は "map_path: <path>" "rows=0" "map_version=-" の 3 行である

  Scenario: validate-config_sh_job-map は最終行に改行が無くても読む
    Given map.csv の最終行 'J1,/w,/s,"[]",60' の後に改行が無い
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 0 で stdout に "rows=1" が出る

  Scenario: validate-config_sh_job-map は NUL バイトを含む行を拒否する
    Given map.csv の 2 行目の job_id セルが J<NUL>2(NUL バイトを含む)である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: nul byte is not allowed line=2 path: map.csv" が出る
    And stderr に "csv quote is invalid" を含む行は出ない

  Scenario: validate-config_sh_job-map は UTF-8 として不正なコメント行を拒否する
    Given map.csv の 2 行目が Shift_JIS で符号化したコメント行 "# 督促" で、3 行目が有効なデータ行である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: encoding is not utf-8 line=2 path: map.csv" が出る

  Scenario: validate-config_sh_job-map は BOM 付きファイルを拒否する
    Given map.csv の先頭 3 バイトが EF BB BF で、続いて有効なヘッダーとデータ行がある
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: byte order mark is not allowed line=1 path: map.csv" が出る
    And stderr に "job map header mismatch" を含む行は出ない

  Scenario: validate-config_sh_job-map は CRLF 改行を拒否する
    Given map.csv の全行が CRLF で終わる(ヘッダーと 1 データ行)
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: carriage return is not allowed line=1 path: map.csv" と "error: carriage return is not allowed line=2 path: map.csv" と "hint: use LF line endings" が出る

  Scenario: validate-config_sh_job-map は空白だけの行を列数不一致として拒否する
    Given map.csv の 2 行目が半角空白 3 つだけで、ヘッダーは 5 列である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: column count mismatch line=2 expected=5 actual=1" が出る

  Scenario: validate-config_sh_job-map はヘッダー列名の重複を拒否する
    Given map.csv のヘッダーが "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,job_id" である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: duplicate column column=job_id path: map.csv" が出る

  Scenario: validate-config_sh_job-map は検証中にファイルが差し替わっても 1 時点の内容だけで判定する
    Given map.csv のデータ行が 'J1,/old,/s,"[]",60' である
    And 検証コマンドが入力を複製した直後に、job_id に NUL バイトを含む行 'J<NUL>2,/new,/s,"[]",60' を持つ新しいファイルを mv で map.csv のパスへ置き換える(テストは TMPDIR 配下に最終名の一時ファイル(接頭辞 relay-gate-、末尾 .part の付かないもの)が現れたことを監視して置き換えのタイミングを決める。最終名が現れた時点で複製は完了している(契約 config_input_rules.snapshot.validate_config))
    When `validate-config.sh --job-map map.csv --verbose` を実行する
    Then 終了コード 0 で stderr に "info: resolved job_id=J1" と "work_dir=/old" を含む行が出る
    And stdout の "map_path:" は map.csv のパスで、TMPDIR 配下のパスは stdout / stderr に出ない
    And 終了後に TMPDIR 配下に relay-gate の一時ファイルは残っていない

  Scenario: validate-config_sh_job-map は一時ファイルを作れないとき終了コード 6 で終える
    Given TMPDIR が書き込めないディレクトリを指している
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 6 で stderr に "error: config snapshot failed path: map.csv" と "hint: check TMPDIR is writable" が出る
    And stdout は 0 行である

  Scenario: validate-config_sh_job-map は補助コマンドの失敗を検証結果にしない
    Given 検証器が複製完了後に実際に呼ぶ補助コマンドのうち 1 つ(実装が使うコマンド。例: 重複検査に sort を使う実装なら sort、バイト点検の tr)を、テストが PATH の先頭に置いた「常に終了コード 1 で終わる代替」に差し替える(テスト fixture は実装が呼ぶコマンド名に合わせる。連想配列だけで重複検査する実装ならバイト点検のコマンドを差し替える)
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 6 で stderr に "error: internal command failed commands=<差し替えたコマンド名> path: map.csv" が出る
    And stdout は 0 行で、stderr に "error:" で始まる行はその 1 行だけである

  Scenario: validate-config_sh_job-map は値に含まれる制御文字を可視表記で出力する
    Given map.csv のヘッダー末尾に列名 "note<ESC>[31m"(ESC を含む)があり、JOB001 行の hang_detect_limit_minutes が "6<TAB>0" である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に 'warn: unknown column column=note\u001b[31m path: map.csv' と 'error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=6\t0' が出る
    And stderr のどの行にも生の ESC・タブは含まれない
```
