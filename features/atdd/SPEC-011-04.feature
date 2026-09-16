# source: docs/usdm/latest/requirements.yaml#requirements[REQ-011].specifications[SPEC-011-04].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-011-04 run_id は {ローカルタイムゾーンの yyyymmddThhmmss}-{job_id}-{8 桁 hex 乱数} の形式で facade が発行する(例 20260830T203000-JOB001-3f9a1c2e)。時刻部はホストのローカルタイムゾーンとし、タイムゾーン指示子は付けない。成果物ディレクトリ名と管理 DB の run_id は同じ値とする

  REQ-011: 1 回の並行稼働を run_id で相関付け、速報側(parallel_run / rapid_run / rapid_crosscheck_request / comparison_result)と確報側(final_crosscheck_request / 対象カタログ)を別ドメインのデータモデルとして管理 DB に保持すること

  @atdd_SPEC-011-04-1
  Scenario: SPEC-011-04-1
    Given run を開始した
    When 成果物ディレクトリ名と管理 DB の parallel_run.run_id を確認する
    Then 同じ値である

  @atdd_SPEC-011-04-2
  Scenario: SPEC-011-04-2
    Given RAPID_CROSSCHECK_MODE=off(管理 DB なし)
    When facade が run を開始する
    Then facade 単独で run_id を発行できる

  @atdd_SPEC-011-04-3
  Scenario: SPEC-011-04-3
    Given 発行された run_id
    When 形式を検証する
    Then yyyymmddThhmmss-{job_id}-8 桁 hex に一致し、時刻部はローカルタイムゾーンで末尾に Z を含まない
