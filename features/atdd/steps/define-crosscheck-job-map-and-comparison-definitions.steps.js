// ATDD(①)step definition skeleton。uc_id=dcd8234d / branch_slug=define-crosscheck-job-map-and-comparison-definitions(S2 test-scaffold 生成)。
// source: features/atdd/SPEC-004-04.feature(@atdd_SPEC-004-04-5 / @atdd_SPEC-004-04-6 / @atdd_SPEC-004-04-7 / @atdd_SPEC-004-04-8 / @atdd_SPEC-004-04-10 / @atdd_SPEC-004-04-11)
//   対象は uc-map dcd8234d の atdd_scenarios に列挙された 6 Scenario のみ。同 feature の -1〜-4 は UC eff24f55、
//   -9(確報の起動コマンド)は別 UC の担当で、ここでは定義しない。
// 仕様の還流後の acceptance_criteria に合わせて作り直した(旧: クロスチェックジョブマップ CSV の形式確認)。
// 全 step は feature から転写したリテラルを完全一致の正規表現で受け、'not implemented' を throw する(red baseline)。
// S7 atdd で実装する。World / Before / After は features/atdd/steps/configure-feature-flags.steps.js が定義済み。
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

function notImplemented() {
  throw new Error('not implemented (S2 skeleton, ATDD)');
}

Given(literal("速報の起動コマンドのコマンド部分(先頭の語)が絶対パスで、存在し、実行可能で、文字列に {job_id} を含む"), notImplemented);
When(literal("validate-config.sh で速報の起動コマンドの設定を検証する"), notImplemented);
Then(literal("終了コード 0 で終了し、stderr に error 行が出ない"), notImplemented);
Given(literal("起動コマンドのコマンド部分が絶対パスでない"), notImplemented);
When(literal("validate-config.sh で検証する"), notImplemented);
Then(literal("非 0 の終了コードで終了し、stderr に絶対パスでない旨の error 行がキー名とパスつきで 1 行出る"), notImplemented);
Given(literal("起動コマンドのコマンド部分のファイルが存在しない、または実行可能でない"), notImplemented);
Then(literal("非 0 の終了コードで終了し、stderr に実行可能でない旨の error 行がキー名とパスつきで 1 行出る"), notImplemented);
Given(literal("速報の起動コマンドに {job_id} が含まれない"), notImplemented);
Then(literal("非 0 の終了コードで終了し、stderr に {job_id} が無い旨の error 行がキー名と値つきで 1 行出る"), notImplemented);
Given(literal("起動コマンドの引数部分に任意の文字列(存在しないパスや未知の語を含む)"), notImplemented);
Then(literal("引数部分を理由とする error 行は出ず、終了コードは引数部分の内容に影響されない"), notImplemented);
Given(literal("relay-gate の設定ファイル置き場"), notImplemented);
When(literal("クロスチェックジョブマップ CSV や対象カタログ CSV を探す"), notImplemented);
Then(literal("存在せず、validate-config.sh にそれらを検証する種別も無い"), notImplemented);
