// UC BDD(②)step definition。uc_id=fd678b04 / branch_slug=configure-feature-flags(S6 uc-bdd で実装)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/spec.md#E2E完了条件(BDD)
// step 文言は feature から転写したリテラルを正規表現で完全一致させる(S2 skeleton の方式を踏襲)。
//
// I/O 境界は実体で検証する: Scenario ごとに一時ディレクトリを sandbox root とし、feature に書かれた
// 絶対パス(/etc/relay-gate/... /opt/relay-gate/...)は root 配下の同じ相対位置に配置する
// (/etc /opt へは書き込まない)。validate-config.sh は与えたパスをそのまま `path:` に出すため、
// 出力を照合するときは root の接頭辞を落として feature の文言と突き合わせる。
// ジョブマップの配置先は tier-facade の RELAY_GATE_CONFIG_DIR(= root/etc/relay-gate)に合わせる。
// 実行時に外部接続(DB・ネットワーク)は行わない。
'use strict';
const { Given, When, Then, Before, After, setWorldConstructor } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const REPO_ROOT = path.resolve(__dirname, '../../..');
const VALIDATE_CONFIG = path.join(REPO_ROOT, 'facade/bin/validate-config.sh');

// feature に書かれた絶対パス(仕様の例示値)
const SPEC_ENV_PATH = '/etc/relay-gate/feature-flag.env';
const SPEC_CONFIG_DIR = '/etc/relay-gate';
const SPEC_RUNNERS = {
  BLUE_RUNNER: '/opt/relay-gate/runners/blue-runner.sh',
  GREEN_RUNNER: '/opt/relay-gate/runners/green-runner.sh',
  RAPID_CROSSCHECK_RUNNER: '/opt/relay-gate/bin/rapid-crosscheck-runner.sh',
  RAPID_CROSSCHECK_WORKER: '/opt/relay-gate/bin/rapid-crosscheck-worker.sh',
};
const SPEC_MISSING_WORKER = '/opt/relay-gate/bin/missing-worker.sh';

// runner スタブ(UC「slot runner の実体スクリプトを割り当てる」の runner IF):
//   --help → runner-if-version=1 を返す
//   それ以外 → 起動記録(root/var/<name>.invoked)を書き、結果を stdout に返す(Scenario「運用モードを切り替える」用)
function runnerStubBody(name) {
  return (
    '#!/usr/bin/env bash\n' +
    'set -euo pipefail\n' +
    'if [ "${1:-}" = "--help" ]; then echo "usage: ' + name + '"; echo "runner-if-version=1"; exit 0; fi\n' +
    'mkdir -p "$RELAY_GATE_UC_BDD_VAR_DIR"\n' +
    'printf \'%s\\n\' "$*" >"$RELAY_GATE_UC_BDD_VAR_DIR/' + name + '.invoked"\n' +
    'echo "result: runner=' + name + ' job=${1:-}"\n'
  );
}

// 旧 Scenario「ジョブ定義を変えずに feature flag だけで運用モードを切り替える」の facade.sh ハーネス注入
// (FACADE_HARNESS_STUB / PSQL_SENTINEL)は spec event 20260917_050000_feedback_impl_feedback_fd678b04 で
// Scenario が検証側だけの判定に分離されたため撤去した(根拠: docs/impl/latest/fd678b04/issues/
// 20260917_074633_cross-uc-scenarios-resolution.md)。実行側は UC「slot 実行モードを選択して runner を起動する」が覆う。

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

// World: 仕様の絶対パスを sandbox root 配下へ写像する
setWorldConstructor(
  class UcBddWorld {
    sandbox(specPath) {
      return path.join(this.root, specPath);
    }
    // 出力中の sandbox root 接頭辞を落として、feature の文言(仕様の絶対パス)と比較可能にする
    unsandbox(text) {
      return text.split(this.root).join('');
    }
  },
);

