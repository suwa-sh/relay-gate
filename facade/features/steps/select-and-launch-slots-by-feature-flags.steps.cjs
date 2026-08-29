// tier-facade BDD step definitions(③)。S2 scoped 再実行(spec 20260829_210828_spec_generation 還流: CR-6078c4ed-011〜018)。
// 方針:
//   - 文言が変わっていない step は attempt 6 で結線済みの実装を継承し、新仕様で追加・変更された Then は
//     「未実装(not implemented)」を明示して fail する skeleton にする(S4 が結線する)
//   - ハーネスは新契約に合わせる: slot 別ジョブマップ(RELAYGATE_JOB_MAP_PATH_BLUE / _GREEN、cli-command-contract.yaml
//     job_map_contract の形式)、認証情報ディレクトリ(RELAYGATE_CREDENTIAL_DIR、credential_resolution)、
//     rdb-schema.yaml の新スキーマ(job_map_version は slot_execution_specs へ移動)
//   - 仕様の Given は /etc/relaygate/... の絶対パスを使う。ハーネスは一時ディレクトリ配下に同じ相対構造
//     ({testDir}/etc/relaygate/job-map.blue.json 等)を作り、標準エラーの照合時に {testDir} 接頭辞を取り除いて
//     仕様の文言(path=/etc/relaygate/job-map.green.json)と突き合わせる
//   - RDB の正本は PostgreSQL だが、既存の限定検証境界(issues/20260817T230000Z・issues/20260821T220045Z §1)に従い SQLite で検証する
//   - run_id / attempt_id 発番の固定は実装の seam RELAYGATE_ID_GENERATOR(facade/src/id_gateway.sh)を使う
//   - 起動イベントは PATH 先頭の ssh スタブが受け取り、引数列(`$*`)を起動ログへ 1 行ずつ追記する。
//     送出失敗・timeout は接続先ホスト名で振る舞いを切り替えるスタブで再現する
const { After, Before, Given, Then, When, setDefaultTimeout } = require("@cucumber/cucumber");
const { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } = require("node:fs");
const { tmpdir } = require("node:os");
const { join, resolve } = require("node:path");
const { spawnSync } = require("node:child_process");

// SSH timeout の Scenario は facade の deadline(10 秒以内)まで待つため、cucumber 既定の 5 秒では足りない
setDefaultTimeout(60 * 1000);

const projectRoot = resolve(__dirname, "../../..");
const relaygate = join(projectRoot, "facade/bin/relaygate");
const SPEC_EVENT = "20260829_210828_spec_generation";

// 新仕様の検証用 SQLite スキーマ(列は契約定数 schema-constants.sh と同一。PK / UNIQUE は rdb-schema.yaml に従う)
const CONTRACT_SCHEMA = [
  "CREATE TABLE execution_specs (run_id TEXT PRIMARY KEY, parent_run_id TEXT REFERENCES execution_specs(run_id), job_id TEXT NOT NULL, additional_args TEXT, hang_detect_limit_minutes INTEGER NOT NULL);",
  "CREATE TABLE slot_execution_specs (run_id TEXT NOT NULL REFERENCES execution_specs(run_id), slot_type TEXT NOT NULL, host TEXT NOT NULL, exec_user TEXT NOT NULL, script_path TEXT NOT NULL, work_dir TEXT NOT NULL, fixed_args TEXT, impl_version TEXT NOT NULL, credential_ref TEXT, job_map_version TEXT NOT NULL, PRIMARY KEY (run_id, slot_type));",
  "CREATE TABLE runner_result_events (event_id TEXT PRIMARY KEY, run_id TEXT NOT NULL, slot_type TEXT NOT NULL, role_type TEXT NOT NULL, attempt_id TEXT NOT NULL, attempt_no INTEGER NOT NULL, event_name TEXT NOT NULL, status TEXT NOT NULL, occurred_at TEXT NOT NULL, started_at TEXT, stdout_path TEXT, stderr_path TEXT, exit_code INTEGER, UNIQUE (run_id, slot_type, role_type, attempt_id, event_name));",
  "CREATE TABLE runner_results (run_id TEXT NOT NULL, slot_type TEXT NOT NULL, role_type TEXT NOT NULL, attempt_id TEXT NOT NULL, attempt_no INTEGER NOT NULL, accepted_at TEXT NOT NULL, started_at TEXT, stdout_path TEXT, stderr_path TEXT, exit_code INTEGER, status TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY (run_id, slot_type, role_type, attempt_id), UNIQUE (run_id, slot_type, role_type, attempt_no));",
  "CREATE TABLE audit_logs (event_id TEXT PRIMARY KEY, event_name TEXT NOT NULL, schema_version TEXT NOT NULL, run_id TEXT NOT NULL, parent_run_id TEXT, slot TEXT NOT NULL, attempt_id TEXT NOT NULL, occurred_at TEXT NOT NULL, actor TEXT NOT NULL, operation TEXT NOT NULL, outcome TEXT NOT NULL, final_status TEXT, error_code TEXT, previous_hash TEXT, event_hash TEXT NOT NULL, UNIQUE (run_id, slot, attempt_id, event_name));",
  "CREATE TABLE audit_chain_heads (run_id TEXT PRIMARY KEY, head_event_id TEXT NOT NULL, head_hash TEXT NOT NULL, chain_length INTEGER NOT NULL, updated_at TEXT NOT NULL);",
  "CREATE TABLE rapid_crosscheck_requests (run_id TEXT PRIMARY KEY, parent_run_id TEXT, job_id TEXT, blue_run_id TEXT, green_run_id TEXT, blue_attempt_id TEXT, green_attempt_id TEXT, comparison_definition_valid_from TEXT, requested_at TEXT, status TEXT, lease_expires_at TEXT, worker_id TEXT);",
].join(" ");

