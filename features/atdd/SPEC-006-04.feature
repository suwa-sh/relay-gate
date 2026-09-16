# source: docs/usdm/latest/requirements.yaml#requirements[REQ-006].specifications[SPEC-006-04].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-006-04 確報クロスチェックは速報と異なるデータモデル(final_crosscheck_request と対象カタログ)を持ち、rapid_run や rapid_crosscheck_request を再利用しない。確報の制御は feature flag に含めず、ジョブスケジューラから直接起動する

  REQ-006: 確報クロスチェックが、ジョブスケジューラの別ジョブ定義から起動され、全テーブル・全ファイルを対象に日次整合性を正式確認し、stdout・stderr・exitcode をジョブスケジューラへ返すこと

  @atdd_SPEC-006-04-1
  Scenario: SPEC-006-04-1
    Given 確報比較を実行する
    When 管理 DB を確認する
    Then rapid_run / rapid_crosscheck_request は変更されず final_crosscheck_request だけが作成される
