// UC BDD(②)step definition。uc_id=7c41c7cd / branch_slug=resolve-execution-target-from-job-map(S6 uc-bdd で実装)。
// source: docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/ジョブマップで JOB_ID から実行先を解決する/spec.md#E2E完了条件(BDD)
// step 文言は feature から転写したリテラルを正規表現で完全一致させる(S2 skeleton の方式を踏襲)。
// ここに定義するのは、同じディレクトリの既存の step 定義に一致しない文言だけ(既存の step と同じ文言を再定義しない)。
// World(root / configDir / sandbox() / unsandbox())と Before / After は configure-feature-flags.steps.js のものを使う。
//
// I/O 境界は実体で検証する:
//   - relay-gate を一時ディレクトリの /opt/relay-gate に配置し(複製。リポジトリの facade/ には書かない)、その標準の slot runner
//     (runners/standard-runner.sh)を実プロセスとして起動する。終了コード・成果物ファイル・実行ログを見る
//   - 「facade が ... で起動する」: feature が固定の run_id を書いているため(facade.sh が発行する run_id は起動のたびに変わる)、
//     facade が渡すのと同じ環境変数(設定・成果物・実行ログの置き場、自 slot の実装版とジョブマップの場所)と runner IF の引数で
//     runner を直接起動する。role ディレクトリは facade が作るものなので、起動の前に step が作る
//     (根拠: docs/impl/latest/7c41c7cd/issues/20261123_142047_cross-uc-scenarios.md の 5)
//   - 「facade を介さずに ... 起動する」: RELAY_GATE_CONFIG_DIR だけを渡す(成果物と実行ログの置き場は、配置ディレクトリからの既定)
//   - 解決結果のうち実行ログに出ない項目(user / script / work_dir / 引数の並びなど)は、自作の runner と同じく共通ライブラリ
//     (配置した lib/runner-resolve.sh)を source して resolve_execution_target を直接呼んで確かめる。
//     関数の名前・引数・結果の受け取り方は、自作の runner へ約束する入口として仕様が定めている
//     (docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml の runner_resolve_library。判断記録 spec-decision-042)。ハーネス注入ではない。
//     execution-spec.json の保存と実装の実行は後続の機能で、この機能では見ない(同 issue の 1・4。オーケストレータの決定は案 A)
// Given が要点だけを書いている Scenario は、書かれていない列を仕様のほかの Scenario の例示の値で補う(同 issue の 5。書かれた値は変えない)。
// この機能は管理 DB に触らない(一時 PostgreSQL を起動しない。RAPID_CROSSCHECK_MODE=off)。
// リポジトリの中にはファイルを書かない。書くのは World の root(Scenario ごとの一時ディレクトリ)の中だけ。
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const h = require('./support/facade-harness');

const { literal } = h;

const SPEC_CONFIG_DIR = '/etc/relay-gate';
const SPEC_MAPS_DIR = '/srv/relay-gate/maps';
const RUNNER_SCRIPT_NAME = 'standard-runner.sh';
// 配置ディレクトリの複製に写すディレクトリ(標準の slot runner の入口 runners/ と lib/、入口が読む本体の src/)
const DEPLOY_DIRS = ['runners', 'lib', 'src'];

const HEADER_7 = 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes';
const HEADER_LOCAL = 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes';
// 仕様のほかの Scenario の例示の行(Given が行を書いていないときに補う)
const ROW_JOB001 = 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60';
const ROW_JOB999 = 'JOB999,host-green-01,batch,/var/app/work,/opt/app/bin/job999.sh,[],60';
// 自 slot の実装版(facade が runner へ渡す。値は仕様の例示)
const IMPL_VERSIONS = { blue: 'blue-2.3.1', green: 'green-1.4.0' };

// ---- 置き場と配置 ----

// relay-gate を一時ディレクトリの /opt/relay-gate に配置する(1 Scenario で 1 回)
function deployedHome(world) {
  if (!world.retHome) {
    world.retHome = world.sandbox(h.SPEC_HOME);
    for (const dir of DEPLOY_DIRS) {
      fs.cpSync(path.join(h.FACADE_HOME, dir), path.join(world.retHome, dir), { recursive: true });
    }
    fs.accessSync(path.join(world.retHome, 'runners', RUNNER_SCRIPT_NAME), fs.constants.X_OK);
  }
  return world.retHome;
}

