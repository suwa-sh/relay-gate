# source: docs/usdm/latest/requirements.yaml#requirements[REQ-006].specifications[SPEC-006-02].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-006-02 確報クロスチェック worker は DB セグメントで依頼を poll / claim し、自分の設定に 1 行で定義された確報の比較ツール起動コマンドをそのまま(プレースホルダ置換なしで)起動して全テーブル・全ファイルの比較を実行し、起動した実装の stdout・stderr・exit_code を依頼レコードの列へ保存する。worker が読む入力は管理 DB の依頼レコードと自分の設定ファイルだけとし、比較ツールにファイルパス(対象カタログのパスなど)を渡さず、worker 側で成果物ファイルを保存しない。exit_code が 0 なら SUCCEEDED、非 0 または起動失敗(実行エラー)なら FAILED とする

  REQ-006: 確報クロスチェックが、ジョブスケジューラの別ジョブ定義から起動され、全テーブル・全ファイルを対象に日次整合性を正式確認し、stdout・stderr・exitcode をジョブスケジューラへ返すこと

  @atdd_SPEC-006-02-1
  Scenario: SPEC-006-02-1
    Given REQUESTED の確報比較依頼
    When worker が claim して比較を完了する
    Then 依頼に stdout・stderr・exitcode が保存され、exitcode=0 で SUCCEEDED、非 0 で FAILED になる

  @atdd_SPEC-006-02-2
  Scenario: SPEC-006-02-2
    Given 確報の起動コマンドが設定に 1 行で定義されている
    When worker が依頼を claim する
    Then その 1 行がそのまま起動され、依頼レコードと自分の設定以外の入力(対象カタログのファイルなど)を読まない

  @atdd_SPEC-006-02-3
  Scenario: SPEC-006-02-3
    Given 比較ツールの起動に失敗した
    When worker が依頼を処理する
    Then 依頼は FAILED で終端し、error_summary に起動失敗の理由が残る

  @atdd_SPEC-006-02-4
  Scenario: SPEC-006-02-4
    Given worker が依頼を処理した
    When 成果物ディレクトリを確認する
    Then worker が書いたファイルは無い
