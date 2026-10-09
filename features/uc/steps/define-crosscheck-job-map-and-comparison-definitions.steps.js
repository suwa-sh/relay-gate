// UC BDD(②)step definition skeleton。uc_id=dcd8234d / branch_slug=define-crosscheck-job-map-and-comparison-definitions(S2 test-scaffold 生成。S6 uc-bdd で実装する)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md#E2E完了条件(BDD)
// step 文言は feature から転写したリテラルを正規表現で完全一致させる(DocString 付き step も文言は同じ)。
// World / Before / After は features/uc/steps/configure-feature-flags.steps.js が定義済み(同一 require glob で読まれる)。
// ここでは setWorldConstructor を呼ばない(World は 1 つだけ)。
// UC 横断 Scenario の一覧: docs/impl/latest/dcd8234d/issues/ の cross-uc-scenarios を参照。
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

// S2 skeleton: 全 step は「未実装」を理由に明示的に fail する(red baseline)
function notImplemented(step) {
  throw new Error(`not implemented: uc_id=dcd8234d define-crosscheck-job-map-and-comparison-definitions step skeleton (S2 test-scaffold, UC BDD) - ${step}`);
}

// ---- Given ----

Given(literal('/etc/relay-gate/crosscheck-job-map.csv の内容が次である'), function () {
  notImplemented('/etc/relay-gate/crosscheck-job-map.csv の内容が次である');
});

Given(literal('/opt/compare/compare.sh と /opt/compare/compare-v2.sh が実行可能である'), function () {
  notImplemented('/opt/compare/compare.sh と /opt/compare/compare-v2.sh が実行可能である');
});

Given(literal('/etc/relay-gate/target-catalog.csv の内容が次である'), function () {
  notImplemented('/etc/relay-gate/target-catalog.csv の内容が次である');
});

Given(literal('crosscheck-job-map.csv の JOB002 行の compare_command を /opt/compare/compare-v3.sh に変更し、実行可能である'), function () {
  notImplemented('crosscheck-job-map.csv の JOB002 行の compare_command を /opt/compare/compare-v3.sh に変更し、実行可能である');
});

Given(literal('crosscheck-job-map.csv の JOB002 行の compare_targets セルが二重引用符で囲まれた `"output.csv,summary.csv"` である(カンマを含むセル)'), function () {
  notImplemented('crosscheck-job-map.csv の JOB002 行の compare_targets セルが二重引用符で囲まれた `"output.csv,summary.csv"` である(カンマを含むセル)');
});

Given(literal('target-catalog.csv の compare_condition セルが二重引用符で囲まれた `"key=sales_id,branch_id"` である'), function () {
  notImplemented('target-catalog.csv の compare_condition セルが二重引用符で囲まれた `"key=sales_id,branch_id"` である');
});

Given(literal('前シナリオの crosscheck-job-map.csv(宣言 3 行 + ヘッダー + JOB001 + JOB002 の 6 行)の 6 行目(JOB002 行)を JOB001 行の複製に置き換える'), function () {
  notImplemented('前シナリオの crosscheck-job-map.csv(宣言 3 行 + ヘッダー + JOB001 + JOB002 の 6 行)の 6 行目(JOB002 行)を JOB001 行の複製に置き換える');
});

Given(literal('crosscheck-job-map.csv の JOB001 行の compare_command が /opt/compare/missing.sh で存在しない'), function () {
  notImplemented('crosscheck-job-map.csv の JOB001 行の compare_command が /opt/compare/missing.sh で存在しない');
});

Given(literal('crosscheck-job-map.csv のヘッダー行が `job_id,host,comparison_type,compare_targets,compare_command,compare_options,definition_version` である(slot ジョブマップの host 列が混入している)'), function () {
  notImplemented('crosscheck-job-map.csv のヘッダー行が `job_id,host,comparison_type,compare_targets,compare_command,compare_options,definition_version` である(slot ジョブマップの host 列が混入している)');
});

Given(literal('前シナリオの target-catalog.csv(ヘッダー + 2 行)の 3 行目(file 行)の target_type を view に変える'), function () {
  notImplemented('前シナリオの target-catalog.csv(ヘッダー + 2 行)の 3 行目(file 行)の target_type を view に変える');
});

// ---- When ----

