# feature flag を設定する - facade / slot runner ティア仕様

## 変更概要

feature flag 設定(env)の 9 キーと任意の 2 キー(slot ジョブマップの場所)の定義・検証ルールを **設定契約** として定義し、`validate-config.sh --feature-flag <path>` の presentation / usecase / domain(検証表)/ repository(env 読み込み)を新規実装する。facade.sh は同じ repository と domain を `source` して起動時検証に使う(検証ロジックの二重化を防ぐ)。

## コマンド契約

### validate-config.sh --feature-flag

- **書式**: `validate-config.sh --feature-flag <path> [--verbose]`
- **アクセス権**: 基盤適用設計者の直接起動(relay-gate 配置ディレクトリの実行権限)。読み取りのみで副作用なし

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| --feature-flag | string(パス) | Yes(この検証種別を選ぶ) | なし | 検証する env ファイル。`--job-map` / `--rapid-crosscheck` / `--final-crosscheck` / `--housekeep` と排他(同時指定は終了コード 2) |
| --verbose | boolean | No | false | 読み取ったキーごとに `info: key loaded key=<KEY> path: <path>` を stderr に出す(キーごとの検査の段(契約 config_input_rules.env_files の (iii))へ進んだ回だけ。バイト・改行の検査または行の構造の検査で止めた回は出さない。正本は CLI 契約 `config_input_rules.env_files` の「validate-config.sh の --verbose の info 行」。`--rapid-crosscheck` / `--final-crosscheck` / `--housekeep` と同じ規則) |
| --help | boolean | No | false | 使い方を stdout に出して終了コード 0 |

- **stdin**: なし

## 設定契約(feature flag env)

