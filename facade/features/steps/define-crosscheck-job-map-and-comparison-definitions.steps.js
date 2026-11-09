// tier BDD(③)step definition。tier-facade / uc_id=dcd8234d(クロスチェックのジョブマップと比較定義を定義する)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-facade.md#ティア完了条件(BDD)
// S2 skeleton の step 文言(feature から転写したリテラル)を完全一致の正規表現で受け、S4 で実装した。
// I/O 境界は実体で検証する: Scenario ごとの一時ディレクトリ(this.workDir。Before / After は
// configure-feature-flags.steps.js が定義済み)に rapid-crosscheck.env と比較ツールのスタブを置き、
// bin/validate-config.sh を実プロセスとして起動する。
// feature のパス /opt/compare/ はホストに作れないため、一時ディレクトリ配下の同名ディレクトリへ読み替える
// (env の値と期待する出力の両方を同じ規則で読み替える)。
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPT = path.resolve(__dirname, '../../bin/validate-config.sh');
const FEATURE_COMPARE_DIR = '/opt/compare/';
const COMPARE_STUB = '#!/usr/bin/env bash\nexit 0\n';

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

function compareDir(world) {
  return path.join(world.workDir, 'opt', 'compare') + path.sep;
}

// feature 上の /opt/compare/ を一時ディレクトリ配下へ読み替える
function localize(world, text) {
  return text.split(FEATURE_COMPARE_DIR).join(compareDir(world));
}

function arrangeCommand(world, command, executable) {
  fs.mkdirSync(compareDir(world), { recursive: true });
  if (executable) {
    fs.writeFileSync(path.join(compareDir(world), executable), COMPARE_STUB, { mode: 0o755 });
  }
  world.rapidEnvPath = path.join(world.workDir, 'rapid-crosscheck.env');
  fs.writeFileSync(world.rapidEnvPath, `RAPID_DB_CONN_REF=rapid_db\nRAPID_COMPARE_COMMAND=${localize(world, command)}\n`);
}

function stdoutLines(world) {
  return world.result.stdout.split('\n').filter((line) => line.length > 0);
}

function assertExit(world, code) {
  assert.equal(world.result.status, code, `exit code\n--- stdout ---\n${world.result.stdout}\n--- stderr ---\n${world.result.stderr}`);
}

function assertStdoutIncludes(world, expected) {
  const line = localize(world, expected);
  assert.ok(stdoutLines(world).includes(line), `stdout should include line "${line}"\n--- stdout ---\n${world.result.stdout}`);
}

function assertStderrIncludes(world, expected) {
  const line = localize(world, expected);
  assert.ok(world.result.stderr.split('\n').includes(line), `stderr should include line "${line}"\n--- stderr ---\n${world.result.stderr}`);
}

// ---- Given ----

Given(literal('RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} で /opt/compare/compare.sh が実行可能'), function () {
  arrangeCommand(this, '/opt/compare/compare.sh --job {job_id}', 'compare.sh');
});

Given(literal('RAPID_COMPARE_COMMAND=/opt/compare/missing.sh --job {job_id} でコマンド部分が存在しない'), function () {
  arrangeCommand(this, '/opt/compare/missing.sh --job {job_id}', null);
});

Given(literal('RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --run {run_id} で {job_id} を含まない'), function () {
  arrangeCommand(this, '/opt/compare/compare.sh --run {run_id}', 'compare.sh');
});

Given(literal('RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} --args={params} で {params} が引数の一部になっている'), function () {
  arrangeCommand(this, '/opt/compare/compare.sh --job {job_id} --args={params}', 'compare.sh');
});

Given(literal('RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} {params} で /opt/compare/compare.sh が実行可能'), function () {
  arrangeCommand(this, '/opt/compare/compare.sh --job {job_id} {params}', 'compare.sh');
});

// ---- When ----

When(literal('validate-config.sh --rapid-crosscheck <path> を実行する'), function () {
  const proc = spawnSync(SCRIPT, ['--rapid-crosscheck', this.rapidEnvPath], {
    cwd: this.workDir,
    encoding: 'utf8',
    env: { ...process.env, RELAY_GATE_CONFIG_DIR: this.configDir },
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  this.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
});

// ---- Then ----

Then(literal('終了コード 0 で stdout に status=valid、command_path: /opt/compare/compare.sh、has_job_id_placeholder=true が出る'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'status=valid');
  assertStdoutIncludes(this, 'command_path: /opt/compare/compare.sh');
  assertStdoutIncludes(this, 'has_job_id_placeholder=true');
});

Then(literal('終了コード 2 で stderr に `error: file not executable key=RAPID_COMPARE_COMMAND path=/opt/compare/missing.sh` が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: file not executable key=RAPID_COMPARE_COMMAND path=/opt/compare/missing.sh');
});

Then(
  literal(
    '終了コード 2 で stderr に `error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --run {run_id}` が出る',
  ),
  function () {
    assertExit(this, 2);
    assertStderrIncludes(this, 'error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --run {run_id}');
  },
);

Then(
  literal(
    '終了コード 2 で stderr に `error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --job {job_id} --args={params}` が出る',
  ),
  function () {
    assertExit(this, 2);
    assertStderrIncludes(
      this,
      'error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --job {job_id} --args={params}',
    );
  },
);

Then(literal('終了コード 0 で stdout に status=valid が出る'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'status=valid');
});
