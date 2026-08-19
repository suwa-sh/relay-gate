# source: docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/spec.md#E2E完了条件(BDD)
Feature: feature flag設定に基づきslotを選択して起動する

  Scenario: BLUE_MODE=foreground, GREEN_MODE=backgroundでblue/green両slotを起動する
    Given JOB_ID "JOB-2026-0817-001" のジョブマップにBLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=onが設定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id JOB-2026-0817-001` を実行する
    Then 終了コード 0 で終了する
    And execution-spec.jsonがrun_id "run-20260817-001" で確定・保存される
    And 標準出力に "blue: foreground" "green: background" を含む行が出力される

  Scenario: RAPID_CROSSCHECK_MODE=offの場合は速報管理DBへ接続しない
    Given JOB_ID "JOB-2026-0817-002" のジョブマップにRAPID_CROSSCHECK_MODE=offが設定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id JOB-2026-0817-002` を実行する
    Then 終了コード 0 で終了する
    And 速報比較依頼テーブルへのINSERTは発生しない

  Scenario: BLUE_MODE=off, GREEN_MODE=foregroundで新実装単独本番の運用モードとして起動する
    Given JOB_ID "JOB-2026-0817-004" のジョブマップにBLUE_MODE=off, GREEN_MODE=foreground, RAPID_CROSSCHECK_MODE=offが設定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id JOB-2026-0817-004` を実行する
    Then 終了コード 0 で終了する
    And execution-spec.jsonがrun_id "run-20260817-004" で確定・保存される
    And 標準出力に "blue: off" "green: foreground" を含む行が出力される（運用モード: 新実装単独本番に相当する組み合わせ）

  Scenario: BLUE_MODEとGREEN_MODEが同時にforegroundに設定されている
    Given JOB_ID "JOB-2026-0817-003" のジョブマップにBLUE_MODE=foreground, GREEN_MODE=foregroundが設定されている
    When 運用者が `relaygate concurrent-run select-slot --job-id JOB-2026-0817-003` を実行する
    Then 終了コード 2 で終了する
    And 標準エラーに "BLUE_MODEとGREEN_MODEを同時にforegroundにすることはできません" が出力される
    And execution-spec.jsonは作成されない

  Scenario: JOB_IDに対応するジョブマップが存在しない
    Given JOB_ID "JOB-UNKNOWN-999" がジョブマップに存在しない
    When 運用者が `relaygate concurrent-run select-slot --job-id JOB-UNKNOWN-999` を実行する
    Then 終了コード 1 で終了する
    And 標準エラーに "JOB_IDに対応するジョブマップが見つかりません: JOB-UNKNOWN-999" が出力される
