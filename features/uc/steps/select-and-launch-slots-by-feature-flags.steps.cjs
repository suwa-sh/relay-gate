// UC BDD step definitions(②)。S2 scoped 再実行(spec 20260829_210828_spec_generation 還流: CR-6078c4ed-011〜018)。
// 方針:
//   - 本 UC の tier は tier-facade のみ。実 bash プロセス(facade/bin/relaygate)を起動し、RDB・起動イベントの実体で検証する
//   - 文言が変わっていない step は S6(attempt 6)で結線済みの実装を継承し、新仕様で追加・変更された Then は
//     「未実装(not implemented)」を明示して fail する skeleton にする(S6 が結線する)
//   - step 文言に ASCII の "/" "(" ")" "[" が含まれるため cucumber expression ではなく正規表現で定義する
//     (固定文言は literal() で完全一致の正規表現にする)
//   - ハーネスは新契約に合わせる: slot 別ジョブマップ(RELAYGATE_JOB_MAP_PATH_BLUE / _GREEN、cli-command-contract.yaml
//     job_map_contract の形式)、認証情報ディレクトリ(RELAYGATE_CREDENTIAL_DIR、credential_resolution、鍵は 0600)、
//     rdb-schema.yaml の新スキーマ(job_map_version は slot_execution_specs へ移動)
//   - 仕様の Given は /etc/relaygate/... の絶対パスを使う。ハーネスは一時ディレクトリ配下に同じ相対構造
//     ({testDir}/etc/relaygate/job-map.blue.json 等)を作り、標準エラーの照合時に {testDir} 接頭辞を取り除いて
//     仕様の文言(path=/etc/relaygate/job-map.green.json)と突き合わせる
//   - RDB の正本は PostgreSQL だが、既存の限定検証境界(issues/20260817T230000Z・issues/20260821T220045Z §1)に従い SQLite で検証する
//   - run_id / attempt_id 発番の固定は実装の seam RELAYGATE_ID_GENERATOR(facade/src/id_gateway.sh)を使う
//   - 起動イベントは PATH 先頭の ssh スタブが受け取り、引数列(`$*`)を起動ログへ 1 行ずつ追記する。
//     送出失敗(exit 255)・送出 timeout(応答しない)は接続先ホスト名で切り替える。
//     「foreground 実行が完了まで 60 秒かかる」は remote runner を模擬するスタブ(起動イベントを受領して即応答し、
//     60 秒の実行を detached プロセスで模擬)で再現する。RUNNING への遷移は後続 UC c3c7ab31 の責務であり、
//     還流後の仕様(Then は STARTING で存在)ではハーネス注入を要しない(issues/20260830T*_select-slot-reflow-e2e-boundary.md)
const { After, Before, Given, Then, When, setDefaultTimeout } = require("@cucumber/cucumber");
const { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, unlinkSync, writeFileSync } = require("node:fs");
const { spawnSync } = require("node:child_process");
const { tmpdir } = require("node:os");
const { join, resolve } = require("node:path");

// SSH timeout の Scenario は facade の deadline(10 秒以内)まで待つため、cucumber 既定の 5 秒では足りない
setDefaultTimeout(60 * 1000);

const projectRoot = resolve(__dirname, "../../..");
const relaygate = join(projectRoot, "facade", "bin", "relaygate");
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

// 既定の ssh スタブ: 起動イベント(引数列)を起動ログへ追記し、接続先ホストにより成功 / 接続失敗(exit 255)/ 送出 timeout(応答しない)を切り替える
const SSH_STUB_DEFAULT = [
  "#!/usr/bin/env bash",
  "printf '%s\\n' \"$*\" >>\"$RELAYGATE_TEST_LAUNCH_LOG\"",
  "target=\"$5\"",
  "if [[ -n ${RELAYGATE_TEST_SSH_FAIL_HOST:-} && $target == *\"@${RELAYGATE_TEST_SSH_FAIL_HOST}\" ]]; then exit 255; fi",
  "if [[ -n ${RELAYGATE_TEST_SSH_HANG_HOST:-} && $target == *\"@${RELAYGATE_TEST_SSH_HANG_HOST}\" ]]; then sleep 120; fi",
  "exit 0",
  "",
].join("\n");

// remote runner 模擬の ssh スタブ: 起動イベントを受領して即応答し、60 秒の実行を detached プロセスで模擬する
// (facade の SSH は起動イベントの送出(handshake)であり実行完了を待つ契約ではない。issues/20260817T230000Z)。
// 引数列は facade/src/launch_gateway.sh の `ssh -n -o BatchMode=yes -- <user@host> <remote_command>`
const SSH_STUB_LONG_RUNNING = [
  "#!/usr/bin/env bash",
  "set -o errexit -o nounset -o pipefail",
  "printf '%s\\n' \"$*\" >>\"$RELAYGATE_TEST_LAUNCH_LOG\"",
  "remote_command=\"$6\"",
  "slot=''",
  "if [[ $remote_command =~ RELAYGATE_SLOT=(blue|green) ]]; then slot=\"${BASH_REMATCH[1]}\"; fi",
  "perl -MPOSIX=setsid -e 'setsid; exec \"sleep\", \"60\"' </dev/null >/dev/null 2>&1 &",
  "printf '%s' \"$!\" >\"$RELAYGATE_TEST_DIR/${slot:-unknown}-execution.pid\"",
  "exit 0",
  "",
].join("\n");

