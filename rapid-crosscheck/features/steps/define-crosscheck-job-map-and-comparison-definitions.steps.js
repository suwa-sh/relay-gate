// tier BDD(③)step definition skeleton。tier-rapid-crosscheck / uc_id=dcd8234d(クロスチェックのジョブマップと比較定義を定義する)。S2 test-scaffold 生成。S4 tier-impl で実装する。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-rapid-crosscheck.md#ティア完了条件(BDD)
// step 文言は feature から転写したリテラルを正規表現で完全一致させる。
// 本 tier には先行 UC の step ファイルが無いため、Before / After(一時ディレクトリ)は S4 で本ファイルに追加する。
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

// S2 skeleton: 全 step は「未実装」を理由に明示的に fail する(red baseline)
function notImplemented(step) {
  throw new Error(`not implemented: uc_id=dcd8234d define-crosscheck-job-map-and-comparison-definitions step skeleton (S2 test-scaffold, tier BDD) - ${step}`);
}

// ---- Given ----

Given(literal('/etc/relay-gate/crosscheck-job-map.csv が宣言 3 行 + ヘッダー + JOB001 / JOB002 の 2 行で構成され、compare_command が実行可能である'), function () {
  notImplemented('/etc/relay-gate/crosscheck-job-map.csv が宣言 3 行 + ヘッダー + JOB001 / JOB002 の 2 行で構成され、compare_command が実行可能である');
});

Given(literal('crosscheck-job-map.csv に `# exit_code_contract=` の行が無い'), function () {
  notImplemented('crosscheck-job-map.csv に `# exit_code_contract=` の行が無い');
});

Given(literal('JOB001 行の compare_options が `--fast` である'), function () {
  notImplemented('JOB001 行の compare_options が `--fast` である');
});

Given(literal('JOB001 行の compare_command が存在せず、JOB002 行の列数が 5 である'), function () {
  notImplemented('JOB001 行の compare_command が存在せず、JOB002 行の列数が 5 である');
});

// ---- When ----

When(literal('`validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する'), function () {
  notImplemented('`validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する');
});

// ---- Then ----

Then(literal('終了コード 0 で stdout に `config=crosscheck-job-map`、`rows=2`、`status=valid` が出る'), function () {
  notImplemented('終了コード 0 で stdout に `config=crosscheck-job-map`、`rows=2`、`status=valid` が出る');
});

Then(literal('終了コード 2 で stderr に `error: exit_code_contract declaration not found path: /etc/relay-gate/crosscheck-job-map.csv` が出る'), function () {
  notImplemented('終了コード 2 で stderr に `error: exit_code_contract declaration not found path: /etc/relay-gate/crosscheck-job-map.csv` が出る');
});

Then(literal('終了コード 2 で stderr に `error: compare_options is missing {blue} or {green} line=5 job_id=JOB001 value=--blue {blue}` が出る'), function () {
  notImplemented('終了コード 2 で stderr に `error: compare_options is missing {blue} or {green} line=5 job_id=JOB001 value=--blue {blue}` が出る');
});

Then(literal('終了コード 2 で stderr に error 行が 2 行出て、stdout に `status=invalid` と `violations=2` が出る'), function () {
  notImplemented('終了コード 2 で stderr に error 行が 2 行出て、stdout に `status=invalid` と `violations=2` が出る');
});
