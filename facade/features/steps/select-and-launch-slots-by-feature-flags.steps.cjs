// tier-facade BDD step definitions(③)。S2 scoped 再実行(spec 20260819_114307 還流)で再生成した skeleton。
// 方針:
//   - feature 文言が変わらなかった step(When / 終了コード)は旧実装を引き継ぐ
//   - 新仕様で追加・変更された step は「未実装」を明示して fail させ、S4 tier-impl が結線する
//   - ハーネス(一時ディレクトリ・SQLite スキーマ・ssh スタブ)は新仕様の 11 テーブル契約
//     (packages/contracts/relay-gate-db/schema-constants.sh)に合わせて用意する
//   - RDB の正本は PostgreSQL だが、既存の限定検証境界(issues/20260817T230000Z)に従い SQLite で検証する
const { After, Before, Given, Then, When } = require("@cucumber/cucumber");
const { mkdtempSync, mkdirSync, rmSync, writeFileSync } = require("node:fs");
const { tmpdir } = require("node:os");
const { join, resolve } = require("node:path");
const { spawnSync } = require("node:child_process");

const projectRoot = resolve(__dirname, "../../..");
const relaygate = join(projectRoot, "facade/bin/relaygate");

// 新仕様の検証用 SQLite スキーマ(列は契約定数 schema-constants.sh と同一。PK / UNIQUE は rdb-schema.yaml に従う)
const CONTRACT_SCHEMA = [
  "CREATE TABLE execution_specs (run_id TEXT PRIMARY KEY, parent_run_id TEXT REFERENCES execution_specs(run_id), job_id TEXT NOT NULL, additional_args TEXT, job_map_version TEXT NOT NULL, hang_detect_limit_minutes INTEGER NOT NULL);",
  "CREATE TABLE slot_execution_specs (run_id TEXT NOT NULL REFERENCES execution_specs(run_id), slot_type TEXT NOT NULL, host TEXT NOT NULL, exec_user TEXT NOT NULL, script_path TEXT NOT NULL, work_dir TEXT NOT NULL, fixed_args TEXT, impl_version TEXT NOT NULL, credential_ref TEXT, PRIMARY KEY (run_id, slot_type));",
  "CREATE TABLE runner_result_events (event_id TEXT PRIMARY KEY, run_id TEXT NOT NULL, slot_type TEXT NOT NULL, role_type TEXT NOT NULL, attempt_id TEXT NOT NULL, attempt_no INTEGER NOT NULL, event_name TEXT NOT NULL, status TEXT NOT NULL, occurred_at TEXT NOT NULL, started_at TEXT, stdout_path TEXT, stderr_path TEXT, exit_code INTEGER, UNIQUE (run_id, slot_type, role_type, attempt_id, event_name));",
  "CREATE TABLE runner_results (run_id TEXT NOT NULL, slot_type TEXT NOT NULL, role_type TEXT NOT NULL, attempt_id TEXT NOT NULL, attempt_no INTEGER NOT NULL, accepted_at TEXT NOT NULL, started_at TEXT, stdout_path TEXT, stderr_path TEXT, exit_code INTEGER, status TEXT NOT NULL, updated_at TEXT, PRIMARY KEY (run_id, slot_type, role_type, attempt_id), UNIQUE (run_id, slot_type, role_type, attempt_no));",
  "CREATE TABLE audit_logs (event_id TEXT PRIMARY KEY, event_name TEXT NOT NULL, schema_version TEXT NOT NULL, run_id TEXT NOT NULL, parent_run_id TEXT, slot TEXT NOT NULL, attempt_id TEXT NOT NULL, occurred_at TEXT NOT NULL, actor TEXT NOT NULL, operation TEXT NOT NULL, outcome TEXT NOT NULL, final_status TEXT, error_code TEXT, previous_hash TEXT, event_hash TEXT NOT NULL, UNIQUE (run_id, slot, attempt_id, event_name));",
  "CREATE TABLE audit_chain_heads (run_id TEXT PRIMARY KEY, head_event_id TEXT NOT NULL, head_hash TEXT NOT NULL, chain_length INTEGER NOT NULL, updated_at TEXT NOT NULL);",
  "CREATE TABLE rapid_crosscheck_requests (run_id TEXT PRIMARY KEY, parent_run_id TEXT, job_id TEXT, blue_run_id TEXT, green_run_id TEXT, blue_attempt_id TEXT, green_attempt_id TEXT, comparison_definition_valid_from TEXT, requested_at TEXT, status TEXT, lease_expires_at TEXT, worker_id TEXT);",
].join(" ");

// ジョブマップ fixture(spec.md の Given 値)。ファイル形式は未契約(issues/20260817T000000Z)のため
// 検証境界の仮形式(JSON・slot 別エントリ)とし、S4 が実装形式に合わせて調整してよい
const JOB_MAP_V140 = {
  version: "v1.4.0",
  jobs: {
    "daily-settlement": {
      hang_detect_limit_minutes: 30,
      slots: {
        blue: { host: "blue-host-01", exec_user: "batchuser", script_path: "/opt/blue/run.sh", work_dir: "/opt/relaygate/work", fixed_args: [], impl_version: "blue-2.3.1", credential_ref: "cred-blue-batch" },
        green: { host: "green-host-01", exec_user: "batchuser", script_path: "/opt/green/run.sh", work_dir: "/opt/relaygate/work", fixed_args: [], impl_version: "green-0.9.0", credential_ref: "cred-green-batch" },
      },
    },
  },
};