// literal は feature の step 文言をそのまま完全一致の正規表現にする(ASCII 記号のエスケープ漏れを防ぐ)
function literal(text) {
  return new RegExp(`^${text.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&")}$`);
}

// notImplemented は S2 skeleton の明示的な未実装 fail(S6 が結線する)
function notImplemented(step) {
  throw new Error(`not implemented: S2 scaffold (spec ${SPEC_EVENT}) — step "${step}" is wired in S6 uc-bdd`);
}

function execute(command, args, options = {}) {
  return spawnSync(command, args, { encoding: "utf8", ...options });
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function assertEqual(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

// query は検証用 SQLite に SQL を投げ、行ごとの文字列配列で返す
function query(dbPath, sql) {
  const result = execute("sqlite3", ["-separator", "\t", dbPath, sql]);
  if (result.status !== 0) throw new Error(`sqlite3 query failed: ${result.stderr}`);
  return result.stdout.split("\n").filter((line) => line.length > 0).map((line) => line.split("\t"));
}

function countRows(dbPath, table, where = "1 = 1") {
  return Number(query(dbPath, `SELECT COUNT(*) FROM ${table} WHERE ${where};`)[0][0]);
}

function sqlString(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

// ジョブマップ fixture(cli-command-contract.yaml job_map_contract の形式。値は spec.md の Background)
function jobEntry(slot, overrides = {}) {
  const base = slot === "blue"
    ? { host: "blue-host-01", exec_user: "batchuser", script_path: "/opt/blue/run.sh", work_dir: "/opt/relaygate/work", fixed_args: ["--mode", "batch"], impl_version: "blue-2.3.1", credential_ref: "cred-blue-batch", hang_detect_limit_minutes: 30 }
    : { host: "green-host-01", exec_user: "batchuser", script_path: "/opt/green/run.sh", work_dir: "/opt/relaygate/work", fixed_args: ["--mode", "batch"], impl_version: "green-0.9.0", credential_ref: "cred-green-batch", hang_detect_limit_minutes: 45 };
  return { ...base, ...overrides };
}

function jobMapDocument(slot, version = "v1.4.0", jobs = { "daily-settlement": jobEntry(slot) }) {
  return { job_map_version: version, slot_type: slot, jobs };
}

function writeJobMap(world, slot, document) {
  world.jobMaps[slot] = document;
  writeFileSync(world.jobMapPaths[slot], JSON.stringify(document));
}

function writeCredential(world, ref, content) {
  writeFileSync(join(world.credentialDir, ref), content, { mode: 0o600 });
}

function setModes(world, blue, green, rapid) {
  Object.assign(world.env, { BLUE_MODE: blue, GREEN_MODE: green, RAPID_CROSSCHECK_MODE: rapid, RELAYGATE_OPERATOR: "ops-tanaka" });
}

// 実装の発番 seam(`<generator> <kind> [<qualifier>]`)へ固定値を返す generator を差し込む。
// attempt_id の qualifier は slot 名(facade/src/id_gateway.sh issue_run_identity)。固定しない種別は uuidgen に委ねる
function installIdGenerator(world, runId, attemptIds = {}) {
  const attemptCases = Object.entries(attemptIds).map(([slot, id]) => `      ${slot}) printf '%s' ${JSON.stringify(id)} ;;`);
  const script = [
    "#!/usr/bin/env bash",
    'case "$1" in',
    `  run_id) printf '%s' ${JSON.stringify(runId)} ;;`,
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

function launchLines(world) {
  if (!existsSync(world.launchLogPath)) return [];
  return readFileSync(world.launchLogPath, "utf8").split("\n").filter((line) => line.length > 0);
}

function stdoutLines(world) {
  return world.result.stdout.split("\n").filter((line) => line.length > 0);
}

function launchLineFor(world, slot) {
  const lines = launchLines(world).filter((line) => line.includes(`RELAYGATE_SLOT=${slot} `));
  assertEqual(lines.length, 1, `launch events for ${slot}`);
  return lines[0];
}

// 起動ログ 1 行から remote_command(`<user@host>` の後ろ)を取り出す
function remoteCommandOf(line) {
  const match = line.match(/^-n -o BatchMode=yes -- (\S+) (.*)$/);
  assert(match, `unexpected launch line: ${line}`);
  return { target: match[1], remoteCommand: match[2] };
}

// normalizedStderr は一時ディレクトリの接頭辞を取り除き、仕様の /etc/relaygate/... 表記と比較できる形にする
function normalizedStderr(world) {
  return world.result.stderr.split(world.testDir).join("");
}

function killRecordedProcess(world, name) {
  const pidPath = join(world.testDir, name);
  if (!existsSync(pidPath)) return;
  const pid = Number(readFileSync(pidPath, "utf8"));
  if (pid > 0) {
    try { process.kill(pid, "SIGKILL"); } catch (_error) { /* 既に終了している */ }
  }
}

function runSelectSlot(world, args) {
  const startedAt = Date.now();
  world.result = execute(relaygate, args, { env: world.env });
  world.elapsedMilliseconds = Date.now() - startedAt;
}

Before(function () {
  this.testDir = mkdtempSync(join(tmpdir(), "relaygate-uc-select-slot-"));
  this.dbPath = join(this.testDir, "relaygate.db");
  this.etcDir = join(this.testDir, "etc", "relaygate");
  this.credentialDir = join(this.etcDir, "credentials");
  mkdirSync(this.credentialDir, { recursive: true });
  this.jobMapPaths = { blue: join(this.etcDir, "job-map.blue.json"), green: join(this.etcDir, "job-map.green.json") };
  this.jobMaps = {};
  this.launchLogPath = join(this.testDir, "ssh-launch.log");
  this.binDir = join(this.testDir, "bin");
  mkdirSync(this.binDir);
  writeFileSync(join(this.binDir, "ssh"), SSH_STUB_DEFAULT, { mode: 0o755 });
  const schema = execute("sqlite3", [this.dbPath, CONTRACT_SCHEMA]);
  assert(schema.status === 0, `failed to create SQLite contract schema: ${schema.stderr}`);
  this.env = {
    ...process.env,
    PATH: `${this.binDir}:${process.env.PATH}`,
    RELAYGATE_RDB_DSN: `sqlite://${this.dbPath}`,
    RELAYGATE_TEST_LAUNCH_LOG: this.launchLogPath,
    RELAYGATE_TEST_DIR: this.testDir,
  };
  // 「facade 本体は無変更」の前提確認に使う: ハーネスが設定する RELAYGATE_* の基準集合(Background の設定を含める)
  this.baselineRelaygateKeys = new Set([...Object.keys(this.env), "RELAYGATE_JOB_MAP_PATH_BLUE", "RELAYGATE_JOB_MAP_PATH_GREEN", "RELAYGATE_CREDENTIAL_DIR"].filter((key) => key.startsWith("RELAYGATE_")));
});

After(function () {
  killRecordedProcess(this, "blue-execution.pid");
  killRecordedProcess(this, "green-execution.pid");
  rmSync(this.testDir, { recursive: true, force: true });
});

// ---- Background ----
Given(literal("環境変数 RELAYGATE_JOB_MAP_PATH_BLUE=/etc/relaygate/job-map.blue.json, RELAYGATE_JOB_MAP_PATH_GREEN=/etc/relaygate/job-map.green.json, RELAYGATE_CREDENTIAL_DIR=/etc/relaygate/credentials が設定されている"), function () {
  Object.assign(this.env, { RELAYGATE_JOB_MAP_PATH_BLUE: this.jobMapPaths.blue, RELAYGATE_JOB_MAP_PATH_GREEN: this.jobMapPaths.green, RELAYGATE_CREDENTIAL_DIR: this.credentialDir });
});
Given(literal('blue のジョブマップ /etc/relaygate/job-map.blue.json は job_map_version="v1.4.0", slot_type="blue" で、jobs."daily-settlement" が host="blue-host-01", exec_user="batchuser", script_path="/opt/blue/run.sh", work_dir="/opt/relaygate/work", fixed_args=["--mode","batch"], impl_version="blue-2.3.1", credential_ref="cred-blue-batch", hang_detect_limit_minutes=30 に定義されている'), function () {
  writeJobMap(this, "blue", jobMapDocument("blue"));
});
Given(literal('green のジョブマップ /etc/relaygate/job-map.green.json は job_map_version="v1.4.0", slot_type="green" で、jobs."daily-settlement" が host="green-host-01", exec_user="batchuser", script_path="/opt/green/run.sh", work_dir="/opt/relaygate/work", fixed_args=["--mode","batch"], impl_version="green-0.9.0", credential_ref="cred-green-batch", hang_detect_limit_minutes=45 に定義されている'), function () {
  writeJobMap(this, "green", jobMapDocument("green"));
});
Given(literal("認証情報ディレクトリに /etc/relaygate/credentials/cred-blue-batch と /etc/relaygate/credentials/cred-green-batch のSSH秘密鍵（パーミッション 0600）が配置されている"), function () {
  for (const ref of ["cred-blue-batch", "cred-green-batch"]) {
    writeCredential(this, ref, `-----BEGIN OPENSSH PRIVATE KEY-----\nuc-test-key ${ref}\n-----END OPENSSH PRIVATE KEY-----\n`);
  }
});

// ---- Given: 環境変数(BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE の組み合わせ。RELAYGATE_OPERATOR は必須) ----
Given(/^環境変数に BLUE_MODE=(off|background|foreground), GREEN_MODE=(off|background|foreground), RAPID_CROSSCHECK_MODE=(on|off), RELAYGATE_OPERATOR=ops-tanaka が設定されている$/, function (blue, green, rapid) {
  setModes(this, blue, green, rapid);
});
Given(literal("環境変数 RELAYGATE_JOB_MAP_PATH_BLUE が未設定である"), function () {
  delete this.env.RELAYGATE_JOB_MAP_PATH_BLUE;
});
Given(literal('環境変数 RELAYGATE_JOB_MAP_PATH_GREEN が blue のジョブマップ（slot_type="blue"）を指している'), function () {
  this.env.RELAYGATE_JOB_MAP_PATH_GREEN = this.jobMapPaths.blue;
});

// ---- Given: ジョブマップ fixture の差し替え ----
Given(literal('blue のジョブマップの jobs."daily-settlement" に facade が読まない余剰フィールド "note"="RELAYGATE-TEST-SECRET-EXTRA" が追加されている'), function () {
  writeJobMap(this, "blue", jobMapDocument("blue", "v1.4.0", { "daily-settlement": jobEntry("blue", { note: "RELAYGATE-TEST-SECRET-EXTRA" }) }));
});
Given(literal('green のジョブマップ /etc/relaygate/job-map.green.json だけが job_map_version="v1.5.0" に更新され、jobs."daily-settlement" が host=green-host-01, exec_user=batchuser, script_path=/opt/green-next/run.sh, work_dir=/opt/relaygate/work, impl_version=green-1.0.0 に差し替えられている'), function () {
  writeJobMap(this, "green", jobMapDocument("green", "v1.5.0", { "daily-settlement": jobEntry("green", { host: "green-host-01", exec_user: "batchuser", script_path: "/opt/green-next/run.sh", work_dir: "/opt/relaygate/work", impl_version: "green-1.0.0" }) }));
});
Given(literal('blue のジョブマップ /etc/relaygate/job-map.blue.json は job_map_version="v1.4.0" のまま変更されていない'), function () {
  assertEqual(JSON.parse(readFileSync(this.jobMapPaths.blue, "utf8")).job_map_version, "v1.4.0", "blue job_map_version");
});
Given(literal("facade本体のコード・設定はジョブマップ以外に一切変更されていない"), function () {
  // 他 Scenario と同じ facade/bin/relaygate を、ハーネス基準以外の RELAYGATE_* 設定を足さずに実行することを確認する
  assert(existsSync(relaygate), `facade entrypoint not found: ${relaygate}`);
  const extraKeys = Object.keys(this.env).filter((key) => key.startsWith("RELAYGATE_") && !this.baselineRelaygateKeys.has(key) && key !== "RELAYGATE_ID_GENERATOR" && key !== "RELAYGATE_OPERATOR");
  assertEqual(extraKeys.join(","), "", "facade configuration overrides other than the job map");
});
Given(literal('job_id "unknown-job" が blue・green いずれのジョブマップ（v1.4.0）の jobs にも存在しない'), function () {
  for (const slot of ["blue", "green"]) {
    const document = JSON.parse(readFileSync(this.jobMapPaths[slot], "utf8"));
    assertEqual(document.job_map_version, "v1.4.0", `${slot} job_map_version`);
    assert(!("unknown-job" in document.jobs), `${slot} job map unexpectedly contains unknown-job`);
  }
});
Given(literal('green のジョブマップ /etc/relaygate/job-map.green.json の jobs."daily-settlement" に hang_detect_limit_minutes が定義されていない'), function () {
  const entry = jobEntry("green");
  delete entry.hang_detect_limit_minutes;
  writeJobMap(this, "green", jobMapDocument("green", "v1.4.0", { "daily-settlement": entry }));
});

// ---- Given: 認証情報 ----
Given(literal('/etc/relaygate/credentials/cred-blue-batch の鍵ファイルに識別文字列 "RELAYGATE-TEST-SECRET-BLUE" が含まれている'), function () {
  writeCredential(this, "cred-blue-batch", "-----BEGIN OPENSSH PRIVATE KEY-----\nRELAYGATE-TEST-SECRET-BLUE\n-----END OPENSSH PRIVATE KEY-----\n");
});
Given(literal("認証情報ディレクトリに /etc/relaygate/credentials/cred-green-batch が存在しない"), function () {
  const keyPath = join(this.credentialDir, "cred-green-batch");
  if (existsSync(keyPath)) unlinkSync(keyPath);
});

// ---- Given: 発番固定・外部状態 ----
Given(/^run_id発番が "([^"]+)" を返すよう固定されている$/, function (runId) {
  installIdGenerator(this, runId);
});
Given(/^run_id発番が "([^"]+)" を、attempt_id発番が blue="([^"]+)" \/ green="([^"]+)" を返すよう固定されている$/, function (runId, blueAttempt, greenAttempt) {
  installIdGenerator(this, runId, { blue: blueAttempt, green: greenAttempt });
});
Given(/^run_id発番が "([^"]+)" を、attempt_id発番が "([^"]+)" を返すよう固定されている$/, function (runId, attemptId) {
  installIdGenerator(this, runId, { blue: attemptId, green: attemptId });
});
Given(literal("blue実装のforeground実行が完了まで60秒かかる状態である"), function () {
  writeFileSync(join(this.binDir, "ssh"), SSH_STUB_LONG_RUNNING, { mode: 0o755 });
});
Given(literal("audit_logs へのINSERTが失敗する状態になっている"), function () {
  const trigger = execute("sqlite3", [this.dbPath, "CREATE TRIGGER reject_audit BEFORE INSERT ON audit_logs BEGIN SELECT RAISE(ABORT, 'injected audit failure'); END;"]);
  assert(trigger.status === 0, `failed to inject audit_logs failure: ${trigger.stderr}`);
});
Given(literal("green実装ホスト green-host-01 へのSSH接続が失敗する状態である"), function () {
  this.env.RELAYGATE_TEST_SSH_FAIL_HOST = "green-host-01";
});
Given(literal("blue実装ホスト blue-host-01 へのSSH起動イベント送出がtimeoutする状態である"), function () {
  this.env.RELAYGATE_TEST_SSH_HANG_HOST = "blue-host-01";
});

// ---- When ----
When(/^運用者が `relaygate concurrent-run select-slot --job-id ([^`\s]+)(?: -- ([^`]+))?` を実行する$/, function (jobId, additionalArgs) {
  const args = ["concurrent-run", "select-slot", "--job-id", jobId];
  if (additionalArgs) args.push("--", ...additionalArgs.split(" "));
  runSelectSlot(this, args);
});
When(literal('運用者が追加引数として 1 番目に `--note`、2 番目に `a b "c"`（空白と二重引用符を含む1要素）、3 番目に改行1文字を含む `x<LF>y` の3要素を渡して `relaygate concurrent-run select-slot --job-id daily-settlement` を実行する'), function () {
  // 追加引数は argv の要素としてそのまま渡す(シェルの再分割を経由しない)。`x<LF>y` は改行 1 文字を含む 1 要素
  runSelectSlot(this, ["concurrent-run", "select-slot", "--job-id", "daily-settlement", "--", "--note", 'a b "c"', "x\ny"]);
});

// ---- Then: 終了コード・標準エラー(汎用) ----
Then(/^終了コード (\d+) で終了する$/, function (expected) {
  assert(this.result.status === Number(expected), `expected exit ${expected}, got ${this.result.status}; stderr: ${this.result.stderr}`);
});
Then(literal("終了コード 0 で終了する（blueはoffのためblueのジョブマップは読まれず、環境変数未設定でもエラーにならない）"), function () {
  assert(this.result.status === 0, `expected exit 0, got ${this.result.status}; stderr: ${this.result.stderr}`);
});
Then(/^標準エラーに "([^"]+)" が出力される$/, function (message) {
  const stderr = normalizedStderr(this);
  assert(stderr.includes(message), `stderr does not contain ${JSON.stringify(message)}: ${stderr}`);
});
Then(/^標準エラーに "([^"]+)" と次アクションが出力される$/, function (message) {
  const stderr = normalizedStderr(this);
  assert(stderr.includes(message), `stderr does not contain ${JSON.stringify(message)}: ${stderr}`);
  notImplemented(`標準エラーの次アクション行(送出失敗 / timeout の補償記録): ${message}`);
});
Then(literal("標準エラーに起動前監査の追記失敗の原因と次アクションが出力される"), function () {
  assert(/Pre-launch audit append failed/.test(this.result.stderr), `stderr lacks the audit append failure cause: ${this.result.stderr}`);
  assert(/boundary=rdb/.test(this.result.stderr), `stderr lacks the failure boundary: ${this.result.stderr}`);
  assert(/Next action:/.test(this.result.stderr), `stderr lacks the next action: ${this.result.stderr}`);
});

