# source: docs/usdm/latest/requirements.yaml#requirements[REQ-011].specifications[SPEC-011-05].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-011-05 管理 DB(ジョブキュー兼管理 DB)は relay-gate 内部のデータストアであり、外部システムとしては扱わない。リモート実行ホスト(SSH)は実装固有のホスト配置として適用側の関心事であり、外部システムとして維持する

  REQ-011: 1 回の並行稼働を run_id で相関付け、速報側(parallel_run / rapid_run / rapid_crosscheck_request / comparison_result)と確報側(final_crosscheck_request / 対象カタログ)を別ドメインのデータモデルとして管理 DB に保持すること

  @atdd_SPEC-011-05-1
  Scenario: SPEC-011-05-1
    Given RDRA の外部システム一覧
    When 管理 DB(RDB)を探す
    Then 外部システムには含まれず、システム概要に relay-gate 内部のジョブキュー兼管理 DB として記載されている

  @atdd_SPEC-011-05-2
  Scenario: SPEC-011-05-2
    Given RDRA の外部システム一覧
    When リモート実行ホスト(SSH)を探す
    Then 外部システムとして残っている
