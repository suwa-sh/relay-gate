// tier BDD(③)step definition。tier-facade / uc_id=65b09d93(slot runner の実体スクリプトを割り当てる)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/slot runner の実体スクリプトを割り当てる/tier-facade.md#ティア完了条件(BDD)
// このファイルが定義するのは、他 UC の step ファイルに定義の無い step だけ(同じ文言を再定義すると ambiguous になる)。
// 既存 step(configure-feature-flags.steps.js の「RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある」
// 「`validate-config.sh --feature-flag ff.env` を実行する」など)は、同ファイルの Before が作る World(workDir / configDir /
// envPath / env)と flushEnv の書き方(this.env を KEY=value の行で this.envPath へ書く)を前提にする。
// 同ファイルを require すると step が二重登録されるため、使う補助関数はここに写している。
// リポジトリの中にはファイルを書かない。書くのは Before が作る一時ディレクトリ(this.workDir)の中だけ。
'use strict';
const { Given, Then, When, After, BeforeStep, AfterStep } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

// 配置ディレクトリ(RELAY_GATE_HOME)は tier dir(facade/)。契約 standard_runner.home: runners/ の 1 つ上
const FACADE_HOME = path.resolve(__dirname, '../..');
const STANDARD_RUNNER = path.join(FACADE_HOME, 'runners', 'standard-runner.sh');
const VALIDATE_CONFIG = path.join(FACADE_HOME, 'bin', 'validate-config.sh');
const FACADE_SH = path.join(FACADE_HOME, 'bin', 'facade.sh');
const LIB_FILES = ['runner-resolve.sh', 'runner-spec.sh', 'runner-result.sh', 'runner-notify.sh'];
// 配置ディレクトリの複製に写すディレクトリ(入口の runners/ と lib/、入口が読む本体の src/)
const DEPLOY_DIRS = ['runners', 'lib', 'src'];

// 自作 runner スタブ: --help で runner-if-version=1 を返す
const CUSTOM_RUNNER_STUB =
  '#!/usr/bin/env bash\n' +
  'if [ "${1:-}" = "--help" ]; then echo "usage: custom-runner.sh"; echo "runner-if-version=1"; exit 0; fi\n' +
  'exit 6\n';

// 起動されるたびに受け取った引数を <スタブのパス>.invoked へ 1 行ずつ記録し、--help で runner-if-version=1 を返すスタブ
const RECORDING_RUNNER_STUB =
  '#!/usr/bin/env bash\n' +
  'printf \'%s\\n\' "$*" >>"$0.invoked"\n' +
  'if [ "${1:-}" = "--help" ]; then echo "usage: runner-stub.sh"; echo "runner-if-version=1"; exit 0; fi\n' +
  'exit 6\n';

// --help に runner-if-version= を含まない出力を返す実行可能ファイル(終了コードは 0)
const NO_VERSION_RUNNER_STUB = '#!/usr/bin/env bash\necho "usage: green-runner.sh"\nexit 0\n';

// --help を受けると 30 秒 sleep するスタブ。exec で sleep に置き換わるため、記録した PID は sleep のプロセス
const SLEEPING_RUNNER_STUB =
  '#!/usr/bin/env bash\n' +
  'if [ "${1:-}" = "--help" ]; then printf \'%s\\n\' "$$" >>"$0.pids"; exec sleep 30; fi\n' +
  'exit 6\n';

// 起動引数と環境変数を記録し、Runner Result 3 ファイルを書く自作 runner(facade.sh を起動する Scenario 用)
const RECORDING_RESULT_RUNNER_STUB =
  '#!/usr/bin/env bash\n' +
  'if [ "${1:-}" = "--help" ]; then echo "usage: custom-runner.sh"; echo "runner-if-version=1"; exit 0; fi\n' +
  'printf \'%s\\n\' "$*" >"$0.args"\n' +
  'env >"$0.env"\n' +
  'run_id=""; role=""\n' +
  'while [ "$#" -gt 0 ]; do case "$1" in --run-id) run_id="$2"; shift 2 ;; --role) role="$2"; shift 2 ;; --) break ;; *) shift ;; esac; done\n' +
  'dir="$RELAY_GATE_ARTIFACT_ROOT/facade/$run_id/$role"\n' +
  'mkdir -p "$dir" && : >"$dir/stdout.log" && : >"$dir/stderr.log" && echo 0 >"$dir/exitcode.txt"\n' +
  'exit 0\n';

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

