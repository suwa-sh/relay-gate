// tier-facade BDD step definitions(③)。S2 scoped 再実行(spec 20260819_114307 還流)の skeleton を S4 attempt 5 で結線した。
// 方針:
//   - ハーネス(一時ディレクトリ・SQLite スキーマ・ssh スタブ)は新仕様の 11 テーブル契約
//     (packages/contracts/relay-gate-db/schema-constants.sh)に合わせて用意する
//   - RDB の正本は PostgreSQL だが、既存の限定検証境界(issues/20260817T230000Z・issues/20260821T220045Z §1)に従い SQLite で検証する
//   - run_id 発番の固定は実装の seam RELAYGATE_ID_GENERATOR(facade/src/id_gateway.sh)を使う
//   - ジョブマップの形式は facade/src/job_map_gateway.sh 冒頭コメントの検証境界形式(JSON・slot 別エントリ)
const { After, Before, Given, Then, When } = require("@cucumber/cucumber");
const { existsSync, mkdtempSync, mkdirSync, rmSync, writeFileSync } = require("node:fs");
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

// ジョブマップ fixture(spec.md の Given 値 + S2 が補った credential_ref。issues/20260821T220045Z §3)
function jobMapV140(jobId) {
  return {
    version: "v1.4.0",
    jobs: {
      [jobId]: {
        hang_detect_limit_minutes: 30,
        slots: {
          blue: { host: "blue-host-01", exec_user: "batchuser", script_path: "/opt/blue/run.sh", work_dir: "/opt/relaygate/work", fixed_args: [], impl_version: "blue-2.3.1", credential_ref: "cred-blue-batch" },
          green: { host: "green-host-01", exec_user: "batchuser", script_path: "/opt/green/run.sh", work_dir: "/opt/relaygate/work", fixed_args: [], impl_version: "green-0.9.0", credential_ref: "cred-green-batch" },
        },
      },
    },
  };
}

function execute(command, args, options = {}) {
  return spawnSync(command, args, { encoding: "utf8", ...options });
}

// query は検証用 SQLite に SQL を投げ、行ごとの文字列配列で返す
function query(dbPath, sql) {
  const result = execute("sqlite3", ["-separator", "\t", dbPath, sql]);
  if (result.status !== 0) throw new Error(`sqlite3 query failed: ${result.stderr}`);
  return result.stdout.split("\n").filter((line) => line.length > 0).map((line) => line.split("\t"));
}

function countRows(dbPath, table) {
  return Number(query(dbPath, `SELECT COUNT(*) FROM ${table};`)[0][0]);
}