// ---- Then: 未発生・rollback(汎用) ----
Then(literal("execution_specs・slot_execution_specs・runner_results・audit_logs へのINSERTは発生しない"), function () {
  for (const table of ["execution_specs", "slot_execution_specs", "runner_results", "audit_logs"]) {
    assertEqual(countRows(this.dbPath, table), 0, `${table} rows`);
  }
});
Then(literal("execution_specs・slot_execution_specs・runner_results・audit_logs へのINSERTは発生せず、blue実装・green実装への起動イベントは送出されない"), function () {
  for (const table of ["execution_specs", "slot_execution_specs", "runner_results", "audit_logs"]) {
    assertEqual(countRows(this.dbPath, table), 0, `${table} rows`);
  }
  assertEqual(launchLines(this).length, 0, "launch events");
});
Then(literal("execution_specs・slot_execution_specs・runner_results・runner_result_events へのINSERTはrollbackされ残らない"), function () {
  for (const table of ["execution_specs", "slot_execution_specs", "runner_results", "runner_result_events"]) {
    assertEqual(countRows(this.dbPath, table), 0, `${table} rows`);
  }
});
Then(literal("blue実装・green実装への起動イベントは送出されない"), function () {
  assertEqual(launchLines(this).length, 0, "launch events");
});
Then(literal("rapid_crosscheck_requests へのINSERTは発生しない"), function () {
  assertEqual(countRows(this.dbPath, "rapid_crosscheck_requests"), 0, "rapid_crosscheck_requests rows");
});