function writeExecutableAt(file, body) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, body, { mode: 0o755 });
  return file;
}

function writeJobMap(world, slot) {
  fs.writeFileSync(path.join(world.configDir, `${slot}-job-map.csv`), 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\n');
}

function invocations(file) {
  const log = `${file}.invoked`;
  if (!fs.existsSync(log)) {
    return [];
  }
  return fs
    .readFileSync(log, 'utf8')
    .split('\n')
    .filter((line) => line.length > 0);
}

// conf と work を、親ディレクトリも別になるように置く(<workDir>/a/conf と <workDir>/b/work)。ff.env は conf に置く
function arrangeConfAndWork(world) {
  world.confDir = path.join(world.workDir, 'a', 'conf');
  world.cwdDir = path.join(world.workDir, 'b', 'work');
  fs.mkdirSync(world.confDir, { recursive: true });
  fs.mkdirSync(world.cwdDir, { recursive: true });
  world.envPath = path.join(world.confDir, 'ff.env');
}

function flushEnv(world) {
  fs.writeFileSync(world.envPath, Object.entries(world.env).map(([key, value]) => `${key}=${value}\n`).join(''));
}

// 作業ディレクトリを指定して validate-config.sh を起動する(契約の作業ディレクトリは $PWD の論理パスのため PWD も合わせる)
function runValidateConfigIn(world, cwd, args) {
  flushEnv(world);
  const env = { ...process.env, RELAY_GATE_CONFIG_DIR: world.configDir, PWD: cwd };
  const proc = spawnSync(VALIDATE_CONFIG, args, { cwd, encoding: 'utf8', env });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  world.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
}

// stdout の行(最後の改行の後の空文字列だけを除く。途中の空行は行として数える)
function stdoutLines(world) {
  const lines = world.result.stdout.split('\n');
  if (lines[lines.length - 1] === '') {
    lines.pop();
  }
  return lines;
}

function stderrLines(world) {
  return world.result.stderr.split('\n').filter((line) => line.length > 0);
}

function dump(world) {
  return `--- stdout ---\n${world.result.stdout}\n--- stderr ---\n${world.result.stderr}`;
}

function assertExit(world, code) {
  assert.equal(world.result.status, code, `exit code\n${dump(world)}`);
}

// n 行目(1 始まり)が expected であること
function assertStdoutLine(world, number, expected) {
  assert.equal(stdoutLines(world)[number - 1], expected, `stdout line ${number}\n${dump(world)}`);
}

function assertStdoutIncludes(world, expected) {
  assert.ok(stdoutLines(world).includes(expected), `stdout should include line "${expected}"\n${dump(world)}`);
}

function assertStderrIncludes(world, expected) {
  assert.ok(stderrLines(world).includes(expected), `stderr should include line "${expected}"\n${dump(world)}`);
}

function assertStderrHasLineStartingWith(world, prefix) {
  assert.ok(
    stderrLines(world).some((line) => line.startsWith(prefix)),
    `stderr should include a line starting with "${prefix}"\n${dump(world)}`,
  );
}

function processAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === 'EPERM';
  }
}

// ---- 条件つきの hook(該当 Scenario が World に印を立てたときだけ働く。ほかの Scenario では何もしない) ----

// 「10 秒以内に復帰する」: When の step の開始から終了までを測る(Given の準備の時間を含めない)
BeforeStep(function ({ pickleStep }) {
  if (this.measureWhenElapsed && pickleStep.type === 'Action') {
    this.whenStartedAt = process.hrtime.bigint();
  }
});

AfterStep(function ({ pickleStep }) {
  if (this.measureWhenElapsed && pickleStep.type === 'Action' && this.whenStartedAt !== undefined) {
    this.whenElapsedMs = Number(process.hrtime.bigint() - this.whenStartedAt) / 1e6;
  }
});

