// UC BDD step definitions(②)。S2 scoped 再実行(spec 20260819_114307 還流)の skeleton を S6 uc-bdd で結線した。
// 方針:
//   - 本 UC の tier は tier-facade のみ。実 bash プロセス(facade/bin/relaygate)を起動し、RDB・起動イベントの実体で検証する
//   - step 文言に ASCII の "/" "(" ")" が含まれるため cucumber expression ではなく正規表現で定義する
//   - ハーネスは新仕様の 11 テーブル契約(packages/contracts/relay-gate-db/schema-constants.sh)に合わせる。
//     RDB の正本は PostgreSQL だが、既存の限定検証境界(issues/20260817T230000Z・issues/20260821T220045Z §1)に従い SQLite で検証する
//   - run_id / attempt_id 発番の固定は実装の seam RELAYGATE_ID_GENERATOR(facade/src/id_gateway.sh)を使う
//   - ジョブマップの形式は facade/src/job_map_gateway.sh 冒頭コメントの検証境界形式(JSON・slot 別エントリ)
//   - 起動イベントは PATH 先頭の ssh スタブが受け取り、引数列(`$*`)を起動ログへ 1 行ずつ追記する
//   - Scenario「background roleを先に起動しforeground待機中もbackgroundが並走する」は後続 UC に依存するため
//     ssh スタブへハーネス注入する(issues/20260821T220045Z §2 / §7。暫定注入・契約確定後に削除)
const { After, Before, Given, Then, When } = require("@cucumber/cucumber");
const { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } = require("node:fs");
const { spawnSync } = require("node:child_process");
const { tmpdir } = require("node:os");
const { join, resolve } = require("node:path");

const projectRoot = resolve(__dirname, "../../..");
const relaygate = join(projectRoot, "facade", "bin", "relaygate");

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

// 既定の ssh スタブ: 起動イベント(引数列)を起動ログへ追記して成功を返す
const SSH_STUB_DEFAULT = "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"$RELAYGATE_TEST_LAUNCH_LOG\"\nexit 0\n";

// 暫定注入(issues/20260821T220045Z §2 / §7。契約確定後に削除): 並走 Scenario 用の ssh スタブ。
// 本 UC の tier-facade は STARTING の記録と起動イベントの送出(handshake)までを担い、
// STARTING→RUNNING の遷移は後続 UC「background roleを起動する」(c3c7ab31、tier-worker の remote runner)の責務。
// このスタブは SSH 先の remote runner を模擬し、
//   - green(background): runner_results を RUNNING へ遷移させ、60 秒の background 実行を detached プロセスで模擬する
//   - blue(foreground): 起動時点の green の status を記録し、60 秒の foreground 実行を detached プロセスで模擬する
// 引数列は facade/src/launch_gateway.sh の `ssh -n -o BatchMode=yes -- <user@host> <remote_command>`。
const SSH_STUB_CONCURRENT = [
  "#!/usr/bin/env bash",
  "# 暫定注入: issues/20260821T220045Z §2(RUNNING 遷移は UC c3c7ab31 の責務)/ §7(foreground 完了待ちは応答 UC の責務)。契約確定後に削除",
  "set -o errexit -o nounset -o pipefail",
  "printf '%s\\n' \"$*\" >>\"$RELAYGATE_TEST_LAUNCH_LOG\"",
  "remote_command=\"$6\"",
  "slot=''",
  "if [[ $remote_command =~ RELAYGATE_SLOT=(blue|green) ]]; then slot=\"${BASH_REMATCH[1]}\"; fi",
  "now=\"$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)\"",
  "if [[ $slot == green ]]; then",
  "  event_id=\"$(uuidgen | tr '[:upper:]' '[:lower:]')\"",
  "  sqlite3 \"$RELAYGATE_TEST_DB_PATH\" \"BEGIN IMMEDIATE; INSERT INTO runner_result_events (event_id, run_id, slot_type, role_type, attempt_id, attempt_no, event_name, status, occurred_at, started_at) SELECT '$event_id', run_id, slot_type, role_type, attempt_id, attempt_no, 'attempt_running', 'RUNNING', '$now', '$now' FROM runner_results WHERE slot_type = 'green'; UPDATE runner_results SET status = 'RUNNING', started_at = '$now', updated_at = '$now' WHERE slot_type = 'green'; COMMIT;\"",
  "  perl -MPOSIX=setsid -e 'setsid; exec \"sleep\", \"60\"' </dev/null >/dev/null 2>&1 &",
  "  printf '%s' \"$!\" >\"$RELAYGATE_TEST_DIR/green-background.pid\"",
  "elif [[ $slot == blue ]]; then",
  "  sqlite3 \"$RELAYGATE_TEST_DB_PATH\" \"SELECT status FROM runner_results WHERE slot_type = 'green';\" >\"$RELAYGATE_TEST_DIR/green-status-at-blue-launch.txt\"",
  "  perl -MPOSIX=setsid -e 'setsid; exec \"sleep\", \"60\"' </dev/null >/dev/null 2>&1 &",
  "  printf '%s' \"$!\" >\"$RELAYGATE_TEST_DIR/blue-foreground.pid\"",
  "fi",
  "exit 0",
  "",
].join("\n");

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

