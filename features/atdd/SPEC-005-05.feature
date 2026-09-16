# source: docs/usdm/latest/requirements.yaml#requirements[REQ-005].specifications[SPEC-005-05].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-005-05 速報クロスチェックは background 処理であり、その exitcode や失敗を通常業務ジョブの結果としてジョブスケジューラへ返さない。速報の比較結果は原因調査に使用し、リリース判断の正本には日次全量比較(確報)を用いる

  REQ-005: 速報クロスチェックが、ジョブの実行ごとに blue と green の完了結果を非同期に比較し、差分を運用者へ提供すること

  @atdd_SPEC-005-05-1
  Scenario: SPEC-005-05-1
    Given 速報比較が比較 NG または FAILED
    When foreground ジョブの結果を確認する
    Then ジョブスケジューラへの応答は速報の結果に影響されない