// 問い合わせの準備失敗の Scenario が書き換えた環境変数(TMPDIR / PATH)を戻す
After(function () {
  if (this.savedProcessEnv) {
    for (const [key, value] of Object.entries(this.savedProcessEnv)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
    this.savedProcessEnv = undefined;
  }
});

// ---- standard-runner.sh の --help ----

When(literal('`runners/standard-runner.sh --help` を実行する'), function () {
  // 配置ディレクトリを作業ディレクトリにして、字面どおりの相対パスで起動する
  const proc = spawnSync('runners/standard-runner.sh', ['--help'], { cwd: FACADE_HOME, encoding: 'utf8' });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  this.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
});

Then(literal('終了コード 0 で stdout に "usage: " で始まる行と "runner-if-version=1" が出る'), function () {
  assertExit(this, 0);
  assert.ok(stdoutLines(this).some((line) => line.startsWith('usage: ')), `stdout should include a usage line\n${dump(this)}`);
  assertStdoutIncludes(this, 'runner-if-version=1');
});

// ---- 配置ディレクトリの中身 ----

Given(literal('relay-gate を配置したディレクトリ <home> がある'), function () {
  // 配置ディレクトリは tier dir(facade/)。読むだけで書かない
  this.deployHome = FACADE_HOME;
  assert.ok(fs.statSync(this.deployHome).isDirectory());
});

When(literal('<home>/runners/ のファイルを確かめる'), function () {
  const runnersDir = path.join(this.deployHome, 'runners');
  this.runnerEntries = fs.readdirSync(runnersDir);
  this.standardRunnerStat = fs.lstatSync(path.join(runnersDir, 'standard-runner.sh'));
});

Then(literal('<home>/runners/standard-runner.sh は通常ファイルで実行権限がある'), function () {
  assert.ok(this.standardRunnerStat.isFile(), 'standard-runner.sh should be a regular file (not a symbolic link)');
  fs.accessSync(path.join(this.deployHome, 'runners', 'standard-runner.sh'), fs.constants.X_OK);
});

Then(literal('<home>/runners/ssh-runner.sh は存在しない'), function () {
  assert.ok(!this.runnerEntries.includes('ssh-runner.sh'), `runners/ should not include ssh-runner.sh: ${this.runnerEntries}`);
});

Then(literal('<home>/lib/ に runner-resolve.sh / runner-spec.sh / runner-result.sh / runner-notify.sh がある'), function () {
  for (const name of LIB_FILES) {
    assert.ok(fs.statSync(path.join(this.deployHome, 'lib', name)).isFile(), `lib/${name} should be a regular file`);
  }
});

// ---- validate-config.sh --feature-flag: 標準の slot runner を割り当てた設定 ----

Given(
  literal(
    'ff.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=<runners/standard-runner.sh の絶対パス> GREEN_RUNNER=<同じ絶対パス> RAPID_CROSSCHECK_MODE=off を書く',
  ),
  function () {
    this.env = {
      BLUE_MODE: 'foreground',
      GREEN_MODE: 'background',
      BLUE_IMPL: 'blue-2.3.1',
      GREEN_IMPL: 'green-1.4.0',
      BLUE_RUNNER: STANDARD_RUNNER,
      GREEN_RUNNER: STANDARD_RUNNER,
      RAPID_CROSSCHECK_MODE: 'off',
    };
  },
);

Then(
  literal(
    'stdout は 15 行で、6 行目は "blue_runner: <runners/standard-runner.sh の絶対パス>"、7 行目は "green_runner: <runners/standard-runner.sh の絶対パス>"(同じパス)である',
  ),
  function () {
    assert.equal(stdoutLines(this).length, 15, `stdout line count\n${dump(this)}`);
    assertStdoutLine(this, 6, `blue_runner: ${STANDARD_RUNNER}`);
    assertStdoutLine(this, 7, `green_runner: ${STANDARD_RUNNER}`);
  },
);

Then(
  literal(
    'stdout の 12 行目は "blue_job_map: <RELAY_GATE_CONFIG_DIR>/blue-job-map.csv"、14 行目は "blue_runner_if_version=1"、15 行目は "green_runner_if_version=1" である',
  ),
  function () {
    assertStdoutLine(this, 12, `blue_job_map: ${this.configDir}/blue-job-map.csv`);
    assertStdoutLine(this, 14, 'blue_runner_if_version=1');
    assertStdoutLine(this, 15, 'green_runner_if_version=1');
  },
);

// ---- validate-config.sh --feature-flag: 設定ファイルからの相対パスで書いた標準の slot runner ----

Given(
  literal(
    'relay-gate の配置ディレクトリ <home> の下の config/ff.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=../runners/standard-runner.sh GREEN_RUNNER=../runners/standard-runner.sh RAPID_CROSSCHECK_MODE=off を書く',
  ),
  function () {
    // config/ff.env を書くため、配置ディレクトリは一時ディレクトリに作る(リポジトリの facade/ には書かない)。
    // 配置ディレクトリ全体(入口の runners/ と lib/、入口が読む本体の src/)を複製する。runner だけの複製やリンクではない
    this.deployHome = path.join(this.workDir, 'home');
    for (const dir of DEPLOY_DIRS) {
      fs.cpSync(path.join(FACADE_HOME, dir), path.join(this.deployHome, dir), { recursive: true });
    }
    fs.accessSync(path.join(this.deployHome, 'runners', 'standard-runner.sh'), fs.constants.X_OK);
    fs.mkdirSync(path.join(this.deployHome, 'config'));
    this.envPath = path.join(this.deployHome, 'config', 'ff.env');
    this.env = {
      BLUE_MODE: 'foreground',
      GREEN_MODE: 'background',
      BLUE_IMPL: 'blue-2.3.1',
      GREEN_IMPL: 'green-1.4.0',
      BLUE_RUNNER: '../runners/standard-runner.sh',
      GREEN_RUNNER: '../runners/standard-runner.sh',
      RAPID_CROSSCHECK_MODE: 'off',
    };
  },
);

When(
  literal('<home> とは別のディレクトリを作業ディレクトリにして `validate-config.sh --feature-flag <home の絶対パス>/config/ff.env` を実行する'),
  function () {
    const cwd = path.join(this.workDir, 'elsewhere');
    fs.mkdirSync(cwd);
    runValidateConfigIn(this, cwd, ['--feature-flag', path.join(this.deployHome, 'config', 'ff.env')]);
  },
);

Then(
  literal(
    '終了コード 0 で stdout の 6 行目は "blue_runner: <home の絶対パス>/config/../runners/standard-runner.sh"、7 行目は "green_runner: <home の絶対パス>/config/../runners/standard-runner.sh" である',
  ),
  function () {
    assertExit(this, 0);
    assertStdoutLine(this, 6, `blue_runner: ${this.deployHome}/config/../runners/standard-runner.sh`);
    assertStdoutLine(this, 7, `green_runner: ${this.deployHome}/config/../runners/standard-runner.sh`);
  },
);

Then(literal('stdout の 14 行目は "blue_runner_if_version=1"、15 行目は "green_runner_if_version=1" である'), function () {
  assertStdoutLine(this, 14, 'blue_runner_if_version=1');
  assertStdoutLine(this, 15, 'green_runner_if_version=1');
});

// ---- validate-config.sh --feature-flag: blue に標準の slot runner、green に自作の runner ----

Given(
  literal(
    'ff.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=<runners/standard-runner.sh の絶対パス> GREEN_RUNNER=<--help で "runner-if-version=1" を返す実行可能な自作 runner スタブの絶対パス> RAPID_CROSSCHECK_MODE=off を書く',
  ),
  function () {
    this.customRunner = writeExecutableAt(path.join(this.workDir, 'custom-runner.sh'), CUSTOM_RUNNER_STUB);
    this.env = {
      BLUE_MODE: 'foreground',
      GREEN_MODE: 'background',
      BLUE_IMPL: 'blue-2.3.1',
      GREEN_IMPL: 'green-1.4.0',
      BLUE_RUNNER: STANDARD_RUNNER,
      GREEN_RUNNER: this.customRunner,
      RAPID_CROSSCHECK_MODE: 'off',
    };
  },
);

Then(
  literal(
    'stdout の 6 行目は "blue_runner: <runners/standard-runner.sh の絶対パス>"、7 行目は "green_runner: <自作 runner スタブの絶対パス>"、14 行目は "blue_runner_if_version=1"、15 行目は "green_runner_if_version=1" である',
  ),
  function () {
    assertStdoutLine(this, 6, `blue_runner: ${STANDARD_RUNNER}`);
    assertStdoutLine(this, 7, `green_runner: ${this.customRunner}`);
    assertStdoutLine(this, 14, 'blue_runner_if_version=1');
    assertStdoutLine(this, 15, 'green_runner_if_version=1');
  },
);

// ---- validate-config.sh --feature-flag: 相対パスの runner ----

Given(
  literal('一時ディレクトリ conf の ff.env に BLUE_MODE=off GREEN_MODE=foreground GREEN_IMPL=green-1.4.0 GREEN_RUNNER=./green-runner.sh RAPID_CROSSCHECK_MODE=off を書く'),
  function () {
    arrangeConfAndWork(this);
    this.env = {
      BLUE_MODE: 'off',
      GREEN_MODE: 'foreground',
      GREEN_IMPL: 'green-1.4.0',
      GREEN_RUNNER: './green-runner.sh',
      RAPID_CROSSCHECK_MODE: 'off',
    };
  },
);

Given(literal('conf/green-runner.sh は、起動されるたびに引数を記録し --help で "runner-if-version=1" を返す実行可能なスタブである'), function () {
  this.confRunner = writeExecutableAt(path.join(this.confDir, 'green-runner.sh'), RECORDING_RUNNER_STUB);
});

Given(literal('作業ディレクトリにするディレクトリ work(conf とは別)に、起動されたら記録を残す別の実行可能な green-runner.sh がある'), function () {
  assert.notEqual(this.cwdDir, this.confDir);
  this.workRunner = writeExecutableAt(path.join(this.cwdDir, 'green-runner.sh'), RECORDING_RUNNER_STUB);
});

Then(
  literal(
    '終了コード 0 で stdout に "green_runner: <conf の絶対パス>/./green-runner.sh" と "green_runner_if_version=1" が出て、stderr に "path is not absolute" を含む行は出ない',
  ),
  function () {
    assertExit(this, 0);
    assertStdoutIncludes(this, `green_runner: ${this.confDir}/./green-runner.sh`);
    assertStdoutIncludes(this, 'green_runner_if_version=1');
    const hits = stderrLines(this).filter((line) => line.includes('path is not absolute'));
    assert.deepEqual(hits, [], `no "path is not absolute" line expected\n${dump(this)}`);
  },
);

Then(literal('conf のスタブは引数 --help で 1 回起動され、work の green-runner.sh は起動されていない'), function () {
  assert.deepEqual(invocations(this.confRunner), ['--help']);
  assert.deepEqual(invocations(this.workRunner), []);
});

Given(literal('conf/green-runner.sh は --help に "runner-if-version=" を含まない出力を返す実行可能ファイルである'), function () {
  const runner = writeExecutableAt(path.join(this.confDir, 'green-runner.sh'), NO_VERSION_RUNNER_STUB);
  const help = spawnSync(runner, ['--help'], { encoding: 'utf8' });
  assert.ok(!help.stdout.includes('runner-if-version='), 'stub should not print runner-if-version=');
});

Then(
  literal('終了コード 0 で stderr に "warn: runner does not respond to --help slot=green runner=<conf の絶対パス>/./green-runner.sh" が出る'),
  function () {
    assertExit(this, 0);
    assertStderrIncludes(this, `warn: runner does not respond to --help slot=green runner=${this.confDir}/./green-runner.sh`);
  },
);

// ---- validate-config.sh --feature-flag: ジョブマップが無い slot ----

Given(literal('ff.env に GREEN_MODE=background GREEN_RUNNER=<実行可能> を書き RELAY_GATE_CONFIG_DIR/green-job-map.csv が無い'), function () {
  this.env = { GREEN_MODE: 'background', GREEN_RUNNER: writeExecutableAt(path.join(this.workDir, 'green-runner.sh'), CUSTOM_RUNNER_STUB) };
  assert.ok(!fs.existsSync(path.join(this.configDir, 'green-job-map.csv')), 'green-job-map.csv should not exist');
});

Then(literal('終了コード 2 で stderr に "error: job map not found slot=green map=<RELAY_GATE_CONFIG_DIR>/green-job-map.csv" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, `error: job map not found slot=green map=${this.configDir}/green-job-map.csv`);
});

// ---- validate-config.sh --feature-flag: --help に応答しない runner ----

Given(
  literal(
    'ff.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 RAPID_CROSSCHECK_MODE=off と、--help を受けると 30 秒 sleep する実行可能なスタブ runner を BLUE_RUNNER / GREEN_RUNNER に書く',
  ),
  function () {
    this.sleepingRunners = [
      writeExecutableAt(path.join(this.workDir, 'blue-runner.sh'), SLEEPING_RUNNER_STUB),
      writeExecutableAt(path.join(this.workDir, 'green-runner.sh'), SLEEPING_RUNNER_STUB),
    ];
    this.env = {
      BLUE_MODE: 'foreground',
      GREEN_MODE: 'background',
      BLUE_IMPL: 'blue-2.3.1',
      GREEN_IMPL: 'green-1.4.0',
      RAPID_CROSSCHECK_MODE: 'off',
      BLUE_RUNNER: this.sleepingRunners[0],
      GREEN_RUNNER: this.sleepingRunners[1],
    };
    this.measureWhenElapsed = true;
  },
);

// 待機の上限という振る舞いの確認(性能の検査ではない)。経過時間は When の step の開始から終了まで
Then(
  literal(
    '終了コード 0 で、起動から終了までの経過時間は 10 秒以内である(契約 runner_help_probe.response_time_budget の問い合わせの上限 9.2 秒に、数行の設定の検査の時間を加えた、この入力での確認)',
  ),
  function () {
    assertExit(this, 0);
    assert.ok(this.whenElapsedMs !== undefined, 'elapsed time of the When step should be measured');
    assert.ok(this.whenElapsedMs <= 10000, `elapsed ${this.whenElapsedMs} ms should be within 10 seconds`);
  },
);

Then(
  literal(
    'stderr に "warn: runner does not respond to --help slot=blue runner=" で始まる行と "warn: runner does not respond to --help slot=green runner=" で始まる行が出る',
  ),
  function () {
    assertStderrHasLineStartingWith(this, 'warn: runner does not respond to --help slot=blue runner=');
    assertStderrHasLineStartingWith(this, 'warn: runner does not respond to --help slot=green runner=');
  },
);

Then(literal('stdout に "blue_runner_if_version=-" と "green_runner_if_version=-" が出る'), function () {
  assertStdoutIncludes(this, 'blue_runner_if_version=-');
  assertStdoutIncludes(this, 'green_runner_if_version=-');
});

Then(literal('終了時点でスタブ runner のプロセスは残っていない'), function () {
  const pids = this.sleepingRunners.flatMap((runner) =>
    fs
      .readFileSync(`${runner}.pids`, 'utf8')
      .split('\n')
      .filter((line) => line.length > 0)
      .map(Number),
  );
  assert.equal(pids.length, 2, `each stub should be started once: ${pids}`);
  assert.deepEqual(
    pids.filter((pid) => processAlive(pid)),
    [],
    'stub runner processes should not remain',
  );
});

// ---- validate-config.sh --feature-flag: 問い合わせの準備失敗 ----

// TMPDIR を存在しないディレクトリにすると、問い合わせより先に行う入力の複製(契約 config_input_rules.snapshot)が失敗し、
// `error: config snapshot failed` になって問い合わせまで進まない(docs/impl/latest/65b09d93/issues/20261118_013500_probe-preparation-failure-scenario-unreachable.md)。
// そこで、PATH の先頭に代替の mktemp を置き、入力の複製の作業名(テンプレートの末尾が .part)だけを Scenario 専用の書ける
// ディレクトリに作る(snapshot.out_of_scope が認める代替コマンドの利用。test/presentation/validate_config.bats の前例)。
// 問い合わせの応答を受ける一時ファイルは TMPDIR(/nonexistent/tmp)のまま本物の mktemp で作るため、実際に作成に失敗する
Given(
  literal('有効な並行稼働設定の ff.env があり、一時ファイルの作成先(環境変数 TMPDIR)が存在しないディレクトリ /nonexistent/tmp を指す'),
  function () {
    this.env = {
      BLUE_MODE: 'foreground',
      GREEN_MODE: 'background',
      BLUE_IMPL: 'blue-2.3.1',
      GREEN_IMPL: 'green-1.4.0',
      BLUE_RUNNER: writeExecutableAt(path.join(this.workDir, 'blue-runner.sh'), CUSTOM_RUNNER_STUB),
      GREEN_RUNNER: writeExecutableAt(path.join(this.workDir, 'green-runner.sh'), CUSTOM_RUNNER_STUB),
      RAPID_CROSSCHECK_MODE: 'off',
    };
    writeJobMap(this, 'blue');
    writeJobMap(this, 'green');
    const nonexistent = '/nonexistent/tmp';
    assert.ok(!fs.existsSync(nonexistent), `${nonexistent} should not exist`);
    const which = spawnSync('bash', ['-c', 'command -v mktemp'], { encoding: 'utf8' });
    const realMktemp = which.stdout.trim();
    assert.ok(realMktemp.length > 0, 'mktemp should be found');
    const snapshotDir = path.join(this.workDir, 'snapshot-tmp');
    fs.mkdirSync(snapshotDir);
    const fakeBin = path.join(this.workDir, 'fake-bin');
    // 作業名は代替の mktemp が自分で作る(X を置き換えた名前・権限 0600)。本物の mktemp に .part のテンプレートを渡すと、
    // 末尾以外の X を置き換えない mktemp(BSD 系)では実装が TMPDIR の下へ移し直そうとして失敗するため
    writeExecutableAt(
      path.join(fakeBin, 'mktemp'),
      '#!/usr/bin/env bash\n' +
        'if [ "$#" -eq 1 ]; then\n' +
        '  case "$1" in\n' +
        `    ${nonexistent}/*XXXXXX.part)\n` +
        `      name="\${1#${nonexistent}/}"\n` +
        `      file="${snapshotDir}/\${name/XXXXXX/$$\$RANDOM}"\n` +
        '      (umask 077 && : >"$file") || exit 1\n' +
        '      printf \'%s\\n\' "$file"\n' +
        '      exit 0\n' +
        '      ;;\n' +
        '  esac\n' +
        'fi\n' +
        `exec "${realMktemp}" "$@"\n`,
    );
    this.savedProcessEnv = { TMPDIR: process.env.TMPDIR, PATH: process.env.PATH };
    process.env.TMPDIR = nonexistent;
    process.env.PATH = `${fakeBin}:${process.env.PATH}`;
  },
);

Then(literal('終了コード 6 で stderr に "error: runner probe failed slot=blue reason=" で始まる行が出る'), function () {
  assertExit(this, 6);
  assertStderrHasLineStartingWith(this, 'error: runner probe failed slot=blue reason=');
});

Then(literal('stderr に "warn: runner does not respond to --help" で始まる行は出ず、stdout は 0 行である'), function () {
  const hits = stderrLines(this).filter((line) => line.startsWith('warn: runner does not respond to --help'));
  assert.deepEqual(hits, [], `no warn line expected\n${dump(this)}`);
  assert.equal(this.result.stdout, '', `stdout should be empty\n${dump(this)}`);
});

// ---- facade.sh から自作 runner を起動する ----
// facade.sh は UC「slot 実行モードを選択して runner を起動する」の担当で、この UC の時点では無い
// (docs/impl/latest/65b09d93/issues/20261118_012630_cross-uc-scenarios.md)。facade.sh を起動する step は、
// bin/facade.sh が無い間は skipped を返し、有るのに未実装なら失敗させる(その UC が step を実装する)

Given(literal('起動引数と環境変数を記録し Runner Result 3 ファイルを書く自作 runner を GREEN_RUNNER に割り当てる'), function () {
  this.customRunner = writeExecutableAt(path.join(this.workDir, 'custom-runner.sh'), RECORDING_RESULT_RUNNER_STUB);
  this.env = { GREEN_RUNNER: this.customRunner };
});

When(literal('`facade.sh JOB001 x` を BLUE_MODE=off GREEN_MODE=foreground GREEN_IMPL=green-1.4.0 RAPID_CROSSCHECK_MODE=off で実行する'), function () {
  if (!fs.existsSync(FACADE_SH)) {
    return 'skipped';
  }
  throw new Error(`not implemented: ${FACADE_SH} exists; implement this step in the UC that provides facade.sh`);
});

Then(
  literal('自作 runner は "--run-id <run_id> --job-id JOB001 --role green --mode foreground -- x" で起動され、facade は exitcode.txt の値で終了する'),
  function () {
    throw new Error('not implemented: requires facade.sh');
  },
);

Then(literal('自作 runner の環境変数に RAPID_CROSSCHECK_MODE=off と GREEN_IMPL=green-1.4.0 があり、RAPID_CROSSCHECK_RUNNER は無い'), function () {
  throw new Error('not implemented: requires facade.sh');
});
