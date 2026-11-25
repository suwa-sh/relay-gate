// ATDD(①)step definition。uc_id=7c41c7cd / branch_slug=resolve-execution-target-from-job-map(S7 atdd で実装)。
// 対象は uc-map の atdd_scenarios に列挙された 13 Scenario だけ(@atdd_SPEC-... タグの完全一致で選んで実行する):
//   SPEC-002-03-1 / SPEC-003-02-1 / SPEC-004-01-1 / SPEC-004-01-3..8 / SPEC-004-02-1 / SPEC-004-04-1..3
// features/atdd/SPEC-*.feature の本文は生成物で、変更しない。
// ここに定義するのは、同じディレクトリの既存の step 定義に一致しない文言だけ(既存の step と同じ文言を再定義しない。
// SPEC-004-01-7 の「facade を起動する」は select-slot-mode-and-launch-runners.steps.js の定義を使う)。
// World(root / configDir / sandbox() / unsandbox())と Before / After は configure-feature-flags.steps.js のもの、
// 後始末(h.cleanup)は select-slot-mode-and-launch-runners.steps.js の After を使う。
//
// I/O 境界は実体で検証する(補助は UC BDD と同じ features/uc/steps/support/facade-harness.js を require で使う。複製しない):
//   - facade/bin/facade.sh を実プロセスとして起動し、facade が両 slot の標準の slot runner(runners/standard-runner.sh)を
//     runner IF で起動する。relay-gate は Scenario ごとの一時ディレクトリの /opt/relay-gate に配置する(複製。リポジトリには書かない)
//   - どのジョブマップで解決したかは、標準の slot runner の実行ログの解決の行(job map resolved ... host=... map_version=...)で見る。
//     ジョブマップごとに map_version の値を変えておき、使われたファイルを見分ける
//   - 受け入れ基準の Given は要点だけを書いているため、書かれていない値(mode・実装版・ジョブマップのほかの列)は
//     仕様のほかの Scenario の例示の値で補う(書かれた値は変えない。
//     根拠: docs/impl/latest/7c41c7cd/issues/20261123_142047_cross-uc-scenarios.md の 5)
//   - この機能は管理 DB に触らない(RAPID_CROSSCHECK_MODE=off。一時 PostgreSQL を起動しない)
//
// この機能が作るのは slot runner の解決の段だけ(同 issue の 1)。execution-spec.json の保存(43850d68)と実装の実行(5ebe8db7)は
// 後続の機能の担当で、解決に成功した後の標準の slot runner は成果物を書かずに仮の終了コードで終わる
// (前提 A-004。docs/impl/latest/7c41c7cd/stages/attempt-5/S4_tier-impl.tier-facade.assumptions.yaml)。
// Then が実装の実行を必要とする Scenario(SPEC-004-02-1)は、この機能で決まる部分を判定した後、実装がまだ実行されない間だけ
// cucumber の skipped を返す(合格にしない)。
// リポジトリの中にはファイルを書かない。書くのは World の root(Scenario ごとの一時ディレクトリ)の中だけ。
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const h = require('../../uc/steps/support/facade-harness');

const { literal } = h;

const VALIDATE_CONFIG = path.join(h.FACADE_HOME, 'bin', 'validate-config.sh');
const SPEC_STANDARD_RUNNER = '/opt/relay-gate/runners/standard-runner.sh';
const RUNNER_SCRIPT_NAME = 'standard-runner.sh';
// 設定ファイル置き場の外のジョブマップの場所(仕様の例示値。一時ディレクトリの下へ写す)
const SPEC_MAPS_DIR = '/srv/relay-gate/maps';
// 配置ディレクトリの複製に写すディレクトリ(標準の slot runner の入口 runners/ と lib/、入口が読む本体の src/)
const DEPLOY_DIRS = ['runners', 'lib', 'src'];
const SLOTS = ['blue', 'green'];

const HEADER_7 = 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes';
const HEADER_LOCAL = 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes';
// 末尾の任意列つき(どのジョブマップで解決したかを map_version で見分けるために使う)
const HEADER_LOCAL_VERSIONED = `${HEADER_LOCAL},credential_ref,map_version`;
// 仕様のほかの Scenario の例示の行
const ROW_LOCAL_JOB001 = 'JOB001,/var/app/work,/opt/app/bin/job001.sh,[],0';
const ROW_SSH_JOB001 = 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60';
// 値にカンマと二重引用符を含むセルは、CSV の書き方(セルを二重引用符で囲み、中の二重引用符を二重化する)で書く
const CELL_FIXED_P1_P2P3 = '"[""p1"",""p2 p3""]"';

