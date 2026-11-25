// UC BDD(②)step definition。uc_id=09730858 / branch_slug=select-slot-mode-and-launch-runners(S6 uc-bdd で実装)。
// source: docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/spec.md#E2E完了条件(BDD)
// step 文言は feature から転写したリテラルを正規表現で完全一致させる(S2 skeleton の方式を踏襲)。
// このファイルが定義するのは、他 UC の step ファイルに定義の無い step だけ(同じ文言を再定義すると ambiguous になる)。
// World(root / configDir / sandbox() / unsandbox())と Before / After は configure-feature-flags.steps.js のものを使う。
// このファイルの After / AfterAll は、Scenario が World に残した後始末の対象(長く動くテスト用 runner の PID、一時 PostgreSQL)が
// あるときだけ働く(他の feature の Scenario では何もしない)。
//
// ハーネス(support/facade-harness.js。ATDD の step と共有):
//   - facade/bin/facade.sh を実プロセスとして起動する。/etc/relay-gate・/opt/relay-gate・/work は World の sandbox() で一時ディレクトリの下に置く
//   - runner の振る舞い(started-at.txt / exitcode.txt の出力、長時間の実行)が要る Scenario は、一時ディレクトリに置く実スクリプトの
//     テスト用 runner を使う(暫定注入・契約確定後に削除。根拠: docs/impl/latest/09730858/issues/20261118_091109_cross-uc-scenarios.md の 1〜3)
//   - 管理 DB は initdb + pg_ctl の一時 PostgreSQL。参照名 mgmt-db は一時の pg_service.conf で結び付ける
//     (暫定注入・契約確定後に削除。根拠: 前提 A-001。docs/impl/latest/09730858/stages/attempt-3/S4_tier-impl.tier-facade.assumptions.yaml)
//   - 仕様の Given が要点(mode など)だけを書いている Scenario は、検証を通る値(実装版・テスト用 runner・速報の runner / worker・
//     rapid-crosscheck.env・起動している管理 DB)を補う(同 issue「仕様に書かれていない前提(step が補うもの)」)
// 標準の slot runner を名指しする Scenario(SPEC-004-01)の扱いは、該当の step のコメントを参照(同 issue の 4。オーケストレータの決定)。
// リポジトリの中にはファイルを書かない。
'use strict';
const { Given, Then, When, After, AfterAll } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const h = require('./support/facade-harness');

const { literal } = h;

const JOB_MAP_HEADER_LOCAL = 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes';
const JOB_MAP_HEADER_7 = 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes';
const JOB001_ROW_LOCAL = 'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",60';
const SPEC_CONFIG_DIR = '/etc/relay-gate';
const SPEC_WORK_DIR = '/work';
const SPEC_STANDARD_RUNNER = '/opt/relay-gate/runners/standard-runner.sh';
// 配置ディレクトリの複製に写すディレクトリ(標準の slot runner の入口 runners/ と lib/、入口が読む本体の src/)
const DEPLOY_DIRS = ['runners', 'lib', 'src'];

After(function () {
  h.cleanup(this);
});

AfterAll(function () {
  h.stopDatabase();
});

// mode などの要点だけを書いた Given: 書かれた値を載せ、検証を通る値を補う。速報クロスチェックが off 以外なら管理 DB を用意する
function defineFlags(world, text) {
  h.setFlags(world, text);
  h.supplementFlags(world);
  if (world.flags.RAPID_CROSSCHECK_MODE && world.flags.RAPID_CROSSCHECK_MODE !== 'off') {
    h.startManagementDb(world);
  }
}

function foregroundSlot(world) {
  return world.flags.BLUE_MODE === 'foreground' ? 'blue' : 'green';
}

function slotDir(world, slot) {
  return path.join(h.runDir(world), slot);
}

function writeJobMap(world, slot, header, rows) {
  fs.writeFileSync(path.join(world.configDir, `${slot}-job-map.csv`), [header, ...rows].join('\n') + '\n');
}

function singleInvocation(world, slot) {
  const calls = h.startedInvocations(h.runnerOf(world, slot));
  assert.equal(calls.length, 1, `${slot} runner should be started once: ${calls}\n${h.dump(world)}`);
  return calls[0];
}

function assertStartedAt(world, slot) {
  h.startedInvocations(h.runnerOf(world, slot));
  assert.ok(fs.existsSync(path.join(slotDir(world, slot), 'started-at.txt')), `${slot}/started-at.txt should exist\n${h.dump(world)}`);
}

function assertNoRows(world) {
  for (const table of ['parallel_runs', 'slot_executions', 'rapid_runs']) {
    assert.deepEqual(h.dbRows(world, `SELECT count(*) FROM ${table}`), ['0'], `${table} should have no rows`);
  }
}

// ---- 並行稼働モードで blue foreground と green background を起動する(SPEC-001-01) ----

Given(literal('feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background BLUE_IMPL=v1 GREEN_IMPL=v2 BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=/opt/relay-gate/rapid-crosscheck-worker.sh が定義されている'), function () {
  defineFlags(
    this,
    'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background BLUE_IMPL=v1 GREEN_IMPL=v2 BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=/opt/relay-gate/rapid-crosscheck-worker.sh',
  );
  // 「facade は blue の PID だけを待機する」を確かめるため、background の green は facade の終了後も動き続けるテスト用 runner にする
  h.setSlotBehavior(this, 'green', h.HOLD);
});

