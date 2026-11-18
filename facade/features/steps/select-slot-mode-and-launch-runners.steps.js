// tier BDD(③)step definition。tier-facade / uc_id=09730858(slot 実行モードを選択して runner を起動する)。
// source: docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/tier-facade.md#ティア完了条件(BDD)
// S2 の skeleton の step 文言(feature から転写したリテラル)を完全一致の正規表現で受け、S4 で実装した。
// このファイルが定義するのは、他 UC の step ファイルに定義の無い step だけ(同じ文言を再定義すると ambiguous になる)。
// 既存 step の再利用: 「終了コード 2 で stderr に "error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground" が出る」
// (configure-feature-flags.steps.js。World の this.result = { status, stdout, stderr } を読む)。
// World(workDir / configDir)と Before / After は configure-feature-flags.steps.js のものを使う。このファイルの After / AfterAll は、
// この UC の Scenario が World に残した後始末の対象(長く動く runner スタブの PID、一時 PostgreSQL)があるときだけ働く。
// I/O 境界は実体で検証する:
//   - facade.sh(bin/facade.sh)を実プロセスとして起動する。runner は一時ディレクトリに置く実スクリプトのスタブ
//     (標準の runner facade/runners/standard-runner.sh は --help 以外は仮の応答のため使わない)
//   - 管理 DB は initdb + pg_ctl で起動する一時 PostgreSQL(support/temp-postgres.js)。参照名 mgmt-db は一時ディレクトリの
//     pg_service.conf(環境変数 PGSERVICEFILE)で接続先に結び付ける(RDB クライアントの呼び出し方は AssumptionRecord に記録した前提)
//   - Given が mode などの要点だけを書いている Scenario は、検証を通る値(実装版・runner スタブ・速報の runner / worker のスタブ・
//     rapid-crosscheck.env)を補う(docs/impl/latest/09730858/issues/20261118_091109_cross-uc-scenarios.md「仕様に書かれていない前提」)
// リポジトリの中にはファイルを書かない。書くのは Before が作る一時ディレクトリ(this.workDir)の中だけ。
'use strict';
const { Given, Then, When, After, AfterAll } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const pg = require('./support/temp-postgres');

const FACADE_HOME = path.resolve(__dirname, '../..');
const FACADE_SH = path.join(FACADE_HOME, 'bin', 'facade.sh');
const VALIDATE_CONFIG = path.join(FACADE_HOME, 'bin', 'validate-config.sh');
const CONN_REF = 'mgmt-db';
const RUN_ID_PATTERN = /^[0-9]{8}T[0-9]{6}-JOB001-[0-9a-f]{8}$/;

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

// ---- runner スタブ ----
// 記録用スタブ: --help には runner-if-version=1 を返す(validate-config.sh の問い合わせを起動記録に数えない)。
// runner IF で起動されると、自分の PID を <スタブ>.self、起動引数を <スタブ>.invoked(1 起動 1 行)、環境変数を <スタブ>.env に記録する。
// behavior: exit0 … Runner Result の 3 ファイル(exitcode.txt=0)を書いて終わる
//           sleep30 … PID を <スタブ>.pid に書いて exec sleep 30(exitcode.txt は書かない。After が止める)
//           fail2db … exitcode.txt=2 を書き、自分の slot_executions 行を RUNNING → FAILED に更新して、<スタブ>.done を書いて終わる
function stubBody(behavior, eventLog) {
  const lines = [
    '#!/usr/bin/env bash',
    'if [ "${1:-}" = "--help" ]; then echo "usage: stub-runner.sh"; echo "runner-if-version=1"; exit 0; fi',
    'printf "%s\\n" "$$" >"$0.self"',
  ];
  if (eventLog) {
    lines.push(`printf "launch %s pid=%s\\n" "$(basename "$0")" "$$" >>'${eventLog}'`);
  }
  lines.push(
    'printf "%s\\n" "$*" >>"$0.invoked"',
    'env >"$0.env"',
    'run_id=""; role=""',
    'while [ "$#" -gt 0 ]; do case "$1" in --run-id) run_id="$2"; shift 2 ;; --role) role="$2"; shift 2 ;; --) break ;; *) shift ;; esac; done',
    'dir="$RELAY_GATE_ARTIFACT_ROOT/facade/$run_id/$role"',
  );
  // 記録を書き終えた印(<スタブ>.ready)は記録の最後に書く。facade は background を待たないため、読む側はこの印を待ってから記録を読む
  if (behavior === 'sleep30') {
    lines.push('printf "%s\\n" "$$" >"$0.pid"', ': >"$0.ready"', 'exec sleep 30');
  } else if (behavior === 'fail2db') {
    lines.push(
      ': >"$0.ready"',
      ': >"$dir/stdout.log"; : >"$dir/stderr.log"; echo 2 >"$dir/exitcode.txt"',
      `"$REAL_PSQL" -X -q -A -t -v ON_ERROR_STOP=1 -v run_id="$run_id" -v slot="$role" "service=${CONN_REF}" -f - <<'SQL' >"$0.updated"`,
      "UPDATE slot_executions SET status = 'FAILED', exit_code = 2, completed_at = '2026-08-30T11:30:00' WHERE run_id = :'run_id' AND slot = :'slot' AND status = 'RUNNING' RETURNING slot;",
      'SQL',
      ': >"$0.done"',
    );
  } else {
    lines.push(': >"$0.ready"', ': >"$dir/stdout.log"; : >"$dir/stderr.log"; echo 0 >"$dir/exitcode.txt"');
  }
  lines.push('exit 0');
  return lines.join('\n') + '\n';
}

function writeExecutable(file, body) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, body, { mode: 0o755 });
  return file;
}

function stubDir(world) {
  return path.join(world.workDir, 'stubs');
}

// 記録用スタブを置く(同じ名前なら置き直す)。置いたスタブは world.stubs に控える
function writeStub(world, name, behavior = 'exit0', dir = stubDir(world)) {
  const file = writeExecutable(path.join(dir, name), stubBody(behavior, world.eventLog));
  world.stubs = world.stubs || {};
  world.stubs[file] = true;
  return file;
}