// ---- 配置と設定 ----

// 暫定注入・契約確定後に削除: 標準の slot runner は受け取った起動引数と環境変数を記録せず、解決に成功した後は成果物も書かない
// (前提 A-004。docs/impl/latest/7c41c7cd/stages/attempt-5/S4_tier-impl.tier-facade.assumptions.yaml)。
// このため、配置の複製の runners/standard-runner.sh の位置に「起動引数と環境変数を記録してから、本物の標準の slot runner
// (同じディレクトリの standard-runner.real.sh へ名前を変えた複製)へ同じ引数で処理を渡し、その終了コードを返す」包みを置く。
// 代わりのスタブではない(解決するのは本物)。background の runner の終了を待つ印(<包み>.<role>.status)にも使う
// (根拠: docs/impl/latest/09730858/issues/20261118_091109_cross-uc-scenarios.md の 4 の案 A。UC BDD の
//  features/uc/steps/select-slot-mode-and-launch-runners.steps.js と同じ包み)
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

// relay-gate を一時ディレクトリの /opt/relay-gate に配置し、feature flag の両 slot に標準の slot runner を割り当てる
// (blue = foreground、green = background の並行稼働。速報クロスチェックは off)
function arrangeStandardRunners(world) {
  const home = world.sandbox(h.SPEC_HOME);
  for (const dir of DEPLOY_DIRS) {
    fs.cpSync(path.join(h.FACADE_HOME, dir), path.join(home, dir), { recursive: true });
  }
  const standard = world.sandbox(SPEC_STANDARD_RUNNER);
  fs.accessSync(standard, fs.constants.X_OK);
  fs.renameSync(standard, path.join(path.dirname(standard), 'standard-runner.real.sh'));
  h.writeExecutable(standard, STANDARD_RUNNER_RECORDING_WRAPPER);
  h.setFlags(
    world,
    `BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=${SPEC_STANDARD_RUNNER} GREEN_RUNNER=${SPEC_STANDARD_RUNNER}`,
  );
  // ジョブスケジューラのジョブ定義が facade に渡すもの(JOB_ID と PARAM)。Given が変えなければ JOB001 だけ
  world.retJobArgs = ['JOB001'];
}

function defaultMap(world, slot) {
  return path.join(world.configDir, `${slot}-job-map.csv`);
}

// ジョブマップを書く(1 行目ヘッダー、2 行目以降は行。改行は LF)
function writeMap(file, header, rows) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, [header, ...rows].map((line) => `${line}\n`).join(''));
  return file;
}

// map_version で見分けられるローカル実行の JOB001 の行だけを持つジョブマップ
function writeVersionedMap(file, mapVersion) {
  return writeMap(file, HEADER_LOCAL_VERSIONED, [`${ROW_LOCAL_JOB001},,${mapVersion}`]);
}

// 両 slot の固定の名前のジョブマップ(見分け用の map_version つき)
function writeDefaultMaps(world) {
  for (const slot of SLOTS) {
    writeVersionedMap(defaultMap(world, slot), `map-${slot}-default`);
  }
}

// ---- 起動 ----

// 包みが残した記録(invoked / env / status)。runner の終了(status の記録)を待ってから読む
function runnerRecord(world, slot, kind) {
  const base = world.sandbox(SPEC_STANDARD_RUNNER);
  h.waitForFile(`${base}.${slot}.status`);
  return fs.readFileSync(`${base}.${slot}.${kind}`, 'utf8');
}

// facade が終わった後も動く background の runner を含め、両 slot の runner の終了を待つ
function waitRunners(world) {
  for (const slot of SLOTS) {
    runnerRecord(world, slot, 'status');
  }
}

// ジョブスケジューラがジョブを起動する = facade.sh を JOB_ID と PARAM だけで起動する
function startJob(world) {
  h.runFacade(world, world.retJobArgs);
  waitRunners(world);
}

function slotDir(world, slot) {
  return path.join(h.runDir(world), slot);
}

function runnerLog(world) {
  return h.standardRunnerLogEntries(world, world.runId).join('\n');
}

function dump(world) {
  return `--- standard runner log ---\n${runnerLog(world)}\n${h.dump(world)}`;
}

// ---- 確かめる ----