function defaultMap(world, slot) {
  return path.join(world.configDir, `${slot}-job-map.csv`);
}

// ジョブマップを書く(1 行目ヘッダー、2 行目以降は行。改行は LF)。続く Given の「行がある」は、最後に書いたジョブマップへ足す
function writeMap(world, file, header, rows) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, [header, ...rows].map((line) => `${line}\n`).join(''));
  world.retCurrentMap = file;
}

function appendRow(world, row) {
  assert.ok(world.retCurrentMap, 'a job map header should be given before a row');
  fs.appendFileSync(world.retCurrentMap, `${row}\n`);
}

function assertConfigDir(world) {
  assert.equal(world.configDir, world.sandbox(SPEC_CONFIG_DIR));
}

// ---- 起動 ----

// When の文言から runner IF の引数と、環境変数で渡すジョブマップの場所を読む
function parseInvocation(text) {
  const match = text.match(/--run-id (\S+) --job-id (\S+) --role (blue|green) --mode (foreground|background)(?: -- (.+?))? で起動する$/);
  assert.ok(match, `step should carry runner IF arguments: ${text}`);
  const [, runId, jobId, role, mode, rest] = match;
  const params = rest ? rest.split(' ') : [];
  const mapEnv = text.match(/環境変数 (?:BLUE|GREEN)_JOB_MAP_CSV=(\S+) と/);
  return {
    runId,
    jobId,
    role,
    mode,
    params,
    args: ['--run-id', runId, '--job-id', jobId, '--role', role, '--mode', mode, '--', ...params],
    specMapPath: mapEnv ? mapEnv[1] : null,
  };
}

function baseEnv(world) {
  // テストのプロセスの環境は引き継がない(ジョブマップの場所などが外から紛れ込まないようにする)
  const env = { PATH: process.env.PATH, RELAY_GATE_CONFIG_DIR: world.configDir };
  if (process.env.TMPDIR) {
    env.TMPDIR = process.env.TMPDIR;
  }
  return env;
}

// 標準の slot runner を実プロセスとして起動する。runner はプロセスの stdout / stderr に出さない(runner IF)ことも、起動のたびに確かめる。
// viaFacade: facade が渡すのと同じ環境変数で起動する(契約 commands「$BLUE_RUNNER / $GREEN_RUNNER」の environment。
//   ジョブマップの場所は、feature flag に書いた場所か、書いていなければ既定の場所を facade が必ず渡す)
function launchRunner(world, invocation, viaFacade) {
  const home = deployedHome(world);
  const env = baseEnv(world);
  let artifactRoot = path.join(home, 'var');
  let logDir = path.join(home, 'log');
  if (viaFacade) {
    artifactRoot = path.join(world.root, 'artifacts');
    logDir = path.join(world.root, 'logs');
    const slot = invocation.role.toUpperCase();
    Object.assign(env, {
      RELAY_GATE_ARTIFACT_ROOT: artifactRoot,
      RELAY_GATE_LOG_DIR: logDir,
      RAPID_CROSSCHECK_MODE: 'off',
      [`${slot}_IMPL`]: IMPL_VERSIONS[invocation.role],
      [`${slot}_JOB_MAP_CSV`]: invocation.specMapPath ? world.sandbox(invocation.specMapPath) : defaultMap(world, invocation.role),
    });
  }
  const roleDir = path.join(artifactRoot, 'facade', invocation.runId, invocation.role);
  if (viaFacade) {
    fs.mkdirSync(roleDir, { recursive: true });
  }
  const proc = spawnSync(path.join(home, 'runners', RUNNER_SCRIPT_NAME), invocation.args, { cwd: world.root, encoding: 'utf8', env });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  assert.equal(proc.stdout, '', `the runner should not write to stdout\n${proc.stdout}`);
  assert.equal(proc.stderr, '', `the runner should not write to stderr\n${proc.stderr}`);
  const run = { invocation, env, roleDir, logFile: path.join(logDir, `${RUNNER_SCRIPT_NAME}.log`), status: proc.status, resolved: null };
  world.retRuns = [...(world.retRuns || []), run];
  return run;
}

function lastRun(world) {
  assert.ok(world.retRuns && world.retRuns.length > 0, 'the runner should be started first');
  return world.retRuns[world.retRuns.length - 1];
}

