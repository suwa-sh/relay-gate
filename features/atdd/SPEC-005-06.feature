# source: docs/usdm/latest/requirements.yaml#requirements[REQ-005].specifications[SPEC-005-06].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-005-06 速報クロスチェックの管理 DB 接続参照名(RAPID_DB_CONN_REF)、依頼の lease 期間(秒。RAPID_LEASE_SEC)、worker の poll 間隔(秒。RAPID_POLL_INTERVAL_SEC)は、基盤適用設計者が所有する速報クロスチェック設定(速報クロスチェック用 env 設定ファイル)で定義する。認証情報は値を置かず参照名のみとする。facade・slot runner・速報クロスチェック runner・速報クロスチェック worker はこの設定を入力として管理 DB へ接続し、claim の lease と poll 間隔を決める。RAPID_CROSSCHECK_MODE=off のときはこの設定を必要としない

  REQ-005: 速報クロスチェックが、ジョブの実行ごとに blue と green の完了結果を非同期に比較し、差分を運用者へ提供すること

  @atdd_SPEC-005-06-1
  Scenario: SPEC-005-06-1
    Given 速報クロスチェック設定に管理 DB 接続参照名・lease 期間・poll 間隔が定義されている
    When RAPID_CROSSCHECK_MODE=background で slot runner が完了通知を送り worker が依頼を claim する
    Then 設定された参照名で管理 DB に接続し、設定された lease 期間と poll 間隔で claim と poll が行われる

  @atdd_SPEC-005-06-2
  Scenario: SPEC-005-06-2
    Given 設定所有区分
    When 速報クロスチェック設定の所有者を確認する
    Then 基盤適用設計者である

  @atdd_SPEC-005-06-3
  Scenario: SPEC-005-06-3
    Given 速報クロスチェック設定
    When 内容を確認する
    Then 認証情報の値は含まれず管理 DB 接続の参照名だけがある

  @atdd_SPEC-005-06-4
  Scenario: SPEC-005-06-4
    Given RAPID_CROSSCHECK_MODE=off
    When 速報クロスチェック設定が存在しない
    Then slot 実行は設定なしで実行できる
