// tier BDD(③)step definition。tier-facade / uc_id=fd678b04(feature flag を設定する)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/tier-facade.md#ティア完了条件(BDD)
// S2 skeleton の step 文言(feature から転写したリテラル)を完全一致の正規表現で受け、S4 で実装した。
// I/O 境界は実体で検証する: Scenario ごとの一時ディレクトリに ff.env / runner スタブ / ジョブマップを置き、
// bin/validate-config.sh を実プロセスとして起動する(cwd = 一時ディレクトリ。`path: ff.env` は相対パスのまま出る)。
'use strict';
const { Given, When, Then, Before, After } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPT = path.resolve(__dirname, '../../bin/validate-config.sh');

// runner スタブ: --help で runner-if-version=1 を返す(UC「slot runner の実体スクリプトを割り当てる」の runner IF)
const RUNNER_STUB =
  '#!/usr/bin/env bash\n' +
  'if [ "${1:-}" = "--help" ]; then echo "usage: runner-stub.sh"; echo "runner-if-version=1"; exit 0; fi\n' +
  'exit 6\n';

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

Before(function () {
  this.workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-gate-ff-'));
  this.configDir = path.join(this.workDir, 'config');
  fs.mkdirSync(this.configDir);
  this.envPath = path.join(this.workDir, 'ff.env');
  this.env = {};
  this.result = null;
});

After(function () {
  if (this.workDir) {
    fs.rmSync(this.workDir, { recursive: true, force: true });
  }
});

function writeRunner(world, name) {
  const runner = path.join(world.workDir, name);
  fs.writeFileSync(runner, RUNNER_STUB, { mode: 0o755 });
  return runner;
}