Before(function () {
  this.root = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-gate-uc-'));
  this.configDir = this.sandbox(SPEC_CONFIG_DIR);
  this.envPath = this.sandbox(SPEC_ENV_PATH);
  this.varDir = path.join(this.root, 'var');
  fs.mkdirSync(this.configDir, { recursive: true });
  fs.mkdirSync(this.sandbox('/opt/relay-gate/runners'), { recursive: true });
  fs.mkdirSync(this.sandbox('/opt/relay-gate/bin'), { recursive: true });
  this.env = {};
  this.result = null;
  this.jobDefinition = null;
  this.jobDefinitionBefore = null;
  this.parallelResult = null;
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

function writeRunnerStubs(world, keys) {
  for (const key of keys) {
    const file = world.sandbox(SPEC_RUNNERS[key]);
    writeExecutable(file, runnerStubBody(path.basename(file)));
  }
}

function assertRunnerHelp(world, key) {
  const help = spawnSync(world.sandbox(SPEC_RUNNERS[key]), ['--help'], { encoding: 'utf8' });
  assert.equal(help.status, 0, `${key} --help exit code`);
  assert.ok(help.stdout.split('\n').includes('runner-if-version=1'), `${key} --help should print runner-if-version=1`);
}

function writeJobMap(world, slot) {
  fs.writeFileSync(path.join(world.configDir, `${slot}-job-map.csv`), 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\n');
}

function sandboxedRunnerEnv(world, keys) {
  const env = {};
  for (const key of keys) {
    env[key] = world.sandbox(SPEC_RUNNERS[key]);
  }
  return env;
}

const ALL_RUNNER_KEYS = ['BLUE_RUNNER', 'GREEN_RUNNER', 'RAPID_CROSSCHECK_RUNNER', 'RAPID_CROSSCHECK_WORKER'];

function parallelEnv(world) {
  return {
    BLUE_MODE: 'foreground',
    GREEN_MODE: 'background',
    RAPID_CROSSCHECK_MODE: 'background',
    BLUE_IMPL: 'blue-2.3.1',
    GREEN_IMPL: 'green-1.4.0',
    ...sandboxedRunnerEnv(world, ALL_RUNNER_KEYS),
  };
}

function greenOnlyEnv(world) {
  return {
    BLUE_MODE: 'off',
    GREEN_MODE: 'foreground',
    RAPID_CROSSCHECK_MODE: 'off',
    GREEN_IMPL: 'green-1.4.0',
    ...sandboxedRunnerEnv(world, ['GREEN_RUNNER']),
  };
}

function flushEnv(world) {
  const body = Object.entries(world.env)
    .map(([key, value]) => `${key}=${value}`)
    .join('\n');
  fs.writeFileSync(world.envPath, body + '\n');
}

function processEnv(world, extra) {
  return {
    ...process.env,
    RELAY_GATE_CONFIG_DIR: world.configDir,
    RELAY_GATE_UC_BDD_VAR_DIR: world.varDir,
    ...extra,
  };
}

function runValidateConfig(world, args) {
  flushEnv(world);
  const proc = spawnSync(VALIDATE_CONFIG, args, { cwd: world.root, encoding: 'utf8', env: processEnv(world) });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  world.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
}

function outputDump(world) {
  return `--- stdout ---\n${world.result.stdout}\n--- stderr ---\n${world.result.stderr}`;
}

function assertExit(world, code) {
  assert.equal(world.result.status, code, `exit code\n${outputDump(world)}`);
}

function stdoutLines(world) {
  return world.unsandbox(world.result.stdout).split('\n').filter((line) => line.length > 0);
}

function stderrLines(world) {
  return world.unsandbox(world.result.stderr).split('\n');
}

function assertStdoutIncludes(world, expected) {
  assert.ok(stdoutLines(world).includes(expected), `stdout should include line "${expected}"\n${outputDump(world)}`);
}

function assertStderrIncludes(world, expected) {
  assert.ok(stderrLines(world).includes(expected), `stderr should include line "${expected}"\n${outputDump(world)}`);
}

// ---- Given: 正常系 ----

Given(
  literal(
    '/etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/bin/rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=/opt/relay-gate/bin/rapid-crosscheck-worker.sh がある',
  ),
  function () {
    this.env = parallelEnv(this);
    flushEnv(this);
  },
);

Given(literal('両 runner・速報 runner・速報 worker は実行可能ファイルで、両 runner は --help に "runner-if-version=1" を返す'), function () {
  writeRunnerStubs(this, ALL_RUNNER_KEYS);
  assertRunnerHelp(this, 'BLUE_RUNNER');
  assertRunnerHelp(this, 'GREEN_RUNNER');
});

Given(literal('/etc/relay-gate/blue-job-map.csv と /etc/relay-gate/green-job-map.csv が存在する'), function () {
  writeJobMap(this, 'blue');
  writeJobMap(this, 'green');
});

Given(
  literal(
    'feature-flag.env に BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE / BLUE_IMPL / GREEN_IMPL / BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER の 9 キーだけを有効な値で書いた',
  ),
  function () {
    // 「有効な値」= runner 実体が実行可能で、off でない slot のジョブマップがある状態
    this.env = parallelEnv(this);
    assert.deepEqual(Object.keys(this.env).length, 9);
    writeRunnerStubs(this, ALL_RUNNER_KEYS);
    writeJobMap(this, 'blue');
    writeJobMap(this, 'green');
    flushEnv(this);
  },
);

Given(
  literal('feature-flag.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh がある'),
  function () {
    this.env = greenOnlyEnv(this);
    flushEnv(this);
  },
);

Given(literal('BLUE_IMPL / BLUE_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER は未設定である'), function () {
  for (const key of ['BLUE_IMPL', 'BLUE_RUNNER', 'RAPID_CROSSCHECK_RUNNER', 'RAPID_CROSSCHECK_WORKER']) {
    assert.ok(!(key in this.env), `${key} should not be set`);
  }
});

Given(literal('green runner は実行可能で --help に "runner-if-version=1" を返し、/etc/relay-gate/green-job-map.csv が存在する'), function () {
  writeRunnerStubs(this, ['GREEN_RUNNER']);
  assertRunnerHelp(this, 'GREEN_RUNNER');
  writeJobMap(this, 'green');
});

Given(
  literal(
    'feature-flag.env に BLUE_MODE=background GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=background BLUE_IMPL=green-1.4.0 GREEN_IMPL=green-2.0.0 BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/bin/rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=/opt/relay-gate/bin/rapid-crosscheck-worker.sh がある',
  ),
  function () {
    this.env = {
      BLUE_MODE: 'background',
      GREEN_MODE: 'foreground',
      RAPID_CROSSCHECK_MODE: 'background',
      BLUE_IMPL: 'green-1.4.0',
      GREEN_IMPL: 'green-2.0.0',
      ...sandboxedRunnerEnv(this, ALL_RUNNER_KEYS),
    };
    flushEnv(this);
  },
);

Given(
  literal('両 runner・速報 runner・速報 worker は実行可能で、両 runner は --help に "runner-if-version=1" を返し、/etc/relay-gate/blue-job-map.csv と green-job-map.csv が存在する'),
  function () {
    writeRunnerStubs(this, ALL_RUNNER_KEYS);
    assertRunnerHelp(this, 'BLUE_RUNNER');
    assertRunnerHelp(this, 'GREEN_RUNNER');
    writeJobMap(this, 'blue');
    writeJobMap(this, 'green');
  },
);

// ---- Given / When / Then: 運用モード切替(検証側だけで判定。spec.md の注記どおり facade.sh は起動しない) ----
// spec event 20260917_050000_feedback_impl_feedback_fd678b04 で When / Then が差し替わった Scenario。
// 同一の sandbox 上で feature-flag.env だけを並行稼働 → 単独本番へ書き換え、validate-config.sh を 2 回実行する。
// ジョブ定義(facade.sh JOB001)は記録だけ保持し、テストは facade.sh を配置も起動もしない。

// ジョブ定義の記録を文字列化する(変更していないことを Then で突き合わせるため)
function jobDefinitionSnapshot(world) {
  return JSON.stringify(world.jobDefinition);
}

Given(literal('ジョブスケジューラのジョブ定義は facade.sh JOB001 のままである'), function () {
  // 前提条件の記録のみ(テストは facade.sh の起動やジョブ定義に触れない。spec.md E2E 完了条件の注記)
  this.jobDefinition = { command: 'facade.sh', args: ['JOB001'] };
  this.jobDefinitionBefore = jobDefinitionSnapshot(this);
});

Given(
  literal(
    'feature-flag.env は並行稼働の組合せ(BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background)で、validate-config.sh --feature-flag が終了コード 0 で stdout に operation_mode=parallel を返した',
  ),
  function () {
    // 並行稼働の組合せ: 4 実体の runner スタブと両 slot のジョブマップを用意して検証を通しておく
    this.env = parallelEnv(this);
    writeRunnerStubs(this, ALL_RUNNER_KEYS);
    writeJobMap(this, 'blue');
    writeJobMap(this, 'green');
    runValidateConfig(this, ['--feature-flag', this.envPath]);
    assertExit(this, 0);
    assertStdoutIncludes(this, 'operation_mode=parallel');
    this.parallelResult = this.result;
  },
);

When(
  literal('feature-flag.env を単独本番の組合せ(BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off)へ変更して validate-config.sh --feature-flag を実行する'),
  function () {
    // 変更するのは feature-flag.env だけ(runner 実体・ジョブマップ・ジョブ定義は前段のまま)
    this.env = greenOnlyEnv(this);
    runValidateConfig(this, ['--feature-flag', this.envPath]);
  },
);

Then(literal('stderr に "error:" で始まる行は出ない'), function () {
  const errors = stderrLines(this).filter((line) => line.startsWith('error:'));
  assert.deepEqual(errors, [], outputDump(this));
});

Then(literal('ジョブスケジューラのジョブ定義は変更していない'), function () {
  // 記録したジョブ定義が Given のままであること
  assert.equal(jobDefinitionSnapshot(this), this.jobDefinitionBefore, 'job definition should stay facade.sh JOB001');
  assert.deepEqual(this.jobDefinition, { command: 'facade.sh', args: ['JOB001'] });
  // テストが facade.sh を配置・起動していないこと(sandbox に facade.sh が無く、runner の起動記録も無い)
  assert.ok(!fs.existsSync(this.sandbox('/opt/relay-gate/bin/facade.sh')), 'facade.sh must not be placed by this test');
  const invoked = fs.existsSync(this.varDir) ? fs.readdirSync(this.varDir).filter((name) => name.endsWith('.invoked')) : [];
  assert.deepEqual(invoked, [], 'runner must not be executed (only --help probe is allowed)');
});

// ---- Given: 異常系 ----

Given(literal('feature-flag.env に BLUE_MODE=foreground GREEN_MODE=foreground がある'), function () {
  this.env = { BLUE_MODE: 'foreground', GREEN_MODE: 'foreground' };
  flushEnv(this);
});

Given(literal('feature-flag.env に RAPID_CROSSCHECK_MODE=on がある'), function () {
  this.env = { RAPID_CROSSCHECK_MODE: 'on' };
  flushEnv(this);
});

Given(
  literal('feature-flag.env に RAPID_CROSSCHECK_MODE=background があり RAPID_CROSSCHECK_RUNNER が未設定、RAPID_CROSSCHECK_WORKER=/opt/relay-gate/bin/missing-worker.sh は存在しない'),
  function () {
    this.env = { RAPID_CROSSCHECK_MODE: 'background', RAPID_CROSSCHECK_WORKER: this.sandbox(SPEC_MISSING_WORKER) };
    assert.ok(!fs.existsSync(this.env.RAPID_CROSSCHECK_WORKER));
    flushEnv(this);
  },
);

Given(literal('feature-flag.env に GREEN_MODE=foreground があり GREEN_IMPL が未設定である'), function () {
  this.env = { GREEN_MODE: 'foreground' };
  flushEnv(this);
});

Given(literal('feature-flag.env に FINAL_CROSSCHECK_MODE=background がある'), function () {
  this.env = { FINAL_CROSSCHECK_MODE: 'background' };
  flushEnv(this);
});

// ---- FINAL_ 接頭辞キーの拒否(spec event 20260917_100000_feedback_impl_feedback_fd678b04_cycle2 で追加) ----
// Scenario「FINAL_ で始まる確報設定のキーは未知キーではなく拒否される(SPEC-001-01)」。
// 有効な並行稼働の状態(9 キー + runner 実体 + ジョブマップ)に FINAL_DB_CONN_REF を 1 行足すだけにし、
// 拒否理由が「未知キー warn」ではなく「final crosscheck key is not allowed error」の 1 件だけであることを確認する。

Given(
  literal(
    'feature-flag.env の 9 キー・両 runner と速報 runner / worker の実体・blue / green のジョブマップは、Scenario「並行稼働モードの feature flag を検証する(SPEC-001-01)」の Given と同じ有効な状態である(単体なら終了コード 0 になる)',
  ),
  function () {
    this.env = parallelEnv(this);
    assert.equal(Object.keys(this.env).length, 9);
    writeRunnerStubs(this, ALL_RUNNER_KEYS);
    assertRunnerHelp(this, 'BLUE_RUNNER');
    assertRunnerHelp(this, 'GREEN_RUNNER');
    writeJobMap(this, 'blue');
    writeJobMap(this, 'green');
    // 「単体なら終了コード 0 になる」ことを実体で確認してから FINAL_ キーを加える
    runValidateConfig(this, ['--feature-flag', this.envPath]);
    assertExit(this, 0);
    assertStdoutIncludes(this, 'operation_mode=parallel');
    this.result = null;
  },
);

Given(literal('feature-flag.env に FINAL_DB_CONN_REF=final-db の 1 行を加えた(FINAL_ で始まるが FINAL_CROSSCHECK_ で始まらないキー)'), function () {
  assert.ok(!('FINAL_DB_CONN_REF' in this.env));
  this.env.FINAL_DB_CONN_REF = 'final-db';
  flushEnv(this);
  const lines = fs.readFileSync(this.envPath, 'utf8').split('\n').filter((line) => line.length > 0);
  assert.equal(lines.length, 10, 'feature-flag.env should have 9 keys + 1 FINAL_ line');
  assert.ok(lines.includes('FINAL_DB_CONN_REF=final-db'));
});

Then(literal('終了コード 2 で stderr に "error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF');
});

Then(literal('stderr の "error:" で始まる行はその 1 行だけである'), function () {
  const errors = stderrLines(this).filter((line) => line.startsWith('error:'));
  assert.deepEqual(errors, ['error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF'], outputDump(this));
});

Then(literal('stderr に "warn: unknown key key=FINAL_DB_CONN_REF" で始まる行は出ない'), function () {
  const warns = stderrLines(this).filter((line) => line.startsWith('warn: unknown key key=FINAL_DB_CONN_REF'));
  assert.deepEqual(warns, [], outputDump(this));
});

Given(literal('feature-flag.env に BLUE_MODE=parallel GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=maybe がある'), function () {
  this.env = { BLUE_MODE: 'parallel', GREEN_MODE: 'foreground', RAPID_CROSSCHECK_MODE: 'maybe' };
  flushEnv(this);
});

// ---- When ----

When(literal('基盤適用設計者が validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する'), function () {
  runValidateConfig(this, ['--feature-flag', this.envPath]);
});

When(literal('validate-config.sh --feature-flag を実行する'), function () {
  runValidateConfig(this, ['--feature-flag', this.envPath]);
});

// ---- Then ----

Then(literal('終了コード 0 で終了する'), function () {
  assertExit(this, 0);
});

Then(
  literal('stdout に blue_mode=foreground green_mode=background blue_impl=blue-2.3.1 green_impl=green-1.4.0 rapid_crosscheck_mode=background operation_mode=parallel が出る'),
  function () {
    for (const expected of [
      'blue_mode=foreground',
      'green_mode=background',
      'blue_impl=blue-2.3.1',
      'green_impl=green-1.4.0',
      'rapid_crosscheck_mode=background',
      'operation_mode=parallel',
    ]) {
      assertStdoutIncludes(this, expected);
    }
  },
);

Then(literal('stderr に "warn: unknown key" で始まる行は 1 行も出ない'), function () {
  const warns = stderrLines(this).filter((line) => line.startsWith('warn: unknown key'));
  assert.deepEqual(warns, [], outputDump(this));
});

Then(literal('終了コード 0 で stdout に operation_mode=green_only が出る'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'operation_mode=green_only');
});

Then(literal('終了コード 0 で stdout に operation_mode=next_gen_parallel が出る'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'operation_mode=next_gen_parallel');
});