function runOfRole(world, role) {
  const run = (world.retRuns || []).find((candidate) => candidate.invocation.role === role);
  assert.ok(run, `the ${role} runner should be started first`);
  return run;
}

// ---- 共通ライブラリの直接呼び出し ----
// 関数 resolve_execution_target <script> <run_id> <job_id> <role> [PARAM...] と、結果のグローバル変数
// (EXECUTION_TARGET_* / ARGUMENT_LIST。null は空文字)は仕様の定めのとおり
// (docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml の runner_resolve_library。判断記録 spec-decision-042)
const RESOLVE_SCRIPT = [
  'set -u',
  'source "$1"',
  'shift',
  'status=0',
  'resolve_execution_target "$@" || status=$?',
  "printf 'status=%s\\n' \"$status\"",
  "printf 'host=%s\\n' \"$EXECUTION_TARGET_HOST\"",
  "printf 'user=%s\\n' \"$EXECUTION_TARGET_USER\"",
  "printf 'script=%s\\n' \"$EXECUTION_TARGET_SCRIPT\"",
  "printf 'work_dir=%s\\n' \"$EXECUTION_TARGET_WORK_DIR\"",
  "printf 'hang_detect_limit_minutes=%s\\n' \"$EXECUTION_TARGET_HANG_DETECT_LIMIT_MINUTES\"",
  "printf 'credential_ref=%s\\n' \"$EXECUTION_TARGET_CREDENTIAL_REF\"",
  "printf 'map_version=%s\\n' \"$EXECUTION_TARGET_MAP_VERSION\"",
  "printf 'exec=%s\\n' \"$EXECUTION_TARGET_EXEC\"",
  'for value in ${EXECUTION_TARGET_FIXED_PARAMS[@]+"${EXECUTION_TARGET_FIXED_PARAMS[@]}"}; do printf \'fixed=%s\\n\' "$value"; done',
  'for value in ${ARGUMENT_LIST[@]+"${ARGUMENT_LIST[@]}"}; do printf \'arg=%s\\n\' "$value"; done',
].join('\n');