function writeJobMap(world, slot) {
  fs.writeFileSync(path.join(world.configDir, `${slot}-job-map.csv`), 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\n');
}

// 有効な並行稼働設定(全 runner スタブは実行可能・--help 応答あり・両ジョブマップあり)
function arrangeParallel(world) {
  world.env = {
    BLUE_MODE: 'foreground',
    GREEN_MODE: 'background',
    RAPID_CROSSCHECK_MODE: 'background',
    BLUE_IMPL: 'blue-2.3.1',
    GREEN_IMPL: 'green-1.4.0',
    BLUE_RUNNER: writeRunner(world, 'blue-runner.sh'),
    GREEN_RUNNER: writeRunner(world, 'green-runner.sh'),
    RAPID_CROSSCHECK_RUNNER: writeRunner(world, 'rapid-crosscheck-runner.sh'),
    RAPID_CROSSCHECK_WORKER: writeRunner(world, 'rapid-crosscheck-worker.sh'),
  };
  writeJobMap(world, 'blue');
  writeJobMap(world, 'green');
}

function flushEnv(world) {
  const body = Object.entries(world.env)
    .map(([key, value]) => `${key}=${value}`)
    .join('\n');
  fs.writeFileSync(world.envPath, body + '\n');
}

function runValidateConfig(world, args) {
  flushEnv(world);
  const proc = spawnSync(SCRIPT, args, {
    cwd: world.workDir,
    encoding: 'utf8',
    env: { ...process.env, RELAY_GATE_CONFIG_DIR: world.configDir },
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  world.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
}

function stdoutLines(world) {
  return world.result.stdout.split('\n').filter((line) => line.length > 0);
}

function assertStderrIncludes(world, expected) {
  assert.ok(
    world.result.stderr.split('\n').includes(expected),
    `stderr should include line "${expected}"\n--- stderr ---\n${world.result.stderr}`,
  );
}

function assertStdoutIncludes(world, expected) {
  assert.ok(stdoutLines(world).includes(expected), `stdout should include line "${expected}"\n--- stdout ---\n${world.result.stdout}`);
}

function assertExit(world, code) {
  assert.equal(world.result.status, code, `exit code\n--- stdout ---\n${world.result.stdout}\n--- stderr ---\n${world.result.stderr}`);
}

// ---- Given ----

Given(
  literal(
    '一時ファイル ff.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=<実行可能な一時スクリプト> GREEN_RUNNER=<実行可能な一時スクリプト> RAPID_CROSSCHECK_RUNNER=<実行可能な一時スクリプト> RAPID_CROSSCHECK_WORKER=<実行可能な一時スクリプト> を書く',
  ),
  function () {
    arrangeParallel(this);
  },
);

Given(literal('両 runner スタブは --help で "runner-if-version=1" を返し、RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある'), function () {
  // arrangeParallel が runner スタブ(--help 応答)と両ジョブマップを配置済み。ここでは実体を確認する
  for (const key of ['BLUE_RUNNER', 'GREEN_RUNNER']) {
    const help = spawnSync(this.env[key], ['--help'], { encoding: 'utf8' });
    assert.equal(help.status, 0);
    assert.ok(help.stdout.includes('runner-if-version=1'));
  }
  assert.ok(fs.existsSync(path.join(this.configDir, 'blue-job-map.csv')));
  assert.ok(fs.existsSync(path.join(this.configDir, 'green-job-map.csv')));
});

Given(literal('ff.env に BLUE_MODE=foreground GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off を書く'), function () {
  this.env = { BLUE_MODE: 'foreground', GREEN_MODE: 'foreground', RAPID_CROSSCHECK_MODE: 'off' };
});

Given(
  literal(
    'ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> を書き BLUE_IMPL / BLUE_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER を書かない',
  ),
  function () {
    this.env = {
      BLUE_MODE: 'off',
      GREEN_MODE: 'foreground',
      RAPID_CROSSCHECK_MODE: 'off',
      GREEN_IMPL: 'green-1.4.0',
      GREEN_RUNNER: writeRunner(this, 'green-runner.sh'),
    };
  },
);

Given(literal('RELAY_GATE_CONFIG_DIR に green-job-map.csv がある(blue-job-map.csv は無くてよい)'), function () {
  writeJobMap(this, 'green');
  assert.ok(!fs.existsSync(path.join(this.configDir, 'blue-job-map.csv')));
});

Given(literal('ff.env に GREEN_MODE=foreground GREEN_IMPL=green-1.4.0 GREEN_RUNNER=/nonexistent/green.sh を書く'), function () {
  this.env = { GREEN_MODE: 'foreground', GREEN_IMPL: 'green-1.4.0', GREEN_RUNNER: '/nonexistent/green.sh' };
});

Given(literal('ff.env に GREEN_MODE=foreground GREEN_RUNNER=<実行可能> を書き GREEN_IMPL を書かない'), function () {
  this.env = { GREEN_MODE: 'foreground', GREEN_RUNNER: writeRunner(this, 'green-runner.sh') };
});

Given(literal('有効な並行稼働設定の RAPID_CROSSCHECK_WORKER を /nonexistent/worker.sh に書き換える'), function () {
  arrangeParallel(this);
  this.env.RAPID_CROSSCHECK_WORKER = '/nonexistent/worker.sh';
});

Given(literal('有効な設定に加えて CONFIG_VERSION=cfg-v1 を書く'), function () {
  arrangeParallel(this);
  this.env.CONFIG_VERSION = 'cfg-v1';
});

// ---- S2 test-scaffold 再実行(spec event 20260917_100000_feedback_impl_feedback_fd678b04_cycle2)で追加 ----
// Scenario「validate-config_sh_feature-flag は FINAL_ で始まるキーを未知キーではなく終了コード 2 で拒否する」。
// 拒否範囲 = キー名が FINAL_ で始まる全キー(接頭辞判定。正本: cli-command-contract.yaml
// config_files.feature-flag.env.validation_rules)。final-crosscheck.env のキー(FINAL_DB_CONN_REF)の誤配置と
// 制御キー(FINAL_CROSSCHECK_MODE)の両方を 1 ファイルに置き、該当キーごとの error 行と warn 不在を確認する。

Given(literal('有効な並行稼働設定に加えて FINAL_DB_CONN_REF=final-db と FINAL_CROSSCHECK_MODE=background を書く'), function () {
  arrangeParallel(this);
  this.env.FINAL_DB_CONN_REF = 'final-db';
  this.env.FINAL_CROSSCHECK_MODE = 'background';
});

Then(
  literal(
    '終了コード 2 で stderr に "error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF" と "error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE" の両方が出る',
  ),
  function () {
    assertExit(this, 2);
    assertStderrIncludes(this, 'error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF');
    assertStderrIncludes(this, 'error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE');
  },
);

// ---- When ----

When(literal('`validate-config.sh --feature-flag ff.env` を実行する'), function () {
  runValidateConfig(this, ['--feature-flag', 'ff.env']);
});

When(literal('`validate-config.sh --feature-flag /nonexistent.env` を実行する'), function () {
  runValidateConfig(this, ['--feature-flag', '/nonexistent.env']);
});

// ---- Then ----

Then(literal('終了コード 0 で stdout は 15 行で、11 行目は "operation_mode=parallel" である'), function () {
  assertExit(this, 0);
  const lines = stdoutLines(this);
  assert.equal(lines.length, 15, `stdout lines\n${this.result.stdout}`);
  assert.equal(lines[10], 'operation_mode=parallel');
});

Then(literal('stdout の 2 行目は "blue_mode=foreground"、4 行目は "blue_impl=blue-2.3.1" である'), function () {
  const lines = stdoutLines(this);
  assert.equal(lines[1], 'blue_mode=foreground');
  assert.equal(lines[3], 'blue_impl=blue-2.3.1');
});

Then(literal('stdout の最終行は "green_runner_if_version=1" である(mode=off の slot なら "-")'), function () {
  const lines = stdoutLines(this);
  const expected = this.env.GREEN_MODE === 'off' ? 'green_runner_if_version=-' : 'green_runner_if_version=1';
  assert.equal(lines[lines.length - 1], expected);
});

Then(literal('stderr に "warn: unknown key" で始まる行は出ない'), function () {
  const warns = this.result.stderr.split('\n').filter((line) => line.startsWith('warn: unknown key'));
  assert.deepEqual(warns, []);
});

Then(literal('終了コード 2 で stderr に "error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground');
});

Then(literal('終了コード 0 で stdout に "blue_impl=-" "blue_runner: -" "rapid_crosscheck_runner: -" と "operation_mode=green_only" が出る'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'blue_impl=-');
  assertStdoutIncludes(this, 'blue_runner: -');
  assertStdoutIncludes(this, 'rapid_crosscheck_runner: -');
  assertStdoutIncludes(this, 'operation_mode=green_only');
});

Then(literal('終了コード 2 で stderr に "error: file not executable key=GREEN_RUNNER path=/nonexistent/green.sh" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: file not executable key=GREEN_RUNNER path=/nonexistent/green.sh');
});

Then(literal('終了コード 2 で stderr に "error: option required option=GREEN_IMPL path: ff.env" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: option required option=GREEN_IMPL path: ff.env');
});

Then(literal('終了コード 2 で stderr に "error: file not executable key=RAPID_CROSSCHECK_WORKER path=/nonexistent/worker.sh" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: file not executable key=RAPID_CROSSCHECK_WORKER path=/nonexistent/worker.sh');
});

Then(literal('終了コード 0 で stderr に "warn: unknown key key=CONFIG_VERSION path: ff.env" が出る'), function () {
  assertExit(this, 0);
  assertStderrIncludes(this, 'warn: unknown key key=CONFIG_VERSION path: ff.env');
});

Then(literal('終了コード 2 で stderr に "error: config file not found path: /nonexistent.env" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: config file not found path: /nonexistent.env');
});