Then(literal('終了コード 2 で stderr に "error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground');
});

Then(literal('終了コード 2 で stderr に "error: invalid value key=RAPID_CROSSCHECK_MODE value=on" と "hint: use foreground, background or off" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: invalid value key=RAPID_CROSSCHECK_MODE value=on');
  assertStderrIncludes(this, 'hint: use foreground, background or off');
});

Then(
  literal(
    '終了コード 2 で stderr に "error: option required option=RAPID_CROSSCHECK_RUNNER path: /etc/relay-gate/feature-flag.env" と "error: file not executable key=RAPID_CROSSCHECK_WORKER path=/opt/relay-gate/bin/missing-worker.sh" の両方が出る',
  ),
  function () {
    assertExit(this, 2);
    assertStderrIncludes(this, 'error: option required option=RAPID_CROSSCHECK_RUNNER path: /etc/relay-gate/feature-flag.env');
    assertStderrIncludes(this, 'error: file not executable key=RAPID_CROSSCHECK_WORKER path=/opt/relay-gate/bin/missing-worker.sh');
  },
);

Then(literal('終了コード 2 で stderr に "error: option required option=GREEN_IMPL path: /etc/relay-gate/feature-flag.env" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: option required option=GREEN_IMPL path: /etc/relay-gate/feature-flag.env');
});

