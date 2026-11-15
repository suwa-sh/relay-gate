# source: docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/tier-facade.md#ティア完了条件(BDD)
# 転写: ティア完了条件の gherkin を意訳せず転写(S2 test-scaffold 生成。uc_id=fd678b04。spec event 20261110_153000_feedback_impl_feedback_dcd8234d までの仕様更新に追従した再転写)
# 追記: spec event 20261115_142000_feedback_impl_feedback_fd678b04_cycle3 で足された末尾の Scenario 4 本と Scenario Outline 1 本(error 行の順 / mode が列挙外・空・欠落の slot の検査 / 9 キー以外の値を取り込まない)を転写(2026-11-15 の S2 再実行。既存 Scenario は変更なし)
# 追記: spec event 20261115_164000_feedback_runner_relative_path で足された末尾の Scenario 4 本と Scenario Outline 2 本(相対パスの解決 / 基準は作業ディレクトリではない / 設定ファイルのパスが相対パス / シンボリックリンク / 実体が無いとき / ~・環境変数・コマンド置換を展開しない)を転写し、error_order の Scenario の Given 1 行・When・表の 5 行目を仕様の置換どおりに差し替えた(2026-11-15 の S2 再実行。ほかの Scenario は変更なし)
# 追記: 2026-11-16 の仕様更新(slot ジョブマップの場所を書く任意の 2 キー BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV。契約 config_files.feature-flag.env.job_map_location、spec-decision-036 / 038)で足された Scenario 6 本と Scenario Outline 2 本(同じ絶対パス / 2 キーが無いときの固定の名前 / 値が空のキー / 相対パスの基準 / 作業ディレクトリにだけある / 書いた場所に無い / off の slot / 名前が違うキー)を仕様と同じ位置へ転写し、duplicate key の Examples に 1 行を足し、Scenario「9 キー以外のキーの値をプロセスの環境へ取り込まない」の名前を仕様の改名どおりに差し替えた(2026-11-16 の S2 再実行。ほかの Scenario は変更なし)
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
