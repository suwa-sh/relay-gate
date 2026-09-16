# source: docs/usdm/latest/requirements.yaml#requirements[REQ-003].specifications[SPEC-003-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-003-01 runner は <FACADE_RUN_DIR>/<FACADE_RUN_ROLE>/ 配下に started-at.txt、stdout.log、stderr.log、exitcode.txt を出力する。exitcode.txt は数値だけを 1 行で保持し、runner の終了コードは exitcode.txt と一致する。3 ファイルは実行終了後に揃えて公開する

  REQ-003: blue / green runner は foreground / background のどちらでも、実装の終了結果を Runner Result Contract(stdout.log / stderr.log / exitcode.txt)として出力すること

  @atdd_SPEC-003-01-1
  Scenario: SPEC-003-01-1
    Given slot 実行が終了した
    When 成果物ディレクトリを確認する
    Then stdout.log、stderr.log、exitcode.txt が揃って存在し、exitcode.txt は数値 1 行である

  @atdd_SPEC-003-01-2
  Scenario: SPEC-003-01-2
    Given runner が終了した
    When runner の終了コードを確認する
    Then exitcode.txt の値と一致する

  @atdd_SPEC-003-01-3
  Scenario: SPEC-003-01-3
    Given role の起動時
    When 成果物ディレクトリを確認する
    Then started-at.txt に起動時刻が記録されている