Then(literal('終了コード 2 で stderr に "error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE');
});

Then(
  literal(
    '終了コード 2 で stderr に "error: invalid value key=BLUE_MODE value=parallel" と "error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe" の両方が出る(各行に "hint: use foreground, background or off" が続く)',
  ),
  function () {
    assertExit(this, 2);
    const lines = stderrLines(this);
    for (const expected of ['error: invalid value key=BLUE_MODE value=parallel', 'error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe']) {
      const index = lines.indexOf(expected);
      assert.ok(index >= 0, `stderr should include line "${expected}"\n${outputDump(this)}`);
      assert.equal(lines[index + 1], 'hint: use foreground, background or off', `hint should follow "${expected}"\n${outputDump(this)}`);
    }
  },
);

// ==== S2 test-scaffold 再実行(2026-11-15。spec event 20261115_142000_feedback_impl_feedback_fd678b04_cycle3)で追加 ====
// spec.md「E2E 完了条件(BDD)」の末尾に足された 2 Scenario:
//   「error 行が 2 行以上のときは決まった順に報告される」
//   「mode が列挙外の slot も実装版と対応ジョブマップを検査し runner へ問い合わせる」
// 規則の正本は cli-command-contract.yaml の config_files.feature-flag.env(error_order / validation_rules)。
// どちらも validate-config.sh だけで判定でき、他 UC の責務を Then に含まない(UC 横断 Scenario ではない)。既存 step は変更していない。
// この仕様更新は現行実装の挙動を仕様に書いたもの(spec-decision-034)のため、追加 Scenario は現行実装で green になる。

// 起動されるたびに受け取った引数を <スタブのパス>.calls へ 1 行ずつ記録する runner スタブ(--help で runner-if-version=1 を返す)。
// 既存の runnerStubBody は --help の起動を記録しないため、--help の起動回数を数える Scenario 用に別に持つ
function recordingRunnerStubBody(name) {
  return (
    '#!/usr/bin/env bash\n' +
    'set -euo pipefail\n' +
    'printf \'%s\\n\' "$*" >>"$0.calls"\n' +
    'if [ "${1:-}" = "--help" ]; then echo "usage: ' + name + '"; echo "runner-if-version=1"; exit 0; fi\n' +
    'exit 6\n'
  );
}

function runnerCalls(world, key) {
  const log = `${world.sandbox(SPEC_RUNNERS[key])}.calls`;
  if (!fs.existsSync(log)) {
    return [];
  }
  return fs.readFileSync(log, 'utf8').split('\n').filter((line) => line.length > 0);
}

function assertJobMapAbsent(world, slot) {
  assert.ok(!fs.existsSync(path.join(world.configDir, `${slot}-job-map.csv`)), `${slot}-job-map.csv should not exist`);
}

