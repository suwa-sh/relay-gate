# source: docs/usdm/latest/requirements.yaml requirements[REQ-009].specifications[SPEC-009-03].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-009-03 起動時に解決済みのホスト・スクリプト・作業ディレクトリ・固定引数・追加引数・マップ版・実装版・hang_detect_l

  @atdd_SPEC-009-03-1 @uc_6078c4ed
  Scenario: SPEC-009-03-1
    Given slot runnerが実行先を解決する
    When 起動する
    Then run共通の実行設定（execution_specs）とslot別実行設定（slot_execution_specs）に解決済み設定が一度だけ確定してRDBへ保存され、認証情報そのものは含まれない

  @atdd_SPEC-009-03-2 @uc_6078c4ed
  Scenario: SPEC-009-03-2
    Given background roleに選ばれたslotのジョブマップにhang_detect_limit_minutesが定義されている
    When 起動時の実行設定を保存する
    Then hang_detect_limit_minutesはrun共通の実行設定（execution_specs）に1値として保存され、role別・slot別の値は保存されない
