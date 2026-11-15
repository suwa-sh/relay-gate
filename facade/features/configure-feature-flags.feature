# source: docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/tier-facade.md#ティア完了条件(BDD)
# 転写: ティア完了条件の gherkin を意訳せず転写(S2 test-scaffold 生成。uc_id=fd678b04。spec event 20261110_153000_feedback_impl_feedback_dcd8234d までの仕様更新に追従した再転写)
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
