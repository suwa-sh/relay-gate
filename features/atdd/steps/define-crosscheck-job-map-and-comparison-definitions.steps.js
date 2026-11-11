// ATDD(①)step definition。uc_id=dcd8234d / branch_slug=define-crosscheck-job-map-and-comparison-definitions(S7 atdd で実装)。
// source: features/atdd/SPEC-004-04.feature(@atdd_SPEC-004-04-5 / @atdd_SPEC-004-04-6 / @atdd_SPEC-004-04-7 / @atdd_SPEC-004-04-8 / @atdd_SPEC-004-04-10 / @atdd_SPEC-004-04-11 / @atdd_SPEC-004-04-12)
//   対象は uc-map dcd8234d の atdd_scenarios に列挙された 7 Scenario のみ。同 feature の -1〜-4 は UC eff24f55、
//   -9(確報の起動コマンド)は別 UC の担当で、ここでは定義しない。
// step 文言は feature から転写したリテラルを正規表現で完全一致させる(S2 skeleton の方式を踏襲)。
//
// ハーネス設計は features/uc/steps/define-crosscheck-job-map-and-comparison-definitions.steps.js(S6)を踏襲する:
//   World / Before / After は features/atdd/steps/configure-feature-flags.steps.js が定義済み(World は 1 つだけ)。
//   Scenario ごとの一時ディレクトリ(this.root)を sandbox root とし、仕様の例示パス(/etc/relay-gate/rapid-crosscheck.env,
//   /opt/compare/*.sh)を root 配下の同じ相対位置に実ファイルで置く(/etc /opt へは書き込まない)。
//   起動コマンドのコマンド部分は絶対パスのときだけ root 配下へ写像し、相対パスと引数部分は書き換えない。
// 1 つの受け入れ基準を複数の入力(ケース)で確かめる Scenario があるため、Given がケースを積み、When が全ケースを実行する。
// 実行時に外部接続(DB・ネットワーク)は行わない。tier 実装は変更しない。
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const REPO_ROOT = path.resolve(__dirname, '../../..');
const VALIDATE_CONFIG = path.join(REPO_ROOT, 'facade/bin/validate-config.sh');

const SPEC_RAPID_ENV_PATH = '/etc/relay-gate/rapid-crosscheck.env';
const SPEC_COMPARE = '/opt/compare/compare.sh';
const KEY = 'RAPID_COMPARE_COMMAND';

// 廃止されたクロスチェックジョブマップ CSV / 対象カタログ CSV を指す名前(ファイル名・検証種別オプションの両方で探す)
const ABOLISHED_FILE_PATTERN = /(crosscheck[-_]?job[-_]?map|target[-_]?catalog|comparison[-_]?definition|catalog)/i;
const ABOLISHED_OPTIONS = ['--crosscheck-job-map', '--target-catalog', '--catalog'];

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

function writeFile(file, body, mode) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, body, { mode });
  fs.chmodSync(file, mode);
}

function writeCompareStub(world, specPath, mode = 0o755) {
  writeFile(world.sandbox(specPath), '#!/usr/bin/env bash\nexit 0\n', mode);
}

function sandboxCommand(world, command) {
  const match = /^(\S+)(.*)$/s.exec(command);
  if (!match || !match[1].startsWith('/')) {
    return command;
  }
  return world.sandbox(match[1]) + match[2];
}

// ケースごとに別の env ファイルを置く(同じ Scenario 内の他ケースと干渉させない)
function addCase(world, label, command) {
  world.cases = world.cases || [];
  const specPath = world.cases.length === 0 ? SPEC_RAPID_ENV_PATH : `/etc/relay-gate/case-${world.cases.length}/rapid-crosscheck.env`;
  const file = world.sandbox(specPath);
  writeFile(file, `RAPID_DB_CONN_REF=rapid_db\n${KEY}=${sandboxCommand(world, command)}\n`, 0o644);
  world.cases.push({ label, command, file });
}