// ジョブマップ fixture(spec.md の Given 値 + credential_ref。issues/20260821T220045Z §3)
function slotEntry(overrides) {
  return { host: "", exec_user: "batchuser", script_path: "", work_dir: "/opt/relaygate/work", fixed_args: [], impl_version: "", credential_ref: "", ...overrides };
}

function jobMapDocument(version = "v1.4.0", jobId = "daily-settlement", slotOverrides = {}) {
  return {
    version,
    jobs: {
      [jobId]: {
        hang_detect_limit_minutes: 30,
        slots: {
          blue: slotEntry({ host: "blue-host-01", script_path: "/opt/blue/run.sh", impl_version: "blue-2.3.1", credential_ref: "cred-blue-batch", ...(slotOverrides.blue || {}) }),
          green: slotEntry({ host: "green-host-01", script_path: "/opt/green/run.sh", impl_version: "green-0.9.0", credential_ref: "cred-green-batch", ...(slotOverrides.green || {}) }),
        },
      },
    },
  };
}

function writeJobMap(world, document) {
  world.jobMap = document;
  writeFileSync(world.jobMapPath, JSON.stringify(document));
}

function setModes(world, blue, green, rapid) {
  Object.assign(world.env, { BLUE_MODE: blue, GREEN_MODE: green, RAPID_CROSSCHECK_MODE: rapid, RELAYGATE_OPERATOR: "ops-tanaka" });
}

