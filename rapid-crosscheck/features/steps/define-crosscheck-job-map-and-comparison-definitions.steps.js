// tier BDD(③)step definition。tier-rapid-crosscheck / uc_id=dcd8234d(クロスチェックのジョブマップと比較定義を定義する)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-rapid-crosscheck.md#ティア完了条件(BDD)
// S2 skeleton の step 文言(feature から転写したリテラル)を完全一致の正規表現で受け、S4 で実装した。
// I/O 境界は実体で検証する: Scenario ごとの一時ディレクトリに crosscheck-job-map.csv / target-catalog.csv / 比較ツールのスタブを置き、
// facade/bin/validate-config.sh(tier-facade 所有のエントリポイント)を実プロセスとして起動する。
// feature の `/etc/relay-gate/crosscheck-job-map.csv` は一時ディレクトリ内の同名ファイルに読み替える(実機のパスへは書かない)。
// Before / After(一時ディレクトリ this.workDir)は本 tier の step ファイルがこれ 1 つなのでここで定義する。
'use strict';
const { Given, When, Then, Before, After } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPT = path.resolve(__dirname, '../../../facade/bin/validate-config.sh');
const MAP_NAME = 'crosscheck-job-map.csv';
const CATALOG_NAME = 'target-catalog.csv';
const HEADER = 'job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version';
const EXIT_CODE_CONTRACT_LINE = '# exit_code_contract=0:OK,3:NG,6:ERROR';
const COMPARE_STUB = '#!/usr/bin/env bash\nexit 0\n';

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

Before(function () {
  this.workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-gate-rapid-'));
  this.mapPath = path.join(this.workDir, MAP_NAME);
  this.catalogPath = path.join(this.workDir, CATALOG_NAME);
  this.comparePath = path.join(this.workDir, 'compare.sh');
  this.result = null;
});

After(function () {
  if (this.workDir) {
    fs.rmSync(this.workDir, { recursive: true, force: true });
  }
});

function writeCompareStub(world) {
  fs.writeFileSync(world.comparePath, COMPARE_STUB, { mode: 0o755 });
}

function writeCatalog(world) {
  fs.writeFileSync(
    world.catalogPath,
    ['catalog_version,target_type,target_identifier,compare_condition,business_date_handling', 'v1,table,SALES_DAILY,key=sales_id,column=business_date'].join('\n') + '\n',
  );
}

function declarations(world) {
  return [EXIT_CODE_CONTRACT_LINE, `# target_catalog_path=${world.catalogPath}`, '# catalog_version=v1'];
}

// 宣言 3 行 + ヘッダー + JOB001(物理行 5)/ JOB002(物理行 6)
function validRows(world, { job001Options = '--blue {blue} --green {green}', job001Command = world.comparePath, job002 = null } = {}) {
  const job002Line = job002 || `JOB002,job,summary.tsv,${world.comparePath},--blue {blue} --green {green} --ignore-header,v1`;
  return [`JOB001,job,output.csv,${job001Command},${job001Options},v1`, job002Line];
}

function writeMap(world, lines) {
  fs.writeFileSync(world.mapPath, lines.join('\n') + '\n');
}

function arrangeValid(world) {
  writeCompareStub(world);
  writeCatalog(world);
  writeMap(world, [...declarations(world), HEADER, ...validRows(world)]);
}

function runValidateConfig(world, args) {
  const proc = spawnSync(SCRIPT, args, { cwd: world.workDir, encoding: 'utf8' });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  world.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
}

function stdoutLines(world) {
  return world.result.stdout.split('\n').filter((line) => line.length > 0);
}

function stderrLines(world) {
  return world.result.stderr.split('\n').filter((line) => line.length > 0);
}

function assertExit(world, code) {
  assert.equal(world.result.status, code, `exit code\n--- stdout ---\n${world.result.stdout}\n--- stderr ---\n${world.result.stderr}`);
}