// ---- Then: 文言不変(S6 attempt 6 の結線を継承) ----
Then(literal("slot_execution_specs には認証情報の参照名（credential_ref）のみが保存され、パスワード・秘密鍵などの認証情報の実値は保存されない"), function () {
  // 列集合に認証情報の実値を持つ列が無く、credential_ref は参照名(英数字・記号の短い識別子)だけであること
  const columns = query(this.dbPath, "PRAGMA table_info(slot_execution_specs);").map((row) => row[1]);
  const secretColumns = columns.filter((name) => /password|secret|private_key|passphrase|token/i.test(name));
  assertEqual(secretColumns.join(","), "", "secret-bearing columns in slot_execution_specs");
  const refs = query(this.dbPath, "SELECT credential_ref FROM slot_execution_specs;").map((row) => row[0]);
  assert(refs.length > 0, "slot_execution_specs has no rows");
  for (const ref of refs) {
    assert(/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(ref), `credential_ref is not a reference name: ${ref}`);
    assert(!/BEGIN .*PRIVATE KEY|password=/i.test(ref), `credential_ref carries a secret value: ${ref}`);
  }
});
Then(/^runner_results に \(run_id="([^"]+)", slot_type="blue", role_type="foreground", attempt_id="([^"]+)", attempt_no=1, status="STARTING"\) と \(run_id="[^"]+", slot_type="green", role_type="background", attempt_id="([^"]+)", attempt_no=1, status="STARTING"\) の2行が accepted_at 付きでINSERTされる$/, function (runId, blueAttempt, greenAttempt) {
  assertEqual(countRows(this.dbPath, "runner_results"), 2, "runner_results rows");
  const rows = query(this.dbPath, "SELECT run_id, slot_type, role_type, attempt_id, attempt_no, status, accepted_at FROM runner_results ORDER BY slot_type;");
  assertEqual(rows[0].slice(0, 6).join("|"), [runId, "blue", "foreground", blueAttempt, "1", "STARTING"].join("|"), "runner_results blue row");
  assertEqual(rows[1].slice(0, 6).join("|"), [runId, "green", "background", greenAttempt, "1", "STARTING"].join("|"), "runner_results green row");
  for (const row of rows) assert(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(row[6]), `accepted_at is not a timestamp: ${row[6]}`);
});
Then(/^audit_logs に \(run_id="([^"]+)", event_name="slot_launch_accepted", slot="-", attempt_id="-", actor="([^"]+)", operation="slot_launch", outcome="accepted", schema_version="1\.0"\) の起動前監査イベントがINSERTされ、audit_chain_heads の run_id 行が更新される$/, function (runId, actor) {
  const rows = query(this.dbPath, `SELECT run_id, slot, attempt_id, actor, operation, outcome, schema_version FROM audit_logs WHERE event_name = 'slot_launch_accepted';`);
  assertEqual(rows.length, 1, "slot_launch_accepted rows");
  assertEqual(rows[0].join("|"), [runId, "-", "-", actor, "slot_launch", "accepted", "1.0"].join("|"), "slot_launch_accepted row");
  const heads = query(this.dbPath, `SELECT h.chain_length, h.head_hash, a.event_hash FROM audit_chain_heads h JOIN audit_logs a ON a.event_id = h.head_event_id AND a.run_id = h.run_id WHERE h.run_id = ${sqlString(runId)};`);
  assertEqual(heads.length, 1, "audit_chain_heads row for run_id");
  assertEqual(heads[0][1], heads[0][2], "audit_chain_heads.head_hash matches head event hash");
  assertEqual(heads[0][0], String(countRows(this.dbPath, "audit_logs", `run_id = ${sqlString(runId)}`)), "audit_chain_heads.chain_length");
});
Then(/^標準出力に run_id="([^"]+)" の blue\/foreground\/att-blue-0001\/STARTING 行と green\/background\/att-green-0001\/STARTING 行が出力される$/, function (runId) {
  const lines = stdoutLines(this);
  assert(lines.includes(`run_id=${runId} slot_type=blue role=foreground attempt_id=att-blue-0001 status=STARTING`), `stdout lacks blue line: ${this.result.stdout}`);
  assert(lines.includes(`run_id=${runId} slot_type=green role=background attempt_id=att-green-0001 status=STARTING`), `stdout lacks green line: ${this.result.stdout}`);
  assertEqual(lines.length, 2, "stdout line count");
});
Then(/^runner_results に \(run_id="([^"]+)", slot_type="green", role_type="foreground", attempt_id="([^"]+)", attempt_no=1, status="STARTING"\) の1行がINSERTされる$/, function (runId, attemptId) {
  const rows = query(this.dbPath, "SELECT run_id, slot_type, role_type, attempt_id, attempt_no, status FROM runner_results;");
  assertEqual(rows.length, 1, "runner_results rows");
  assertEqual(rows[0].join("|"), [runId, "green", "foreground", attemptId, "1", "STARTING"].join("|"), "runner_results green row");
});
Then(literal("標準出力に green/foreground/att-green-0001/STARTING の1行のみが出力される（運用モード: 新実装単独本番に相当する組み合わせ）"), function () {
  const lines = stdoutLines(this);
  assertEqual(lines.length, 1, "stdout line count");
  assert(/^run_id=\S+ slot_type=green role=foreground attempt_id=att-green-0001 status=STARTING$/.test(lines[0]), `unexpected stdout line: ${lines[0]}`);
});
Then(literal("green実装への起動イベントは slot_execution_specs の host / exec_user / script_path / work_dir / fixed_args / credential_ref の値のみから構成され、facadeは実装固有の起動方式差異（実装名・バージョンによる分岐）を参照しない"), function () {
  const row = query(this.dbPath, "SELECT host, exec_user, script_path, work_dir, COALESCE(fixed_args, ''), impl_version FROM slot_execution_specs WHERE slot_type = 'green';")[0];
  assert(row, "slot_execution_specs has no green row");
  const [host, execUser, scriptPath, workDir, , implVersion] = row;
  const { target, remoteCommand } = remoteCommandOf(launchLineFor(this, "green"));
  assertEqual(target, `${execUser}@${host}`, "ssh target from exec_user/host");
  // remote_command = `cd <work_dir> && <run 実行コンテキスト> <script_path>[ <argv>]`。run 実行コンテキスト以外は slot_execution_specs の値だけで構成される
  const pattern = /^cd (\S+) && RELAYGATE_RUN_ID=\S+ RELAYGATE_ATTEMPT_ID=\S+ RELAYGATE_SLOT=green RELAYGATE_ROLE=\S+ RELAYGATE_RAPID_CROSSCHECK_MODE=\S+ (\S+)(?: (.*))?$/;
  const match = remoteCommand.match(pattern);
  assert(match, `green launch command is not composed only from slot_execution_specs values: ${remoteCommand}`);
  assertEqual(match[1], workDir, "work_dir in launch command");
  assertEqual(match[2], scriptPath, "script_path in launch command");
  assert(!remoteCommand.includes(implVersion), `launch command references impl_version ${implVersion}: ${remoteCommand}`);
  assert(!/green-next|green-0\.9|green-1\.0/.test(remoteCommand.replace(scriptPath, "")), `launch command branches on implementation name/version: ${remoteCommand}`);
  // fixed_args(JSON 配列)の要素順 argv 復元と credential_ref からの鍵解決(-i)は新仕様で追加された検証。S6 が結線する
  notImplemented("green 起動イベントの fixed_args(JSON 配列)復元と credential_ref(認証情報ディレクトリ)による秘密鍵指定");
});

