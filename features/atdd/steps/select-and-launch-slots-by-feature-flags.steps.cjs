// ATDD step definitions(①)。uc-map 6078c4ed の atdd_scenarios(SPEC-001-01/02/03, SPEC-009-01/02/03 の各 -1)を
// tier-facade attempt 6 の実装(facade/bin/relaygate)へ結線する。S7 atdd で旧仕様・旧契約前提の steps を全面更新した。
// 方針:
//   - 受け入れ基準(USDM acceptance_criteria)は 1 行の Given/When/Then で具体値を持たない。具体値は spec.md の
//     E2E 完了条件(BDD)の Given 値(ジョブマップ v1.4.0 / daily-settlement / blue-host-01 等)をそのまま使う
//   - 「execution-spec.json」(RDRA 情報)は spec.md 関連 RDRA モデルのとおり execution_specs + slot_execution_specs
//     (RDB)へ分離して保存される。SPEC-009-03 はこの 2 テーブルの実体で検証する
//   - ハーネスは features/uc/steps と同じ: SQLite 検証境界(issues/20260821T220045Z §1)、PATH 先頭の ssh スタブ
//     (引数列を起動ログへ 1 行ずつ追記)、RELAYGATE_ID_GENERATOR seam(facade/src/id_gateway.sh)による発番固定、
//     facade/src/job_map_gateway.sh 冒頭コメントの JSON ジョブマップ形式
//   - step 文言に ASCII の "/" が含まれるため cucumber expression ではなく正規表現で定義する
//   - 本ファイルは tier 実装を変更しない。ハーネス注入(後続 UC の模擬)は本 6 Scenario には不要
const { After, Before, Given, Then, When } = require("@cucumber/cucumber");
const { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } = require("node:fs");
const { spawnSync } = require("node:child_process");
const { tmpdir } = require("node:os");
const { join, resolve } = require("node:path");

const projectRoot = resolve(__dirname, "../../..");
const relaygate = join(projectRoot, "facade", "bin", "relaygate");

const JOB_ID = "daily-settlement";
const JOB_MAP_VERSION = "v1.4.0";
const HANG_DETECT_LIMIT_MINUTES = 30;
const RUN_ID_FIRST = "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57";
const RUN_ID_SECOND = "7a1d4c0b-2e9f-4b36-8d5a-0c4e6f2b9a11";
// 認証情報の実値の代わり(ジョブマップに混入させ、保存されないことを検証する)。facade はこのフィールドを読まない
const CREDENTIAL_SECRET = "-----BEGIN OPENSSH PRIVATE KEY----- atdd-secret-material";

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

// ssh スタブ: 起動イベント(引数列)を起動ログへ追記して成功を返す
const SSH_STUB = "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"$RELAYGATE_TEST_LAUNCH_LOG\"\nexit 0\n";

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

