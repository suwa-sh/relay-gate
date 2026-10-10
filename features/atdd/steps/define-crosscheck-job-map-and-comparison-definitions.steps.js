// ATDD(①)step definition。uc_id=dcd8234d / branch_slug=define-crosscheck-job-map-and-comparison-definitions(S2 skeleton を S7 atdd で実装)。
// source: features/atdd/SPEC-004-04.feature(@atdd_SPEC-004-04-5)
//   対象は uc-map dcd8234d の atdd_scenarios に列挙された 1 Scenario のみ(同 feature の他 Scenario は他 UC の担当)。
// 対応する UC BDD Scenario: spec.md「クロスチェックジョブマップと対象カタログは slot ジョブマップと同じ CSV 形式である(SPEC-004-04)」
// step 文言は feature から転写したリテラルを正規表現で完全一致させる。
// World / Before / After は features/atdd/steps/configure-feature-flags.steps.js が定義済み(同一 require glob で読まれる)。
// ここでは setWorldConstructor を呼ばない(World は 1 つだけ)。
// 3 step とも既存の step ファイル(configure-feature-flags / define-slot-job-maps)に同一文言は無く、ambiguous にならない。
//
// ハーネス設計は features/uc/steps/define-crosscheck-job-map-and-comparison-definitions.steps.js(S6)を踏襲する:
//   Scenario ごとの一時ディレクトリを sandbox root とし、仕様の絶対パス(/etc/relay-gate/*.csv, /opt/compare/*.sh)を
//   root 配下の同じ相対位置に実ファイルで配置する(/etc /opt へは書き込まない)。facade/bin/validate-config.sh を
//   実プロセスとして起動し(facade の handler 登録 hook で rapid-crosscheck / final-crosscheck の検査が source される)、
//   出力中の sandbox root 接頭辞は World.unsandbox で落として判定する。実行時に外部接続(DB・ネットワーク)は行わない。
//   tier 実装は変更しない。ハーネス注入なし(前提の新規抽出もしない)。
// UC 横断 Scenario の扱い: docs/impl/latest/dcd8234d/issues/20261010_084142_cross-uc-scenarios.md(#3。責務は本 UC に閉じる)
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const REPO_ROOT = path.resolve(__dirname, '../../..');
const VALIDATE_CONFIG = path.join(REPO_ROOT, 'facade/bin/validate-config.sh');

// 仕様の例示値(spec.md E2E 完了条件の絶対パス)
const SPEC_MAP = '/etc/relay-gate/crosscheck-job-map.csv';
const SPEC_CATALOG = '/etc/relay-gate/target-catalog.csv';
const SPEC_COMPARE_DIR = '/opt/compare';
const SPEC_COMPARE = '/opt/compare/compare.sh';
const SPEC_COMPARE_V2 = '/opt/compare/compare-v2.sh';

// 列名は spec.md の定義どおり(cli-command-contract の --crosscheck-job-map / --target-catalog の受理ヘッダー)
const MAP_HEADER = 'job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version';
const CATALOG_HEADER = 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling';

// 比較ツールは外部システム(どの UC の成果物でもない)。sandbox に exit 0 の実行可能スタブを置く fixture で足りる。
// 根拠: docs/impl/latest/dcd8234d/issues/20261010_084142_cross-uc-scenarios.md(#1)
const COMPARE_STUB = '#!/usr/bin/env bash\nexit 0\n';

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

// ---- fixture helpers ----

// 行中の仕様の絶対パスを sandbox 配下へ写像する(/data/out/... のような対象識別子は触らない)
function sandboxText(world, text) {
  return text.split('/etc/relay-gate/').join(world.sandbox('/etc/relay-gate') + '/').split(`${SPEC_COMPARE_DIR}/`).join(world.sandbox(SPEC_COMPARE_DIR) + '/');
}

function writeLines(world, specPath, lines) {
  const file = world.sandbox(specPath);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, lines.map((line) => sandboxText(world, line)).join('\n') + '\n');
  return file;
}

function writeCompareStub(world, specPath) {
  const file = world.sandbox(specPath);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, COMPARE_STUB, { mode: 0o755 });
  fs.accessSync(file, fs.constants.X_OK);
}

// slot ジョブマップと同じ CSV 形式の要素を両ファイルに含める:
//   カンマ区切り / 1 行目ヘッダー / 1 行 1 job_id(または 1 対象)/ 二重引用符で囲んだセル(カンマを含む)/
//   セル内の二重引用符を二重化した引用セル(slot ジョブマップの fixed_params と同じ書式)
function crosscheckMapLines() {
  return [
    '# exit_code_contract=0:OK,3:NG,6:ERROR',
    `# target_catalog_path=${SPEC_CATALOG}`,
    '# catalog_version=v1',
    MAP_HEADER,
    `JOB001,job,"output.csv,summary.csv",${SPEC_COMPARE},--blue {blue} --green {green},v1`,
    `JOB002,job,"summary ""v2"",out.csv",${SPEC_COMPARE_V2},--blue {blue} --green {green} --ignore-header,v1`,
  ];
}

