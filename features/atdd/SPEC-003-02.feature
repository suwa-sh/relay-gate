# source: docs/usdm/latest/requirements.yaml requirements[REQ-003].specifications[SPEC-003-02].acceptance_criteria
# 転写ルール: 1 criterion = 1 Scenario、文言は原文のまま(dev-rules/test-strategy.md)
Feature: SPEC-003-02 起動失敗・ジョブマップ未定義・SSH失敗が発生した場合でも、可能な限り3ファイル（stdout.log/stderr.l

  @atdd_SPEC-003-02-1
  Scenario: SPEC-003-02-1
    Given 起動先ホストへのSSH接続が失敗する
    When runnerが異常終了する
    Then 可能な範囲でstdout.log/stderr.log/exitcode.txtが出力される
