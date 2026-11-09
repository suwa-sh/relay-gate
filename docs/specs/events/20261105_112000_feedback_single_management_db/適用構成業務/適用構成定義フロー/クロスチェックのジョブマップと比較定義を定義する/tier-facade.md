# tier-facade: クロスチェックのジョブマップと比較定義を定義する

> facade ティアは全設定ファイルを自身の解析関数で検証する。他ティアへ検証を委譲せず、他ティアのシェルファイルを source しない(arch CTR-007)。本 UC は速報クロスチェック設定(`rapid-crosscheck.env` の `RAPID_COMPARE_COMMAND`)の `validate-config.sh --rapid-crosscheck` 検証を担う。確報側(`FINAL_COMPARE_COMMAND` / `--final-crosscheck`)は UC「比較ツールで日次全量比較を実行して結果を保存する」が持つ。

## 変更概要

- `validate-config.sh --rapid-crosscheck <path>` を facade ティアが単独で実装する(エントリポイントの定義元は UC「feature flag を設定する」。本 UC はその検証種別 `--rapid-crosscheck` の検証ルールを定義する)。
- 検証対象は `rapid-crosscheck.env` の `RAPID_COMPARE_COMMAND`(速報の比較ツール起動コマンド 1 行)。
- 検証は 3 点: コマンド部分(先頭の語 = shared_rules.compare_command_argv で空白区切りに分けた先頭の引数)が絶対パスで存在・実行可能であること、`{job_id}` を含むこと、`{params}` を使うなら引数 1 つ全体のときだけであること。`{job_id}` の有無と `{params}` の位置のほかは、引数部分の内容を検査しない(存在しないパス・未知の語・記号・空白を含む値は拒否しない)。

## コマンド契約

| 項目 | 内容 |
|------|------|
| コマンド | `validate-config.sh --rapid-crosscheck <path>` |
| 所有 tier | tier-facade(全検証種別。arch CTR-007。契約正本 = `_cross-cutting/api/cli-command-contract.yaml` の validate-config.sh) |
| 引数 | `--rapid-crosscheck <path>`(値必須。既定パス `$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` を使う場合も明示的に渡す)。`--feature-flag` / `--job-map` / `--rapid-crosscheck` / `--final-crosscheck` の 4 検証種別のうちちょうど 1 つ(排他) |
| stdin | なし |
| stdout | 固定順: `config=rapid-crosscheck` / `path: <path>` / `command_path: <RAPID_COMPARE_COMMAND の先頭の語>` / `has_job_id_placeholder=true|false|-` / `status=valid|invalid` / `violations=N`(invalid 時)。入力の守備範囲の違反(バイト・改行、invalid line、同じキーの重複)で値を使わないときは command_path と has_job_id_placeholder を `-` にする(CLI 契約 `config_input_rules.env_files`) |
| stderr | 違反ごとに `error:` 1 行(全件)。下記「検証ルール」の違反文言。入力の守備範囲(NUL / UTF-8 / BOM / CR の拒否、invalid line、同じキーが 2 行以上ある設定の拒否 `error: duplicate key key=<KEY> lines=<n1,n2,...> path: ...`)と報告の順は CLI 契約 `config_input_rules`(`byte_checks` / `env_files`)に従う。バイト・改行の違反はファイル内の全件を行番号の昇順に、同じ行は NUL → UTF-8 → BOM → CR の順に 1 種類 1 行で出し、hint は最後の CR の error 行の次に 1 回だけ出して止める(violations はこの error 行の数で、hint を数えない)。invalid line・同じキーの重複があるときは下記の検証ルールを行わない。キー表(契約 config_files.rapid-crosscheck.env の keys)に無いキーは `warn: unknown key key=<KEY> path: ...` を出して継続する(終了コード・violations に数えない。他の読み手が使うキーは未知キーではない。契約 config_files.rapid-crosscheck.env note) |
| 終了コード | 0(違反 0 件)/ 2(検証種別オプションの指定数不正・値なし・ファイル不在・入力の守備範囲の違反(NUL / UTF-8 / BOM / CR / invalid line / 同じキーの重複)・必須キー欠落・コマンド部分の絶対パス違反・存在しない・実行不可・`{job_id}` 欠落・`{params}` が引数全体でない位置にある・未知のオプション)/ 6(検証器の内部障害。`config_input_rules.internal_failure`) |

## 検証ルール(domain: launch_command_rules)

コマンド部分(先頭の語)は shared_rules.compare_command_argv に従って値を空白区切りで引数の並びに分けた先頭の引数と定義する。検証はコマンド部分と `{job_id}` の有無・`{params}` の位置に行い、`{job_id}` の有無と `{params}` の位置のほかは、引数部分の内容を検査しない。

| # | ルール | 違反文言(終了コード 2) |
|---|--------|------------------------|
| 1 | `RAPID_COMPARE_COMMAND` が存在し非空である | `error: option required option=RAPID_COMPARE_COMMAND path: ...` |
| 2 | コマンド部分(先頭の引数)が絶対パスである | `error: path is not absolute key=RAPID_COMPARE_COMMAND path=<先頭の引数>` |
| 3 | コマンド部分が存在し実行可能である | `error: file not executable key=RAPID_COMPARE_COMMAND path=<先頭の引数>` |
| 4 | 起動コマンドに `{job_id}` を含む | `error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=<値>` |
| 5 | `{params}` を使うなら引数 1 つ全体がちょうど `{params}` である(引数の一部に `{params}` を含まない) | `error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=<値>` |