function targetCatalogLines() {
  return [
    CATALOG_HEADER,
    'v1,table,SALES_DAILY,"key=sales_id,branch_id",column=business_date',
    'v1,file,/data/out/summary_{business_date}.tsv,"note=""daily"",dash",filename',
  ];
}

// ---- run helpers ----

function runValidateConfig(world, option, specPath) {
  const file = world.sandbox(specPath);
  assert.ok(fs.existsSync(file), `fixture should exist: ${specPath}`);
  const proc = spawnSync(VALIDATE_CONFIG, [option, file], {
    cwd: world.root,
    encoding: 'utf8',
    env: { ...process.env, RELAY_GATE_CONFIG_DIR: world.configDir },
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  return { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
}

// ---- assert helpers ----

function outputDump(result) {
  return `--- stdout ---\n${result.stdout}\n--- stderr ---\n${result.stderr}`;
}

function stdoutLines(world, result) {
  return world.unsandbox(result.stdout).split('\n').filter((line) => line.length > 0);
}

function stderrLines(world, result) {
  return world.unsandbox(result.stderr).split('\n').filter((line) => line.length > 0);
}

function assertValid(world, result, label) {
  assert.equal(result.status, 0, `exit code (${label})\n${outputDump(result)}`);
  assert.ok(stdoutLines(world, result).includes('status=valid'), `stdout should include "status=valid" (${label})\n${outputDump(result)}`);
  const errors = stderrLines(world, result).filter((line) => line.startsWith('error:'));
  assert.deepEqual(errors, [], `stderr should not contain error lines (${label})\n${outputDump(result)}`);
}

// ---- @atdd_SPEC-004-04-5 ----

Given(literal('クロスチェックジョブマップと対象カタログ'), function () {
  writeCompareStub(this, SPEC_COMPARE);
  writeCompareStub(this, SPEC_COMPARE_V2);
  writeLines(this, SPEC_MAP, crosscheckMapLines());
  writeLines(this, SPEC_CATALOG, targetCatalogLines());
  // fixture が「slot ジョブマップと同じ CSV 形式」の要素を実際に含むことを前提として固定する
  for (const specPath of [SPEC_MAP, SPEC_CATALOG]) {
    const body = fs.readFileSync(this.sandbox(specPath), 'utf8');
    const dataLines = body.split('\n').filter((line) => line.length > 0 && !line.startsWith('#'));
    assert.ok(dataLines[0].includes(','), `header must be comma separated: ${specPath}`);
    assert.equal(dataLines.length, 3, `header + 2 rows: ${specPath}`);
    assert.ok(body.includes('""'), `must contain a doubled quote inside a quoted cell: ${specPath}`);
  }
  this.crosscheck = { map: SPEC_MAP, catalog: SPEC_CATALOG, expectedRows: 2 };
});

When(literal('ファイル形式を確認する'), function () {
  // 形式の確認 = 検証コマンドがそのファイルを CSV として読み、ヘッダー・行・セルを受理するかどうか
  assert.ok(this.crosscheck, 'fixtures must be prepared by Given');
  this.crosscheckResults = {
    map: runValidateConfig(this, '--crosscheck-job-map', this.crosscheck.map),
    catalog: runValidateConfig(this, '--target-catalog', this.crosscheck.catalog),
  };
});

Then(literal('slot ジョブマップと同じ CSV 形式である'), function () {
  // 「同じ CSV 形式」= カンマ区切り・1 行目ヘッダー・引用セル(カンマ・二重化した引用符を含む)が
  // slot ジョブマップと同じ解析結果で受理される(status=valid / 終了コード 0)。
  // 引用セルが 1 セルとして解析されなければ列数不一致の違反になり status=valid にならず、行数も 2 にならない。
  for (const key of ['map', 'catalog']) {
    const result = this.crosscheckResults[key];
    assertValid(this, result, key);
    assert.ok(stdoutLines(this, result).includes(`rows=${this.crosscheck.expectedRows}`), `stdout should include "rows=${this.crosscheck.expectedRows}" (${key})\n${outputDump(result)}`);
  }
  assert.ok(stdoutLines(this, this.crosscheckResults.map).includes('config=crosscheck-job-map'), outputDump(this.crosscheckResults.map));
  assert.ok(stdoutLines(this, this.crosscheckResults.catalog).includes('config=target-catalog'), outputDump(this.crosscheckResults.catalog));
});