// 何も記録しない実行可能なスタブ(速報クロスチェックの runner / worker)
function writePlainExecutable(world, name, dir = stubDir(world)) {
  return writeExecutable(path.join(dir, name), '#!/usr/bin/env bash\nexit 0\n');
}

function invocations(file) {
  const log = `${file}.invoked`;
  return fs.existsSync(log) ? fs.readFileSync(log, 'utf8').split('\n').filter((l) => l.length > 0) : [];
}

// 起動されたはずのスタブの起動引数。記録を書き終えた印を待ってから読む
function startedInvocations(file) {
  waitForFile(`${file}.ready`);
  return invocations(file);
}

function recordedEnv(file) {
  waitForFile(`${file}.ready`);
  const env = {};
  for (const line of fs.readFileSync(`${file}.env`, 'utf8').split('\n')) {
    const index = line.indexOf('=');
    if (index > 0) {
      env[line.slice(0, index)] = line.slice(index + 1);
    }
  }
  return env;
}

// ---- feature-flag.env ----
// world.flags(KEY → 値。書いた順)を RELAY_GATE_CONFIG_DIR/feature-flag.env に書く
function flushFlags(world) {
  const lines = (world.flagLines || []).concat(Object.entries(world.flags || {}).map(([k, v]) => `${k}=${v}`));
  fs.writeFileSync(path.join(world.configDir, 'feature-flag.env'), lines.map((l) => `${l}\n`).join(''));
}

// Given に書かれた KEY=value を world.flags に載せる
function setFlags(world, text) {
  world.flags = world.flags || {};
  for (const [, key, value] of text.matchAll(/([A-Z_]+)=(\S*)/g)) {
    world.flags[key] = value;
  }
}

// mode だけを書いた Given の補い: off でない slot の実装版と runner、off でない速報の runner / worker(書かれた値は変えない)
function supplementFlags(world) {
  const f = world.flags;
  const impls = { BLUE: 'v1', GREEN: 'v2' };
  for (const slot of ['BLUE', 'GREEN']) {
    if (f[`${slot}_MODE`] && f[`${slot}_MODE`] !== 'off') {
      if (f[`${slot}_IMPL`] === undefined) {
        f[`${slot}_IMPL`] = impls[slot];
      }
      if (f[`${slot}_RUNNER`] === undefined) {
        f[`${slot}_RUNNER`] = writeStub(world, `${slot.toLowerCase()}-runner.sh`);
      }
    }
  }
  if (f.RAPID_CROSSCHECK_MODE && f.RAPID_CROSSCHECK_MODE !== 'off') {
    if (f.RAPID_CROSSCHECK_RUNNER === undefined) {
      f.RAPID_CROSSCHECK_RUNNER = writePlainExecutable(world, 'rapid-crosscheck-runner.sh');
    }
    if (f.RAPID_CROSSCHECK_WORKER === undefined) {
      f.RAPID_CROSSCHECK_WORKER = writePlainExecutable(world, 'rapid-crosscheck-worker.sh');
    }
  }
}

// ---- 管理 DB ----
// 一時 PostgreSQL に Scenario 用のデータベースを作り、参照名 mgmt-db を pg_service.conf で結び付け、rapid-crosscheck.env を置く
function startManagementDb(world) {
  world.db = pg.createDatabase();
  world.pgServiceFile = path.join(world.workDir, 'pg_service.conf');
  pg.writeServiceFile(world.pgServiceFile, CONN_REF, world.db);
  const rapidEnv = path.join(world.configDir, 'rapid-crosscheck.env');
  if (!fs.existsSync(rapidEnv)) {
    fs.writeFileSync(rapidEnv, `RAPID_DB_CONN_REF=${CONN_REF}\n`);
  }
}

function dbRows(world, sql) {
  return pg.query(world.db, sql);
}

// RDB クライアント CLI のパス(PATH の先頭)に psql という名前のラッパーを置く。
// forward: true なら記録の後に本物の psql へ同じ引数と SQL を渡す。記録は <workDir>/psql.log(1 呼び出しの引数・SQL・環境変数)と、
// world.eventLog(SQL の最初の文と -v の値を 1 行で。runner スタブの起動記録と同じファイルに順に残る)
function writePsqlWrapper(world, forward) {
  const realPsql = pg.which('psql');
  world.fakeBin = path.join(world.workDir, 'fakebin');
  world.psqlLog = path.join(world.workDir, 'psql.log');
  const lines = [
    '#!/usr/bin/env bash',
    'sql="$(cat)"',
    `{ printf "args:"; printf " %s" "$@"; printf "\\n"; printf "%s\\n" "$sql"; env | grep "^PG" || true; printf -- "---\\n"; } >>'${world.psqlLog}'`,
  ];
  if (world.eventLog) {
    lines.push(
      'vars=""; prev=""; for a in "$@"; do if [ "$prev" = "-v" ]; then vars+=" $a"; fi; prev="$a"; done',
      `printf "sql %s |%s\\n" "$(printf "%s\\n" "$sql" | grep -v "^\\\\\\\\echo" | head -1)" "$vars" >>'${world.eventLog}'`,
    );
  }
  if (forward) {
    lines.push(`exec '${realPsql}' "$@" <<<"$sql"`);
  } else {
    lines.push('exit 0');
  }
  writeExecutable(path.join(world.fakeBin, 'psql'), lines.join('\n') + '\n');
}