// stderr の全行(空行を除く。sandbox root の接頭辞を落とした後)が表の行とこの順で完全に一致する
function assertStderrIsExactly(world, count, table) {
  const expected = table.raw().map((row) => row[0].trim());
  assert.equal(expected.length, Number(count), `feature table should have ${count} rows`);
  assert.deepEqual(
    stderrLines(world).filter((line) => line.length > 0),
    expected,
    outputDump(world),
  );
}

// ---- Given ----

Given(
  literal(
    '/etc/relay-gate/feature-flag.env の 1 行目が BLUE_MODE=foreground、2 行目が GREEN_MODE=foreground、3 行目が RAPID_CROSSCHECK_MODE=maybe、4 行目が GREEN_IMPL=green-1.4.0、5 行目が BLUE_RUNNER=relative/blue-runner.sh、6 行目が FINAL_POLL_LIMIT_SEC=60、7 行目が FINAL_CROSSCHECK_MODE=background である',
  ),
  function () {
    // this.env は挿入順に 1 行ずつ書き出される(flushEnv)
    this.env = {
      BLUE_MODE: 'foreground',
      GREEN_MODE: 'foreground',
      RAPID_CROSSCHECK_MODE: 'maybe',
      GREEN_IMPL: 'green-1.4.0',
      BLUE_RUNNER: 'relative/blue-runner.sh',
      FINAL_POLL_LIMIT_SEC: '60',
      FINAL_CROSSCHECK_MODE: 'background',
    };
    flushEnv(this);
    const lines = fs.readFileSync(this.envPath, 'utf8').split('\n').filter((line) => line.length > 0);
    assert.equal(lines.length, 7);
    assert.equal(lines[0], 'BLUE_MODE=foreground');
    assert.equal(lines[6], 'FINAL_CROSSCHECK_MODE=background');
  },
);

Given(
  literal(
    'BLUE_IMPL / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER は未設定で、/etc/relay-gate/blue-job-map.csv と /etc/relay-gate/green-job-map.csv は存在せず、/etc/relay-gate/relative/blue-runner.sh も存在しない',
  ),
  function () {
    // spec event 20261115_164000_feedback_runner_relative_path で文言が置き換わった(相対パスは設定ファイルのあるディレクトリ基準で解決し、
    // 実体が無ければ解決後のパスの file not executable になる。そのため解決後の位置に実体が無いことを前提に足した)
    for (const key of ['BLUE_IMPL', 'GREEN_RUNNER', 'RAPID_CROSSCHECK_RUNNER', 'RAPID_CROSSCHECK_WORKER']) {
      assert.ok(!(key in this.env), `${key} should not be set`);
    }
    assertJobMapAbsent(this, 'blue');
    assertJobMapAbsent(this, 'green');
    assert.ok(!fs.existsSync(this.sandbox('/etc/relay-gate/relative/blue-runner.sh')), 'relative/blue-runner.sh should not exist');
  },
);

Given(
  literal(
    'feature-flag.env に BLUE_MODE=parallel GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_IMPL=green-1.4.0 GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh があり BLUE_IMPL が未設定である',
  ),
  function () {
    this.env = {
      BLUE_MODE: 'parallel',
      GREEN_MODE: 'foreground',
      RAPID_CROSSCHECK_MODE: 'off',
      BLUE_RUNNER: this.sandbox(SPEC_RUNNERS.BLUE_RUNNER),
      GREEN_IMPL: 'green-1.4.0',
      GREEN_RUNNER: this.sandbox(SPEC_RUNNERS.GREEN_RUNNER),
    };
    assert.ok(!('BLUE_IMPL' in this.env));
    flushEnv(this);
  },
);

Given(
  literal(
    '両 runner は実行可能で --help に "runner-if-version=1" を返し、/etc/relay-gate/green-job-map.csv は存在し、/etc/relay-gate/blue-job-map.csv は存在しない',
  ),
  function () {
    for (const key of ['BLUE_RUNNER', 'GREEN_RUNNER']) {
      const file = this.sandbox(SPEC_RUNNERS[key]);
      writeExecutable(file, recordingRunnerStubBody(path.basename(file)));
      // スタブを直接 1 回起動して応答を確認し、その起動の記録を消してから When に進む
      assertRunnerHelp(this, key);
      assert.deepEqual(runnerCalls(this, key), ['--help']);
      fs.rmSync(`${file}.calls`);
    }
    writeJobMap(this, 'green');
    assertJobMapAbsent(this, 'blue');
  },
);

// ---- When ----

When(literal('validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する'), function () {
  runValidateConfig(this, ['--feature-flag', this.envPath]);
});

// ---- Then ----

Then(literal('終了コード 2 で stdout は 0 行である'), function () {
  assertExit(this, 2);
  assert.equal(this.result.stdout, '', `stdout should be empty\n${outputDump(this)}`);
});

Then(/^stderr は次の (\d+) 行だけがこの順に出る$/, function (count, table) {
  assertStderrIsExactly(this, count, table);
});

Then(literal('blue runner は --help で 1 回起動されている(mode が列挙外の slot も runner へ問い合わせる)'), function () {
  assert.deepEqual(runnerCalls(this, 'BLUE_RUNNER'), ['--help'], 'blue runner invocations');
});

// ==== S2 test-scaffold 再実行(2026-11-15。spec event 20261115_164000_feedback_runner_relative_path)で追加 ====
// spec.md「E2E 完了条件(BDD)」に足された 2 Scenario:
//   「方針資料の設定例の書き方(相対パス)の feature flag を検証する」
//   「相対パスの基準は作業ディレクトリではなく設定ファイルのあるディレクトリである」
// 規則の正本は cli-command-contract.yaml の config_files.feature-flag.env.runner_path_resolution
// (BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER の相対パスは、設定ファイルのあるディレクトリを基準に解決する)。
// どちらも validate-config.sh だけで判定でき、他 UC の責務を Then に含まない(UC 横断 Scenario ではない)。
// 置換された Scenario「error 行が 2 行以上のときは決まった順に報告される」は、Given の文言 1 件だけを上で差し替えた。
// 現行実装は 4 キーの相対パスを `error: path is not absolute` で拒否するため、この 3 Scenario は実装が追従するまで assertion failure で fail する。

// feature に書かれた作業ディレクトリ(/tmp /tmp/work)も sandbox root 配下へ写像する
const SPEC_CWD_TMP = '/tmp';
const SPEC_CWD_WORK = '/tmp/work';
const RELATIVE_RUNNER_NAMES = ['blue-runner.sh', 'green-runner.sh', 'rapid-crosscheck-runner.sh', 'rapid-crosscheck-worker.sh'];