// facade が runner IF で JOB_ID(と PARAM)を渡して runner を起動している
function assertInvoked(world, slot) {
  const mode = world.flags[`${slot.toUpperCase()}_MODE`];
  const [jobId, ...params] = world.retJobArgs;
  const expected = ['--run-id', h.runDir(world) && world.runId, '--job-id', jobId, '--role', slot, '--mode', mode, '--', ...params].join(' ');
  assert.equal(runnerRecord(world, slot, 'invoked').trim(), expected, dump(world));
}

// この run の、slot の `job map resolved` の行(1 起動に 1 行)。解決に失敗していれば失敗する
function resolvedLine(world, slot) {
  waitRunners(world);
  h.runDir(world);
  const prefix = `INFO job map resolved job_id=${world.retJobArgs[0]} slot=${slot} `;
  const lines = h.standardRunnerLogEntries(world, world.runId).filter((entry) => entry.startsWith(prefix));
  assert.equal(lines.length, 1, `${slot} runner should resolve the job once\n${dump(world)}`);
  // 解決フェーズの失敗は終了コード 2。成功した後の runner の終わり方は後続の機能が決めるため、値を固定しない
  assert.notEqual(runnerRecord(world, slot, 'status').trim(), '2', dump(world));
  return lines[0];
}

// slot の runner が受け取ったジョブマップの場所(facade が環境変数で渡したもの。一時ディレクトリの接頭辞を落とした形)
function receivedMapPath(world, slot) {
  const env = h.parseEnv(runnerRecord(world, slot, 'env'));
  return world.unsandbox(env[`${slot.toUpperCase()}_JOB_MAP_CSV`] || '');
}

// slot の runner が、指定の場所(仕様の絶対パスの形)のジョブマップ(map_version で見分ける)で解決している
function assertResolvedFrom(world, slot, specPath, mapVersion) {
  assert.equal(receivedMapPath(world, slot), specPath, `${slot} runner should receive the job map location\n${dump(world)}`);
  assert.ok(
    resolvedLine(world, slot).endsWith(` host=- map_version=${mapVersion}`),
    `${slot} runner should resolve from the job map "${mapVersion}"\n${dump(world)}`,
  );
}

// 解決結果のうち実行ログに出ない項目(user / script / work_dir / 固定引数 / 引数の並びなど)は、
// 自作の runner と同じく共通ライブラリ(配置した lib/runner-resolve.sh)を source して resolve_execution_target を直接呼んで確かめる。
// 関数 resolve_execution_target <script> <run_id> <job_id> <role> [PARAM...] と、結果のグローバル変数
// (EXECUTION_TARGET_* / ARGUMENT_LIST。null は空文字)は、自作の runner へ約束する入口として仕様が定めている
// (docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml の runner_resolve_library。判断記録 spec-decision-042。ハーネス注入ではない)
// (根拠: docs/impl/latest/7c41c7cd/issues/20261123_142047_cross-uc-scenarios.md の 4 の案 A)
const RESOLVE_SCRIPT = [
  'set -u',
  'source "$1"',
  'shift',
  'status=0',
  'resolve_execution_target "$@" || status=$?',
  "printf 'status=%s\\n' \"$status\"",
  "printf 'host=%s\\n' \"$EXECUTION_TARGET_HOST\"",
  "printf 'user=%s\\n' \"$EXECUTION_TARGET_USER\"",
  "printf 'script=%s\\n' \"$EXECUTION_TARGET_SCRIPT\"",
  "printf 'work_dir=%s\\n' \"$EXECUTION_TARGET_WORK_DIR\"",
  "printf 'hang_detect_limit_minutes=%s\\n' \"$EXECUTION_TARGET_HANG_DETECT_LIMIT_MINUTES\"",
  "printf 'credential_ref=%s\\n' \"$EXECUTION_TARGET_CREDENTIAL_REF\"",
  "printf 'map_version=%s\\n' \"$EXECUTION_TARGET_MAP_VERSION\"",
  "printf 'exec=%s\\n' \"$EXECUTION_TARGET_EXEC\"",
  'for value in ${EXECUTION_TARGET_FIXED_PARAMS[@]+"${EXECUTION_TARGET_FIXED_PARAMS[@]}"}; do printf \'fixed=%s\\n\' "$value"; done',
  'for value in ${ARGUMENT_LIST[@]+"${ARGUMENT_LIST[@]}"}; do printf \'arg=%s\\n\' "$value"; done',
].join('\n');

