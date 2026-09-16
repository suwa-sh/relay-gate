# source: docs/usdm/latest/requirements.yaml#requirements[REQ-009].specifications[SPEC-009-03].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-009-03 事前検証: --role が blue / green で元の slot mode が background なら新しい run_id でリランする。元の slot mode が foreground または off ならリランせず呼び出し元の専用ジョブをエラー終了する。--role が rapid-crosscheck なら業務ジョブを再実行せず比較依頼だけを新規作成する。未対応の role、元の実行が見つからない、元の実行が RUNNING または中止未確認の場合はリランせずエラー終了する

  REQ-009: background 側リランが、ジョブスケジューラの専用ジョブから、完了済みまたは明示中止済みの background slot 実行または速報比較依頼を、元の execution-spec.json を使って新しい run_id で再実行できること

  @atdd_SPEC-009-03-1
  Scenario: SPEC-009-03-1
    Given 元の実行で blue が foreground
    When --role blue でリランする
    Then リランせずエラー終了する

  @atdd_SPEC-009-03-2
  Scenario: SPEC-009-03-2
    Given 元の green 実行が RUNNING
    When --role green でリランする
    Then 実行中である旨のエラーで終了し、中止を促す

  @atdd_SPEC-009-03-3
  Scenario: SPEC-009-03-3
    Given 速報比較依頼が ABORTED
    When --role rapid-crosscheck でリランする
    Then 新しい比較依頼だけが作成され、業務ジョブは再実行されない
