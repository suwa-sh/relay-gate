// ATDD(①)step definition。uc_id=fd678b04 / branch_slug=configure-feature-flags(S7 atdd で実装)。
// source: features/atdd/SPEC-001-01.feature(@atdd_SPEC-001-01-4。uc-map fd678b04 の atdd_scenarios)
//   2026-11-16 の S2 再実行で @atdd_SPEC-001-01-7 / -8 / -9 と features/atdd/SPEC-004-01.feature の @atdd_SPEC-004-01-9 を末尾に追加した
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
  // 検証種別は Scenario ごとに既定(feature flag)へ戻す
  this.validation = null;
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

// 「設定を検証する」は複数 SPEC の受け入れ基準が同じ文言で使う(@atdd_SPEC-001-01-4 / @atdd_SPEC-004-04-4)。
// 同じ文言を UC ごとに再定義すると ambiguous step になるため、定義はここ 1 箇所に置き、
// Given が World に置いた検証種別(this.validation)で起動を切り替える。
//   未設定(既定)      → --feature-flag <envPath>(@atdd_SPEC-001-01-4。従来の起動と同一)
//   kind = 'job-map'   → --job-map <path>(@atdd_SPEC-004-04-4。define-slot-job-maps.steps.js の Given が設定)
// 根拠: docs/impl/latest/eff24f55/issues/20260919_161456_cross-uc-scenarios.md(4. step 文言の重複)
function validationArgs(world) {
  const validation = world.validation || { kind: 'feature-flag' };
  if (validation.kind === 'job-map') {
    assert.ok(validation.path, 'job map path must be prepared by Given');
    return ['--job-map', validation.path];
  }
  assert.equal(validation.kind, 'feature-flag', `unsupported validation kind: ${validation.kind}`);
  return ['--feature-flag', world.envPath];
}