// ---- facade.sh の起動 ----
function runFacade(world, args, cwd = world.workDir) {
  flushFlags(world);
  world.artifactRoot = path.join(world.workDir, 'artifacts');
  world.logDir = path.join(world.workDir, 'logs');
  const env = {
    ...process.env,
    ...(world.extraEnv || {}),
    RELAY_GATE_CONFIG_DIR: world.configDir,
    RELAY_GATE_ARTIFACT_ROOT: world.artifactRoot,
    RELAY_GATE_LOG_DIR: world.logDir,
    PWD: cwd,
  };
  if (world.pgServiceFile) {
    env.PGSERVICEFILE = world.pgServiceFile;
  }
  if (world.fakeBin) {
    env.PATH = `${world.fakeBin}:${env.PATH}`;
  }
  env.REAL_PSQL = pg.which('psql') || 'psql';
  const proc = spawnSync(FACADE_SH, args, { cwd, encoding: 'utf8', env });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  world.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
  const runRoot = path.join(world.artifactRoot, 'facade');
  const runs = fs.existsSync(runRoot) ? fs.readdirSync(runRoot) : [];
  world.runId = runs.length === 1 ? runs[0] : null;
}

function dump(world) {
  return `--- status ${world.result.status}\n--- stdout ---\n${world.result.stdout}\n--- stderr ---\n${world.result.stderr}`;
}

