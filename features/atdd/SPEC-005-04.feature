# source: docs/usdm/latest/requirements.yaml#requirements[REQ-005].specifications[SPEC-005-04].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-005-04 RAPID_CROSSCHECK_MODE=off のとき、blue / green runner は完了通知を送信せず、速報管理 DB への接続・完了結果・比較依頼・比較結果の書き込みを行わない。このとき parallel_run も作成せず、slot 実行と background 側リランは成果物ファイルだけで動作する

  REQ-005: 速報クロスチェックが、ジョブの実行ごとに blue と green の完了結果を非同期に比較し、差分を運用者へ提供すること

  @atdd_SPEC-005-04-1
  Scenario: SPEC-005-04-1
    Given RAPID_CROSSCHECK_MODE=off
    When slot を実行する
    Then 速報管理 DB の接続設定なしで実行でき、DB へ何も書き込まれない

  @atdd_SPEC-005-04-2
  Scenario: SPEC-005-04-2
    Given RAPID_CROSSCHECK_MODE=background
    When slot が完了する
    Then runner が完了通知を送信し、速報管理 DB に完了結果と比較依頼が書き込まれる

  @atdd_SPEC-005-04-3
  Scenario: SPEC-005-04-3
    Given RAPID_CROSSCHECK_MODE=foreground
    When slot が完了する
    Then background と同じく runner が完了通知を送信し、速報管理 DB に完了結果と比較依頼が書き込まれる
