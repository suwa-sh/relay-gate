// ATDD(①)step definition。uc_id=09730858 / branch_slug=select-slot-mode-and-launch-runners(S7 atdd で実装)。
// 対象は uc-map の atdd_scenarios の 14 件だけ:
//   @atdd_SPEC-001-01-1 / -2 / -3、@atdd_SPEC-001-02-1、@atdd_SPEC-001-04-1 / -2、@atdd_SPEC-002-01-1 / -2、
//   @atdd_SPEC-005-06-3 / -4、@atdd_SPEC-011-01-1、@atdd_SPEC-011-04-1 / -2 / -3
// features/atdd/SPEC-*.feature の本文は生成物で、変更しない。
// このファイルが定義するのは、他 UC の step ファイルに定義の無い step だけ(同じ文言を再定義すると ambiguous になる)。
// 同じ文言が複数の Scenario に出る step(「facade を起動する」)は 1 回だけ定義している。前提は Given が World に残す。
// World(root / configDir / sandbox() / unsandbox())と Before / After は configure-feature-flags.steps.js のものを使う。
// このファイルの After / AfterAll は、Scenario が World に残した後始末の対象(長く動くテスト用 runner の PID、終わっていない facade.sh、
// 一時 PostgreSQL)があるときだけ働く(他の Scenario では何もしない)。
//
// ハーネスは UC BDD と同じ補助(features/uc/steps/support/facade-harness.js)を require で使う(複製しない):
//   - facade/bin/facade.sh を実プロセスとして起動する。/etc/relay-gate・/opt/relay-gate は World の sandbox() で一時ディレクトリの下に置く
//   - runner はテスト用 runner(一時ディレクトリの実スクリプト。暫定注入・契約確定後に削除。
//     根拠: docs/impl/latest/09730858/issues/20261118_091109_cross-uc-scenarios.md の 1〜3)
//   - 管理 DB は initdb + pg_ctl の一時 PostgreSQL。参照名 mgmt-db は一時の pg_service.conf で結び付ける
//     (暫定注入・契約確定後に削除。根拠: 前提 A-001。docs/impl/latest/09730858/stages/attempt-3/S4_tier-impl.tier-facade.assumptions.yaml)
//   - 受け入れ基準の Given は要点だけを書いているため、検証を通る値(mode の残り・実装版・テスト用 runner・速報の runner / worker・
//     rapid-crosscheck.env・起動している管理 DB)を補う(同 issue「仕様に書かれていない前提(step が補うもの)」)
// リポジトリの中にはファイルを書かない。
'use strict';
const { Given, Then, When, After, AfterAll } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const YAML = require('yaml');
const h = require('../../uc/steps/support/facade-harness');

const { literal } = h;

const CLI_CONTRACT = path.join(h.REPO_ROOT, 'docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml');
// facade の実体(入口と本体)。SPEC-001-04-2 で「facade を変更せず」を見る対象
const FACADE_DIRS = ['bin', 'src', 'lib', 'runners'];
const JOB_MAP_HEADER = 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes';
const JOB001_ROW = 'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",60';

After(function () {
  h.cleanup(this);
});

AfterAll(function () {
  h.stopDatabase();
});

// 書かれた値を載せ、検証を通る値を補う(RAPID_CROSSCHECK_MODE が書かれていなければ off)。off 以外なら管理 DB を用意する
function defineFlags(world, text) {
  h.setFlags(world, text);
  if (world.flags.RAPID_CROSSCHECK_MODE === undefined) {
    world.flags.RAPID_CROSSCHECK_MODE = 'off';
  }
  h.supplementFlags(world);
  if (world.flags.RAPID_CROSSCHECK_MODE !== 'off') {
    h.startManagementDb(world);
  }
}

function slotDir(world, slot) {
  return path.join(h.runDir(world), slot);
}

function singleInvocation(world, slot) {
  const calls = h.startedInvocations(h.runnerOf(world, slot));
  assert.equal(calls.length, 1, `${slot} runner should be started once: ${calls}\n${h.dump(world)}`);
  return calls[0];
}

function listFiles(dir) {
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .flatMap((entry) => (entry.isDirectory() ? listFiles(path.join(dir, entry.name)) : [path.join(dir, entry.name)]))
    .sort();
}

