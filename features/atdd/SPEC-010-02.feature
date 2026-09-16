# source: docs/usdm/latest/requirements.yaml#requirements[REQ-010].specifications[SPEC-010-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-010-02 abort-rapid-crosscheck は --run-id を受け取り、対象の速報比較依頼が REQUESTED / CLAIMED / RUNNING のいずれかのとき ABORTED へ遷移させる。運用者に worker のプロセスを停止してあるかを対話確認し、yes のときだけ status IN (REQUESTED, CLAIMED, RUNNING) を条件とする条件付き UPDATE で ABORTED にする。中止できる状態でない(終端済み)場合は状態を変更せずエラー終了する。速報クロスチェック worker は claim 後・比較開始前に依頼が ABORTED になっていれば比較を開始しない(CLAIMED から RUNNING への遷移を条件付き UPDATE で行い、更新件数が 0 件なら終了する)。abort-final-crosscheck は --run-id を受け取り、対象の確報比較依頼が RUNNING のときだけ ABORTED へ遷移させ、RUNNING でない場合は状態を変更せずエラー終了する(確報の未着手依頼はジョブスケジューラの正規ジョブが同期 polling 中であり、runner 側の polling 上限で扱う)

  REQ-010: 運用者が、プロセス停止を確認した上で、background slot 実行・速報比較依頼・確報比較依頼を明示的に ABORTED へ遷移させられること

  @atdd_SPEC-010-02-1
  Scenario: SPEC-010-02-1
    Given 速報比較依頼が RUNNING
    When abort-rapid-crosscheck --run-id を実行し yes と答える
    Then 依頼が ABORTED になる

  @atdd_SPEC-010-02-2
  Scenario: SPEC-010-02-2
    Given 速報比較依頼が REQUESTED または CLAIMED
    When abort-rapid-crosscheck を実行して yes と答える
    Then その依頼は ABORTED になり、worker は比較を開始しない

  @atdd_SPEC-010-02-3
  Scenario: SPEC-010-02-3
    Given CLAIMED の速報比較依頼が abort-rapid-crosscheck で ABORTED になった
    When claim 済みの worker が RUNNING への条件付き UPDATE を行う
    Then 更新件数は 0 件で、worker は比較を開始せず終了する

  @atdd_SPEC-010-02-4
  Scenario: SPEC-010-02-4
    Given 速報比較依頼が SUCCEEDED / FAILED / ABORTED の終端状態
    When abort-rapid-crosscheck を実行する
    Then 状態を変更せずエラー終了する

  @atdd_SPEC-010-02-5
  Scenario: SPEC-010-02-5
    Given 確報比較依頼が RUNNING でない
    When abort-final-crosscheck を実行する
    Then 状態を変更せずエラー終了する
