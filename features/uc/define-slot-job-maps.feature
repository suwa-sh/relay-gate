# source: docs/specs/latest/適用構成業務/適用構成定義フロー/slot ごとのジョブマップを定義する/spec.md#E2E完了条件(BDD)
# 転写: 正常系・異常系の 2 ブロックを意訳せず結合(S2 test-scaffold scoped 再生成。uc_id=eff24f55。spec event 20260923_112000_feedback_impl_feedback_eff24f55_cycle2)
Feature: slot ごとのジョブマップを定義する

  Scenario: 有効なジョブマップを検証する(SPEC-004-01)
    Given /etc/relay-gate/green-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version" である
    And 行 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[""--mode"",""full""]",60,ssh-key-green,map-v3' と 'JOB002,host-green-01,batch,/var/app/work,/opt/app/bin/job002.sh,"[]",0,ssh-key-green,map-v3' がある
    When 基盤適用設計者が validate-config.sh --job-map /etc/relay-gate/green-job-map.csv を実行する
    Then 終了コード 0 で stdout に "map_path: /etc/relay-gate/green-job-map.csv" "rows=2" "map_version=map-v3" が出る

  Scenario: 元資料の列名の CSV ジョブマップを検証する(SPEC-004-04)
    Given green-job-map.csv のヘッダーが元資料どおりの "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" の 7 列である
    And 行 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60' がある
    When validate-config.sh --job-map を実行する
    Then 終了コード 0 で stdout に "rows=1" "map_version=-" が出る
    And stderr に "warn: unknown column" で始まる行は出ない

  Scenario: fixed_params セルの JSON 配列を CSV クォート規則で解析する(SPEC-004-04)
    Given green-job-map.csv の JOB001 行の fixed_params セルが '"[""p1"",""p2 p3""]"' である(二重引用符で囲み、内部の二重引用符を二重化)
    When validate-config.sh --job-map --verbose を実行する
    Then 終了コード 0 で stderr に 'info: resolved job_id=JOB001' と 'fixed_params=["p1","p2 p3"]' を含む 1 行が出る(固定引数は p1 と "p2 p3" の 2 要素)

  Scenario: host と user の列を持たないローカル実行用ジョブマップを検証する(SPEC-004-04)
    Given blue-job-map.csv のヘッダーが "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" で host / user 列が無い
    And 行 'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",0' がある
    When validate-config.sh --job-map /etc/relay-gate/blue-job-map.csv --verbose を実行する
    Then 終了コード 0 で stderr に "info: resolved job_id=JOB001 host=- user=- exec=local" で始まる行が出る

  Scenario: credential_ref と map_version の列が無くてもエラーにならない(SPEC-004-04)
    Given green-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" である
    When validate-config.sh --job-map を実行する
    Then 終了コード 0 で stdout に "map_version=-" が出る
    When ヘッダー末尾に credential_ref,map_version を加え各行に ssh-key-green,map-v3 を追記して再実行する
    Then 終了コード 0 で stdout に "map_version=map-v3" が出る

  Scenario: hang_detect_limit_minutes の変更は次回以降の run に反映される(SPEC-008-05)
    Given run_id=20260830T113000-JOB001-3f9a1c2e が execution-spec.json の slots.green.hang_detect_limit_minutes=60 で実行中である
    And green-job-map.csv の JOB001 行の hang_detect_limit_minutes を 60 から 90 に変更した
    When validate-config.sh --job-map /etc/relay-gate/green-job-map.csv --verbose を実行する
    Then 終了コード 0 で stderr に "info: resolved job_id=JOB001" と "hang_detect_limit_minutes=90" を含む 1 行が出る
    And 20260830T113000-JOB001-3f9a1c2e の execution-spec.json の slots.green.hang_detect_limit_minutes は 60 のままである

  Scenario: 導入時は全ジョブ 60 分・foreground slot の行は 0 で定義する
    Given 並行稼働モード(blue foreground / green background)で導入する
    When blue-job-map.csv の全行に hang_detect_limit_minutes=0、green-job-map.csv の全行に 60 を定義して validate-config.sh を実行する
    Then 両ファイルとも終了コード 0 で検証を通過する

  Scenario: 方針資料の Windows 形式パスと非 ASCII の値を含むジョブマップを受理する(SPEC-004-04)
    Given blue-job-map.csv がヘッダー "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" と方針資料の例の行 'TOMM0410010100,督促AP,saiken,G:\scripts,G:\scripts\xxx.bat,"[""param1"",""param2"",""param3""]",60' である
    When 基盤適用設計者が validate-config.sh --job-map /etc/relay-gate/blue-job-map.csv --verbose を実行する
    Then 終了コード 0 で stdout に "rows=1" が出て、stderr に "error:" で始まる行は出ない
    And stderr に 'info: resolved job_id=TOMM0410010100 host=督促AP user=saiken exec=ssh work_dir=G:\scripts script=G:\scripts\xxx.bat fixed_params=["param1","param2","param3"] hang_detect_limit_minutes=60' が出る(ホスト名・バックスラッシュは 1 バイトも変わらない)

  Scenario: 方針資料の相対パスのジョブマップを受理する(SPEC-004-04)
    Given green-job-map.csv がヘッダー "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" と方針資料の例の行 'TOMM0410010100,./beam-batches,./beam-batches/TOMM0410010100.sh,"[""param1"",""param2"",""param3""]",60' である
    When validate-config.sh --job-map /etc/relay-gate/green-job-map.csv を実行する
    Then 終了コード 0 で stdout に "rows=1" が出て、stderr に "error:" で始まる行は出ない

  Scenario: データ行 0 件のジョブマップは受理される
    Given green-job-map.csv がヘッダー行と行頭 # のコメント行だけで、最終行に改行が無い
    When validate-config.sh --job-map /etc/relay-gate/green-job-map.csv を実行する
    Then 終了コード 0 で stdout は "map_path: /etc/relay-gate/green-job-map.csv" "rows=0" "map_version=-" の 3 行である

  Scenario: 検証中に差し替わったファイルは複製した時点の内容だけで判定される
    Given green-job-map.csv のデータ行が 'J1,/old,/s,"[]",60' である
    And 検証コマンドが入力を一時ファイルへ複製した直後に、基盤適用設計者が job_id に NUL バイトを含む新しいファイルを mv で同じパスへ置き換える(契約 edit_rule どおりの運用。テストは TMPDIR 配下に最終名の一時ファイル(接頭辞 relay-gate-、末尾 .part の付かないもの)が現れたことを監視して置き換えのタイミングを決める。最終名が現れた時点で複製は完了している)
    When validate-config.sh --job-map /etc/relay-gate/green-job-map.csv --verbose を実行する
    Then 終了コード 0 で stderr に "info: resolved job_id=J1" と "work_dir=/old" を含む行が出る(旧内容と新内容を混ぜた結果は返さない)
    And stdout の "map_path:" は /etc/relay-gate/green-job-map.csv で、TMPDIR 配下の一時ファイルのパスは出ない
    And 終了後に TMPDIR 配下に一時ファイルは残らない

  Scenario: 固定引数が JSON 配列でない行は拒否される(SPEC-004-02)
    Given green-job-map.csv の 3 行目(JOB003)の fixed_params セルが '"p1,p2"' である
    When validate-config.sh --job-map を実行する
    Then 終了コード 2 で stderr に "error: fixed_params is not a json array of strings line=3 job_id=JOB003 value=p1,p2" が出る

  Scenario: クォートが不正な CSV は拒否される
    Given green-job-map.csv の 2 行目の fixed_params セルが '"[""--mode"",""full""]' で閉じ引用符が無い
    When validate-config.sh --job-map を実行する
    Then 終了コード 2 で stderr に "error: csv quote is invalid line=2 path: /etc/relay-gate/green-job-map.csv" が出る

  Scenario: job_id が重複するジョブマップは拒否される
    Given green-job-map.csv に job_id=JOB001 の行が 2 行目と 5 行目にある
    When validate-config.sh --job-map を実行する
    Then 終了コード 2 で stderr に "error: duplicate job_id job_id=JOB001 lines=2,5" が出る(初出行 2 を含む)
    And stderr に "duplicate job_id" を含む行は 1 行だけである

  Scenario: ヘッダーに必須列が無いジョブマップは拒否される
    Given green-job-map.csv のヘッダーに hang_detect_limit_minutes 列が無い
    When validate-config.sh --job-map を実行する
    Then 終了コード 2 で stderr に "error: job map header mismatch missing=hang_detect_limit_minutes path: /etc/relay-gate/green-job-map.csv" が出る

  Scenario: host と user の片方だけの列は拒否される
    Given green-job-map.csv のヘッダーに host 列はあるが user 列が無い
    When validate-config.sh --job-map を実行する
    Then 終了コード 2 で stderr に "error: job map header mismatch missing=user path: /etc/relay-gate/green-job-map.csv" が出る

  Scenario: host と user の片方だけが空の行は拒否される
    Given green-job-map.csv の 2 行目(JOB001)の host が host-green-01 で user が空である
    When validate-config.sh --job-map を実行する
    Then 終了コード 2 で stderr に "error: user is empty line=2 job_id=JOB001 value=" が出る

  Scenario: hang_detect_limit_minutes が非負整数でない行は拒否される
    Given green-job-map.csv の 2 行目の hang_detect_limit_minutes が "60m" である
    When validate-config.sh --job-map を実行する
    Then 終了コード 2 で stderr に "error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=60m" が出る

  Scenario: 実装版の列は未知列として警告される
    Given green-job-map.csv のヘッダー末尾に impl_version 列がある
    When validate-config.sh --job-map を実行する
    Then 終了コード 0 で stderr に "warn: unknown column column=impl_version path: /etc/relay-gate/green-job-map.csv" が出る

  Scenario: 認証情報らしい値は警告される
    Given green-job-map.csv の credential_ref が /home/batch/.ssh/id_green である
    When validate-config.sh --job-map を実行する
    Then 終了コード 0 で stderr に "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" が出る
    And stdout と stderr のどこにも "/home/batch/.ssh/id_green" は出ない

  Scenario: 参照名の形式に合わない credential_ref は同じ警告で受理され値は出力されない
    Given green-job-map.csv の 2 行目(JOB001)の credential_ref が "ssh key green"(空白を含み、"/" も "BEGIN" も含まない)である
    When validate-config.sh --job-map --verbose を実行する
    Then 終了コード 0 で stderr に "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" が 1 行だけ出る
    And stderr に "error:" で始まる行は出ず、stdout に "rows=" が出る(受理される)
    And stdout と stderr のどこにも "ssh key green" は出ない

  Scenario: 形式から外れた入力は原因ごとの文言で拒否される
    Given 次の 5 つのジョブマップがある: (a) 2 行目の job_id に NUL バイトを含む (b) 2 行目が Shift_JIS のコメント行 (c) 先頭に BOM がある (d) 全行が CRLF で終わる (e) ヘッダーに job_id 列が 2 つある
    When それぞれに validate-config.sh --job-map を実行する
    Then いずれも終了コード 2 で、stderr は順に "error: nul byte is not allowed line=2 path: ..." / "error: encoding is not utf-8 line=2 path: ..." / "error: byte order mark is not allowed line=1 path: ..." / "error: carriage return is not allowed line=1 path: ..." と "hint: use LF line endings" / "error: duplicate column column=job_id path: ..." を含む
    And (a)(b) の stderr に "csv quote is invalid" は出ず、(c) の stderr に "job map header mismatch" は出ない(利用者が error 行だけで原因を区別できる)

  Scenario: 検証器の内部障害は検証結果にならない
    Given TMPDIR が書き込めないディレクトリを指している
    When validate-config.sh --job-map /etc/relay-gate/green-job-map.csv を実行する
    Then 終了コード 6 で stderr に "error: config snapshot failed path: /etc/relay-gate/green-job-map.csv" と "hint: check TMPDIR is writable" が出る
    And stdout は 0 行で、"rows=" は出ない(検証 OK も違反も返さない)

  Scenario: 出力する値の制御文字は可視表記になる(SPEC-004-04)
    Given green-job-map.csv の JOB001 行の hang_detect_limit_minutes が "6<TAB>0"(タブを含む)で、ヘッダー末尾に列名 "note<ESC>[31m"(ESC を含む)がある
    When validate-config.sh --job-map を実行する
    Then 終了コード 2 で stderr に 'error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=6\t0' と 'warn: unknown column column=note\u001b[31m path: /etc/relay-gate/green-job-map.csv' が出る
    And stderr のどの行にも生の ESC・タブは含まれず、行数は増えない(1 行 1 事実)