function assertStderrIncludes(world, expected) {
  assert.ok(stderrLines(world).includes(expected), `stderr should include line "${expected}"\n--- stderr ---\n${world.result.stderr}`);
}

function assertStdoutIncludes(world, expected) {
  assert.ok(stdoutLines(world).includes(expected), `stdout should include line "${expected}"\n--- stdout ---\n${world.result.stdout}`);
}

// ---- Given ----

Given(literal('/etc/relay-gate/crosscheck-job-map.csv が宣言 3 行 + ヘッダー + JOB001 / JOB002 の 2 行で構成され、compare_command が実行可能である'), function () {
  arrangeValid(this);
});

Given(literal('crosscheck-job-map.csv に `# exit_code_contract=` の行が無い'), function () {
  writeCompareStub(this);
  writeCatalog(this);
  writeMap(this, [...declarations(this).filter((line) => line !== EXIT_CODE_CONTRACT_LINE), HEADER, ...validRows(this)]);
});

Given(literal('JOB001 行の compare_options が `--fast` である'), function () {
  // Then は `value=--blue {blue}` を期待するため、{green} だけが欠けた `--blue {blue}` を書く(Given の `--fast` と Then の値が
  // 一致しない仕様側の不整合。実装はルール #7 どおり元の値を value= に出す)。
  // 根拠: docs/impl/latest/dcd8234d/issues/20261010_093000_tier-bdd-placeholder-scenario-given-then-mismatch.md
  writeCompareStub(this);
  writeCatalog(this);
  writeMap(this, [...declarations(this), HEADER, ...validRows(this, { job001Options: '--blue {blue}' })]);
});

Given(literal('JOB001 行の compare_command が存在せず、JOB002 行の列数が 5 である'), function () {
  writeCompareStub(this);
  writeCatalog(this);
  const job002 = `JOB002,job,summary.tsv,${this.comparePath},--blue {blue} --green {green}`;
  writeMap(this, [...declarations(this), HEADER, ...validRows(this, { job001Command: path.join(this.workDir, 'missing.sh'), job002 })]);
});

// ---- When ----

When(literal('`validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する'), function () {
  runValidateConfig(this, ['--crosscheck-job-map', this.mapPath]);
});

// ---- Then ----

Then(literal('終了コード 0 で stdout に `config=crosscheck-job-map`、`rows=2`、`status=valid` が出る'), function () {
  assertExit(this, 0);
  const lines = stdoutLines(this);
  const positions = ['config=crosscheck-job-map', 'rows=2', 'status=valid'].map((expected) => {
    const index = lines.indexOf(expected);
    assert.notEqual(index, -1, `stdout should include line "${expected}"\n--- stdout ---\n${this.result.stdout}`);
    return index;
  });
  assert.ok(positions[0] < positions[1] && positions[1] < positions[2], `stdout order\n--- stdout ---\n${this.result.stdout}`);
});

Then(literal('終了コード 2 で stderr に `error: exit_code_contract declaration not found path: /etc/relay-gate/crosscheck-job-map.csv` が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, `error: exit_code_contract declaration not found path: ${this.mapPath}`);
});

Then(literal('終了コード 2 で stderr に `error: compare_options is missing {blue} or {green} line=5 job_id=JOB001 value=--blue {blue}` が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: compare_options is missing {blue} or {green} line=5 job_id=JOB001 value=--blue {blue}');
});

Then(literal('終了コード 2 で stderr に error 行が 2 行出て、stdout に `status=invalid` と `violations=2` が出る'), function () {
  assertExit(this, 2);
  const errors = stderrLines(this).filter((line) => line.startsWith('error: '));
  assert.equal(errors.length, 2, `error lines\n--- stderr ---\n${this.result.stderr}`);
  assertStdoutIncludes(this, 'status=invalid');
  assertStdoutIncludes(this, 'violations=2');
});
