# source: docs/usdm/latest/requirements.yaml#requirements[REQ-010].specifications[SPEC-010-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-010-01 abort-blue / abort-green は --run-id を受け取り、対象 slot が background かつ RUNNING のときだけ中止できる。foreground または off の場合は状態を変更せずエラー終了する。中止時は成果物ディレクトリに aborted.txt(中止日時 1 行)を書き、RAPID_CROSSCHECK_MODE が off 以外なら管理 DB の状態も ABORTED に更新する。slot 実行の状態はファイル正本(exitcode.txt があれば SUCCEEDED(0)/ FAILED(非 0)、無く aborted.txt があれば ABORTED、どちらも無ければ RUNNING)から導出する。対象 run に REQUESTED で未着手(worker が claim していない)の速報比較依頼があれば、それも ABORTED にする。これは両系の完了通知で速報比較依頼が REQUESTED で作成された後に運用者が slot を中止した場合の競合窓を塞ぐ保険であり、速報クロスチェック runner(dispatcher)側の中止済み run 判定と併用する。CLAIMED / RUNNING の依頼は abort-blue / abort-green では変更せず、REQUESTED / CLAIMED / RUNNING の速報比較依頼の明示中止は abort-rapid-crosscheck で行う

  REQ-010: 運用者が、プロセス停止を確認した上で、background slot 実行・速報比較依頼・確報比較依頼を明示的に ABORTED へ遷移させられること

  @atdd_SPEC-010-01-1
  Scenario: SPEC-010-01-1
    Given green が background かつ RUNNING
    When abort-green --run-id を実行し yes と答える
    Then green slot が ABORTED になる

  @atdd_SPEC-010-01-2
  Scenario: SPEC-010-01-2
    Given blue が foreground
    When abort-blue --run-id を実行する
    Then 状態を変更せずエラー終了する

  @atdd_SPEC-010-01-3
  Scenario: SPEC-010-01-3
    Given RAPID_CROSSCHECK_MODE=off で background slot が RUNNING(exitcode.txt も aborted.txt も無い)
    When abort-blue を実行して yes と答える
    Then aborted.txt が書かれ、background-rerun で同じ run をリランできる

  @atdd_SPEC-010-01-4
  Scenario: SPEC-010-01-4
    Given exitcode.txt が無く aborted.txt がある slot
    When 状態を導出する
    Then ABORTED と判定され、ハング検知は中止済みとして監視記録を終端する

  @atdd_SPEC-010-01-5
  Scenario: SPEC-010-01-5
    Given RAPID_CROSSCHECK_MODE=background で background slot を中止した
    When 管理 DB を確認する
    Then aborted.txt の書き込みに加えて管理 DB の状態も ABORTED になっている

  @atdd_SPEC-010-01-6
  Scenario: SPEC-010-01-6
    Given REQUESTED の速報比較依頼がある run
    When abort-blue または abort-green を実行して yes と答える
    Then その依頼も ABORTED になる

  @atdd_SPEC-010-01-7
  Scenario: SPEC-010-01-7
    Given CLAIMED または RUNNING の速報比較依頼がある run
    When abort-blue または abort-green を実行して yes と答える
    Then slot は ABORTED になるが依頼の状態は変更されない

  @atdd_SPEC-010-01-8
  Scenario: SPEC-010-01-8
    Given 両系の完了通知で速報比較依頼が REQUESTED で作成された直後
    When 運用者が abort-blue または abort-green で slot を中止して yes と答える
    Then slot と依頼の両方が ABORTED になり、その後の完了通知でも速報比較依頼は再作成されない
