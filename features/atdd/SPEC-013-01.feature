# source: docs/usdm/latest/requirements.yaml#requirements[REQ-013].specifications[SPEC-013-01].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-013-01 比較対象(テーブル・ファイル)の定義は relay-gate の設定に持たず、適用側が比較ツール側で定義する。relay-gate が持つクロスチェックの設定(比較定義)は、速報・確報の比較ツール起動コマンド各 1 行だけとし、速報の起動コマンドは依頼レコードの値({job_id} 必須。{run_id} / {params} / {blue_exit_code} / {green_exit_code} は任意)をプレースホルダで比較ツールに渡すことで、ジョブごとの比較対象の決定を比較ツール側に委ねる。ジョブ ID ごとの比較定義の差し替えや対象カタログは relay-gate では持たない。外部 IF の送受信方針・ネットワーク制約・ホスト配置は適用文書で定義し、relay-gate の仕組みには含めない

  REQ-013: 外部 IF の送受信方針、比較対象の定義、個別製品のネットワーク制約、実装固有のホスト配置は relay-gate ではなく適用側で定義できること

  @atdd_SPEC-013-01-1
  Scenario: SPEC-013-01-1
    Given 新しい案件に適用する
    When runner・ジョブマップ・比較ツール起動コマンドだけを差し替える
    Then facade・クロスチェック runner / worker・ハング検知・リラン・中止のスクリプトは変更不要である

  @atdd_SPEC-013-01-2
  Scenario: SPEC-013-01-2
    Given 比較対象のテーブル・ファイルを追加した
    When relay-gate 側の作業を確認する
    Then relay-gate の設定変更は不要で、比較ツール側の定義変更だけで済む