Given(literal('両 slot のジョブマップに job_id=JOB001 の行がある'), function () {
  // runner が実行先を解決するための前提(後続 UC)。facade はジョブマップを検査しない。置くだけ
  writeJobMap(this, 'blue', JOB_MAP_HEADER_LOCAL, [JOB001_ROW_LOCAL]);
  writeJobMap(this, 'green', JOB_MAP_HEADER_LOCAL, [JOB001_ROW_LOCAL]);
});

When(literal('ジョブスケジューラが facade.sh JOB001 20260830 full を実行する'), function () {
  h.runFacade(this, ['JOB001', '20260830', 'full']);
});

Then(literal('green runner が --role green --mode background -- 20260830 full で先に起動される'), function () {
  assert.equal(singleInvocation(this, 'green'), `--run-id ${this.runId} --job-id JOB001 --role green --mode background -- 20260830 full`);
  h.assertStartedInOrder(this, { slot: 'green', mode: 'background' }, { slot: 'blue', mode: 'foreground' });
});

Then(literal('blue runner が --role blue --mode foreground -- 20260830 full でその後に起動される'), function () {
  assert.equal(singleInvocation(this, 'blue'), `--run-id ${this.runId} --job-id JOB001 --role blue --mode foreground -- 20260830 full`);
  h.assertStartedInOrder(this, { slot: 'green', mode: 'background' }, { slot: 'blue', mode: 'foreground' });
});

Then(literal('各 runner の環境変数に RAPID_CROSSCHECK_MODE=background RAPID_CROSSCHECK_RUNNER=/opt/relay-gate/rapid-crosscheck-runner.sh と自 slot の BLUE_IMPL=v1 または GREEN_IMPL=v2 が設定されている'), function () {
  const blue = h.recordedEnv(h.runnerOf(this, 'blue'));
  const green = h.recordedEnv(h.runnerOf(this, 'green'));
  for (const env of [blue, green]) {
    assert.equal(env.RAPID_CROSSCHECK_MODE, 'background');
    assert.equal(this.unsandbox(env.RAPID_CROSSCHECK_RUNNER || ''), '/opt/relay-gate/rapid-crosscheck-runner.sh');
  }
  assert.equal(blue.BLUE_IMPL, 'v1');
  assert.equal(blue.GREEN_IMPL, undefined, 'blue runner must not receive GREEN_IMPL');
  assert.equal(green.GREEN_IMPL, 'v2');
  assert.equal(green.BLUE_IMPL, undefined, 'green runner must not receive BLUE_IMPL');
});

Then(literal('facade は blue の PID だけを待機する'), function () {
  h.assertWaitedOnly(this, 'blue', 'green');
});

Then(literal('parallel_runs に run_id の行が status=RUNNING job_id=JOB001 parameters=["20260830","full"] で存在する'), function () {
  const rows = h.dbRows(this, 'SELECT run_id, status, job_id FROM parallel_runs');
  assert.deepEqual(rows, [`${h.runDir(this) && this.runId}|RUNNING|JOB001`]);
  const parameters = h.dbRows(this, 'SELECT parameters FROM parallel_runs');
  assert.equal(parameters.length, 1);
  assert.deepEqual(JSON.parse(parameters[0]), ['20260830', 'full']);
});

// ---- background を先に起動し foreground だけを待機する(SPEC-002-01) ----

Given(literal('feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background が定義されている'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background');
});

Given(literal('green の実装スクリプトは 600 秒、blue の実装スクリプトは 5 秒で終了する'), function () {
  // 実装スクリプトを起動するのは runner(後続 UC)。この UC ではテスト用 runner が同じ時間だけ待つ。
  // 600 秒待つ green は Scenario の終了時に After が止める
  h.setSlotBehavior(this, 'green', { kind: 'hold', sec: 600 });
  h.setSlotBehavior(this, 'blue', { kind: 'result', code: 0, delaySec: 5 });
});

When(literal('ジョブスケジューラが facade.sh JOB001 を実行する'), function () {
  h.runFacade(this, ['JOB001']);
});

Then(literal('facade は blue の終了後 10 秒以内に終了する'), function () {
  // 仕様のシナリオが定める振る舞い(600 秒の green を待たない)の確認。性能の検査ではない
  h.assertExit(this, 0);
  const blueFinished = `${h.runnerOf(this, 'blue')}.finished`;
  assert.ok(fs.existsSync(blueFinished), `blue runner should have finished\n${h.dump(this)}`);
  const elapsedMs = this.facadeEndedAtMs - fs.statSync(blueFinished).mtimeMs;
  assert.ok(elapsedMs <= 10000, `facade ended ${elapsedMs} ms after blue finished (should be within 10 seconds)`);
});

Then(literal('facade 終了時点で facade/<run_id>/green/exitcode.txt は存在しない(green は実行中)'), function () {
  assert.ok(Array.isArray(this.filesAtFacadeExit.green), `green/ should exist when facade exits\n${h.dump(this)}`);
  assert.ok(!this.filesAtFacadeExit.green.includes('exitcode.txt'), `green/exitcode.txt must not exist when facade exits: ${this.filesAtFacadeExit.green}`);
  const pid = h.runnerPid(h.runnerOf(this, 'green'));
  assert.ok(h.processAlive(pid), `green runner (pid ${pid}) should still be running`);
});

Then(literal('実行ログに "slot started slot=green mode=background" が "slot started slot=blue mode=foreground" より前に記録される'), function () {
  const log = h.executionLog(this);
  const green = log.indexOf('slot started slot=green mode=background');
  const blue = log.indexOf('slot started slot=blue mode=foreground');
  assert.ok(green >= 0 && blue >= 0 && green < blue, `green must be logged before blue\n${log}`);
});

// ---- 新実装の単独本番モードでは green だけを起動し管理 DB に触れない(SPEC-001-03) ----