// 作業ディレクトリを指定して validate-config.sh を起動する。
// 契約の「作業ディレクトリ」はシェルの $PWD の論理パスのため、環境変数 PWD も作業ディレクトリに合わせて渡す
function runValidateConfigIn(world, cwd, args) {
  flushEnv(world);
  fs.mkdirSync(cwd, { recursive: true });
  const proc = spawnSync(VALIDATE_CONFIG, args, { cwd, encoding: 'utf8', env: processEnv(world, { PWD: cwd }) });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  world.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
}

// ---- Given ----

Given(
  literal(
    '/etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=./blue-runner.sh GREEN_RUNNER=./green-runner.sh RAPID_CROSSCHECK_RUNNER=./rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=./rapid-crosscheck-worker.sh がある',
  ),
  function () {
    // 値は feature に書かれた相対パスのまま書く(sandbox の絶対パスへ置き換えない)
    this.env = {
      BLUE_MODE: 'foreground',
      GREEN_MODE: 'background',
      RAPID_CROSSCHECK_MODE: 'background',
      BLUE_IMPL: 'blue-2.3.1',
      GREEN_IMPL: 'green-1.4.0',
      BLUE_RUNNER: './blue-runner.sh',
      GREEN_RUNNER: './green-runner.sh',
      RAPID_CROSSCHECK_RUNNER: './rapid-crosscheck-runner.sh',
      RAPID_CROSSCHECK_WORKER: './rapid-crosscheck-worker.sh',
    };
    flushEnv(this);
  },
);

Given(
  literal(
    '/etc/relay-gate に blue-runner.sh / green-runner.sh / rapid-crosscheck-runner.sh / rapid-crosscheck-worker.sh が実行可能ファイルとしてあり、両 runner は --help に "runner-if-version=1" を返す',
  ),
  function () {
    for (const name of RELATIVE_RUNNER_NAMES) {
      writeExecutable(path.join(this.configDir, name), runnerStubBody(name));
    }
    for (const name of ['blue-runner.sh', 'green-runner.sh']) {
      const help = spawnSync(path.join(this.configDir, name), ['--help'], { encoding: 'utf8' });
      assert.equal(help.status, 0, `${name} --help exit code`);
      assert.ok(help.stdout.split('\n').includes('runner-if-version=1'), `${name} --help should print runner-if-version=1`);
    }
  },
);

Given(
  literal('/etc/relay-gate/feature-flag.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=./green-runner.sh がある'),
  function () {
    this.env = {
      BLUE_MODE: 'off',
      GREEN_MODE: 'foreground',
      RAPID_CROSSCHECK_MODE: 'off',
      GREEN_IMPL: 'green-1.4.0',
      GREEN_RUNNER: './green-runner.sh',
    };
    flushEnv(this);
  },
);

Given(literal('/etc/relay-gate/green-runner.sh は存在せず、作業ディレクトリ /tmp/work に実行可能な green-runner.sh がある'), function () {
  assert.ok(!fs.existsSync(path.join(this.configDir, 'green-runner.sh')), '/etc/relay-gate/green-runner.sh should not exist');
  // 作業ディレクトリ側の実体は、起動されたら記録が残るスタブにする(作業ディレクトリを基準にしたら検証を通ってしまう)
  const decoy = path.join(this.sandbox(SPEC_CWD_WORK), 'green-runner.sh');
  writeExecutable(decoy, recordingRunnerStubBody('green-runner.sh'));
  fs.accessSync(decoy, fs.constants.X_OK);
});

Given(literal('/etc/relay-gate/green-job-map.csv が存在する'), function () {
  writeJobMap(this, 'green');
});

// ---- When ----

When(literal('基盤適用設計者が作業ディレクトリ /tmp で validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する'), function () {
  runValidateConfigIn(this, this.sandbox(SPEC_CWD_TMP), ['--feature-flag', this.envPath]);
});

When(
  literal('基盤適用設計者が作業ディレクトリ /tmp/work で validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する'),
  function () {
    runValidateConfigIn(this, this.sandbox(SPEC_CWD_WORK), ['--feature-flag', this.envPath]);
  },
);

// ---- Then ----

Then(literal('終了コード 0 で終了し、stderr に "error:" で始まる行は出ない'), function () {
  assertExit(this, 0);
  const errors = stderrLines(this).filter((line) => line.startsWith('error:'));
  assert.deepEqual(errors, [], outputDump(this));
});

Then(
  literal(
    'stdout に "blue_runner: /etc/relay-gate/./blue-runner.sh" "green_runner: /etc/relay-gate/./green-runner.sh" "rapid_crosscheck_runner: /etc/relay-gate/./rapid-crosscheck-runner.sh" "rapid_crosscheck_worker: /etc/relay-gate/./rapid-crosscheck-worker.sh" と operation_mode=parallel が出る',
  ),
  function () {
    // 解決後のパス = 設定ファイルのあるディレクトリ + / + 値(. を畳まない)。sandbox root の接頭辞は stdoutLines が落とす
    for (const expected of [
      'blue_runner: /etc/relay-gate/./blue-runner.sh',
      'green_runner: /etc/relay-gate/./green-runner.sh',
      'rapid_crosscheck_runner: /etc/relay-gate/./rapid-crosscheck-runner.sh',
      'rapid_crosscheck_worker: /etc/relay-gate/./rapid-crosscheck-worker.sh',
      'operation_mode=parallel',
    ]) {
      assertStdoutIncludes(this, expected);
    }
  },
);

Then(literal('終了コード 2 で stderr に "error: file not executable key=GREEN_RUNNER path=/etc/relay-gate/./green-runner.sh" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: file not executable key=GREEN_RUNNER path=/etc/relay-gate/./green-runner.sh');
});

Then(literal('stderr に "path is not absolute" を含む行は出ない'), function () {
  const hits = stderrLines(this).filter((line) => line.includes('path is not absolute'));
  assert.deepEqual(hits, [], outputDump(this));
});