function hashFiles(files) {
  return Object.fromEntries(files.map((file) => [file, crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')]));
}

function facadeFileHashes() {
  return hashFiles(FACADE_DIRS.flatMap((dir) => listFiles(path.join(h.FACADE_HOME, dir))));
}

// ---- SPEC-001-01-1(@atdd_SPEC-001-01-1) ----

Given(literal('feature flag 設定に BLUE_MODE=foreground, GREEN_MODE=background が定義されている'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background');
});

When(literal('ジョブスケジューラが facade を起動する'), function () {
  h.runFacade(this, ['JOB001']);
});

Then(literal('blue が foreground、green が background として起動される'), function () {
  h.assertExit(this, 0);
  assert.equal(singleInvocation(this, 'blue'), `--run-id ${this.runId} --job-id JOB001 --role blue --mode foreground --`);
  assert.equal(singleInvocation(this, 'green'), `--run-id ${this.runId} --job-id JOB001 --role green --mode background --`);
});

// ---- SPEC-001-01-2(@atdd_SPEC-001-01-2) ----

Given(literal('slot の実行モードが off である'), function () {
  // off にする slot は green(blue は foreground)。起動されないことを観測するため、green にもテスト用 runner を割り当てる
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=off');
  this.offSlot = 'green';
});

When(literal('facade を起動する'), function () {
  h.runFacade(this, ['JOB001']);
});

Then(literal('その slot の runner は起動されない'), function () {
  h.assertExit(this, 0);
  singleInvocation(this, 'blue');
  assert.deepEqual(h.invocations(h.runnerOf(this, this.offSlot)), [], `${this.offSlot} runner must not be started\n${h.dump(this)}`);
  assert.ok(!fs.existsSync(slotDir(this, this.offSlot)), `${this.offSlot}/ must not be created`);
});

// ---- SPEC-001-01-3(@atdd_SPEC-001-01-3) ----

Given(literal('確報クロスチェックの制御設定は feature flag に含まれない'), function () {
  // 有効な並行稼働の設定を補う。「起動しない」は、配置ディレクトリと PATH に置いた記録用の final-crosscheck-runner.sh の
  // 起動記録が無いことで見る(issue「仕様に書かれていない前提」)
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background');
  assert.deepEqual(Object.keys(this.flags).filter((key) => key.startsWith('FINAL')), []);
  this.finalRunnerLog = path.join(this.root, 'final-crosscheck-runner.invoked');
  const recorder = `#!/usr/bin/env bash\nprintf "%s\\n" "$*" >>'${this.finalRunnerLog}'\nexit 0\n`;
  for (const dir of [this.sandbox(h.SPEC_HOME), this.sandbox(`${h.SPEC_HOME}/bin`), path.join(this.root, 'fakebin')]) {
    h.writeExecutable(path.join(dir, 'final-crosscheck-runner.sh'), recorder);
  }
});

Then(literal('facade は確報クロスチェックを起動しない'), function () {
  h.assertExit(this, 0);
  singleInvocation(this, 'blue');
  singleInvocation(this, 'green');
  assert.ok(!fs.existsSync(this.finalRunnerLog), 'final-crosscheck-runner.sh must not be started');
});

// ---- SPEC-001-02-1(@atdd_SPEC-001-02-1) ----

Given(literal('BLUE_MODE=foreground かつ GREEN_MODE=foreground'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=foreground');
});

Then(literal('どの slot も起動せずエラー終了する'), function () {
  h.assertExit(this, 2);
  h.assertStderrIncludes(this, 'error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground');
  assert.equal(Object.keys(this.fhRunners).length, 2, 'test runners should be assigned to both slots');
  h.assertNoInvocations(this);
  assert.deepEqual(this.runIds, [], 'no run directory expected');
});

// ---- SPEC-001-04-1(@atdd_SPEC-001-04-1) ----

Given(literal('BLUE_RUNNER / GREEN_RUNNER に実体スクリプトのパスが設定されている'), function () {
  // 既定の名前ではない実体(名前から slot も実装も読み取れないパス)を割り当てる
  h.setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2');
  this.flags.BLUE_RUNNER = h.writeRunnerAt(this, this.sandbox('/opt/relay-gate/runners/legacy-host-launcher.sh'));
  this.flags.GREEN_RUNNER = h.writeRunnerAt(this, this.sandbox('/opt/relay-gate/runners/container-launcher.sh'));
});

When(literal('facade が slot を起動する'), function () {
  h.runFacade(this, ['JOB001', 'p1']);
});

Then(literal('facade は実装固有の起動方式を判断せず、設定された runner を起動する'), function () {
  h.assertExit(this, 0);
  // どちらの runner も、同じ runner IF の引数だけで 1 回ずつ起動される(実体ごとの引数の違いが無い)
  assert.deepEqual(h.startedInvocations(this.flags.BLUE_RUNNER), [`--run-id ${this.runId} --job-id JOB001 --role blue --mode foreground -- p1`]);
  assert.deepEqual(h.startedInvocations(this.flags.GREEN_RUNNER), [`--run-id ${this.runId} --job-id JOB001 --role green --mode background -- p1`]);
});

// ---- SPEC-001-04-2(@atdd_SPEC-001-04-2) ----
// 判定のしかた(docs/impl/latest/09730858/issues/20261118_091109_cross-uc-scenarios.md の 6):
//   (a) 書き換えの前後で facade の実体(facade/bin・src・lib・runners)と、feature-flag.env 以外の設定ファイルの内容が同じ
//   (b) 書き換え後の facade.sh の起動で、差し替えた runner が runner IF で起動される

Given(literal('green runner を次世代実装用に差し替える'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background');
  for (const slot of ['blue', 'green']) {
    fs.writeFileSync(path.join(this.configDir, `${slot}-job-map.csv`), `${JOB_MAP_HEADER}\n${JOB001_ROW}\n`);
  }
  this.previousGreenRunner = this.flags.GREEN_RUNNER;
  this.nextGreenRunner = h.writeRunnerAt(this, this.sandbox('/opt/relay-gate/runners/green-next-runner.sh'));
  h.flushFlags(this);
  this.facadeHashesBefore = facadeFileHashes();
  this.otherConfigBefore = hashFiles(listFiles(this.configDir).filter((file) => file !== this.envPath));
});

When(literal('feature flag と runner 設定だけを変更する'), function () {
  // 変更するのは feature-flag.env の GREEN_RUNNER(runner の割当)と GREEN_IMPL(実装版)だけ
  this.flags.GREEN_RUNNER = this.nextGreenRunner;
  this.flags.GREEN_IMPL = 'v3';
});

Then(literal('facade と比較規約を変更せずに並行稼働できる'), function () {
  h.runFacade(this, ['JOB001']);
  h.assertExit(this, 0);
  // (b) blue は foreground、差し替えた green は background で、runner IF で起動される。差し替え前の green の runner は起動されない
  assert.deepEqual(h.startedInvocations(h.runnerOf(this, 'blue')), [`--run-id ${this.runId} --job-id JOB001 --role blue --mode foreground --`]);
  assert.deepEqual(h.startedInvocations(this.nextGreenRunner), [`--run-id ${this.runId} --job-id JOB001 --role green --mode background --`]);
  assert.equal(h.recordedEnv(this.nextGreenRunner).GREEN_IMPL, 'v3');
  assert.deepEqual(h.invocations(this.previousGreenRunner), []);
  // (a) facade の実体と、feature-flag.env 以外の設定ファイルは変わっていない
  assert.deepEqual(facadeFileHashes(), this.facadeHashesBefore, 'facade files must not be changed');
  assert.deepEqual(hashFiles(listFiles(this.configDir).filter((file) => file !== this.envPath)), this.otherConfigBefore, 'other config files must not be changed');
});

// ---- SPEC-002-01-1(@atdd_SPEC-002-01-1) ----

Given(literal('BLUE_MODE=foreground, GREEN_MODE=background'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background');
  // 「blue の終了のみを待機する」を確かめるため、background の green は facade の終了後も動き続けるテスト用 runner にする
  h.setSlotBehavior(this, 'green', h.HOLD);
});

Then(literal('green が先に background 起動され、その後 blue が起動され、facade は blue の終了のみを待機する'), function () {
  assert.equal(singleInvocation(this, 'green'), `--run-id ${this.runId} --job-id JOB001 --role green --mode background --`);
  assert.equal(singleInvocation(this, 'blue'), `--run-id ${this.runId} --job-id JOB001 --role blue --mode foreground --`);
  h.assertStartedInOrder(this, { slot: 'green', mode: 'background' }, { slot: 'blue', mode: 'foreground' });
  h.assertWaitedOnly(this, 'blue', 'green');
});

// ---- SPEC-002-01-2(@atdd_SPEC-002-01-2) ----
// facade.sh を終了を待たずに起動し、foreground の runner が動いている間に両 slot の runner のプロセスを確かめる。
// 「長時間」は、確かめる間だけ動き続ければ足りるため、foreground のテスト用 runner は 3 秒待ってから結果を書く

Given(literal('foreground slot が長時間実行中'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background');
  h.setSlotBehavior(this, 'blue', { kind: 'result', code: 0, delaySec: 3 });
  h.setSlotBehavior(this, 'green', h.HOLD);
  h.startFacade(this, ['JOB001']);
  h.waitForFile(`${h.runnerOf(this, 'blue')}.ready`);
});

When(literal('実行状況を確認する'), function () {
  const blue = h.runnerOf(this, 'blue');
  const green = h.runnerOf(this, 'green');
  h.waitForFile(`${green}.ready`);
  this.observed = {
    facadeRunning: this.fhFacade.child.exitCode === null,
    blueRunning: h.processAlive(h.runnerPid(blue)) && !fs.existsSync(`${blue}.finished`),
    greenRunning: h.processAlive(h.runnerPid(green)),
  };
});

Then(literal('background slot は foreground と同時に実行されている'), { timeout: 30000 }, async function () {
  assert.deepEqual(this.observed, { facadeRunning: true, blueRunning: true, greenRunning: true });
  // foreground が終わると facade は終わる(background は動いたまま)
  const status = await this.fhFacade.exited;
  assert.equal(status, 0, 'facade exit code');
  assert.ok(h.processAlive(h.runnerPid(h.runnerOf(this, 'green'))), 'green runner should still be running after facade exit');
});

// ---- SPEC-005-06-3(@atdd_SPEC-005-06-3) ----
// 「設定所有区分」の照合先: CLI 契約 config_files(設定ファイルごとの owner。設定所有区分の正本の写し)

Given(literal('設定所有区分'), function () {
  const contract = YAML.parse(fs.readFileSync(CLI_CONTRACT, 'utf8'));
  this.configFiles = contract.config_files || [];
  assert.ok(this.configFiles.length > 0, 'CLI contract should define config_files');
});

When(literal('速報クロスチェック設定の所有者を確認する'), function () {
  const entries = this.configFiles.filter((entry) => entry.file === 'rapid-crosscheck.env');
  assert.equal(entries.length, 1, 'CLI contract should define exactly one rapid-crosscheck.env');
  this.rapidOwner = String(entries[0].owner);
});

Then(literal('基盤適用設計者である'), function () {
  assert.ok(this.rapidOwner.startsWith('基盤適用設計者'), `owner: ${this.rapidOwner}`);
  assert.ok(this.rapidOwner.includes('設定所有区分: 速報クロスチェック設定'), `owner: ${this.rapidOwner}`);
  assert.ok(!this.rapidOwner.includes('運用者'), `owner should be only the platform designer: ${this.rapidOwner}`);
});

// ---- SPEC-005-06-4(@atdd_SPEC-005-06-4) ----

Given(literal('速報クロスチェック設定'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background');
  fs.writeFileSync(path.join(this.configDir, 'rapid-crosscheck.env'), 'RAPID_DB_CONN_REF=mgmt-db\nRAPID_LEASE_SEC=600\nRAPID_POLL_INTERVAL_SEC=30\n');
});

When(literal('内容を確認する'), function () {
  this.rapidEnvText = fs.readFileSync(path.join(this.configDir, 'rapid-crosscheck.env'), 'utf8');
  // この設定で facade が管理 DB に接続できること(参照名だけで足りること)も確かめる
  h.runFacade(this, ['JOB001']);
});

Then(literal('認証情報の値は含まれず管理 DB 接続の参照名だけがある'), function () {
  const settings = h.parseEnv(this.rapidEnvText);
  assert.deepEqual(Object.keys(settings).sort(), ['RAPID_DB_CONN_REF', 'RAPID_LEASE_SEC', 'RAPID_POLL_INTERVAL_SEC']);
  assert.match(settings.RAPID_DB_CONN_REF, /^[A-Za-z0-9_-]+$/);
  for (const pattern of [/pass(word)?/i, /secret/i, /token/i, /:\/\//, /host=/i, /dbname=/i, /user=/i]) {
    assert.ok(!pattern.test(this.rapidEnvText), `rapid-crosscheck.env must not contain ${pattern}`);
  }
  for (const value of [this.db.host, this.db.dbname]) {
    assert.ok(!this.rapidEnvText.includes(value), `rapid-crosscheck.env must not contain ${value}`);
  }
  // 参照名だけの設定で facade は管理 DB に接続し、解決した接続情報の値を実行ログにも stderr にも出さない
  h.assertExit(this, 0);
  assert.deepEqual(h.dbRows(this, 'SELECT run_id FROM parallel_runs'), [h.runDir(this) && this.runId]);
  for (const secret of [this.db.host, this.db.dbname, 'host=', 'dbname=']) {
    assert.ok(!h.executionLog(this).includes(secret), `execution log must not include ${secret}`);
    assert.ok(!this.result.stderr.includes(secret), `stderr must not include ${secret}`);
  }
});

// ---- SPEC-011-01-1(@atdd_SPEC-011-01-1) ----

Given(literal('RAPID_CROSSCHECK_MODE=background で run を開始'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background');
  h.runFacade(this, ['JOB001']);
  h.assertExit(this, 0);
});

When(literal('parallel_run を確認する'), function () {
  this.parallelRuns = h.dbRows(this, 'SELECT run_id, execution_spec_uri FROM parallel_runs');
});

Then(literal('execution_spec_uri が facade/<run_id>/execution-spec.json を指す'), function () {
  h.runDir(this);
  assert.deepEqual(this.parallelRuns, [`${this.runId}|${this.artifactRoot}/facade/${this.runId}/execution-spec.json`]);
});

// ---- SPEC-011-04-1(@atdd_SPEC-011-04-1) ----
// uc-map では UC「execution-spec.json を確定保存する」(43850d68)の atdd_scenarios にも載っている。step はこの UC が定義する

Given(literal('run を開始した'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background');
  h.runFacade(this, ['JOB001']);
  h.assertExit(this, 0);
});

When(literal('成果物ディレクトリ名と管理 DB の parallel_run.run_id を確認する'), function () {
  this.artifactDirNames = fs.readdirSync(path.join(this.artifactRoot, 'facade'));
  this.dbRunIds = h.dbRows(this, 'SELECT run_id FROM parallel_runs');
});

Then(literal('同じ値である'), function () {
  assert.equal(this.artifactDirNames.length, 1);
  assert.match(this.artifactDirNames[0], h.RUN_ID_PATTERN);
  assert.deepEqual(this.dbRunIds, this.artifactDirNames);
});

// ---- SPEC-011-04-2(@atdd_SPEC-011-04-2) ----

Given(literal('RAPID_CROSSCHECK_MODE=off(管理 DB なし)'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off');
  assert.equal(this.db, undefined, 'management db must not be prepared');
  assert.ok(!fs.existsSync(path.join(this.configDir, 'rapid-crosscheck.env')));
});

When(literal('facade が run を開始する'), function () {
  h.runFacade(this, ['JOB001']);
});

Then(literal('facade 単独で run_id を発行できる'), function () {
  h.assertExit(this, 0);
  assert.ok(fs.statSync(h.runDir(this)).isDirectory());
  assert.match(this.runId, h.RUN_ID_PATTERN);
  // 発行した run_id は runner へ渡っている。RDB クライアント CLI(PATH の先頭の記録用ラッパー)は 1 回も呼ばれていない
  assert.ok(singleInvocation(this, 'blue').startsWith(`--run-id ${this.runId} `));
  assert.ok(!h.psqlCalled(this), 'RDB client must not be called');
});

// ---- SPEC-011-04-3(@atdd_SPEC-011-04-3) ----
// ローカルタイムゾーンであることを見るため、UTC と日付・時刻の表記がずれるタイムゾーン(Asia/Tokyo)で、
// 時刻を固定(RELAY_GATE_NOW=2026-08-30T11:30:00Z。ローカルでは 20:30:00)して発行する(SPEC-011-04 の例 20260830T203000-JOB001-…)

Given(literal('発行された run_id'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off');
  this.extraEnv = { TZ: 'Asia/Tokyo', RELAY_GATE_NOW: '2026-08-30T11:30:00Z' };
  h.runFacade(this, ['JOB001']);
  h.assertExit(this, 0);
});

When(literal('形式を検証する'), function () {
  h.runDir(this);
  this.issuedRunId = this.runId;
});

Then(literal('yyyymmddThhmmss-{job_id}-8 桁 hex に一致し、時刻部はローカルタイムゾーンで末尾に Z を含まない'), function () {
  assert.match(this.issuedRunId, /^[0-9]{8}T[0-9]{6}-JOB001-[0-9a-f]{8}$/);
  // 時刻部はローカル(Asia/Tokyo)の 20:30:00。UTC の 11:30:00 ではなく、タイムゾーン指示子も付かない
  assert.match(this.issuedRunId, /^20260830T203000-JOB001-[0-9a-f]{8}$/);
  assert.ok(!this.issuedRunId.includes('Z'), `run_id must not carry a zone designator: ${this.issuedRunId}`);
});