Given(literal('ジョブスケジューラのジョブ定義は並行稼働モードのときと同じ facade.sh JOB001 のままで、変更していない'), function () {
  // ジョブ定義 = When が実行するコマンド(facade.sh JOB001)。並行稼働モードの Scenario と同じ When を使う
  this.jobDefinition = ['facade.sh', 'JOB001'];
});

Given(literal('feature flag に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off が定義されている'), function () {
  defineFlags(this, 'BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off');
});

Given(literal('管理 DB の接続設定が存在しない'), function () {
  assert.equal(this.db, undefined, 'management db must not be prepared');
  assert.equal(this.pgServiceFile, undefined, 'connection service file must not be prepared');
  assert.ok(!fs.existsSync(path.join(this.configDir, 'rapid-crosscheck.env')), 'rapid-crosscheck.env should not exist');
});

Then(literal('blue runner は起動されない'), function () {
  assert.deepEqual(h.invocations(h.runnerOf(this, 'blue')), [], `blue runner must not be started\n${h.dump(this)}`);
});

Then(literal('green runner が --role green --mode foreground で起動される'), function () {
  assert.equal(singleInvocation(this, 'green'), `--run-id ${this.runId} --job-id JOB001 --role green --mode foreground --`);
});

Then(literal('facade は管理 DB へ接続せず終了する'), function () {
  h.assertExit(this, 0);
  // RDB クライアント CLI(PATH の先頭に置いた記録用ラッパー)が 1 回も呼ばれていない
  assert.ok(!h.psqlCalled(this), `RDB client must not be called\n${fs.existsSync(this.psqlLog) ? fs.readFileSync(this.psqlLog, 'utf8') : ''}`);
});

Then(literal('facade/<run_id>/green/ に started-at.txt が存在する'), function () {
  assertStartedAt(this, 'green');
});

// ---- 次世代並行稼働モードでは blue background と green foreground を起動する(SPEC-001-03) ----

Given(literal('feature flag に BLUE_MODE=background GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=background が定義されている'), function () {
  defineFlags(this, 'BLUE_MODE=background GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=background');
  // 「facade は green の PID だけを待機する」を確かめるため、background の blue は facade の終了後も動き続けるテスト用 runner にする
  h.setSlotBehavior(this, 'blue', h.HOLD);
});

Then(literal('blue runner が --mode background で先に起動される'), function () {
  assert.equal(singleInvocation(this, 'blue'), `--run-id ${this.runId} --job-id JOB001 --role blue --mode background --`);
  h.assertStartedInOrder(this, { slot: 'blue', mode: 'background' }, { slot: 'green', mode: 'foreground' });
});

Then(literal('green runner が --mode foreground でその後に起動される'), function () {
  assert.equal(singleInvocation(this, 'green'), `--run-id ${this.runId} --job-id JOB001 --role green --mode foreground --`);
  h.assertStartedInOrder(this, { slot: 'blue', mode: 'background' }, { slot: 'green', mode: 'foreground' });
});

Then(literal('facade は green の PID だけを待機する'), function () {
  h.assertWaitedOnly(this, 'green', 'blue');
});

// ---- off の slot は起動しない(SPEC-001-01) ----

Given(literal('feature flag に BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=off が定義されている'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=off');
});

Then(literal('green runner は起動されない'), function () {
  h.assertExit(this, 0);
  assert.deepEqual(h.invocations(h.runnerOf(this, 'green')), [], `green runner must not be started\n${h.dump(this)}`);
});

Then(literal('facade/<run_id>/green/ ディレクトリは作成されない'), function () {
  assert.ok(fs.statSync(slotDir(this, 'blue')).isDirectory(), 'blue/ should exist');
  assert.ok(!fs.existsSync(slotDir(this, 'green')), 'green/ must not be created');
});

// ---- RAPID_CROSSCHECK_MODE=background では parallel_run を STARTED から RUNNING にする(SPEC-011-01) ----

Then(literal('parallel_runs に status=STARTED の行が INSERT された後に status=RUNNING へ更新される'), function () {
  h.assertExit(this, 0);
  // 管理 DB の側で記録した履歴(テスト用のトリガ)で、INSERT と UPDATE の順を見る
  const history = h.dbRows(this, 'SELECT op, run_id, status FROM test_parallel_run_status_history ORDER BY seq');
  assert.deepEqual(history, [`INSERT|${this.runId}|STARTED`, `UPDATE|${this.runId}|RUNNING`]);
  assert.deepEqual(h.dbRows(this, 'SELECT run_id, status FROM parallel_runs'), [`${this.runId}|RUNNING`]);
});

Then(literal('execution_spec_uri が <RELAY_GATE_ARTIFACT_ROOT>/facade/<run_id>/execution-spec.json を指す'), function () {
  assert.deepEqual(h.dbRows(this, 'SELECT execution_spec_uri FROM parallel_runs'), [`${this.artifactRoot}/facade/${this.runId}/execution-spec.json`]);
});

Then(literal('rapid_runs に run_id の行が completion_status=PENDING で存在する'), function () {
  assert.deepEqual(h.dbRows(this, 'SELECT run_id, completion_status FROM rapid_runs'), [`${h.runDir(this) && this.runId}|PENDING`]);
});

// ---- RAPID_CROSSCHECK_MODE=off では管理 DB に触れない(SPEC-005-04) ----

Given(literal('feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off が定義されている'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off');
});

Then(literal('blue と green の runner が起動される'), function () {
  singleInvocation(this, 'blue');
  singleInvocation(this, 'green');
});

