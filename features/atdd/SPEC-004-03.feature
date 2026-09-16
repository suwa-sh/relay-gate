# source: docs/usdm/latest/requirements.yaml#requirements[REQ-004].specifications[SPEC-004-03].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-004-03 run 開始時に、解決済みのホスト・スクリプト・作業ディレクトリ・固定引数・追加引数・マップ版・実装版・role ごとの hang_detect_limit_minutes を facade/<run_id>/execution-spec.json として一度だけ確定保存する。認証情報そのものは保存せず参照名だけを保存する

  REQ-004: ジョブスケジューラのジョブ定義に実行先(ホスト・実行ユーザー・スクリプトパス)を持たせず、slot runner が実装固有のジョブマップで JOB_ID から実行先を解決し、解決結果を execution-spec.json として保存すること

  @atdd_SPEC-004-03-1
  Scenario: SPEC-004-03-1
    Given run を開始した
    When facade/<run_id>/execution-spec.json を確認する
    Then 解決済みの実行設定・追加引数・マップ版・実装版・role ごとの hang_detect_limit_minutes が記録され、認証情報の値は含まれない

  @atdd_SPEC-004-03-2
  Scenario: SPEC-004-03-2
    Given run 開始後にジョブマップを変更した
    When 同じ run の execution-spec.json を確認する
    Then 変更前の内容のまま上書きされていない
