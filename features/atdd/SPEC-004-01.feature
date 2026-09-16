# source: docs/usdm/latest/requirements.yaml#requirements[REQ-004].specifications[SPEC-004-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-004-01 実装スロットと runner は feature flag が、ホスト・実行ユーザー・スクリプト・作業ディレクトリ・固定引数・hang_detect_limit_minutes は該当 slot のジョブマップが、比較対象と対象カタログはクロスチェックのジョブマップが所有する

  REQ-004: ジョブスケジューラのジョブ定義に実行先(ホスト・実行ユーザー・スクリプトパス)を持たせず、slot runner が実装固有のジョブマップで JOB_ID から実行先を解決し、解決結果を execution-spec.json として保存すること

  @atdd_SPEC-004-01-1
  Scenario: SPEC-004-01-1
    Given slot のジョブマップに JOB_ID の行がある
    When runner が JOB_ID を解決する
    Then ホスト・実行ユーザー・スクリプト・作業ディレクトリ・固定引数・hang_detect_limit_minutes が得られる
