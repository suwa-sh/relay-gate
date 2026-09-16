# source: docs/usdm/latest/requirements.yaml#requirements[REQ-013].specifications[SPEC-013-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-013-01 比較対象と対象カタログはクロスチェックのジョブマップで適用側が定義し、job_id ごとに比較定義を差し替えられる。外部 IF の送受信方針・ネットワーク制約・ホスト配置は適用文書で定義し、relay-gate の仕組みには含めない

  REQ-013: 外部 IF の送受信方針、比較対象の定義、個別製品のネットワーク制約、実装固有のホスト配置は relay-gate ではなく適用側で定義できること

  @atdd_SPEC-013-01-1
  Scenario: SPEC-013-01-1
    Given 新しい案件に適用する
    When runner・ジョブマップ・比較定義だけを差し替える
    Then facade・クロスチェック runner / worker・ハング検知・リラン・中止のスクリプトは変更不要である
