# source: docs/usdm/latest/requirements.yaml requirements[REQ-003].specifications[SPEC-003-03].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-003-03 成果物は実行終了後に一時ファイルへ出力してから確定名へリネームし、揃った状態で公開する。後続処理は書き込み途中のファイル

  @atdd_SPEC-003-03-1
  Scenario: SPEC-003-03-1
    Given runnerが成果物を出力中である
    When 後続処理（hang-detectorや速報クロスチェック）が成果物を参照する
    Then 書き込み途中の不完全なファイルを読まない