// ---- Then: 新仕様で追加・変更(S2 skeleton。S6 が結線する) ----
Then(literal('execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", parent_run_id=NULL, job_id="daily-settlement", additional_args=[], hang_detect_limit_minutes=45 の1行がINSERTされる（hang_detect_limit_minutesはbackground roleに選ばれたgreenのジョブマップ値）'), function () {
  notImplemented("execution_specs 行(additional_args=[] の JSON 配列、hang_detect_limit_minutes は background slot の値)");
});
Then(literal('slot_execution_specs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", host="blue-host-01", impl_version="blue-2.3.1", credential_ref="cred-blue-batch", job_map_version="v1.4.0") と (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", host="green-host-01", impl_version="green-0.9.0", credential_ref="cred-green-batch", job_map_version="v1.4.0") の2行が (run_id, slot_type) で一意に識別されるようINSERTされる'), function () {
  notImplemented("slot_execution_specs 2 rows with slot 別 job_map_version");
});
Then(literal('runner_result_events に対応する event_name="attempt_started", status="STARTING" の履歴が同一transactionでINSERTされ、各行の occurred_at は対応する runner_results の accepted_at および updated_at とマイクロ秒精度で同一値である'), function () {
  notImplemented("attempt_started 履歴と snapshot の occurred_at / accepted_at / updated_at のマイクロ秒精度一致");
});
Then(literal("audit_logs の各行の event_hash は audit-event-contract.yaml の hash_chain.canonical_form に従って当該行から再計算した値と一致する"), function () {
  notImplemented("audit-event-contract.yaml hash_chain.canonical_form による event_hash の再計算照合");
});
Then(literal('execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", hang_detect_limit_minutes=45 の1行が、slot_execution_specs に slot_type="green", job_map_version="v1.4.0" の1行のみがINSERTされる（backgroundのslotが無いため起動対象の唯一のslotであるgreenの値を採用）'), function () {
  notImplemented("foreground のみの構成で唯一の slot の hang_detect_limit_minutes を採用し slot_execution_specs は green 1 行");
});
Then(literal('execution_specs の run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" 行の hang_detect_limit_minutes は 45 である（blue=30, green=45 のうち大きい方）'), function () {
  notImplemented("両 slot background のとき hang_detect_limit_minutes に大きい方を採用");
});
Then(literal('slot_execution_specs に slot_type="blue" と slot_type="green" の2行が job_map_version="v1.4.0" でINSERTされる'), function () {
  notImplemented("slot_execution_specs 2 rows with slot 別 job_map_version");
});
Then(literal("green実装へのbackground起動イベントの送出が、blue実装へのforeground起動イベントの送出より先に完了する"), function () {
  notImplemented("background → foreground の送出順(起動ログの順序)");
});
Then(literal('runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001") が status="STARTING" で存在する'), function () {
  notImplemented("green background 行が STARTING で存在(RUNNING 遷移は後続 UC の責務)");
});
Then(literal("CLIは blue foreground実行および green background実行の完了を待たずに、起動受付から 10 秒以内に終了コード 0 で終了する"), function () {
  notImplemented("完了を待たない起動受付応答(10 秒以内・detached 実行が継続)");
});
Then(literal('execution_specs の run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" 行の additional_args にJSON配列 ["--target-date","2026-08-18","--retry","3"] が保存される'), function () {
  notImplemented("additional_args の JSON 配列保存 (argument_serialization)");
});
Then(literal('slot_execution_specs の (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue") 行の fixed_args にJSON配列 ["--mode","batch"] が保存される'), function () {
  notImplemented("fixed_args の JSON 配列保存 (argument_serialization)");
});
Then(literal('blue実装への起動イベントのargvが ["--mode","batch","--target-date","2026-08-18","--retry","3"]（固定引数→追加引数の順、要素の順序・値とも改変なし）で構成される'), function () {
  notImplemented("fixed_args + additional_args の要素順 argv 復元");
});
Then(literal('execution_specs の additional_args にJSON配列 ["--note","a b \\"c\\"","x\\ny"] が保存される'), function () {
  notImplemented("空白・引用符・改行を含む要素の JSON 配列保存");
});
Then(literal("保存値をJSON配列として復元した3要素は、渡した3要素と1要素ずつ同一である（再分割・再結合・トリム・クォート付与が行われない）"), function () {
  notImplemented("JSON 配列の往復同一性(再分割・トリム・クォート付与なし)");
});
Then(literal('blue実装への起動イベントのargvは ["--mode","batch","--note","a b \\"c\\"","x\\ny"] である'), function () {
  notImplemented("空白・引用符・改行を含む argv の起動イベント構成");
});
Then(literal("blue実装への起動イベントは /etc/relaygate/credentials/cred-blue-batch を秘密鍵として送出される"), function () {
  notImplemented("credential_ref から解決した秘密鍵(認証情報ディレクトリ)の起動イベントへの適用");
});
Then(literal('"RELAYGATE-TEST-SECRET-BLUE" と "RELAYGATE-TEST-SECRET-EXTRA" は execution_specs・slot_execution_specs・audit_logs・標準出力・標準エラー・起動イベントの引数のいずれにも現れない'), function () {
  notImplemented("認証情報の実値・余剰フィールド値の非露出(RDB dump・stdout・stderr・起動ログ)");
});
Then(literal('slot_execution_specs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", script_path="/opt/green-next/run.sh", impl_version="green-1.0.0", job_map_version="v1.5.0") の1行がINSERTされる'), function () {
  notImplemented("green のジョブマップ差し替え(v1.5.0)の slot_execution_specs 反映");
});
Then(literal('runner_results の (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001") 行が status="FAILED", exit_code=NULL へ更新され、runner_result_events に event_name="attempt_failed", status="FAILED" の履歴が同一transactionでINSERTされる'), function () {
  notImplemented("送出失敗の FAILED 補償記録 (attempt_failed)");
});
Then(literal('audit_logs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot="green", attempt_id="att-green-0001", event_name="slot_launch_failed", outcome="failed", error_code="launch_event_send_failed", actor="ops-tanaka") が slot_launch_attempted の後ろにチェーンされてINSERTされる'), function () {
  notImplemented("slot_launch_failed 監査イベントのチェーン追記");
});
Then(literal('blue実装へのforeground起動イベントは送出され、runner_results の blue/foreground/att-blue-0001 行は status="STARTING" のままである'), function () {
  notImplemented("他 slot の送出失敗に影響されない blue foreground の送出と STARTING 維持");
});
Then(literal("標準出力には blue/foreground/att-blue-0001/STARTING 行と green/background/att-green-0001/STARTING 行が出力される（起動受付の記録）"), function () {
  notImplemented("送出失敗時も起動受付の STARTING 行を標準出力する契約");
});
Then(literal('runner_results の (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="foreground", attempt_id="att-blue-0001") 行が status="UNKNOWN", exit_code=NULL へ更新され、runner_result_events に event_name="attempt_unknown", status="UNKNOWN" の履歴が同一transactionでINSERTされる（推測でFAILEDを確定しない）'), function () {
  notImplemented("送出 timeout の UNKNOWN 補償記録 (attempt_unknown)");
});
Then(literal('audit_logs に (slot="blue", attempt_id="att-blue-0001", event_name="slot_launch_timeout", outcome="timeout", error_code="launch_event_send_timeout") がINSERTされる'), function () {
  notImplemented("slot_launch_timeout 監査イベントの追記");
});
Then(literal('runner_results の green/background/att-green-0001 行は status="STARTING" のままである'), function () {
  notImplemented("timeout した slot 以外の STARTING 維持");
});