// ssh スタブ: 接続先ホストにより「成功 / 接続失敗(exit 255)/ 送出 timeout(応答しない)」を切り替える。
// 起動イベント(引数列)は結果にかかわらず起動ログへ追記する
const SSH_STUB = [
  "#!/usr/bin/env bash",
  "printf '%s\\n' \"$*\" >>\"$RELAYGATE_TEST_LAUNCH_LOG\"",
  "target=\"$5\"",
  "if [[ -n ${RELAYGATE_TEST_SSH_FAIL_HOST:-} && $target == *\"@${RELAYGATE_TEST_SSH_FAIL_HOST}\" ]]; then exit 255; fi",
  "if [[ -n ${RELAYGATE_TEST_SSH_HANG_HOST:-} && $target == *\"@${RELAYGATE_TEST_SSH_HANG_HOST}\" ]]; then sleep 120; fi",
  "exit 0",
  "",
].join("\n");

// literal は feature の step 文言をそのまま完全一致の正規表現にする(ASCII 記号のエスケープ漏れを防ぐ)
function literal(text) {
  return new RegExp(`^${text.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&")}$`);
}

// notImplemented は S2 skeleton の明示的な未実装 fail(S4 が結線する)
function notImplemented(step) {
  throw new Error(`not implemented: S2 scaffold (spec ${SPEC_EVENT}) — step "${step}" is wired in S4 tier-impl`);
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

// ジョブマップ fixture(cli-command-contract.yaml job_map_contract の形式。値は tier-facade.md の Background)
function jobMapDocument(slot, entryOverrides = {}) {
  const base = slot === "blue"
    ? { host: "blue-host-01", exec_user: "batchuser", script_path: "/opt/blue/run.sh", work_dir: "/opt/relaygate/work", fixed_args: ["--mode", "batch"], impl_version: "blue-2.3.1", credential_ref: "cred-blue-batch", hang_detect_limit_minutes: 30 }
    : { host: "green-host-01", exec_user: "batchuser", script_path: "/opt/green/run.sh", work_dir: "/opt/relaygate/work", fixed_args: [], impl_version: "green-0.9.0", credential_ref: "cred-green-batch", hang_detect_limit_minutes: 45 };
  return { job_map_version: "v1.4.0", slot_type: slot, jobs: { "daily-settlement": { ...base, ...entryOverrides } } };
}

function writeJobMap(world, slot, document) {
  world.jobMaps[slot] = document;
  writeFileSync(world.jobMapPaths[slot], JSON.stringify(document));
}

// installIdGenerator は実装の発番 seam(`<generator> <kind> [<qualifier>]`)へ固定値を返す generator を差し込む。
// attempt_id の qualifier は slot 名(facade/src/id_gateway.sh issue_run_identity)。固定しない種別は uuidgen に委ねる
function installIdGenerator(world) {
  const attemptCases = Object.entries(world.fixedAttemptIds).map(([slot, id]) => `      ${slot}) printf '%s' ${JSON.stringify(id)} ;;`);
  const runIdCase = world.fixedRunId ? [`  run_id) printf '%s' ${JSON.stringify(world.fixedRunId)} ;;`] : [];
  const script = [
    "#!/usr/bin/env bash",
    'case "$1" in',
    ...runIdCase,
    "  attempt_id)",
    '    case "$2" in',
    ...attemptCases,
    "      *) uuidgen | tr '[:upper:]' '[:lower:]' ;;",
    "    esac ;;",
    "  *) uuidgen | tr '[:upper:]' '[:lower:]' ;;",
    "esac",
    "",
  ].join("\n");
  const generatorPath = join(world.binDir, "fixed-id-generator");
  writeFileSync(generatorPath, script, { mode: 0o755 });
  world.env.RELAYGATE_ID_GENERATOR = generatorPath;
}

// normalizedStderr は一時ディレクトリの接頭辞を取り除き、仕様の /etc/relaygate/... 表記と比較できる形にする
function normalizedStderr(world) {
  return world.result.stderr.split(world.testDir).join("");
}

Before(function () {
  this.testDir = mkdtempSync(join(tmpdir(), "relaygate-tier-facade-select-slot-"));
  this.dbPath = join(this.testDir, "relaygate.db");
  this.etcDir = join(this.testDir, "etc", "relaygate");
  this.credentialDir = join(this.etcDir, "credentials");
  mkdirSync(this.credentialDir, { recursive: true });
  this.jobMapPaths = { blue: join(this.etcDir, "job-map.blue.json"), green: join(this.etcDir, "job-map.green.json") };
  this.jobMaps = {};
  this.launchLogPath = join(this.testDir, "launch.log");
  this.binDir = join(this.testDir, "bin");
  mkdirSync(this.binDir);
  writeFileSync(join(this.binDir, "ssh"), SSH_STUB, { mode: 0o755 });
  this.fixedRunId = null;
  this.fixedAttemptIds = {};
  const schema = execute("sqlite3", [this.dbPath, CONTRACT_SCHEMA]);
  if (schema.status !== 0) throw new Error(`failed to create SQLite contract schema: ${schema.stderr}`);
  this.env = { ...process.env, PATH: `${this.binDir}:${process.env.PATH}`, RELAYGATE_TEST_LAUNCH_LOG: this.launchLogPath, RELAYGATE_RDB_DSN: `sqlite://${this.dbPath}` };
});

After(function () { rmSync(this.testDir, { recursive: true, force: true }); });

// ---- Background ----
Given(literal("環境変数 RELAYGATE_JOB_MAP_PATH_BLUE=/etc/relaygate/job-map.blue.json, RELAYGATE_JOB_MAP_PATH_GREEN=/etc/relaygate/job-map.green.json, RELAYGATE_CREDENTIAL_DIR=/etc/relaygate/credentials が設定されている"), function () {
  Object.assign(this.env, { RELAYGATE_JOB_MAP_PATH_BLUE: this.jobMapPaths.blue, RELAYGATE_JOB_MAP_PATH_GREEN: this.jobMapPaths.green, RELAYGATE_CREDENTIAL_DIR: this.credentialDir });
  // credential_resolution: {RELAYGATE_CREDENTIAL_DIR}/{credential_ref} を 0600 で配置する
  for (const ref of ["cred-blue-batch", "cred-green-batch"]) {
    writeFileSync(join(this.credentialDir, ref), `-----BEGIN OPENSSH PRIVATE KEY-----\ntier-facade-test-key ${ref}\n-----END OPENSSH PRIVATE KEY-----\n`, { mode: 0o600 });
  }
});
Given(literal('blue のジョブマップは job_map_version="v1.4.0", slot_type="blue" で job_id "daily-settlement" が host=blue-host-01, impl_version=blue-2.3.1, fixed_args=["--mode","batch"], credential_ref=cred-blue-batch, hang_detect_limit_minutes=30 に解決できる'), function () {
  writeJobMap(this, "blue", jobMapDocument("blue"));
});
Given(literal('green のジョブマップは job_map_version="v1.4.0", slot_type="green" で job_id "daily-settlement" が host=green-host-01, impl_version=green-0.9.0, credential_ref=cred-green-batch, hang_detect_limit_minutes=45 に解決できる'), function () {
  writeJobMap(this, "green", jobMapDocument("green"));
});

// ---- Given(環境変数・発番・外部状態) ----
Given(/^環境変数 BLUE_MODE=(off|background|foreground), GREEN_MODE=(off|background|foreground), RAPID_CROSSCHECK_MODE=(on|off), RELAYGATE_OPERATOR=ops-tanaka が設定されている$/, function (blue, green, rapid) {
  Object.assign(this.env, { BLUE_MODE: blue, GREEN_MODE: green, RAPID_CROSSCHECK_MODE: rapid, RELAYGATE_OPERATOR: "ops-tanaka" });
});
Given("環境変数 BLUE_MODE=foreground, GREEN_MODE=foreground, RELAYGATE_OPERATOR=ops-tanaka が設定されている", function () {
  Object.assign(this.env, { BLUE_MODE: "foreground", GREEN_MODE: "foreground", RELAYGATE_OPERATOR: "ops-tanaka" });
});
Given(/^run_id発番が "([^"]+)" を返すよう固定されている$/, function (runId) {
  this.fixedRunId = runId;
  installIdGenerator(this);
});
Given(/^attempt_id発番が (blue|green)="([^"]+)" を返すよう固定されている$/, function (slot, attemptId) {
  this.fixedAttemptIds[slot] = attemptId;
  installIdGenerator(this);
});
Given(literal('green のジョブマップの jobs."daily-settlement" に host が定義されていない'), function () {
  const document = jobMapDocument("green");
  delete document.jobs["daily-settlement"].host;
  writeJobMap(this, "green", document);
});
Given("audit_logs へのINSERTが失敗する状態になっている", function () {
  const trigger = execute("sqlite3", [this.dbPath, "CREATE TRIGGER reject_audit BEFORE INSERT ON audit_logs BEGIN SELECT RAISE(ABORT, 'injected audit failure'); END;"]);
  if (trigger.status !== 0) throw new Error(`failed to inject audit_logs failure: ${trigger.stderr}`);
});
Given(literal("green実装ホスト green-host-01 へのSSH接続が失敗する状態である"), function () {
  this.env.RELAYGATE_TEST_SSH_FAIL_HOST = "green-host-01";
});
Given(literal("blue実装ホスト blue-host-01 へのSSH起動イベント送出がtimeoutする状態である"), function () {
  this.env.RELAYGATE_TEST_SSH_HANG_HOST = "blue-host-01";
});

