# source: docs/usdm/latest/requirements.yaml#requirements[REQ-005].specifications[SPEC-005-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-005-01 blue / green runner は完了時に速報クロスチェック runner(dispatcher)へ系統ごとの公開 function(blue-completed / green-completed)で run_id、job_id、結果(終了コード、成果物ディレクトリまたは artifact_uri)を通知する。runner は相手側の状態や比較依頼を判断しない。自 slot の中止状態(aborted.txt の有無)も判断せず、実装が走り切って exitcode.txt を公開したときは通常どおり完了通知を送る

  REQ-005: 速報クロスチェックが、ジョブの実行ごとに blue と green の完了結果を非同期に比較し、差分を運用者へ提供すること

  @atdd_SPEC-005-01-1
  Scenario: SPEC-005-01-1
    Given blue が完了した
    When blue runner が完了通知を送る
    Then 速報クロスチェック runner に blue-completed(run_id, job_id, result) が届き、rapid_run の blue 側完了結果が登録される

  @atdd_SPEC-005-01-2
  Scenario: SPEC-005-01-2
    Given green が未完了
    When blue runner が完了通知を送る
    Then blue runner は green の状態を参照せず終了する

  @atdd_SPEC-005-01-3
  Scenario: SPEC-005-01-3
    Given 完了通知の送信が失敗した
    When slot runner が終了する
    Then 終了コードは実装スクリプトの exitcode のままで、Runner Result は変更されず、実行ログに警告が残る

  @atdd_SPEC-005-01-4
  Scenario: SPEC-005-01-4
    Given 運用者が同一引数で速報クロスチェック runner を再実行して完了通知を再送した
    When 完了結果を確認する
    Then 完了結果は一度だけ登録される(冪等・先勝ち)

  @atdd_SPEC-005-01-5
  Scenario: SPEC-005-01-5
    Given 完了通知の送信が失敗した
    When ハング検知が実行される
    Then 通知失敗は自動検知しない(スコープ外)

  @atdd_SPEC-005-01-6
  Scenario: SPEC-005-01-6
    Given abort-blue で中止した後に実装が走り切り exitcode.txt が公開された
    When blue runner が終了する
    Then blue runner は中止状態を判断せず通常どおり完了通知(blue-completed)を送る
