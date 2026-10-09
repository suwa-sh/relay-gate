# source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-rapid-crosscheck.md#ティア完了条件(BDD)
# 転写: gherkin ブロックを意訳せず転写(S2 test-scaffold 生成。uc_id=dcd8234d)
Feature: クロスチェックのジョブマップと比較定義を定義する - 速報クロスチェックティア

  Scenario: 妥当なジョブマップを検証する
    Given /etc/relay-gate/crosscheck-job-map.csv が宣言 3 行 + ヘッダー + JOB001 / JOB002 の 2 行で構成され、compare_command が実行可能である
    When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する
    Then 終了コード 0 で stdout に `config=crosscheck-job-map`、`rows=2`、`status=valid` が出る

  Scenario: exit_code_contract 宣言が無い
    Given crosscheck-job-map.csv に `# exit_code_contract=` の行が無い
    When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する
    Then 終了コード 2 で stderr に `error: exit_code_contract declaration not found path: /etc/relay-gate/crosscheck-job-map.csv` が出る

  Scenario: compare_options にプレースホルダが無い
    Given JOB001 行の compare_options が `--fast` である
    When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する
    Then 終了コード 2 で stderr に `error: compare_options is missing {blue} or {green} line=5 job_id=JOB001 value=--blue {blue}` が出る

  Scenario: 複数の違反を全件出力する
    Given JOB001 行の compare_command が存在せず、JOB002 行の列数が 5 である
    When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する
    Then 終了コード 2 で stderr に error 行が 2 行出て、stdout に `status=invalid` と `violations=2` が出る