// ---- When ----
When(/^`relaygate concurrent-run select-slot --job-id ([^`]+)` を実行する$/, function (jobId) {
  this.result = execute(relaygate, ["concurrent-run", "select-slot", "--job-id", jobId], { env: this.env });
});
When(literal('追加引数 `--note` と `a b "c"`（空白と二重引用符を含む1要素）を渡して `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する'), function () {
  // 追加引数は argv の要素としてそのまま渡す(シェルの再分割を経由しない)
  this.result = execute(relaygate, ["concurrent-run", "select-slot", "--job-id", "daily-settlement", "--", "--note", 'a b "c"'], { env: this.env });
});

// ---- Then(汎用: 終了コード・標準エラー・未発生の検証は結線済み) ----
Then("終了コード {int} で終了する", function (exitCode) {
  if (this.result.status !== exitCode) throw new Error(`expected exit ${exitCode}, got ${this.result.status}: ${this.result.stderr}`);
});
Then(/^標準エラーに "([^"]+)" が出力される$/, function (message) {
  const stderr = normalizedStderr(this);
  if (!stderr.includes(message)) throw new Error(`stderr does not contain ${JSON.stringify(message)}: ${stderr}`);
});
Then("execution_specs・slot_execution_specs へのINSERTは発生しない", function () {
  assertEqual(countRows(this.dbPath, "execution_specs"), 0, "execution_specs rows");
  assertEqual(countRows(this.dbPath, "slot_execution_specs"), 0, "slot_execution_specs rows");
});
Then("execution_specs・slot_execution_specs・runner_results・audit_logs へのINSERTは発生しない", function () {
  for (const table of ["execution_specs", "slot_execution_specs", "runner_results", "audit_logs"]) {
    assertEqual(countRows(this.dbPath, table), 0, `${table} rows`);
  }
});
Then("execution_specs・slot_execution_specs・runner_results・runner_result_events へのINSERTはrollbackされ残らない", function () {
  for (const table of ["execution_specs", "slot_execution_specs", "runner_results", "runner_result_events"]) {
    assertEqual(countRows(this.dbPath, table), 0, `${table} rows`);
  }
});
Then("外部slotへの起動イベントは送出されない", function () {
  if (existsSync(this.launchLogPath)) throw new Error("launch log exists: a slot launch event was emitted");
});