// 実装の発番 seam(`<generator> <kind> [<qualifier>]`)へ固定値を返す generator を差し込む。
// attempt_id の qualifier は slot 名(facade/src/id_gateway.sh issue_run_identity)。固定しない種別は uuidgen に委ねる
function installIdGenerator(world, runId, attemptIds = {}) {
  const attemptCases = Object.entries(attemptIds).map(([slot, id]) => `${slot}) printf '%s' ${JSON.stringify(id)} ;;`);
  const script = [
    "#!/usr/bin/env bash",
    'case "$1" in',
    `  run_id) printf '%s' ${JSON.stringify(runId)} ;;`,
    "  attempt_id)",
    '    case "$2" in',
    ...attemptCases.map((line) => `      ${line}`),
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

function killRecordedProcess(world, name) {
  const pidPath = join(world.testDir, name);
  if (!existsSync(pidPath)) return;
  const pid = Number(readFileSync(pidPath, "utf8"));
  if (pid > 0) {
    try { process.kill(pid, "SIGKILL"); } catch (_error) { /* 既に終了している */ }
  }
}

function isAlive(pid) {
  try { process.kill(pid, 0); return true; } catch (_error) { return false; }
}

Before(function () {
  this.testDir = mkdtempSync(join(tmpdir(), "relaygate-uc-select-slot-"));
  this.dbPath = join(this.testDir, "relaygate.db");
  this.jobMapPath = join(this.testDir, "job-map.json");
  this.launchLogPath = join(this.testDir, "ssh-launch.log");
  this.binDir = join(this.testDir, "bin");
  mkdirSync(this.binDir);
  writeFileSync(join(this.binDir, "ssh"), SSH_STUB_DEFAULT, { mode: 0o755 });
  // Given でジョブマップが与えられない Scenario(バリデーションエラー)でも必須環境変数は揃えておく
  writeJobMap(this, { version: "v1.4.0", jobs: {} });
  const schema = execute("sqlite3", [this.dbPath, CONTRACT_SCHEMA]);
  assert(schema.status === 0, `failed to create SQLite contract schema: ${schema.stderr}`);
  this.env = {
    ...process.env,
    PATH: `${this.binDir}:${process.env.PATH}`,
    RELAYGATE_RDB_DSN: `sqlite://${this.dbPath}`,
    RELAYGATE_JOB_MAP_PATH: this.jobMapPath,
    RELAYGATE_TEST_LAUNCH_LOG: this.launchLogPath,
    RELAYGATE_TEST_DB_PATH: this.dbPath,
    RELAYGATE_TEST_DIR: this.testDir,
  };
  // 「facade 本体は無変更」の前提確認に使う: ハーネスが設定する RELAYGATE_* の基準集合
  this.baselineRelaygateKeys = new Set(Object.keys(this.env).filter((key) => key.startsWith("RELAYGATE_")));
});

After(function () {
  killRecordedProcess(this, "green-background.pid");
  killRecordedProcess(this, "blue-foreground.pid");
  rmSync(this.testDir, { recursive: true, force: true });
});

// ---- Given: 環境変数(4 通りの組み合わせ。RELAYGATE_OPERATOR が必須になった) ----
Given(/^環境変数に BLUE_MODE=(off|background|foreground), GREEN_MODE=(off|background|foreground), RAPID_CROSSCHECK_MODE=(on|off), RELAYGATE_OPERATOR=ops-tanaka が設定されている$/, function (blue, green, rapid) {
  setModes(this, blue, green, rapid);
});

// ---- Given: ジョブマップ fixture ----
Given(/^ジョブマップ v1\.4\.0 で job_id "daily-settlement" が blue（host=blue-host-01, exec_user=batchuser, work_dir=\/opt\/relaygate\/work, impl_version=blue-2\.3\.1）と green（host=green-host-01, exec_user=batchuser, work_dir=\/opt\/relaygate\/work, impl_version=green-0\.9\.0）に解決できる$/, function () {
  writeJobMap(this, jobMapDocument());
});
Given(/^ジョブマップ v1\.4\.0 で job_id "daily-settlement" が blue（host=blue-host-01, impl_version=blue-2\.3\.1）と green（host=green-host-01, impl_version=green-0\.9\.0）に解決できる$/, function () {
  writeJobMap(this, jobMapDocument());
});
Given(/^ジョブマップ v1\.4\.0 で job_id "daily-settlement" が green（host=green-host-01, impl_version=green-0\.9\.0）に解決できる$/, function () {
  writeJobMap(this, jobMapDocument());
});
Given(/^ジョブマップ v1\.4\.0 で job_id "daily-settlement" が解決できる$/, function () {
  writeJobMap(this, jobMapDocument());
});
Given(/^ジョブマップの hang_detect_limit_minutes が 30 である$/, function () {
  assertEqual(this.jobMap.jobs["daily-settlement"].hang_detect_limit_minutes, 30, "job map hang_detect_limit_minutes");
});
Given(/^ジョブマップ v1\.4\.0 で job_id "daily-settlement" の blue の fixed_args が \["--mode", "batch"\] に定義されている$/, function () {
  writeJobMap(this, jobMapDocument("v1.4.0", "daily-settlement", { blue: { fixed_args: ["--mode", "batch"] } }));
});
Given(/^ジョブマップが v1\.5\.0 に更新され、job_id "daily-settlement" の green が host=green-host-01, exec_user=batchuser, script_path=\/opt\/green-next\/run\.sh, work_dir=\/opt\/relaygate\/work, impl_version=green-1\.0\.0 に差し替えられている$/, function () {
  writeJobMap(this, jobMapDocument("v1.5.0", "daily-settlement", { green: { host: "green-host-01", exec_user: "batchuser", script_path: "/opt/green-next/run.sh", work_dir: "/opt/relaygate/work", impl_version: "green-1.0.0" } }));
});
Given(/^facade本体のコード・設定はジョブマップ以外に一切変更されていない$/, function () {
  // 他 Scenario と同じ facade/bin/relaygate を、ハーネス基準以外の RELAYGATE_* 設定を足さずに実行することを確認する
  assert(existsSync(relaygate), `facade entrypoint not found: ${relaygate}`);
  const extraKeys = Object.keys(this.env).filter((key) => key.startsWith("RELAYGATE_") && !this.baselineRelaygateKeys.has(key) && key !== "RELAYGATE_ID_GENERATOR" && key !== "RELAYGATE_OPERATOR");
  assertEqual(extraKeys.join(","), "", "facade configuration overrides other than the job map");
});
Given(/^job_id "unknown-job" がジョブマップ v1\.4\.0 に存在しない$/, function () {
  writeJobMap(this, jobMapDocument());
  assert(!("unknown-job" in this.jobMap.jobs), "job map unexpectedly contains unknown-job");
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
Given(/^blue実装のforeground実行が完了まで60秒かかる状態である$/, function () {
  // 暫定注入(issues/20260821T220045Z §2 / §7。契約確定後に削除): remote runner を模擬する ssh スタブへ差し替える。
  // 60 秒の実行は detached プロセスで模擬する。facade の SSH は起動イベントの送出(handshake、上限 8 秒)であり
  // 実行完了を待つ契約ではない(§7)ため、スタブ自身は 60 秒ブロックしない
  writeFileSync(join(this.binDir, "ssh"), SSH_STUB_CONCURRENT, { mode: 0o755 });
});
Given(/^audit_logs へのINSERTが失敗する状態になっている$/, function () {
  const trigger = execute("sqlite3", [this.dbPath, "CREATE TRIGGER reject_audit BEFORE INSERT ON audit_logs BEGIN SELECT RAISE(ABORT, 'injected audit failure'); END;"]);
  assert(trigger.status === 0, `failed to inject audit_logs failure: ${trigger.stderr}`);
});

// ---- When(追加引数 "--" 以降も受け取る) ----
When(/^運用者が `relaygate concurrent-run select-slot --job-id ([^`\s]+)(?: -- ([^`]+))?` を実行する$/, function (jobId, additionalArgs) {
  const args = ["concurrent-run", "select-slot", "--job-id", jobId];
  if (additionalArgs) args.push("--", ...additionalArgs.split(" "));
  const startedAt = Date.now();
  this.result = execute(relaygate, args, { env: this.env });
  this.elapsedMilliseconds = Date.now() - startedAt;
});

// ---- Then: 終了コード・標準エラー ----
Then(/^終了コード (\d+) で終了する$/, function (expected) {
  assert(this.result.status === Number(expected), `expected exit ${expected}, got ${this.result.status}; stderr: ${this.result.stderr}`);
});
Then(/^標準エラーに "([^"]+)" が出力される$/, function (message) {
  assert(this.result.stderr.includes(message), `stderr does not contain ${message}: ${this.result.stderr}`);
});

// ---- Then: RDB 記録(正常系) ----
Then(/^execution_specs に run_id="([^"]+)", parent_run_id=NULL, job_id="([^"]+)", job_map_version="([^"]+)", hang_detect_limit_minutes=(\d+) の1行がINSERTされる$/, function (runId, jobId, jobMapVersion, hangLimit) {
  assertEqual(countRows(this.dbPath, "execution_specs"), 1, "execution_specs rows");
  const row = query(this.dbPath, `SELECT run_id, COALESCE(parent_run_id, 'NULL'), job_id, job_map_version, hang_detect_limit_minutes FROM execution_specs;`)[0];
  assertEqual(row.join("|"), [runId, "NULL", jobId, jobMapVersion, hangLimit].join("|"), "execution_specs row");
});
Then(/^slot_execution_specs に \(run_id="([^"]+)", slot_type="blue", host="([^"]+)", impl_version="([^"]+)", credential_ref="([^"]+)"\) と \(run_id="[^"]+", slot_type="green", host="([^"]+)", impl_version="([^"]+)", credential_ref="([^"]+)"\) の2行が \(run_id, slot_type\) で一意に識別されるようINSERTされる$/, function (runId, blueHost, blueVersion, blueCred, greenHost, greenVersion, greenCred) {
  assertEqual(countRows(this.dbPath, "slot_execution_specs"), 2, "slot_execution_specs rows");
  const rows = query(this.dbPath, "SELECT run_id, slot_type, host, impl_version, credential_ref FROM slot_execution_specs ORDER BY slot_type;");
  assertEqual(rows[0].join("|"), [runId, "blue", blueHost, blueVersion, blueCred].join("|"), "slot_execution_specs blue row");
  assertEqual(rows[1].join("|"), [runId, "green", greenHost, greenVersion, greenCred].join("|"), "slot_execution_specs green row");
  assertEqual(query(this.dbPath, "SELECT COUNT(DISTINCT run_id || '/' || slot_type) FROM slot_execution_specs;")[0][0], "2", "(run_id, slot_type) uniqueness");
});
Then(/^slot_execution_specs には認証情報の参照名（credential_ref）のみが保存され、パスワード・秘密鍵などの認証情報の実値は保存されない$/, function () {
  // 列集合に認証情報の実値を持つ列が無く、credential_ref は参照名(英数字・記号の短い識別子)だけであること
  const columns = query(this.dbPath, "PRAGMA table_info(slot_execution_specs);").map((row) => row[1]);
  const secretColumns = columns.filter((name) => /password|secret|private_key|passphrase|token/i.test(name));
  assertEqual(secretColumns.join(","), "", "secret-bearing columns in slot_execution_specs");
  const refs = query(this.dbPath, "SELECT credential_ref FROM slot_execution_specs;").map((row) => row[0]);
  for (const ref of refs) {
    assert(/^cred-[a-z-]+$/.test(ref), `credential_ref is not a reference name: ${ref}`);
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
Then(/^runner_result_events に対応する event_name="attempt_started", status="STARTING" の履歴が同一transactionでINSERTされる$/, function () {
  // 同一 transaction の検証: 履歴が snapshot と同じ起動試行 identity(run_id, slot_type, role_type, attempt_id)と同じ受付時刻で 1:1 対応する
  assertEqual(countRows(this.dbPath, "runner_result_events", "event_name = 'attempt_started' AND status = 'STARTING'"), 2, "attempt_started rows");
  assertEqual(query(this.dbPath, "SELECT COUNT(*) FROM runner_results r JOIN runner_result_events e ON e.run_id = r.run_id AND e.slot_type = r.slot_type AND e.role_type = r.role_type AND e.attempt_id = r.attempt_id AND e.attempt_no = r.attempt_no AND e.occurred_at = r.accepted_at WHERE e.event_name = 'attempt_started';")[0][0], "2", "history/snapshot pairing");
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
Then(/^rapid_crosscheck_requests へのINSERTは発生しない$/, function () {
  assertEqual(countRows(this.dbPath, "rapid_crosscheck_requests"), 0, "rapid_crosscheck_requests rows");
});
Then(/^execution_specs に run_id="([^"]+)" の1行が、slot_execution_specs に slot_type="green" の1行のみがINSERTされる$/, function (runId) {
  assertEqual(countRows(this.dbPath, "execution_specs"), 1, "execution_specs rows");
  assertEqual(query(this.dbPath, "SELECT run_id FROM execution_specs;")[0][0], runId, "execution_specs.run_id");
  assertEqual(query(this.dbPath, "SELECT slot_type FROM slot_execution_specs;").map((row) => row[0]).join(","), "green", "slot_execution_specs slot_type");
});
Then(/^runner_results に \(run_id="([^"]+)", slot_type="green", role_type="foreground", attempt_id="([^"]+)", attempt_no=1, status="STARTING"\) の1行がINSERTされる$/, function (runId, attemptId) {
  const rows = query(this.dbPath, "SELECT run_id, slot_type, role_type, attempt_id, attempt_no, status FROM runner_results;");
  assertEqual(rows.length, 1, "runner_results rows");
  assertEqual(rows[0].join("|"), [runId, "green", "foreground", attemptId, "1", "STARTING"].join("|"), "runner_results green row");
});
Then(/^標準出力に green\/foreground\/att-green-0001\/STARTING の1行のみが出力される（運用モード: 新実装単独本番に相当する組み合わせ）$/, function () {
  const lines = stdoutLines(this);
  assertEqual(lines.length, 1, "stdout line count");
  assert(/^run_id=\S+ slot_type=green role=foreground attempt_id=att-green-0001 status=STARTING$/.test(lines[0]), `unexpected stdout line: ${lines[0]}`);
});

// ---- Then: 並走(background → foreground の起動順) ----
Then(/^green実装へのbackground起動イベント（非同期起動トリガー）が、blue実装へのforeground起動イベント（同期実行）より先に送出される$/, function () {
  const lines = launchLines(this);
  assertEqual(lines.length, 2, "launch events");
  assert(lines[0].includes("@green-host-01 ") && lines[0].includes("RELAYGATE_ROLE=background "), `first launch event is not green/background: ${lines[0]}`);
  assert(lines[1].includes("@blue-host-01 ") && lines[1].includes("RELAYGATE_ROLE=foreground "), `second launch event is not blue/foreground: ${lines[1]}`);
});
Then(/^blue foreground実行の待機中に、runner_results の \(run_id="([^"]+)", slot_type="green", role_type="background", attempt_id="([^"]+)"\) が status="RUNNING" で並走している$/, function (runId, greenAttempt) {
  // 暫定注入(issues/20260821T220045Z §2。契約確定後に削除): RUNNING への遷移は注入した ssh スタブ(remote runner 模擬)が行う。
  // 検証するのは「blue foreground の起動時点で green background が RUNNING で並走していること」
  const snapshotPath = join(this.testDir, "green-status-at-blue-launch.txt");
  assert(existsSync(snapshotPath), "blue foreground launch did not observe the green status (ssh stub snapshot missing)");
  assertEqual(readFileSync(snapshotPath, "utf8").trim(), "RUNNING", "green status observed at blue foreground launch");
  const rows = query(this.dbPath, "SELECT run_id, slot_type, role_type, attempt_id, status FROM runner_results WHERE slot_type = 'green';");
  assertEqual(rows.length, 1, "green runner_results rows");
  assertEqual(rows[0].join("|"), [runId, "green", "background", greenAttempt, "RUNNING"].join("|"), "green runner_results row");
});
Then(/^blue foreground実行の完了を待ってから終了コード 0 で終了し、green background実行の完了は待たない$/, function () {
  // 暫定注入(issues/20260821T220045Z §7。契約確定後に削除): 本 UC の facade は起動受付(STARTING)までを応答し、
  // foreground 実行完了の待機と応答は後続 UC「foreground roleの標準出力・標準エラー・終了コードを応答する」の責務。
  // ここで検証できるのは「終了コード 0」と「green background の完了を待たない(CLI 終了後も green の実行が継続している)」まで
  assert(this.result.status === 0, `expected exit 0, got ${this.result.status}; stderr: ${this.result.stderr}`);
  const greenPidPath = join(this.testDir, "green-background.pid");
  assert(existsSync(greenPidPath), "green background execution was not started by the ssh stub");
  assert(isAlive(Number(readFileSync(greenPidPath, "utf8"))), "green background execution already finished: the CLI waited for it");
  assert(this.elapsedMilliseconds < 60000, `CLI waited for the green background completion (${this.elapsedMilliseconds} ms)`);
});

// ---- Then: 引数列 ----
Then(/^execution_specs の run_id="([^"]+)" 行の additional_args に "([^"]+)" が保存される$/, function (runId, expected) {
  assertEqual(query(this.dbPath, `SELECT additional_args FROM execution_specs WHERE run_id = ${sqlString(runId)};`)[0][0], expected, "execution_specs.additional_args");
});
Then(/^slot_execution_specs の \(run_id="([^"]+)", slot_type="blue"\) 行の fixed_args に "([^"]+)" が保存される$/, function (runId, expected) {
  assertEqual(query(this.dbPath, `SELECT fixed_args FROM slot_execution_specs WHERE run_id = ${sqlString(runId)} AND slot_type = 'blue';`)[0][0], expected, "slot_execution_specs.fixed_args");
});
Then(/^blue実装への起動イベントの引数列が "([^"]+)"（固定引数→追加引数の順、順序・値とも改変なし）で構成される$/, function (expectedArgv) {
  const { remoteCommand } = remoteCommandOf(launchLineFor(this, "blue"));
  const scriptPath = query(this.dbPath, "SELECT script_path FROM slot_execution_specs WHERE slot_type = 'blue';")[0][0];
  const marker = ` ${scriptPath} `;
  const index = remoteCommand.indexOf(marker);
  assert(index >= 0, `blue launch command does not invoke ${scriptPath}: ${remoteCommand}`);
  assertEqual(remoteCommand.slice(index + marker.length), expectedArgv, "blue launch argv");
});

// ---- Then: runner 設定の差し替え ----
Then(/^slot_execution_specs に \(run_id="([^"]+)", slot_type="green", script_path="([^"]+)", impl_version="([^"]+)"\) の1行がINSERTされる$/, function (runId, scriptPath, implVersion) {
  const rows = query(this.dbPath, "SELECT run_id, slot_type, script_path, impl_version FROM slot_execution_specs;");
  assertEqual(rows.length, 1, "slot_execution_specs rows");
  assertEqual(rows[0].join("|"), [runId, "green", scriptPath, implVersion].join("|"), "slot_execution_specs green row");
});
Then(/^green実装への起動イベントは slot_execution_specs の host \/ exec_user \/ script_path \/ work_dir \/ fixed_args \/ credential_ref の値のみから構成され、facadeは実装固有の起動方式差異（実装名・バージョンによる分岐）を参照しない$/, function () {
  const row = query(this.dbPath, "SELECT host, exec_user, script_path, work_dir, COALESCE(fixed_args, ''), impl_version FROM slot_execution_specs WHERE slot_type = 'green';")[0];
  const [host, execUser, scriptPath, workDir, fixedArgs, implVersion] = row;
  const { target, remoteCommand } = remoteCommandOf(launchLineFor(this, "green"));
  assertEqual(target, `${execUser}@${host}`, "ssh target from exec_user/host");
  // remote_command = `cd <work_dir> && <run 実行コンテキスト> <script_path>[ <fixed_args>]`。run 実行コンテキスト以外は slot_execution_specs の値だけで構成される
  const pattern = new RegExp(`^cd (\\S+) && RELAYGATE_RUN_ID=\\S+ RELAYGATE_ATTEMPT_ID=\\S+ RELAYGATE_SLOT=green RELAYGATE_ROLE=\\S+ RELAYGATE_RAPID_CROSSCHECK_MODE=\\S+ (\\S+)(?: (.*))?$`);
  const match = remoteCommand.match(pattern);
  assert(match, `green launch command is not composed only from slot_execution_specs values: ${remoteCommand}`);
  assertEqual(match[1], workDir, "work_dir in launch command");
  assertEqual(match[2], scriptPath, "script_path in launch command");
  assertEqual(match[3] || "", fixedArgs, "fixed_args in launch command");
  assert(!remoteCommand.includes(implVersion), `launch command references impl_version ${implVersion}: ${remoteCommand}`);
  assert(!/green-next|green-0\.9|green-1\.0/.test(remoteCommand.replace(scriptPath, "")), `launch command branches on implementation name/version: ${remoteCommand}`);
});

