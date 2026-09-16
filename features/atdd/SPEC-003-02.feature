# source: docs/usdm/latest/requirements.yaml#requirements[REQ-003].specifications[SPEC-003-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-003-02 起動失敗、ジョブマップ未定義、SSH 失敗などの異常でも、runner は可能な限り 3 ファイルを出力する

  REQ-003: blue / green runner は foreground / background のどちらでも、実装の終了結果を Runner Result Contract(stdout.log / stderr.log / exitcode.txt)として出力すること

  @atdd_SPEC-003-02-1
  Scenario: SPEC-003-02-1
    Given JOB_ID がジョブマップに未定義
    When runner を起動する
    Then 非 0 の exitcode.txt と原因を含む stderr.log が出力される
