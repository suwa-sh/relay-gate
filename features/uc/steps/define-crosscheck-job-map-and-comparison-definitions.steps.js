// UC BDD(②)step definition skeleton。uc_id=dcd8234d / branch_slug=define-crosscheck-job-map-and-comparison-definitions(S2 test-scaffold 生成)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md#E2E完了条件(BDD)
// 仕様の還流(クロスチェック簡素化 + 起動コマンドの argv 規則)後の spec に合わせて作り直した(旧: 比較定義 CSV / 対象カタログ)。
// 全 step は feature から転写したリテラルを完全一致の正規表現で受け、'not implemented' を throw する(red baseline)。
// S6 uc-bdd で実装する。World / Before / After は features/uc/steps/configure-feature-flags.steps.js が定義済み
// (同一 require glob で読まれる)。ここでは setWorldConstructor を呼ばない(World は 1 つだけ)。
// UC 横断 Scenario: 0 件(docs/impl/latest/dcd8234d/issues/20261027_083500_cross-uc-scenarios.md)。
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

function notImplemented() {
  throw new Error('not implemented (S2 skeleton, UC BDD)');
}

Given(literal("/etc/relay-gate/rapid-crosscheck.env の内容が次である"), function (_docString) {
  notImplemented();
});
Given(literal("/opt/compare/compare.sh が実行可能である"), notImplemented);
When(literal("基盤適用設計者が `validate-config.sh --rapid-crosscheck /etc/relay-gate/rapid-crosscheck.env` を実行する"), notImplemented);
Then(literal("終了コード 0 で stdout に `config=rapid-crosscheck`、`path: /etc/relay-gate/rapid-crosscheck.env`、`command_path: /opt/compare/compare.sh`、`has_job_id_placeholder=true`、`status=valid` がこの順で出る"), notImplemented);
Then(literal("管理 DB への接続は行われず、relay-gate のスクリプトは変更されていない"), notImplemented);
Given(literal("rapid-crosscheck.env の RAPID_COMPARE_COMMAND を `/opt/compare/compare-v2.sh --job {job_id}` に変更し、/opt/compare/compare-v2.sh が実行可能である"), notImplemented);
When(literal("`validate-config.sh --rapid-crosscheck /etc/relay-gate/rapid-crosscheck.env` を実行する"), notImplemented);
Then(literal("終了コード 0 で stdout に `command_path: /opt/compare/compare-v2.sh`、`status=valid` が出る"), notImplemented);
Given(literal("rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `/opt/compare/missing.sh --job {job_id}` でコマンド部分が存在しない"), notImplemented);
Then(literal("終了コードは 2 で stderr に `error: file not executable key=RAPID_COMPARE_COMMAND path=/opt/compare/missing.sh` が出る"), notImplemented);
Given(literal("rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `compare.sh --job {job_id}` で先頭の語が絶対パスでない"), notImplemented);
Then(literal("終了コードは 2 で stderr に `error: path is not absolute key=RAPID_COMPARE_COMMAND path=compare.sh` が出る"), notImplemented);
Given(literal("rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `/opt/compare/compare.sh --run {run_id}` で `{job_id}` を含まない"), notImplemented);
Then(literal("終了コードは 2 で stderr に `error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --run {run_id}` が出る"), notImplemented);
Given(literal("rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `/opt/compare/compare.sh --job {job_id} --args={params}` で、`{params}` が `--args=` と同じ引数の一部になっている"), notImplemented);
Then(literal("終了コードは 2 で stderr に `error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --job {job_id} --args={params}` が出る"), notImplemented);
Given(literal("rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `/opt/compare/compare.sh --job {job_id} {params}` で、`{params}` が独立した 1 引数であり /opt/compare/compare.sh が実行可能である"), notImplemented);
Then(literal("終了コード 0 で stdout に `status=valid` が出る"), notImplemented);
