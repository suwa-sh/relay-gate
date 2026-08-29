# source: docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/spec.md#E2E完了条件(BDD)
# 転写ルール: 正常系・異常系の 2 つの gherkin ブロックを同一 Feature としてそのまま連結(dev-rules/test-strategy.md)
Feature: feature flag設定に基づきslotを選択して起動する

  Background:
    Given 環境変数 RELAYGATE_JOB_MAP_PATH_BLUE=/etc/relaygate/job-map.blue.json, RELAYGATE_JOB_MAP_PATH_GREEN=/etc/relaygate/job-map.green.json, RELAYGATE_CREDENTIAL_DIR=/etc/relaygate/credentials が設定されている
    And blue のジョブマップ /etc/relaygate/job-map.blue.json は job_map_version="v1.4.0", slot_type="blue" で、jobs."daily-settlement" が host="blue-host-01", exec_user="batchuser", script_path="/opt/blue/run.sh", work_dir="/opt/relaygate/work", fixed_args=["--mode","batch"], impl_version="blue-2.3.1", credential_ref="cred-blue-batch", hang_detect_limit_minutes=30 に定義されている
    And green のジョブマップ /etc/relaygate/job-map.green.json は job_map_version="v1.4.0", slot_type="green" で、jobs."daily-settlement" が host="green-host-01", exec_user="batchuser", script_path="/opt/green/run.sh", work_dir="/opt/relaygate/work", fixed_args=["--mode","batch"], impl_version="green-0.9.0", credential_ref="cred-green-batch", hang_detect_limit_minutes=45 に定義されている
    And 認証情報ディレクトリに /etc/relaygate/credentials/cred-blue-batch と /etc/relaygate/credentials/cred-green-batch のSSH秘密鍵（パーミッション 0600）が配置されている

  Scenario: BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を、attempt_id発番が blue="att-blue-0001" / green="att-green-0001" を返すよう固定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 0 で終了する
    And execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", parent_run_id=NULL, job_id="daily-settlement", additional_args=[], hang_detect_limit_minutes=45 の1行がINSERTされる（hang_detect_limit_minutesはbackground roleに選ばれたgreenのジョブマップ値）
    And slot_execution_specs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", host="blue-host-01", impl_version="blue-2.3.1", credential_ref="cred-blue-batch", job_map_version="v1.4.0") と (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", host="green-host-01", impl_version="green-0.9.0", credential_ref="cred-green-batch", job_map_version="v1.4.0") の2行が (run_id, slot_type) で一意に識別されるようINSERTされる
    And slot_execution_specs には認証情報の参照名（credential_ref）のみが保存され、パスワード・秘密鍵などの認証情報の実値は保存されない
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="foreground", attempt_id="att-blue-0001", attempt_no=1, status="STARTING") と (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001", attempt_no=1, status="STARTING") の2行が accepted_at 付きでINSERTされる
    And runner_result_events に対応する event_name="attempt_started", status="STARTING" の履歴が同一transactionでINSERTされ、各行の occurred_at は対応する runner_results の accepted_at および updated_at とマイクロ秒精度で同一値である
    And audit_logs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", event_name="slot_launch_accepted", slot="-", attempt_id="-", actor="ops-tanaka", operation="slot_launch", outcome="accepted", schema_version="1.0") の起動前監査イベントがINSERTされ、audit_chain_heads の run_id 行が更新される
    And audit_logs の各行の event_hash は audit-event-contract.yaml の hash_chain.canonical_form に従って当該行から再計算した値と一致する
    And 標準出力に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" の blue/foreground/att-blue-0001/STARTING 行と green/background/att-green-0001/STARTING 行が出力される

  Scenario: RAPID_CROSSCHECK_MODE=offの場合は速報管理DBへ接続しない
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=off, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を返すよう固定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 0 で終了する
    And rapid_crosscheck_requests へのINSERTは発生しない

  Scenario: BLUE_MODE=off, GREEN_MODE=foregroundで新実装単独本番の運用モードとして起動する
    Given 環境変数に BLUE_MODE=off, GREEN_MODE=foreground, RAPID_CROSSCHECK_MODE=off, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And 環境変数 RELAYGATE_JOB_MAP_PATH_BLUE が未設定である
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を、attempt_id発番が "att-green-0001" を返すよう固定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 0 で終了する（blueはoffのためblueのジョブマップは読まれず、環境変数未設定でもエラーにならない）
    And execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", hang_detect_limit_minutes=45 の1行が、slot_execution_specs に slot_type="green", job_map_version="v1.4.0" の1行のみがINSERTされる（backgroundのslotが無いため起動対象の唯一のslotであるgreenの値を採用）
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="foreground", attempt_id="att-green-0001", attempt_no=1, status="STARTING") の1行がINSERTされる
    And 標準出力に green/foreground/att-green-0001/STARTING の1行のみが出力される（運用モード: 新実装単独本番に相当する組み合わせ）

  Scenario: BLUE_MODE=background, GREEN_MODE=backgroundの場合は両ジョブマップのhang_detect_limit_minutesの大きい方を採用する
    Given 環境変数に BLUE_MODE=background, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を返すよう固定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 0 で終了する
    And execution_specs の run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" 行の hang_detect_limit_minutes は 45 である（blue=30, green=45 のうち大きい方）
    And slot_execution_specs に slot_type="blue" と slot_type="green" の2行が job_map_version="v1.4.0" でINSERTされる

  Scenario: background roleを先に起動しforegroundの完了を待たずに応答する
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を、attempt_id発番が blue="att-blue-0001" / green="att-green-0001" を返すよう固定されている
    And blue実装のforeground実行が完了まで60秒かかる状態である
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then green実装へのbackground起動イベントの送出が、blue実装へのforeground起動イベントの送出より先に完了する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001") が status="STARTING" で存在する
    And CLIは blue foreground実行および green background実行の完了を待たずに、起動受付から 10 秒以内に終了コード 0 で終了する

  Scenario: job mapの固定引数の後ろに追加引数を順序を変えず連結する
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を返すよう固定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement -- --target-date 2026-08-18 --retry 3` を実行する
    Then execution_specs の run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" 行の additional_args にJSON配列 ["--target-date","2026-08-18","--retry","3"] が保存される
    And slot_execution_specs の (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue") 行の fixed_args にJSON配列 ["--mode","batch"] が保存される
    And blue実装への起動イベントのargvが ["--mode","batch","--target-date","2026-08-18","--retry","3"]（固定引数→追加引数の順、要素の順序・値とも改変なし）で構成される

  Scenario: 空白・引用符・改行を含む引数が保存と復元の往復で同一になる
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=off, RAPID_CROSSCHECK_MODE=off, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を返すよう固定されている
    When 運用者が追加引数として 1 番目に `--note`、2 番目に `a b "c"`（空白と二重引用符を含む1要素）、3 番目に改行1文字を含む `x<LF>y` の3要素を渡して `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then execution_specs の additional_args にJSON配列 ["--note","a b \"c\"","x\ny"] が保存される
    And 保存値をJSON配列として復元した3要素は、渡した3要素と1要素ずつ同一である（再分割・再結合・トリム・クォート付与が行われない）
    And blue実装への起動イベントのargvは ["--mode","batch","--note","a b \"c\"","x\ny"] である

  Scenario: credential_refから認証情報を解決し実値を露出させない
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And /etc/relaygate/credentials/cred-blue-batch の鍵ファイルに識別文字列 "RELAYGATE-TEST-SECRET-BLUE" が含まれている
    And blue のジョブマップの jobs."daily-settlement" に facade が読まない余剰フィールド "note"="RELAYGATE-TEST-SECRET-EXTRA" が追加されている
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を返すよう固定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 0 で終了する
    And blue実装への起動イベントは /etc/relaygate/credentials/cred-blue-batch を秘密鍵として送出される
    And "RELAYGATE-TEST-SECRET-BLUE" と "RELAYGATE-TEST-SECRET-EXTRA" は execution_specs・slot_execution_specs・audit_logs・標準出力・標準エラー・起動イベントの引数のいずれにも現れない

  Scenario: runner設定の差し替えのみで新世代実装を起動できる（facade本体は無変更）
    Given 環境変数に BLUE_MODE=off, GREEN_MODE=foreground, RAPID_CROSSCHECK_MODE=off, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And green のジョブマップ /etc/relaygate/job-map.green.json だけが job_map_version="v1.5.0" に更新され、jobs."daily-settlement" が host=green-host-01, exec_user=batchuser, script_path=/opt/green-next/run.sh, work_dir=/opt/relaygate/work, impl_version=green-1.0.0 に差し替えられている
    And blue のジョブマップ /etc/relaygate/job-map.blue.json は job_map_version="v1.4.0" のまま変更されていない
    And facade本体のコード・設定はジョブマップ以外に一切変更されていない
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を、attempt_id発番が "att-green-0001" を返すよう固定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 0 で終了する
    And slot_execution_specs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", script_path="/opt/green-next/run.sh", impl_version="green-1.0.0", job_map_version="v1.5.0") の1行がINSERTされる
    And green実装への起動イベントは slot_execution_specs の host / exec_user / script_path / work_dir / fixed_args / credential_ref の値のみから構成され、facadeは実装固有の起動方式差異（実装名・バージョンによる分岐）を参照しない

  Scenario: BLUE_MODEとGREEN_MODEが同時にforegroundに設定されている
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=foreground, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 2 で終了する
    And 標準エラーに "BLUE_MODEとGREEN_MODEを同時にforegroundにすることはできません" が出力される
    And execution_specs・slot_execution_specs・runner_results・audit_logs へのINSERTは発生しない

  Scenario: JOB_IDに対応するジョブマップが存在しない
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And job_id "unknown-job" が blue・green いずれのジョブマップ（v1.4.0）の jobs にも存在しない
    When 運用者が `relaygate concurrent-run select-slot --job-id unknown-job` を実行する
    Then 終了コード 1 で終了する
    And 標準エラーに "JOB_IDに対応するジョブマップが見つかりません: unknown-job" が出力される
    And execution_specs・slot_execution_specs・runner_results・audit_logs へのINSERTは発生しない

  Scenario: ジョブマップの必須フィールドが欠落している
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And green のジョブマップ /etc/relaygate/job-map.green.json の jobs."daily-settlement" に hang_detect_limit_minutes が定義されていない
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 2 で終了する
    And 標準エラーに "ジョブマップの必須フィールドが欠落しています: slot_type=green path=/etc/relaygate/job-map.green.json field=jobs.daily-settlement.hang_detect_limit_minutes" が出力される
    And execution_specs・slot_execution_specs・runner_results・audit_logs へのINSERTは発生せず、blue実装・green実装への起動イベントは送出されない

  Scenario: ジョブマップのslot_typeが環境変数の指すslotと一致しない
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And 環境変数 RELAYGATE_JOB_MAP_PATH_GREEN が blue のジョブマップ（slot_type="blue"）を指している
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 2 で終了する
    And 標準エラーに "ジョブマップの必須フィールドが欠落しています: slot_type=green path=/etc/relaygate/job-map.blue.json field=slot_type" が出力される
    And execution_specs・slot_execution_specs・runner_results・audit_logs へのINSERTは発生しない

  Scenario: 起動前監査の追記に失敗した場合は外部slotを起動しない
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And audit_logs へのINSERTが失敗する状態になっている
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 1 で終了する
    And 標準エラーに起動前監査の追記失敗の原因と次アクションが出力される
    And execution_specs・slot_execution_specs・runner_results・runner_result_events へのINSERTはrollbackされ残らない
    And blue実装・green実装への起動イベントは送出されない

  Scenario: 起動イベントの送出に失敗した試行をFAILEDへ補償記録する
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を、attempt_id発番が blue="att-blue-0001" / green="att-green-0001" を返すよう固定されている
    And green実装ホスト green-host-01 へのSSH接続が失敗する状態である
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 1 で終了する
    And runner_results の (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001") 行が status="FAILED", exit_code=NULL へ更新され、runner_result_events に event_name="attempt_failed", status="FAILED" の履歴が同一transactionでINSERTされる
    And audit_logs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot="green", attempt_id="att-green-0001", event_name="slot_launch_failed", outcome="failed", error_code="launch_event_send_failed", actor="ops-tanaka") が slot_launch_attempted の後ろにチェーンされてINSERTされる
    And blue実装へのforeground起動イベントは送出され、runner_results の blue/foreground/att-blue-0001 行は status="STARTING" のままである
    And 標準出力には blue/foreground/att-blue-0001/STARTING 行と green/background/att-green-0001/STARTING 行が出力される（起動受付の記録）
    And 標準エラーに "green実装への起動イベント送出に失敗しました: slot_type=green attempt_id=att-green-0001 を FAILED として記録しました" と次アクションが出力される

  Scenario: 起動イベントの送出がtimeoutした試行をUNKNOWNへ補償記録する
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And run_id発番が "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" を、attempt_id発番が blue="att-blue-0001" / green="att-green-0001" を返すよう固定されている
    And blue実装ホスト blue-host-01 へのSSH起動イベント送出がtimeoutする状態である
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 124 で終了する
    And runner_results の (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="foreground", attempt_id="att-blue-0001") 行が status="UNKNOWN", exit_code=NULL へ更新され、runner_result_events に event_name="attempt_unknown", status="UNKNOWN" の履歴が同一transactionでINSERTされる（推測でFAILEDを確定しない）
    And audit_logs に (slot="blue", attempt_id="att-blue-0001", event_name="slot_launch_timeout", outcome="timeout", error_code="launch_event_send_timeout") がINSERTされる
    And runner_results の green/background/att-green-0001 行は status="STARTING" のままである
    And 標準エラーに "blue実装への起動イベント送出がtimeoutしました: slot_type=blue attempt_id=att-blue-0001 を UNKNOWN として記録しました" と次アクションが出力される

  Scenario: credential_refに対応する認証情報が解決できない
    Given 環境変数に BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている
    And 認証情報ディレクトリに /etc/relaygate/credentials/cred-green-batch が存在しない
    When 運用者が `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する
    Then 終了コード 1 で終了する
    And 標準エラーに "SSH認証情報を解決できません: credential_ref=cred-green-batch" が出力される
    And execution_specs・slot_execution_specs・runner_results・audit_logs へのINSERTは発生せず、blue実装・green実装への起動イベントは送出されない
