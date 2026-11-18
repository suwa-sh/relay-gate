# source: docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/tier-facade.md#ティア完了条件(BDD)
# 転写: gherkin ブロックを意訳せず転写(S2 test-scaffold 初回生成。uc_id=09730858)
Feature: slot 実行モードを選択して runner を起動する - facade / slot runner ティア

  Scenario: facade_sh は background を先に起動し foreground だけを wait する
    Given RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2 BLUE_RUNNER=<記録用スタブ runner> GREEN_RUNNER=<記録用スタブ runner> がある
    And スタブ runner は起動引数・環境変数・起動時刻をファイルに記録し、green は 30 秒 sleep、blue は exitcode.txt に 0 を書いて即終了する
    When `facade.sh JOB001 20260830 full` を実行する
    Then 終了コード 0 で終了し、green の起動記録が blue より先である
    And green の起動引数は "--run-id <run_id> --job-id JOB001 --role green --mode background -- 20260830 full" である
    And green の記録した環境変数に GREEN_IMPL=v2 と RAPID_CROSSCHECK_MODE=off があり RAPID_CROSSCHECK_RUNNER は無い
    And <run_id> は正規表現 ^[0-9]{8}T[0-9]{6}-JOB001-[0-9a-f]{8}$ に一致する
    And facade の終了時に green のスタブはまだ実行中である

  Scenario: facade_sh は両 slot foreground を終了コード 2 で拒否する
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off がある
    When `facade.sh JOB001` を実行する
    Then 終了コード 2 で stderr に "error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground" が出る
    And スタブ runner の起動記録は存在しない
    And RELAY_GATE_ARTIFACT_ROOT/facade/ 配下にディレクトリは作成されない

  Scenario: facade_sh は RAPID_CROSSCHECK_MODE=background で parallel_runs を STARTED から RUNNING へ更新する
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=background BLUE_IMPL=v1 RAPID_CROSSCHECK_RUNNER=<実行可能なスタブ> RAPID_CROSSCHECK_WORKER=<実行可能なスタブ> がある
    And 管理 DB が起動している
    When `facade.sh JOB001` を実行する
    Then parallel_runs に run_id job_id=JOB001 status=RUNNING parameters=[] の行が 1 件ある
    And parallel_runs.run_id は成果物ディレクトリ facade/<run_id>/ の名前と同じ値である
    And 実行ログに "parallel_run status changed from=STARTED to=RUNNING run_id=<run_id>" が出る
    And 実行ログの "feature flag loaded" 行に "blue_impl=v1" と "operation_mode=custom" が含まれ "config_version=" は含まれない
    And blue のスタブ runner が記録した環境変数に RAPID_CROSSCHECK_RUNNER=<実行可能なスタブ> がある

  Scenario: facade_sh は RAPID_CROSSCHECK_MODE=foreground を background と同じに扱う
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=foreground があり管理 DB が起動している
    When `facade.sh JOB001` を実行する
    Then parallel_runs に run_id の行が status=RUNNING で 1 件あり rapid_runs に completion_status=PENDING の行が 1 件ある

  Scenario: facade_sh は runner 起動前に slot_executions を pid=NULL で INSERT し起動後に pid を更新する
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background があり管理 DB が起動している
    And RDB クライアント CLI のパスに SQL を順序つきで記録して実 DB へ転送するラッパーを置く
    And green のスタブ runner は起動直後に exitcode.txt=2 を書いて終了し、自分の slot_executions 行を RUNNING → FAILED に更新する
    When `facade.sh JOB001` を実行する
    Then 記録された SQL は slot_executions の INSERT(slot=green, pid NULL)が green runner 起動より前で、pid の UPDATE がその後である
    And 最終的に slot_executions の slot=green の行は status=FAILED exit_code=2 で pid が設定されている(runner 側の終端 UPDATE が 0 件にならない)

  Scenario: facade_sh は RAPID_CROSSCHECK_MODE=background で rapid-crosscheck.env が無ければ終了コード 2 で終了する
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=background BLUE_IMPL=v1 BLUE_RUNNER=<記録用スタブ runner> RAPID_CROSSCHECK_RUNNER=<実行可能なスタブ> RAPID_CROSSCHECK_WORKER=<実行可能なスタブ> がある(feature-flag.env のキーごとの検査を通る設定)
    And RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env が存在しない
    When `facade.sh JOB001` を実行する
    Then 終了コード 2 で stderr に "error: config file not found path: <RELAY_GATE_CONFIG_DIR>/rapid-crosscheck.env" が出る
    And どの runner も起動されない

  Scenario: facade_sh は速報クロスチェック設定の RAPID_DB_CONN_REF を参照名としてだけ使い認証情報の値を出さない(SPEC-005-06)
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=background があり管理 DB が起動している
    And RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env に RAPID_DB_CONN_REF=mgmt-db RAPID_LEASE_SEC=600 RAPID_POLL_INTERVAL_SEC=30 だけがあり、パスワード・接続文字列の値は無い
    And RDB クライアント CLI のパスに引数と環境変数を記録して実 DB へ転送するラッパーを置く
    When `facade.sh JOB001` を実行する
    Then parallel_runs に run_id の行が status=RUNNING で 1 件ある
    And RDB クライアントラッパーの記録には参照名 mgmt-db があり、実行ログと stderr には参照名から解決した接続情報の値が無い

  Scenario: facade_sh は RAPID_CROSSCHECK_MODE=off で RDB クライアントを呼ばず rapid-crosscheck.env も読まない(SPEC-005-06)
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off がある
    And RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env が存在しない
    And RDB クライアント CLI のパスに呼び出し記録用スタブを置く
    When `facade.sh JOB001` を実行する
    Then 終了コード 0 で終了し、RDB クライアントスタブの呼び出し記録は存在しない
    And blue と green のスタブ runner の起動記録がある

  Scenario: facade_sh は runner 実体が実行不可なら終了コード 2 で終了する
    Given feature-flag.env に BLUE_MODE=foreground BLUE_IMPL=v1 BLUE_RUNNER=<実行可能な runner> GREEN_MODE=background GREEN_IMPL=v2 GREEN_RUNNER=/opt/relay-gate/runners/missing.sh RAPID_CROSSCHECK_MODE=off がある
    When `facade.sh JOB001` を実行する
    Then 終了コード 2 で stderr に "error: file not executable key=GREEN_RUNNER path=/opt/relay-gate/runners/missing.sh" が出る
    And blue runner も起動されない

  Scenario: facade_sh は未知キーを warn にとどめ 9 キー以外を必須にしない
    Given feature-flag.env に 9 キーがすべて正しく定義され、加えて CONFIG_VERSION=2026-08-30 がある
    When `facade.sh JOB001` を実行する
    Then stderr に "warn: unknown key key=CONFIG_VERSION path: <RELAY_GATE_CONFIG_DIR>/feature-flag.env" が出るが終了コードは foreground の exitcode.txt の値である

  Scenario: facade_sh は JOB_ID 欠落を終了コード 2 で拒否する
    Given feature-flag.env が正しく定義されている
    When `facade.sh` を引数なしで実行する
    Then 終了コード 2 で stderr に "error: JOB_ID required" が出る

  Scenario: facade_sh は相対パスの runner を設定ファイルのあるディレクトリ基準で起動し速報 runner を解決後のパスで渡す
    Given RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=background BLUE_IMPL=v1 BLUE_RUNNER=./blue-runner.sh RAPID_CROSSCHECK_RUNNER=./rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=./rapid-crosscheck-worker.sh がある
    And RELAY_GATE_CONFIG_DIR のディレクトリに、起動引数と環境変数を記録して exitcode.txt に 0 を書く実行可能なスタブ blue-runner.sh と、実行可能な rapid-crosscheck-runner.sh / rapid-crosscheck-worker.sh があり、管理 DB が起動している
    And RELAY_GATE_CONFIG_DIR は末尾に `/` の無い絶対パスで、そのディレクトリに RAPID_DB_CONN_REF を書いた rapid-crosscheck.env と、JOB001 の行を含む blue-job-map.csv がある
    And 作業ディレクトリにするディレクトリ work(RELAY_GATE_CONFIG_DIR とは別)に、起動されたら記録を残す別の実行可能な blue-runner.sh がある
    When work を作業ディレクトリにして `facade.sh JOB001` を実行する
    Then 終了コード 0 で、RELAY_GATE_CONFIG_DIR のスタブ blue-runner.sh が 1 回起動され、work の blue-runner.sh は起動されていない
    And スタブが記録した環境変数 RAPID_CROSSCHECK_RUNNER は "<RELAY_GATE_CONFIG_DIR>/./rapid-crosscheck-runner.sh" である(契約 config_files.feature-flag.env.runner_path_resolution)

  Scenario: facade_sh は相対パスの runner 実体が無ければ解決後のパスを報告して終了コード 2 で終了する
    Given RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground BLUE_IMPL=v1 BLUE_RUNNER=<実行可能な runner の絶対パス> GREEN_MODE=background GREEN_IMPL=v2 GREEN_RUNNER=./green-runner.sh RAPID_CROSSCHECK_MODE=off がある
    And RELAY_GATE_CONFIG_DIR は末尾に `/` の無い絶対パスで、そのディレクトリに green-runner.sh は無く、作業ディレクトリにするディレクトリ work に実行可能な green-runner.sh がある
    When work を作業ディレクトリにして `facade.sh JOB001` を実行する
    Then 終了コード 2 で stderr に "error: file not executable key=GREEN_RUNNER path=<RELAY_GATE_CONFIG_DIR>/./green-runner.sh" が出る
    And どの runner も起動されず、stderr に "path is not absolute" を含む行は出ない

  Scenario: facade_sh は設定の違反が 2 つあるとき検証コマンドの error 行の順で最初の違反の 1 行だけを出す
    Given RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 BLUE_RUNNER=relative/blue-runner.sh GREEN_RUNNER=<記録用スタブ runner> があり、GREEN_IMPL の行は無い
    And RELAY_GATE_CONFIG_DIR は末尾に `/` の無い絶対パスで、<RELAY_GATE_CONFIG_DIR>/relative/blue-runner.sh は無い
    When `facade.sh JOB001` を実行する
    Then 終了コード 2 で、stderr は "error: file not executable key=BLUE_RUNNER path=<RELAY_GATE_CONFIG_DIR>/relative/blue-runner.sh" の 1 行だけである
    And stderr に "option=GREEN_IMPL" を含む行は出ない
    And その 1 行は、同じファイルを `validate-config.sh --feature-flag <RELAY_GATE_CONFIG_DIR>/feature-flag.env` で検証したときの stderr の最初の error 行と同じである
    And スタブ runner の起動記録は存在せず、RELAY_GATE_ARTIFACT_ROOT/facade/ 配下にディレクトリは作成されない

  Scenario: facade_sh は最初の違反に hint が続くとき error 行と hint の 2 行だけを出す
    Given RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=maybe だけがある
    When `facade.sh JOB001` を実行する
    Then 終了コード 2 で、stderr は 1 行目 "error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe"、2 行目 "hint: use foreground, background or off" の 2 行だけである
    And stderr に "foreground slot must be exactly one" を含む行も "option required" を含む行も出ない
    And RELAY_GATE_ARTIFACT_ROOT/facade/ 配下にディレクトリは作成されない

  Scenario: facade_sh は未知キーの warn 行を最初の違反の error 行より前に出す
    Given RELAY_GATE_CONFIG_DIR/feature-flag.env に CONFIG_VERSION=2026-08-30 BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 BLUE_RUNNER=relative/blue-runner.sh GREEN_RUNNER=<記録用スタブ runner> があり、GREEN_IMPL の行は無い
    And RELAY_GATE_CONFIG_DIR は末尾に `/` の無い絶対パスで、<RELAY_GATE_CONFIG_DIR>/relative/blue-runner.sh は無い
    When `facade.sh JOB001` を実行する
    Then 終了コード 2 で、stderr は 1 行目 "warn: unknown key key=CONFIG_VERSION path: <RELAY_GATE_CONFIG_DIR>/feature-flag.env"、2 行目 "error: file not executable key=BLUE_RUNNER path=<RELAY_GATE_CONFIG_DIR>/relative/blue-runner.sh" の 2 行だけである
    And スタブ runner の起動記録は存在しない

  Scenario: facade_sh は相対パスの BLUE_JOB_MAP_CSV を設定ファイルのあるディレクトリ基準で解決して blue の runner へ渡しキーの無い green の runner へ既定の場所を渡す
    Given RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2 BLUE_RUNNER=<記録用スタブ runner> GREEN_RUNNER=<記録用スタブ runner> BLUE_JOB_MAP_CSV=./maps/blue-jobs.csv があり、GREEN_JOB_MAP_CSV の行は無い
    And RELAY_GATE_CONFIG_DIR は末尾に `/` の無い絶対パスで、<RELAY_GATE_CONFIG_DIR>/maps/blue-jobs.csv も <RELAY_GATE_CONFIG_DIR>/green-job-map.csv も存在しない
    And スタブ runner は起動引数と環境変数をファイルに記録し、exitcode.txt に 0 を書いて終了する
    And facade.sh を起動するプロセスの環境に BLUE_JOB_MAP_CSV=/tmp/other-blue.csv と GREEN_JOB_MAP_CSV=/tmp/other-green.csv がある
    When RELAY_GATE_CONFIG_DIR とは別のディレクトリ work を作業ディレクトリにして `facade.sh JOB001` を実行する
    Then 終了コード 0 で終了し、blue のスタブの起動引数は "--run-id <run_id> --job-id JOB001 --role blue --mode foreground --" である
    And blue のスタブが記録した環境変数 BLUE_JOB_MAP_CSV は "<RELAY_GATE_CONFIG_DIR>/./maps/blue-jobs.csv" である(契約 config_files.feature-flag.env.job_map_location)
    And green のスタブが記録した環境変数 GREEN_JOB_MAP_CSV は "<RELAY_GATE_CONFIG_DIR>/green-job-map.csv" である
    And stderr に "job map not found" を含む行は出ない(facade はジョブマップの存在を検査しない)

  Scenario: facade_sh は値が空の GREEN_JOB_MAP_CSV の行がある設定で green の runner へ既定の場所を渡す
    Given RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2 BLUE_RUNNER=<記録用スタブ runner> GREEN_RUNNER=<記録用スタブ runner> があり、加えて値が空の行 `GREEN_JOB_MAP_CSV=` がある
    And RELAY_GATE_CONFIG_DIR は末尾に `/` の無い絶対パスである
    And スタブ runner は起動引数と環境変数をファイルに記録し、exitcode.txt に 0 を書いて終了する
    When `facade.sh JOB001` を実行する
    Then 終了コード 0 で終了し、green のスタブが記録した環境変数 GREEN_JOB_MAP_CSV は "<RELAY_GATE_CONFIG_DIR>/green-job-map.csv" である(空の値ではない。契約 config_files.feature-flag.env.job_map_location)
    And stderr に "warn: unknown key key=GREEN_JOB_MAP_CSV" を含む行は出ない
