# source: docs/usdm/latest/requirements.yaml#requirements[REQ-011].specifications[SPEC-011-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-011-01 parallel_run は run_id、parent_run_id、job_id、parameters、execution_spec_uri、status、requested_at、completed_at を保持する。速報クロスチェック有効時、execution_spec_uri は成果物の execution-spec.json を参照する

  REQ-011: 1 回の並行稼働を run_id で相関付け、速報側(parallel_run / rapid_run / rapid_crosscheck_request / comparison_result)と確報側(final_crosscheck_request / 対象カタログ)を別ドメインのデータモデルとして管理 DB に保持すること

  @atdd_SPEC-011-01-1
  Scenario: SPEC-011-01-1
    Given RAPID_CROSSCHECK_MODE=background で run を開始
    When parallel_run を確認する
    Then execution_spec_uri が facade/<run_id>/execution-spec.json を指す