// ---- Then(文言不変: attempt 6 の結線を継承) ----
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

// ---- Then(新仕様で追加・変更: S4 tier-impl で結線) ----
Then(literal('execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", hang_detect_limit_minutes=45 の1行がINSERTされる'), function () {
  const rows = query(this.dbPath, "SELECT run_id, hang_detect_limit_minutes, job_id, additional_args, (parent_run_id IS NULL) FROM execution_specs;");
  assertEqual(rows.length, 1, "execution_specs rows");
  assertEqual(rows[0].join("|"), "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57|45|daily-settlement|[]|1", "execution_specs row");
});
Then(literal('slot_execution_specs に slot_type="blue" と slot_type="green" の2行が job_map_version="v1.4.0" でINSERTされる'), function () {
  const rows = query(this.dbPath, "SELECT slot_type, job_map_version, host, impl_version, credential_ref FROM slot_execution_specs ORDER BY slot_type;");
  assertEqual(rows.map((row) => row.join("|")).join("\n"), "blue|v1.4.0|blue-host-01|blue-2.3.1|cred-blue-batch\ngreen|v1.4.0|green-host-01|green-0.9.0|cred-green-batch", "slot_execution_specs rows");
  assertEqual(query(this.dbPath, "SELECT COUNT(DISTINCT run_id) FROM slot_execution_specs;")[0][0], "1", "slot_execution_specs run_id");
});

