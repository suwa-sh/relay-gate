const { After, Before, Given, Then, When } = require('@cucumber/cucumber');
const { existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } = require('node:fs');
const { spawnSync } = require('node:child_process');
const { tmpdir } = require('node:os');
const { join, resolve } = require('node:path');

const projectRoot = resolve(__dirname, '../../..');
const relaygate = join(projectRoot, 'facade', 'bin', 'relaygate');
const jobId = 'JOB-ATDD-6078C4ED';
const secretValue = 'private-key-material-must-not-be-persisted';

function execute(command, args, options = {}) {
  return spawnSync(command, args, { encoding: 'utf8', ...options });
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function createSchema(dbPath) {
  const schema = [
    'CREATE TABLE execution_specs (run_id TEXT PRIMARY KEY, parent_run_id TEXT, job_id TEXT, host TEXT, exec_user TEXT, script_path TEXT, work_dir TEXT, fixed_args TEXT, additional_args TEXT, job_map_version TEXT, impl_version TEXT, hang_detect_limit_minutes INTEGER, credential_ref TEXT);',
    'CREATE TABLE runner_results (run_id TEXT, slot_type TEXT, role_type TEXT, started_at TEXT, stdout_path TEXT, stderr_path TEXT, exit_code INTEGER, status TEXT, PRIMARY KEY (run_id, role_type));',
    'CREATE TABLE rapid_crosscheck_requests (run_id TEXT PRIMARY KEY, job_id TEXT, blue_run_id TEXT, green_run_id TEXT, requested_at TEXT, status TEXT, lease_expires_at TEXT, worker_id TEXT);',
  ].join(' ');
  const result = execute('sqlite3', [dbPath, schema]);
  assert(result.status === 0, `failed to create SQLite schema: ${result.stderr}`);
}

function jobEntry() {
  return {
    host: 'runner.example.test',
    exec_user: 'relay',
    script_path: '/opt/jobs/example.sh',
    work_dir: '/var/tmp/relay',
    fixed_args: ['--fixed', 'fixed value'],
    impl_version: 'green-v1',
    hang_detect_limit_minutes: 15,
    credential_ref: 'ssh-key-reference',
    credential_secret: secretValue,
  };
}

function seedJob(world, modes = { blue: 'foreground', green: 'background', rapid: 'on' }) {
  const document = { version: 'map-v1', jobs: { [jobId]: jobEntry() } };
  writeFileSync(world.jobMapPath, JSON.stringify(document));
  world.originalJobDefinition = readFileSync(world.jobMapPath, 'utf8');
  Object.assign(world.env, {
    BLUE_MODE: modes.blue,
    GREEN_MODE: modes.green,
    RAPID_CROSSCHECK_MODE: modes.rapid,
  });
}

function runSelectSlot(world, additionalArgs = ['--additional', 'value']) {
  world.result = execute(relaygate, ['concurrent-run', 'select-slot', '--job-id', jobId, '--', ...additionalArgs], { env: world.env });
  return world.result;
}

function specPath(world, runId = world.runId) {
  return join(world.executionSpecDir, runId, 'execution-spec.json');
}

function readSpec(world, runId) {
  const path = specPath(world, runId);
  assert(existsSync(path), `execution spec not created: ${path}`);
  return JSON.parse(readFileSync(path, 'utf8'));
}

function launchLog(world) {
  return existsSync(world.launchLogPath) ? readFileSync(world.launchLogPath, 'utf8').trim().split('\n').filter(Boolean) : [];
}

function databaseCount(world, tableName) {
  const result = execute('sqlite3', [world.dbPath, `SELECT COUNT(*) FROM ${tableName};`]);
  assert(result.status === 0, `failed to count ${tableName}: ${result.stderr}`);
  return Number(result.stdout.trim());
}

Before(function () {
  this.testDir = mkdtempSync(join(tmpdir(), 'relaygate-atdd-6078c4ed-'));
  this.dbPath = join(this.testDir, 'relaygate.db');
  this.jobMapPath = join(this.testDir, 'job-map.json');
  this.executionSpecDir = join(this.testDir, 'execution-specs');
  this.launchLogPath = join(this.testDir, 'ssh-launch.log');
  const binDir = join(this.testDir, 'bin');
  mkdirSync(binDir);
  mkdirSync(this.executionSpecDir);
  createSchema(this.dbPath);
  writeFileSync(join(binDir, 'ssh'), '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >>"$RELAYGATE_TEST_LAUNCH_LOG"\nexit 0\n', { mode: 0o755 });
  writeFileSync(join(binDir, 'uuidgen'), '#!/usr/bin/env bash\nprintf "%s\\n" "$RELAYGATE_TEST_RUN_ID"\n', { mode: 0o755 });
  this.runId = 'run-atdd-6078c4ed-1';
  this.env = {
    ...process.env,
    PATH: `${binDir}:${process.env.PATH}`,
    RELAYGATE_RDB_DSN: `sqlite://${this.dbPath}`,
    RELAYGATE_JOB_MAP_PATH: this.jobMapPath,
    RELAYGATE_EXECUTION_SPEC_DIR: this.executionSpecDir,
    RELAYGATE_TEST_LAUNCH_LOG: this.launchLogPath,
    RELAYGATE_TEST_RUN_ID: this.runId,
  };
});

After(function () {
  rmSync(this.testDir, { recursive: true, force: true });
});

Given(/^feature flag設定（BLUE_MODE\/GREEN_MODE）が投入されている$/, function () {
  seedJob(this);
});

When('facadeがJOB_IDを受け取る', function () {
  runSelectSlot(this);
});

Then('設定に従いblue・greenの各slotが起動される', function () {
  assert(this.result.status === 0, `expected successful launch: ${this.result.stderr}`);
  const launches = launchLog(this);
  assert(launches.length === 2, `expected blue and green launches, got ${launches.length}`);
  assert(launches.some((line) => line.includes('RELAYGATE_SLOT=blue') && line.includes('RELAYGATE_ROLE=foreground')), 'blue foreground launch was not observed');
  assert(launches.some((line) => line.includes('RELAYGATE_SLOT=green') && line.includes('RELAYGATE_ROLE=background')), 'green background launch was not observed');
});

Given(/^BLUE_MODE\/GREEN_MODE\/RAPID_CROSSCHECK_MODEの組み合わせを変更する$/, function () {
  seedJob(this, { blue: 'foreground', green: 'background', rapid: 'on' });
  this.firstResult = runSelectSlot(this);
  this.env.RELAYGATE_TEST_RUN_ID = 'run-atdd-6078c4ed-2';
  Object.assign(this.env, { BLUE_MODE: 'off', GREEN_MODE: 'foreground', RAPID_CROSSCHECK_MODE: 'off' });
});

When('同じジョブ定義でジョブを起動する', function () {
  this.result = runSelectSlot(this, ['--additional', 'value']);
});

Then('ジョブ定義を変更せず運用モードが切り替わる', function () {
  assert(this.firstResult.status === 0 && this.result.status === 0, `mode transition failed: ${this.firstResult.stderr}\n${this.result.stderr}`);
  assert(readFileSync(this.jobMapPath, 'utf8') === this.originalJobDefinition, 'job definition was changed while switching modes');
  const firstSpec = readSpec(this, this.runId);
  const secondSpec = readSpec(this, 'run-atdd-6078c4ed-2');
  assert(firstSpec.blue_mode === 'foreground' && firstSpec.green_mode === 'background', 'parallel operation modes were not persisted');
  assert(secondSpec.blue_mode === 'off' && secondSpec.green_mode === 'foreground', 'single-green operation modes were not persisted');
});

Given('BLUE_MODEとGREEN_MODEの両方にforegroundを設定しようとする', function () {
  seedJob(this, { blue: 'foreground', green: 'foreground', rapid: 'on' });
});

When('facadeが設定を検証する', function () {
  runSelectSlot(this);
});

Then('起動を許可しない', function () {
  assert(this.result.status === 2, `expected validation exit 2, got ${this.result.status}: ${this.result.stderr}`);
  assert(launchLog(this).length === 0, 'a slot was launched despite foreground conflict');
  assert(databaseCount(this, 'execution_specs') === 0, 'execution spec was persisted despite foreground conflict');
  assert(readdirSync(this.executionSpecDir).length === 0, 'execution-spec file was created despite foreground conflict');
});

Given('ジョブスケジューラがJOB_IDと追加引数だけを渡す', function () {
  seedJob(this);
  this.schedulerArgs = ['--scheduler-parameter', 'argument from scheduler'];
});

When('slot runnerがジョブマップを参照する', function () {
  runSelectSlot(this, this.schedulerArgs);
});

Then('実行先の詳細が解決される', function () {
  assert(this.result.status === 0, `job map resolution failed: ${this.result.stderr}`);
  const spec = readSpec(this);
  assert(spec.host === 'runner.example.test' && spec.exec_user === 'relay', 'host or user was not resolved from job map');
  assert(spec.script_path === '/opt/jobs/example.sh' && spec.work_dir === '/var/tmp/relay', 'script or work directory was not resolved from job map');
  assert(JSON.stringify(spec.additional_args) === JSON.stringify(this.schedulerArgs), 'scheduler additional arguments were not retained');
  assert(launchLog(this).every((line) => line.includes('relay@runner.example.test') && line.includes('/opt/jobs/example.sh')), 'SSH launches did not use resolved job-map target');
});

Given('job mapに固定引数が定義されている', function () {
  seedJob(this);
  this.schedulerArgs = ['--extra', 'two words'];
});

When('ジョブスケジューラから追加引数が渡される', function () {
  runSelectSlot(this, this.schedulerArgs);
});

Then('固定引数の後ろに追加引数が順序どおり連結される', function () {
  assert(this.result.status === 0, `argument launch failed: ${this.result.stderr}`);
  const spec = readSpec(this);
  assert(JSON.stringify(spec.fixed_args) === JSON.stringify(['--fixed', 'fixed value']), 'fixed args were not persisted');
  assert(JSON.stringify(spec.additional_args) === JSON.stringify(this.schedulerArgs), 'additional args were not persisted in order');
  for (const line of launchLog(this)) {
    const fixedFlag = line.indexOf('--fixed');
    const fixedValue = line.indexOf('fixed\\ value');
    const additionalFlag = line.indexOf('--extra');
    const additionalValue = line.indexOf('two\\ words');
    assert(fixedFlag >= 0 && fixedFlag < fixedValue && fixedValue < additionalFlag && additionalFlag < additionalValue, `SSH command did not preserve argument order: ${line}`);
  }
});

Given('slot runnerが実行先を解決する', function () {
  seedJob(this);
  this.schedulerArgs = ['--additional', 'value'];
});

When('起動する', function () {
  runSelectSlot(this, this.schedulerArgs);
});

Then('execution-spec.jsonに解決済み設定が一度だけ確定して保存され、認証情報そのものは含まれない', function () {
  assert(this.result.status === 0, `execution-spec persistence failed: ${this.result.stderr}`);
  const spec = readSpec(this);
  const specFile = specPath(this);
  assert(databaseCount(this, 'execution_specs') === 1, 'execution_specs was not persisted exactly once');
  assert(readdirSync(join(this.executionSpecDir, this.runId)).filter((name) => name === 'execution-spec.json').length === 1, 'execution-spec.json was not finalized exactly once');
  assert(!readdirSync(join(this.executionSpecDir, this.runId)).some((name) => name.startsWith('.execution-spec.json.')), 'atomic temporary file remained after finalization');
  assert((statSync(specFile).mode & 0o777) === 0o600, 'execution-spec.json permissions are not 0600');
  assert(spec.run_id === this.runId && spec.job_id === jobId && spec.parent_run_id === null, 'execution identity was not fully persisted');
  assert(spec.host === 'runner.example.test' && spec.exec_user === 'relay' && spec.script_path === '/opt/jobs/example.sh' && spec.work_dir === '/var/tmp/relay', 'resolved execution target was incomplete');
  assert(JSON.stringify(spec.fixed_args) === JSON.stringify(['--fixed', 'fixed value']) && JSON.stringify(spec.additional_args) === JSON.stringify(this.schedulerArgs), 'resolved arguments were incomplete');
  assert(spec.job_map_version === 'map-v1' && spec.impl_version === 'green-v1' && spec.hang_detect_limit_minutes === 15, 'resolved metadata was incomplete');
  assert(spec.blue_mode === 'foreground' && spec.green_mode === 'background' && spec.rapid_crosscheck_mode === 'on', 'selected modes were not persisted');
  assert(spec.credential_ref === 'ssh-key-reference', 'credential reference was not persisted');
  assert(!readFileSync(specFile, 'utf8').includes(secretValue), 'credential secret was persisted in execution spec');
});
