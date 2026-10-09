# source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md#E2E完了条件(BDD)
# 転写: 正常系・異常系の 2 ブロックを意訳せず結合(S2 test-scaffold 生成。uc_id=dcd8234d)
Feature: クロスチェックのジョブマップと比較定義を定義する

  Scenario: 比較定義と対象カタログを検証する(SPEC-004-01)
    Given /etc/relay-gate/crosscheck-job-map.csv の内容が次である
      """
      # exit_code_contract=0:OK,3:NG,6:ERROR
      # target_catalog_path=/etc/relay-gate/target-catalog.csv
      # catalog_version=v1
      job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version
      JOB001,job,output.csv,/opt/compare/compare.sh,--blue {blue} --green {green},v1
      JOB002,job,summary.tsv,/opt/compare/compare-v2.sh,--blue {blue} --green {green} --ignore-header,v1
      """
    And /opt/compare/compare.sh と /opt/compare/compare-v2.sh が実行可能である
    And /etc/relay-gate/target-catalog.csv の内容が次である
      """
      catalog_version,target_type,target_identifier,compare_condition,business_date_handling
      v1,table,SALES_DAILY,key=sales_id,column=business_date
      v1,file,/data/out/summary_{business_date}.tsv,-,filename
      """
    When 基盤適用設計者が `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する
    And 続けて `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する
    Then 1 回目は終了コード 0 で stdout に `config=crosscheck-job-map`、`path: /etc/relay-gate/crosscheck-job-map.csv`、`rows=2`、`target_catalog_path: /etc/relay-gate/target-catalog.csv`、`catalog_version=v1`、`exit_code_contract=0:OK,3:NG,6:ERROR`、`status=valid` がこの順で出る
    And 2 回目は終了コード 0 で stdout に `config=target-catalog`、`path: /etc/relay-gate/target-catalog.csv`、`rows=2`、`catalog_versions=v1`、`tables=1`、`files=1`、`status=valid` がこの順で出る
    And 管理 DB への接続は行われず、relay-gate のスクリプトは変更されていない

  Scenario: job_id ごとに比較定義を差し替えて検証する
    Given crosscheck-job-map.csv の JOB002 行の compare_command を /opt/compare/compare-v3.sh に変更し、実行可能である
    When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する
    Then 終了コード 0 で `status=valid` が出て、JOB001 の定義は変更されていない

  Scenario: クロスチェックジョブマップと対象カタログは slot ジョブマップと同じ CSV 形式である(SPEC-004-04)
    Given crosscheck-job-map.csv の JOB002 行の compare_targets セルが二重引用符で囲まれた `"output.csv,summary.csv"` である(カンマを含むセル)
    And target-catalog.csv の compare_condition セルが二重引用符で囲まれた `"key=sales_id,branch_id"` である
    When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` と `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する
    Then どちらも終了コード 0 で `status=valid` が出て、囲んだセルはカンマを含む 1 セルとして解析される
    And slot ジョブマップの読み込みと同じ CSV クォート解析関数が使われ、タブ区切りのファイルは `error: header mismatch` で拒否される

  Scenario: job_id が重複している
    Given 前シナリオの crosscheck-job-map.csv(宣言 3 行 + ヘッダー + JOB001 + JOB002 の 6 行)の 6 行目(JOB002 行)を JOB001 行の複製に置き換える
    When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する
    Then 終了コードは 2 で stderr に `error: duplicate job_id job_id=JOB001 lines=5,6` が出る(初出行 5 を含む)

  Scenario: compare_command が実行できない
    Given crosscheck-job-map.csv の JOB001 行の compare_command が /opt/compare/missing.sh で存在しない
    When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する
    Then 終了コードは 2 で stderr に `error: compare_command is not executable line=5 job_id=JOB001 value=/opt/compare/missing.sh` が出る

  Scenario: ヘッダー列が契約と異なる
    Given crosscheck-job-map.csv のヘッダー行が `job_id,host,comparison_type,compare_targets,compare_command,compare_options,definition_version` である(slot ジョブマップの host 列が混入している)
    When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する
    Then 終了コードは 2 で stderr に `error: header mismatch expected=job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version actual=job_id,host,comparison_type,compare_targets,compare_command,compare_options,definition_version path: /etc/relay-gate/crosscheck-job-map.csv` が出る

  Scenario: 対象カタログの target_type が不正
    Given 前シナリオの target-catalog.csv(ヘッダー + 2 行)の 3 行目(file 行)の target_type を view に変える
    When `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する
    Then 終了コードは 2 で stderr に `error: target_type is not in table,file line=3 value=view` が出る