// assertCompensation は補償記録(履歴 INSERT + snapshot UPDATE が同一時刻で対応する)を検証する
function assertCompensation(world, slot, role, attemptId, status, eventName) {
  assertEqual(query(world.dbPath, `SELECT status, (exit_code IS NULL) FROM runner_results WHERE slot_type = '${slot}' AND role_type = '${role}' AND attempt_id = '${attemptId}';`)[0].join("|"), `${status}|1`, `runner_results ${slot}`);
  assertEqual(query(world.dbPath, `SELECT event_name || ':' || status FROM runner_result_events WHERE slot_type = '${slot}' ORDER BY occurred_at;`).map((row) => row[0]).join("\n"), `attempt_started:STARTING\n${eventName}:${status}`, `runner_result_events ${slot}`);
  assertEqual(query(world.dbPath, `SELECT COUNT(*) FROM runner_results r JOIN runner_result_events e ON e.run_id = r.run_id AND e.slot_type = r.slot_type AND e.role_type = r.role_type AND e.attempt_id = r.attempt_id AND e.event_name = '${eventName}' AND e.occurred_at = r.updated_at WHERE r.slot_type = '${slot}';`)[0][0], "1", `history/snapshot pairing ${slot}`);
}

// assertPostLaunchAudit は起動後監査イベントがチェーン先頭へ追記されていることを検証する
function assertPostLaunchAudit(world, slot, attemptId, eventName, outcome, errorCode) {
  const rows = query(world.dbPath, `SELECT slot, attempt_id, outcome, error_code, actor, operation FROM audit_logs WHERE event_name = '${eventName}';`);
  assertEqual(rows.length, 1, `${eventName} rows`);
  assertEqual(rows[0].join("|"), `${slot}|${attemptId}|${outcome}|${errorCode}|ops-tanaka|slot_launch`, eventName);
  assertEqual(query(world.dbPath, `SELECT COUNT(*) FROM audit_logs f JOIN audit_logs p ON p.event_hash = f.previous_hash AND p.run_id = f.run_id WHERE f.event_name = '${eventName}';`)[0][0], "1", `${eventName} chained`);
  assertEqual(query(world.dbPath, `SELECT COUNT(*) FROM audit_chain_heads h JOIN audit_logs f ON f.event_id = h.head_event_id AND f.event_hash = h.head_hash AND f.run_id = h.run_id WHERE f.event_name = '${eventName}' AND h.chain_length = (SELECT COUNT(*) FROM audit_logs);`)[0][0], "1", `${eventName} is chain head`);
}

