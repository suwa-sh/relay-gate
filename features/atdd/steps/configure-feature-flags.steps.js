// ATDD(①)step definition。uc_id=fd678b04 / branch_slug=configure-feature-flags(S7 atdd で実装)。
// source: features/atdd/SPEC-001-01.feature(@atdd_SPEC-001-01-4 のみ。uc-map fd678b04 の atdd_scenarios)
// 対応する UC BDD Scenario: spec.md「元資料の 9 キーの feature flag は未知キー警告なしで検証を通過する(SPEC-001-01)」
// step 文言は feature から転写したリテラルを正規表現で完全一致させる(S2 skeleton の方式を踏襲)。
//
// ハーネス設計は features/uc/steps/configure-feature-flags.steps.js(S6)を踏襲する:
//   Scenario ごとの一時ディレクトリを sandbox root とし、仕様の絶対パス(/etc/relay-gate, /opt/relay-gate)を
//   root 配下の同じ相対位置に配置する(/etc /opt へは書き込まない)。runner 実体は --help で
//   runner-if-version=1 を返す実行可能スタブ。ジョブマップは RELAY_GATE_CONFIG_DIR(= root/etc/relay-gate)に置く。
//   実行時に外部接続(DB・ネットワーク)は行わない。tier 実装は変更しない。
'use strict';
const { Given, When, Then, Before, After, setWorldConstructor } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const REPO_ROOT = path.resolve(__dirname, '../../..');
const VALIDATE_CONFIG = path.join(REPO_ROOT, 'facade/bin/validate-config.sh');

// 仕様の例示値(spec.md E2E 完了条件の絶対パス)
const SPEC_ENV_PATH = '/etc/relay-gate/feature-flag.env';
const SPEC_CONFIG_DIR = '/etc/relay-gate';
const SPEC_RUNNERS = {
  BLUE_RUNNER: '/opt/relay-gate/runners/blue-runner.sh',
  GREEN_RUNNER: '/opt/relay-gate/runners/green-runner.sh',
  RAPID_CROSSCHECK_RUNNER: '/opt/relay-gate/bin/rapid-crosscheck-runner.sh',
  RAPID_CROSSCHECK_WORKER: '/opt/relay-gate/bin/rapid-crosscheck-worker.sh',
};

// 元資料の 9 キー(spec.md「設定所有区分」)
const NINE_KEYS = [
  'BLUE_MODE',
  'GREEN_MODE',
  'RAPID_CROSSCHECK_MODE',
  'BLUE_IMPL',
  'GREEN_IMPL',
  'BLUE_RUNNER',
  'GREEN_RUNNER',
  'RAPID_CROSSCHECK_RUNNER',
  'RAPID_CROSSCHECK_WORKER',
];

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

// runner スタブ: --help → runner-if-version=1 を返す(UC「slot runner の実体スクリプトを割り当てる」の runner IF)
function runnerStubBody(name) {
  return (
    '#!/usr/bin/env bash\n' +
    'set -euo pipefail\n' +
    'if [ "${1:-}" = "--help" ]; then echo "usage: ' + name + '"; echo "runner-if-version=1"; exit 0; fi\n' +
    'echo "result: runner=' + name + ' job=${1:-}"\n'
  );
}

setWorldConstructor(
  class AtddWorld {
    sandbox(specPath) {
      return path.join(this.root, specPath);
    }
    unsandbox(text) {
      return text.split(this.root).join('');
    }
  },
);

Before(function () {
  this.root = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-gate-atdd-'));
  this.configDir = this.sandbox(SPEC_CONFIG_DIR);
  this.envPath = this.sandbox(SPEC_ENV_PATH);
  fs.mkdirSync(this.configDir, { recursive: true });
  fs.mkdirSync(this.sandbox('/opt/relay-gate/runners'), { recursive: true });
  fs.mkdirSync(this.sandbox('/opt/relay-gate/bin'), { recursive: true });
  this.env = {};
  this.result = null;
});

After(function () {
  if (this.root) {
    fs.rmSync(this.root, { recursive: true, force: true });
  }
});

function writeExecutable(file, body) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, body, { mode: 0o755 });
  return file;
}

function writeJobMap(world, slot) {
  fs.writeFileSync(path.join(world.configDir, `${slot}-job-map.csv`), 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\n');
}

function flushEnv(world) {
  const body = Object.entries(world.env)
    .map(([key, value]) => `${key}=${value}`)
    .join('\n');
  fs.writeFileSync(world.envPath, body + '\n');
}

function outputDump(world) {
  return `--- stdout ---\n${world.result.stdout}\n--- stderr ---\n${world.result.stderr}`;
}

function stderrLines(world) {
  return world.unsandbox(world.result.stderr).split('\n');
}

// ---- Given ----

Given(
  literal(
    '元資料の 9 キー(BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE / BLUE_IMPL / GREEN_IMPL / BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)で feature flag 設定を書く',
  ),
  function () {
    // 「有効な値」= 並行稼働の組合せ + runner 実体が実行可能 + off でない slot のジョブマップが存在
    this.env = {
      BLUE_MODE: 'foreground',
      GREEN_MODE: 'background',
      RAPID_CROSSCHECK_MODE: 'background',
      BLUE_IMPL: 'blue-2.3.1',
      GREEN_IMPL: 'green-1.4.0',
    };
    for (const key of Object.keys(SPEC_RUNNERS)) {
      const file = this.sandbox(SPEC_RUNNERS[key]);
      writeExecutable(file, runnerStubBody(path.basename(file)));
      this.env[key] = file;
    }
    assert.deepEqual(Object.keys(this.env).sort(), [...NINE_KEYS].sort(), 'feature flag must contain exactly the 9 keys');
    writeJobMap(this, 'blue');
    writeJobMap(this, 'green');
    flushEnv(this);
  },
);

// ---- When ----

When(literal('設定を検証する'), function () {
  const proc = spawnSync(VALIDATE_CONFIG, ['--feature-flag', this.envPath], {
    cwd: this.root,
    encoding: 'utf8',
    env: { ...process.env, RELAY_GATE_CONFIG_DIR: this.configDir },
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  this.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
});

// ---- Then ----

Then(literal('未知キーの警告は出ない'), function () {
  // 「検証を通過する」(spec.md 設定所有区分の完了条件)の前提として終了コード 0 も確認する
  assert.equal(this.result.status, 0, `exit code\n${outputDump(this)}`);
  const warns = stderrLines(this).filter((line) => line.startsWith('warn: unknown key'));
  assert.deepEqual(warns, [], `stderr should not contain "warn: unknown key" lines\n${outputDump(this)}`);
});