function runCase(world, c) {
  const proc = spawnSync(VALIDATE_CONFIG, ['--rapid-crosscheck', c.file], {
    cwd: world.root,
    encoding: 'utf8',
    env: { ...process.env, RELAY_GATE_CONFIG_DIR: world.sandbox('/etc/relay-gate') },
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  c.result = { status: proc.status, stdout: world.unsandbox(proc.stdout), stderr: world.unsandbox(proc.stderr) };
}

function runAllCases(world) {
  assert.ok(world.cases && world.cases.length > 0, 'Given should prepare at least one case');
  world.cases.forEach((c) => runCase(world, c));
}

function errorLines(c) {
  return c.result.stderr.split('\n').filter((line) => line.startsWith('error:'));
}

function describe(c) {
  return `[${c.label}] command=${c.command}\nexit=${c.result.status}\nstdout:\n${c.result.stdout}\nstderr:\n${c.result.stderr}`;
}

// 非 0 で終了し、error 行がちょうど 1 行で、その行が想定の違反・キー名・値を含む
function assertSingleViolation(world, { reason, field }) {
  for (const c of world.cases) {
    assert.notEqual(c.result.status, 0, `exit code should be non-zero\n${describe(c)}`);
    const errors = errorLines(c);
    assert.equal(errors.length, 1, `exactly one error line expected\n${describe(c)}`);
    const line = errors[0];
    assert.ok(line.includes(reason), `error line should state "${reason}"\n${describe(c)}`);
    assert.ok(line.includes(`key=${KEY}`), `error line should include key=${KEY}\n${describe(c)}`);
    assert.ok(line.includes(field(c)), `error line should include "${field(c)}"\n${describe(c)}`);
  }
}

function firstWord(command) {
  return command.split(/\s+/)[0];
}

// --- @atdd_SPEC-004-04-5 ---

Given(literal('速報の起動コマンドのコマンド部分(先頭の語)が絶対パスで、存在し、実行可能で、文字列に {job_id} を含む'), function () {
  writeCompareStub(this, SPEC_COMPARE);
  addCase(this, 'valid', `${SPEC_COMPARE} --job {job_id} --run {run_id}`);
});

When(literal('validate-config.sh で速報の起動コマンドの設定を検証する'), function () {
  runAllCases(this);
});

Then(literal('終了コード 0 で終了し、stderr に error 行が出ない'), function () {
  for (const c of this.cases) {
    assert.equal(c.result.status, 0, `exit code\n${describe(c)}`);
    assert.deepEqual(errorLines(c), [], `no error line expected\n${describe(c)}`);
  }
});

// --- @atdd_SPEC-004-04-6 / -7 / -8 / -10 共通の When ---

When(literal('validate-config.sh で検証する'), function () {
  runAllCases(this);
});

// --- @atdd_SPEC-004-04-6 ---

Given(literal('起動コマンドのコマンド部分が絶対パスでない'), function () {
  // 他の違反を混ぜない(相対パス以外は満たす): {job_id} を含める
  addCase(this, 'bare name', 'compare.sh --job {job_id}');
  addCase(this, 'relative path', 'opt/compare/compare.sh --job {job_id}');
});

Then(literal('非 0 の終了コードで終了し、stderr に絶対パスでない旨の error 行がキー名とパスつきで 1 行出る'), function () {
  assertSingleViolation(this, { reason: 'path is not absolute', field: (c) => `path=${firstWord(c.command)}` });
});

// --- @atdd_SPEC-004-04-7 ---

Given(literal('起動コマンドのコマンド部分のファイルが存在しない、または実行可能でない'), function () {
  addCase(this, 'missing', '/opt/compare/missing.sh --job {job_id}');
  writeCompareStub(this, '/opt/compare/not-executable.sh', 0o644);
  addCase(this, 'not executable', '/opt/compare/not-executable.sh --job {job_id}');
});

Then(literal('非 0 の終了コードで終了し、stderr に実行可能でない旨の error 行がキー名とパスつきで 1 行出る'), function () {
  assertSingleViolation(this, { reason: 'file not executable', field: (c) => `path=${firstWord(c.command)}` });
});

// --- @atdd_SPEC-004-04-8 ---

Given(literal('速報の起動コマンドに {job_id} が含まれない'), function () {
  writeCompareStub(this, SPEC_COMPARE);
  addCase(this, 'no placeholder', SPEC_COMPARE);
  addCase(this, 'other placeholder only', `${SPEC_COMPARE} --run {run_id}`);
});

Then(literal('非 0 の終了コードで終了し、stderr に {job_id} が無い旨の error 行がキー名と値つきで 1 行出る'), function () {
  assertSingleViolation(this, { reason: 'placeholder {job_id} is missing', field: (c) => `value=${c.command}` });
});

// --- @atdd_SPEC-004-04-10 ---
// USDM SPEC-004-04 の検証は 3 点((1) コマンド部分 / (2) {job_id} / (3) {params} の位置)で、spec・CLI 契約と一致している
// (feedback run 2〜9 で USDM に (3) が加わり、旧 issue 20261027_083600_params-rule-vs-usdm-two-checks.md の食い違いは解消した)。
// この基準の Given は「{params} を引数の一部に含まない任意の文字列で、速報の場合は {job_id} を含む」なので、
// fixture は {params} を引数の一部に含めない。{params} が引数 1 つ全体の場合は位置規則に合うため任意の文字列に含める。
// {params} を引数の一部に含む場合(違反)は @atdd_SPEC-004-04-12 が扱う。

const ARBITRARY_ARGUMENTS = [
  '',
  '/no/such/path/input.csv',
  'relative/missing-dir unknown-word',
  '--unknown-flag=1 -zz',
  '"quoted words" \'single\' ; | & * ? $HOME $(whoami) `id`',
  '{run_id} {blue_exit_code} {green_exit_code} {unknown_placeholder}',
  '{params}',
];

Given(literal('起動コマンドの引数部分が、{params} を引数の一部に含まない任意の文字列(存在しないパスや未知の語を含む)で、速報の起動コマンドの場合は {job_id} を含む'), function () {
  writeCompareStub(this, SPEC_COMPARE);
  this.argumentGroups = [];
  // コマンド部分が妥当なとき(終了コード 0)と、コマンド部分が絶対パスでないとき(非 0)の両方で、
  // 引数部分を変えても終了コードと error 行が変わらないことを見る
  for (const [group, head] of [
    ['valid command part', SPEC_COMPARE],
    ['non-absolute command part', 'compare.sh'],
  ]) {
    const start = (this.cases || []).length;
    for (const args of ARBITRARY_ARGUMENTS) {
      addCase(this, `${group} args=${JSON.stringify(args)}`, `${head} --job {job_id}${args === '' ? '' : ' ' + args}`);
    }
    this.argumentGroups.push({ group, start, end: start + ARBITRARY_ARGUMENTS.length });
  }
});

Then(literal('引数部分を理由とする error 行は出ず、終了コードは引数部分の内容に影響されない'), function () {
  for (const { group, start, end } of this.argumentGroups) {
    const cases = this.cases.slice(start, end);
    const baseline = cases[0];
    for (const c of cases) {
      assert.equal(c.result.status, baseline.result.status, `exit code should not depend on arguments (${group})\n${describe(c)}`);
      assert.deepEqual(errorLines(c), errorLines(baseline), `error lines should not depend on arguments (${group})\n${describe(c)}`);
    }
    if (group === 'valid command part') {
      assert.equal(baseline.result.status, 0, `valid command part should pass\n${describe(baseline)}`);
      cases.forEach((c) => assert.deepEqual(errorLines(c), [], `no error line expected\n${describe(c)}`));
    }
  }
});

// --- @atdd_SPEC-004-04-12 ---
// When は @atdd_SPEC-004-04-5 の「validate-config.sh で速報の起動コマンドの設定を検証する」を共有する

Given(literal('速報の起動コマンドの引数の一部に {params} を含む(--args={params})'), function () {
  // 他の違反を混ぜない(コマンド部分は実行可能、{job_id} を含む)
  writeCompareStub(this, SPEC_COMPARE);
  addCase(this, 'params with prefix', `${SPEC_COMPARE} --job {job_id} --args={params}`);
});

Then(literal('非 0 の終了コードで終了し、stderr に {params} が引数全体でない旨の error 行がキー名と値つきで 1 行出る'), function () {
  assertSingleViolation(this, { reason: 'placeholder {params} must be a whole argument', field: (c) => `value=${c.command}` });
});

// --- @atdd_SPEC-004-04-11 ---

Given(literal('relay-gate の設定ファイル置き場'), function () {
  // relay-gate が配布する設定ファイル置き場(各 tier の config/)と、設定ファイル置き場の既定(RELAY_GATE_CONFIG_DIR)
  this.configDirs = fs
    .readdirSync(REPO_ROOT, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith('.') && entry.name !== 'node_modules')
    .map((entry) => path.join(REPO_ROOT, entry.name, 'config'))
    .filter((dir) => fs.existsSync(dir));
  assert.ok(this.configDirs.length > 0, 'at least one distributed config dir should exist');
});

When(literal('クロスチェックジョブマップ CSV や対象カタログ CSV を探す'), function () {
  const walk = (dir) =>
    fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
      const full = path.join(dir, entry.name);
      return entry.isDirectory() ? walk(full) : [full];
    });
  this.foundFiles = this.configDirs.flatMap(walk).filter((file) => ABOLISHED_FILE_PATTERN.test(path.basename(file)));
  const help = spawnSync(VALIDATE_CONFIG, ['--help'], { encoding: 'utf8' });
  assert.equal(help.status, 0, `--help exit code\n${help.stderr}`);
  this.helpText = help.stdout;
  this.optionResults = ABOLISHED_OPTIONS.map((option) => {
    const proc = spawnSync(VALIDATE_CONFIG, [option, path.join(this.root, 'x.csv')], { encoding: 'utf8' });
    return { option, status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
  });
});

Then(literal('存在せず、validate-config.sh にそれらを検証する種別も無い'), function () {
  assert.deepEqual(this.foundFiles, [], 'no crosscheck job map / target catalog file should exist in config dirs');
  for (const option of ABOLISHED_OPTIONS) {
    assert.ok(!this.helpText.includes(option), `--help should not list ${option}`);
  }
  assert.ok(!ABOLISHED_FILE_PATTERN.test(this.helpText), `--help should not mention crosscheck job map / catalog\n${this.helpText}`);
  for (const r of this.optionResults) {
    assert.equal(r.status, 2, `${r.option} should be rejected as unknown option\n${r.stderr}`);
    assert.ok(r.stderr.includes(`error: unknown option option=${r.option}`), `${r.option} should be unknown\n${r.stderr}`);
  }
});
