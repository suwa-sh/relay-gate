// tier BDD(③)step definition skeleton。tier-facade / uc_id=dcd8234d(クロスチェックのジョブマップと比較定義を定義する)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-facade.md#ティア完了条件(BDD)
// 全 step は feature から転写したリテラルを完全一致の正規表現で受け、'not implemented' を throw する(red baseline)。
// S4 tier-impl で実装する。Before / After は facade/features/steps/configure-feature-flags.steps.js が定義済み
// (Scenario ごとの一時ディレクトリ this.workDir)。
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

function notImplemented() {
  throw new Error('not implemented (S2 skeleton, tier BDD)');
}

Given(literal("RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} で /opt/compare/compare.sh が実行可能"), notImplemented);
When(literal("validate-config.sh --rapid-crosscheck <path> を実行する"), notImplemented);
Then(literal("終了コード 0 で stdout に status=valid、command_path: /opt/compare/compare.sh、has_job_id_placeholder=true が出る"), notImplemented);
Given(literal("RAPID_COMPARE_COMMAND=/opt/compare/missing.sh --job {job_id} でコマンド部分が存在しない"), notImplemented);
Then(literal("終了コード 2 で stderr に `error: file not executable key=RAPID_COMPARE_COMMAND path=/opt/compare/missing.sh` が出る"), notImplemented);
Given(literal("RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --run {run_id} で {job_id} を含まない"), notImplemented);
Then(literal("終了コード 2 で stderr に `error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --run {run_id}` が出る"), notImplemented);
Given(literal("RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} --args={params} で {params} が引数の一部になっている"), notImplemented);
Then(literal("終了コード 2 で stderr に `error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --job {job_id} --args={params}` が出る"), notImplemented);
Given(literal("RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} {params} で /opt/compare/compare.sh が実行可能"), notImplemented);
Then(literal("終了コード 0 で stdout に status=valid が出る"), notImplemented);