// 実プロセスの起動と同じ環境変数・同じ引数で、共通ライブラリの解決の関数を呼ぶ(1 起動につき 1 回)。
// 実行ログと成果物の置き場は、実プロセスの起動のものと分ける(実行ログの Then が見るのは実プロセスの実行ログだけにする)
function resolvedOf(world, run) {
  if (run.resolved) {
    return run.resolved;
  }
  const { invocation } = run;
  // 断片はファイルにして渡す(`bash -c` は、標準入力がソケットのとき利用者の ~/.bashrc を読むことがあり、テストの環境に左右される)
  const scriptFile = path.join(world.root, 'library-call.sh');
  fs.writeFileSync(scriptFile, `${RESOLVE_SCRIPT}\n`);
  const env = {
    ...run.env,
    RELAY_GATE_ARTIFACT_ROOT: path.join(world.root, 'library-artifacts'),
    RELAY_GATE_LOG_DIR: path.join(world.root, 'library-logs'),
  };
  const library = path.join(deployedHome(world), 'lib', 'runner-resolve.sh');
  const proc = spawnSync('bash', [scriptFile, library, RUNNER_SCRIPT_NAME, invocation.runId, invocation.jobId, invocation.role, ...invocation.params], {
    cwd: world.root,
    encoding: 'utf8',
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  assert.equal(proc.status, 0, `the library call should finish\n--- stdout ---\n${proc.stdout}\n--- stderr ---\n${proc.stderr}`);
  assert.equal(proc.stderr, '', `the library should not write to stderr\n${proc.stderr}`);
  const resolved = { fixed: [], args: [] };
  for (const line of proc.stdout.split('\n').slice(0, -1)) {
    const separator = line.indexOf('=');
    const name = line.slice(0, separator);
    const value = line.slice(separator + 1);
    if (name === 'fixed') {
      resolved.fixed.push(value);
    } else if (name === 'arg') {
      resolved.args.push(value);
    } else {
      resolved[name] = value;
    }
  }
  run.resolved = resolved;
  return resolved;
}

// ---- 確かめる ----

function readLog(run) {
  return fs.existsSync(run.logFile) ? fs.readFileSync(run.logFile, 'utf8') : '';
}

function dump(run) {
  return `--- exit code ---\n${run.status}\n--- execution log ---\n${readLog(run)}`;
}

// 実行ログの行(行形式 `{script} {run_id} {ローカル日時} {LEVEL} {message}`)のうち、この起動の run_id で LEVEL が一致するものの message
function logMessages(run, level) {
  const pattern = /^(\S+) (\S+) (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}) (\S+) (.*)$/;
  return readLog(run)
    .split('\n')
    .map((line) => line.match(pattern))
    .filter((match) => match && match[1] === RUNNER_SCRIPT_NAME && match[2] === run.invocation.runId && match[4] === level)
    .map((match) => match[5]);
}

function assertLogLine(run, level, message) {
  assert.ok(logMessages(run, level).includes(message), `execution log should include "${level} ${message}"\n${dump(run)}`);
}

// この起動の `job map resolved` の行(1 起動に 1 行)
function resolvedLogLine(run) {
  const { jobId, role } = run.invocation;
  const lines = logMessages(run, 'INFO').filter((message) => message.startsWith(`job map resolved job_id=${jobId} slot=${role} `));
  assert.equal(lines.length, 1, `execution log should include one "job map resolved" line\n${dump(run)}`);
  return lines[0];
}

// 実プロセスの runner と共通ライブラリの両方が解決に成功している。
// 解決フェーズの失敗は終了コード 2(検証エラー)。成功した後の runner の終わり方は後続の機能が決めるため、ここでは値を固定しない
function assertResolved(world, run) {
  const resolved = resolvedOf(world, run);
  assert.equal(resolved.status, '0', `resolve_execution_target should succeed: ${JSON.stringify(resolved)}`);
  assert.notEqual(run.status, 2, `the runner should not fail the resolve phase\n${dump(run)}`);
  // 実プロセスの実行ログの host が、共通ライブラリで受け取った host と同じ(同じ解決であること)
  const shownHost = resolved.host === '' ? '-' : resolved.host;
  assert.ok(resolvedLogLine(run).includes(` host=${shownHost} `), `the runner process should resolve the same host\n${dump(run)}`);
  return resolved;
}

// 「host=... user=... script=...」の並びを読む(null は、列が無い・値が空 = 空文字。runner_resolve_library の empty_values)
function expectedTarget(text) {
  const expected = {};
  for (const match of text.matchAll(/([a-z_]+)=([^\s()()]+)/g)) {
    expected[match[1]] = match[2] === 'null' ? '' : match[2];
  }
  return expected;
}

function assertTarget(world, run, text) {
  const resolved = assertResolved(world, run);
  const expected = expectedTarget(text);
  assert.ok(Object.keys(expected).length > 0, `step should list resolved values: ${text}`);
  for (const [name, value] of Object.entries(expected)) {
    if (name === 'fixed_params') {
      assert.deepEqual(resolved.fixed, JSON.parse(value), `resolved fixed_params: ${JSON.stringify(resolved)}`);
    } else {
      assert.equal(resolved[name], value, `resolved ${name}: ${JSON.stringify(resolved)}`);
    }
  }
  return resolved;
}

function assertExit(run, code) {
  assert.equal(run.status, code, `exit code\n${dump(run)}`);
}

function readResultFile(run, name) {
  return fs.readFileSync(path.join(run.roleDir, name), 'utf8');
}

function assertExitcodeFile(run, code) {
  assert.equal(readResultFile(run, 'exitcode.txt'), `${code}\n`, 'exitcode.txt should be one line');
}

// stderr.log の行(root の接頭辞を落として、feature の文言の絶対パスと比べられる形にする)
function assertStderrLogIncludes(world, run, expected) {
  const lines = world.unsandbox(readResultFile(run, 'stderr.log')).split('\n');
  assert.ok(lines.includes(expected), `stderr.log should include line "${expected}"\n--- stderr.log ---\n${lines.join('\n')}`);
}

// ---- Given: ヘッダーと行 ----

Given(literal('green-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version" である'), function () {
  writeMap(this, defaultMap(this, 'green'), `${HEADER_7},credential_ref,map_version`, []);
});

Given(literal('行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60,ssh-key-green,map-v3" がある'), function () {
  appendRow(this, 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60,ssh-key-green,map-v3');
});

Given(literal('green-job-map.csv のヘッダーが元資料どおりの "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" である'), function () {
  writeMap(this, defaultMap(this, 'green'), HEADER_7, []);
});

Given(literal('行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60" がある'), function () {
  appendRow(this, ROW_JOB001);
});

Given(literal('blue-job-map.csv のヘッダーが "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" である'), function () {
  writeMap(this, defaultMap(this, 'blue'), HEADER_LOCAL, []);
});

Given(literal('行 "JOB001,/var/app/work,/opt/app/bin/job001.sh,[],0" がある'), function () {
  appendRow(this, 'JOB001,/var/app/work,/opt/app/bin/job001.sh,[],0');
});

// Given はヘッダーに無い列だけを書いている。元資料どおりの 7 列のヘッダーと JOB001 の行を例示の値で補う
Given(literal('green-job-map.csv のヘッダーに credential_ref と map_version が無い'), function () {
  writeMap(this, defaultMap(this, 'green'), HEADER_7, [ROW_JOB001]);
});

// ---- Given: 固定引数 ----
// Given は fixed_params の値だけを書いている。ほかの列はローカル実行の行の例示の値で補う。
// 値にカンマと二重引用符を含むセルは、CSV の書き方(セルを二重引用符で囲み、中の二重引用符を二重化する)で書く

Given(literal('blue-job-map.csv の JOB001 行の fixed_params が ["p1","p2 p3"] である'), function () {
  writeMap(this, defaultMap(this, 'blue'), HEADER_LOCAL, ['JOB001,/var/app/work,/opt/app/bin/job001.sh,"[""p1"",""p2 p3""]",0']);
});

// セルの書き方そのものが Given に書かれている(そのまま書く)
Given(literal('blue-job-map.csv の JOB001 行の fixed_params セルが "[""p1"",""p2 p3""]" と書かれている'), function () {
  writeMap(this, defaultMap(this, 'blue'), HEADER_LOCAL, ['JOB001,/var/app/work,/opt/app/bin/job001.sh,"[""p1"",""p2 p3""]",0']);
});

Given(literal('blue-job-map.csv の JOB002 行の fixed_params が [] である'), function () {
  writeMap(this, defaultMap(this, 'blue'), HEADER_LOCAL, ['JOB002,/var/app/work,/opt/app/bin/job002.sh,[],0']);
});

// ---- Given: ジョブマップの場所 ----

Given(literal('RELAY_GATE_CONFIG_DIR は /etc/relay-gate である'), function () {
  assertConfigDir(this);
});

// feature-flag.env を読むのは facade(実装済みの前の機能)。runner が読むのは facade から受け取る環境変数だけなので、
// ここでは書かれた 1 行を置き、When が渡す環境変数の値がこの行の値と同じであることを When の側で確かめる
Given(literal('RELAY_GATE_CONFIG_DIR は /etc/relay-gate で、/etc/relay-gate/feature-flag.env に GREEN_JOB_MAP_CSV=/srv/relay-gate/maps/green-jobs.csv が定義されている'), function () {
  assertConfigDir(this);
  this.retFlagMapPath = `${SPEC_MAPS_DIR}/green-jobs.csv`;
  fs.writeFileSync(path.join(this.configDir, 'feature-flag.env'), `GREEN_JOB_MAP_CSV=${this.sandbox(this.retFlagMapPath)}\n`);
});

Given(literal('/srv/relay-gate/maps/green-jobs.csv に行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60" がある'), function () {
  writeMap(this, this.sandbox(`${SPEC_MAPS_DIR}/green-jobs.csv`), HEADER_7, [ROW_JOB001]);
});

Given(literal('/etc/relay-gate/green-job-map.csv に行 "JOB001,host-default-99,other,/var/default,/opt/default/job001.sh,[],60" がある'), function () {
  writeMap(this, defaultMap(this, 'green'), HEADER_7, ['JOB001,host-default-99,other,/var/default,/opt/default/job001.sh,[],60']);
});

// 未設定であること自体は、When が環境変数を渡さずに起動することで実現する(テストのプロセスの環境は引き継がない)
Given(literal('RELAY_GATE_CONFIG_DIR は /etc/relay-gate で、環境変数 GREEN_JOB_MAP_CSV は未設定である'), function () {
  assertConfigDir(this);
});

Given(literal('/etc/relay-gate/green-job-map.csv に行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60" がある'), function () {
  writeMap(this, defaultMap(this, 'green'), HEADER_7, [ROW_JOB001]);
});

// ---- Given: 標準の slot runner を両 slot に割り当てる ----

Given(literal('feature flag の BLUE_RUNNER と GREEN_RUNNER の両方に標準の slot runner /opt/relay-gate/runners/standard-runner.sh が割り当てられている'), function () {
  const runner = path.join(deployedHome(this), 'runners', RUNNER_SCRIPT_NAME);
  assert.equal(this.unsandbox(runner), '/opt/relay-gate/runners/standard-runner.sh');
  fs.writeFileSync(path.join(this.configDir, 'feature-flag.env'), `BLUE_RUNNER=${runner}\nGREEN_RUNNER=${runner}\n`);
});

Given(literal('blue のジョブマップのヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" で、行 "JOB001,,,/var/app/work,/opt/app/bin/job001.sh,[],0"(host と user が両方空)がある'), function () {
  writeMap(this, defaultMap(this, 'blue'), HEADER_7, ['JOB001,,,/var/app/work,/opt/app/bin/job001.sh,[],0']);
});

Given(literal('green のジョブマップのヘッダーが同じ 7 列で、行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60" がある'), function () {
  writeMap(this, defaultMap(this, 'green'), HEADER_7, [ROW_JOB001]);
});

// ---- Given: 解決に失敗するジョブマップ ----

// 「JOB999 の行が無い」: 例示の JOB001 の行だけがある
Given(literal('green-job-map.csv に job_id=JOB999 の行が無い'), function () {
  writeMap(this, defaultMap(this, 'green'), HEADER_7, [ROW_JOB001]);
});

Given(literal('/etc/relay-gate/green-job-map.csv が存在しない'), function () {
  assert.ok(!fs.existsSync(defaultMap(this, 'green')));
});

Given(literal('RELAY_GATE_CONFIG_DIR は /etc/relay-gate で、/etc/relay-gate/green-job-map.csv に JOB001 と JOB999 の行がある'), function () {
  assertConfigDir(this);
  writeMap(this, defaultMap(this, 'green'), HEADER_7, [ROW_JOB001, ROW_JOB999]);
});

Given(literal('/srv/relay-gate/maps/green-jobs.csv に JOB999 の行が無く、/srv/relay-gate/maps/missing-job-map.csv は存在しない'), function () {
  writeMap(this, this.sandbox(`${SPEC_MAPS_DIR}/green-jobs.csv`), HEADER_7, [ROW_JOB001]);
  assert.ok(!fs.existsSync(this.sandbox(`${SPEC_MAPS_DIR}/missing-job-map.csv`)));
});

// 1 行目はヘッダー、2 行目は例示の JOB001 の行、3 行目が JOB003
Given(literal('green-job-map.csv の 3 行目 JOB003 の fixed_params セルが "p1 p2"(配列でない)である'), function () {
  writeMap(this, defaultMap(this, 'green'), HEADER_7, [ROW_JOB001, 'JOB003,host-green-01,batch,/var/app/work,/opt/app/bin/job003.sh,p1 p2,60']);
});

Given(literal('green-job-map.csv の 2 行目 JOB004 の host が host-green-01 で user が空である'), function () {
  writeMap(this, defaultMap(this, 'green'), HEADER_7, ['JOB004,host-green-01,,/var/app/work,/opt/app/bin/job004.sh,[],60']);
});

// セルの書き方そのものが Given に書かれている(開いた二重引用符が行末まで閉じない)
Given(literal('green-job-map.csv の 2 行目の fixed_params セルが "[""p1"" で閉じていない'), function () {
  writeMap(this, defaultMap(this, 'green'), HEADER_7, ['JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[""p1"",60']);
});

// ---- When ----

// facade が渡すのと同じ環境変数で起動する(ジョブマップの場所は既定の場所)
for (const text of [
  'facade が green runner を --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する',
  'facade が blue runner を --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role blue --mode foreground -- a b で起動する',
  'facade が blue runner を --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role blue --mode foreground で起動する',
  'facade が blue runner を --run-id 20260830T113000-JOB002-5c7d9e0f --job-id JOB002 --role blue --mode foreground -- 20260830 で起動する',
  'facade が green runner を --run-id 20260830T113000-JOB999-a1b2c3d4 --job-id JOB999 --role green --mode background で起動する',
  'facade が green runner を --run-id 20260830T113000-JOB003-6d8e0f1a --job-id JOB003 --role green --mode background で起動する',
  'facade が green runner を --run-id 20260830T113000-JOB004-7e9f1a2b --job-id JOB004 --role green --mode background で起動する',
]) {
  When(literal(text), function () {
    launchRunner(this, parseInvocation(text), true);
  });
}

// feature flag に書いた場所を、facade が環境変数で渡す
for (const text of [
  'facade が green runner を環境変数 GREEN_JOB_MAP_CSV=/srv/relay-gate/maps/green-jobs.csv と --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する',
  'facade が green runner を環境変数 GREEN_JOB_MAP_CSV=/srv/relay-gate/maps/green-jobs.csv と --run-id 20260830T113000-JOB999-a1b2c3d4 --job-id JOB999 --role green --mode background で起動する',
  'facade が green runner を環境変数 GREEN_JOB_MAP_CSV=/srv/relay-gate/maps/missing-job-map.csv と --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する',
]) {
  When(literal(text), function () {
    const invocation = parseInvocation(text);
    assert.ok(invocation.specMapPath, `step should carry the job map location: ${text}`);
    if (this.retFlagMapPath) {
      // Given が feature-flag.env に書いた場所と、facade が渡す場所は同じ
      assert.equal(invocation.specMapPath, this.retFlagMapPath);
    }
    launchRunner(this, invocation, true);
  });
}

When(literal('green runner を facade を介さずに --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する'), function () {
  const run = launchRunner(
    this,
    parseInvocation('green runner を facade を介さずに --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background で起動する'),
    false,
  );
  assert.ok(!('GREEN_JOB_MAP_CSV' in run.env), 'GREEN_JOB_MAP_CSV should not be passed');
});

// 同じ実体(配置した標準の slot runner)を、role ごとに 1 回ずつ起動する(facade の起動順と同じく background の green が先)
When(literal('facade が標準の slot runner を --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role blue --mode foreground と --role green --mode background でそれぞれ起動する'), function () {
  const common = '--run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001';
  launchRunner(this, parseInvocation(`${common} --role green --mode background で起動する`), true);
  launchRunner(this, parseInvocation(`${common} --role blue --mode foreground で起動する`), true);
});

// ---- Then: 解決結果 ----

for (const text of [
  'runner は host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work hang_detect_limit_minutes=60 credential_ref=ssh-key-green map_version=map-v3 を解決する',
  'runner は host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work を解決する',
]) {
  Then(literal(text), function () {
    const resolved = assertTarget(this, lastRun(this), text);
    assert.equal(resolved.exec, 'ssh');
  });
}

Then(literal('列名の読み替えなしに host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work fixed_params=[] hang_detect_limit_minutes=60 が得られる'), function () {
  assertTarget(
    this,
    lastRun(this),
    'host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work fixed_params=[] hang_detect_limit_minutes=60',
  );
});

Then(literal('credential_ref と map_version は null として扱われる'), function () {
  assertTarget(this, lastRun(this), 'credential_ref=null map_version=null');
});

Then(literal('エラーにならず credential_ref=null map_version=null で解決する'), function () {
  assertTarget(this, lastRun(this), 'credential_ref=null map_version=null');
});

// 「SSH しない」のうち、この機能で決まるのは解決結果の実行方法(ローカル実行)まで。実際に実装を実行するのは後続の機能
Then(literal('runner は host=null user=null のローカル実行として解決する(SSH しない)'), function () {
  const resolved = assertTarget(this, lastRun(this), 'host=null user=null');
  assert.equal(resolved.exec, 'local');
});

Then(literal('role=blue の runner は host=null user=null のローカル実行として解決する(SSH しない)'), function () {
  const resolved = assertTarget(this, runOfRole(this, 'blue'), 'host=null user=null');
  assert.equal(resolved.exec, 'local');
});

Then(literal('role=green の runner は host=host-green-01 user=batch の SSH 実行として解決する'), function () {
  const resolved = assertTarget(this, runOfRole(this, 'green'), 'host=host-green-01 user=batch');
  assert.equal(resolved.exec, 'ssh');
});

// ---- Then: 固定引数と引数の並び ----
// この機能で決まるのは、解決フェーズが組み立てた引数の並び(固定引数 + PARAM)まで。実装へ実際に渡すのは後続の機能

Then(literal('実装へ渡す引数は 4 個で、順に p1 / "p2 p3" / a / b である'), function () {
  assert.deepEqual(assertResolved(this, lastRun(this)).args, ['p1', 'p2 p3', 'a', 'b']);
});

Then(literal('固定引数は p1 と "p2 p3" の 2 引数として得られ、空白とカンマは維持される'), function () {
  const resolved = assertResolved(this, lastRun(this));
  assert.deepEqual(resolved.fixed, ['p1', 'p2 p3']);
  assert.deepEqual(resolved.args, ['p1', 'p2 p3']);
});

Then(literal('実装へ渡す引数は 1 個で 20260830 である'), function () {
  assert.deepEqual(assertResolved(this, lastRun(this)).args, ['20260830']);
});

// ---- Then: 実行ログ ----

for (const message of [
  'job map resolved job_id=JOB001 slot=green host=host-green-01 map_version=map-v3',
  'job map resolved job_id=JOB001 slot=green host=host-green-01 map_version=-',
]) {
  Then(literal(`実行ログに "${message}" が出る`), function () {
    assertLogLine(lastRun(this), 'INFO', message);
  });
}

Then(literal('実行ログの "job map resolved" 行は map_version=- を含む'), function () {
  assert.ok(resolvedLogLine(lastRun(this)).endsWith(' map_version=-'), dump(lastRun(this)));
});

// ---- Then: 終了コードと成果物(解決の失敗) ----

Then(literal('runner は終了コード 2 で終了する'), function () {
  assertExit(lastRun(this), 2);
});

Then(literal('facade/20260830T113000-JOB999-a1b2c3d4/green/ に stdout.log(空)・stderr.log・exitcode.txt が揃う'), function () {
  const run = lastRun(this);
  assert.ok(run.roleDir.endsWith(path.join('facade', '20260830T113000-JOB999-a1b2c3d4', 'green')), run.roleDir);
  for (const name of ['stdout.log', 'stderr.log', 'exitcode.txt']) {
    assert.ok(fs.statSync(path.join(run.roleDir, name)).isFile(), `${name} should exist`);
  }
  // 実装は実行していないため stdout.log は空。書きかけの一時ファイルは残らない
  assert.equal(readResultFile(run, 'stdout.log'), '');
  assert.deepEqual(fs.readdirSync(run.roleDir).filter((name) => name.endsWith('.tmp')), []);
});

Then(literal('exitcode.txt の中身は "2" である'), function () {
  assertExitcodeFile(lastRun(this), 2);
});

Then(literal('runner は終了コード 2 で終了し、exitcode.txt の中身は "2" である'), function () {
  assertExit(lastRun(this), 2);
  assertExitcodeFile(lastRun(this), 2);
});

Then(literal('どちらの runner も終了コード 2 で終了し、exitcode.txt の中身は "2" である'), function () {
  assert.equal(this.retRuns.length, 2);
  for (const run of this.retRuns) {
    assertExit(run, 2);
    assertExitcodeFile(run, 2);
  }
});

for (const line of [
  'error: job_id=JOB999 not found in job map slot=green map=/etc/relay-gate/green-job-map.csv',
  'error: job map not found slot=green map=/etc/relay-gate/green-job-map.csv',
]) {
  Then(literal(`stderr.log に "${line}" が含まれる`), function () {
    assertStderrLogIncludes(this, lastRun(this), line);
  });
}

Then(literal('1 つ目の stderr.log に "error: job_id=JOB999 not found in job map slot=green map=/srv/relay-gate/maps/green-jobs.csv" が含まれる'), function () {
  assertStderrLogIncludes(this, this.retRuns[0], 'error: job_id=JOB999 not found in job map slot=green map=/srv/relay-gate/maps/green-jobs.csv');
});

Then(literal('2 つ目の stderr.log に "error: job map not found slot=green map=/srv/relay-gate/maps/missing-job-map.csv" が含まれる'), function () {
  assertStderrLogIncludes(this, this.retRuns[1], 'error: job map not found slot=green map=/srv/relay-gate/maps/missing-job-map.csv');
});

for (const line of [
  'error: fixed_params is not a json array of strings line=3 job_id=JOB003 value=p1 p2',
  'error: user is empty line=2 job_id=JOB004 value=',
  'error: csv quote is invalid line=2 path: /etc/relay-gate/green-job-map.csv',
]) {
  Then(literal(`runner は終了コード 2 で終了し、stderr.log に "${line}" が含まれる`), function () {
    assertExit(lastRun(this), 2);
    assertStderrLogIncludes(this, lastRun(this), line);
  });
}
