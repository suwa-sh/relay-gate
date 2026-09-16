# source: docs/usdm/latest/requirements.yaml#requirements[REQ-003].specifications[SPEC-003-04].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-003-04 background 実行でも同じ 3 ファイルを残し、ハング検知は started-at.txt、exitcode.txt、hang_detect_limit_minutes を使って background 実行を判定する

  REQ-003: blue / green runner は foreground / background のどちらでも、実装の終了結果を Runner Result Contract(stdout.log / stderr.log / exitcode.txt)として出力すること

  @atdd_SPEC-003-04-1
  Scenario: SPEC-003-04-1
    Given GREEN_MODE=background
    When green の実行が終了する
    Then green/ 配下に 3 ファイルが残る
