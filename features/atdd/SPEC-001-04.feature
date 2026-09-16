# source: docs/usdm/latest/requirements.yaml#requirements[REQ-001].specifications[SPEC-001-04].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-001-04 blue / green の runner は設定で実体スクリプトを割り当て、実装固有の起動方式・ホスト・OS・プロトコルを slot の runner に閉じ込める。runner を差し替えることで異なる世代の実装を並行稼働できる

  REQ-001: ジョブスケジューラの同一ジョブ定義から、feature flag の設定だけで現行実装(blue)と新実装(green)の並行稼働・単独本番を切り替えられること

  @atdd_SPEC-001-04-1
  Scenario: SPEC-001-04-1
    Given BLUE_RUNNER / GREEN_RUNNER に実体スクリプトのパスが設定されている
    When facade が slot を起動する
    Then facade は実装固有の起動方式を判断せず、設定された runner を起動する

  @atdd_SPEC-001-04-2
  Scenario: SPEC-001-04-2
    Given green runner を次世代実装用に差し替える
    When feature flag と runner 設定だけを変更する
    Then facade と比較規約を変更せずに並行稼働できる
