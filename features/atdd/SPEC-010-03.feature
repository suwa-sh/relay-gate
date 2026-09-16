# source: docs/usdm/latest/requirements.yaml#requirements[REQ-010].specifications[SPEC-010-03].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-010-03 各中止スクリプトは現在状態を表示後、「対象ジョブのプロセスは強制終了してありますか？ [yes/no]」と対話確認し、yes 以外なら状態を変更せず終了する。スクリプト自身はプロセス・Pod・SSH 接続先の処理を停止しない

  REQ-010: 運用者が、プロセス停止を確認した上で、background slot 実行・速報比較依頼・確報比較依頼を明示的に ABORTED へ遷移させられること

  @atdd_SPEC-010-03-1
  Scenario: SPEC-010-03-1
    Given 中止スクリプトを起動
    When 確認に no と答える
    Then 状態は変更されず終了する

  @atdd_SPEC-010-03-2
  Scenario: SPEC-010-03-2
    Given 中止スクリプトを起動
    When yes と答える
    Then スクリプトはプロセスを停止せず、状態だけを ABORTED に更新する
