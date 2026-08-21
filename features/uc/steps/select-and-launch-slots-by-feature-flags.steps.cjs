// UC BDD step definitions(②)。S2 scoped 再実行(spec 20260819_114307 還流)で再生成した skeleton。
// 方針:
//   - feature 文言が変わらなかった step(When / 終了コード / 標準エラー {string})は旧実装を引き継ぐ
//   - 新仕様で追加・変更された step は「未実装」を明示して fail させ、S6 uc-bdd が結線する
//   - step 文言に ASCII の "/" "(" ")" が含まれるため cucumber expression ではなく正規表現で定義する
//   - ハーネスは新仕様の 11 テーブル契約(packages/contracts/relay-gate-db/schema-constants.sh)に合わせる。
//     RDB の正本は PostgreSQL だが、既存の限定検証境界(issues/20260817T230000Z)に従い SQLite で検証する
const { After, Before, Given, Then, When } = require("@cucumber/cucumber");
const { mkdtempSync, mkdirSync, rmSync, writeFileSync } = require("node:fs");
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

function execute(command, args, options = {}) {
  return spawnSync(command, args, { encoding: "utf8", ...options });
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function notImplemented(step) {
  throw new Error(`not implemented (S2 scaffold, spec 20260819_114307): ${step}`);
}

// ジョブマップ fixture(spec.md の Given 値)。ファイル形式は未契約(issues/20260817T000000Z)のため
// 検証境界の仮形式(JSON・slot 別エントリ)とし、S6 が実装形式に合わせて調整してよい
function jobMapDocument(version = "v1.4.0") {
  return {
    version,
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
}

function setModes(world, blue, green, rapid) {
  Object.assign(world.env, { BLUE_MODE: blue, GREEN_MODE: green, RAPID_CROSSCHECK_MODE: rapid, RELAYGATE_OPERATOR: "ops-tanaka" });
}

Before(function () {
  this.testDir = mkdtempSync(join(tmpdir(), "relaygate-uc-select-slot-"));
  this.dbPath = join(this.testDir, "relaygate.db");
  this.jobMapPath = join(this.testDir, "job-map.json");
  this.launchLogPath = join(this.testDir, "ssh-launch.log");
  const binDir = join(this.testDir, "bin");
  mkdirSync(binDir);
  writeFileSync(join(binDir, "ssh"), "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"$RELAYGATE_TEST_LAUNCH_LOG\"\nexit 0\n", { mode: 0o755 });
  writeFileSync(this.jobMapPath, JSON.stringify(jobMapDocument()));
  const schema = execute("sqlite3", [this.dbPath, CONTRACT_SCHEMA]);
  assert(schema.status === 0, `failed to create SQLite contract schema: ${schema.stderr}`);
  this.env = { ...process.env, PATH: `${binDir}:${process.env.PATH}`, RELAYGATE_RDB_DSN: `sqlite://${this.dbPath}`, RELAYGATE_JOB_MAP_PATH: this.jobMapPath, RELAYGATE_TEST_LAUNCH_LOG: this.launchLogPath };
});

After(function () { rmSync(this.testDir, { recursive: true, force: true }); });

// ---- Given: 環境変数(4 通りの組み合わせ。RELAYGATE_OPERATOR が必須になった) ----
Given(/^環境変数に BLUE_MODE=(off|background|foreground), GREEN_MODE=(off|background|foreground), RAPID_CROSSCHECK_MODE=(on|off), RELAYGATE_OPERATOR=ops-tanaka が設定されている$/, function (blue, green, rapid) {
  setModes(this, blue, green, rapid);
});

// ---- Given: ジョブマップ fixture ----
Given(/^ジョブマップ v1\.4\.0 で job_id "daily-settlement" が blue（host=blue-host-01, exec_user=batchuser, work_dir=\/opt\/relaygate\/work, impl_version=blue-2\.3\.1）と green（host=green-host-01, exec_user=batchuser, work_dir=\/opt\/relaygate\/work, impl_version=green-0\.9\.0）に解決できる$/, function () {
  notImplemented("job map v1.4.0 resolves blue/green with exec_user and work_dir (job map file format is decided by the implementation)");
});
Given(/^ジョブマップ v1\.4\.0 で job_id "daily-settlement" が blue（host=blue-host-01, impl_version=blue-2\.3\.1）と green（host=green-host-01, impl_version=green-0\.9\.0）に解決できる$/, function () {
  notImplemented("job map v1.4.0 resolves blue/green entries");
});
Given(/^ジョブマップ v1\.4\.0 で job_id "daily-settlement" が green（host=green-host-01, impl_version=green-0\.9\.0）に解決できる$/, function () {
  notImplemented("job map v1.4.0 resolves green entry");
});
Given(/^ジョブマップ v1\.4\.0 で job_id "daily-settlement" が解決できる$/, function () {
  notImplemented("job map v1.4.0 resolves daily-settlement");
});
Given(/^ジョブマップの hang_detect_limit_minutes が 30 である$/, function () {
  notImplemented("job map hang_detect_limit_minutes=30");
});
Given(/^ジョブマップ v1\.4\.0 で job_id "daily-settlement" の blue の fixed_args が \["--mode", "batch"\] に定義されている$/, function () {
  notImplemented("job map blue fixed_args [--mode, batch]");
});
Given(/^ジョブマップが v1\.5\.0 に更新され、job_id "daily-settlement" の green が host=green-host-01, exec_user=batchuser, script_path=\/opt\/green-next\/run\.sh, work_dir=\/opt\/relaygate\/work, impl_version=green-1\.0\.0 に差し替えられている$/, function () {
  notImplemented("job map v1.5.0 replaces green entry with green-next runner");
});
Given(/^facade本体のコード・設定はジョブマップ以外に一切変更されていない$/, function () {
  notImplemented("assert facade code and config unchanged except the job map (for example compare facade/ tree hash)");
});
Given(/^job_id "unknown-job" がジョブマップ v1\.4\.0 に存在しない$/, function () {
  notImplemented("job map v1.4.0 without unknown-job");
});

// ---- Given: 発番固定・外部状態 ----
Given(/^run_id発番が "([^"]+)" を返すよう固定されている$/, function (_runId) {
  notImplemented("fixed run_id generator (id generation seam is decided by the implementation)");
});
Given(/^run_id発番が "([^"]+)" を、attempt_id発番が blue="([^"]+)" \/ green="([^"]+)" を返すよう固定されている$/, function (_runId, _blueAttempt, _greenAttempt) {
  notImplemented("fixed run_id and per-slot attempt_id generators");
});
Given(/^run_id発番が "([^"]+)" を、attempt_id発番が "([^"]+)" を返すよう固定されている$/, function (_runId, _attemptId) {
  notImplemented("fixed run_id and single attempt_id generators");
});
Given(/^blue実装のforeground実行が完了まで60秒かかる状態である$/, function () {
  notImplemented("ssh stub: blue foreground launch takes 60 seconds");
});
Given(/^audit_logs へのINSERTが失敗する状態になっている$/, function () {
  notImplemented("inject audit_logs INSERT failure (for example a SQLite BEFORE INSERT trigger raising ABORT)");
});

// ---- When(文言不変。追加引数 "--" 以降も受け取れるよう拡張) ----
When(/^運用者が `relaygate concurrent-run select-slot --job-id ([^`\s]+)(?: -- ([^`]+))?` を実行する$/, function (jobId, additionalArgs) {
  const args = ["concurrent-run", "select-slot", "--job-id", jobId];
  if (additionalArgs) args.push("--", ...additionalArgs.split(" "));
  this.result = execute(relaygate, args, { env: this.env });
});

// ---- Then: 文言不変(旧実装を引き継ぐ) ----
Then(/^終了コード (\d+) で終了する$/, function (expected) {
  assert(this.result.status === Number(expected), `expected exit ${expected}, got ${this.result.status}; stderr: ${this.result.stderr}`);
});
Then(/^標準エラーに "([^"]+)" が出力される$/, function (message) {
  assert(this.result.stderr.includes(message), `stderr does not contain ${message}: ${this.result.stderr}`);
});