function jobMapDocument(slotOverrides = {}) {
  return {
    version: JOB_MAP_VERSION,
    jobs: {
      [JOB_ID]: {
        hang_detect_limit_minutes: HANG_DETECT_LIMIT_MINUTES,
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
  world.jobMapSnapshot = readFileSync(world.jobMapPath, "utf8");
}

function setModes(world, blue, green, rapid) {
  Object.assign(world.env, { BLUE_MODE: blue, GREEN_MODE: green, RAPID_CROSSCHECK_MODE: rapid });
}

// 実装の発番 seam(`<generator> <kind> [<qualifier>]`)へ固定値を返す generator を差し込む。
// attempt_id の qualifier は slot 名(facade/src/id_gateway.sh issue_run_identity)
function installIdGenerator(world, runId) {
  const script = [
    "#!/usr/bin/env bash",
    'case "$1" in',
    `  run_id) printf '%s' ${JSON.stringify(runId)} ;;`,
    "  attempt_id) printf 'att-%s-0001' \"$2\" ;;",
    "  *) uuidgen | tr '[:upper:]' '[:lower:]' ;;",
    "esac",
    "",
  ].join("\n");
  const generatorPath = join(world.binDir, "fixed-id-generator");
  writeFileSync(generatorPath, script, { mode: 0o755 });
  world.env.RELAYGATE_ID_GENERATOR = generatorPath;
}

// runSelectSlot は facade を実プロセスで起動し、結果と「この起動で送出された起動イベント」を返す
function runSelectSlot(world, additionalArgs = []) {
  const before = launchLines(world).length;
  const args = ["concurrent-run", "select-slot", "--job-id", JOB_ID];
  if (additionalArgs.length > 0) args.push("--", ...additionalArgs);
  const result = execute(relaygate, args, { env: world.env });
  result.launches = launchLines(world).slice(before);
  world.result = result;
  return result;
}

function launchLines(world) {
  if (!existsSync(world.launchLogPath)) return [];
  return readFileSync(world.launchLogPath, "utf8").split("\n").filter((line) => line.length > 0);
}

function stdoutLines(result) {
  return result.stdout.split("\n").filter((line) => line.length > 0);
}

function launchLineFor(lines, slot) {
  const matched = lines.filter((line) => line.includes(`RELAYGATE_SLOT=${slot} `));
  assertEqual(matched.length, 1, `launch events for ${slot}`);
  return matched[0];
}

// 起動ログ 1 行から ssh 接続先と remote_command(`<user@host>` の後ろ)を取り出す
// (facade/src/launch_gateway.sh: `ssh -n -o BatchMode=yes -- <user@host> <remote_command>`)
function remoteCommandOf(line) {
  const match = line.match(/^-n -o BatchMode=yes -- (\S+) (.*)$/);
  assert(match, `unexpected launch line: ${line}`);
  return { target: match[1], remoteCommand: match[2] };
}

// remote_command から `<script_path>` 以降の引数列を取り出す
function launchArgvOf(remoteCommand, scriptPath) {
  const marker = ` ${scriptPath}`;
  const index = remoteCommand.indexOf(marker);
  assert(index >= 0, `launch command does not invoke ${scriptPath}: ${remoteCommand}`);
  return remoteCommand.slice(index + marker.length).trim();
}

function assertExitZero(result, label) {
  assert(result.status === 0, `${label}: expected exit 0, got ${result.status}; stderr: ${result.stderr}`);
}

// runnerRows は runner_results の (slot_type, role_type, status) を slot 順で "slot/role/status" 文字列にする
function runnerRows(dbPath, runId) {
  return query(dbPath, `SELECT slot_type, role_type, status FROM runner_results WHERE run_id = ${sqlString(runId)} ORDER BY slot_type;`).map((row) => row.join("/"));
}

Before(function () {
  this.testDir = mkdtempSync(join(tmpdir(), "relaygate-atdd-select-slot-"));
  this.dbPath = join(this.testDir, "relaygate.db");
  this.jobMapPath = join(this.testDir, "job-map.json");
  this.launchLogPath = join(this.testDir, "ssh-launch.log");
  this.binDir = join(this.testDir, "bin");
  mkdirSync(this.binDir);
  writeFileSync(join(this.binDir, "ssh"), SSH_STUB, { mode: 0o755 });
  const schema = execute("sqlite3", [this.dbPath, CONTRACT_SCHEMA]);
  assert(schema.status === 0, `failed to create SQLite contract schema: ${schema.stderr}`);
  this.env = {
    ...process.env,
    PATH: `${this.binDir}:${process.env.PATH}`,
    RELAYGATE_RDB_DSN: `sqlite://${this.dbPath}`,
    RELAYGATE_JOB_MAP_PATH: this.jobMapPath,
    RELAYGATE_TEST_LAUNCH_LOG: this.launchLogPath,
    RELAYGATE_OPERATOR: "ops-tanaka",
  };
  // 既定: 並行稼働(blue foreground / green background)。Scenario の Given が上書きする
  writeJobMap(this, jobMapDocument());
  setModes(this, "foreground", "background", "on");
  installIdGenerator(this, RUN_ID_FIRST);
  this.additionalArgs = [];
});

After(function () {
  rmSync(this.testDir, { recursive: true, force: true });
});

// ======== SPEC-001-01-1: 設定に従い blue・green の各 slot が起動される ========
Given(/^feature flag設定（BLUE_MODE\/GREEN_MODE）が投入されている$/, function () {
  setModes(this, "foreground", "background", "on");
});

When(/^facadeがJOB_IDを受け取る$/, function () {
  runSelectSlot(this);
});

Then(/^設定に従いblue・greenの各slotが起動される$/, function () {
  assertExitZero(this.result, "select-slot");
  // 起動イベント: blue は foreground、green は background で、設定どおり両 slot へ送出される
  const blue = remoteCommandOf(launchLineFor(this.result.launches, "blue"));
  const green = remoteCommandOf(launchLineFor(this.result.launches, "green"));
  assertEqual(this.result.launches.length, 2, "launch events");
  assertEqual(blue.target, "batchuser@blue-host-01", "blue launch target");
  assertEqual(green.target, "batchuser@green-host-01", "green launch target");
  assert(blue.remoteCommand.includes("RELAYGATE_ROLE=foreground "), `blue was not launched as foreground: ${blue.remoteCommand}`);
  assert(green.remoteCommand.includes("RELAYGATE_ROLE=background "), `green was not launched as background: ${green.remoteCommand}`);
  // 起動受付の記録と応答も設定どおりの slot / role である
  assertEqual(runnerRows(this.dbPath, RUN_ID_FIRST).join(","), "blue/foreground/STARTING,green/background/STARTING", "runner_results");
  const lines = stdoutLines(this.result);
  assert(lines.includes(`run_id=${RUN_ID_FIRST} slot_type=blue role=foreground attempt_id=att-blue-0001 status=STARTING`), `stdout lacks blue line: ${this.result.stdout}`);
  assert(lines.includes(`run_id=${RUN_ID_FIRST} slot_type=green role=background attempt_id=att-green-0001 status=STARTING`), `stdout lacks green line: ${this.result.stdout}`);
});

// ======== SPEC-001-02-1: ジョブ定義を変更せず運用モードが切り替わる ========
Given(/^BLUE_MODE\/GREEN_MODE\/RAPID_CROSSCHECK_MODEの組み合わせを変更する$/, function () {
  // 1 回目: 並行稼働(BLUE_MODE=foreground, GREEN_MODE=background, RAPID_CROSSCHECK_MODE=on)で起動しておく
  setModes(this, "foreground", "background", "on");
  installIdGenerator(this, RUN_ID_FIRST);
  this.firstResult = runSelectSlot(this);
  // 2 回目: 新実装単独本番(BLUE_MODE=off, GREEN_MODE=foreground, RAPID_CROSSCHECK_MODE=off)へ設定だけを変える
  setModes(this, "off", "foreground", "off");
  installIdGenerator(this, RUN_ID_SECOND);
});

When(/^同じジョブ定義でジョブを起動する$/, function () {
  assertEqual(readFileSync(this.jobMapPath, "utf8"), this.jobMapSnapshot, "job map before the second launch");
  this.secondResult = runSelectSlot(this);
});

Then(/^ジョブ定義を変更せず運用モードが切り替わる$/, function () {
  assertExitZero(this.firstResult, "first launch (parallel operation)");
  assertExitZero(this.secondResult, "second launch (green-only production)");
  // ジョブ定義(ジョブマップ)は両起動を通じて変更されていない
  assertEqual(readFileSync(this.jobMapPath, "utf8"), this.jobMapSnapshot, "job map after both launches");
  // 1 回目は並行稼働: blue foreground + green background
  assertEqual(runnerRows(this.dbPath, RUN_ID_FIRST).join(","), "blue/foreground/STARTING,green/background/STARTING", "first run runner_results");
  assertEqual(this.firstResult.launches.length, 2, "first run launch events");
  assert(remoteCommandOf(launchLineFor(this.firstResult.launches, "blue")).remoteCommand.includes("RELAYGATE_ROLE=foreground "), "first run: blue is not foreground");
  assert(remoteCommandOf(launchLineFor(this.firstResult.launches, "green")).remoteCommand.includes("RELAYGATE_ROLE=background "), "first run: green is not background");
  // 2 回目は新実装単独本番: green foreground のみ(blue は起動されない)
  assertEqual(runnerRows(this.dbPath, RUN_ID_SECOND).join(","), "green/foreground/STARTING", "second run runner_results");
  assertEqual(query(this.dbPath, `SELECT slot_type FROM slot_execution_specs WHERE run_id = ${sqlString(RUN_ID_SECOND)};`).map((row) => row[0]).join(","), "green", "second run slot_execution_specs");
  assertEqual(this.secondResult.launches.length, 1, "second run launch events");
  assert(remoteCommandOf(launchLineFor(this.secondResult.launches, "green")).remoteCommand.includes("RELAYGATE_ROLE=foreground RELAYGATE_RAPID_CROSSCHECK_MODE=off "), "second run: green is not foreground with rapid crosscheck off");
  // 両 run とも同じジョブマップ版から解決されている
  assertEqual(query(this.dbPath, "SELECT DISTINCT job_map_version FROM execution_specs;").map((row) => row[0]).join(","), JOB_MAP_VERSION, "job_map_version across runs");
});

// ======== SPEC-001-03-1: 同時 foreground は起動を許可しない ========
Given(/^BLUE_MODEとGREEN_MODEの両方にforegroundを設定しようとする$/, function () {
  setModes(this, "foreground", "foreground", "on");
});

When(/^facadeが設定を検証する$/, function () {
  runSelectSlot(this);
});

Then(/^起動を許可しない$/, function () {
  assert(this.result.status === 2, `expected validation exit 2, got ${this.result.status}; stderr: ${this.result.stderr}`);
  assert(this.result.stderr.includes("BLUE_MODEとGREEN_MODEを同時にforegroundにすることはできません"), `stderr lacks the exclusive-foreground message: ${this.result.stderr}`);
  assertEqual(this.result.launches.length, 0, "launch events despite foreground conflict");
  assertEqual(stdoutLines(this.result).length, 0, "stdout lines despite foreground conflict");
  for (const table of ["execution_specs", "slot_execution_specs", "runner_results", "runner_result_events", "audit_logs"]) {
    assertEqual(countRows(this.dbPath, table), 0, `${table} rows despite foreground conflict`);
  }
});

// ======== SPEC-009-01-1: JOB_ID と追加引数だけから実行先の詳細が解決される ========
Given(/^ジョブスケジューラがJOB_IDと追加引数だけを渡す$/, function () {
  this.additionalArgs = ["--target-date", "2026-08-18"];
  // ジョブスケジューラ由来の入力は JOB_ID と追加引数のみ。実行先の詳細は環境変数でも渡さない
  for (const key of Object.keys(this.env)) {
    assert(!/^RELAYGATE_(HOST|EXEC_USER|SCRIPT_PATH|WORK_DIR|FIXED_ARGS)$/.test(key), `execution target leaked into the scheduler input: ${key}`);
  }
});

When(/^slot runnerがジョブマップを参照する$/, function () {
  runSelectSlot(this, this.additionalArgs);
});

Then(/^実行先の詳細が解決される$/, function () {
  assertExitZero(this.result, "job map resolution");
  // run 共通項目(ジョブマップ版・hang_detect_limit_minutes・追加引数)が解決される
  const run = query(this.dbPath, `SELECT job_id, job_map_version, hang_detect_limit_minutes, additional_args FROM execution_specs WHERE run_id = ${sqlString(RUN_ID_FIRST)};`);
  assertEqual(run.length, 1, "execution_specs rows");
  assertEqual(run[0].join("|"), [JOB_ID, JOB_MAP_VERSION, String(HANG_DETECT_LIMIT_MINUTES), "--target-date 2026-08-18"].join("|"), "execution_specs row");
  // slot 別項目(ホスト・実行ユーザー・スクリプト・作業ディレクトリ)がジョブマップの値に解決される
  const rows = query(this.dbPath, `SELECT slot_type, host, exec_user, script_path, work_dir FROM slot_execution_specs WHERE run_id = ${sqlString(RUN_ID_FIRST)} ORDER BY slot_type;`);
  assertEqual(rows.map((row) => row.join("|")).join(","), ["blue|blue-host-01|batchuser|/opt/blue/run.sh|/opt/relaygate/work", "green|green-host-01|batchuser|/opt/green/run.sh|/opt/relaygate/work"].join(","), "slot_execution_specs rows");
  // 起動イベントも解決済みの実行先で構成される
  for (const [slot, host, scriptPath] of [["blue", "blue-host-01", "/opt/blue/run.sh"], ["green", "green-host-01", "/opt/green/run.sh"]]) {
    const { target, remoteCommand } = remoteCommandOf(launchLineFor(this.result.launches, slot));
    assertEqual(target, `batchuser@${host}`, `${slot} launch target`);
    assert(remoteCommand.startsWith("cd /opt/relaygate/work && "), `${slot} launch does not change into the resolved work_dir: ${remoteCommand}`);
    assertEqual(launchArgvOf(remoteCommand, scriptPath), "--target-date 2026-08-18", `${slot} launch argv`);
  }
});

// ======== SPEC-009-02-1: 固定引数の後ろに追加引数が順序どおり連結される ========
Given(/^job mapに固定引数が定義されている$/, function () {
  writeJobMap(this, jobMapDocument({ blue: { fixed_args: ["--mode", "batch"] }, green: { fixed_args: ["--mode", "batch", "--profile", "green"] } }));
});

When(/^ジョブスケジューラから追加引数が渡される$/, function () {
  this.additionalArgs = ["--target-date", "2026-08-18", "--retry", "3"];
  runSelectSlot(this, this.additionalArgs);
});

Then(/^固定引数の後ろに追加引数が順序どおり連結される$/, function () {
  assertExitZero(this.result, "launch with fixed and additional args");
  assertEqual(query(this.dbPath, `SELECT additional_args FROM execution_specs WHERE run_id = ${sqlString(RUN_ID_FIRST)};`)[0][0], "--target-date 2026-08-18 --retry 3", "execution_specs.additional_args");
  assertEqual(query(this.dbPath, `SELECT fixed_args FROM slot_execution_specs WHERE run_id = ${sqlString(RUN_ID_FIRST)} AND slot_type = 'blue';`)[0][0], "--mode batch", "slot_execution_specs.fixed_args (blue)");
  assertEqual(query(this.dbPath, `SELECT fixed_args FROM slot_execution_specs WHERE run_id = ${sqlString(RUN_ID_FIRST)} AND slot_type = 'green';`)[0][0], "--mode batch --profile green", "slot_execution_specs.fixed_args (green)");
  // 起動イベントの引数列は slot ごとに「固定引数 → 追加引数」の順で、順序・値とも改変されない
  const blue = remoteCommandOf(launchLineFor(this.result.launches, "blue"));
  assertEqual(launchArgvOf(blue.remoteCommand, "/opt/blue/run.sh"), "--mode batch --target-date 2026-08-18 --retry 3", "blue launch argv");
  const green = remoteCommandOf(launchLineFor(this.result.launches, "green"));
  assertEqual(launchArgvOf(green.remoteCommand, "/opt/green/run.sh"), "--mode batch --profile green --target-date 2026-08-18 --retry 3", "green launch argv");
});

// ======== SPEC-009-03-1: 解決済み設定が一度だけ確定して保存され、認証情報そのものは含まれない ========
Given(/^slot runnerが実行先を解決する$/, function () {
  // 認証情報の実値をジョブマップに混入させる(facade が読まない余剰フィールド)。参照名だけが保存されることを検証する
  writeJobMap(this, jobMapDocument({
    blue: { fixed_args: ["--mode", "batch"], credential_secret: CREDENTIAL_SECRET },
    green: { credential_secret: CREDENTIAL_SECRET },
  }));
  this.additionalArgs = ["--target-date", "2026-08-18"];
});

When(/^起動する$/, function () {
  runSelectSlot(this, this.additionalArgs);
});

Then(/^execution-spec\.jsonに解決済み設定が一度だけ確定して保存され、認証情報そのものは含まれない$/, function () {
  assertExitZero(this.result, "launch");
  // 一度だけ確定: run 共通設定は run_id で 1 行、slot 別設定は (run_id, slot_type) で slot ごとに 1 行
  assertEqual(countRows(this.dbPath, "execution_specs"), 1, "execution_specs rows");
  assertEqual(countRows(this.dbPath, "slot_execution_specs"), 2, "slot_execution_specs rows");
  assertEqual(query(this.dbPath, "SELECT COUNT(DISTINCT run_id || '/' || slot_type) FROM slot_execution_specs;")[0][0], "2", "(run_id, slot_type) uniqueness");
  // 解決済み設定: 追加引数・マップ版・hang_detect_limit_minutes(run 共通)
  const run = query(this.dbPath, "SELECT run_id, COALESCE(parent_run_id, 'NULL'), job_id, additional_args, job_map_version, hang_detect_limit_minutes FROM execution_specs;")[0];
  assertEqual(run.join("|"), [RUN_ID_FIRST, "NULL", JOB_ID, "--target-date 2026-08-18", JOB_MAP_VERSION, String(HANG_DETECT_LIMIT_MINUTES)].join("|"), "execution_specs row");
  // 解決済み設定: ホスト・スクリプト・作業ディレクトリ・固定引数・実装版・認証情報の参照名(slot 別)
  const slots = query(this.dbPath, "SELECT run_id, slot_type, host, exec_user, script_path, work_dir, COALESCE(fixed_args, ''), impl_version, credential_ref FROM slot_execution_specs ORDER BY slot_type;");
  assertEqual(slots[0].join("|"), [RUN_ID_FIRST, "blue", "blue-host-01", "batchuser", "/opt/blue/run.sh", "/opt/relaygate/work", "--mode batch", "blue-2.3.1", "cred-blue-batch"].join("|"), "slot_execution_specs blue row");
  assertEqual(slots[1].join("|"), [RUN_ID_FIRST, "green", "green-host-01", "batchuser", "/opt/green/run.sh", "/opt/relaygate/work", "", "green-0.9.0", "cred-green-batch"].join("|"), "slot_execution_specs green row");
  // 認証情報そのものは含まれない: 実値を持つ列が無く、保存内容のどこにも実値が現れない
  const columns = query(this.dbPath, "PRAGMA table_info(slot_execution_specs);").map((row) => row[1]);
  assertEqual(columns.filter((name) => /password|secret|private_key|passphrase|token/i.test(name)).join(","), "", "secret-bearing columns in slot_execution_specs");
  const dump = execute("sqlite3", [this.dbPath, ".dump"]);
  assert(dump.status === 0, `sqlite3 .dump failed: ${dump.stderr}`);
  assert(!dump.stdout.includes(CREDENTIAL_SECRET) && !dump.stdout.includes("PRIVATE KEY"), "credential secret was persisted into the RDB");
  // 起動イベントにも認証情報の実値は含まれない(参照名は鍵解決方式が未契約のため起動コマンドにも現れない)
  for (const line of this.result.launches) {
    assert(!line.includes(CREDENTIAL_SECRET) && !line.includes("PRIVATE KEY"), `credential secret leaked into the launch event: ${line}`);
  }
  assert(!this.result.stdout.includes(CREDENTIAL_SECRET), "credential secret leaked into stdout");
});
