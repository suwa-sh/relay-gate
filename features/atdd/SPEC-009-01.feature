# source: docs/usdm/latest/requirements.yaml#requirements[REQ-009].specifications[SPEC-009-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-009-01 background-rerun は --source-run-id と --role(blue / green / rapid-crosscheck)を受け取り、元の実行を参照して新しい run_id を発行する。新しい実行の parent_run_id には直前のリラン元 run_id を設定し、最新の run_id から parent_run_id をたどると元の実行まで数珠つなぎに追跡できる

  REQ-009: background 側リランが、ジョブスケジューラの専用ジョブから、完了済みまたは明示中止済みの background slot 実行または速報比較依頼を、元の execution-spec.json を使って新しい run_id で再実行できること

  @atdd_SPEC-009-01-1
  Scenario: SPEC-009-01-1
    Given 完了済みの background green 実行 R1
    When --source-run-id R1 --role green でリランする
    Then 新しい run_id R2 が発行され R2.parent_run_id = R1 となる

  @atdd_SPEC-009-01-2
  Scenario: SPEC-009-01-2
    Given R2 をさらにリランして R3 を作った
    When R3 の parent_run_id をたどる
    Then R2 → R1 と追跡できる
