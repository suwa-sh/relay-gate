// tier BDD(③)step definition skeleton。tier-final-crosscheck / uc_id=dcd8234d(クロスチェックのジョブマップと比較定義を定義する)。S2 test-scaffold 生成。S4 tier-impl で実装する。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-final-crosscheck.md#ティア完了条件(BDD)
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

Given(literal('/etc/relay-gate/target-catalog.csv がヘッダー + `v1,table,SALES_DAILY,key=sales_id,column=business_date` + `v1,file,/data/out/summary_{business_date}.tsv,-,filename` の 2 行である'), function () {
  notImplemented('/etc/relay-gate/target-catalog.csv がヘッダー + `v1,table,SALES_DAILY,key=sales_id,column=business_date` + `v1,file,/data/out/summary_{business_date}.tsv,-,filename` の 2 行である');
});

Given(literal('上記に `v2,table,SALES_DAILY,key=sales_id,column=business_date` を追加する'), function () {
  notImplemented('上記に `v2,table,SALES_DAILY,key=sales_id,column=business_date` を追加する');
});

Given(literal('3 行目の target_type が `view` である'), function () {
  notImplemented('3 行目の target_type が `view` である');
});

Given(literal('妥当な対象カタログの 3 行目を `v1,table,SALES_DAILY,key=sales_id,column=business_date` に置き換え、2 行目と 3 行目が `v1,table,SALES_DAILY` で始まる'), function () {
  notImplemented('妥当な対象カタログの 3 行目を `v1,table,SALES_DAILY,key=sales_id,column=business_date` に置き換え、2 行目と 3 行目が `v1,table,SALES_DAILY` で始まる');
});

// ---- When ----

When(literal('`validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する'), function () {
  notImplemented('`validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する');
});

// ---- Then ----

Then(literal('終了コード 0 で stdout に `rows=2`、`catalog_versions=v1`、`tables=1`、`files=1`、`status=valid` が出る'), function () {
  notImplemented('終了コード 0 で stdout に `rows=2`、`catalog_versions=v1`、`tables=1`、`files=1`、`status=valid` が出る');
});

Then(literal('終了コード 0 で stdout に `catalog_versions=v1,v2` が出る'), function () {
  notImplemented('終了コード 0 で stdout に `catalog_versions=v1,v2` が出る');
});

Then(literal('終了コード 2 で stderr に `error: target_type is not in table,file line=3 value=view` が出る'), function () {
  notImplemented('終了コード 2 で stderr に `error: target_type is not in table,file line=3 value=view` が出る');
});

Then(literal('終了コード 2 で stderr に `error: duplicate target catalog_version=v1 target_type=table target_identifier=SALES_DAILY lines=2,3` が出る(初出行 2 を含む)'), function () {
  notImplemented('終了コード 2 で stderr に `error: duplicate target catalog_version=v1 target_type=table target_identifier=SALES_DAILY lines=2,3` が出る(初出行 2 を含む)');
});
