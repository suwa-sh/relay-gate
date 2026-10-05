# source: docs/specs/latest/適用構成業務/適用構成定義フロー/slot ごとのジョブマップを定義する/tier-facade.md#ティア完了条件(BDD)
# 転写: gherkin ブロックを意訳せず転写(S2 test-scaffold scoped 再生成。uc_id=eff24f55。spec event 20260923_112000_feedback_impl_feedback_eff24f55_cycle2)
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
    Then 終了コード 2 で stderr に "error: duplicate job_id job_id=JOB001 lines=2,5" が出る(初出行 2 を含む)
    And stderr に "duplicate job_id" を含む行は 1 行だけである

  Scenario: validate-config_sh_job-map は 3 行以上の重複を初出行から全部列挙する
    Given map.csv の 2・3・4 行目が job_id=JOB001 である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 2 で stderr に "error: duplicate job_id job_id=JOB001 lines=2,3,4" が出る

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
    And stdout と stderr のどこにも "/home/batch/.ssh/id_green" は出ない

  Scenario: validate-config_sh_job-map は参照名の形式に合わない credential_ref を同じ warn で受理し値を出さない
    Given map.csv の 2 行目(JOB001)の credential_ref が "ssh key green"(空白を含み、"/" も "BEGIN" も含まない)である
    When `validate-config.sh --job-map map.csv --verbose` を実行する
    Then 終了コード 0 で stderr に "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" が 1 行だけ出る
    And stderr に "error:" で始まる行は出ない
    And stdout と stderr のどこにも "ssh key green" は出ない

  Scenario: validate-config_sh_job-map は正規表現に合っていても BEGIN を含む credential_ref を warn で報告する
    Given map.csv の 2 行目(JOB001)の credential_ref が BEGIN_KEY である
    When `validate-config.sh --job-map map.csv` を実行する
    Then 終了コード 0 で stderr に "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" が 1 行だけ出る
    And stdout と stderr のどこにも "BEGIN_KEY" は出ない

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