文言は feature-flag.env の検証(`config_files.feature-flag.env.error_messages`)と同じ形式に揃える。`{run_id}` / `{blue_exit_code}` / `{green_exit_code}` は任意プレースホルダで、有無を検査しない。`{params}` は任意だが、使う場合の位置(引数 1 つ全体)だけをルール 5 で検査する。記号・空白を含む値は拒否しない(shared_rules.compare_command_argv により引数として文字のまま届くため)。

## ティア完了条件(BDD)

```gherkin
Feature: tier-facade 速報クロスチェック設定の検証

  Scenario: 絶対パスで実行可能・{job_id} 含むなら valid
    Given RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} で /opt/compare/compare.sh が実行可能
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 0 で stdout に status=valid、command_path: /opt/compare/compare.sh、has_job_id_placeholder=true が出る

  Scenario: 引数部分に存在しないパスや未知の語があっても valid
    Given RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} --in /no/such/path unknown-word で /opt/compare/compare.sh が実行可能
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 0 で stdout に status=valid が出て、stderr に error 行は出ない

  Scenario: コマンド部分が実行不可なら 2
    Given RAPID_COMPARE_COMMAND=/opt/compare/missing.sh --job {job_id} でコマンド部分が存在しない
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 2 で stderr に `error: file not executable key=RAPID_COMPARE_COMMAND path=/opt/compare/missing.sh` が出る

  Scenario: {job_id} が無ければ 2
    Given RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --run {run_id} で {job_id} を含まない
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 2 で stderr に `error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --run {run_id}` が出る

  Scenario: {params} が引数全体でない位置にあれば 2
    Given RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} --args={params} で {params} が引数の一部になっている
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 2 で stderr に `error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --job {job_id} --args={params}` が出る

  Scenario: {params} が独立した 1 引数なら valid
    Given RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} {params} で /opt/compare/compare.sh が実行可能
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 0 で stdout に status=valid が出る

  Scenario Outline: 前後の空白を除いて # で始まる行はコメントとして読み飛ばす
    Given rapid-crosscheck.env の 1 行目が <line> で、2 行目が RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} である(/opt/compare/compare.sh は実行可能。<SP> は半角空白 1 個、<TAB> はタブ 1 個に置き換えて書き込む)
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 0 で stdout に status=valid が出て、stderr に "error: invalid line" で始まる行は出ない(契約 config_input_rules.env_files。全 env 設定ファイル共通)

    Examples:
      | line                                    |
      | # memo                                  |
      | <SP><SP># memo                          |
      | <TAB># memo                             |

  Scenario: 起動コマンドのキーが 2 行あれば 2 でどちらの値も使わない
    Given rapid-crosscheck.env の 1 行目が RAPID_COMPARE_COMMAND=/opt/compare/old.sh --job {job_id}、2 行目が RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} である(どちらのコマンドも実行可能)
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 2 で stderr の error 行は `error: duplicate key key=RAPID_COMPARE_COMMAND lines=1,2 path: <path>` の 1 行だけである(契約 config_input_rules.env_files。後の行の値で検証しない)
    And stdout は `config=rapid-crosscheck` / `path: <path>` / `command_path: -` / `has_job_id_placeholder=-` / `status=invalid` / `violations=1` の 6 行である

  Scenario: 字下げしてコメントにした起動コマンドの行は読まない
    Given rapid-crosscheck.env が `<SP># RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id}` の 1 行だけである(<SP> は半角空白 1 個に置き換えて書き込む。/opt/compare/compare.sh は実行可能)
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 2 で stderr に `error: option required option=RAPID_COMPARE_COMMAND path: <path>` が出て、"error: invalid line" で始まる行は出ない(コメント行として読み飛ばすため、起動コマンドが無い設定になる)

  Scenario: バイト・改行の違反は全件を行番号の昇順に出し violations は hint を数えない
    Given rapid-crosscheck.env の 1 行目が BOM 付きの "# compare" + CR + LF、2 行目が NUL バイトと UTF-8 として不正なバイト列を含み CR + LF で終わる行、3 行目が "RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id}" + CR + LF、4 行目が NUL バイトを含む行である
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 2 で stderr は次の 8 行がこの順に出る
      | error: byte order mark is not allowed line=1 path: <path> |
      | error: carriage return is not allowed line=1 path: <path> |
      | error: nul byte is not allowed line=2 path: <path>        |
      | error: encoding is not utf-8 line=2 path: <path>          |
      | error: carriage return is not allowed line=2 path: <path> |
      | error: carriage return is not allowed line=3 path: <path> |
      | hint: use LF line endings                                 |
      | error: nul byte is not allowed line=4 path: <path>        |
    And stdout は `config=rapid-crosscheck` / `path: <path>` / `command_path: -` / `has_job_id_placeholder=-` / `status=invalid` / `violations=7` の 6 行である(契約 config_input_rules.byte_checks)
```
