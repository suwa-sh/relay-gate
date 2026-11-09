# 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する - facade ティア仕様

## 変更概要

`validate-config.sh` に検証種別 `--housekeep <path>` を追加する。
検証対象はハウスキープ設定(`housekeep.env`)の保持日数 `HOUSEKEEP_RETENTION_DAYS` の形式だけである。
`HOUSEKEEP_DB_CONN_REF` の要否は `RAPID_CROSSCHECK_MODE` と、確報クロスチェックを使う設置か(final-crosscheck.env の `FINAL_DB_CONN_REF` の有無)で決まる。このため、この検証では扱わず、`housekeep.sh` の起動時に検査する(契約 `shared_rules.housekeep_rules.db_requirement`)。
facade ティアは自身の解析関数で検証し、他ティアのシェルファイルを source しない(arch CTR-007)。
エントリポイント `validate-config.sh` の定義元は UC「feature flag を設定する」で、契約の正本は [CLI コマンド契約](../../../_cross-cutting/api/cli-command-contract.yaml) の validate-config.sh。

## コマンド契約

### validate-config.sh --housekeep

- **書式**: `validate-config.sh --housekeep <path> [--verbose] [--help]`
- **アクセス権**: 基盤適用設計者 / 運用者が直接起動する。設定ファイルを変更しない

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--housekeep` | string | Yes(検証種別のうちちょうど 1 つ) | なし | 検証する housekeep.env のパス。値必須。既定パス `$RELAY_GATE_CONFIG_DIR/housekeep.env` を使う場合も明示的に渡す |
| `--verbose` | boolean | No | false | 補助出力を stderr に出す(この検証種別に固有の補助出力は無い) |

- 検証種別オプション `--feature-flag` / `--job-map` / `--rapid-crosscheck` / `--final-crosscheck` / `--housekeep` は排他。0 個または 2 個以上は終了コード 2
- **stdin**: なし

## 出力契約

- **stdout**(固定順。終了コード 0 と 2 の検証結果で出す。内部障害の 6 では出さない):

| 順 | 行 | 値 |
|---|---|---|
| 1 | `config=housekeep` | 固定 |
| 2 | `path: <path>` | 指定されたパス |
| 3 | `retention_days=<N>` | キーがあり valid ならその値、キーが無ければ 90、invalid なら `-`(入力の守備範囲の違反で値を使わないときも `-`) |
| 4 | `status=valid` / `status=invalid` | 違反 0 件なら valid |
| 5 | `violations=<N>` | invalid のときだけ。出した error 行の数(hint 行は数えない) |

- **stderr**:

| 条件 | 行 | 終了コード |
|---|---|---|
| ファイルが無い / 読めない | `error: config file not found path: ...` / `error: config file is not readable path: ...` | 2 |
| 入力の守備範囲の違反(NUL / UTF-8 / BOM / CR / `=` を含まない行 / キーの前後の空白を除いた結果キーが空になる行 / 同じキーが 2 行以上ある) | 契約 `config_input_rules` と同じ文言(同じキーの重複は `error: duplicate key key=<KEY> lines=<n1,n2,...> path: ...`)。報告の順と、この違反があるときは保持日数の検査と未知キーの warn を行わないことは契約 `config_input_rules.env_files` に従う | 2 |
| 保持日数が `^[1-9][0-9]{0,8}$` に合わない | `error: invalid value key=HOUSEKEEP_RETENTION_DAYS value=<値> path: <path>` + `hint: use a positive integer` | 2 |
| 未知キー | `warn: unknown key key=<KEY> path: <path>` | 影響しない |
| 検証器の内部障害 | 契約 `config_input_rules.internal_failure` と同じ文言 | 6 |

- 値の比較は、契約 `config_input_rules.env_files` の規則で前後の空白と引用符を外した後の値で行う。stderr の `value=` にも外した後の値を出す
- `value=` の任意入力は契約 `conventions.output_format.control_chars` の可視表記にする

- **終了コード**:

| コード | 意味 | 条件 |
|-------|------|------|
| 0 | 検証 OK | 違反 0 件(未知キーの warn だけを含む) |
| 2 | 入力・設定検証エラー | 検証種別オプションの指定数不正、値なし、未知のオプション、ファイル不在・読み取り不可、入力の守備範囲の違反、保持日数の違反 |
| 6 | 実行エラー | 検証器の内部障害 |

## UC ロジック

- **検証規則(domain `retention_days_rule`)**:

| 値(引用符と空白を外した後) | 判定 |
|---|---|
| キーが無い | valid。`retention_days=90` |
| `1` 〜 `999999999`(先頭 0 なし) | valid |
| 空 / `0` / 負の数 / 小数 / 先頭 0(`030`)/ `+` 付き / 10 桁以上 / 数字以外 | invalid |

- **確認プロンプト**: なし
- **冪等性**: 参照のみ。入力の複製は契約 `config_input_rules.snapshot` に従う

## ティア完了条件(BDD)

```gherkin
Feature: 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する - facade ティア

  Scenario: 保持日数のキーが無ければ既定 90 で valid
    Given housekeep.env に HOUSEKEEP_DB_CONN_REF=relay_gate_housekeep の行だけがある
    When `validate-config.sh --housekeep /etc/relay-gate/housekeep.env` を実行する
    Then 終了コード 0 で stdout が "config=housekeep" / "path: /etc/relay-gate/housekeep.env" / "retention_days=90" / "status=valid" の 4 行である

  Scenario: 9 桁の保持日数は valid
    Given housekeep.env に HOUSEKEEP_RETENTION_DAYS=999999999 がある
    When `validate-config.sh --housekeep /etc/relay-gate/housekeep.env` を実行する
    Then 終了コード 0 で stdout に retention_days=999999999 と status=valid が出る

  Scenario Outline: 正の整数でない保持日数は invalid
    Given housekeep.env に HOUSEKEEP_RETENTION_DAYS=<value> がある
    When `validate-config.sh --housekeep /etc/relay-gate/housekeep.env` を実行する
    Then 終了コード 2 で stderr に "error: invalid value key=HOUSEKEEP_RETENTION_DAYS value=<value> path: /etc/relay-gate/housekeep.env" と "hint: use a positive integer" が出る
    And stdout が "config=housekeep" / "path: /etc/relay-gate/housekeep.env" / "retention_days=-" / "status=invalid" / "violations=1" の 5 行である

    Examples:
      | value      |
      | 0          |
      | -1         |
      | 1.5        |
      | 030        |
      | +30        |
      | 1000000000 |

  Scenario: 値が空なら invalid
    Given housekeep.env に `HOUSEKEEP_RETENTION_DAYS=` の行がある
    When `validate-config.sh --housekeep /etc/relay-gate/housekeep.env` を実行する
    Then 終了コード 2 で stderr に "error: invalid value key=HOUSEKEEP_RETENTION_DAYS value= path: /etc/relay-gate/housekeep.env" が出る

  Scenario: 引用符と空白を外した値で検証する
    Given housekeep.env に `HOUSEKEEP_RETENTION_DAYS= "30" ` の行がある
    When `validate-config.sh --housekeep /etc/relay-gate/housekeep.env` を実行する
    Then 終了コード 0 で stdout に retention_days=30 と status=valid が出る

  Scenario: HOUSEKEEP_DB_CONN_REF が無くても valid
    Given housekeep.env に HOUSEKEEP_RETENTION_DAYS=90 の行だけがある
    When `validate-config.sh --housekeep /etc/relay-gate/housekeep.env` を実行する
    Then 終了コード 0 で stdout に status=valid が出る

  Scenario: 検証種別を 2 つ指定したら 2
    When `validate-config.sh --housekeep /etc/relay-gate/housekeep.env --final-crosscheck /etc/relay-gate/final-crosscheck.env` を実行する
    Then 終了コード 2 で stdout は 0 行である

  Scenario: 同じキーが 2 行あれば 2 で保持日数の値を使わない
    Given housekeep.env の 1 行目が HOUSEKEEP_RETENTION_DAYS=30、2 行目が HOUSEKEEP_RETENTION_DAYS=30 である(値が同じでも重複)
    When `validate-config.sh --housekeep /etc/relay-gate/housekeep.env` を実行する
    Then 終了コード 2 で stderr の error 行は "error: duplicate key key=HOUSEKEEP_RETENTION_DAYS lines=1,2 path: /etc/relay-gate/housekeep.env" の 1 行だけである(契約 config_input_rules.env_files)
    And stdout が "config=housekeep" / "path: /etc/relay-gate/housekeep.env" / "retention_days=-" / "status=invalid" / "violations=1" の 5 行である

  Scenario: ファイルが無ければ 2
    Given /etc/relay-gate/housekeep.env が無い
    When `validate-config.sh --housekeep /etc/relay-gate/housekeep.env` を実行する
    Then 終了コード 2 で stderr に "error: config file not found path: /etc/relay-gate/housekeep.env" が出る
```
