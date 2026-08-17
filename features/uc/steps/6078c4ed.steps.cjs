const { After, Before, Given, Then, When } = require("@cucumber/cucumber");
const { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } = require("node:fs");
const { spawnSync } = require("node:child_process");
const { tmpdir } = require("node:os");
const { join, resolve } = require("node:path");

const projectRoot = resolve(__dirname, "../../..");
const relaygate = join(projectRoot, "facade", "bin", "relaygate");

function execute(command, args, options = {}) {
  return spawnSync(command, args, { encoding: "utf8", ...options });
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function createSchema(dbPath) {
  const schema = [
    "CREATE TABLE execution_specs (run_id TEXT PRIMARY KEY, parent_run_id TEXT, job_id TEXT, host TEXT, exec_user TEXT, script_path TEXT, work_dir TEXT, fixed_args TEXT, additional_args TEXT, job_map_version TEXT, impl_version TEXT, hang_detect_limit_minutes INTEGER, credential_ref TEXT);",
    "CREATE TABLE runner_results (run_id TEXT, slot_type TEXT, role_type TEXT, started_at TEXT, stdout_path TEXT, stderr_path TEXT, exit_code INTEGER, status TEXT, PRIMARY KEY (run_id, role_type));",
    "CREATE TABLE rapid_crosscheck_requests (run_id TEXT PRIMARY KEY, job_id TEXT, blue_run_id TEXT, green_run_id TEXT, requested_at TEXT, status TEXT, lease_expires_at TEXT, worker_id TEXT);",
  ].join(" ");
  const result = execute("sqlite3", [dbPath, schema]);
  assert(result.status === 0, `failed to create SQLite schema: ${result.stderr}`);
}

function jobEntry() {
  return { host: "runner.example.test", exec_user: "relay", script_path: "/opt/jobs/example.sh", work_dir: "/var/tmp/relay", fixed_args: ["--fixed"], impl_version: "green-v1", hang_detect_limit_minutes: 15, credential_ref: "ssh-key-reference" };
}

function seedJob(world, jobId, blueMode, greenMode, rapidMode, runId) {
  writeFileSync(world.jobMapPath, JSON.stringify({ version: "map-v1", jobs: { [jobId]: jobEntry() } }));
  Object.assign(world.env, { BLUE_MODE: blueMode, GREEN_MODE: greenMode, RAPID_CROSSCHECK_MODE: rapidMode, RELAYGATE_TEST_RUN_ID: runId || "run-20260817-test" });
}

Before(function () {
  this.testDir = mkdtempSync(join(tmpdir(), "relaygate-uc-6078c4ed-"));
  this.dbPath = join(this.testDir, "relaygate.db");
  this.jobMapPath = join(this.testDir, "job-map.json");
  this.executionSpecDir = join(this.testDir, "execution-specs");
  this.launchLogPath = join(this.testDir, "ssh-launch.log");
  const binDir = join(this.testDir, "bin");
  mkdirSync(binDir);
  mkdirSync(this.executionSpecDir);
  createSchema(this.dbPath);
  writeFileSync(join(binDir, "ssh"), "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"$RELAYGATE_TEST_LAUNCH_LOG\"\nexit 0\n", { mode: 0o755 });
  writeFileSync(join(binDir, "uuidgen"), "#!/usr/bin/env bash\nprintf '%s\\n' \"$RELAYGATE_TEST_RUN_ID\"\n", { mode: 0o755 });
  this.env = { ...process.env, PATH: `${binDir}:${process.env.PATH}`, RELAYGATE_RDB_DSN: `sqlite://${this.dbPath}`, RELAYGATE_JOB_MAP_PATH: this.jobMapPath, RELAYGATE_EXECUTION_SPEC_DIR: this.executionSpecDir, RELAYGATE_TEST_LAUNCH_LOG: this.launchLogPath };
});

After(function () { rmSync(this.testDir, { recursive: true, force: true }); });

Given('JOB_ID {string} のジョブマップにBLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=onが設定されている', function (jobId) { seedJob(this, jobId, "foreground", "background", "on", "run-20260817-001"); });
Given('JOB_ID {string} のジョブマップにRAPID_CROSSCHECK_MODE=offが設定されている', function (jobId) { seedJob(this, jobId, "background", "off", "off"); });
Given('JOB_ID {string} のジョブマップにBLUE_MODE=off, GREEN_MODE=foreground, RAPID_CROSSCHECK_MODE=offが設定されている', function (jobId) { seedJob(this, jobId, "off", "foreground", "off", "run-20260817-004"); });
Given('JOB_ID {string} のジョブマップにBLUE_MODE=foreground, GREEN_MODE=foregroundが設定されている', function (jobId) { seedJob(this, jobId, "foreground", "foreground", "on"); });
Given('JOB_ID {string} がジョブマップに存在しない', function (_jobId) { writeFileSync(this.jobMapPath, JSON.stringify({ version: "map-v1", jobs: {} })); Object.assign(this.env, { BLUE_MODE: "background", GREEN_MODE: "off", RAPID_CROSSCHECK_MODE: "off" }); });

When(/^運用者が `relaygate concurrent-run select-slot --job-id ([^`]+)` を実行する$/, function (jobId) { this.result = execute(relaygate, ["concurrent-run", "select-slot", "--job-id", jobId], { env: this.env }); });

Then("終了コード {int} で終了する", function (expected) { assert(this.result.status === expected, `expected exit ${expected}, got ${this.result.status}; stderr: ${this.result.stderr}`); });
Then("execution-spec.jsonがrun_id {string} で確定・保存される", function (runId) {
  const specPath = join(this.executionSpecDir, runId, "execution-spec.json");
  assert(existsSync(specPath), `execution spec not created: ${specPath}`);
  assert(JSON.parse(readFileSync(specPath, "utf8")).run_id === runId, "execution-spec run_id differs from expected value");
  const result = execute("sqlite3", [this.dbPath, "SELECT run_id FROM execution_specs;"]);
  assert(result.status === 0 && result.stdout.trim() === runId, "execution_specs does not contain the confirmed run_id");
});
Then(/^標準出力に "([^"]+)" "([^"]+)" を含む行が出力される(?:（.*）)?$/, function (first, second) { assert(this.result.stdout.includes(first) && this.result.stdout.includes(second), `stdout does not contain ${first} and ${second}: ${this.result.stdout}`); });
Then("速報比較依頼テーブルへのINSERTは発生しない", function () { const result = execute("sqlite3", [this.dbPath, "SELECT COUNT(*) FROM rapid_crosscheck_requests;"]); assert(result.status === 0 && result.stdout.trim() === "0", `rapid_crosscheck_requests INSERT detected: ${result.stdout}`); });
Then("標準エラーに {string} が出力される", function (message) { assert(this.result.stderr.includes(message), `stderr does not contain ${message}: ${this.result.stderr}`); });
Then("execution-spec.jsonは作成されない", function () {
  const files = execute("find", [this.executionSpecDir, "-name", "execution-spec.json", "-print"]);
  const rows = execute("sqlite3", [this.dbPath, "SELECT COUNT(*) FROM execution_specs;"]);
  assert(files.status === 0 && files.stdout.trim() === "" && rows.status === 0 && rows.stdout.trim() === "0", "execution-spec was unexpectedly created");
});
