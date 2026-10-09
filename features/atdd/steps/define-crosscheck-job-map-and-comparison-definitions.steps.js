// ATDD(①)step definition skeleton。uc_id=dcd8234d / branch_slug=define-crosscheck-job-map-and-comparison-definitions(S2 test-scaffold 生成。S7 atdd で実装する)。
// source: features/atdd/SPEC-004-04.feature(@atdd_SPEC-004-04-5)
//   対象は uc-map dcd8234d の atdd_scenarios に列挙された 1 Scenario のみ(同 feature の他 Scenario は他 UC の担当)。
// step 文言は feature から転写したリテラルを正規表現で完全一致させる。
// World / Before / After は features/atdd/steps/configure-feature-flags.steps.js が定義済み(同一 require glob で読まれる)。
// ここでは setWorldConstructor を呼ばない(World は 1 つだけ)。
// 3 step とも既存の step ファイル(configure-feature-flags / define-slot-job-maps)に同一文言は無く、ambiguous にならない。
// UC 横断 Scenario の扱い: docs/impl/latest/dcd8234d/issues/ の cross-uc-scenarios を参照。
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

// S2 skeleton: 全 step は「未実装」を理由に明示的に fail する(red baseline)
function notImplemented(step) {
  throw new Error(`not implemented: uc_id=dcd8234d define-crosscheck-job-map-and-comparison-definitions step skeleton (S2 test-scaffold, ATDD) - ${step}`);
}

// ---- @atdd_SPEC-004-04-5 ----

Given(literal('クロスチェックジョブマップと対象カタログ'), function () {
  notImplemented('クロスチェックジョブマップと対象カタログ');
});

When(literal('ファイル形式を確認する'), function () {
  notImplemented('ファイル形式を確認する');
});

Then(literal('slot ジョブマップと同じ CSV 形式である'), function () {
  notImplemented('slot ジョブマップと同じ CSV 形式である');
});
