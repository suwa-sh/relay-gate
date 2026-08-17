const { After, Before, Given, Then, When } = require("@cucumber/cucumber");
const { mkdtempSync, mkdirSync, rmSync, writeFileSync } = require("node:fs");
const { tmpdir } = require("node:os");
const { join, resolve } = require("node:path");
const { spawnSync } = require("node:child_process");

const projectRoot = resolve(__dirname, "../../..");
const relaygate = join(projectRoot, "facade/bin/relaygate");

function execute(command, args, options = {}) {
  return spawnSync(command, args, { encoding: "utf8", ...options });
}

Before(function () {
  this.testDir = mkdtempSync(join(tmpdir(), "relaygate-6078c4ed-"));
  this.dbPath = join(this.testDir, "relaygate.db");
  this.jobMapPath = join(this.testDir, "job-map.json");
  this.launchLogPath = join(this.testDir, "launch.log");
  const binDir = join(this.testDir, "bin");
  mkdirSync(binDir);
  writeFileSync(join(binDir, "ssh"), "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"$RELAYGATE_TEST_LAUNCH_LOG\"\n", { mode: 0o755 });
  writeFileSync(this.jobMapPath, JSON.stringify({ version: "map-v1", jobs: { "JOB-2026-0817-001": { host: "runner.example.test", exec_user: "relay", script_path: "/opt/jobs/example.sh", work_dir: "/var/tmp/relay", fixed_args: ["--fixed"], impl_version: "green-v1", hang_detect_limit_minutes: 15, credential_ref: "ssh-key-reference" } } }));
  execute("sqlite3", [this.dbPath, "CREATE TABLE execution_specs (run_id TEXT PRIMARY KEY, parent_run_id TEXT, job_id TEXT, host TEXT, exec_user TEXT, script_path TEXT, work_dir TEXT, fixed_args TEXT, additional_args TEXT, job_map_version TEXT, impl_version TEXT, hang_detect_limit_minutes INTEGER, credential_ref TEXT); CREATE TABLE runner_results (run_id TEXT, slot_type TEXT, role_type TEXT, started_at TEXT, stdout_path TEXT, stderr_path TEXT, exit_code INTEGER, status TEXT, PRIMARY KEY (run_id, role_type));"]);
  this.env = { ...process.env, PATH: `${binDir}:${process.env.PATH}`, RELAYGATE_TEST_LAUNCH_LOG: this.launchLogPath, RELAYGATE_RDB_DSN: `sqlite://${this.dbPath}`, RELAYGATE_JOB_MAP_PATH: this.jobMapPath };
});

After(function () { rmSync(this.testDir, { recursive: true, force: true }); });

Given("環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on が設定されている", function () { Object.assign(this.env, { BLUE_MODE: "foreground", GREEN_MODE: "background", RAPID_CROSSCHECK_MODE: "on" }); });
Given('JOB_ID {string} がジョブマップで解決可能である', function (jobId) {
  const jobMap = JSON.parse(require("node:fs").readFileSync(this.jobMapPath, "utf8"));
  if (!jobMap.jobs[jobId]) throw new Error(`job map cannot resolve ${jobId}`);
});
Given("環境変数 BLUE_MODE=foreground, GREEN_MODE=foreground が設定されている", function () { Object.assign(this.env, { BLUE_MODE: "foreground", GREEN_MODE: "foreground", RAPID_CROSSCHECK_MODE: "on" }); });
When(/^`relaygate concurrent-run select-slot --job-id ([^`]+)` を実行する$/, function (jobId) {
  this.result = execute(relaygate, ["concurrent-run", "select-slot", "--job-id", jobId], { env: this.env });
});
Then("終了コード {int} で終了する", function (exitCode) { if (this.result.status !== exitCode) throw new Error(`expected exit ${exitCode}, got ${this.result.status}: ${this.result.stderr}`); });
Then("execution_specsテーブルに run_id を持つ1件のレコードがINSERTされる", function () { if (execute("sqlite3", [this.dbPath, "SELECT COUNT(run_id) FROM execution_specs;"]).stdout.trim() !== "1") throw new Error("execution_specs record was not inserted"); });
Then("execution_specsテーブルへのINSERTは発生しない", function () { if (execute("sqlite3", [this.dbPath, "SELECT COUNT(*) FROM execution_specs;"]).stdout.trim() !== "0") throw new Error("execution_specs record must not be inserted"); });
