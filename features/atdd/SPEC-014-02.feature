# source: docs/usdm/latest/requirements.yaml#requirements[REQ-014].specifications[SPEC-014-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-014-02 削除の単位は 2 種類とする。実行の単位は、リランの親子(parent_run_id でつながる実行)をまとめた 1 単位とし、単位内の各実行の成果物ディレクトリ、管理 DB の行(並行稼働実行・slot 実行・速報実行・速報比較依頼・監視記録)、ハング検知が残した通知済みの印を一緒に消す。確報比較依頼の単位は確報比較依頼 1 件とする。リランの親子は、単位内のすべての実行が削除の条件を満たすまで残す

  REQ-014: ハウスキープが、ジョブスケジューラの定期ジョブ(1 日 1 回)から起動され、保持日数を過ぎた終了済みの実行の成果物と管理 DB の履歴、および終端した確報比較依頼を自動で削除すること

  @atdd_SPEC-014-02-1
  Scenario: SPEC-014-02-1
    Given すべての構成要素が終端し、最も遅い終了日時から保持日数を過ぎた実行
    When ハウスキープを実行する
    Then その実行の成果物ディレクトリ、管理 DB の行(並行稼働実行・slot 実行・速報実行・速報比較依頼・監視記録)、通知済みの印がすべて無くなる

  @atdd_SPEC-014-02-2
  Scenario: SPEC-014-02-2
    Given すべての構成要素が終端し、最も遅い終了日時から保持日数以内の実行
    When ハウスキープを実行する
    Then その実行の成果物と管理 DB の行は残る

  @atdd_SPEC-014-02-3
  Scenario: SPEC-014-02-3
    Given リラン元の実行は保持日数を過ぎたが、parent_run_id でつながるリラン先の実行が保持日数以内である
    When ハウスキープを実行する
    Then リラン元とリラン先の成果物と管理 DB の行はどちらも残る

  @atdd_SPEC-014-02-4
  Scenario: SPEC-014-02-4
    Given parent_run_id でつながるリランの親子すべてが終端し、保持日数を過ぎた
    When ハウスキープを実行する
    Then 親子すべての成果物と管理 DB の行が無くなる