When(literal('設定を検証する'), function () {
  const proc = spawnSync(VALIDATE_CONFIG, validationArgs(this), {
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

// ==== S2 test-scaffold 再実行(2026-11-16。slot ジョブマップの場所を書く任意の 2 キー)で追加 ====
// source: features/atdd/SPEC-001-01.feature(@atdd_SPEC-001-01-7 / -8 / -9)と features/atdd/SPEC-004-01.feature(@atdd_SPEC-004-01-9)。
// uc-map fd678b04 の atdd_scenarios に加わった 4 件。対応する UC BDD Scenario(spec.md「関連 USDM」):
//   SPEC-001-01-7 → 「ジョブマップの場所を絶対パスで書いた feature flag は未知キー警告なしで検証を通過する(SPEC-001-01)」
//   SPEC-001-01-8 → 「元資料の 9 キーの feature flag は未知キー警告なしで検証を通過する(SPEC-001-01)」
//   SPEC-001-01-9 → 「9 キーと任意の 2 キーのどちらでもないキーは未知キーとして警告される(SPEC-001-01)」
//   SPEC-004-01-9 → 「書いた場所にジョブマップが無い feature flag は解決後のパスつきで拒否される(SPEC-004-01)」
// 受け入れ基準の文言が持たない具体値(キー名・パス・文言)は、対応する UC BDD Scenario と CLI 契約
// config_files.feature-flag.env.job_map_location の値を使う。既存 step(@atdd_SPEC-001-01-4)は変更していない。
// 追加時点の実装は 2 キーを未知キーとして warn し、固定の名前だけを見るため、-7 と SPEC-004-01-9 は実装が追従するまで
// assertion failure で fail する(-8 と -9 は現行実装でも通る)。

// 設定ファイル置き場の外のジョブマップの場所(仕様の例示値。sandbox root 配下へ写像する)
const SPEC_MAPS = {
  blue: '/srv/relay-gate/maps/blue-jobs.csv',
  green: '/srv/relay-gate/maps/green-jobs.csv',
};
// 任意の 2 キーと名前が違うキー(仕様の例示値)
const UNKNOWN_KEY = 'BLUE_JOB_MAP';

// 有効な並行稼働の 9 キーと runner 実体を用意する(ジョブマップは置かない。置き場は Scenario ごとに決める)
function arrangeNineKeys(world) {
  world.env = {
    BLUE_MODE: 'foreground',
    GREEN_MODE: 'background',
    RAPID_CROSSCHECK_MODE: 'background',
    BLUE_IMPL: 'blue-2.3.1',
    GREEN_IMPL: 'green-1.4.0',
  };
  for (const key of Object.keys(SPEC_RUNNERS)) {
    const file = world.sandbox(SPEC_RUNNERS[key]);
    writeExecutable(file, runnerStubBody(path.basename(file)));
    world.env[key] = file;
  }
  assert.deepEqual(Object.keys(world.env).sort(), [...NINE_KEYS].sort(), 'feature flag must contain exactly the 9 keys');
}

function writeJobMapAt(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\n');
}

function fixedNameJobMap(world, slot) {
  return path.join(world.configDir, `${slot}-job-map.csv`);
}

function runFeatureFlagValidation(world) {
  const proc = spawnSync(VALIDATE_CONFIG, ['--feature-flag', world.envPath], {
    cwd: world.root,
    encoding: 'utf8',
    env: { ...process.env, RELAY_GATE_CONFIG_DIR: world.configDir },
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  world.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
}

// ---- Given ----

Given(
  literal(
    '元資料の 9 キーに加えて、slot ジョブマップの場所を書く任意の 2 キー(blue 用と green 用。キー名は仕様で確定する。推奨は BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV)を書いた feature flag 設定で、2 キーの値が指す場所にジョブマップがある',
  ),
  function () {
    arrangeNineKeys(this);
    // キー名は仕様で BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV に確定した(spec.md 設定所有区分、CLI 契約 job_map_location)
    this.env.BLUE_JOB_MAP_CSV = this.sandbox(SPEC_MAPS.blue);
    this.env.GREEN_JOB_MAP_CSV = this.sandbox(SPEC_MAPS.green);
    writeJobMapAt(this.env.BLUE_JOB_MAP_CSV);
    writeJobMapAt(this.env.GREEN_JOB_MAP_CSV);
    // 固定の名前のファイルは置かない(2 キーの値を使わない実装なら job map not found になる)
    assert.ok(!fs.existsSync(fixedNameJobMap(this, 'blue')));
    assert.ok(!fs.existsSync(fixedNameJobMap(this, 'green')));
    flushEnv(this);
  },
);

Given(literal('元資料の 9 キーだけを書き、slot ジョブマップの場所を書くキーが無い feature flag 設定'), function () {
  arrangeNineKeys(this);
  assert.ok(!('BLUE_JOB_MAP_CSV' in this.env) && !('GREEN_JOB_MAP_CSV' in this.env));
  // 場所を書くキーが無いときの場所 = $RELAY_GATE_CONFIG_DIR/<slot>-job-map.csv
  writeJobMap(this, 'blue');
  writeJobMap(this, 'green');
  flushEnv(this);
});

Given(literal('元資料の 9 キーと任意の 2 キーのどちらでもないキーを書いた feature flag 設定'), function () {
  arrangeNineKeys(this);
  writeJobMap(this, 'blue');
  writeJobMap(this, 'green');
  this.env[UNKNOWN_KEY] = this.sandbox(SPEC_MAPS.blue);
  flushEnv(this);
});

Given(literal('feature flag のジョブマップの場所のキーに書いた場所にジョブマップが無い'), function () {
  // 単独本番(green だけ)の設定に、相対パスで場所を書く。書いた場所には置かず、固定の名前のファイルは置く
  // (固定の名前へ読み替える実装なら検証を通ってしまう)
  const runner = this.sandbox(SPEC_RUNNERS.GREEN_RUNNER);
  writeExecutable(runner, runnerStubBody(path.basename(runner)));
  this.env = {
    BLUE_MODE: 'off',
    GREEN_MODE: 'foreground',
    RAPID_CROSSCHECK_MODE: 'off',
    GREEN_IMPL: 'green-1.4.0',
    GREEN_RUNNER: runner,
    GREEN_JOB_MAP_CSV: './green-jobs.csv',
  };
  assert.ok(!fs.existsSync(path.join(this.configDir, 'green-jobs.csv')));
  writeJobMap(this, 'green');
  flushEnv(this);
});

// ---- When ----

When(literal('feature flag の検証コマンドを実行する'), function () {
  runFeatureFlagValidation(this);
});

// ---- Then ----

Then(literal('未知キーの警告は出ず、エラーにならない'), function () {
  assert.equal(this.result.status, 0, `exit code\n${outputDump(this)}`);
  const hits = stderrLines(this).filter((line) => line.startsWith('warn: unknown key') || line.startsWith('error:'));
  assert.deepEqual(hits, [], `stderr should not contain "warn: unknown key" or "error:" lines\n${outputDump(this)}`);
});

Then(literal('ジョブマップの場所を書くキーが無いことを理由とするエラーも警告も出ない'), function () {
  // 9 キーだけの有効な設定は、error 行も warn 行も 1 行も出さずに通る
  assert.equal(this.result.status, 0, `exit code\n${outputDump(this)}`);
  const hits = stderrLines(this).filter((line) => line.startsWith('error:') || line.startsWith('warn:'));
  assert.deepEqual(hits, [], `stderr should not contain "error:" or "warn:" lines\n${outputDump(this)}`);
});

Then(literal('そのキーについて未知キーの警告が出る'), function () {
  const expected = `warn: unknown key key=${UNKNOWN_KEY} path: ${SPEC_ENV_PATH}`;
  assert.ok(stderrLines(this).includes(expected), `stderr should include line "${expected}"\n${outputDump(this)}`);
  // 未知キーは拒否しない(warn だけ)
  assert.equal(this.result.status, 0, `exit code\n${outputDump(this)}`);
});

Then(literal('非 0 の終了コードで終わり、標準エラーに、ジョブマップが見つからない旨の行が解決した後のパスつきで出る'), function () {
  assert.notEqual(this.result.status, 0, `exit code should be non-zero\n${outputDump(this)}`);
  // 解決した後のパス = 設定ファイルのあるディレクトリ + / + 値(. を畳まない)。sandbox root の接頭辞は stderrLines が落とす
  const expected = `error: job map not found slot=green map=${SPEC_CONFIG_DIR}/./green-jobs.csv`;
  assert.ok(stderrLines(this).includes(expected), `stderr should include line "${expected}"\n${outputDump(this)}`);
});
