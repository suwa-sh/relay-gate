# source: docs/usdm/latest/requirements.yaml#requirements[REQ-009].specifications[SPEC-009-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-009-02 リランは最新のジョブマップを再解決せず、元の execution-spec.json から実行パラメータ・ホスト・実行ユーザー・スクリプト・作業ディレクトリを復元して起動する。ジョブマップの変更は実行済みまたはリラン対象の設定を上書きしない

  REQ-009: background 側リランが、ジョブスケジューラの専用ジョブから、完了済みまたは明示中止済みの background slot 実行または速報比較依頼を、元の execution-spec.json を使って新しい run_id で再実行できること

  @atdd_SPEC-009-02-1
  Scenario: SPEC-009-02-1
    Given 元の run 以降にジョブマップが変更された
    When リランする
    Then 元の execution-spec.json の設定で起動される
