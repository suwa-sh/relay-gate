// facade.sh を実プロセスとして起動する統合テストの補助(UC BDD と ATDD の step が共有する。step も hook も登録しない)。
// 対象: UC「slot 実行モードを選択して runner を起動する」(uc_id=09730858)と、facade.sh を起動する先行 UC の Scenario。
// cucumber の読込対象のディレクトリ(features/uc/steps/)にあるが、@cucumber/cucumber を require しない。
// features/atdd/steps/ からは相対パスの require で使う(複製しない)。
//
// I/O 境界は実体で検証する:
//   - facade.sh(facade/bin/facade.sh)を実プロセスとして起動する
//   - runner は Scenario の一時ディレクトリ(World の root)に置く実スクリプトのテスト用 runner。
//     暫定注入・契約確定後に削除: started-at.txt / exitcode.txt を書く runner の中身は後続 UC の担当で、標準の slot runner は
//     --help 以外は仮の応答のため、テスト用 runner が代わりに書く
//     (根拠: docs/impl/latest/09730858/issues/20261118_091109_cross-uc-scenarios.md の 1〜3)
//   - 管理 DB は initdb + pg_ctl の一時 PostgreSQL(facade/features/steps/support/temp-postgres.js を再利用)。常設のサービスに接続しない
//   - 暫定注入・契約確定後に削除: 参照名(RAPID_DB_CONN_REF=mgmt-db)を一時の pg_service.conf(環境変数 PGSERVICEFILE)で
//     一時 PostgreSQL に結び付ける。参照名の解決方法は仕様に無く、実装者の前提 A-001
//     (docs/impl/latest/09730858/stages/attempt-3/S4_tier-impl.tier-facade.assumptions.yaml)に合わせている
// リポジトリの中にはファイルを書かない。書くのは World の root(Scenario ごとの一時ディレクトリ)の中だけ。
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const pg = require('../../../../facade/features/steps/support/temp-postgres');

const REPO_ROOT = path.resolve(__dirname, '../../../..');
const FACADE_HOME = path.join(REPO_ROOT, 'facade');
const FACADE_SH = path.join(FACADE_HOME, 'bin', 'facade.sh');
const CONN_REF = 'mgmt-db';
const RUN_ID_PATTERN = /^[0-9]{8}T[0-9]{6}-JOB001-[0-9a-f]{8}$/;
const SPEC_RUNNER_DIR = '/opt/relay-gate/runners';
const SPEC_HOME = '/opt/relay-gate';
// facade が background を待ってしまったときに、テストが長時間止まらないための打ち切り(判定の対象ではない)
const FACADE_SPAWN_TIMEOUT_MS = 120000;

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

function writeExecutable(file, body) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, body, { mode: 0o755 });
  return file;
}