// ---- Then: 新仕様(S6 が結線) ----
Then(/^execution_specs に run_id="([^"]+)", parent_run_id=NULL, job_id="([^"]+)", job_map_version="([^"]+)", hang_detect_limit_minutes=(\d+) の1行がINSERTされる$/, function () {
  notImplemented("assert execution_specs row (run_id, parent_run_id NULL, job_id, job_map_version, hang_detect_limit_minutes)");
});
Then(/^slot_execution_specs に \(run_id="[^"]+", slot_type="blue", host="[^"]+", impl_version="[^"]+", credential_ref="[^"]+"\) と \(run_id="[^"]+", slot_type="green", host="[^"]+", impl_version="[^"]+", credential_ref="[^"]+"\) の2行が \(run_id, slot_type\) で一意に識別されるようINSERTされる$/, function () {
  notImplemented("assert slot_execution_specs blue/green rows keyed by (run_id, slot_type)");
});
Then(/^slot_execution_specs には認証情報の参照名（credential_ref）のみが保存され、パスワード・秘密鍵などの認証情報の実値は保存されない$/, function () {
  notImplemented("assert slot_execution_specs stores credential_ref only and never the secret value");
});
Then(/^runner_results に \(run_id="[^"]+", slot_type="blue", role_type="foreground", attempt_id="[^"]+", attempt_no=1, status="STARTING"\) と \(run_id="[^"]+", slot_type="green", role_type="background", attempt_id="[^"]+", attempt_no=1, status="STARTING"\) の2行が accepted_at 付きでINSERTされる$/, function () {
  notImplemented("assert runner_results STARTING rows for blue/foreground and green/background with accepted_at");
});
Then(/^runner_result_events に対応する event_name="attempt_started", status="STARTING" の履歴が同一transactionでINSERTされる$/, function () {
  notImplemented("assert runner_result_events attempt_started history matches runner_results rows");
});
Then(/^audit_logs に \(run_id="[^"]+", event_name="slot_launch_accepted", slot="-", attempt_id="-", actor="[^"]+", operation="slot_launch", outcome="accepted", schema_version="1\.0"\) の起動前監査イベントがINSERTされ、audit_chain_heads の run_id 行が更新される$/, function () {
  notImplemented("assert audit_logs slot_launch_accepted row and audit_chain_heads head update");
});
Then(/^標準出力に run_id="[^"]+" の blue\/foreground\/att-blue-0001\/STARTING 行と green\/background\/att-green-0001\/STARTING 行が出力される$/, function () {
  notImplemented("assert stdout has one line per selected slot (run_id, slot_type, role, attempt_id, STARTING)");
});
Then(/^rapid_crosscheck_requests へのINSERTは発生しない$/, function () {
  notImplemented("assert rapid_crosscheck_requests is empty");
});
Then(/^execution_specs に run_id="[^"]+" の1行が、slot_execution_specs に slot_type="green" の1行のみがINSERTされる$/, function () {
  notImplemented("assert execution_specs single row and slot_execution_specs green only");
});
Then(/^runner_results に \(run_id="[^"]+", slot_type="green", role_type="foreground", attempt_id="[^"]+", attempt_no=1, status="STARTING"\) の1行がINSERTされる$/, function () {
  notImplemented("assert runner_results single green/foreground STARTING row");
});
Then(/^標準出力に green\/foreground\/att-green-0001\/STARTING の1行のみが出力される（運用モード: 新実装単独本番に相当する組み合わせ）$/, function () {
  notImplemented("assert stdout has exactly one green/foreground line");
});
Then(/^green実装へのbackground起動イベント（非同期起動トリガー）が、blue実装へのforeground起動イベント（同期実行）より先に送出される$/, function () {
  notImplemented("assert launch log order: green background before blue foreground");
});
Then(/^blue foreground実行の待機中に、runner_results の \(run_id="[^"]+", slot_type="green", role_type="background", attempt_id="[^"]+"\) が status="RUNNING" で並走している$/, function () {
  notImplemented("assert green background runner_results is RUNNING while blue foreground waits (depends on UC c3c7ab31 status transition; see issues/)");
});
Then(/^blue foreground実行の完了を待ってから終了コード 0 で終了し、green background実行の完了は待たない$/, function () {
  notImplemented("assert exit 0 after blue foreground completes without waiting for green background");
});
Then(/^execution_specs の run_id="[^"]+" 行の additional_args に "([^"]+)" が保存される$/, function (_args) {
  notImplemented("assert execution_specs.additional_args");
});
Then(/^slot_execution_specs の \(run_id="[^"]+", slot_type="blue"\) 行の fixed_args に "([^"]+)" が保存される$/, function (_args) {
  notImplemented("assert slot_execution_specs.fixed_args for blue");
});
Then(/^blue実装への起動イベントの引数列が "([^"]+)"（固定引数→追加引数の順、順序・値とも改変なし）で構成される$/, function (_argv) {
  notImplemented("assert blue launch argv = fixed_args then additional_args in order");
});
Then(/^slot_execution_specs に \(run_id="[^"]+", slot_type="green", script_path="[^"]+", impl_version="[^"]+"\) の1行がINSERTされる$/, function () {
  notImplemented("assert slot_execution_specs green row with replaced script_path and impl_version");
});
Then(/^green実装への起動イベントは slot_execution_specs の host \/ exec_user \/ script_path \/ work_dir \/ fixed_args \/ credential_ref の値のみから構成され、facadeは実装固有の起動方式差異（実装名・バージョンによる分岐）を参照しない$/, function () {
  notImplemented("assert green launch is composed only from slot_execution_specs columns");
});
Then(/^execution_specs・slot_execution_specs・runner_results・audit_logs へのINSERTは発生しない$/, function () {
  notImplemented("assert no rows in execution_specs, slot_execution_specs, runner_results, audit_logs");
});
Then(/^標準エラーに起動前監査の追記失敗の原因と次アクションが出力される$/, function () {
  notImplemented("assert stderr explains audit append failure cause and next action");
});
Then(/^execution_specs・slot_execution_specs・runner_results・runner_result_events へのINSERTはrollbackされ残らない$/, function () {
  notImplemented("assert rollback left no rows in the four tables");
});
Then(/^blue実装・green実装への起動イベントは送出されない$/, function () {
  notImplemented("assert launch log is empty");
});
