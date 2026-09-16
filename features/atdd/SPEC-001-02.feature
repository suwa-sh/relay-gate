# source: docs/usdm/latest/requirements.yaml#requirements[REQ-001].specifications[SPEC-001-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-001-02 blue と green の両方が foreground になる構成は許可せず、facade は入力検証でエラー終了する

  REQ-001: ジョブスケジューラの同一ジョブ定義から、feature flag の設定だけで現行実装(blue)と新実装(green)の並行稼働・単独本番を切り替えられること

  @atdd_SPEC-001-02-1
  Scenario: SPEC-001-02-1
    Given BLUE_MODE=foreground かつ GREEN_MODE=foreground
    When facade を起動する
    Then どの slot も起動せずエラー終了する