// facade が slot の runner へ渡したのと同じ環境変数・同じ JOB_ID と PARAM で、共通ライブラリの解決の関数を呼ぶ。
// 実プロセスの runner が解決に成功していること(実行ログの解決の行)を先に確かめ、同じ host を返すことも見る。
// 実行ログと成果物の置き場は、実プロセスの起動のものと分ける
function resolvedTarget(world, slot) {
  const line = resolvedLine(world, slot);
  const scriptFile = path.join(world.root, 'library-call.sh');
  fs.writeFileSync(scriptFile, `${RESOLVE_SCRIPT}\n`);
  const env = {
    ...h.parseEnv(runnerRecord(world, slot, 'env')),
    RELAY_GATE_ARTIFACT_ROOT: path.join(world.root, 'library-artifacts'),
    RELAY_GATE_LOG_DIR: path.join(world.root, 'library-logs'),
  };
  const library = path.join(world.sandbox(h.SPEC_HOME), 'lib', 'runner-resolve.sh');
  const [jobId, ...params] = world.retJobArgs;
  const proc = spawnSync('bash', [scriptFile, library, RUNNER_SCRIPT_NAME, world.runId, jobId, slot, ...params], {
    cwd: world.root,
    encoding: 'utf8',
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  assert.equal(proc.status, 0, `the library call should finish\n--- stdout ---\n${proc.stdout}\n--- stderr ---\n${proc.stderr}`);
  const resolved = { fixed: [], args: [] };
  for (const text of proc.stdout.split('\n').slice(0, -1)) {
    const separator = text.indexOf('=');
    const name = text.slice(0, separator);
    const value = text.slice(separator + 1);
    if (name === 'fixed') {
      resolved.fixed.push(value);
    } else if (name === 'arg') {
      resolved.args.push(value);
    } else {
      resolved[name] = value;
    }
  }
  assert.equal(resolved.status, '0', `resolve_execution_target should succeed: ${JSON.stringify(resolved)}`);
  const shownHost = resolved.host === '' ? '-' : resolved.host;
  assert.ok(line.includes(` host=${shownHost} `), `the runner process should resolve the same host\n${dump(world)}`);
  return resolved;
}

// ---- SPEC-002-03-1(@atdd_SPEC-002-03-1) ----

Given(literal('ジョブスケジューラのジョブ定義が facade の呼び出しと JOB_ID・PARAM だけを持つ'), function () {
  arrangeStandardRunners(this);
  writeDefaultMaps(this);
  // ジョブ定義 = `facade.sh JOB001 20260830`。ホスト・実行ユーザー・スクリプトは持たない(持つのはジョブマップ)
  this.retJobArgs = ['JOB001', '20260830'];
});

When(literal('ジョブを起動する'), function () {
  startJob(this);
});

Then(literal('facade は JOB_ID を runner に渡し、runner がジョブマップで実行先を解決する'), function () {
  for (const slot of SLOTS) {
    assertInvoked(this, slot);
    assertResolvedFrom(this, slot, `/etc/relay-gate/${slot}-job-map.csv`, `map-${slot}-default`);
  }
});

// ---- SPEC-003-02-1(@atdd_SPEC-003-02-1) ----
// uc-map では UC「実装スクリプトを実行して Runner Result を出力する」(5ebe8db7)の atdd_scenarios にも載っている。
// 「JOB_ID がジョブマップに未定義」の経路(解決の失敗)はこの機能の担当で、ここで判定する

Given(literal('JOB_ID がジョブマップに未定義'), function () {
  arrangeStandardRunners(this);
  // 両 slot のジョブマップにあるのは JOB001 の行だけ。起動するのは JOB999
  writeDefaultMaps(this);
  this.retJobArgs = ['JOB999'];
});

When(literal('runner を起動する'), function () {
  startJob(this);
});

Then(literal('非 0 の exitcode.txt と原因を含む stderr.log が出力される'), function () {
  for (const slot of SLOTS) {
    assertInvoked(this, slot);
    const dir = slotDir(this, slot);
    // Runner Result の 3 ファイルが揃う(実装は実行していないため stdout.log は空。書きかけの一時ファイルは残らない)
    for (const name of ['stdout.log', 'stderr.log', 'exitcode.txt']) {
      assert.ok(fs.existsSync(path.join(dir, name)), `${slot}/${name} should exist\n${dump(this)}`);
    }
    assert.equal(fs.readFileSync(path.join(dir, 'stdout.log'), 'utf8'), '');
    assert.deepEqual(fs.readdirSync(dir).filter((name) => name.endsWith('.tmp')), []);
    // 解決の失敗は検証エラー(終了コード 2)。runner の終了コードと exitcode.txt は同じ値
    assert.equal(fs.readFileSync(path.join(dir, 'exitcode.txt'), 'utf8'), '2\n', `${slot}/exitcode.txt`);
    assert.equal(runnerRecord(this, slot, 'status').trim(), '2', `${slot} runner exit code\n${dump(this)}`);
    const expected = `error: job_id=JOB999 not found in job map slot=${slot} map=/etc/relay-gate/${slot}-job-map.csv`;
    const lines = this.unsandbox(fs.readFileSync(path.join(dir, 'stderr.log'), 'utf8')).split('\n');
    assert.ok(lines.includes(expected), `${slot}/stderr.log should include line "${expected}"\n--- stderr.log ---\n${lines.join('\n')}`);
  }
});

// ---- SPEC-004-01-1(@atdd_SPEC-004-01-1) ----
// Then が見る slot は Given が World(retSubjectSlot)に残す。When「runner が JOB_ID を解決する」は SPEC-004-04-1 / -3 と共有する

Given(literal('slot のジョブマップに JOB_ID の行がある'), function () {
  arrangeStandardRunners(this);
  writeMap(defaultMap(this, 'blue'), HEADER_LOCAL, [ROW_LOCAL_JOB001]);
  writeMap(defaultMap(this, 'green'), HEADER_7, [`JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,${CELL_FIXED_P1_P2P3},60`]);
  this.retSubjectSlot = 'green';
});

When(literal('runner が JOB_ID を解決する'), function () {
  startJob(this);
});

Then(literal('ホスト・実行ユーザー・スクリプト・作業ディレクトリ・固定引数・hang_detect_limit_minutes が得られる'), function () {
  const resolved = resolvedTarget(this, this.retSubjectSlot);
  assert.equal(resolved.host, 'host-green-01');
  assert.equal(resolved.user, 'batch');
  assert.equal(resolved.script, '/opt/app/bin/job001.sh');
  assert.equal(resolved.work_dir, '/var/app/work');
  assert.deepEqual(resolved.fixed, ['p1', 'p2 p3']);
  assert.equal(resolved.hang_detect_limit_minutes, '60');
});

// ---- SPEC-004-01-3(@atdd_SPEC-004-01-3) ----

Given(literal('feature flag に blue 用のジョブマップの場所のキーを絶対パスで書き、そのパスと設定ファイル置き場の blue-job-map.csv の両方にジョブマップがある'), function () {
  arrangeStandardRunners(this);
  writeDefaultMaps(this);
  this.flags.BLUE_JOB_MAP_CSV = writeVersionedMap(this.sandbox(`${SPEC_MAPS_DIR}/blue-jobs.csv`), 'map-blue-key');
  assert.ok(path.isAbsolute(this.flags.BLUE_JOB_MAP_CSV));
});

When(literal('blue の runner が JOB_ID を解決する'), function () {
  startJob(this);
});

Then(literal('キーに書いたパスのジョブマップの行で実行先が解決される'), function () {
  assertResolvedFrom(this, 'blue', `${SPEC_MAPS_DIR}/blue-jobs.csv`, 'map-blue-key');
});

// ---- SPEC-004-01-4(@atdd_SPEC-004-01-4) ----

Given(literal('feature flag にジョブマップの場所のキーが blue 用も green 用も無い'), function () {
  arrangeStandardRunners(this);
  writeDefaultMaps(this);
  assert.ok(!('BLUE_JOB_MAP_CSV' in this.flags) && !('GREEN_JOB_MAP_CSV' in this.flags));
});

// SPEC-004-01-6 と共有する
When(literal('blue と green の runner が JOB_ID を解決する'), function () {
  startJob(this);
});

Then(literal('設定ファイル置き場の blue-job-map.csv と green-job-map.csv の行で実行先が解決される'), function () {
  assertResolvedFrom(this, 'blue', '/etc/relay-gate/blue-job-map.csv', 'map-blue-default');
  assertResolvedFrom(this, 'green', '/etc/relay-gate/green-job-map.csv', 'map-green-default');
});

// ---- SPEC-004-01-5(@atdd_SPEC-004-01-5) ----

Given(literal('feature flag のジョブマップの場所のキーの値が空である'), function () {
  arrangeStandardRunners(this);
  writeDefaultMaps(this);
  // 値が空の行 `GREEN_JOB_MAP_CSV=` を書く(その slot = green)
  this.flags.GREEN_JOB_MAP_CSV = '';
  this.retSubjectSlot = 'green';
});

When(literal('その slot の runner が JOB_ID を解決する'), function () {
  startJob(this);
  assert.ok(fs.readFileSync(this.envPath, 'utf8').split('\n').includes('GREEN_JOB_MAP_CSV='), 'feature-flag.env should carry the empty key');
});

Then(literal('キーが無いときと同じく、設定ファイル置き場の固定の名前のジョブマップの行で実行先が解決される'), function () {
  const slot = this.retSubjectSlot;
  assertResolvedFrom(this, slot, `/etc/relay-gate/${slot}-job-map.csv`, `map-${slot}-default`);
});

// ---- SPEC-004-01-6(@atdd_SPEC-004-01-6) ----

Given(literal('feature flag に green 用のジョブマップの場所のキーだけを書き、blue 用のキーが無い'), function () {
  arrangeStandardRunners(this);
  // 固定の名前のジョブマップは両 slot に置く(green がキーの場所ではなく固定の名前を読めば、map_version が食い違う)
  writeDefaultMaps(this);
  this.flags.GREEN_JOB_MAP_CSV = writeVersionedMap(this.sandbox(`${SPEC_MAPS_DIR}/green-jobs.csv`), 'map-green-key');
  assert.ok(!('BLUE_JOB_MAP_CSV' in this.flags));
});

Then(literal('green はキーに書いたパスのジョブマップ、blue は設定ファイル置き場の blue-job-map.csv で実行先が解決される'), function () {
  assertResolvedFrom(this, 'green', `${SPEC_MAPS_DIR}/green-jobs.csv`, 'map-green-key');
  assertResolvedFrom(this, 'blue', '/etc/relay-gate/blue-job-map.csv', 'map-blue-default');
});

// ---- SPEC-004-01-7(@atdd_SPEC-004-01-7) ----
// When「facade を起動する」は select-slot-mode-and-launch-runners.steps.js の定義(カレントディレクトリは World の root で facade.sh JOB001)。
// World の root は feature-flag.env があるディレクトリ(root の下の /etc/relay-gate)とは別のディレクトリ

Given(literal('feature flag のジョブマップの場所のキーに相対パスを書き、feature-flag.env があるディレクトリとは別のディレクトリをカレントディレクトリにしている'), function () {
  arrangeStandardRunners(this);
  writeDefaultMaps(this);
  // 値は相対パスのまま書く(一時ディレクトリの絶対パスへ置き換えない)
  this.flags.GREEN_JOB_MAP_CSV = './maps/green-jobs.csv';
  writeVersionedMap(path.join(this.configDir, 'maps', 'green-jobs.csv'), 'map-green-config-relative');
  // カレントディレクトリを基準にした同じ相対パスにも、別のジョブマップを置く(こちらを読めば map_version が食い違う)
  assert.notEqual(this.root, path.dirname(this.envPath));
  writeVersionedMap(path.join(this.root, 'maps', 'green-jobs.csv'), 'map-green-cwd-relative');
});

Then(literal('feature-flag.env があるディレクトリを基準に解決したパスのジョブマップで実行先が解決される'), function () {
  // 解決した後のパス = feature-flag.env があるディレクトリ + / + 値(. を畳まない)
  assertResolvedFrom(this, 'green', '/etc/relay-gate/./maps/green-jobs.csv', 'map-green-config-relative');
  assertResolvedFrom(this, 'blue', '/etc/relay-gate/blue-job-map.csv', 'map-blue-default');
});

// ---- SPEC-004-01-8(@atdd_SPEC-004-01-8) ----

Given(literal('feature flag にジョブマップの場所のキーを書いた'), function () {
  arrangeStandardRunners(this);
  writeDefaultMaps(this);
  // blue は絶対パス、green は相対パスで書く
  this.flags.BLUE_JOB_MAP_CSV = writeVersionedMap(this.sandbox(`${SPEC_MAPS_DIR}/blue-jobs.csv`), 'map-blue-key');
  this.flags.GREEN_JOB_MAP_CSV = './maps/green-jobs.csv';
  writeVersionedMap(path.join(this.configDir, 'maps', 'green-jobs.csv'), 'map-green-config-relative');
});

When(literal('feature flag の検証コマンドを実行し、同じ設定で facade を起動する'), function () {
  h.flushFlags(this);
  const before = fs.readFileSync(this.envPath, 'utf8');
  const proc = spawnSync(VALIDATE_CONFIG, ['--feature-flag', this.envPath], {
    cwd: this.root,
    encoding: 'utf8',
    env: { ...process.env, RELAY_GATE_CONFIG_DIR: this.configDir },
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  this.retValidation = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
  startJob(this);
  // 同じ設定(feature-flag.env の内容は検証のときと同じ)
  assert.equal(fs.readFileSync(this.envPath, 'utf8'), before);
});

Then(literal('検証コマンドが所在を検査して表示するジョブマップと、slot runner が実行先の解決に使うジョブマップは、同じファイルである'), function () {
  const validation = this.retValidation;
  const shown = `--- validation status ${validation.status}\n--- stdout ---\n${validation.stdout}\n--- stderr ---\n${validation.stderr}`;
  // 検証コマンドは所在の検査を通り(終了コード 0)、決めた場所を stdout に表示する
  assert.equal(validation.status, 0, shown);
  const lines = validation.stdout.split('\n');
  for (const [slot, mapVersion] of [
    ['blue', 'map-blue-key'],
    ['green', 'map-green-config-relative'],
  ]) {
    const prefix = `${slot}_job_map: `;
    const displayed = lines.filter((text) => text.startsWith(prefix)).map((text) => text.slice(prefix.length));
    assert.equal(displayed.length, 1, `validation should show ${slot}_job_map once\n${shown}`);
    // 表示された場所と、runner が受け取った場所は、文字列として同じで、同じ実体を指す
    const received = h.parseEnv(runnerRecord(this, slot, 'env'))[`${slot.toUpperCase()}_JOB_MAP_CSV`];
    assert.equal(received, displayed[0], `${slot} runner should receive the location shown by validation\n${shown}`);
    assert.equal(fs.realpathSync(received), fs.realpathSync(displayed[0]));
    // runner はその場所のジョブマップで解決している
    assertResolvedFrom(this, slot, this.unsandbox(displayed[0]), mapVersion);
  }
});

// ---- SPEC-004-02-1(@atdd_SPEC-004-02-1) ----
// uc-map では UC「実装スクリプトを実行して Runner Result を出力する」(5ebe8db7)の atdd_scenarios にも載っている。
// 「実装へ渡される」の実行の側は 5ebe8db7 の担当(docs/impl/latest/7c41c7cd/issues/20261123_142047_cross-uc-scenarios.md の 3)。
// この機能で決まるのは、解決フェーズが組み立てた引数の並び(固定引数 + PARAM)まで。
//   - ジョブマップの script は、受け取った引数を記録する実スクリプト(一時ディレクトリの中。ローカル実行の行)にしておく
//   - 実装が実行されて記録があれば、記録(実装が実際に受け取った引数)で判定する
//   - 標準の slot runner が解決に成功し、まだ実装を実行せず結果も公開していない間は、組み立てた引数の並びを判定した後、
//     cucumber の skipped を返す(合格にしない)。5ebe8db7 が実装の実行を作ると、同じ step が記録で判定する
//   - 解決に失敗した回は保留にせず失敗させる

Given(literal('固定引数 ["p1","p2 p3"] と追加引数 a b'), function () {
  arrangeStandardRunners(this);
  const workDir = this.sandbox('/var/app/work');
  fs.mkdirSync(workDir, { recursive: true });
  this.retImplScript = h.writeExecutable(
    this.sandbox('/opt/app/bin/job001.sh'),
    '#!/usr/bin/env bash\n{ printf "%s\\n" "$#"; for a in "$@"; do printf "%s\\n" "$a"; done; } >"$0.args"\nexit 0\n',
  );
  writeMap(defaultMap(this, 'blue'), HEADER_LOCAL, [`JOB001,${workDir},${this.retImplScript},${CELL_FIXED_P1_P2P3},0`]);
  // green は判定の対象にしない(記録するスクリプトを指さない)
  writeMap(defaultMap(this, 'green'), HEADER_LOCAL, [ROW_LOCAL_JOB001]);
  this.retJobArgs = ['JOB001', 'a', 'b'];
});

When(literal('実装へ渡す引数を確認する'), function () {
  startJob(this);
});

Then(literal('p1, "p2 p3", a, b の順で 4 引数として渡される'), function () {
  const expected = ['p1', 'p2 p3', 'a', 'b'];
  const record = `${this.retImplScript}.args`;
  const published = fs.existsSync(path.join(slotDir(this, 'blue'), 'exitcode.txt'));
  if (!fs.existsSync(record) && !published) {
    // 実装の実行(5ebe8db7)がまだ無い間。解決フェーズが組み立てた引数の並びを判定してから保留を返す(食い違えばここで失敗する)
    const resolved = resolvedTarget(this, 'blue');
    assert.deepEqual(resolved.fixed, ['p1', 'p2 p3']);
    assert.deepEqual(resolved.args, expected);
    return 'skipped';
  }
  assert.ok(fs.existsSync(record), `the implementation should be executed and record its arguments\n${dump(this)}`);
  const [count, ...received] = fs.readFileSync(record, 'utf8').split('\n').slice(0, -1);
  assert.equal(count, '4');
  assert.deepEqual(received, expected);
  return undefined;
});

// ---- SPEC-004-04-1(@atdd_SPEC-004-04-1) ----

Given(literal('元資料どおりの列名(job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes)の CSV ジョブマップ'), function () {
  arrangeStandardRunners(this);
  writeMap(defaultMap(this, 'blue'), HEADER_LOCAL, [ROW_LOCAL_JOB001]);
  writeMap(defaultMap(this, 'green'), 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes', [ROW_SSH_JOB001]);
  this.retSubjectSlot = 'green';
});

Then(literal('列名の読み替えなしに host・user・script・work_dir・fixed_params・hang_detect_limit_minutes が得られる'), function () {
  const resolved = resolvedTarget(this, this.retSubjectSlot);
  assert.equal(resolved.host, 'host-green-01');
  assert.equal(resolved.user, 'batch');
  assert.equal(resolved.script, '/opt/app/bin/job001.sh');
  assert.equal(resolved.work_dir, '/var/app/work');
  assert.deepEqual(resolved.fixed, []);
  assert.equal(resolved.hang_detect_limit_minutes, '60');
});

// ---- SPEC-004-04-2(@atdd_SPEC-004-04-2) ----

Given(literal('fixed_params セルに p1 と p2 p3 の 2 要素の JSON 配列を、二重引用符で囲み内部の二重引用符を二重化して書いた'), function () {
  arrangeStandardRunners(this);
  writeMap(defaultMap(this, 'blue'), HEADER_LOCAL, [`JOB001,/var/app/work,/opt/app/bin/job001.sh,${CELL_FIXED_P1_P2P3},0`]);
  writeMap(defaultMap(this, 'green'), HEADER_LOCAL, [ROW_LOCAL_JOB001]);
  // セルの書き方そのもの(カンマを含むセルを二重引用符で囲み、中の二重引用符を二重化している)
  assert.ok(fs.readFileSync(defaultMap(this, 'blue'), 'utf8').includes(',"[""p1"",""p2 p3""]",'));
});

When(literal('runner が固定引数を解析する'), function () {
  startJob(this);
});

Then(literal('空白とカンマを維持した 2 引数として得られる'), function () {
  // セルの中のカンマで列がずれず(ずれれば解決に失敗する)、要素の中の空白で引数が割れない
  const resolved = resolvedTarget(this, 'blue');
  assert.deepEqual(resolved.fixed, ['p1', 'p2 p3']);
  assert.equal(resolved.script, '/opt/app/bin/job001.sh');
  assert.equal(resolved.hang_detect_limit_minutes, '0');
});

// ---- SPEC-004-04-3(@atdd_SPEC-004-04-3) ----
// uc-map では 5ebe8db7 の atdd_scenarios にも載っている(ローカル実行の実行の側)。この機能で決まるのは解決結果の実行方法まで

Given(literal('host と user の列を持たないローカル実行用の slot ジョブマップ'), function () {
  arrangeStandardRunners(this);
  writeMap(defaultMap(this, 'blue'), HEADER_LOCAL, [ROW_LOCAL_JOB001]);
  writeMap(defaultMap(this, 'green'), HEADER_LOCAL, [ROW_LOCAL_JOB001]);
  const header = fs.readFileSync(defaultMap(this, 'blue'), 'utf8').split('\n')[0].split(',');
  assert.ok(!header.includes('host') && !header.includes('user'));
  this.retSubjectSlot = 'blue';
});

Then(literal('ローカル実行として解決される'), function () {
  const resolved = resolvedTarget(this, this.retSubjectSlot);
  assert.equal(resolved.exec, 'local');
  assert.equal(resolved.host, '');
  assert.equal(resolved.user, '');
  assert.ok(resolvedLine(this, this.retSubjectSlot).includes(' host=- '), dump(this));
});