// ==== S2 test-scaffold 再実行(2026-11-16。slot ジョブマップの場所を書く任意の 2 キー)で追加 ====
// spec.md「E2E 完了条件(BDD)」に足された 4 Scenario:
//   「ジョブマップの場所を絶対パスで書いた feature flag は未知キー警告なしで検証を通過する(SPEC-001-01)」
//   「ジョブマップの場所の相対パスは設定ファイルのあるディレクトリを基準に解決される(SPEC-004-01)」
//   「9 キーと任意の 2 キーのどちらでもないキーは未知キーとして警告される(SPEC-001-01)」
//   「書いた場所にジョブマップが無い feature flag は解決後のパスつきで拒否される(SPEC-004-01)」
// と、Scenario「元資料の 9 キーの feature flag は未知キー警告なしで検証を通過する(SPEC-001-01)」に足された And 2 行。
// 規則の正本は cli-command-contract.yaml の config_files.feature-flag.env.job_map_location
// (BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV は任意。無い・空なら $RELAY_GATE_CONFIG_DIR/<slot>-job-map.csv。相対パスの基準は設定ファイルのあるディレクトリ)。
// どれも validate-config.sh だけで判定でき、他 UC の責務を Then に含まない(UC 横断 Scenario ではない。実行側 = runner が同じ場所を使うことは
// spec.md「関連 USDM」の注記どおり別 UC が覆う)。既存 step は変更していない。
// 追加時点の実装は 2 キーを未知キーとして warn し、固定の名前だけを見るため、2 キーを書く 3 Scenario は実装が追従するまで assertion failure で fail する
// (2 キーを書かない Scenario と、名前が違うキーの Scenario は現行実装でも通る)。

// feature に書かれた、設定ファイル置き場の外のジョブマップの場所(sandbox root 配下へ写像する)
const SPEC_MAPS = {
  blue: '/srv/relay-gate/maps/blue-jobs.csv',
  green: '/srv/relay-gate/maps/green-jobs.csv',
};
const JOB_MAP_HEADER = 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\n';

function writeJobMapAt(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JOB_MAP_HEADER);
}

function assertJobMapPresent(world, slot) {
  assert.ok(fs.existsSync(path.join(world.configDir, `${slot}-job-map.csv`)), `${slot}-job-map.csv should exist`);
}

function assertNoErrorLines(world) {
  const errors = stderrLines(world).filter((line) => line.startsWith('error:'));
  assert.deepEqual(errors, [], outputDump(world));
}

// ---- Given ----

Given(
  literal(
    'BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV は書かず、RELAY_GATE_CONFIG_DIR=/etc/relay-gate で /etc/relay-gate/blue-job-map.csv と /etc/relay-gate/green-job-map.csv が存在する',
  ),
  function () {
    assert.ok(!('BLUE_JOB_MAP_CSV' in this.env), 'BLUE_JOB_MAP_CSV should not be written');
    assert.ok(!('GREEN_JOB_MAP_CSV' in this.env), 'GREEN_JOB_MAP_CSV should not be written');
    // RELAY_GATE_CONFIG_DIR は processEnv が sandbox の /etc/relay-gate を渡す
    assert.equal(this.configDir, this.sandbox(SPEC_CONFIG_DIR));
    writeJobMap(this, 'blue');
    writeJobMap(this, 'green');
  },
);

Given(
  literal(
    '/etc/relay-gate/feature-flag.env に、Scenario「並行稼働モードの feature flag を検証する(SPEC-001-01)」の Given と同じ 9 キーに加えて BLUE_JOB_MAP_CSV=/srv/relay-gate/maps/blue-jobs.csv GREEN_JOB_MAP_CSV=/srv/relay-gate/maps/green-jobs.csv がある',
  ),
  function () {
    this.env = {
      ...parallelEnv(this),
      BLUE_JOB_MAP_CSV: this.sandbox(SPEC_MAPS.blue),
      GREEN_JOB_MAP_CSV: this.sandbox(SPEC_MAPS.green),
    };
    assert.equal(Object.keys(this.env).length, 11);
    flushEnv(this);
  },
);

Given(
  literal(
    '/srv/relay-gate/maps/blue-jobs.csv と /srv/relay-gate/maps/green-jobs.csv が存在し、/etc/relay-gate/blue-job-map.csv と /etc/relay-gate/green-job-map.csv は存在しない',
  ),
  function () {
    writeJobMapAt(this.sandbox(SPEC_MAPS.blue));
    writeJobMapAt(this.sandbox(SPEC_MAPS.green));
    // 固定の名前のファイルは置かない(固定の名前を見る実装なら job map not found になる)
    assertJobMapAbsent(this, 'blue');
    assertJobMapAbsent(this, 'green');
  },
);

Given(
  literal(
    '/etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh BLUE_JOB_MAP_CSV=./blue-jobs.csv GREEN_JOB_MAP_CSV=maps/green-jobs.csv がある',
  ),
  function () {
    // 2 キーの値は feature に書かれた相対パスのまま書く(sandbox の絶対パスへ置き換えない)
    this.env = {
      BLUE_MODE: 'foreground',
      GREEN_MODE: 'background',
      RAPID_CROSSCHECK_MODE: 'off',
      BLUE_IMPL: 'blue-2.3.1',
      GREEN_IMPL: 'green-1.4.0',
      ...sandboxedRunnerEnv(this, ['BLUE_RUNNER', 'GREEN_RUNNER']),
      BLUE_JOB_MAP_CSV: './blue-jobs.csv',
      GREEN_JOB_MAP_CSV: 'maps/green-jobs.csv',
    };
    flushEnv(this);
  },
);

Given(literal('両 runner は実行可能で --help に "runner-if-version=1" を返す'), function () {
  writeRunnerStubs(this, ['BLUE_RUNNER', 'GREEN_RUNNER']);
  assertRunnerHelp(this, 'BLUE_RUNNER');
  assertRunnerHelp(this, 'GREEN_RUNNER');
});

