# source: docs/usdm/latest/requirements.yaml#requirements[REQ-011].specifications[SPEC-011-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-011-02 rapid_run は run_id ごとに blue_status、green_status、blue_artifact_uri、green_artifact_uri、blue_completed_at、green_completed_at を保持する。rapid_crosscheck_request は run_id を主キーとし、comparison_result は comparison_result_id、run_id、comparison_type、status、difference_count、report_uri、compared_at を保持する

  REQ-011: 1 回の並行稼働を run_id で相関付け、速報側(parallel_run / rapid_run / rapid_crosscheck_request / comparison_result)と確報側(final_crosscheck_request / 対象カタログ)を別ドメインのデータモデルとして管理 DB に保持すること

  @atdd_SPEC-011-02-1
  Scenario: SPEC-011-02-1
    Given 比較が完了した
    When comparison_result を確認する
    Then comparison_type・status・difference_count・report_uri・compared_at が記録されている
