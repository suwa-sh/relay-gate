# source: docs/usdm/latest/requirements.yaml#requirements[REQ-011].specifications[SPEC-011-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-011-02 rapid_run は run_id ごとに blue_status、green_status、blue / green の終了コード、blue_completed_at、green_completed_at を保持し、成果物 URI(blue_artifact_uri / green_artifact_uri)は持たない。rapid_crosscheck_request は run_id を主キーとし、worker が起動コマンドの置換に使う job_id・parameters・blue と green の exit_code を、自身の列として持つか同一トランザクションで参照できる parallel_run / rapid_run の列から引けるようにする(持ち方は仕様で決める)。比較結果のレコード(comparison_result)は持たず、比較の結果は依頼レコードの stdout・stderr・exit_code で参照する

  REQ-011: 1 回の並行稼働を run_id で相関付け、速報側(parallel_run / rapid_run / rapid_crosscheck_request)と確報側(final_crosscheck_request)を別ドメインのデータモデルとして管理 DB に保持すること

  @atdd_SPEC-011-02-1
  Scenario: SPEC-011-02-1
    Given 完了通知を受けた
    When rapid_run を確認する
    Then blue / green の状態と終了コードが記録され、成果物 URI の列は無い

  @atdd_SPEC-011-02-2
  Scenario: SPEC-011-02-2
    Given 速報比較が完了した
    When 管理 DB を確認する
    Then comparison_result のテーブルは存在せず、依頼レコードの stdout・stderr・exit_code に結果がある
