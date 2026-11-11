# source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-facade.md#ティア完了条件(BDD)
# 転写: ティア完了条件の gherkin ブロックを意訳せず転写(S2 test-scaffold 再生成。uc_id=dcd8234d / tier-facade。feedback run 20261110_080548 後の spec。--verbose の info 行の 4 Scenario を追加)
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

  Scenario: --verbose では info 行をすべて出してから未知キーの warn 行、検証ルールの error 行の順に出す
    Given rapid-crosscheck.env の 1 行目が ZZ=x、2 行目が RAPID_COMPARE_COMMAND=relative、3 行目が AA=x である
    When validate-config.sh --rapid-crosscheck <path> --verbose を実行する
    Then 終了コード 2 で stderr は次の 7 行がこの順に出る
      | info: key loaded key=ZZ path: <path>                                          |
      | info: key loaded key=RAPID_COMPARE_COMMAND path: <path>                       |
      | info: key loaded key=AA path: <path>                                          |
      | warn: unknown key key=ZZ path: <path>                                         |
      | warn: unknown key key=AA path: <path>                                         |
      | error: path is not absolute key=RAPID_COMPARE_COMMAND path=relative           |
      | error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=relative |
    And stdout は `config=rapid-crosscheck` / `path: <path>` / `command_path: relative` / `has_job_id_placeholder=false` / `status=invalid` / `violations=2` の 6 行である(info 行と warn 行は violations に数えない。契約 config_input_rules.env_files)

  Scenario: --verbose の info 行は値が空のキーにも出し、値は出さない
    Given rapid-crosscheck.env の 1 行目がコメント行 # memo、2 行目が RAPID_DB_CONN_REF=、3 行目が RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} である(/opt/compare/compare.sh は実行可能)
    When validate-config.sh --rapid-crosscheck <path> --verbose を実行する
    Then 終了コード 0 で stderr は `info: key loaded key=RAPID_DB_CONN_REF path: <path>` / `info: key loaded key=RAPID_COMPARE_COMMAND path: <path>` の 2 行だけである(コメント行の info 行は出ない)
    And stdout は --verbose を付けないときと同じ `config=rapid-crosscheck` / `path: <path>` / `command_path: /opt/compare/compare.sh` / `has_job_id_placeholder=true` / `status=valid` の 5 行である

  Scenario: 行の構造の検査で止めた回は --verbose でも info 行を出さない
    Given rapid-crosscheck.env の 1 行目が ZZ=x、2 行目が broken、3 行目が RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} である(/opt/compare/compare.sh は実行可能)
    When validate-config.sh --rapid-crosscheck <path> --verbose を実行する
    Then 終了コード 2 で stderr は `error: invalid line line=2 path: <path>` の 1 行だけである(info 行と未知キーの warn 行は出ない。契約 config_input_rules.env_files)
    And stdout は `config=rapid-crosscheck` / `path: <path>` / `command_path: -` / `has_job_id_placeholder=-` / `status=invalid` / `violations=1` の 6 行である

  Scenario: バイト・改行の検査で止めた回は --verbose でも info 行を出さない
    Given rapid-crosscheck.env の 1 行目が ZZ=x + CR + LF、2 行目が RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} である
    When validate-config.sh --rapid-crosscheck <path> --verbose を実行する
    Then 終了コード 2 で stderr は `error: carriage return is not allowed line=1 path: <path>` / `hint: use LF line endings` の 2 行だけがこの順に出る(info 行は出ない。契約 config_input_rules.byte_checks / env_files)
    And stdout は `config=rapid-crosscheck` / `path: <path>` / `command_path: -` / `has_job_id_placeholder=-` / `status=invalid` / `violations=1` の 6 行である
