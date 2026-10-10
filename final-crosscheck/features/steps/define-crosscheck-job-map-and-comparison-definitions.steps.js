// tier BDD(③)step definition。tier-final-crosscheck / uc_id=dcd8234d(クロスチェックのジョブマップと比較定義を定義する)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-final-crosscheck.md#ティア完了条件(BDD)
// S2 skeleton の step 文言(feature から転写したリテラル)を完全一致の正規表現で受け、S4 で実装した。
// I/O 境界は実体で検証する: Scenario ごとの一時ディレクトリに target-catalog.csv を置き(feature の /etc/relay-gate/ は
// 一時ディレクトリに読み替える。validate-config.sh は引数のパスをそのまま使い既定パスで補完しないため、置き場所は結果に影響しない)、
// tier-facade のエントリポイント facade/bin/validate-config.sh を実プロセスとして起動する(本 tier の handler を source して委譲する。
// 登録の所在は docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md)。
// 本 tier には先行 UC の step ファイルが無いため、Before / After(一時ディレクトリ)は本ファイルが持つ。
'use strict';
const { Given, When, Then, Before, After } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPT = path.resolve(__dirname, '../../../facade/bin/validate-config.sh');
const CATALOG_NAME = 'target-catalog.csv';
const HEADER = 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling';
const ROW_TABLE_V1 = 'v1,table,SALES_DAILY,key=sales_id,column=business_date';
const ROW_FILE_V1 = 'v1,file,/data/out/summary_{business_date}.tsv,-,filename';
const ROW_TABLE_V2 = 'v2,table,SALES_DAILY,key=sales_id,column=business_date';

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

Before(function () {
  this.workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-gate-final-'));
  this.catalogPath = path.join(this.workDir, CATALOG_NAME);
  this.result = null;
});

After(function () {
  if (this.workDir) {
    fs.rmSync(this.workDir, { recursive: true, force: true });
  }
});

// Arrange: 妥当な対象カタログ(ヘッダー + table 行 + file 行)。各 Scenario はここから差分を加える
function writeCatalog(world, lines) {
  fs.writeFileSync(world.catalogPath, lines.join('\n') + '\n');
}

// stdout の行の中から、期待する行が期待する順で現れることを確かめる
function assertLinesInOrder(output, expected) {
  const lines = output.split('\n');
  let cursor = 0;
  for (const line of expected) {
    const found = lines.indexOf(line, cursor);
    assert.notEqual(found, -1, `expected line not found in order: ${line}\n--- output ---\n${output}`);
    cursor = found + 1;
  }
}

// ---- Given ----

Given(literal('/etc/relay-gate/target-catalog.csv がヘッダー + `v1,table,SALES_DAILY,key=sales_id,column=business_date` + `v1,file,/data/out/summary_{business_date}.tsv,-,filename` の 2 行である'), function () {
  writeCatalog(this, [HEADER, ROW_TABLE_V1, ROW_FILE_V1]);
});

Given(literal('上記に `v2,table,SALES_DAILY,key=sales_id,column=business_date` を追加する'), function () {
  // 「上記」= 妥当な対象カタログ(ヘッダー + 2 行)。Scenario は独立しているため、ここで 2 行 + 追加行を書く
  writeCatalog(this, [HEADER, ROW_TABLE_V1, ROW_FILE_V1, ROW_TABLE_V2]);
});

Given(literal('3 行目の target_type が `view` である'), function () {
  // 妥当な対象カタログの 3 行目(file 行)の target_type を view に変える(物理行 3)
  writeCatalog(this, [HEADER, ROW_TABLE_V1, ROW_FILE_V1.replace('v1,file,', 'v1,view,')]);
});

Given(literal('妥当な対象カタログの 3 行目を `v1,table,SALES_DAILY,key=sales_id,column=business_date` に置き換え、2 行目と 3 行目が `v1,table,SALES_DAILY` で始まる'), function () {
  writeCatalog(this, [HEADER, ROW_TABLE_V1, ROW_TABLE_V1]);
});

// ---- When ----

When(literal('`validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する'), function () {
  const proc = spawnSync(SCRIPT, ['--target-catalog', this.catalogPath], { cwd: this.workDir, encoding: 'utf8' });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  this.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
});

// ---- Then ----

Then(literal('終了コード 0 で stdout に `rows=2`、`catalog_versions=v1`、`tables=1`、`files=1`、`status=valid` が出る'), function () {
  assert.equal(this.result.status, 0, `stderr: ${this.result.stderr}`);
  assertLinesInOrder(this.result.stdout, ['rows=2', 'catalog_versions=v1', 'tables=1', 'files=1', 'status=valid']);
});

Then(literal('終了コード 0 で stdout に `catalog_versions=v1,v2` が出る'), function () {
  assert.equal(this.result.status, 0, `stderr: ${this.result.stderr}`);
  assertLinesInOrder(this.result.stdout, ['catalog_versions=v1,v2']);
});

Then(literal('終了コード 2 で stderr に `error: target_type is not in table,file line=3 value=view` が出る'), function () {
  assert.equal(this.result.status, 2, `stdout: ${this.result.stdout}\nstderr: ${this.result.stderr}`);
  assert.ok(this.result.stderr.split('\n').includes('error: target_type is not in table,file line=3 value=view'), `stderr: ${this.result.stderr}`);
});

Then(literal('終了コード 2 で stderr に `error: duplicate target catalog_version=v1 target_type=table target_identifier=SALES_DAILY lines=2,3` が出る(初出行 2 を含む)'), function () {
  assert.equal(this.result.status, 2, `stdout: ${this.result.stdout}\nstderr: ${this.result.stderr}`);
  assert.ok(
    this.result.stderr.split('\n').includes('error: duplicate target catalog_version=v1 target_type=table target_identifier=SALES_DAILY lines=2,3'),
    `stderr: ${this.result.stderr}`
  );
});