Then(literal('各 runner の環境変数に RAPID_CROSSCHECK_MODE=off が設定され RAPID_CROSSCHECK_RUNNER は設定されない'), function () {
  for (const slot of ['blue', 'green']) {
    const env = h.recordedEnv(h.runnerOf(this, slot));
    assert.equal(env.RAPID_CROSSCHECK_MODE, 'off', `${slot} RAPID_CROSSCHECK_MODE`);
    assert.equal(env.RAPID_CROSSCHECK_RUNNER, undefined, `${slot} must not receive RAPID_CROSSCHECK_RUNNER`);
  }
});

Then(literal('parallel_runs / slot_executions / rapid_runs に行は作成されない'), function () {
  // 管理 DB の接続設定が無い Scenario。RDB クライアント CLI が 1 回も呼ばれていないことで、行が作られていないことを見る
  assert.equal(this.db, undefined);
  assert.ok(!h.psqlCalled(this), 'RDB client must not be called');
});

Then(literal('facade 単独で発行した run_id 形式の成果物ディレクトリ facade/<run_id>/ が作成される'), function () {
  assert.ok(fs.statSync(h.runDir(this)).isDirectory());
  assert.match(this.runId, h.RUN_ID_PATTERN);
});

// ---- RAPID_CROSSCHECK_MODE=foreground でも background と同じく parallel_run を作成する(SPEC-005-04) ----

Given(literal('feature flag に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=foreground が定義されている'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=foreground');
});

Then(literal('parallel_runs に run_id の行が status=RUNNING で存在する'), function () {
  h.assertExit(this, 0);
  assert.deepEqual(h.dbRows(this, 'SELECT run_id, status FROM parallel_runs'), [`${h.runDir(this) && this.runId}|RUNNING`]);
});

Then(literal('各 runner の環境変数に RAPID_CROSSCHECK_MODE=foreground と RAPID_CROSSCHECK_RUNNER が設定されている'), function () {
  for (const slot of ['blue', 'green']) {
    const env = h.recordedEnv(h.runnerOf(this, slot));
    assert.equal(env.RAPID_CROSSCHECK_MODE, 'foreground', `${slot} RAPID_CROSSCHECK_MODE`);
    assert.equal(env.RAPID_CROSSCHECK_RUNNER, this.flags.RAPID_CROSSCHECK_RUNNER, `${slot} RAPID_CROSSCHECK_RUNNER`);
  }
});

// ---- 速報クロスチェック設定には管理 DB 接続の参照名だけがあり認証情報の値は含まれない(SPEC-005-06) ----

Given(literal('速報クロスチェック設定 <RELAY_GATE_CONFIG_DIR>/rapid-crosscheck.env に RAPID_DB_CONN_REF=mgmt-db RAPID_LEASE_SEC=600 RAPID_POLL_INTERVAL_SEC=30 が定義されている'), function () {
  fs.writeFileSync(path.join(this.configDir, 'rapid-crosscheck.env'), 'RAPID_DB_CONN_REF=mgmt-db\nRAPID_LEASE_SEC=600\nRAPID_POLL_INTERVAL_SEC=30\n');
});

When(literal('運用者が速報クロスチェック設定の内容を確認し、ジョブスケジューラが facade.sh JOB001 を実行する'), function () {
  this.rapidEnvText = fs.readFileSync(path.join(this.configDir, 'rapid-crosscheck.env'), 'utf8');
  h.runFacade(this, ['JOB001']);
});