function stderrLines(world) {
  return world.result.stderr.split('\n').filter((line) => line.length > 0);
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

function assertNoInvocations(world) {
  for (const file of Object.keys(world.stubs || {})) {
    assert.deepEqual(invocations(file), [], `runner stub should not be started: ${file}\n${dump(world)}`);
  }
}

function assertNoRunDirectory(world) {
  const runRoot = path.join(world.artifactRoot, 'facade');
  const entries = fs.existsSync(runRoot) ? fs.readdirSync(runRoot) : [];
  assert.deepEqual(entries, [], `no directory expected under ${runRoot}`);
}

function expandConfigDir(world, text) {
  return text.split('<RELAY_GATE_CONFIG_DIR>').join(world.configDir);
}

function stubPid(file) {
  waitForFile(`${file}.ready`);
  return fs.readFileSync(`${file}.self`, 'utf8').trim();
}

function sleepMs(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

// facade の終了後も動く runner スタブが書く印を待つ(上限 10 秒。出なければ失敗)
function waitForFile(file) {
  for (let i = 0; i < 100; i += 1) {
    if (fs.existsSync(file)) {
      return;
    }
    sleepMs(100);
  }
  throw new Error(`timed out waiting for ${file}`);
}

// 作業ディレクトリ work(RELAY_GATE_CONFIG_DIR とは別)
function workCwd(world) {
  const dir = path.join(world.workDir, 'work');
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

// ---- 後始末(この UC の Scenario が控えたものだけ) ----
// 長く動くスタブ(sleep30)が記録した PID を、後始末の時点で集めて止める(runner が遅れて書いた PID も取りこぼさない)
After(function () {
  for (const file of Object.keys(this.stubs || {})) {
    if (!fs.existsSync(`${file}.pid`)) {
      continue;
    }
    try {
      process.kill(Number(fs.readFileSync(`${file}.pid`, 'utf8').trim()), 'SIGTERM');
    } catch {
      // 既に終わっている
    }
  }
});

AfterAll(function () {
  pg.stopTempPostgres();
});

// ---- facade_sh は background を先に起動し foreground だけを wait する ----

Given(literal('RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2 BLUE_RUNNER=<記録用スタブ runner> GREEN_RUNNER=<記録用スタブ runner> がある'), function () {
  setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2');
  this.flags.BLUE_RUNNER = writeStub(this, 'blue-runner.sh');
  this.flags.GREEN_RUNNER = writeStub(this, 'green-runner.sh');
});

Given(literal('スタブ runner は起動引数・環境変数・起動時刻をファイルに記録し、green は 30 秒 sleep、blue は exitcode.txt に 0 を書いて即終了する'), function () {
  writeStub(this, 'green-runner.sh', 'sleep30');
  writeStub(this, 'blue-runner.sh', 'exit0');
});

When(literal('`facade.sh JOB001 20260830 full` を実行する'), function () {
  runFacade(this, ['JOB001', '20260830', 'full']);
});

Then(literal('終了コード 0 で終了し、green の起動記録が blue より先である'), function () {
  assertExit(this, 0);
  // 起動の順は facade の実行ログの slot started の行の順で見る(行の pid は各スタブが記録した自分の PID と同じ。
  // スタブの中で書く記録どうしの前後は、起動直後のプロセスの進み方で入れ替わりうるため使わない)
  const log = executionLog(this).split('\n');
  const green = log.findIndex((l) => l.includes(`slot started slot=green mode=background pid=${stubPid(this.flags.GREEN_RUNNER)}`));
  const blue = log.findIndex((l) => l.includes(`slot started slot=blue mode=foreground pid=${stubPid(this.flags.BLUE_RUNNER)}`));
  assert.ok(green >= 0 && blue >= 0 && green < blue, `green must be started before blue\n${log.join('\n')}`);
});

Then(literal('green の起動引数は "--run-id <run_id> --job-id JOB001 --role green --mode background -- 20260830 full" である'), function () {
  assert.deepEqual(startedInvocations(this.flags.GREEN_RUNNER), [`--run-id ${this.runId} --job-id JOB001 --role green --mode background -- 20260830 full`]);
});

Then(literal('green の記録した環境変数に GREEN_IMPL=v2 と RAPID_CROSSCHECK_MODE=off があり RAPID_CROSSCHECK_RUNNER は無い'), function () {
  const env = recordedEnv(this.flags.GREEN_RUNNER);
  assert.equal(env.GREEN_IMPL, 'v2');
  assert.equal(env.RAPID_CROSSCHECK_MODE, 'off');
  assert.equal(env.RAPID_CROSSCHECK_RUNNER, undefined);
});

Then(literal('<run_id> は正規表現 ^[0-9]{8}T[0-9]{6}-JOB001-[0-9a-f]{8}$ に一致する'), function () {
  assert.match(this.runId || '', RUN_ID_PATTERN);
});

Then(literal('facade の終了時に green のスタブはまだ実行中である'), function () {
  waitForFile(`${this.flags.GREEN_RUNNER}.ready`);
  const pid = Number(fs.readFileSync(`${this.flags.GREEN_RUNNER}.pid`, 'utf8').trim());
  assert.doesNotThrow(() => process.kill(pid, 0), `green stub (pid ${pid}) should still be running`);
});

// ---- facade_sh は両 slot foreground を終了コード 2 で拒否する ----

Given(literal('feature-flag.env に BLUE_MODE=foreground GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off がある'), function () {
  setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off');
  supplementFlags(this);
});

When(literal('`facade.sh JOB001` を実行する'), function () {
  runFacade(this, ['JOB001']);
});

Then(literal('スタブ runner の起動記録は存在しない'), function () {
  assertNoInvocations(this);
});

Then(literal('RELAY_GATE_ARTIFACT_ROOT/facade/ 配下にディレクトリは作成されない'), function () {
  assertNoRunDirectory(this);
});

// ---- facade_sh は RAPID_CROSSCHECK_MODE=background で parallel_runs を STARTED から RUNNING へ更新する ----

Given(literal('feature-flag.env に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=background BLUE_IMPL=v1 RAPID_CROSSCHECK_RUNNER=<実行可能なスタブ> RAPID_CROSSCHECK_WORKER=<実行可能なスタブ> がある'), function () {
  setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=background BLUE_IMPL=v1');
  this.flags.RAPID_CROSSCHECK_RUNNER = writePlainExecutable(this, 'rapid-crosscheck-runner.sh');
  this.flags.RAPID_CROSSCHECK_WORKER = writePlainExecutable(this, 'rapid-crosscheck-worker.sh');
  supplementFlags(this);
});

Given(literal('管理 DB が起動している'), function () {
  startManagementDb(this);
});

Then(literal('parallel_runs に run_id job_id=JOB001 status=RUNNING parameters=[] の行が 1 件ある'), function () {
  assertExit(this, 0);
  const rows = dbRows(this, 'SELECT run_id, job_id, status, parameters FROM parallel_runs');
  assert.deepEqual(rows, [`${this.runId}|JOB001|RUNNING|[]`]);
});

Then(literal('parallel_runs.run_id は成果物ディレクトリ facade/<run_id>/ の名前と同じ値である'), function () {
  const rows = dbRows(this, 'SELECT run_id FROM parallel_runs');
  assert.equal(rows.length, 1);
  assert.ok(fs.statSync(path.join(this.artifactRoot, 'facade', rows[0])).isDirectory());
  assert.equal(rows[0], this.runId);
});

Then(literal('実行ログに "parallel_run status changed from=STARTED to=RUNNING run_id=<run_id>" が出る'), function () {
  assert.ok(
    executionLog(this).split('\n').some((l) => l.endsWith(` INFO parallel_run status changed from=STARTED to=RUNNING run_id=${this.runId}`)),
    executionLog(this),
  );
});

Then(literal('実行ログの "feature flag loaded" 行に "blue_impl=v1" と "operation_mode=custom" が含まれ "config_version=" は含まれない'), function () {
  const line = executionLog(this).split('\n').find((l) => l.includes(' INFO feature flag loaded '));
  assert.ok(line, executionLog(this));
  assert.ok(line.includes('blue_impl=v1'), line);
  assert.ok(line.includes('operation_mode=custom'), line);
  assert.ok(!line.includes('config_version='), line);
});

Then(literal('blue のスタブ runner が記録した環境変数に RAPID_CROSSCHECK_RUNNER=<実行可能なスタブ> がある'), function () {
  assert.equal(recordedEnv(this.flags.BLUE_RUNNER).RAPID_CROSSCHECK_RUNNER, this.flags.RAPID_CROSSCHECK_RUNNER);
});

// ---- facade_sh は RAPID_CROSSCHECK_MODE=foreground を background と同じに扱う ----

Given(literal('feature-flag.env に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=foreground があり管理 DB が起動している'), function () {
  setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=foreground');
  supplementFlags(this);
  startManagementDb(this);
});

Then(literal('parallel_runs に run_id の行が status=RUNNING で 1 件あり rapid_runs に completion_status=PENDING の行が 1 件ある'), function () {
  assertExit(this, 0);
  assert.deepEqual(dbRows(this, 'SELECT run_id, status FROM parallel_runs'), [`${this.runId}|RUNNING`]);
  assert.deepEqual(dbRows(this, 'SELECT run_id, completion_status FROM rapid_runs'), [`${this.runId}|PENDING`]);
});

// ---- facade_sh は runner 起動前に slot_executions を pid=NULL で INSERT し起動後に pid を更新する ----

Given(literal('feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background があり管理 DB が起動している'), function () {
  this.eventLog = path.join(this.workDir, 'events.log');
  setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background');
  supplementFlags(this);
  startManagementDb(this);
});

Given(literal('RDB クライアント CLI のパスに SQL を順序つきで記録して実 DB へ転送するラッパーを置く'), function () {
  writePsqlWrapper(this, true);
});

Given(literal('green のスタブ runner は起動直後に exitcode.txt=2 を書いて終了し、自分の slot_executions 行を RUNNING → FAILED に更新する'), function () {
  writeStub(this, 'green-runner.sh', 'fail2db');
});

Then(literal('記録された SQL は slot_executions の INSERT(slot=green, pid NULL)が green runner 起動より前で、pid の UPDATE がその後である'), function () {
  assertExit(this, 0);
  waitForFile(`${this.flags.GREEN_RUNNER}.done`);
  const events = fs.readFileSync(this.eventLog, 'utf8').split('\n').filter((l) => l.length > 0);
  const insert = events.findIndex((l) => l.startsWith('sql INSERT INTO slot_executions ') && l.includes(' slot=green'));
  const launch = events.findIndex((l) => l.startsWith('launch green-runner.sh '));
  const greenPid = stubPid(this.flags.GREEN_RUNNER);
  const update = events.findIndex((l) => l.startsWith('sql UPDATE slot_executions SET pid ') && l.includes(' slot=green') && l.includes(` pid=${greenPid}`));
  assert.ok(insert >= 0 && launch > insert, `INSERT(slot=green) must precede the green runner start\n${events.join('\n')}`);
  // pid の UPDATE は起動した green runner 自身の PID を持つ(起動の後にしか書けない)。記録の上でも INSERT の後にある
  assert.ok(update > insert, `pid UPDATE(slot=green) must follow the INSERT\n${events.join('\n')}`);
  assert.ok(!events[insert].includes(' pid='), `INSERT must not carry a pid\n${events[insert]}`);
});

Then(literal('最終的に slot_executions の slot=green の行は status=FAILED exit_code=2 で pid が設定されている(runner 側の終端 UPDATE が 0 件にならない)'), function () {
  waitForFile(`${this.flags.GREEN_RUNNER}.done`);
  assert.equal(fs.readFileSync(`${this.flags.GREEN_RUNNER}.updated`, 'utf8').trim(), 'green', 'runner terminal UPDATE must hit 1 row');
  assert.deepEqual(dbRows(this, "SELECT status, exit_code, pid FROM slot_executions WHERE slot = 'green'"), [
    `FAILED|2|${stubPid(this.flags.GREEN_RUNNER)}`,
  ]);
});

// ---- facade_sh は RAPID_CROSSCHECK_MODE=background で rapid-crosscheck.env が無ければ終了コード 2 で終了する ----

Given(literal('feature-flag.env に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=background BLUE_IMPL=v1 BLUE_RUNNER=<記録用スタブ runner> RAPID_CROSSCHECK_RUNNER=<実行可能なスタブ> RAPID_CROSSCHECK_WORKER=<実行可能なスタブ> がある(feature-flag.env のキーごとの検査を通る設定)'), function () {
  setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=background BLUE_IMPL=v1');
  this.flags.BLUE_RUNNER = writeStub(this, 'blue-runner.sh');
  this.flags.RAPID_CROSSCHECK_RUNNER = writePlainExecutable(this, 'rapid-crosscheck-runner.sh');
  this.flags.RAPID_CROSSCHECK_WORKER = writePlainExecutable(this, 'rapid-crosscheck-worker.sh');
});

Given(literal('RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env が存在しない'), function () {
  fs.rmSync(path.join(this.configDir, 'rapid-crosscheck.env'), { force: true });
});

Then(literal('終了コード 2 で stderr に "error: config file not found path: <RELAY_GATE_CONFIG_DIR>/rapid-crosscheck.env" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, `error: config file not found path: ${this.configDir}/rapid-crosscheck.env`);
});

Then(literal('どの runner も起動されない'), function () {
  assertNoInvocations(this);
});

// ---- facade_sh は速報クロスチェック設定の RAPID_DB_CONN_REF を参照名としてだけ使い認証情報の値を出さない(SPEC-005-06) ----

Given(literal('feature-flag.env に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=background があり管理 DB が起動している'), function () {
  setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=background');
  supplementFlags(this);
  startManagementDb(this);
});

Given(literal('RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env に RAPID_DB_CONN_REF=mgmt-db RAPID_LEASE_SEC=600 RAPID_POLL_INTERVAL_SEC=30 だけがあり、パスワード・接続文字列の値は無い'), function () {
  fs.writeFileSync(path.join(this.configDir, 'rapid-crosscheck.env'), 'RAPID_DB_CONN_REF=mgmt-db\nRAPID_LEASE_SEC=600\nRAPID_POLL_INTERVAL_SEC=30\n');
});

Given(literal('RDB クライアント CLI のパスに引数と環境変数を記録して実 DB へ転送するラッパーを置く'), function () {
  writePsqlWrapper(this, true);
});

Then(literal('parallel_runs に run_id の行が status=RUNNING で 1 件ある'), function () {
  assertExit(this, 0);
  assert.deepEqual(dbRows(this, 'SELECT run_id, status FROM parallel_runs'), [`${this.runId}|RUNNING`]);
});

Then(literal('RDB クライアントラッパーの記録には参照名 mgmt-db があり、実行ログと stderr には参照名から解決した接続情報の値が無い'), function () {
  const record = fs.readFileSync(this.psqlLog, 'utf8');
  assert.ok(record.includes(`service='${CONN_REF}'`), record);
  // 参照名から解決した接続情報(pg_service.conf の host / dbname)は、facade の実行ログにも stderr にも出ない
  for (const secret of [this.db.host, this.db.dbname, 'host=', 'dbname=']) {
    assert.ok(!executionLog(this).includes(secret), `execution log must not include ${secret}`);
    assert.ok(!this.result.stderr.includes(secret), `stderr must not include ${secret}`);
  }
});

// ---- facade_sh は RAPID_CROSSCHECK_MODE=off で RDB クライアントを呼ばず rapid-crosscheck.env も読まない(SPEC-005-06) ----

Given(literal('feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off がある'), function () {
  setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off');
  supplementFlags(this);
});

Given(literal('RDB クライアント CLI のパスに呼び出し記録用スタブを置く'), function () {
  writePsqlWrapper(this, false);
});

Then(literal('終了コード 0 で終了し、RDB クライアントスタブの呼び出し記録は存在しない'), function () {
  assertExit(this, 0);
  assert.equal(fs.existsSync(this.psqlLog), false, 'RDB client must not be called');
});

Then(literal('blue と green のスタブ runner の起動記録がある'), function () {
  assert.equal(startedInvocations(this.flags.BLUE_RUNNER).length, 1);
  assert.equal(startedInvocations(this.flags.GREEN_RUNNER).length, 1);
});

// ---- facade_sh は runner 実体が実行不可なら終了コード 2 で終了する ----

Given(literal('feature-flag.env に BLUE_MODE=foreground BLUE_IMPL=v1 BLUE_RUNNER=<実行可能な runner> GREEN_MODE=background GREEN_IMPL=v2 GREEN_RUNNER=/opt/relay-gate/runners/missing.sh RAPID_CROSSCHECK_MODE=off がある'), function () {
  this.flags = {
    BLUE_MODE: 'foreground',
    BLUE_IMPL: 'v1',
    BLUE_RUNNER: writeStub(this, 'blue-runner.sh'),
    GREEN_MODE: 'background',
    GREEN_IMPL: 'v2',
    GREEN_RUNNER: '/opt/relay-gate/runners/missing.sh',
    RAPID_CROSSCHECK_MODE: 'off',
  };
});

Then(literal('終了コード 2 で stderr に "error: file not executable key=GREEN_RUNNER path=/opt/relay-gate/runners/missing.sh" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: file not executable key=GREEN_RUNNER path=/opt/relay-gate/runners/missing.sh');
});

Then(literal('blue runner も起動されない'), function () {
  assert.deepEqual(invocations(this.flags.BLUE_RUNNER), []);
});

// ---- facade_sh は未知キーを warn にとどめ 9 キー以外を必須にしない ----

Given(literal('feature-flag.env に 9 キーがすべて正しく定義され、加えて CONFIG_VERSION=2026-08-30 がある'), function () {
  // 9 キーの正しい定義(管理 DB を使わない RAPID_CROSSCHECK_MODE=off。速報の runner / worker も実行可能な実体を書く)
  setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2');
  this.flags.RAPID_CROSSCHECK_RUNNER = writePlainExecutable(this, 'rapid-crosscheck-runner.sh');
  this.flags.RAPID_CROSSCHECK_WORKER = writePlainExecutable(this, 'rapid-crosscheck-worker.sh');
  supplementFlags(this);
  this.flags.CONFIG_VERSION = '2026-08-30';
});

Then(literal('stderr に "warn: unknown key key=CONFIG_VERSION path: <RELAY_GATE_CONFIG_DIR>/feature-flag.env" が出るが終了コードは foreground の exitcode.txt の値である'), function () {
  assertStderrIncludes(this, `warn: unknown key key=CONFIG_VERSION path: ${this.configDir}/feature-flag.env`);
  const exitcode = fs.readFileSync(path.join(this.artifactRoot, 'facade', this.runId, 'blue', 'exitcode.txt'), 'utf8').trim();
  assertExit(this, Number(exitcode));
});

// ---- facade_sh は JOB_ID 欠落を終了コード 2 で拒否する ----

Given(literal('feature-flag.env が正しく定義されている'), function () {
  setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off');
  supplementFlags(this);
});

When(literal('`facade.sh` を引数なしで実行する'), function () {
  runFacade(this, []);
});

Then(literal('終了コード 2 で stderr に "error: JOB_ID required" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: JOB_ID required');
});

// ---- facade_sh は相対パスの runner を設定ファイルのあるディレクトリ基準で起動し速報 runner を解決後のパスで渡す ----

Given(literal('RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=background BLUE_IMPL=v1 BLUE_RUNNER=./blue-runner.sh RAPID_CROSSCHECK_RUNNER=./rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=./rapid-crosscheck-worker.sh がある'), function () {
  setFlags(
    this,
    'BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=background BLUE_IMPL=v1 BLUE_RUNNER=./blue-runner.sh RAPID_CROSSCHECK_RUNNER=./rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=./rapid-crosscheck-worker.sh',
  );
});

Given(literal('RELAY_GATE_CONFIG_DIR のディレクトリに、起動引数と環境変数を記録して exitcode.txt に 0 を書く実行可能なスタブ blue-runner.sh と、実行可能な rapid-crosscheck-runner.sh / rapid-crosscheck-worker.sh があり、管理 DB が起動している'), function () {
  this.configBlueRunner = writeStub(this, 'blue-runner.sh', 'exit0', this.configDir);
  writePlainExecutable(this, 'rapid-crosscheck-runner.sh', this.configDir);
  writePlainExecutable(this, 'rapid-crosscheck-worker.sh', this.configDir);
  startManagementDb(this);
});

Given(literal('RELAY_GATE_CONFIG_DIR は末尾に `/` の無い絶対パスで、そのディレクトリに RAPID_DB_CONN_REF を書いた rapid-crosscheck.env と、JOB001 の行を含む blue-job-map.csv がある'), function () {
  assert.ok(path.isAbsolute(this.configDir) && !this.configDir.endsWith('/'));
  fs.writeFileSync(path.join(this.configDir, 'rapid-crosscheck.env'), `RAPID_DB_CONN_REF=${CONN_REF}\n`);
  fs.writeFileSync(
    path.join(this.configDir, 'blue-job-map.csv'),
    'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\nJOB001,/var/app/work,/opt/app/bin/blue-job001.sh,[],60\n',
  );
});

Given(literal('作業ディレクトリにするディレクトリ work(RELAY_GATE_CONFIG_DIR とは別)に、起動されたら記録を残す別の実行可能な blue-runner.sh がある'), function () {
  this.workBlueRunner = writeStub(this, 'blue-runner.sh', 'exit0', workCwd(this));
});

When(literal('work を作業ディレクトリにして `facade.sh JOB001` を実行する'), function () {
  runFacade(this, ['JOB001'], workCwd(this));
});

Then(literal('終了コード 0 で、RELAY_GATE_CONFIG_DIR のスタブ blue-runner.sh が 1 回起動され、work の blue-runner.sh は起動されていない'), function () {
  assertExit(this, 0);
  assert.equal(invocations(this.configBlueRunner).length, 1);
  assert.deepEqual(invocations(this.workBlueRunner), []);
});

Then(literal('スタブが記録した環境変数 RAPID_CROSSCHECK_RUNNER は "<RELAY_GATE_CONFIG_DIR>/./rapid-crosscheck-runner.sh" である(契約 config_files.feature-flag.env.runner_path_resolution)'), function () {
  assert.equal(recordedEnv(this.configBlueRunner).RAPID_CROSSCHECK_RUNNER, `${this.configDir}/./rapid-crosscheck-runner.sh`);
});

// ---- facade_sh は相対パスの runner 実体が無ければ解決後のパスを報告して終了コード 2 で終了する ----

Given(literal('RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground BLUE_IMPL=v1 BLUE_RUNNER=<実行可能な runner の絶対パス> GREEN_MODE=background GREEN_IMPL=v2 GREEN_RUNNER=./green-runner.sh RAPID_CROSSCHECK_MODE=off がある'), function () {
  this.flags = {
    BLUE_MODE: 'foreground',
    BLUE_IMPL: 'v1',
    BLUE_RUNNER: writeStub(this, 'blue-runner.sh'),
    GREEN_MODE: 'background',
    GREEN_IMPL: 'v2',
    GREEN_RUNNER: './green-runner.sh',
    RAPID_CROSSCHECK_MODE: 'off',
  };
});

Given(literal('RELAY_GATE_CONFIG_DIR は末尾に `/` の無い絶対パスで、そのディレクトリに green-runner.sh は無く、作業ディレクトリにするディレクトリ work に実行可能な green-runner.sh がある'), function () {
  assert.ok(path.isAbsolute(this.configDir) && !this.configDir.endsWith('/'));
  assert.equal(fs.existsSync(path.join(this.configDir, 'green-runner.sh')), false);
  writeStub(this, 'green-runner.sh', 'exit0', workCwd(this));
});

Then(literal('終了コード 2 で stderr に "error: file not executable key=GREEN_RUNNER path=<RELAY_GATE_CONFIG_DIR>/./green-runner.sh" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, `error: file not executable key=GREEN_RUNNER path=${this.configDir}/./green-runner.sh`);
});

Then(literal('どの runner も起動されず、stderr に "path is not absolute" を含む行は出ない'), function () {
  assertNoInvocations(this);
  assert.deepEqual(stderrLines(this).filter((l) => l.includes('path is not absolute')), []);
});

// ---- facade_sh は設定の違反が 2 つあるとき検証コマンドの error 行の順で最初の違反の 1 行だけを出す ----

Given(literal('RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 BLUE_RUNNER=relative/blue-runner.sh GREEN_RUNNER=<記録用スタブ runner> があり、GREEN_IMPL の行は無い'), function () {
  setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 BLUE_RUNNER=relative/blue-runner.sh');
  this.flags.GREEN_RUNNER = writeStub(this, 'green-runner.sh');
});

Given(literal('RELAY_GATE_CONFIG_DIR は末尾に `/` の無い絶対パスで、<RELAY_GATE_CONFIG_DIR>/relative/blue-runner.sh は無い'), function () {
  assert.ok(path.isAbsolute(this.configDir) && !this.configDir.endsWith('/'));
  assert.equal(fs.existsSync(path.join(this.configDir, 'relative', 'blue-runner.sh')), false);
});

Then(literal('終了コード 2 で、stderr は "error: file not executable key=BLUE_RUNNER path=<RELAY_GATE_CONFIG_DIR>/relative/blue-runner.sh" の 1 行だけである'), function () {
  assertExit(this, 2);
  assert.deepEqual(stderrLines(this), [`error: file not executable key=BLUE_RUNNER path=${this.configDir}/relative/blue-runner.sh`]);
});

Then(literal('stderr に "option=GREEN_IMPL" を含む行は出ない'), function () {
  assert.deepEqual(stderrLines(this).filter((l) => l.includes('option=GREEN_IMPL')), []);
});

Then(literal('その 1 行は、同じファイルを `validate-config.sh --feature-flag <RELAY_GATE_CONFIG_DIR>/feature-flag.env` で検証したときの stderr の最初の error 行と同じである'), function () {
  const proc = spawnSync(VALIDATE_CONFIG, ['--feature-flag', `${this.configDir}/feature-flag.env`], {
    cwd: this.workDir,
    encoding: 'utf8',
    env: { ...process.env, RELAY_GATE_CONFIG_DIR: this.configDir, PWD: this.workDir },
  });
  assert.equal(proc.error, undefined);
  const firstError = proc.stderr.split('\n').find((l) => l.startsWith('error:'));
  assert.equal(stderrLines(this)[0], firstError, `validate-config stderr:\n${proc.stderr}`);
});

Then(literal('スタブ runner の起動記録は存在せず、RELAY_GATE_ARTIFACT_ROOT/facade/ 配下にディレクトリは作成されない'), function () {
  assertNoInvocations(this);
  assertNoRunDirectory(this);
});

// ---- facade_sh は最初の違反に hint が続くとき error 行と hint の 2 行だけを出す ----

Given(literal('RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=maybe だけがある'), function () {
  this.flags = { BLUE_MODE: 'foreground', GREEN_MODE: 'foreground', RAPID_CROSSCHECK_MODE: 'maybe' };
});

Then(literal('終了コード 2 で、stderr は 1 行目 "error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe"、2 行目 "hint: use foreground, background or off" の 2 行だけである'), function () {
  assertExit(this, 2);
  assert.deepEqual(stderrLines(this), ['error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe', 'hint: use foreground, background or off']);
});

Then(literal('stderr に "foreground slot must be exactly one" を含む行も "option required" を含む行も出ない'), function () {
  assert.deepEqual(stderrLines(this).filter((l) => l.includes('foreground slot must be exactly one') || l.includes('option required')), []);
});

// ---- facade_sh は未知キーの warn 行を最初の違反の error 行より前に出す ----

Given(literal('RELAY_GATE_CONFIG_DIR/feature-flag.env に CONFIG_VERSION=2026-08-30 BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 BLUE_RUNNER=relative/blue-runner.sh GREEN_RUNNER=<記録用スタブ runner> があり、GREEN_IMPL の行は無い'), function () {
  setFlags(this, 'CONFIG_VERSION=2026-08-30 BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 BLUE_RUNNER=relative/blue-runner.sh');
  this.flags.GREEN_RUNNER = writeStub(this, 'green-runner.sh');
});

Then(literal('終了コード 2 で、stderr は 1 行目 "warn: unknown key key=CONFIG_VERSION path: <RELAY_GATE_CONFIG_DIR>/feature-flag.env"、2 行目 "error: file not executable key=BLUE_RUNNER path=<RELAY_GATE_CONFIG_DIR>/relative/blue-runner.sh" の 2 行だけである'), function () {
  assertExit(this, 2);
  assert.deepEqual(stderrLines(this), [
    expandConfigDir(this, 'warn: unknown key key=CONFIG_VERSION path: <RELAY_GATE_CONFIG_DIR>/feature-flag.env'),
    expandConfigDir(this, 'error: file not executable key=BLUE_RUNNER path=<RELAY_GATE_CONFIG_DIR>/relative/blue-runner.sh'),
  ]);
});

// ---- facade_sh は相対パスの BLUE_JOB_MAP_CSV を設定ファイルのあるディレクトリ基準で解決して blue の runner へ渡しキーの無い green の runner へ既定の場所を渡す ----

Given(literal('RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2 BLUE_RUNNER=<記録用スタブ runner> GREEN_RUNNER=<記録用スタブ runner> BLUE_JOB_MAP_CSV=./maps/blue-jobs.csv があり、GREEN_JOB_MAP_CSV の行は無い'), function () {
  setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2');
  this.flags.BLUE_RUNNER = writeStub(this, 'blue-runner.sh');
  this.flags.GREEN_RUNNER = writeStub(this, 'green-runner.sh');
  this.flags.BLUE_JOB_MAP_CSV = './maps/blue-jobs.csv';
});

Given(literal('RELAY_GATE_CONFIG_DIR は末尾に `/` の無い絶対パスで、<RELAY_GATE_CONFIG_DIR>/maps/blue-jobs.csv も <RELAY_GATE_CONFIG_DIR>/green-job-map.csv も存在しない'), function () {
  assert.ok(path.isAbsolute(this.configDir) && !this.configDir.endsWith('/'));
  assert.equal(fs.existsSync(path.join(this.configDir, 'maps', 'blue-jobs.csv')), false);
  assert.equal(fs.existsSync(path.join(this.configDir, 'green-job-map.csv')), false);
});

Given(literal('スタブ runner は起動引数と環境変数をファイルに記録し、exitcode.txt に 0 を書いて終了する'), function () {
  // 記録用スタブの既定の振る舞い(起動引数・環境変数の記録と exitcode.txt=0)。置き直して確かめる
  writeStub(this, 'blue-runner.sh', 'exit0');
  writeStub(this, 'green-runner.sh', 'exit0');
});

Given(literal('facade.sh を起動するプロセスの環境に BLUE_JOB_MAP_CSV=/tmp/other-blue.csv と GREEN_JOB_MAP_CSV=/tmp/other-green.csv がある'), function () {
  this.extraEnv = { BLUE_JOB_MAP_CSV: '/tmp/other-blue.csv', GREEN_JOB_MAP_CSV: '/tmp/other-green.csv' };
});

When(literal('RELAY_GATE_CONFIG_DIR とは別のディレクトリ work を作業ディレクトリにして `facade.sh JOB001` を実行する'), function () {
  runFacade(this, ['JOB001'], workCwd(this));
});

Then(literal('終了コード 0 で終了し、blue のスタブの起動引数は "--run-id <run_id> --job-id JOB001 --role blue --mode foreground --" である'), function () {
  assertExit(this, 0);
  assert.deepEqual(invocations(this.flags.BLUE_RUNNER), [`--run-id ${this.runId} --job-id JOB001 --role blue --mode foreground --`]);
});

Then(literal('blue のスタブが記録した環境変数 BLUE_JOB_MAP_CSV は "<RELAY_GATE_CONFIG_DIR>/./maps/blue-jobs.csv" である(契約 config_files.feature-flag.env.job_map_location)'), function () {
  assert.equal(recordedEnv(this.flags.BLUE_RUNNER).BLUE_JOB_MAP_CSV, `${this.configDir}/./maps/blue-jobs.csv`);
});

Then(literal('green のスタブが記録した環境変数 GREEN_JOB_MAP_CSV は "<RELAY_GATE_CONFIG_DIR>/green-job-map.csv" である'), function () {
  assert.equal(recordedEnv(this.flags.GREEN_RUNNER).GREEN_JOB_MAP_CSV, `${this.configDir}/green-job-map.csv`);
});

Then(literal('stderr に "job map not found" を含む行は出ない(facade はジョブマップの存在を検査しない)'), function () {
  assert.deepEqual(stderrLines(this).filter((l) => l.includes('job map not found')), []);
});

// ---- facade_sh は値が空の GREEN_JOB_MAP_CSV の行がある設定で green の runner へ既定の場所を渡す ----

Given(literal('RELAY_GATE_CONFIG_DIR/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2 BLUE_RUNNER=<記録用スタブ runner> GREEN_RUNNER=<記録用スタブ runner> があり、加えて値が空の行 `GREEN_JOB_MAP_CSV=` がある'), function () {
  setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2');
  this.flags.BLUE_RUNNER = writeStub(this, 'blue-runner.sh');
  this.flags.GREEN_RUNNER = writeStub(this, 'green-runner.sh');
  this.flags.GREEN_JOB_MAP_CSV = '';
});

Given(literal('RELAY_GATE_CONFIG_DIR は末尾に `/` の無い絶対パスである'), function () {
  assert.ok(path.isAbsolute(this.configDir) && !this.configDir.endsWith('/'));
});

Then(literal('終了コード 0 で終了し、green のスタブが記録した環境変数 GREEN_JOB_MAP_CSV は "<RELAY_GATE_CONFIG_DIR>/green-job-map.csv" である(空の値ではない。契約 config_files.feature-flag.env.job_map_location)'), function () {
  assertExit(this, 0);
  assert.equal(recordedEnv(this.flags.GREEN_RUNNER).GREEN_JOB_MAP_CSV, `${this.configDir}/green-job-map.csv`);
});

Then(literal('stderr に "warn: unknown key key=GREEN_JOB_MAP_CSV" を含む行は出ない'), function () {
  assert.deepEqual(stderrLines(this).filter((l) => l.includes('warn: unknown key key=GREEN_JOB_MAP_CSV')), []);
});
