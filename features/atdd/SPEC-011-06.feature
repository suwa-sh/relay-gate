# source: docs/usdm/latest/requirements.yaml#requirements[REQ-011].specifications[SPEC-011-06].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-011-06 parallel_run は STARTED から直接 ABORTED へ遷移できる(facade が STARTED で作成した直後に中止された実行を取りこぼさない)。リラン由来の parallel_run は、速報比較依頼だけを新規作成した場合は依頼が終端状態(SUCCEEDED / FAILED)になった時点で worker が COMPLETED にし、background slot をリランした場合は slot の終端時に runner が COMPLETED にする

  REQ-011: 1 回の並行稼働を run_id で相関付け、速報側(parallel_run / rapid_run / rapid_crosscheck_request / comparison_result)と確報側(final_crosscheck_request / 対象カタログ)を別ドメインのデータモデルとして管理 DB に保持すること

  @atdd_SPEC-011-06-1
  Scenario: SPEC-011-06-1
    Given STARTED の parallel_run
    When 中止スクリプトで yes と答える
    Then parallel_run は ABORTED になる

  @atdd_SPEC-011-06-2
  Scenario: SPEC-011-06-2
    Given --role rapid-crosscheck でリランした parallel_run
    When 速報比較依頼が SUCCEEDED または FAILED になる
    Then parallel_run は COMPLETED になる

  @atdd_SPEC-011-06-3
  Scenario: SPEC-011-06-3
    Given --role green でリランした parallel_run
    When background green slot が終端する
    Then parallel_run は COMPLETED になる
