# source: docs/usdm/latest/requirements.yaml#requirements[REQ-005].specifications[SPEC-005-03].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-005-03 速報クロスチェック worker は比較依頼を取得(poll / claim)し、job_id ごとの比較定義に従って比較ツールでジョブ単位の比較を実行し、stdout・stderr・exitcode と比較結果(comparison_result)を登録する

  REQ-005: 速報クロスチェックが、ジョブの実行ごとに blue と green の完了結果を非同期に比較し、差分を運用者へ提供すること

  @atdd_SPEC-005-03-1
  Scenario: SPEC-005-03-1
    Given REQUESTED の速報比較依頼がある
    When worker が poll する
    Then 依頼を claim して比較を実行し、stdout・stderr・exitcode と比較結果を登録する

  @atdd_SPEC-005-03-2
  Scenario: SPEC-005-03-2
    Given job_id ごとに比較定義が差し替えられている
    When 比較を実行する
    Then その job_id の比較定義が使われる

  @atdd_SPEC-005-03-3
  Scenario: SPEC-005-03-3
    Given job_id の比較定義が無い
    When worker が依頼を処理する
    Then comparison_result は登録されず、依頼だけが FAILED(exit_code=6 相当、error_summary に理由)で終端する

  @atdd_SPEC-005-03-4
  Scenario: SPEC-005-03-4
    Given 比較ツールの起動に失敗した
    When worker が依頼を処理する
    Then comparison_result は登録されず、依頼だけが FAILED で終端する

  @atdd_SPEC-005-03-5
  Scenario: SPEC-005-03-5
    Given 比較ツールが終了コードを返した
    When worker が結果を登録する
    Then comparison_result が登録される