Then(literal('runner_results の green/background/att-green-0001 行が status="FAILED" へ更新され、runner_result_events に event_name="attempt_failed" の履歴が同一transactionでINSERTされる'), function () {
  assertCompensation(this, "green", "background", "att-green-0001", "FAILED", "attempt_failed");
});
Then(literal('audit_logs に (slot="green", attempt_id="att-green-0001", event_name="slot_launch_failed", outcome="failed", error_code="launch_event_send_failed") がINSERTされる'), function () {
  assertPostLaunchAudit(this, "green", "att-green-0001", "slot_launch_failed", "failed", "launch_event_send_failed");
});
Then(literal("標準出力には選択slotごとの status=STARTING 行が出力される"), function () {
  const lines = this.result.stdout.split("\n").filter((line) => line.length > 0);
  assertEqual(lines.length, 2, "stdout lines");
  for (const slot of ["blue", "green"]) {
    if (!lines.some((line) => line.includes(`slot_type=${slot} `) && line.endsWith("status=STARTING"))) throw new Error(`stdout has no STARTING line for ${slot}: ${this.result.stdout}`);
  }
});
Then(literal('runner_results の blue/foreground/att-blue-0001 行が status="UNKNOWN" へ更新され、runner_result_events に event_name="attempt_unknown" の履歴が同一transactionでINSERTされる'), function () {
  assertCompensation(this, "blue", "foreground", "att-blue-0001", "UNKNOWN", "attempt_unknown");
  assertEqual(query(this.dbPath, "SELECT COUNT(*) FROM audit_logs WHERE event_name = 'slot_launch_failed';")[0][0], "0", "no FAILED guess");
});
Then(literal('audit_logs に (slot="blue", attempt_id="att-blue-0001", event_name="slot_launch_timeout", outcome="timeout", error_code="launch_event_send_timeout") がINSERTされる'), function () {
  assertPostLaunchAudit(this, "blue", "att-blue-0001", "slot_launch_timeout", "timeout", "launch_event_send_timeout");
});
Then(literal('execution_specs の additional_args にJSON配列 ["--note","a b \\"c\\""] が保存される'), function () {
  const saved = query(this.dbPath, "SELECT additional_args FROM execution_specs;")[0][0];
  assertEqual(JSON.stringify(JSON.parse(saved)), JSON.stringify(["--note", 'a b "c"']), "additional_args");
});
Then(literal('blue実装への起動イベントのargvは fixed_args の要素に additional_args の要素を後置連結した ["--mode","batch","--note","a b \\"c\\""] である'), function () {
  // 起動ログの行(ssh 引数列)からリモートコマンド(user@host の次の要素)を取り出し、スクリプトパス以降の argv を
  // リモート側と同じ bash の単語分割で復元して比較する
  const line = readFileSync(this.launchLogPath, "utf8").split("\n").find((entry) => entry.includes("batchuser@blue-host-01 "));
  if (!line) throw new Error("no launch event for blue-host-01");
  const remoteCommand = line.slice(line.indexOf("batchuser@blue-host-01 ") + "batchuser@blue-host-01 ".length);
  const argvPart = remoteCommand.slice(remoteCommand.indexOf(" /opt/blue/run.sh") + " /opt/blue/run.sh".length);
  const restored = execute("bash", ["-c", `eval "set -- $1"; printf '%s\\0' "$@"`, "bash", argvPart]);
  if (restored.status !== 0) throw new Error(`argv restore failed: ${restored.stderr}`);
  const argv = restored.stdout.split("\0").slice(0, -1);
  assertEqual(JSON.stringify(argv), JSON.stringify(["--mode", "batch", "--note", 'a b "c"']), "argv");
});