When(literal('基盤適用設計者が `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する'), function () {
  notImplemented('基盤適用設計者が `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する');
});

When(literal('続けて `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する'), function () {
  notImplemented('続けて `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する');
});

When(literal('`validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する'), function () {
  notImplemented('`validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する');
});

When(literal('`validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` と `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する'), function () {
  notImplemented('`validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` と `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する');
});

When(literal('`validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する'), function () {
  notImplemented('`validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する');
});

// ---- Then ----

Then(literal('1 回目は終了コード 0 で stdout に `config=crosscheck-job-map`、`path: /etc/relay-gate/crosscheck-job-map.csv`、`rows=2`、`target_catalog_path: /etc/relay-gate/target-catalog.csv`、`catalog_version=v1`、`exit_code_contract=0:OK,3:NG,6:ERROR`、`status=valid` がこの順で出る'), function () {
  notImplemented('1 回目は終了コード 0 で stdout に `config=crosscheck-job-map`、`path: /etc/relay-gate/crosscheck-job-map.csv`、`rows=2`、`target_catalog_path: /etc/relay-gate/target-catalog.csv`、`catalog_version=v1`、`exit_code_contract=0:OK,3:NG,6:ERROR`、`status=valid` がこの順で出る');
});

Then(literal('2 回目は終了コード 0 で stdout に `config=target-catalog`、`path: /etc/relay-gate/target-catalog.csv`、`rows=2`、`catalog_versions=v1`、`tables=1`、`files=1`、`status=valid` がこの順で出る'), function () {
  notImplemented('2 回目は終了コード 0 で stdout に `config=target-catalog`、`path: /etc/relay-gate/target-catalog.csv`、`rows=2`、`catalog_versions=v1`、`tables=1`、`files=1`、`status=valid` がこの順で出る');
});

Then(literal('管理 DB への接続は行われず、relay-gate のスクリプトは変更されていない'), function () {
  notImplemented('管理 DB への接続は行われず、relay-gate のスクリプトは変更されていない');
});

Then(literal('終了コード 0 で `status=valid` が出て、JOB001 の定義は変更されていない'), function () {
  notImplemented('終了コード 0 で `status=valid` が出て、JOB001 の定義は変更されていない');
});

Then(literal('どちらも終了コード 0 で `status=valid` が出て、囲んだセルはカンマを含む 1 セルとして解析される'), function () {
  notImplemented('どちらも終了コード 0 で `status=valid` が出て、囲んだセルはカンマを含む 1 セルとして解析される');
});

Then(literal('slot ジョブマップの読み込みと同じ CSV クォート解析関数が使われ、タブ区切りのファイルは `error: header mismatch` で拒否される'), function () {
  notImplemented('slot ジョブマップの読み込みと同じ CSV クォート解析関数が使われ、タブ区切りのファイルは `error: header mismatch` で拒否される');
});

Then(literal('終了コードは 2 で stderr に `error: duplicate job_id job_id=JOB001 lines=5,6` が出る(初出行 5 を含む)'), function () {
  notImplemented('終了コードは 2 で stderr に `error: duplicate job_id job_id=JOB001 lines=5,6` が出る(初出行 5 を含む)');
});

Then(literal('終了コードは 2 で stderr に `error: compare_command is not executable line=5 job_id=JOB001 value=/opt/compare/missing.sh` が出る'), function () {
  notImplemented('終了コードは 2 で stderr に `error: compare_command is not executable line=5 job_id=JOB001 value=/opt/compare/missing.sh` が出る');
});

Then(literal('終了コードは 2 で stderr に `error: header mismatch expected=job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version actual=job_id,host,comparison_type,compare_targets,compare_command,compare_options,definition_version path: /etc/relay-gate/crosscheck-job-map.csv` が出る'), function () {
  notImplemented('終了コードは 2 で stderr に `error: header mismatch expected=job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version actual=job_id,host,comparison_type,compare_targets,compare_command,compare_options,definition_version path: /etc/relay-gate/crosscheck-job-map.csv` が出る');
});

Then(literal('終了コードは 2 で stderr に `error: target_type is not in table,file line=3 value=view` が出る'), function () {
  notImplemented('終了コードは 2 で stderr に `error: target_type is not in table,file line=3 value=view` が出る');
});
