# source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-facade.md#ティア完了条件(BDD)
# 転写: ティア完了条件の gherkin ブロックを意訳せず転写(S2 test-scaffold 生成。uc_id=dcd8234d / tier-facade)
Feature: tier-facade 速報クロスチェック設定の検証

  Scenario: 絶対パスで実行可能・{job_id} 含むなら valid
    Given RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} で /opt/compare/compare.sh が実行可能
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 0 で stdout に status=valid、command_path: /opt/compare/compare.sh、has_job_id_placeholder=true が出る

  Scenario: コマンド部分が実行不可なら 2
    Given RAPID_COMPARE_COMMAND=/opt/compare/missing.sh --job {job_id} でコマンド部分が存在しない
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 2 で stderr に `error: file not executable key=RAPID_COMPARE_COMMAND path=/opt/compare/missing.sh` が出る

  Scenario: {job_id} が無ければ 2
    Given RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --run {run_id} で {job_id} を含まない
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 2 で stderr に `error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --run {run_id}` が出る

  Scenario: {params} が引数全体でない位置にあれば 2
    Given RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} --args={params} で {params} が引数の一部になっている
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 2 で stderr に `error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --job {job_id} --args={params}` が出る

  Scenario: {params} が独立した 1 引数なら valid
    Given RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} {params} で /opt/compare/compare.sh が実行可能
    When validate-config.sh --rapid-crosscheck <path> を実行する
    Then 終了コード 0 で stdout に status=valid が出る