function sleepMs(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

// facade の終了後も動く background の runner が書くファイルを待つ(上限 10 秒。出なければ失敗)
function waitForFile(file) {
  for (let i = 0; i < 100; i += 1) {
    if (fs.existsSync(file)) {
      return;
    }
    sleepMs(100);
  }
  throw new Error(`timed out waiting for ${file}`);
}

// ---- テスト用 runner ----
// --help には runner-if-version=1 を返す。runner IF で起動されると、自分の PID を <runner>.self、起動引数を <runner>.invoked
// (1 起動 1 行)、環境変数を <runner>.env に記録し、facade が作った role ディレクトリに started-at.txt を書く。
// behavior:
//   { kind: 'result', code, delaySec } … delaySec 秒待ってから Runner Result の 3 ファイル(exitcode.txt=code)を書いて終わる
//   { kind: 'hold', sec }              … PID を <runner>.pid に書いて exec sleep <sec>(exitcode.txt は書かない。cleanup が止める)
// role ディレクトリは作らない(作るのは facade。無ければ started-at.txt を書けず、判定が失敗する)
function runnerBody(behavior) {
  const lines = [
    '#!/usr/bin/env bash',
    'if [ "${1:-}" = "--help" ]; then echo "usage: test-runner.sh"; echo "runner-if-version=1"; exit 0; fi',
    'printf "%s\\n" "$$" >"$0.self"',
    'printf "%s\\n" "$*" >>"$0.invoked"',
    'env >"$0.env"',
    'run_id=""; role=""',
    'while [ "$#" -gt 0 ]; do case "$1" in --run-id) run_id="$2"; shift 2 ;; --role) role="$2"; shift 2 ;; --) break ;; *) shift ;; esac; done',
    'dir="$RELAY_GATE_ARTIFACT_ROOT/facade/$run_id/$role"',
    'date "+%Y-%m-%dT%H:%M:%S" >"$dir/started-at.txt"',
  ];
  if (behavior.kind === 'hold') {
    lines.push('printf "%s\\n" "$$" >"$0.pid"', ': >"$0.ready"', `exec sleep ${behavior.sec}`);
  } else {
    lines.push(': >"$0.ready"');
    if (behavior.delaySec) {
      lines.push(`sleep ${behavior.delaySec}`);
    }
    lines.push(
      ': >"$dir/stdout.log"; : >"$dir/stderr.log"',
      `echo ${behavior.code || 0} >"$dir/exitcode.txt.tmp" && mv "$dir/exitcode.txt.tmp" "$dir/exitcode.txt"`,
      ': >"$0.finished"',
    );
  }
  lines.push('exit 0');
  return lines.join('\n') + '\n';
}

const RESULT_OK = { kind: 'result', code: 0 };
const HOLD = { kind: 'hold', sec: 600 };

// テスト用 runner を置く(同じ場所なら置き直す)。置いた runner は world.fhRunners に控える(cleanup と「起動されない」の判定に使う)
function writeRunnerAt(world, file, behavior = RESULT_OK) {
  writeExecutable(file, runnerBody(behavior));
  world.fhRunners = world.fhRunners || {};
  world.fhRunners[file] = true;
  return file;
}

// slot のテスト用 runner の置き場(仕様の例示 /opt/relay-gate/runners/<slot>-runner.sh を root 配下へ写像)
function slotRunnerPath(world, slot) {
  return world.sandbox(`${SPEC_RUNNER_DIR}/${slot}-runner.sh`);
}

// feature-flag.env が指している slot の runner(解決後のパス)。相対パスは設定ファイル置き場が基準
function runnerOf(world, slot) {
  const value = world.flags[`${slot.toUpperCase()}_RUNNER`];
  return path.isAbsolute(value) ? value : `${world.configDir}/${value}`;
}

function setSlotBehavior(world, slot, behavior) {
  return writeRunnerAt(world, runnerOf(world, slot), behavior);
}

function invocations(file) {
  const log = `${file}.invoked`;
  return fs.existsSync(log) ? fs.readFileSync(log, 'utf8').split('\n').filter((l) => l.length > 0) : [];
}

// 起動されたはずの runner の起動引数。記録を書き終えた印を待ってから読む(facade は background を待たないため)
function startedInvocations(file) {
  waitForFile(`${file}.ready`);
  return invocations(file);
}

function parseEnv(text) {
  const env = {};
  for (const line of text.split('\n')) {
    const index = line.indexOf('=');
    if (index > 0) {
      env[line.slice(0, index)] = line.slice(index + 1);
    }
  }
  return env;
}

function recordedEnv(file) {
  waitForFile(`${file}.ready`);
  return parseEnv(fs.readFileSync(`${file}.env`, 'utf8'));
}

function runnerPid(file) {
  waitForFile(`${file}.ready`);
  return fs.readFileSync(`${file}.self`, 'utf8').trim();
}

function processAlive(pid) {
  try {
    process.kill(Number(pid), 0);
    return true;
  } catch (error) {
    return error.code === 'EPERM';
  }
}

function assertNoInvocations(world) {
  for (const file of Object.keys(world.fhRunners || {})) {
    assert.deepEqual(invocations(file), [], `runner should not be started: ${file}\n${dump(world)}`);
  }
}

// ---- feature-flag.env ----
// Given に書かれた KEY=value を world.flags に載せる。仕様の例示の絶対パス(/opt/relay-gate/… /etc/relay-gate/…)は root 配下へ写像する
function setFlags(world, text) {
  world.flags = world.flags || {};
  for (const [, key, value] of text.matchAll(/([A-Z_]+)=(\S*)/g)) {
    world.flags[key] = value.startsWith('/opt/relay-gate') || value.startsWith('/etc/relay-gate') ? world.sandbox(value) : value;
  }
}

// 仕様の Given が要点(mode など)だけを書いている Scenario の補い(書かれた値は変えない):
//   off でない slot の実装版と runner、off でない速報クロスチェックの runner / worker。書かれた runner のパスに実体が無ければ置く。
//   off の slot にも、起動されないことを観測するためのテスト用 runner を割り当てる。
// 根拠: docs/impl/latest/09730858/issues/20261118_091109_cross-uc-scenarios.md「仕様に書かれていない前提(step が補うもの)」
function supplementFlags(world) {
  const f = world.flags;
  const impls = { BLUE: 'v1', GREEN: 'v2' };
  for (const slot of ['BLUE', 'GREEN']) {
    if (f[`${slot}_MODE`] === undefined) {
      continue;
    }
    if (f[`${slot}_MODE`] !== 'off' && f[`${slot}_IMPL`] === undefined) {
      f[`${slot}_IMPL`] = impls[slot];
    }
    if (f[`${slot}_RUNNER`] === undefined) {
      f[`${slot}_RUNNER`] = slotRunnerPath(world, slot.toLowerCase());
    }
    const runner = runnerOf(world, slot.toLowerCase());
    if (!fs.existsSync(runner)) {
      writeRunnerAt(world, runner);
    }
  }
  if (f.RAPID_CROSSCHECK_MODE && f.RAPID_CROSSCHECK_MODE !== 'off') {
    for (const [key, name] of [
      ['RAPID_CROSSCHECK_RUNNER', 'rapid-crosscheck-runner.sh'],
      ['RAPID_CROSSCHECK_WORKER', 'rapid-crosscheck-worker.sh'],
    ]) {
      if (f[key] === undefined) {
        f[key] = world.sandbox(`${SPEC_HOME}/${name}`);
      }
      if (!fs.existsSync(f[key])) {
        writeExecutable(f[key], '#!/usr/bin/env bash\nexit 0\n');
      }
    }
  }
}

function flushFlags(world) {
  world.envPath = path.join(world.configDir, 'feature-flag.env');
  fs.writeFileSync(world.envPath, Object.entries(world.flags || {}).map(([k, v]) => `${k}=${v}\n`).join(''));
}

// ---- 管理 DB ----
// parallel_runs の status の履歴を残す表とトリガ(テストの観測用。INSERT と UPDATE の順を DB の側で記録する)
const STATUS_HISTORY_SQL =
  'CREATE TABLE test_parallel_run_status_history (seq serial PRIMARY KEY, op text, run_id text, status text);' +
  ' CREATE FUNCTION test_record_parallel_run_status() RETURNS trigger LANGUAGE plpgsql AS' +
  " $$ BEGIN INSERT INTO test_parallel_run_status_history (op, run_id, status) VALUES (TG_OP, NEW.run_id, NEW.status); RETURN NEW; END $$;" +
  ' CREATE TRIGGER test_parallel_run_status AFTER INSERT OR UPDATE ON parallel_runs FOR EACH ROW EXECUTE FUNCTION test_record_parallel_run_status();';

// 一時 PostgreSQL に Scenario 用のデータベースを作り、参照名 mgmt-db を pg_service.conf で結び付け、rapid-crosscheck.env を置く
// (既に Given が置いた rapid-crosscheck.env は書き換えない)
function startManagementDb(world) {
  if (world.db) {
    return;
  }
  world.db = pg.createDatabase();
  pg.query(world.db, STATUS_HISTORY_SQL);
  world.pgServiceFile = path.join(world.root, 'pg_service.conf');
  pg.writeServiceFile(world.pgServiceFile, CONN_REF, world.db);
  const rapidEnv = path.join(world.configDir, 'rapid-crosscheck.env');
  if (!fs.existsSync(rapidEnv)) {
    fs.writeFileSync(rapidEnv, `RAPID_DB_CONN_REF=${CONN_REF}\n`);
  }
}

// 管理 DB を止める(参照名の結び付けと rapid-crosscheck.env は残す。一時 PostgreSQL は次に使う Scenario が起動し直す)
function stopManagementDb(world) {
  startManagementDb(world);
  pg.stopTempPostgres();
  world.dbStopped = true;
}

function dbRows(world, sql) {
  return pg.query(world.db, sql);
}

// RDB クライアント CLI のパス(PATH の先頭)に psql という名前の記録用ラッパーを置く。
// 記録は <root>/psql.log(1 呼び出しの引数・SQL・PG で始まる環境変数)。管理 DB を用意した Scenario では記録の後に本物の psql へ
// 同じ引数と SQL を渡す。用意していない Scenario では渡さない(呼ばれたこと自体が判定の対象)
function installPsqlWrapper(world) {
  const realPsql = pg.which('psql');
  assert.ok(realPsql, 'environment: psql not found on PATH');
  world.fhFakeBin = path.join(world.root, 'fakebin');
  world.psqlLog = path.join(world.root, 'psql.log');
  const lines = [
    '#!/usr/bin/env bash',
    'sql="$(cat)"',
    `{ printf "args:"; printf " %s" "$@"; printf "\\n"; printf "%s\\n" "$sql"; env | grep "^PG" || true; printf -- "---\\n"; } >>'${world.psqlLog}'`,
  ];
  if (world.db) {
    lines.push(`exec '${realPsql}' "$@" <<<"$sql"`);
  } else {
    lines.push('exit 0');
  }
  writeExecutable(path.join(world.fhFakeBin, 'psql'), lines.join('\n') + '\n');
}

function psqlCalled(world) {
  return fs.existsSync(world.psqlLog);
}

// ---- facade.sh の起動 ----
// options: cwd(作業ディレクトリ)、facadeSh(起動する facade.sh。既定はリポジトリの facade/bin/facade.sh)
function facadeEnv(world, cwd) {
  flushFlags(world);
  installPsqlWrapper(world);
  world.artifactRoot = path.join(world.root, 'artifacts');
  world.logDir = path.join(world.root, 'logs');
  const env = {
    ...process.env,
    ...(world.extraEnv || {}),
    RELAY_GATE_CONFIG_DIR: world.configDir,
    RELAY_GATE_ARTIFACT_ROOT: world.artifactRoot,
    RELAY_GATE_LOG_DIR: world.logDir,
    PWD: cwd,
    PATH: `${world.fhFakeBin}:${process.env.PATH}`,
  };
  delete env.RELAY_GATE_HOME;
  if (world.pgServiceFile) {
    env.PGSERVICEFILE = world.pgServiceFile;
  }
  return env;
}

// facade.sh を起動して、終了を待たずに返す(実行中の様子を確かめる Scenario 用)。
// world.fhFacade = { child, exited(終了コードで解決する Promise) }。終わっていなければ cleanup が止める
function startFacade(world, args) {
  const cwd = world.root;
  const child = spawn(FACADE_SH, args, { cwd, env: facadeEnv(world, cwd), stdio: 'ignore' });
  const exited = new Promise((resolve, reject) => {
    child.on('error', reject);
    child.on('exit', (code) => resolve(code));
  });
  world.fhFacade = { child, exited };
  return world.fhFacade;
}

function runFacade(world, args, options = {}) {
  const cwd = options.cwd || world.root;
  const env = facadeEnv(world, cwd);
  const proc = spawnSync(options.facadeSh || FACADE_SH, args, { cwd, encoding: 'utf8', env, timeout: FACADE_SPAWN_TIMEOUT_MS });
  world.facadeEndedAtMs = Date.now();
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  world.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
  const runRoot = path.join(world.artifactRoot, 'facade');
  const runs = fs.existsSync(runRoot) ? fs.readdirSync(runRoot) : [];
  world.runIds = runs;
  world.runId = runs.length === 1 ? runs[0] : null;
  // facade の終了時点の成果物(role ディレクトリごとのファイル名)を控える
  world.filesAtFacadeExit = {};
  if (world.runId) {
    for (const slot of ['blue', 'green']) {
      const dir = path.join(runRoot, world.runId, slot);
      world.filesAtFacadeExit[slot] = fs.existsSync(dir) ? fs.readdirSync(dir) : null;
    }
  }
}

function runDir(world) {
  assert.ok(world.runId, `exactly one run directory expected under ${world.artifactRoot}/facade: ${world.runIds}\n${dump(world)}`);
  return path.join(world.artifactRoot, 'facade', world.runId);
}

function dump(world) {
  if (!world.result) {
    return '(facade.sh not started)';
  }
  return `--- status ${world.result.status}\n--- stdout ---\n${world.unsandbox(world.result.stdout)}\n--- stderr ---\n${world.unsandbox(world.result.stderr)}`;
}

// stderr の行(空行を除く。root の接頭辞を落として、feature の文言の絶対パスと比べられる形にする)
function stderrLines(world) {
  return world.unsandbox(world.result.stderr).split('\n').filter((line) => line.length > 0);
}

function assertExit(world, code) {
  assert.equal(world.result.status, code, `exit code\n${dump(world)}`);
}

function assertStderrIncludes(world, expected) {
  assert.ok(stderrLines(world).includes(expected), `stderr should include line "${expected}"\n${dump(world)}`);
}

function executionLog(world) {
  const file = path.join(world.logDir, 'facade.sh.log');
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
}

// 実行ログの `slot started` の行の位置(行の pid は、その slot のテスト用 runner が記録した自分の PID と同じ)
function slotStartedIndex(world, slot, mode) {
  const pid = runnerPid(runnerOf(world, slot));
  return executionLog(world).split('\n').findIndex((l) => l.includes(`slot started slot=${slot} mode=${mode} pid=${pid}`));
}

// background → foreground の順に起動されたこと(実行ログの行の順)
function assertStartedInOrder(world, first, second) {
  const a = slotStartedIndex(world, first.slot, first.mode);
  const b = slotStartedIndex(world, second.slot, second.mode);
  assert.ok(a >= 0 && b >= 0 && a < b, `${first.slot} must be started before ${second.slot}\n${executionLog(world)}`);
}

// facade が待ったのは foreground の PID だけ: 実行ログの待機の行は foreground の PID の 1 行だけで、
// facade の終了後も background の runner は動いている
function assertWaitedOnly(world, foreground, background) {
  assertExit(world, 0);
  const waits = executionLog(world).split('\n').filter((l) => l.includes(' INFO waiting foreground '));
  assert.equal(waits.length, 1, `exactly one waiting line expected\n${executionLog(world)}`);
  assert.ok(waits[0].endsWith(` waiting foreground slot=${foreground} pid=${runnerPid(runnerOf(world, foreground))}`), waits[0]);
  const backgroundPid = runnerPid(runnerOf(world, background));
  assert.ok(processAlive(backgroundPid), `${background} runner (pid ${backgroundPid}) should still be running after facade exit`);
  assert.ok(
    !(world.filesAtFacadeExit[background] || []).includes('exitcode.txt'),
    `${background}/exitcode.txt must not exist when facade exits`,
  );
}

// ---- 後始末 ----
// 長く動くテスト用 runner(hold)が記録した PID を止める(プロセスを残さない)
function cleanup(world) {
  if (world.fhFacade && world.fhFacade.child.exitCode === null && world.fhFacade.child.signalCode === null) {
    world.fhFacade.child.kill('SIGKILL');
  }
  for (const file of Object.keys(world.fhRunners || {})) {
    for (const record of [`${file}.pid`]) {
      if (!fs.existsSync(record)) {
        continue;
      }
      try {
        process.kill(Number(fs.readFileSync(record, 'utf8').trim()), 'SIGKILL');
      } catch {
        // 既に終わっている
      }
    }
  }
}

function stopDatabase() {
  pg.stopTempPostgres();
}

module.exports = {
  REPO_ROOT,
  FACADE_HOME,
  FACADE_SH,
  CONN_REF,
  RUN_ID_PATTERN,
  SPEC_HOME,
  RESULT_OK,
  HOLD,
  literal,
  writeExecutable,
  waitForFile,
  writeRunnerAt,
  slotRunnerPath,
  runnerOf,
  setSlotBehavior,
  invocations,
  startedInvocations,
  parseEnv,
  recordedEnv,
  runnerPid,
  processAlive,
  assertNoInvocations,
  setFlags,
  supplementFlags,
  flushFlags,
  startManagementDb,
  stopManagementDb,
  dbRows,
  psqlCalled,
  startFacade,
  runFacade,
  runDir,
  dump,
  stderrLines,
  assertExit,
  assertStderrIncludes,
  executionLog,
  assertStartedInOrder,
  assertWaitedOnly,
  cleanup,
  stopDatabase,
};
