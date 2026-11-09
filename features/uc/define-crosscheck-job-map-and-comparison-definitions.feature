# source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md#E2E完了条件(BDD)
# 転写: 正常系・異常系の 2 ブロックを意訳せず結合(S2 test-scaffold 生成。uc_id=dcd8234d。spec event 20261027_055000_feedback_impl_feedback_dcd8234d)
Feature: クロスチェックのジョブマップと比較定義を定義する

  Scenario: 速報の起動コマンドを検証する(SPEC-004-01)
    Given /etc/relay-gate/rapid-crosscheck.env の内容が次である
      """
      RAPID_DB_CONN_REF=rapid_db
      RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} --run {run_id}
      """
    And /opt/compare/compare.sh が実行可能である
    When 基盤適用設計者が `validate-config.sh --rapid-crosscheck /etc/relay-gate/rapid-crosscheck.env` を実行する
    Then 終了コード 0 で stdout に `config=rapid-crosscheck`、`path: /etc/relay-gate/rapid-crosscheck.env`、`command_path: /opt/compare/compare.sh`、`has_job_id_placeholder=true`、`status=valid` がこの順で出る
    And 管理 DB への接続は行われず、relay-gate のスクリプトは変更されていない

  Scenario: 起動コマンドを差し替えて検証する
    Given rapid-crosscheck.env の RAPID_COMPARE_COMMAND を `/opt/compare/compare-v2.sh --job {job_id}` に変更し、/opt/compare/compare-v2.sh が実行可能である
    When `validate-config.sh --rapid-crosscheck /etc/relay-gate/rapid-crosscheck.env` を実行する
    Then 終了コード 0 で stdout に `command_path: /opt/compare/compare-v2.sh`、`status=valid` が出る

  Scenario: コマンド部分が実行できない
    Given rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `/opt/compare/missing.sh --job {job_id}` でコマンド部分が存在しない
    When `validate-config.sh --rapid-crosscheck /etc/relay-gate/rapid-crosscheck.env` を実行する
    Then 終了コードは 2 で stderr に `error: file not executable key=RAPID_COMPARE_COMMAND path=/opt/compare/missing.sh` が出る

  Scenario: コマンド部分が絶対パスでない
    Given rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `compare.sh --job {job_id}` で先頭の語が絶対パスでない
    When `validate-config.sh --rapid-crosscheck /etc/relay-gate/rapid-crosscheck.env` を実行する
    Then 終了コードは 2 で stderr に `error: path is not absolute key=RAPID_COMPARE_COMMAND path=compare.sh` が出る

  Scenario: {job_id} プレースホルダが無い
    Given rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `/opt/compare/compare.sh --run {run_id}` で `{job_id}` を含まない
    When `validate-config.sh --rapid-crosscheck /etc/relay-gate/rapid-crosscheck.env` を実行する
    Then 終了コードは 2 で stderr に `error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --run {run_id}` が出る

  Scenario: {params} が引数全体でない位置にある
    Given rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `/opt/compare/compare.sh --job {job_id} --args={params}` で、`{params}` が `--args=` と同じ引数の一部になっている
    When `validate-config.sh --rapid-crosscheck /etc/relay-gate/rapid-crosscheck.env` を実行する
    Then 終了コードは 2 で stderr に `error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --job {job_id} --args={params}` が出る

  Scenario: {params} が引数 1 つ全体なら valid
    Given rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `/opt/compare/compare.sh --job {job_id} {params}` で、`{params}` が独立した 1 引数であり /opt/compare/compare.sh が実行可能である
    When `validate-config.sh --rapid-crosscheck /etc/relay-gate/rapid-crosscheck.env` を実行する
    Then 終了コード 0 で stdout に `status=valid` が出る