Given(
  literal(
    '/etc/relay-gate/blue-jobs.csv と /etc/relay-gate/maps/green-jobs.csv が存在し、作業ディレクトリ /tmp/work に blue-jobs.csv と maps/green-jobs.csv は無い',
  ),
  function () {
    writeJobMapAt(path.join(this.configDir, 'blue-jobs.csv'));
    writeJobMapAt(path.join(this.configDir, 'maps', 'green-jobs.csv'));
    const work = this.sandbox(SPEC_CWD_WORK);
    assert.ok(!fs.existsSync(path.join(work, 'blue-jobs.csv')), '/tmp/work/blue-jobs.csv should not exist');
    assert.ok(!fs.existsSync(path.join(work, 'maps', 'green-jobs.csv')), '/tmp/work/maps/green-jobs.csv should not exist');
    // 固定の名前のファイルも置かない(2 キーの値を使わない実装なら job map not found になる)
    assertJobMapAbsent(this, 'blue');
    assertJobMapAbsent(this, 'green');
  },
);

Given(literal('feature-flag.env に BLUE_JOB_MAP=/srv/relay-gate/maps/blue-jobs.csv の 1 行を加えた(任意の 2 キーと名前が違うキー)'), function () {
  assert.ok(!('BLUE_JOB_MAP' in this.env));
  this.env.BLUE_JOB_MAP = this.sandbox(SPEC_MAPS.blue);
  flushEnv(this);
  const lines = fs.readFileSync(this.envPath, 'utf8').split('\n').filter((line) => line.length > 0);
  assert.equal(lines.length, 10, 'feature-flag.env should have 9 keys + 1 BLUE_JOB_MAP line');
});

Given(
  literal(
    '/etc/relay-gate/feature-flag.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh GREEN_JOB_MAP_CSV=./green-jobs.csv がある',
  ),
  function () {
    this.env = { ...greenOnlyEnv(this), GREEN_JOB_MAP_CSV: './green-jobs.csv' };
    flushEnv(this);
  },
);

Given(literal('green runner は実行可能で --help に "runner-if-version=1" を返す'), function () {
  writeRunnerStubs(this, ['GREEN_RUNNER']);
  assertRunnerHelp(this, 'GREEN_RUNNER');
});

Given(literal('/etc/relay-gate/green-jobs.csv は存在せず、/etc/relay-gate/green-job-map.csv は存在する'), function () {
  assert.ok(!fs.existsSync(path.join(this.configDir, 'green-jobs.csv')), '/etc/relay-gate/green-jobs.csv should not exist');
  writeJobMap(this, 'green');
  assertJobMapPresent(this, 'green');
});

// ---- When ----

// RELAY_GATE_CONFIG_DIR=/etc/relay-gate は processEnv が渡す sandbox の /etc/relay-gate(既存の起動と同じ)
When(
  literal('基盤適用設計者が RELAY_GATE_CONFIG_DIR=/etc/relay-gate で validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する'),
  function () {
    runValidateConfig(this, ['--feature-flag', this.envPath]);
  },
);

When(literal('RELAY_GATE_CONFIG_DIR=/etc/relay-gate で validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env を実行する'), function () {
  runValidateConfig(this, ['--feature-flag', this.envPath]);
});

// ---- Then ----

Then(
  literal(
    'stderr に "error:" で始まる行は出ず、stdout に "blue_job_map: /etc/relay-gate/blue-job-map.csv" "green_job_map: /etc/relay-gate/green-job-map.csv" が出る(場所を書くキーが無いときは固定の名前を使う)',
  ),
  function () {
    assertNoErrorLines(this);
    assertStdoutIncludes(this, 'blue_job_map: /etc/relay-gate/blue-job-map.csv');
    assertStdoutIncludes(this, 'green_job_map: /etc/relay-gate/green-job-map.csv');
  },
);

Then(literal('終了コード 0 で stderr は 0 行である("warn: unknown key" で始まる行も "error:" で始まる行も出ない)'), function () {
  assertExit(this, 0);
  assert.deepEqual(
    stderrLines(this).filter((line) => line.length > 0),
    [],
    outputDump(this),
  );
});

Then(
  literal('stdout に "blue_job_map: /srv/relay-gate/maps/blue-jobs.csv" "green_job_map: /srv/relay-gate/maps/green-jobs.csv" と operation_mode=parallel が出る'),
  function () {
    assertStdoutIncludes(this, 'blue_job_map: /srv/relay-gate/maps/blue-jobs.csv');
    assertStdoutIncludes(this, 'green_job_map: /srv/relay-gate/maps/green-jobs.csv');
    assertStdoutIncludes(this, 'operation_mode=parallel');
  },
);

Then(literal('終了コード 0 で stderr に "error:" で始まる行は出ない'), function () {
  assertExit(this, 0);
  assertNoErrorLines(this);
});

Then(
  literal(
    'stdout に "blue_job_map: /etc/relay-gate/./blue-jobs.csv" "green_job_map: /etc/relay-gate/maps/green-jobs.csv" が出る(設定に書いた相対パスのままは出ない)',
  ),
  function () {
    // 解決後のパス = 設定ファイルのあるディレクトリ + / + 値(. を畳まない)。sandbox root の接頭辞は stdoutLines が落とす
    assertStdoutIncludes(this, 'blue_job_map: /etc/relay-gate/./blue-jobs.csv');
    assertStdoutIncludes(this, 'green_job_map: /etc/relay-gate/maps/green-jobs.csv');
    const asWritten = stdoutLines(this).filter((line) => line === 'blue_job_map: ./blue-jobs.csv' || line === 'green_job_map: maps/green-jobs.csv');
    assert.deepEqual(asWritten, [], outputDump(this));
  },
);

Then(literal('終了コード 0 で stderr に "warn: unknown key key=BLUE_JOB_MAP path: /etc/relay-gate/feature-flag.env" が出る'), function () {
  assertExit(this, 0);
  assertStderrIncludes(this, 'warn: unknown key key=BLUE_JOB_MAP path: /etc/relay-gate/feature-flag.env');
});

Then(literal('stdout に "blue_job_map: /etc/relay-gate/blue-job-map.csv" が出る(未知キーの値はジョブマップの場所に使われない)'), function () {
  assertStdoutIncludes(this, 'blue_job_map: /etc/relay-gate/blue-job-map.csv');
});

Then(
  literal('stderr に "error: job map not found slot=green map=/etc/relay-gate/./green-jobs.csv" が出る(固定の名前のファイルがあっても使わない)'),
  function () {
    assertStderrIncludes(this, 'error: job map not found slot=green map=/etc/relay-gate/./green-jobs.csv');
  },
);
