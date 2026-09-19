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
