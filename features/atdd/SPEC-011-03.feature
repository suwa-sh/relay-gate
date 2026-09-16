# source: docs/usdm/latest/requirements.yaml#requirements[REQ-011].specifications[SPEC-011-03].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-011-03 final_crosscheck_request は final_crosscheck_id、business_date、対象カタログの版、status、worker_id、lease_until、requested_at / started_at / completed_at、exit_code、stdout、stderr、error_summary を保持し、対象カタログ(target_type、target_identifier)を紐付ける

  REQ-011: 1 回の並行稼働を run_id で相関付け、速報側(parallel_run / rapid_run / rapid_crosscheck_request / comparison_result)と確報側(final_crosscheck_request / 対象カタログ)を別ドメインのデータモデルとして管理 DB に保持すること

  @atdd_SPEC-011-03-1
  Scenario: SPEC-011-03-1
    Given 確報依頼を登録した
    When final_crosscheck_request と対象カタログを確認する
    Then business_date と対象カタログの版、対象一覧が記録されている
