# source: docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/ジョブマップで JOB_ID から実行先を解決する/spec.md#E2E完了条件(BDD)
# 転写: 正常系・異常系の 2 ブロックを意訳せず結合(S2 test-scaffold 初回生成。uc_id=7c41c7cd)
Feature: ジョブマップで JOB_ID から実行先を解決する

  Scenario: ジョブマップの行から実行先を解決する(SPEC-004-01)
    Given green-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version" である
    And 行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60,ssh-key-green,map-v3" がある
    When facade が green runner を --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する
    Then runner は host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work hang_detect_limit_minutes=60 credential_ref=ssh-key-green map_version=map-v3 を解決する
    And 実行ログに "job map resolved job_id=JOB001 slot=green host=host-green-01 map_version=map-v3" が出る

  Scenario: CSV の列名で読み替えなしに実行先を解決する(SPEC-004-04)
    Given green-job-map.csv のヘッダーが元資料どおりの "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" である
    And 行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60" がある
    When facade が green runner を --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する
    Then 列名の読み替えなしに host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work fixed_params=[] hang_detect_limit_minutes=60 が得られる
    And credential_ref と map_version は null として扱われる

  Scenario: 固定引数の後ろに PARAM を順序保持で連結する(SPEC-004-02)
    Given blue-job-map.csv の JOB001 行の fixed_params が ["p1","p2 p3"] である
    When facade が blue runner を --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role blue --mode foreground -- a b で起動する
    Then 実装へ渡す引数は 4 個で、順に p1 / "p2 p3" / a / b である

  Scenario: 二重引用符で囲んだ fixed_params セルを 2 引数として解析する(SPEC-004-04)
    Given blue-job-map.csv の JOB001 行の fixed_params セルが "[""p1"",""p2 p3""]" と書かれている
    When facade が blue runner を --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role blue --mode foreground で起動する
    Then 固定引数は p1 と "p2 p3" の 2 引数として得られ、空白とカンマは維持される

  Scenario: host と user の列が無いジョブマップはローカル実行として解決する(SPEC-004-04)
    Given blue-job-map.csv のヘッダーが "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" である
    And 行 "JOB001,/var/app/work,/opt/app/bin/job001.sh,[],0" がある
    When facade が blue runner を --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role blue --mode foreground で起動する
    Then runner は host=null user=null のローカル実行として解決する(SSH しない)

  Scenario: credential_ref と map_version の列が無くても解決できる(SPEC-004-04)
    Given green-job-map.csv のヘッダーに credential_ref と map_version が無い
    When facade が green runner を --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する
    Then エラーにならず credential_ref=null map_version=null で解決する
    And 実行ログの "job map resolved" 行は map_version=- を含む

  Scenario: 空の固定引数は PARAM だけを渡す
    Given blue-job-map.csv の JOB002 行の fixed_params が [] である
    When facade が blue runner を --run-id 20260830T113000-JOB002-5c7d9e0f --job-id JOB002 --role blue --mode foreground -- 20260830 で起動する
    Then 実装へ渡す引数は 1 個で 20260830 である

  Scenario: feature flag に書いた場所のジョブマップで実行先を解決し、固定の名前のジョブマップは使わない
    Given RELAY_GATE_CONFIG_DIR は /etc/relay-gate で、/etc/relay-gate/feature-flag.env に GREEN_JOB_MAP_CSV=/srv/relay-gate/maps/green-jobs.csv が定義されている
    And /srv/relay-gate/maps/green-jobs.csv に行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60" がある
    And /etc/relay-gate/green-job-map.csv に行 "JOB001,host-default-99,other,/var/default,/opt/default/job001.sh,[],60" がある
    When facade が green runner を環境変数 GREEN_JOB_MAP_CSV=/srv/relay-gate/maps/green-jobs.csv と --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する
    Then runner は host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work を解決する
    And 実行ログに "job map resolved job_id=JOB001 slot=green host=host-green-01 map_version=-" が出る

  Scenario: 環境変数でジョブマップの場所を受け取らない起動では既定の場所のジョブマップで解決する
    Given RELAY_GATE_CONFIG_DIR は /etc/relay-gate で、環境変数 GREEN_JOB_MAP_CSV は未設定である
    And /etc/relay-gate/green-job-map.csv に行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60" がある
    When green runner を facade を介さずに --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する
    Then runner は host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work を解決する

  Scenario: 標準の slot runner はローカル実行の行と SSH 実行の行をそれぞれ解決する
    Given feature flag の BLUE_RUNNER と GREEN_RUNNER の両方に標準の slot runner /opt/relay-gate/runners/standard-runner.sh が割り当てられている
    And blue のジョブマップのヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" で、行 "JOB001,,,/var/app/work,/opt/app/bin/job001.sh,[],0"(host と user が両方空)がある
    And green のジョブマップのヘッダーが同じ 7 列で、行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60" がある
    When facade が標準の slot runner を --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role blue --mode foreground と --role green --mode background でそれぞれ起動する
    Then role=blue の runner は host=null user=null のローカル実行として解決する(SSH しない)
    And role=green の runner は host=host-green-01 user=batch の SSH 実行として解決する

  Scenario: ジョブマップ未定義でも 3 ファイルを揃えて非 0 終了する(SPEC-003-02)
    Given RELAY_GATE_CONFIG_DIR は /etc/relay-gate である
    And green-job-map.csv に job_id=JOB999 の行が無い
    When facade が green runner を --run-id 20260830T113000-JOB999-a1b2c3d4 --job-id JOB999 --role green --mode background で起動する
    Then runner は終了コード 2 で終了する
    And facade/20260830T113000-JOB999-a1b2c3d4/green/ に stdout.log(空)・stderr.log・exitcode.txt が揃う
    And exitcode.txt の中身は "2" である
    And stderr.log に "error: job_id=JOB999 not found in job map slot=green map=/etc/relay-gate/green-job-map.csv" が含まれる

  Scenario: ジョブマップファイルが無い場合も 3 ファイルを揃える
    Given RELAY_GATE_CONFIG_DIR は /etc/relay-gate である
    And /etc/relay-gate/green-job-map.csv が存在しない
    When facade が green runner を --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する
    Then runner は終了コード 2 で終了し、exitcode.txt の中身は "2" である
    And stderr.log に "error: job map not found slot=green map=/etc/relay-gate/green-job-map.csv" が含まれる

  Scenario: feature flag に書いた場所のジョブマップに行が無い・ファイルが無いときは、その場所を map= に出す
    Given RELAY_GATE_CONFIG_DIR は /etc/relay-gate で、/etc/relay-gate/green-job-map.csv に JOB001 と JOB999 の行がある
    And /srv/relay-gate/maps/green-jobs.csv に JOB999 の行が無く、/srv/relay-gate/maps/missing-job-map.csv は存在しない
    When facade が green runner を環境変数 GREEN_JOB_MAP_CSV=/srv/relay-gate/maps/green-jobs.csv と --run-id 20260830T113000-JOB999-a1b2c3d4 --job-id JOB999 --role green --mode background で起動する
    And facade が green runner を環境変数 GREEN_JOB_MAP_CSV=/srv/relay-gate/maps/missing-job-map.csv と --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する
    Then どちらの runner も終了コード 2 で終了し、exitcode.txt の中身は "2" である
    And 1 つ目の stderr.log に "error: job_id=JOB999 not found in job map slot=green map=/srv/relay-gate/maps/green-jobs.csv" が含まれる
    And 2 つ目の stderr.log に "error: job map not found slot=green map=/srv/relay-gate/maps/missing-job-map.csv" が含まれる

  Scenario: fixed_params が JSON 配列でない行は解決失敗にする
    Given green-job-map.csv の 3 行目 JOB003 の fixed_params セルが "p1 p2"(配列でない)である
    When facade が green runner を --run-id 20260830T113000-JOB003-6d8e0f1a --job-id JOB003 --role green --mode background で起動する
    Then runner は終了コード 2 で終了し、stderr.log に "error: fixed_params is not a json array of strings line=3 job_id=JOB003 value=p1 p2" が含まれる

  Scenario: host と user の片方だけが空の行は解決失敗にする
    Given green-job-map.csv の 2 行目 JOB004 の host が host-green-01 で user が空である
    When facade が green runner を --run-id 20260830T113000-JOB004-7e9f1a2b --job-id JOB004 --role green --mode background で起動する
    Then runner は終了コード 2 で終了し、stderr.log に "error: user is empty line=2 job_id=JOB004 value=" が含まれる

  Scenario: 閉じていない二重引用符のセルは解決失敗にする
    Given RELAY_GATE_CONFIG_DIR は /etc/relay-gate である
    And green-job-map.csv の 2 行目の fixed_params セルが "[""p1"" で閉じていない
    When facade が green runner を --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する
    Then runner は終了コード 2 で終了し、stderr.log に "error: csv quote is invalid line=2 path: /etc/relay-gate/green-job-map.csv" が含まれる
