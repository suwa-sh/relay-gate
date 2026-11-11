# source: docs/usdm/latest/requirements.yaml#requirements[REQ-014].specifications[SPEC-014-04].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-014-04 経過日数の基準は、単位内の構成要素の終了日時のうち最も遅いものとする。管理 DB の行は completed_at、成果物だけの slot は exitcode.txt または aborted.txt の更新時刻を使い、開始日時は使わない。確報比較依頼は、管理 DB に接続する設定で、終端状態(SUCCEEDED / FAILED / ABORTED)で、completed_at から保持日数を過ぎたものを依頼ごとに消す。RAPID_CROSSCHECK_MODE=off でも、確報クロスチェックを使う設置(確報クロスチェック worker の設定がある設置)ではハウスキープ設定の管理 DB 接続参照名が必須のため(SPEC-014-07)、確報比較依頼は同じ規則で消す(管理 DB に接続しないときは SPEC-014-08 のとおり消さない)

  REQ-014: ハウスキープが、ジョブスケジューラの定期ジョブ(1 日 1 回)から起動され、保持日数を過ぎた終了済みの実行の成果物と管理 DB の履歴、および終端した確報比較依頼を自動で削除すること

  @atdd_SPEC-014-04-1
  Scenario: SPEC-014-04-1
    Given 開始日時とほかの構成要素の終了日時は保持日数より古いが、最も遅い構成要素の終了日時が保持日数以内の実行
    When ハウスキープを実行する
    Then その実行の成果物と管理 DB の行は残る

  @atdd_SPEC-014-04-2
  Scenario: SPEC-014-04-2
    Given 管理 DB に接続する設定で、終端状態の確報比較依頼のうち、completed_at から保持日数を過ぎた依頼と過ぎていない依頼がある
    When ハウスキープを実行する
    Then 過ぎた依頼だけが無くなり、過ぎていない依頼は残る

  @atdd_SPEC-014-04-3
  Scenario: SPEC-014-04-3
    Given REQUESTED・CLAIMED・RUNNING のいずれかの確報比較依頼が、登録から保持日数より長く経っている
    When ハウスキープを実行する
    Then その依頼は残る

  @atdd_SPEC-014-04-4
  Scenario: SPEC-014-04-4
    Given RAPID_CROSSCHECK_MODE=off で、確報クロスチェックを使う設置(確報クロスチェック worker の設定がある設置)で、ハウスキープ設定に管理 DB 接続参照名があり、終端状態で completed_at から保持日数を過ぎた確報比較依頼がある
    When ハウスキープを実行する
    Then その確報比較依頼は無くなる