function execute(command, args, options = {}) {
  return spawnSync(command, args, { encoding: "utf8", ...options });
}

function notImplemented(step) {
  throw new Error(`not implemented (S2 scaffold, spec 20260819_114307): ${step}`);
}

Before(function () {
  this.testDir = mkdtempSync(join(tmpdir(), "relaygate-tier-facade-select-slot-"));
  this.dbPath = join(this.testDir, "relaygate.db");
  this.jobMapPath = join(this.testDir, "job-map.json");
  this.launchLogPath = join(this.testDir, "launch.log");
  const binDir = join(this.testDir, "bin");
  mkdirSync(binDir);
  writeFileSync(join(binDir, "ssh"), "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"$RELAYGATE_TEST_LAUNCH_LOG\"\nexit 0\n", { mode: 0o755 });
  writeFileSync(this.jobMapPath, JSON.stringify(JOB_MAP_V140));
  const schema = execute("sqlite3", [this.dbPath, CONTRACT_SCHEMA]);
  if (schema.status !== 0) throw new Error(`failed to create SQLite contract schema: ${schema.stderr}`);
  this.env = { ...process.env, PATH: `${binDir}:${process.env.PATH}`, RELAYGATE_TEST_LAUNCH_LOG: this.launchLogPath, RELAYGATE_RDB_DSN: `sqlite://${this.dbPath}`, RELAYGATE_JOB_MAP_PATH: this.jobMapPath };
});

After(function () { rmSync(this.testDir, { recursive: true, force: true }); });

// ---- Given(環境変数・fixture。新仕様で RELAYGATE_OPERATOR が必須になった) ----
Given("環境変数 BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on, RELAYGATE_OPERATOR=ops-tanaka が設定されている", function () {
  Object.assign(this.env, { BLUE_MODE: "foreground", GREEN_MODE: "background", RAPID_CROSSCHECK_MODE: "on", RELAYGATE_OPERATOR: "ops-tanaka" });
});
Given("環境変数 BLUE_MODE=foreground, GREEN_MODE=foreground, RELAYGATE_OPERATOR=ops-tanaka が設定されている", function () {
  Object.assign(this.env, { BLUE_MODE: "foreground", GREEN_MODE: "foreground", RELAYGATE_OPERATOR: "ops-tanaka" });
});
Given('ジョブマップ v1.4.0 で job_id {string} が blue（host=blue-host-01, impl_version=blue-2.3.1）と green（host=green-host-01, impl_version=green-0.9.0）に解決できる', function (_jobId) {
  notImplemented("job map v1.4.0 resolves blue/green entries (job map file format is decided in S4)");
});
Given('ジョブマップ v1.4.0 で job_id {string} が解決できる', function (_jobId) {
  notImplemented("job map v1.4.0 resolves job_id (job map file format is decided in S4)");
});
Given('run_id発番が {string} を返すよう固定されている', function (_runId) {
  notImplemented("fixed run_id generator (id generation seam is decided in S4)");
});
Given("audit_logs へのINSERTが失敗する状態になっている", function () {
  notImplemented("inject audit_logs INSERT failure (for example a SQLite BEFORE INSERT trigger raising ABORT)");
});

// ---- When(文言不変。旧実装を引き継ぐ) ----
When(/^`relaygate concurrent-run select-slot --job-id ([^`]+)` を実行する$/, function (jobId) {
  this.result = execute(relaygate, ["concurrent-run", "select-slot", "--job-id", jobId], { env: this.env });
});

// ---- Then ----
Then("終了コード {int} で終了する", function (exitCode) {
  if (this.result.status !== exitCode) throw new Error(`expected exit ${exitCode}, got ${this.result.status}: ${this.result.stderr}`);
});
Then('execution_specs に run_id={string} の1行がINSERTされる', function (_runId) {
  notImplemented("assert execution_specs row by run_id");
});
Then('slot_execution_specs に slot_type={string} と slot_type={string} の2行がINSERTされる', function (_blue, _green) {
  notImplemented("assert slot_execution_specs rows for blue and green");
});
Then('runner_results に status={string} の2行と、runner_result_events に event_name={string} の2行が同一transactionでINSERTされる', function (_status, _eventName) {
  notImplemented("assert runner_results STARTING snapshot and runner_result_events attempt_started history");
});
Then('audit_logs に event_name={string} と event_name={string} の起動前監査イベントがINSERTされる', function (_accepted, _attempted) {
  notImplemented("assert audit_logs slot_launch_accepted / slot_launch_attempted");
});
Then("execution_specs・slot_execution_specs へのINSERTは発生しない", function () {
  notImplemented("assert no rows in execution_specs and slot_execution_specs");
});
Then("execution_specs・slot_execution_specs・runner_results・runner_result_events へのINSERTはrollbackされ残らない", function () {
  notImplemented("assert rollback left no rows in the four tables");
});
Then("外部slotへの起動イベントは送出されない", function () {
  notImplemented("assert launch log is empty");
});