function assertEqual(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

Before(function () {
  this.testDir = mkdtempSync(join(tmpdir(), "relaygate-tier-facade-select-slot-"));
  this.dbPath = join(this.testDir, "relaygate.db");
  this.jobMapPath = join(this.testDir, "job-map.json");
  this.launchLogPath = join(this.testDir, "launch.log");
  const binDir = join(this.testDir, "bin");
  mkdirSync(binDir);
  writeFileSync(join(binDir, "ssh"), "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"$RELAYGATE_TEST_LAUNCH_LOG\"\nexit 0\n", { mode: 0o755 });
  // Given でジョブマップが与えられない Scenario(バリデーションエラー)でも必須環境変数は揃えておく
  writeFileSync(this.jobMapPath, JSON.stringify({ version: "v1.4.0", jobs: {} }));
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
Given('ジョブマップ v1.4.0 で job_id {string} が blue（host=blue-host-01, impl_version=blue-2.3.1）と green（host=green-host-01, impl_version=green-0.9.0）に解決できる', function (jobId) {
  writeFileSync(this.jobMapPath, JSON.stringify(jobMapV140(jobId)));
});
Given('ジョブマップ v1.4.0 で job_id {string} が解決できる', function (jobId) {
  writeFileSync(this.jobMapPath, JSON.stringify(jobMapV140(jobId)));
});
Given('run_id発番が {string} を返すよう固定されている', function (runId) {
  // 実装の発番 seam(RELAYGATE_ID_GENERATOR)へ run_id だけ固定値を返す generator を差し込む。他の id は uuidgen に委ねる
  const generatorPath = join(this.testDir, "bin", "fixed-run-id");
  writeFileSync(generatorPath, `#!/usr/bin/env bash\nif [[ "$1" == run_id ]]; then printf '%s' ${JSON.stringify(runId)}; else uuidgen | tr '[:upper:]' '[:lower:]'; fi\n`, { mode: 0o755 });
  this.env.RELAYGATE_ID_GENERATOR = generatorPath;
});
Given("audit_logs へのINSERTが失敗する状態になっている", function () {
  const trigger = execute("sqlite3", [this.dbPath, "CREATE TRIGGER reject_audit BEFORE INSERT ON audit_logs BEGIN SELECT RAISE(ABORT, 'injected audit failure'); END;"]);
  if (trigger.status !== 0) throw new Error(`failed to inject audit_logs failure: ${trigger.stderr}`);
});

// ---- When ----
When(/^`relaygate concurrent-run select-slot --job-id ([^`]+)` を実行する$/, function (jobId) {
  this.result = execute(relaygate, ["concurrent-run", "select-slot", "--job-id", jobId], { env: this.env });
});

// ---- Then ----
Then("終了コード {int} で終了する", function (exitCode) {
  if (this.result.status !== exitCode) throw new Error(`expected exit ${exitCode}, got ${this.result.status}: ${this.result.stderr}`);
});
Then('execution_specs に run_id={string} の1行がINSERTされる', function (runId) {
  assertEqual(countRows(this.dbPath, "execution_specs"), 1, "execution_specs rows");
  assertEqual(query(this.dbPath, "SELECT run_id FROM execution_specs;")[0][0], runId, "execution_specs.run_id");
});
Then('slot_execution_specs に slot_type={string} と slot_type={string} の2行がINSERTされる', function (first, second) {
  const rows = query(this.dbPath, "SELECT slot_type FROM slot_execution_specs ORDER BY slot_type;").map((row) => row[0]);
  assertEqual(rows.join(","), [first, second].sort().join(","), "slot_execution_specs.slot_type");
  assertEqual(query(this.dbPath, "SELECT COUNT(DISTINCT run_id) FROM slot_execution_specs;")[0][0], "1", "slot_execution_specs run_id");
});
Then('runner_results に status={string} の2行と、runner_result_events に event_name={string} の2行が同一transactionでINSERTされる', function (status, eventName) {
  assertEqual(query(this.dbPath, `SELECT COUNT(*) FROM runner_results WHERE status = '${status}';`)[0][0], "2", "runner_results STARTING rows");
  assertEqual(query(this.dbPath, `SELECT COUNT(*) FROM runner_result_events WHERE event_name = '${eventName}' AND status = '${status}';`)[0][0], "2", "runner_result_events attempt_started rows");
  // 同一 transaction の検証: 履歴と snapshot が同じ起動試行 identity(run_id, slot_type, role_type, attempt_id)と同じ受付時刻で対応する
  assertEqual(query(this.dbPath, "SELECT COUNT(*) FROM runner_results r JOIN runner_result_events e ON e.run_id = r.run_id AND e.slot_type = r.slot_type AND e.role_type = r.role_type AND e.attempt_id = r.attempt_id AND e.occurred_at = r.accepted_at;")[0][0], "2", "history/snapshot pairing");
});
Then('audit_logs に event_name={string} と event_name={string} の起動前監査イベントがINSERTされる', function (accepted, attempted) {
  assertEqual(query(this.dbPath, `SELECT slot || '|' || attempt_id || '|' || actor || '|' || operation || '|' || outcome FROM audit_logs WHERE event_name = '${accepted}';`)[0][0], "-|-|ops-tanaka|slot_launch|accepted", "slot_launch_accepted");
  assertEqual(query(this.dbPath, `SELECT COUNT(*) FROM audit_logs WHERE event_name = '${attempted}' AND slot IN ('blue', 'green') AND attempt_id <> '-';`)[0][0], "2", "slot_launch_attempted rows");
  assertEqual(query(this.dbPath, "SELECT COUNT(*) FROM audit_chain_heads h JOIN audit_logs a ON a.event_id = h.head_event_id AND a.event_hash = h.head_hash AND a.run_id = h.run_id;")[0][0], "1", "audit_chain_heads head");
});
Then("execution_specs・slot_execution_specs へのINSERTは発生しない", function () {
  assertEqual(countRows(this.dbPath, "execution_specs"), 0, "execution_specs rows");
  assertEqual(countRows(this.dbPath, "slot_execution_specs"), 0, "slot_execution_specs rows");
});
Then("execution_specs・slot_execution_specs・runner_results・runner_result_events へのINSERTはrollbackされ残らない", function () {
  for (const table of ["execution_specs", "slot_execution_specs", "runner_results", "runner_result_events"]) {
    assertEqual(countRows(this.dbPath, table), 0, `${table} rows`);
  }
});
Then("外部slotへの起動イベントは送出されない", function () {
  if (existsSync(this.launchLogPath)) throw new Error("launch log exists: a slot launch event was emitted");
});
