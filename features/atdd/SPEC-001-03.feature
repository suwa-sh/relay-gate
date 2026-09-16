# source: docs/usdm/latest/requirements.yaml#requirements[REQ-001].specifications[SPEC-001-03].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-001-03 運用モード(並行稼働: blue foreground / green background / crosscheck background、新実装の単独本番: blue off / green foreground / crosscheck off、次世代実装との並行稼働: blue background / green foreground / crosscheck background)を feature flag の組み合わせだけで表現でき、ジョブスケジューラへ返す結果は foreground slot の結果となる

  REQ-001: ジョブスケジューラの同一ジョブ定義から、feature flag の設定だけで現行実装(blue)と新実装(green)の並行稼働・単独本番を切り替えられること

  @atdd_SPEC-001-03-1
  Scenario: SPEC-001-03-1
    Given 並行稼働モードの設定
    When ジョブを実行する
    Then blue の結果がジョブスケジューラへ返る

  @atdd_SPEC-001-03-2
  Scenario: SPEC-001-03-2
    Given 新実装の単独本番モードの設定
    When ジョブを実行する
    Then green の結果がジョブスケジューラへ返り、速報クロスチェックは動作しない

  @atdd_SPEC-001-03-3
  Scenario: SPEC-001-03-3
    Given ジョブスケジューラのジョブ定義を変更しない
    When feature flag だけを変更する
    Then 並行稼働と単独本番を切り替えられる
