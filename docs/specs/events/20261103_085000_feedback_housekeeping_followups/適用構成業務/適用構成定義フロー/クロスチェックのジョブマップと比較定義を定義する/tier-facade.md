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
| stdout | 固定順: `config=rapid-crosscheck` / `path: <path>` / `command_path: <RAPID_COMPARE_COMMAND の先頭の語>` / `has_job_id_placeholder=true|false` / `status=valid|invalid` / `violations=N`(invalid 時) |
| stderr | 違反ごとに `error:` 1 行(全件)。下記「検証ルール」の違反文言。入力の守備範囲(NUL / UTF-8 / BOM / CR の拒否)は CLI 契約 `config_input_rules` に従う |
| 終了コード | 0(違反 0 件)/ 2(検証種別オプションの指定数不正・値なし・ファイル不在・必須キー欠落・コマンド部分の絶対パス違反・存在しない・実行不可・`{job_id}` 欠落・`{params}` が引数全体でない位置にある・未知のオプション)/ 6(検証器の内部障害。`config_input_rules.internal_failure`) |

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
```
