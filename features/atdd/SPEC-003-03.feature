# source: docs/usdm/latest/requirements.yaml#requirements[REQ-003].specifications[SPEC-003-03].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-003-03 後続処理が書き込み途中のファイルを読まないよう、成果物は一時ファイルへ出力してから確定名へリネームする

  REQ-003: blue / green runner は foreground / background のどちらでも、実装の終了結果を Runner Result Contract(stdout.log / stderr.log / exitcode.txt)として出力すること

  @atdd_SPEC-003-03-1
  Scenario: SPEC-003-03-1
    Given 成果物の書き込み中
    When ハング検知や比較処理が成果物を読む
    Then 書き込み途中の確定名ファイルは存在しない