Then(literal('rapid-crosscheck.env にはパスワード・接続文字列などの認証情報の値は無く、管理 DB 接続の参照名 RAPID_DB_CONN_REF だけがある'), function () {
  const settings = h.parseEnv(this.rapidEnvText);
  assert.deepEqual(Object.keys(settings).sort(), ['RAPID_DB_CONN_REF', 'RAPID_LEASE_SEC', 'RAPID_POLL_INTERVAL_SEC']);
  // 管理 DB 接続に関するキーは参照名だけで、値は名前(接続文字列・パスワードの形ではない)
  assert.match(settings.RAPID_DB_CONN_REF, /^[A-Za-z0-9_-]+$/);
  assert.equal(settings.RAPID_DB_CONN_REF, h.CONN_REF);
  for (const pattern of [/pass(word)?/i, /secret/i, /token/i, /:\/\//, /host=/i, /dbname=/i, /user=/i]) {
    assert.ok(!pattern.test(this.rapidEnvText), `rapid-crosscheck.env must not contain ${pattern}`);
  }
  // 参照名から解決した接続先(テストの pg_service.conf に書いた値)も設定には無い
  for (const value of [this.db.host, this.db.dbname]) {
    assert.ok(!this.rapidEnvText.includes(value), `rapid-crosscheck.env must not contain ${value}`);
  }
});

Then(literal('facade は参照名 mgmt-db で管理 DB に接続し parallel_runs に run_id の行を作成する'), function () {
  h.assertExit(this, 0);
  // 参照名 mgmt-db だけを結び付けた接続設定の先のデータベースに、run_id の行がある
  assert.deepEqual(h.dbRows(this, 'SELECT run_id FROM parallel_runs'), [h.runDir(this) && this.runId]);
  // RDB クライアント CLI へ渡ったのは参照名で、接続先の値(ホスト・データベース名)ではない
  const record = fs.readFileSync(this.psqlLog, 'utf8');
  const argLines = record.split('\n').filter((l) => l.startsWith('args:'));
  assert.ok(argLines.length > 0, 'RDB client should be called');
  for (const line of argLines) {
    assert.ok(line.includes(h.CONN_REF), `RDB client args should carry the reference name: ${line}`);
    for (const value of [this.db.host, this.db.dbname]) {
      assert.ok(!line.includes(value), `RDB client args must not carry resolved connection values: ${line}`);
    }
  }
});

Then(literal('実行ログにも stderr にも参照名から解決した接続情報の値は出ない'), function () {
  const log = h.executionLog(this);
  assert.ok(log.length > 0, 'execution log should exist');
  for (const secret of [this.db.host, this.db.dbname, 'host=', 'dbname=']) {
    assert.ok(!log.includes(secret), `execution log must not include ${secret}`);
    assert.ok(!this.result.stderr.includes(secret), `stderr must not include ${secret}`);
  }
});

// ---- RAPID_CROSSCHECK_MODE=off では速報クロスチェック設定が存在しなくても slot 実行できる(SPEC-005-06) ----

Given(literal('<RELAY_GATE_CONFIG_DIR>/rapid-crosscheck.env が存在しない'), function () {
  assert.ok(!fs.existsSync(path.join(this.configDir, 'rapid-crosscheck.env')), 'rapid-crosscheck.env should not exist');
  // 「終了コードは foreground の exitcode.txt の値である」を 0 以外の値で確かめるため、foreground のテスト用 runner は exitcode.txt に 3 を書く
  h.setSlotBehavior(this, foregroundSlot(this), { kind: 'result', code: 3 });
});

Then(literal('facade は rapid-crosscheck.env を読まず、終了コードは foreground の exitcode.txt の値である'), function () {
  assert.ok(!fs.existsSync(path.join(this.configDir, 'rapid-crosscheck.env')), 'rapid-crosscheck.env should not exist');
  assert.deepEqual(h.stderrLines(this).filter((l) => l.includes('rapid-crosscheck.env')), [], `no diagnostics about rapid-crosscheck.env expected\n${h.dump(this)}`);
  const exitcode = fs.readFileSync(path.join(slotDir(this, foregroundSlot(this)), 'exitcode.txt'), 'utf8').trim();
  assert.equal(exitcode, '3');
  h.assertExit(this, Number(exitcode));
});

Then(literal('facade/<run_id>/blue/ と facade/<run_id>/green/ に started-at.txt が存在する'), function () {
  assertStartedAt(this, 'blue');
  assertStartedAt(this, 'green');
});

// ---- feature flag に書いたジョブマップの場所を自 slot の runner へ渡し、書いていない slot の runner へは既定の場所を渡す ----

Given(literal('設定ファイル置き場が /etc/relay-gate で、/etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2 と、起動引数と環境変数を記録するスタブ runner を指す BLUE_RUNNER / GREEN_RUNNER と、BLUE_JOB_MAP_CSV=./blue-jobs.csv が定義されている'), function () {
  assert.equal(this.configDir, this.sandbox(SPEC_CONFIG_DIR));
  h.setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2');
  h.supplementFlags(this);
  // 値は feature に書かれた相対パスのまま書く(一時ディレクトリの絶対パスへ置き換えない)
  this.flags.BLUE_JOB_MAP_CSV = './blue-jobs.csv';
});

Given(literal('feature flag に GREEN_JOB_MAP_CSV の行は無い'), function () {
  assert.ok(!('GREEN_JOB_MAP_CSV' in this.flags), 'GREEN_JOB_MAP_CSV should not be written');
});

Given(literal('/etc/relay-gate/blue-job-map.csv も存在する'), function () {
  writeJobMap(this, 'blue', JOB_MAP_HEADER_LOCAL, [JOB001_ROW_LOCAL]);
});

When(literal('ジョブスケジューラが /etc/relay-gate とは別の作業ディレクトリ /work で facade.sh JOB001 を実行する'), function () {
  const cwd = this.sandbox(SPEC_WORK_DIR);
  fs.mkdirSync(cwd, { recursive: true });
  h.runFacade(this, ['JOB001'], { cwd });
});

Then(literal('blue runner が --role blue --mode foreground で起動され、環境変数 BLUE_JOB_MAP_CSV=/etc/relay-gate/./blue-jobs.csv が設定されている'), function () {
  assert.equal(singleInvocation(this, 'blue'), `--run-id ${this.runId} --job-id JOB001 --role blue --mode foreground --`);
  assert.equal(this.unsandbox(h.recordedEnv(h.runnerOf(this, 'blue')).BLUE_JOB_MAP_CSV || ''), '/etc/relay-gate/./blue-jobs.csv');
});

Then(literal('green runner が --role green --mode background で起動され、環境変数 GREEN_JOB_MAP_CSV=/etc/relay-gate/green-job-map.csv が設定されている'), function () {
  assert.equal(singleInvocation(this, 'green'), `--run-id ${this.runId} --job-id JOB001 --role green --mode background --`);
  assert.equal(this.unsandbox(h.recordedEnv(h.runnerOf(this, 'green')).GREEN_JOB_MAP_CSV || ''), '/etc/relay-gate/green-job-map.csv');
});

Then(literal('blue runner の環境変数 BLUE_JOB_MAP_CSV は /work/blue-jobs.csv でも /etc/relay-gate/blue-job-map.csv でもない'), function () {
  const value = this.unsandbox(h.recordedEnv(h.runnerOf(this, 'blue')).BLUE_JOB_MAP_CSV || '');
  assert.notEqual(value, '/work/blue-jobs.csv');
  assert.notEqual(value, '/etc/relay-gate/blue-job-map.csv');
});

// ---- 値が空のジョブマップの場所のキーがある slot の runner は固定の名前のジョブマップで実行先を解決する(SPEC-004-01) ----
// この Scenario は標準の slot runner を名指しする。標準の slot runner の中身は機能ごとに順に作る
// (docs/impl/latest/09730858/issues/20261118_091109_cross-uc-scenarios.md の 4。オーケストレータの決定は案 A)。
// UC「ジョブマップで JOB_ID から実行先を解決する」(7c41c7cd)で解決の段ができたので、保留の条件を行ごとに分けた
// (docs/impl/latest/7c41c7cd/issues/20261123_142047_cross-uc-scenarios.md の 6):
//   - Then 1 行目(場所を runner へ渡す): facade の担当。判定する
//   - Then 2 行目(execution-spec.json の中身): execution-spec.json の保存は後続 UC(43850d68)の担当。標準の slot runner が解決に
//     成功し、まだ execution-spec.json を保存せず結果も公開していない間だけ cucumber の skipped を返す。
//     後続 UC が保存を作ると、同じ step がそのまま判定する。解決に失敗しているときは保留にせず失敗させる
//   - Then 3 行目(green の stderr.log): 判定する。固定の名前のジョブマップで解決できたことを実行ログの解決の行で確かめ、
//     stderr.log があれば該当の行が無いことを見る(解決に成功した回は、今は stderr.log を書かない)。
//     cucumber は skipped の step より後ろを実行しないため、2 行目が保留の間は、2 行目の step が保留を返す前にこの判定を済ませる
//     (レポートの上では 3 行目も skipped と表示される)
//   - 標準の slot runner の代わりのスタブは作らない。暫定注入・契約確定後に削除: 標準の slot runner は受け取った環境変数を
//     記録しないため、配置の複製の runners/standard-runner.sh の位置に「起動引数と環境変数を記録してから、本物の標準の slot runner
//     (同じディレクトリの standard-runner.real.sh へ名前を変えた複製)へ同じ引数で処理を渡し、その終了コードを返す」包みを置く(同 issue の 4 の案 A)

const STANDARD_RUNNER_RECORDING_WRAPPER =
  '#!/usr/bin/env bash\n' +
  'real="$(dirname "$0")/standard-runner.real.sh"\n' +
  'if [ "${1:-}" = "--help" ]; then exec "$real" "$@"; fi\n' +
  'role=""; prev=""\n' +
  'for a in "$@"; do if [ "$a" = "--" ]; then break; fi; if [ "$prev" = "--role" ]; then role="$a"; fi; prev="$a"; done\n' +
  'printf "%s\\n" "$*" >"$0.$role.invoked"\n' +
  'env >"$0.$role.env"\n' +
  'status=0\n' +
  '"$real" "$@" || status=$?\n' +
  'printf "%s\\n" "$status" >"$0.$role.status"\n' +
  'exit "$status"\n';

function standardRunnerRecord(world, slot, kind) {
  const file = `${world.sandbox(SPEC_STANDARD_RUNNER)}.${slot}.${kind}`;
  h.waitForFile(`${world.sandbox(SPEC_STANDARD_RUNNER)}.${slot}.status`);
  return fs.readFileSync(file, 'utf8');
}

// green の標準の slot runner が、固定の名前のジョブマップ(host と user が空のローカル実行の行)で解決に成功したか。
// runner の終了を待ってから、実行ログの解決の行(この run_id のもの)を見る
function greenResolvedFromDefaultMap(world) {
  standardRunnerRecord(world, 'green', 'status');
  return h.standardRunnerLogEntries(world, world.runId).includes('INFO job map resolved job_id=JOB001 slot=green host=- map_version=-');
}

// execution-spec.json の保存(後続 UC 43850d68)がまだ無い間か: 解決には成功しているが、execution-spec.json が無く、
// green の結果(exitcode.txt)も公開されていない。解決に失敗した回はこれに当たらない(保留にしない)
function executionSpecNotProvidedYet(world) {
  const resolved = greenResolvedFromDefaultMap(world);
  const specExists = fs.existsSync(path.join(h.runDir(world), 'execution-spec.json'));
  const published = fs.existsSync(path.join(slotDir(world, 'green'), 'exitcode.txt'));
  return resolved && !specExists && !published;
}

// Then 3 行目の判定
function assertGreenStderrLogHasNoJobMapNotFound(world) {
  // 固定の名前のジョブマップで解決できている(runner の終了を待ってから実行ログを見る)
  assert.ok(
    greenResolvedFromDefaultMap(world),
    `green runner should resolve JOB001 from the default job map\n${h.standardRunnerLogEntries(world, world.runId).join('\n')}\n${h.dump(world)}`,
  );
  // 解決に成功した回は、今は stderr.log を書かない(書くのは実装を実行する後続 UC)。あれば該当の行が無いことを見る
  const stderrLog = path.join(slotDir(world, 'green'), 'stderr.log');
  const lines = fs.existsSync(stderrLog) ? fs.readFileSync(stderrLog, 'utf8').split('\n') : [];
  assert.deepEqual(lines.filter((l) => l.startsWith('error: job map not found')), []);
}

Given(literal('設定ファイル置き場が /etc/relay-gate で、/etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2 と、標準の slot runner /opt/relay-gate/runners/standard-runner.sh を指す BLUE_RUNNER / GREEN_RUNNER と、値が空の行 `GREEN_JOB_MAP_CSV=` が定義されている'), function () {
  assert.equal(this.configDir, this.sandbox(SPEC_CONFIG_DIR));
  // relay-gate を一時ディレクトリの /opt/relay-gate に配置する(リンクではなく複製。リポジトリの facade/ には書かない)
  const home = this.sandbox(h.SPEC_HOME);
  for (const dir of DEPLOY_DIRS) {
    fs.cpSync(path.join(h.FACADE_HOME, dir), path.join(home, dir), { recursive: true });
  }
  const standard = this.sandbox(SPEC_STANDARD_RUNNER);
  fs.accessSync(standard, fs.constants.X_OK);
  fs.renameSync(standard, path.join(path.dirname(standard), 'standard-runner.real.sh'));
  h.writeExecutable(standard, STANDARD_RUNNER_RECORDING_WRAPPER);
  h.setFlags(this, `BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=v1 GREEN_IMPL=v2 BLUE_RUNNER=${SPEC_STANDARD_RUNNER} GREEN_RUNNER=${SPEC_STANDARD_RUNNER}`);
  this.flags.GREEN_JOB_MAP_CSV = '';
});

Given(literal('/etc/relay-gate/blue-job-map.csv に JOB001 の行があり、/etc/relay-gate/green-job-map.csv に行 `JOB001,,,/var/app/work,/opt/app/bin/green-job001.sh,[],60` がある(host と user が空のローカル実行の行)'), function () {
  writeJobMap(this, 'blue', JOB_MAP_HEADER_LOCAL, [JOB001_ROW_LOCAL]);
  writeJobMap(this, 'green', JOB_MAP_HEADER_7, ['JOB001,,,/var/app/work,/opt/app/bin/green-job001.sh,[],60']);
});

Then(literal('green runner は環境変数 GREEN_JOB_MAP_CSV=/etc/relay-gate/green-job-map.csv を受け取って起動される(空の値は渡らない)'), function () {
  const invoked = standardRunnerRecord(this, 'green', 'invoked').trim();
  assert.equal(invoked, `--run-id ${h.runDir(this) && this.runId} --job-id JOB001 --role green --mode background --`);
  const env = h.parseEnv(standardRunnerRecord(this, 'green', 'env'));
  assert.equal(this.unsandbox(env.GREEN_JOB_MAP_CSV || ''), '/etc/relay-gate/green-job-map.csv');
});

Then(literal('facade/<run_id>/execution-spec.json の slots.green は script=/opt/app/bin/green-job001.sh work_dir=/var/app/work hang_detect_limit_minutes=60 である(/etc/relay-gate/green-job-map.csv の JOB001 の行)'), function () {
  if (executionSpecNotProvidedYet(this)) {
    // cucumber は、skipped を返した step より後ろの step を実行しない。3 行目(green の stderr.log)の判定は保留の対象ではないため、
    // 保留を返す前にここで済ませる(食い違えばこの step が失敗する)。後続 UC が execution-spec.json を保存すると、3 行目の step がそのまま判定する
    assertGreenStderrLogHasNoJobMapNotFound(this);
    return 'skipped';
  }
  const specFile = path.join(h.runDir(this), 'execution-spec.json');
  assert.ok(
    fs.existsSync(specFile),
    `execution-spec.json should exist (green runner status ${standardRunnerRecord(this, 'green', 'status').trim()})\n--- standard runner log ---\n${h.standardRunnerLogEntries(this, this.runId).join('\n')}\n--- green files ---\n${fs.readdirSync(slotDir(this, 'green')).join(' ')}\n${h.dump(this)}`,
  );
  const spec = JSON.parse(fs.readFileSync(specFile, 'utf8'));
  const green = spec.slots && spec.slots.green;
  assert.ok(green, `execution-spec.json should have slots.green: ${JSON.stringify(spec)}`);
  assert.equal(green.script, '/opt/app/bin/green-job001.sh');
  assert.equal(green.work_dir, '/var/app/work');
  assert.equal(Number(green.hang_detect_limit_minutes), 60);
  return undefined;
});

Then(literal('facade/<run_id>/green/stderr.log に "error: job map not found" で始まる行は無い'), function () {
  assertGreenStderrLogHasNoJobMapNotFound(this);
});

// ---- run_id はローカルタイムゾーンの時刻と job_id と 8 桁 hex で発行され成果物と管理 DB で同値である(SPEC-011-04) ----

Given(literal('TZ=UTC で RELAY_GATE_NOW=2026-08-30T11:30:00Z が設定されている'), function () {
  this.extraEnv = { ...(this.extraEnv || {}), TZ: 'UTC', RELAY_GATE_NOW: '2026-08-30T11:30:00Z' };
});

Then(literal('発行された run_id は正規表現 ^20260830T113000-JOB001-[0-9a-f]{8}$ に一致し、末尾に Z を含まない'), function () {
  h.assertExit(this, 0);
  h.runDir(this);
  assert.match(this.runId, /^20260830T113000-JOB001-[0-9a-f]{8}$/);
  assert.ok(!this.runId.endsWith('Z') && !this.runId.includes('Z-'), `run_id must not carry a zone designator: ${this.runId}`);
});

Then(literal('成果物ディレクトリ名 facade/<run_id>/ と parallel_runs.run_id は同じ値である'), function () {
  const rows = h.dbRows(this, 'SELECT run_id FROM parallel_runs');
  assert.equal(rows.length, 1);
  assert.ok(fs.statSync(path.join(this.artifactRoot, 'facade', rows[0])).isDirectory());
  assert.deepEqual(fs.readdirSync(path.join(this.artifactRoot, 'facade')), [rows[0]]);
});

// ---- 確報クロスチェックを起動しない(SPEC-001-01) ----

Given(literal('feature flag に確報クロスチェックの制御キーは存在しない'), function () {
  // 有効な並行稼働の設定を補う。「起動されない」は、配置ディレクトリと PATH に置いた記録用の final-crosscheck-runner.sh の
  // 起動記録が無いことで見る(docs/impl/latest/09730858/issues/20261118_091109_cross-uc-scenarios.md「仕様に書かれていない前提」)
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background');
  assert.deepEqual(Object.keys(this.flags).filter((key) => key.startsWith('FINAL')), []);
  this.finalRunnerLog = path.join(this.root, 'final-crosscheck-runner.invoked');
  const recorder = `#!/usr/bin/env bash\nprintf "%s\\n" "$*" >>'${this.finalRunnerLog}'\nexit 0\n`;
  for (const dir of [this.sandbox(h.SPEC_HOME), this.sandbox(`${h.SPEC_HOME}/bin`), path.join(this.root, 'fakebin')]) {
    h.writeExecutable(path.join(dir, 'final-crosscheck-runner.sh'), recorder);
  }
});

Then(literal('final-crosscheck-runner.sh は起動されない'), function () {
  h.assertExit(this, 0);
  singleInvocation(this, 'blue');
  singleInvocation(this, 'green');
  assert.ok(!fs.existsSync(this.finalRunnerLog), 'final-crosscheck-runner.sh must not be started');
});

// ---- 両 slot foreground は入力検証で拒否する(SPEC-001-02) ----

Given(literal('feature flag に BLUE_MODE=foreground GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=background が定義されている'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=background');
});

Then(literal('終了コード 2 で終了する'), function () {
  h.assertExit(this, 2);
});

Then(literal('stderr に "error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground" が出る'), function () {
  h.assertStderrIncludes(this, 'error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground');
});

Then(literal('blue runner も green runner も起動されない'), function () {
  h.assertNoInvocations(this);
  assert.deepEqual(this.runIds, [], 'no run directory expected');
});

Then(literal('parallel_runs に行は作成されない'), function () {
  assertNoRows(this);
});

// ---- JOB_ID が無い起動は拒否する ----

Given(literal('feature flag が正しく定義されている'), function () {
  defineFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off');
});

When(literal('ジョブスケジューラが facade.sh を引数なしで実行する'), function () {
  h.runFacade(this, []);
});

Then(literal('stderr に "error: JOB_ID required" が出る'), function () {
  h.assertStderrIncludes(this, 'error: JOB_ID required');
});

Then(literal('どの runner も起動されない'), function () {
  assert.ok(Object.keys(this.fhRunners || {}).length > 0, 'test runners should be assigned');
  h.assertNoInvocations(this);
});

// ---- 未知の実行モードは拒否する ----

Given(literal('feature flag に BLUE_MODE=parallel GREEN_MODE=background が定義されている'), function () {
  // RAPID_CROSSCHECK_MODE の行は有効な値を補う(補わないと、最初の違反が別のキーになり得る)
  defineFlags(this, 'BLUE_MODE=parallel GREEN_MODE=background RAPID_CROSSCHECK_MODE=off');
});

Then(literal('stderr に "error: invalid value key=BLUE_MODE value=parallel" が出る'), function () {
  h.assertStderrIncludes(this, 'error: invalid value key=BLUE_MODE value=parallel');
});

Then(literal('stderr の次行に "hint: use foreground, background or off" が出る'), function () {
  const lines = h.stderrLines(this);
  const index = lines.indexOf('error: invalid value key=BLUE_MODE value=parallel');
  assert.equal(lines[index + 1], 'hint: use foreground, background or off', h.dump(this));
});

// ---- 設定の違反が 2 つあるときは検証コマンドの error 行の順で最初の違反の 1 行だけを出す ----

Given(literal('/etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 BLUE_RUNNER=relative/blue-runner.sh と実行可能な runner を指す GREEN_RUNNER が定義され、GREEN_IMPL の行は無い'), function () {
  assert.equal(this.configDir, this.sandbox(SPEC_CONFIG_DIR));
  // 値は feature に書かれたとおり(補わない)。GREEN_RUNNER だけ実行可能なテスト用 runner を置く
  h.setFlags(this, 'BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 BLUE_RUNNER=relative/blue-runner.sh');
  this.flags.GREEN_RUNNER = h.writeRunnerAt(this, h.slotRunnerPath(this, 'green'));
  assert.ok(!('GREEN_IMPL' in this.flags));
});

Given(literal('/etc/relay-gate/relative/blue-runner.sh は存在しない'), function () {
  assert.ok(!fs.existsSync(this.sandbox('/etc/relay-gate/relative/blue-runner.sh')));
});

Then(literal('stderr は "error: file not executable key=BLUE_RUNNER path=/etc/relay-gate/relative/blue-runner.sh" の 1 行だけである'), function () {
  assert.deepEqual(h.stderrLines(this), ['error: file not executable key=BLUE_RUNNER path=/etc/relay-gate/relative/blue-runner.sh']);
});

Then(literal('stderr に "error: option required option=GREEN_IMPL" で始まる行は出ない'), function () {
  assert.deepEqual(h.stderrLines(this).filter((l) => l.startsWith('error: option required option=GREEN_IMPL')), []);
});

// ---- RAPID_CROSSCHECK_MODE=background で管理 DB に接続できない ----

Given(literal('管理 DB が停止している'), function () {
  // 参照名の結び付け(pg_service.conf)と rapid-crosscheck.env は残したまま、一時 PostgreSQL を止める
  h.stopManagementDb(this);
});

Then(literal('終了コード 6 で終了する'), function () {
  h.assertExit(this, 6);
});

Then(literal('stderr に "error: management db connection failed run_id=" で始まり "conn_ref=" を含む行が出る'), function () {
  const hits = h.stderrLines(this).filter((l) => l.startsWith('error: management db connection failed run_id=') && l.includes('conn_ref='));
  assert.equal(hits.length, 1, h.dump(this));
});
