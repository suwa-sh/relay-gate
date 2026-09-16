# source: docs/usdm/latest/requirements.yaml#requirements[REQ-007].specifications[SPEC-007-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-007-02 依頼レコードは worker_id、lease_until、requested_at、started_at、completed_at、exit_code、stdout、stderr、error_summary を保持する。比較差分の詳細は comparison_result、stdout、stderr に保持し、依頼の状態は worker の exitcode に従う

  REQ-007: 速報・確報のクロスチェック依頼が同じライフサイクル(REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED)で管理され、worker の claim と lease で多重実行を防ぐこと

  @atdd_SPEC-007-02-1
  Scenario: SPEC-007-02-1
    Given worker が依頼を claim した
    When 依頼レコードを確認する
    Then worker_id と lease_until が設定されている
