# source: docs/usdm/latest/requirements.yaml#requirements[REQ-009].specifications[SPEC-009-04].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-009-04 foreground slot 実行と確報クロスチェックは background-rerun を使用せず、ジョブスケジューラの正規ジョブを直接再実行する

  REQ-009: background 側リランが、ジョブスケジューラの専用ジョブから、完了済みまたは明示中止済みの background slot 実行または速報比較依頼を、元の execution-spec.json を使って新しい run_id で再実行できること

  @atdd_SPEC-009-04-1
  Scenario: SPEC-009-04-1
    Given foreground がエラー終了した
    When 復旧する
    Then ジョブスケジューラの正規ジョブを再実行する
