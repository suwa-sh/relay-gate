# source: docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/ジョブマップで JOB_ID から実行先を解決する/tier-facade.md#ティア完了条件(BDD)
# 転写: gherkin ブロックを意訳せず転写(S2 test-scaffold 初回生成。uc_id=7c41c7cd)
# 再転写: 2026-11-24 S2 scoped 再実行(spec-event 20261123_201000_feedback_impl_feedback_7c41c7cd の仕様変更に追従。意訳せず転写)
Feature: ジョブマップで JOB_ID から実行先を解決する - facade / slot runner ティア

  Scenario: runner はヘッダー列名で列位置を決めて実行先を解決する
    Given RELAY_GATE_CONFIG_DIR/green-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version" である
    And CSV 行 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[""--mode"",""full""]",60,ssh-key-green,map-v3' がある
    And 環境変数 GREEN_JOB_MAP_CSV は未設定である(既定の場所を使う)
    When `<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background -- 20260830` を解決フェーズまで実行する
    Then 解決結果は host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work hang_detect_limit_minutes=60 credential_ref=ssh-key-green map_version=map-v3 である
    And 引数列は --mode / full / 20260830 の 3 個である

  Scenario: parse_csv_row は二重化された二重引用符を 1 文字に戻す
    Given CSV 行 'JOB001,,,/var/app/work,/opt/app/bin/job001.sh,"[""p1"",""p2 p3"",""a,b""]",60' がある
    When CSV 行分解関数 `parse_csv_row` にこの行を渡して呼ぶ(呼び方は契約 runner IF の standard_runner.runner_resolve_library)
    Then 戻り値は 0 で、配列 CSV_CELLS のセルは 7 個で、fixed_params セルは ["p1","p2 p3","a,b"] であり host と user のセルは空である

  Scenario: runner は host と user の列が無いジョブマップをローカル実行として解決する
    Given RELAY_GATE_CONFIG_DIR/blue-job-map.csv のヘッダーが "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" である
    And 行 "JOB001,/var/app/work,/opt/app/bin/job001.sh,[],0" がある
    When `<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role blue --mode foreground` を解決フェーズまで実行する
    Then 解決結果は host=null user=null(ローカル実行)credential_ref=null map_version=null である
    And 実行ログに "job map resolved job_id=JOB001 slot=blue host=- map_version=-" が出る

  Scenario: runner は host 列だけがあるヘッダーを終了コード 2 で拒否する
    Given RELAY_GATE_CONFIG_DIR/green-job-map.csv のヘッダーが "job_id,host,work_dir,script,fixed_params,hang_detect_limit_minutes" である
    When `<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background` を実行する
    Then 終了コード 2 で終了し、stderr.log は "error: job map header mismatch missing=user path: <RELAY_GATE_CONFIG_DIR>/green-job-map.csv" を含む

  Scenario: runner は impl_version 列を未知列として warn にとどめる
    Given RELAY_GATE_CONFIG_DIR/green-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,impl_version" である
    When `<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background` を解決フェーズまで実行する
    Then 解決は成功し、実行ログに "WARN unknown column column=impl_version path: <RELAY_GATE_CONFIG_DIR>/green-job-map.csv" が出る

  Scenario: build_argument_list は空白とカンマを含む要素を 1 引数として維持する
    Given fixed_params が ["p1","p2 p3","a,b"] で PARAM が x y である
    When 引数連結関数 `build_argument_list` に '["p1","p2 p3","a,b"]' と x y を渡して呼ぶ
    Then 配列 ARGUMENT_LIST は p1 / "p2 p3" / "a,b" / x / y の 5 個である

  Scenario: 自作の runner は共通ライブラリの解決の入口を呼んで標準の slot runner と同じ結果を受け取る
    Given RELAY_GATE_CONFIG_DIR / RELAY_GATE_ARTIFACT_ROOT / RELAY_GATE_LOG_DIR を設定し、RELAY_GATE_CONFIG_DIR/blue-job-map.csv のヘッダーが "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" で行 'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[""--mode"",""full""]",0' がある
    And 自作の runner が EXIT の trap を設定してから lib/runner-resolve.sh を source する
    When `resolve_execution_target my-runner.sh 20260830T113000-JOB001-3f9a1c2e JOB001 blue 20260830` を呼ぶ
    Then 戻り値は 0 で、EXECUTION_TARGET_EXEC は local、EXECUTION_TARGET_HOST と EXECUTION_TARGET_USER と EXECUTION_TARGET_CREDENTIAL_REF と EXECUTION_TARGET_MAP_VERSION は空文字、EXECUTION_TARGET_SCRIPT は /opt/app/bin/job001.sh である
    And 配列 ARGUMENT_LIST は --mode / full / 20260830 の 3 個で、RUNNER_RESOLVE_MAP_PATH は <RELAY_GATE_CONFIG_DIR>/blue-job-map.csv である
    And source の前後で set のオプションと EXIT の trap は変わらず、source と関数の呼び出しでプロセスの stdout と stderr には何も出ていない

  Scenario: 引数の違反の報告は run_id が分からないとき成果物を書かず RUNNER_RESOLVE_EXIT_CODE を 2 にする
    When 自作の runner が `runner_resolve_reject_invocation my-runner.sh "" green "option required option=--run-id"` を呼ぶ
    Then 戻り値は 0 以外で、RUNNER_RESOLVE_EXIT_CODE は 2 である
    And 実行ログに "ERROR option required option=--run-id" が出て、RELAY_GATE_ARTIFACT_ROOT/facade/ 配下にファイルは作られない

  Scenario: 自作の runner は解決できなかったとき RUNNER_RESOLVE_EXIT_CODE の値で終える
    Given RELAY_GATE_CONFIG_DIR/green-job-map.csv に JOB999 の行が無い
    When 自作の runner が `resolve_execution_target my-runner.sh 20260830T113000-JOB999-a1b2c3d4 JOB999 green` を呼ぶ
    Then 戻り値は 2 で、RUNNER_RESOLVE_EXIT_CODE は 2 である
    And RELAY_GATE_ARTIFACT_ROOT/facade/20260830T113000-JOB999-a1b2c3d4/green/exitcode.txt は "2" の 1 行である(関数が Runner Result を揃え済み)

  Scenario: 解決の入口は既存の exitcode.txt が 0 の二重起動のとき RUNNER_RESOLVE_STATUS_NOT_RESOLVED を返す
    Given RELAY_GATE_ARTIFACT_ROOT/facade/20260830T113000-JOB999-a1b2c3d4/green/exitcode.txt が "0" の 1 行で公開済みで、RELAY_GATE_CONFIG_DIR/green-job-map.csv に JOB999 の行が無い
    When 自作の runner が `resolve_execution_target my-runner.sh 20260830T113000-JOB999-a1b2c3d4 JOB999 green` を呼ぶ
    Then 戻り値は RUNNER_RESOLVE_STATUS_NOT_RESOLVED(1)で、RUNNER_RESOLVE_EXIT_CODE は 0 である
    And exitcode.txt は "0" の 1 行のまま変わらない

  Scenario: 二重起動の判定は既存の exitcode.txt が 0 のとき 0 以外を返して終了コード 0 を知らせる
    Given RELAY_GATE_ARTIFACT_ROOT/facade/20260830T113000-JOB001-3f9a1c2e/green/exitcode.txt が "0" の 1 行で公開済みである
    When 自作の runner が `runner_resolve_guard_existing_result 20260830T113000-JOB001-3f9a1c2e green` を呼ぶ
    Then 戻り値は 0 以外で、RUNNER_RESOLVE_EXIT_CODE は 0 である
    And 成果物ディレクトリのファイルは変わらない

  Scenario: runner は job_id 未定義のとき 3 ファイルと started-at.txt を揃えて終了コード 2 で終了する
    Given RELAY_GATE_CONFIG_DIR/green-job-map.csv に JOB999 の行が無い
    When `<runner> --run-id 20260830T113000-JOB999-a1b2c3d4 --job-id JOB999 --role green --mode background` を実行する
    Then 終了コード 2 で終了する
    And RELAY_GATE_ARTIFACT_ROOT/facade/20260830T113000-JOB999-a1b2c3d4/green/ に started-at.txt stdout.log stderr.log exitcode.txt が揃う
    And exitcode.txt は "2" の 1 行、stderr.log は "error: job_id=JOB999 not found in job map slot=green map=<RELAY_GATE_CONFIG_DIR>/green-job-map.csv" を含む
    And 同ディレクトリに .tmp サフィックスのファイルは残っていない

  Scenario: runner は --job-id 欠落を終了コード 2 で拒否する
    Given 正しいジョブマップがある
    When `<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --role green --mode background` を実行する
    Then 終了コード 2 で終了し、実行ログに "ERROR option required option=--job-id" が出る

  Scenario: runner は環境変数 GREEN_JOB_MAP_CSV に渡されたパスのジョブマップで解決し既定の場所のジョブマップを使わない
    Given RELAY_GATE_CONFIG_DIR/green-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" で、行 "JOB001,host-default-99,other,/var/default,/opt/default/job001.sh,[],60" がある
    And RELAY_GATE_CONFIG_DIR とは別のディレクトリ maps の green-jobs.csv のヘッダーが同じ 7 列で、行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60" がある
    And 環境変数 GREEN_JOB_MAP_CSV=<maps>/green-jobs.csv が設定されている
    When `<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background` を解決フェーズまで実行する
    Then 解決結果は host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work である(host-default-99 ではない)
    And 実行ログに "job map resolved job_id=JOB001 slot=green host=host-green-01 map_version=-" が出る

  Scenario: runner は環境変数 GREEN_JOB_MAP_CSV の値が空のとき既定の場所のジョブマップで解決する
    Given RELAY_GATE_CONFIG_DIR/green-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" で、行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60" がある
    And 環境変数 GREEN_JOB_MAP_CSV が空文字で設定されている
    When `<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background` を解決フェーズまで実行する
    Then 解決結果は host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work である

  Scenario: runner は job_id 未定義の error 行の map= に環境変数で渡されたパスを出す
    Given RELAY_GATE_CONFIG_DIR/green-job-map.csv に JOB999 の行がある
    And RELAY_GATE_CONFIG_DIR とは別のディレクトリ maps の green-jobs.csv に JOB999 の行が無い
    And 環境変数 GREEN_JOB_MAP_CSV=<maps>/green-jobs.csv が設定されている
    When `<runner> --run-id 20260830T113000-JOB999-a1b2c3d4 --job-id JOB999 --role green --mode background` を実行する
    Then 終了コード 2 で終了し、exitcode.txt は "2" の 1 行である
    And stderr.log は "error: job_id=JOB999 not found in job map slot=green map=<maps>/green-jobs.csv" を含む

  Scenario: runner はジョブマップが無いときの error 行の map= に環境変数で渡されたパスを出す
    Given RELAY_GATE_CONFIG_DIR/green-job-map.csv に JOB001 の行がある
    And RELAY_GATE_CONFIG_DIR とは別のディレクトリ maps に green-jobs.csv は存在しない
    And 環境変数 GREEN_JOB_MAP_CSV=<maps>/green-jobs.csv が設定されている
    When `<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background` を実行する
    Then 終了コード 2 で終了し、exitcode.txt は "2" の 1 行である
    And stderr.log は "error: job map not found slot=green map=<maps>/green-jobs.csv" を含む

  Scenario: runner は使ったパスにあるがディレクトリのジョブマップを config file is not readable で報告する
    Given RELAY_GATE_CONFIG_DIR とは別のディレクトリ maps に green-jobs.csv という名前のディレクトリがある
    And 環境変数 GREEN_JOB_MAP_CSV=<maps>/green-jobs.csv が設定されている
    When `<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background` を実行する
    Then 終了コード 2 で終了し、exitcode.txt は "2" の 1 行である
    And stderr.log は "error: config file is not readable path: <maps>/green-jobs.csv" を含み、"job map not found" を含まない(契約 job_map_location.presence_report)

  Scenario: 標準の slot runner はローカル実行の行と SSH 実行の行をそれぞれ解決する
    Given RELAY_GATE_CONFIG_DIR/blue-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" で、行 "JOB001,,,/var/app/work,/opt/app/bin/job001.sh,[],0"(host と user が両方空)がある
    And RELAY_GATE_CONFIG_DIR/green-job-map.csv のヘッダーが同じ 7 列で、行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60" がある
    And 環境変数 BLUE_JOB_MAP_CSV と GREEN_JOB_MAP_CSV は未設定である
    When 標準の slot runner を `<RELAY_GATE_HOME>/runners/standard-runner.sh --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role blue --mode foreground` で解決フェーズまで実行する
    And 同じ実体を `<RELAY_GATE_HOME>/runners/standard-runner.sh --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background` で解決フェーズまで実行する
    Then role=blue の解決結果は host=null user=null(ローカル実行)script=/opt/app/bin/job001.sh work_dir=/var/app/work である
    And role=green の解決結果は host=host-green-01 user=batch(SSH 実行)script=/opt/app/bin/job001.sh work_dir=/var/app/work である
    And 実行ログに "job map resolved job_id=JOB001 slot=blue host=- map_version=-" と "job map resolved job_id=JOB001 slot=green host=host-green-01 map_version=-" が出る