// ---- Then: 異常系 ----
Then(/^execution_specs・slot_execution_specs・runner_results・audit_logs へのINSERTは発生しない$/, function () {
  for (const table of ["execution_specs", "slot_execution_specs", "runner_results", "audit_logs"]) {
    assertEqual(countRows(this.dbPath, table), 0, `${table} rows`);
  }
});
Then(/^標準エラーに起動前監査の追記失敗の原因と次アクションが出力される$/, function () {
  assert(/Pre-launch audit append failed/.test(this.result.stderr), `stderr lacks the audit append failure cause: ${this.result.stderr}`);
  assert(/boundary=rdb/.test(this.result.stderr), `stderr lacks the failure boundary: ${this.result.stderr}`);
  assert(/Next action:/.test(this.result.stderr), `stderr lacks the next action: ${this.result.stderr}`);
});
Then(/^execution_specs・slot_execution_specs・runner_results・runner_result_events へのINSERTはrollbackされ残らない$/, function () {
  for (const table of ["execution_specs", "slot_execution_specs", "runner_results", "runner_result_events"]) {
    assertEqual(countRows(this.dbPath, table), 0, `${table} rows`);
  }
});
Then(/^blue実装・green実装への起動イベントは送出されない$/, function () {
  assertEqual(launchLines(this).length, 0, "launch events");
});