- **所在**: `$RELAY_GATE_CONFIG_DIR/feature-flag.env`(facade.sh が起動のたびに読む。仮採用: _inference.md #5)
- **形式**: 1 行 1 キー `KEY=value`。行の前後の空白(半角空白とタブ)を除いた結果が `#` で始まる行はコメント(字下げしたコメント行を含む。`KEY=#abc` はコメントではなく値 `#abc`)、0 バイトの空行は無視。コメント行の定義は CLI 契約 `config_input_rules.env_files` に従う。値のクォートは不要。キーと値の分け方、キー・値の前後の空白の除き方、値の先頭末尾の引用符の外し方は、この順序を含めて CLI 契約 `config_input_rules.env_files` の規則に従う。シェル変数展開・コマンド置換は行わない(`source` しない。`grep` / `cut` で読む)。文字コード UTF-8、改行 LF。形式から外れた入力(NUL バイト・UTF-8 として不正なバイト列・BOM・CR・`=` を含まない行・キーの前後の空白を除いた結果キーが空になる行・同じキーが 2 行以上ある設定)の拒否(終了コード 2。文言は契約と同文。同じキーの重複は `error: duplicate key key=<KEY> lines=<n1,n2,...> path: <path>` で、どちらの行の値も使わない)、読み込みは 1 時点の内容だけで判定する保証、補助コマンドの失敗(終了コード 6)は CLI 契約 `config_input_rules`(`env_files`)に従う(値は複写しない)。CR を黙って落として受理しない
- **設定所有区分**: feature flag が所有するのは下表の 9 キー(元の方針資料の設定契約と同じ)と、slot ジョブマップの場所を書く任意の 2 キー(`BLUE_JOB_MAP_CSV` / `GREEN_JOB_MAP_CSV`。利用者決定 2026-11-16)だけ。設定版は持たない
- **値を取り込むキーの範囲**: feature-flag.env から値を取り込むのは下表の 9 キーと任意の 2 キーだけ。そのどちらでもないキー(未知キーと `FINAL_` で始まるキー)は、値をプロセスの変数・環境変数へ取り込まず、キー名を warn・error 行(と `--verbose` の info 行)の表示と重複の判定に使うだけ。この規則は検証コマンドだけでなく、feature-flag.env を読むすべての処理(facade.sh などの実行時の読み手)に及ぶ。正本は CLI 契約 `config_input_rules.env_files` の「feature-flag.env から値を取り込むキーの範囲」
- **読み取りの途中の一時的な保持**: 「取り込む」は、キーに対応する変数・環境変数へ値を載せることを指す。ファイルを読む途中に、行の内容(9 キーと任意の 2 キーのどちらでもないキーの値を含む)を作業用の領域へ置くことは、次の 3 条件をすべて満たせば取り込みに当たらない。作業用の領域の変数の名前は実装が固定で決め、ファイルに書かれたキー名から決めない(キー名から名前を決めた変数は作業用の領域に当たらない。例: 9 キーと任意の 2 キーのどちらでもないキーの値を、そのキーと同じ名前の変数へ代入する場合)。読み取りは、行・キー・値を取り出し、読み手が使うキーの値(検証コマンドでは 9 キーと任意の 2 キーのすべて)をキーに対応する変数へ載せ終えるまでを指す(キーごとの検査と runner への問い合わせは読み取りの後)。検証コマンドと実行時の読み手に同じく及ぶ。正本は CLI 契約 `config_input_rules.env_files` の「読み取りの途中の一時的な保持」
  1. 作業用の領域を環境変数にしない(子プロセスへ渡らない)
  2. 読み終えたとき(設定値を使う処理を始める前)と失敗したときに、読み手が取り込まないキーの値を置いた作業用の領域を空にする
  3. 読み取りの後まで残すのは、9 キーと任意の 2 キーのどちらでもないキーについてはキー名だけ

| キー | 型 | 必須 | 値 | 検証 | 説明 |
|---|---|---|---|---|---|
| BLUE_MODE | enum | Yes | foreground / background / off | 列挙外は `error: invalid value key=BLUE_MODE value=<v>` + `hint: use foreground, background or off` | blue slot の実行モード |
| GREEN_MODE | enum | Yes | foreground / background / off | 列挙外は `error: invalid value key=GREEN_MODE value=<v>` + `hint: use foreground, background or off` | green slot の実行モード |
| RAPID_CROSSCHECK_MODE | enum | Yes | foreground / background / off | 列挙外は `error: invalid value key=RAPID_CROSSCHECK_MODE value=<v>` + `hint: use foreground, background or off` | 速報クロスチェックの制御。off 以外(foreground / background)は runner が完了通知を送信し速報管理 DB へ書き込む。off は完了通知を送信せず速報管理 DB へ接続も書込みもしない(parallel_run も作らない) |
| BLUE_IMPL | string(非空) | BLUE_MODE≠off のとき Yes | 任意の文字列 | 欠落・空は `error: option required option=BLUE_IMPL path: <path>` | blue の実装版。execution-spec.json の `slots.blue.impl_version` の出所 |
| GREEN_IMPL | string(非空) | GREEN_MODE≠off のとき Yes | 任意の文字列 | 欠落・空は `error: option required option=GREEN_IMPL path: <path>` | green の実装版。`slots.green.impl_version` の出所 |
| BLUE_RUNNER | path | BLUE_MODE≠off のとき Yes | 絶対パスまたは相対パス | 欠落・空は `error: option required option=BLUE_RUNNER path: <path>`。解決後のパスに実体が存在しない / 実行権限なしは `error: file not executable key=BLUE_RUNNER path=<解決後のパス>` | blue slot runner 実体 |
| GREEN_RUNNER | path | GREEN_MODE≠off のとき Yes | 絶対パスまたは相対パス | 同上(key=GREEN_RUNNER) | green slot runner 実体 |
| RAPID_CROSSCHECK_RUNNER | path | RAPID_CROSSCHECK_MODE≠off のとき Yes | 絶対パスまたは相対パス | 同上(key=RAPID_CROSSCHECK_RUNNER) | slot runner が完了通知(blue-completed / green-completed)を送る速報クロスチェック runner の実体 |
| RAPID_CROSSCHECK_WORKER | path | RAPID_CROSSCHECK_MODE≠off のとき Yes | 絶対パスまたは相対パス | 同上(key=RAPID_CROSSCHECK_WORKER) | 速報クロスチェック worker の実体(ジョブスケジューラの worker ジョブ定義 / 常駐起動が参照する実体) |
| BLUE_JOB_MAP_CSV | path | No(任意) | 絶対パスまたは相対パス。無い・空なら `$RELAY_GATE_CONFIG_DIR/blue-job-map.csv` | BLUE_MODE≠off のとき、決めた場所に何も無いは `error: job map not found slot=blue map=<決めた場所>`、あるが読めない・通常のファイルでない(ディレクトリなど)は `error: config file is not readable path: <決めた場所>`。キーが無い・値が空は違反にも warn にもしない | blue の slot ジョブマップの場所 |
| GREEN_JOB_MAP_CSV | path | No(任意) | 絶対パスまたは相対パス。無い・空なら `$RELAY_GATE_CONFIG_DIR/green-job-map.csv` | 同上(GREEN_MODE≠off のとき。slot=green) | green の slot ジョブマップの場所 |

- **slot ジョブマップの場所**: 上表の `BLUE_JOB_MAP_CSV` / `GREEN_JOB_MAP_CSV` は任意のキーで、この 2 キーを書かない 9 キーだけの設定はそのまま通る。規則の正本は CLI 契約 `config_files.feature-flag.env.job_map_location` で、下表はその要約(実装は契約の節だけに従う)。値からパスを決める規則は、次項の runner / worker の 4 キーと同じ 1 つの規則(`runner_path_resolution`)で、本書は規則を持たない

| 場合 | ジョブマップの場所 | stdout の `<slot>_job_map` |
|---|---|---|
| キーがあり値が空でない(絶対パス) | 値のまま | 値のまま |
| キーがあり値が空でない(相対パス) | その feature-flag.env のあるディレクトリを基準に解決したパス(作業ディレクトリは基準にしない) | 解決後のパス(設定に書いた相対パスのままは出さない) |
| キーが無い、または値が空(`BLUE_JOB_MAP_CSV=` の行を含む) | `$RELAY_GATE_CONFIG_DIR/<slot>-job-map.csv`(検証に渡したファイルのあるディレクトリではない) | 同左 |
| mode が off の slot(キーの有無・値によらない) | 決めない(値を解決せず、所在も検査しない) | `-` |

  - 決めた場所に何も無いときは `error: job map not found slot=<blue|green> map=<決めた場所>`、あるが読めない・通常のファイルでない(ディレクトリなど)ときは全コマンド共通の定型文 `error: config file is not readable path: <決めた場所>`(`slot=` は付かず、`path:` は feature-flag.env のパスではなく決めた場所)。どちらも終了コード 2 で、行の位置は同じ(契約 `error_order` の 6。blue → green)。判定と文言の正本は契約 `job_map_location.presence_report`(ジョブマップの検証・slot runner と同じ考え方)。キーに書いた場所に無ければ、固定の名前のファイルがあっても違反
  - 値の内容(拡張子・ファイル名)は検査しない。blue と green に同じ場所を書いてもよい
  - 2 キーは未知キーではない(`warn: unknown key` を出さない)。同じキーの重複の判定はほかのキーと同じ
  - mode の値が列挙外・欠落・空の slot は「off でない」として、場所を決めて所在を検査する
  - 決めた場所を使う読み手は、feature flag の検証(`validate-config.sh --feature-flag`)、facade.sh(slot runner へ環境変数で渡す)、slot runner(通常起動)の 3 つ。background-rerun.sh と `validate-config.sh --job-map` は決めた場所を使わない(background-rerun.sh は 2 キーを読まず、`--job-map` は渡されたパスをそのまま検証する)。それぞれの扱いは契約 `job_map_location` の `usage` / `readers` を参照する

- **runner / worker の実体パスの解決**: 上表の `BLUE_RUNNER` / `GREEN_RUNNER` / `RAPID_CROSSCHECK_RUNNER` / `RAPID_CROSSCHECK_WORKER` は、絶対パスと相対パスのどちらも受け付ける(元の方針資料の設定例 `BLUE_RUNNER=./blue-runner.sh` の書き方)。規則の正本は CLI 契約 `config_files.feature-flag.env.runner_path_resolution` で、下表はその要約(読むための抜粋。基準が `/` のとき・連続する `/`・値が空のとき・作業ディレクトリの扱いなどの細部は契約の節にだけあり、実装は契約の節だけに従う)

| 項目 | 規則 |
|---|---|
| 相対パスの判定 | 値が `/` で始まらなければ相対パス。`./x`・`x`・`../d/x` は同じ基準で解決する。`~`・環境変数・コマンド置換は展開しない(値は文字のまま) |
| 基準のディレクトリ | その feature-flag.env のあるディレクトリ(渡されたパスの字面のディレクトリ。シンボリックリンクは辿らない)。プロセスの作業ディレクトリは基準にしない。作業ディレクトリは、設定ファイルのパス自体が相対パスのときの絶対化にだけ使う |
| 解決後のパス | 基準のディレクトリ + `/` + 値(`.`・`..` を畳まない)。絶対パスの値はそのまま |
| 解決後のパスを使う場所 | 存在・実行権限の検査、runner への `--help` の問い合わせ、runner の起動、slot runner へ渡す `RAPID_CROSSCHECK_RUNNER`、stdout の `blue_runner:` などの 4 行、error 行の `path=`、warn 行の `runner=` |
| 出さない error 行 | `error: path is not absolute`(この 4 キーでは出さない) |

- **mode の値が列挙外・欠落・空のとき**: その mode は「off でない」として扱う。mode 自体の error 行に加えて、その slot の実装版・runner の必須と実体の検査、対応ジョブマップの検査、runner への `--help` の問い合わせを行う(`RAPID_CROSSCHECK_MODE` なら速報 runner / worker の検査)。上表の「`<SLOT>_MODE≠off` のとき」は、値が `off` と完全一致しないすべての場合を指す。正本は CLI 契約 `config_files.feature-flag.env.validation_rules`

| mode の値 | mode 自体の error 行 | 従属キー・対応ジョブマップ・runner への問い合わせ |
|---|---|---|
| foreground / background | なし | 検査する |
| off | なし | 検査しない |
| 列挙外(例: `parallel`) | `error: invalid value key=<KEY> value=<v>` + hint | 検査する |
| 欠落・空 | `error: option required option=<KEY> path: <path>` | 検査する |

- **組合せ検証**:
  - foreground が 2 個(`BLUE_MODE=foreground` かつ `GREEN_MODE=foreground`)または 0 個 → `error: foreground slot must be exactly one blue_mode=<v> green_mode=<v>`(条件: foreground slot 排他)。`<v>` は読み取った値(列挙外の値もそのまま)で、キーが無い・値が空のときは `-`(CLI 契約 `config_files.feature-flag.env.error_messages`)
  - キー名が `FINAL_` で始まるキー(接頭辞判定。キー名の列挙ではない。大文字小文字を区別。`FINAL_CROSSCHECK_MODE` のような制御キーも final-crosscheck.env のキー `FINAL_DB_CONN_REF` 等の誤配置も同じ)→ 該当キーごとに `error: final crosscheck key is not allowed key=<k>`(条件: 確報クロスチェック非起動)。未知キー warn より先に判定し、`FINAL_` で始まるキーには `warn: unknown key` を出さない。範囲の正本は CLI 契約 `config_files.feature-flag.env.validation_rules`(spec.md の処理フロー・分岐条件一覧と同じ表記)
  - 上記 9 キーと任意の 2 キーのどちらでもなく、`FINAL_` で始まらないキー → `warn: unknown key key=<k> path: <path>`(拒否しない)。9 キーと任意の 2 キーは未知キーとして扱わない
  - 上記 9 キー以外に必須キーは無い(任意の 2 キーは、無くても値が空でも違反にも warn にもならない)
  - foreground の個数は、値が `foreground` と完全一致する slot だけを数える(列挙外・欠落・空の mode は数えない)
- **error 行どうしの順**: キーごとの検査で error 行が 2 行以上出るときの順は、CLI 契約 `config_files.feature-flag.env.error_order` に従う(本書は順を持たない)。上のキー表の並びとは異なる
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
  (未設定の値は `-`。`blue_runner` / `green_runner` / `rapid_crosscheck_runner` / `rapid_crosscheck_worker` には解決後のパスを出す。設定が `BLUE_RUNNER=./blue-runner.sh` で設定ファイルが /etc/relay-gate にあれば `blue_runner: /etc/relay-gate/./blue-runner.sh`(CLI 契約 `config_files.feature-flag.env.runner_path_resolution`)。`blue_job_map` / `green_job_map` には、上記「slot ジョブマップの場所」で決めた場所を出す。設定が `BLUE_JOB_MAP_CSV=./blue-jobs.csv` で設定ファイルが /etc/relay-gate にあれば `blue_job_map: /etc/relay-gate/./blue-jobs.csv`、2 キーを書かなければ例のとおり固定の名前(CLI 契約 `config_files.feature-flag.env.job_map_location`)。runner が `--help` に応答しない場合の `<slot>_runner_if_version` も `-`(問い合わせの待機上限・実行順・未応答判定・準備失敗の扱いは契約 `validate-config.sh` の `runner_help_probe` が正)。15 キー固定順は契約 `cli-command-contract.yaml` の `validate-config.sh` stdout が正。末尾 4 行(blue_job_map / green_job_map / blue_runner_if_version / green_runner_if_version)は UC「slot runner の実体スクリプトを割り当てる」が定義する。mode=off の slot は `<slot>_impl` / `<slot>_runner` / `<slot>_job_map` / `<slot>_runner_if_version` を `-` にする。RAPID_CROSSCHECK_MODE=off では rapid_crosscheck_runner / rapid_crosscheck_worker を `-` にする)
- **stderr**: 違反ごとに `error: ...` 1 行(全件)。`warn:` は未知キー。`hint:` は対処が明確な場合。`--verbose` のときは、キーごとの検査の段(契約 config_input_rules.env_files の (iii))へ進んだ回だけ、読み取ったキーごとに `info: key loaded key=<KEY> path: <path>` を出す(コメント行を除く全キー。未知キー・値が空のキー・`FINAL_` で始まるキーも含む。値は出さない)。行の順は、バイト・改行の検査または行の構造の検査で違反があればその段の error 行(と hint)だけ。無ければ info 行をすべて(キーがファイルに初めて出た順)→ 未知キーの warn 行をすべて(同じ順)→ キーごとの検査の error 行(組合せ検証・`FINAL_` で始まるキー・対応ジョブマップを含む。と hint。error 行どうしの順は CLI 契約 `config_files.feature-flag.env.error_order`)→ runner `--help` 問い合わせの `warn: runner does not respond ...` 行。runner の問い合わせの準備失敗(終了コード 6)の回は、その error 行だけを出す(正本は CLI 契約 `config_input_rules.env_files` の「validate-config.sh の --verbose の info 行」)。`key=` / `value=` / `path:` に出す任意入力(キー名・値・パス)は `ui-design.md`「制御文字の表記」の可視表記にする(改行 `\n`、タブ `\t`、その他の制御文字 `\u00XX`。バックスラッシュは置き換えない。例: 値が `on<ESC>` なら `error: invalid value key=BLUE_MODE value=on\u001b`)。生の制御文字はそのまま出さない
- **実行ログ**(facade.sh が起動のたびに残す行。定義元は UC「slot 実行モードを選択して runner を起動する」): `INFO feature flag loaded blue_mode=... green_mode=... rapid_crosscheck_mode=... blue_impl=... green_impl=... operation_mode=...`。行形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式 `{script} {run_id} {ローカル出力日時} {LEVEL} {message}` に従う。情報「実行ログ」の属性「出力日時」はこの ローカル時刻列に対応する
- **終了コード**:

| コード | 意味 | 条件 |
|-------|------|------|
| 0 | 検証 OK | 違反 0 件(warn はあってもよい) |
| 2 | 入力・設定検証エラー | 引数不正 / ファイルなし・読めない / 上記の検証違反が 1 件以上 |
| 6 | 実行エラー | 入力の複製の失敗 / 補助コマンドの失敗(契約 `config_input_rules.internal_failure`。stdout なし、error 行 1 つ(+ hint)だけ)。runner `--help` 問い合わせの準備(一時ファイルの作成・プロセスグループでの起動)に失敗した。`error: runner probe failed slot=<s> reason=<r>` を出して即時終了(契約 `validate-config.sh` の `runner_help_probe.preparation_failure`。runner の未応答は warn で継続し 6 にしない) |

## UC ロジック

- **バリデーション**: 上記の設定契約。違反は全件収集してから報告する(1 件目で止めない)。ただし検査の段は CLI 契約 `config_input_rules.env_files` に従う: (1) バイト・改行(NUL / UTF-8 / BOM / CR)の違反があればそれだけを報告して止める(ファイル内の全件を行番号の昇順に、同じ行は NUL → UTF-8 → BOM → CR の順に 1 種類 1 行。hint は最後の CR の error 行の次に 1 回。CLI 契約 `config_input_rules.byte_checks`)→ (2) invalid line(行番号の昇順)と同じキーの重複(重複したキーの初出行の昇順)を全件報告し、1 件でもあれば値を使わず (3) を行わない → (3) 上表のキーごとの検査・組合せ検証・未知キーの warn。runner `--help` の問い合わせ規則(待機上限・実行順・未応答判定)は契約 `validate-config.sh` の `runner_help_probe` に従う
- **性能**: 設定ファイルの検査の性能は目標値で、入力の制限でも合否の検査でもない(大きさを理由に拒否・警告せず、目標の時間を超えても終了コード・stdout・stderr は変わらない)。runner の応答待ちは、設定ファイルの検査の目標とは別に数える。数値と位置付けは CLI 契約 `config_input_rules.performance_target` と `runner_help_probe.response_time_budget`(出所は NFR B.1.1.2 / B.2.1.1)を参照し、本 UC は数値を再定義しない
- **確認プロンプト**: なし
- **冪等性**: 読み取り専用。何度実行しても同じ結果
- **エラーハンドリング**: ファイル読み込み失敗は `error: config file not found path: <path>`、終了コード 2。runner `--help` 問い合わせの準備失敗は終了コード 6(上表)
- **クラッシュ耐性**: 副作用が無いため考慮不要
- **facade.sh との共有**: facade.sh は起動時に同じ検証関数で設定を検査し、違反があれば runner を起動せず終了コード 2(UC「slot 実行モードを選択して runner を起動する」)。facade.sh は対応ジョブマップの所在だけは検査せず、キーごとの検査の違反が 2 つ以上あるときは、上記「error 行どうしの順」で最初に出る違反の error 行(hint があれば hint も)だけを出す(CLI 契約 commands「facade.sh」の `config_violation_report`)。validate-config.sh はその検証を事前に単体で実行し、違反を全件確かめる手段
- **runner への受け渡し**: slot runner は feature-flag.env を読まない。facade.sh / background-rerun.sh が読み、runner へ環境変数で渡す(`RAPID_CROSSCHECK_MODE`、off 以外のとき `RAPID_CROSSCHECK_RUNNER`、通常起動では自 slot の `BLUE_IMPL` / `GREEN_IMPL` と、自 slot のジョブマップの場所 `BLUE_JOB_MAP_CSV` / `GREEN_JOB_MAP_CSV`。場所は、キーが無い・値が空のときも既定の場所を渡す。background-rerun.sh と復元起動の runner はジョブマップを読まないため、2 キーを読まず、渡さない。契約は UC「slot runner の実体スクリプトを割り当てる」の runner IF と CLI 契約 `config_files.feature-flag.env.job_map_location`)

## データモデル変更

RDB テーブルは触らない(`tables: []`)。

### ファイル: `feature-flag.env`(情報: feature flag 設定)

上記「設定契約」の 9 キーと任意の 2 キー。変更種別はすべて「追加」。

## ビジネスルール

- foreground はちょうど 1 slot(条件: foreground slot 排他)
- 実装スロットと runner の割当・実装版・速報クロスチェックの制御と実体は feature flag が所有する。実行先・ハング検知上限・比較対象は所有しない(条件: 設定所有区分)
- slot ジョブマップの場所は feature flag が所有する。任意の 2 キーに書かなければ、設定ファイル置き場の固定の名前を使う(条件: 設定所有区分)
- RAPID_CROSSCHECK_MODE が off 以外(foreground / background)のときのみ速報が有効。判定は「off か off 以外か」で行う(条件: 速報クロスチェック有効判定)
- 確報の制御は feature flag に含めない。キー名が `FINAL_` で始まるキーは feature-flag.env に置けない(条件: 確報クロスチェック非起動。範囲は上記「組合せ検証」と CLI 契約 `config_files.feature-flag.env.validation_rules`)

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

  Scenario: validate-config_sh_feature-flag は値に含まれる制御文字を可視表記で出力する
    Given 有効な設定の BLUE_MODE の値を "on<ESC>[0m"(ESC を含む)にする
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に 'error: invalid value key=BLUE_MODE value=on\u001b[0m' が出る(出力規約「制御文字の表記」)
    And stderr のどの行にも生の ESC は含まれない

  Scenario: validate-config_sh_feature-flag は CRLF 改行の設定を拒否する
    Given 有効な設定の全行が CRLF で終わる
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: carriage return is not allowed line=1 path: ff.env" と "hint: use LF line endings" が出る(契約 config_input_rules。CR を黙って落として受理しない)

  Scenario: validate-config_sh_feature-flag はバイト・改行の違反を全件出してキーの検査をしない
    Given ff.env の 1 行目が "BLUE_MODE=foreground" + CR + LF、2 行目が UTF-8 として不正なバイト列を含むコメント行、3 行目が "GREEN_MODE=sideways"(列挙外)+ CR + LF である
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr は "error: carriage return is not allowed line=1 path: ff.env" / "error: encoding is not utf-8 line=2 path: ff.env" / "error: carriage return is not allowed line=3 path: ff.env" / "hint: use LF line endings" の 4 行がこの順に出る
    And stderr に "invalid value" / "option required" を含む行は出ない(バイト・改行の違反で止める)

  Scenario: validate-config_sh_feature-flag は FINAL_ で始まるキーを未知キーではなく終了コード 2 で拒否する
    Given 有効な並行稼働設定に加えて FINAL_DB_CONN_REF=final-db と FINAL_CROSSCHECK_MODE=background を書く
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF" と "error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE" の両方が出る
    And stderr に "warn: unknown key" で始まる行は出ない

  Scenario Outline: validate-config_sh_feature-flag はキーが空の行と KEY=VALUE でない行を invalid line で拒否する
    Given 有効な並行稼働設定の 1 行目の後に <line> の 1 行を挿入した ff.env がある(<SP> は半角空白 1 個に置き換えて書き込む)
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr に "error: invalid line line=2 path: ff.env" が出る(契約 config_input_rules.env_files。読み飛ばさない)

    Examples:
      | line          | note                  |
      | <SP>=abc      | キーが空              |
      | =abc          | キーが空              |
      | <SP>=<SP>     | キーも値も空白だけ    |
      | BLUE_MODE     | = が無い              |
      | <SP><SP>      | 空白だけの行          |

  Scenario Outline: validate-config_sh_feature-flag は前後の空白を除いて # で始まる行をコメントとして読み飛ばす
    Given 有効な並行稼働設定の 1 行目の後に <line> の 1 行を挿入した ff.env がある(<SP> は半角空白 1 個、<TAB> はタブ 1 個に置き換えて書き込む)
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で、stderr に "error:" と "warn: unknown key" で始まる行は出ない(契約 config_input_rules.env_files)

    Examples:
      | line                      | note                           |
      | # x                       | 行頭の #                        |
      | <SP><SP># x               | 半角空白で字下げした #           |
      | <TAB># x                  | タブで字下げした #               |
      | <SP># BLUE_MODE=off       | = を含む字下げしたコメント行     |

  Scenario: validate-config_sh_feature-flag は値の先頭の # をコメントにしない
    Given 有効な並行稼働設定の BLUE_IMPL の行を `BLUE_IMPL=#v1` に置き換えた ff.env がある
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stdout に blue_impl=#v1 が出る(値の先頭の # はコメントにしない)

  Scenario Outline: validate-config_sh_feature-flag は同じキーが 2 行以上ある設定を duplicate key で拒否する
    Given 有効な並行稼働設定(1 行目が BLUE_MODE=foreground)の 1 行目の後に <lines> を挿入した ff.env がある(<lines> の「 と 」は行の区切りで、区切った各行をこの順に 2 行目から 1 行ずつ挿入する。<SP> は半角空白 1 個に置き換えて書き込む)
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stderr の error 行は <errors> だけで、この順に出る(契約 config_input_rules.env_files)
    And stdout は 0 行で、stderr に "error: option required" / "error: invalid value" / "warn: unknown key" で始まる行は出ない(値を使わず、キーごとの検査を行わない)

    Examples:
      | lines                                   | errors                                                                                                   | note                     |
      | BLUE_MODE=foreground                    | "error: duplicate key key=BLUE_MODE lines=1,2 path: ff.env"                                               | 値が同じでも重複         |
      | <SP>BLUE_MODE<SP>=off                   | "error: duplicate key key=BLUE_MODE lines=1,2 path: ff.env"                                               | キーの前後の空白は除く   |
      | BLUE_MODE=                              | "error: duplicate key key=BLUE_MODE lines=1,2 path: ff.env"                                               | 値が空の行も数える       |
      | CONFIG_VERSION=a と CONFIG_VERSION=b    | "error: duplicate key key=CONFIG_VERSION lines=2,3 path: ff.env"                                          | 未知キーも数える         |
      | BLUE_JOB_MAP_CSV=a.csv と BLUE_JOB_MAP_CSV= | "error: duplicate key key=BLUE_JOB_MAP_CSV lines=2,3 path: ff.env"                                    | 任意の 2 キーも数える    |
      | BLUE_MODE=off と BLUE_MODE=background   | "error: duplicate key key=BLUE_MODE lines=1,2,3 path: ff.env"                                             | 3 行は初出行から全部     |
      | BLUE_MODE と BLUE_MODE=off              | "error: invalid line line=2 path: ff.env" と "error: duplicate key key=BLUE_MODE lines=1,3 path: ff.env" | invalid line が先        |

  Scenario: validate-config_sh_feature-flag は大文字小文字の違うキーを重複にしない
    Given 有効な並行稼働設定に加えて blue_mode=off を書く
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stderr に "warn: unknown key key=blue_mode path: ff.env" が出て、"error: duplicate key" で始まる行は出ない(キーの比較は大文字小文字を区別した完全一致)
    And stdout の 2 行目は "blue_mode=foreground" である

  Scenario: validate-config_sh_feature-flag はファイルが無ければ終了コード 2 を返す
    When `validate-config.sh --feature-flag /nonexistent.env` を実行する
    Then 終了コード 2 で stderr に "error: config file not found path: /nonexistent.env" が出る

  Scenario: validate-config_sh_feature-flag は --verbose で info 行をすべて出してから未知キーの warn 行、キーごとの検査の error 行の順に出す
    Given ff.env の 1 行目が ZZ=x、2 行目が BLUE_MODE=off、3 行目が GREEN_MODE=off、4 行目が RAPID_CROSSCHECK_MODE=off である
    When `validate-config.sh --feature-flag ff.env --verbose` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr は次の 6 行がこの順に出る(契約 config_input_rules.env_files)
      | info: key loaded key=ZZ path: ff.env                                     |
      | info: key loaded key=BLUE_MODE path: ff.env                              |
      | info: key loaded key=GREEN_MODE path: ff.env                             |
      | info: key loaded key=RAPID_CROSSCHECK_MODE path: ff.env                  |
      | warn: unknown key key=ZZ path: ff.env                                    |
      | error: foreground slot must be exactly one blue_mode=off green_mode=off |

  Scenario: validate-config_sh_feature-flag は --verbose でも有効な設定の stdout を変えず info 行を出す
    Given ff.env の 1 行目がコメント行 # memo、2 行目が BLUE_MODE=off、3 行目が GREEN_MODE=foreground、4 行目が RAPID_CROSSCHECK_MODE=off、5 行目が GREEN_IMPL=green-1.4.0、6 行目が GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> である
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv がある
    When `validate-config.sh --feature-flag ff.env --verbose` を実行する
    Then 終了コード 0 で stderr は info 行 5 行だけで、key= が BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE / GREEN_IMPL / GREEN_RUNNER の順に "info: key loaded key=<KEY> path: ff.env" が出る(コメント行の info 行は出ず、値は出さない)
    And stdout は --verbose を付けないときと同じ 15 行で、11 行目は "operation_mode=green_only" である

  Scenario: validate-config_sh_feature-flag は行の構造の検査で止めた回は --verbose でも info 行を出さない
    Given ff.env の 1 行目が ZZ=x、2 行目が broken、3 行目が BLUE_MODE=off、4 行目が GREEN_MODE=foreground、5 行目が RAPID_CROSSCHECK_MODE=off である
    When `validate-config.sh --feature-flag ff.env --verbose` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr は "error: invalid line line=2 path: ff.env" の 1 行だけである(info 行と未知キーの warn 行は出ない。契約 config_input_rules.env_files)

  Scenario: validate-config_sh_feature-flag は error 行が 2 行以上のとき契約の error_order の順に出す
    Given ff.env の 1 行目が BLUE_MODE=foreground、2 行目が GREEN_MODE=foreground、3 行目が RAPID_CROSSCHECK_MODE=maybe、4 行目が GREEN_IMPL=green-1.4.0、5 行目が BLUE_RUNNER=relative/blue-runner.sh、6 行目が FINAL_POLL_LIMIT_SEC=60、7 行目が FINAL_CROSSCHECK_MODE=background である(BLUE_IMPL / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER は書かない)
    And RELAY_GATE_CONFIG_DIR に blue-job-map.csv も green-job-map.csv も無く、ff.env のあるディレクトリに relative/blue-runner.sh は無い
    When ff.env のあるディレクトリを作業ディレクトリにして `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr は次の 12 行だけがこの順に出る(契約 config_files.feature-flag.env.error_order)
      | error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe                              |
      | hint: use foreground, background or off                                                 |
      | error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground   |
      | error: option required option=BLUE_IMPL path: ff.env                                    |
      | error: file not executable key=BLUE_RUNNER path=<ff.env のあるディレクトリの絶対パス>/relative/blue-runner.sh |
      | error: option required option=GREEN_RUNNER path: ff.env                                 |
      | error: option required option=RAPID_CROSSCHECK_RUNNER path: ff.env                      |
      | error: option required option=RAPID_CROSSCHECK_WORKER path: ff.env                      |
      | error: final crosscheck key is not allowed key=FINAL_POLL_LIMIT_SEC                     |
      | error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE                    |
      | error: job map not found slot=blue map=<RELAY_GATE_CONFIG_DIR>/blue-job-map.csv         |
      | error: job map not found slot=green map=<RELAY_GATE_CONFIG_DIR>/green-job-map.csv       |

  Scenario Outline: validate-config_sh_feature-flag は mode が列挙外・空・欠落の slot も従属キーと対応ジョブマップを検査し runner へ問い合わせる
    Given ff.env に <blue_mode_line> GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off BLUE_RUNNER=<実行可能な blue スタブ> GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<実行可能な green スタブ> を書き BLUE_IMPL を書かない(<blue_mode_line> が「(書かない)」のときは BLUE_MODE の行を書かない)
    And 両 runner スタブは --help で "runner-if-version=1" を返し、起動されるたびに受け取った引数を記録する
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv があり blue-job-map.csv は無い
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr は <mode_lines> に続けて "error: option required option=BLUE_IMPL path: ff.env" / "error: job map not found slot=blue map=<RELAY_GATE_CONFIG_DIR>/blue-job-map.csv" がこの順に出て、ほかの行は出ない(契約 config_files.feature-flag.env.validation_rules)
    And blue スタブと green スタブは、それぞれ引数 --help で 1 回ずつ起動されている

    Examples:
      | blue_mode_line     | mode_lines                                                                                       | note   |
      | BLUE_MODE=parallel | "error: invalid value key=BLUE_MODE value=parallel" / "hint: use foreground, background or off" | 列挙外 |
      | BLUE_MODE=         | "error: option required option=BLUE_MODE path: ff.env"                                          | 空     |
      | (書かない)       | "error: option required option=BLUE_MODE path: ff.env"                                          | 欠落   |

  Scenario: validate-config_sh_feature-flag は mode が 3 つとも欠落・空の設定で foreground の個数の error 行に - を出す
    Given ff.env の 1 行目が CONFIG_VERSION=cfg-v1、2 行目が GREEN_MODE=(値が空)で、ほかの行は無い
    And RELAY_GATE_CONFIG_DIR に blue-job-map.csv も green-job-map.csv も無い
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr は次の 13 行だけがこの順に出る(契約 config_files.feature-flag.env の error_messages / error_order / validation_rules)
      | warn: unknown key key=CONFIG_VERSION path: ff.env                                  |
      | error: option required option=BLUE_MODE path: ff.env                               |
      | error: option required option=GREEN_MODE path: ff.env                              |
      | error: option required option=RAPID_CROSSCHECK_MODE path: ff.env                   |
      | error: foreground slot must be exactly one blue_mode=- green_mode=-                |
      | error: option required option=BLUE_IMPL path: ff.env                               |
      | error: option required option=BLUE_RUNNER path: ff.env                             |
      | error: option required option=GREEN_IMPL path: ff.env                              |
      | error: option required option=GREEN_RUNNER path: ff.env                            |
      | error: option required option=RAPID_CROSSCHECK_RUNNER path: ff.env                 |
      | error: option required option=RAPID_CROSSCHECK_WORKER path: ff.env                 |
      | error: job map not found slot=blue map=<RELAY_GATE_CONFIG_DIR>/blue-job-map.csv    |
      | error: job map not found slot=green map=<RELAY_GATE_CONFIG_DIR>/green-job-map.csv  |

  Scenario: validate-config_sh_feature-flag は RAPID_CROSSCHECK_MODE が列挙外でも速報 runner と worker を検査する
    Given ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=maybe GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> を書き RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER を書かない
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv がある
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr は次の 4 行だけがこの順に出る(契約 config_files.feature-flag.env.validation_rules)
      | error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe          |
      | hint: use foreground, background or off                             |
      | error: option required option=RAPID_CROSSCHECK_RUNNER path: ff.env  |
      | error: option required option=RAPID_CROSSCHECK_WORKER path: ff.env  |

  Scenario: validate-config_sh_feature-flag は 9 キーと任意の 2 キーのどちらでもないキーの値をプロセスの環境へ取り込まない
    Given 有効な並行稼働設定の 1 行目の前に PATH=/nonexistent を、最終行の後に RELAY_GATE_CONFIG_DIR=/nonexistent を書いた ff.env がある
    And 両 runner スタブは --help で "runner-if-version=1" を返し、RELAY_GATE_CONFIG_DIR(環境変数)のディレクトリに blue-job-map.csv と green-job-map.csv がある
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stderr は "warn: unknown key key=PATH path: ff.env" / "warn: unknown key key=RELAY_GATE_CONFIG_DIR path: ff.env" の 2 行だけがこの順に出る(契約 config_input_rules.env_files。キー名を表示に使うだけ)
    And stdout は 15 行で、12 行目は "blue_job_map: <環境変数 RELAY_GATE_CONFIG_DIR>/blue-job-map.csv"、最終行は "green_runner_if_version=1" である(ファイルの PATH / RELAY_GATE_CONFIG_DIR の値は使われない)

  Scenario: validate-config_sh_feature-flag は blue と green に同じ絶対パスのジョブマップの場所を書いた設定を未知キーの warn なしで受理する
    Given 有効な並行稼働設定に加えて BLUE_JOB_MAP_CSV=<一時ディレクトリ maps の絶対パス>/jobs.csv と GREEN_JOB_MAP_CSV=<一時ディレクトリ maps の絶対パス>/jobs.csv を書いた ff.env がある
    And maps に jobs.csv があり、RELAY_GATE_CONFIG_DIR に blue-job-map.csv も green-job-map.csv も無い
    And 両 runner スタブは --help で "runner-if-version=1" を返す
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stderr は 0 行である("warn: unknown key" で始まる行は出ない。契約 config_files.feature-flag.env.job_map_location)
    And stdout は 15 行で、12 行目は "blue_job_map: <maps の絶対パス>/jobs.csv"、13 行目は "green_job_map: <maps の絶対パス>/jobs.csv" である

  Scenario: validate-config_sh_feature-flag は 2 キーが無い設定で渡したファイルのあるディレクトリではなく RELAY_GATE_CONFIG_DIR 配下の固定の名前を使う
    Given 一時ディレクトリ conf に 9 キーだけの有効な並行稼働設定 ff.env があり、conf に blue-job-map.csv も green-job-map.csv も無い
    And conf とは別のディレクトリを指す RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある
    And 両 runner スタブは --help で "runner-if-version=1" を返す
    When `validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する
    Then 終了コード 0 で stderr は 0 行である
    And stdout の 12 行目は "blue_job_map: <RELAY_GATE_CONFIG_DIR>/blue-job-map.csv"、13 行目は "green_job_map: <RELAY_GATE_CONFIG_DIR>/green-job-map.csv" である

  Scenario Outline: validate-config_sh_feature-flag は値が空のキーと書いていないキーの slot に固定の名前を使う
    Given 有効な並行稼働設定(9 キー)に加えて <lines> を書いた ff.env がある(<lines> の「 と 」は行の区切り)
    And 一時ディレクトリ maps に blue-jobs.csv と green-jobs.csv があり、RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある
    And 両 runner スタブは --help で "runner-if-version=1" を返す
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stderr は 0 行である(値が空のキーに error も warn も出ない)
    And stdout の 12 行目は "blue_job_map: <blue>"、13 行目は "green_job_map: <green>" である

    Examples:
      | lines                                                                    | blue                                      | green                                      | note                         |
      | BLUE_JOB_MAP_CSV=                                                        | <RELAY_GATE_CONFIG_DIR>/blue-job-map.csv  | <RELAY_GATE_CONFIG_DIR>/green-job-map.csv  | 値が空は無いときと同じ       |
      | BLUE_JOB_MAP_CSV= と GREEN_JOB_MAP_CSV=<maps の絶対パス>/green-jobs.csv  | <RELAY_GATE_CONFIG_DIR>/blue-job-map.csv  | <maps の絶対パス>/green-jobs.csv           | 空のキーと書いたキー         |
      | GREEN_JOB_MAP_CSV=<maps の絶対パス>/green-jobs.csv                       | <RELAY_GATE_CONFIG_DIR>/blue-job-map.csv  | <maps の絶対パス>/green-jobs.csv           | green だけ書く               |
      | BLUE_JOB_MAP_CSV=<maps の絶対パス>/blue-jobs.csv                         | <maps の絶対パス>/blue-jobs.csv           | <RELAY_GATE_CONFIG_DIR>/green-job-map.csv  | blue だけ書く                |

  Scenario Outline: validate-config_sh_feature-flag は相対パスのジョブマップの場所を作業ディレクトリではなく設定ファイルのあるディレクトリ基準で解決する
    Given 一時ディレクトリ conf に ff.env があり、BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> GREEN_JOB_MAP_CSV=<value> が書いてある
    And <location> にジョブマップがあり、作業ディレクトリにするディレクトリ work(conf とは別で、親ディレクトリも conf の親とは別)から見た同じ相対位置にファイルは無い
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv は無い
    When work を作業ディレクトリにして `validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する
    Then 終了コード 0 で stdout の 13 行目は "green_job_map: <conf の絶対パス>/<value>" である(`.`・`..` を畳まない。契約 config_files.feature-flag.env の job_map_location / runner_path_resolution)

    Examples:
      | value                   | location                         | note             |
      | ./green-jobs.csv        | conf/green-jobs.csv              | ./ で始まる      |
      | green-jobs.csv          | conf/green-jobs.csv              | ./ を付けない    |
      | ../maps/green-jobs.csv  | conf の親の maps/green-jobs.csv  | .. で親をたどる  |

  Scenario: validate-config_sh_feature-flag は相対パスのジョブマップが作業ディレクトリにだけあるとき解決後のパスで job map not found を出す
    Given 一時ディレクトリ conf の ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> GREEN_JOB_MAP_CSV=./green-jobs.csv が書いてあり、conf に green-jobs.csv は無い
    And 作業ディレクトリにするディレクトリ work(conf とは別)に green-jobs.csv がある
    When work を作業ディレクトリにして `validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr は "error: job map not found slot=green map=<conf の絶対パス>/./green-jobs.csv" の 1 行だけである

  Scenario: validate-config_sh_feature-flag は書いた場所にジョブマップが無ければ固定の名前のファイルがあっても job map not found を出す
    Given 有効な並行稼働設定に加えて BLUE_JOB_MAP_CSV=<一時ディレクトリ maps の絶対パス>/missing.csv を書いた ff.env がある(GREEN_JOB_MAP_CSV は書かない)
    And maps に missing.csv は無く、RELAY_GATE_CONFIG_DIR に blue-job-map.csv があり green-job-map.csv は無い
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr は次の 2 行だけがこの順に出る(契約 config_files.feature-flag.env の job_map_location / error_order)
      | error: job map not found slot=blue map=<maps の絶対パス>/missing.csv              |
      | error: job map not found slot=green map=<RELAY_GATE_CONFIG_DIR>/green-job-map.csv |

  Scenario: validate-config_sh_feature-flag は決めた場所にあるが読めないジョブマップを config file is not readable で報告する
    Given 有効な並行稼働設定(9 キー)の ff.env があり、両 runner スタブは --help で "runner-if-version=1" を返す
    And RELAY_GATE_CONFIG_DIR の blue-job-map.csv はディレクトリで、green-job-map.csv は読み取り権限の無いファイルである(テストは root 以外のユーザーで実行する)
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr は次の 2 行だけがこの順に出る(契約 config_files.feature-flag.env の job_map_location.presence_report / error_order)
      | error: config file is not readable path: <RELAY_GATE_CONFIG_DIR>/blue-job-map.csv  |
      | error: config file is not readable path: <RELAY_GATE_CONFIG_DIR>/green-job-map.csv |
    And stderr に "job map not found" を含む行も "slot=" を含む行も出ない

  Scenario: validate-config_sh_feature-flag はシンボリックリンクのジョブマップをリンク先で判定する
    Given 有効な並行稼働設定(9 キー)の ff.env があり、両 runner スタブは --help で "runner-if-version=1" を返す
    And RELAY_GATE_CONFIG_DIR の blue-job-map.csv は読める通常のファイルを指すシンボリックリンクで、green-job-map.csv はリンク先が無いシンボリックリンクである
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr は "error: job map not found slot=green map=<RELAY_GATE_CONFIG_DIR>/green-job-map.csv" の 1 行だけである(blue はリンク先が読めるため違反にしない。契約 job_map_location.presence_report)

  Scenario: validate-config_sh_feature-flag は読めないジョブマップの行を job map not found と同じ位置に出す
    Given ff.env の 1 行目が BLUE_MODE=foreground、2 行目が GREEN_MODE=background、3 行目が RAPID_CROSSCHECK_MODE=off、4 行目が BLUE_IMPL=blue-1.0.0、5 行目が BLUE_RUNNER=<実行可能な blue スタブ>、6 行目が GREEN_RUNNER=<実行可能な green スタブ> である(GREEN_IMPL は書かない)
    And 両 runner スタブは --help で "runner-if-version=1" を返す
    And RELAY_GATE_CONFIG_DIR の blue-job-map.csv はディレクトリで、green-job-map.csv は無い
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr は次の 3 行だけがこの順に出る(契約 config_files.feature-flag.env.error_order の 3 → 6。6 の中は blue → green)
      | error: option required option=GREEN_IMPL path: ff.env                             |
      | error: config file is not readable path: <RELAY_GATE_CONFIG_DIR>/blue-job-map.csv |
      | error: job map not found slot=green map=<RELAY_GATE_CONFIG_DIR>/green-job-map.csv |

  Scenario: validate-config_sh_feature-flag は off の slot のジョブマップの場所を解決も検査もしない
    Given ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> BLUE_JOB_MAP_CSV=/nonexistent/blue-jobs.csv を書く
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv がある(blue-job-map.csv は無い)
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stderr は 0 行である("error: job map not found" も "warn: unknown key" も出ない)
    And stdout の 12 行目は "blue_job_map: -"、13 行目は "green_job_map: <RELAY_GATE_CONFIG_DIR>/green-job-map.csv" である

  Scenario: validate-config_sh_feature-flag は任意の 2 キーと名前が違うキーを未知キーとして warn し値を使わない
    Given 有効な並行稼働設定の最終行の後に BLUE_JOB_MAP=<一時ディレクトリ maps の絶対パス>/blue-jobs.csv と green_job_map_csv=<一時ディレクトリ maps の絶対パス>/green-jobs.csv の 2 行を書いた ff.env がある
    And maps に blue-jobs.csv と green-jobs.csv があり、RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある
    And 両 runner スタブは --help で "runner-if-version=1" を返す
    When `validate-config.sh --feature-flag ff.env` を実行する
    Then 終了コード 0 で stderr は "warn: unknown key key=BLUE_JOB_MAP path: ff.env" / "warn: unknown key key=green_job_map_csv path: ff.env" の 2 行だけがこの順に出る(キーの比較は大文字小文字を区別した完全一致)
    And stdout の 12 行目は "blue_job_map: <RELAY_GATE_CONFIG_DIR>/blue-job-map.csv"、13 行目は "green_job_map: <RELAY_GATE_CONFIG_DIR>/green-job-map.csv" である

  Scenario: validate-config_sh_feature-flag は方針資料の書き方の相対パスを設定ファイルのあるディレクトリ基準で解決して受理する
    Given 一時ディレクトリ conf に ff.env があり、BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=./blue-runner.sh GREEN_RUNNER=./green-runner.sh RAPID_CROSSCHECK_RUNNER=./rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=./rapid-crosscheck-worker.sh が書いてある
    And conf に実行可能な blue-runner.sh / green-runner.sh / rapid-crosscheck-runner.sh / rapid-crosscheck-worker.sh があり、両 runner は --help で "runner-if-version=1" を返す
    And RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある
    When conf とは別のディレクトリを作業ディレクトリにして `validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する
    Then 終了コード 0 で stderr は 0 行である
    And stdout の 6 行目は "blue_runner: <conf の絶対パス>/./blue-runner.sh"、7 行目は "green_runner: <conf の絶対パス>/./green-runner.sh"、9 行目は "rapid_crosscheck_runner: <conf の絶対パス>/./rapid-crosscheck-runner.sh"、10 行目は "rapid_crosscheck_worker: <conf の絶対パス>/./rapid-crosscheck-worker.sh" である(契約 config_files.feature-flag.env.runner_path_resolution)
    And stdout の最終行は "green_runner_if_version=1" である

  Scenario Outline: validate-config_sh_feature-flag は相対パスの基準を作業ディレクトリではなく設定ファイルのあるディレクトリにする
    Given 一時ディレクトリ conf に ff.env があり、BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<value> が書いてある
    And <location> に、--help で "runner-if-version=1" を返す実行可能な green スタブがある
    And 作業ディレクトリにするディレクトリ work(conf とは別で、親ディレクトリも conf の親とは別)から見た同じ相対位置に、起動されたら記録を残し --help で "runner-if-version=9" を返す別の実行可能ファイルがある
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv がある
    When work を作業ディレクトリにして `validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する
    Then 終了コード 0 で stdout の 7 行目は "green_runner: <conf の絶対パス>/<value>"、最終行は "green_runner_if_version=1" である
    And work から見た位置に置いた別の実行可能ファイルは起動されていない

    Examples:
      | value                       | location                            | note             |
      | ./green-runner.sh           | conf/green-runner.sh                | ./ で始まる      |
      | green-runner.sh             | conf/green-runner.sh                | ./ を付けない    |
      | ../runners/green-runner.sh  | conf の親の runners/green-runner.sh | .. で親をたどる  |

  Scenario: validate-config_sh_feature-flag は設定ファイルのパスが相対パスのとき作業ディレクトリで絶対化したディレクトリを基準にする
    Given ディレクトリ work の下の conf/ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=green-runner.sh が書いてある
    And work/conf/green-runner.sh は --help で "runner-if-version=1" を返す実行可能なスタブで、work/green-runner.sh は無い
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv がある
    When work を作業ディレクトリにして `validate-config.sh --feature-flag conf/ff.env` を実行する
    Then 終了コード 0 で stdout の 7 行目は "green_runner: <work の絶対パス>/conf/green-runner.sh" である(<work の絶対パス> は作業ディレクトリの論理パス = シェルの $PWD)

  Scenario: validate-config_sh_feature-flag は設定ファイルがシンボリックリンクのときリンクのあるディレクトリを基準にする
    Given ディレクトリ real に ff.env(BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=./green-runner.sh)があり、real に green-runner.sh は無い
    And 別のディレクトリ link に、real/ff.env へのシンボリックリンク ff.env と、--help で "runner-if-version=1" を返す実行可能な green-runner.sh がある
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv がある
    When `validate-config.sh --feature-flag <link の絶対パス>/ff.env` を実行する
    Then 終了コード 0 で stdout の 7 行目は "green_runner: <link の絶対パス>/./green-runner.sh" である(リンク先のディレクトリ real は基準にしない)

  Scenario: validate-config_sh_feature-flag は相対パスの実体が無いとき解決後のパスで報告し path is not absolute を出さない
    Given 一時ディレクトリ conf の ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=./green-runner.sh が書いてあり、conf に green-runner.sh は無い
    And 作業ディレクトリにするディレクトリ work(conf とは別)に実行可能な green-runner.sh がある
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv がある
    When work を作業ディレクトリにして `validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する
    Then 終了コード 2 で stdout は 0 行、stderr は "error: file not executable key=GREEN_RUNNER path=<conf の絶対パス>/./green-runner.sh" の 1 行だけである
    And stderr に "path is not absolute" を含む行は出ない

  Scenario Outline: validate-config_sh_feature-flag は ~ と環境変数とコマンド置換を展開せず文字のまま相対パスとして扱う
    Given 一時ディレクトリ conf の ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<value> が書いてある
    And 環境変数 HOME のディレクトリに実行可能な green-runner.sh があり、conf に marker という名前のファイルは無い
    And RELAY_GATE_CONFIG_DIR に green-job-map.csv がある
    When conf を作業ディレクトリにして `validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する
    Then 終了コード 2 で stderr は "error: file not executable key=GREEN_RUNNER path=<conf の絶対パス>/<value>" の 1 行だけである(<value> は設定に書いた文字のまま)
    And conf に marker という名前のファイルは作られていない(コマンド置換の中身は実行されない)

    Examples:
      | value                              | note           |
      | ~/green-runner.sh                  | ~ を展開しない |
      | $HOME/green-runner.sh              | 環境変数       |
      | $(touch marker)green-runner.sh     | コマンド置換   |
```
