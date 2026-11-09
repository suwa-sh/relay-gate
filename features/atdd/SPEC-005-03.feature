# source: docs/usdm/latest/requirements.yaml#requirements[REQ-005].specifications[SPEC-005-03].acceptance_criteria
# 転写: 1 criterion = 1 Scenario。文言は原文のまま(Given / When / Then の区切りで行分割のみ)。bootstrap P7 生成
Feature: SPEC-005-03 速報クロスチェック worker は比較依頼を取得(poll / claim)し、自分の設定に 1 行で定義された速報の比較ツール起動コマンドのプレースホルダを依頼レコードの値で置換して比較ツールを起動し、比較ツールの stdout・stderr・exit_code を依頼レコードの列へ保存する。プレースホルダは依頼レコードの値だけで、{job_id} を必須、{run_id} / {params} / {blue_exit_code} / {green_exit_code} を任意とする。worker が読む入力は管理 DB の依頼レコードと自分の設定ファイルだけとし、比較ツールにファイルパス(成果物 URI など)を渡さず、worker 側で成果物ファイル(stdout / stderr / exitcode のファイル)を保存しない。比較結果(差分件数・レポート URI など)を stdout から抽出して別レコードに登録しない。exit_code が 0 なら SUCCEEDED、非 0 または起動失敗なら FAILED(起動失敗は error_summary に理由)とする。ジョブ ID ごとの比較定義は持たないため「比較定義が無い job_id」の失敗は存在しない

  REQ-005: 速報クロスチェックが、ジョブの実行ごとに blue と green の完了結果を非同期に比較し、差分を運用者へ提供すること

  @atdd_SPEC-005-03-1
  Scenario: SPEC-005-03-1
    Given REQUESTED の速報比較依頼がある
    When worker が poll する
    Then 依頼を claim し、設定の起動コマンドのプレースホルダを依頼レコードの値で置換して比較ツールを起動し、stdout・stderr・exit_code を依頼レコードに保存する

  @atdd_SPEC-005-03-2
  Scenario: SPEC-005-03-2
    Given 起動コマンドが {job_id} と {run_id} と {params} を含む
    When worker が run_id=R1・job_id=J1・parameters=p1 p2 の依頼を処理する
    Then 比較ツールは J1・R1・p1 p2 に置換された引数で起動される

  @atdd_SPEC-005-03-3
  Scenario: SPEC-005-03-3
    Given 比較ツールの起動に失敗した
    When worker が依頼を処理する
    Then 依頼は FAILED で終端し、error_summary に起動失敗の理由が残る

  @atdd_SPEC-005-03-4
  Scenario: SPEC-005-03-4
    Given 比較ツールが終了コード 0 を返した
    When worker が結果を保存する
    Then 依頼は SUCCEEDED になり、stdout・stderr はそのまま依頼レコードに保存され、別の比較結果レコードは作成されない

  @atdd_SPEC-005-03-5
  Scenario: SPEC-005-03-5
    Given 比較ツールが非 0 の終了コードを返した
    When worker が結果を保存する
    Then 依頼は FAILED になり、exit_code にその値が保存される

  @atdd_SPEC-005-03-6
  Scenario: SPEC-005-03-6
    Given worker が依頼を処理した
    When runner 側の成果物ディレクトリを確認する
    Then worker が書いたファイルは無い
