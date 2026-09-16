# source: docs/usdm/latest/requirements.yaml#requirements[REQ-002].specifications[SPEC-002-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-002-01 facade は (1) background の blue・green slot をすべて起動して PID と成果物ディレクトリを確定し、(2) foreground slot を起動し(この時点では待機しない)、(3) すべての slot を起動してから foreground の PID だけを待機する、という順序を固定する

  REQ-002: facade は background slot を先に起動してから foreground slot を起動し、foreground の結果だけを待機してジョブスケジューラへ返すこと

  @atdd_SPEC-002-01-1
  Scenario: SPEC-002-01-1
    Given BLUE_MODE=foreground, GREEN_MODE=background
    When facade を起動する
    Then green が先に background 起動され、その後 blue が起動され、facade は blue の終了のみを待機する

  @atdd_SPEC-002-01-2
  Scenario: SPEC-002-01-2
    Given foreground slot が長時間実行中
    When 実行状況を確認する
    Then background slot は foreground と同時に実行されている
