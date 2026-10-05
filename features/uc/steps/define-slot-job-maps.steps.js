// UC BDD(②)step definition。uc_id=eff24f55 / branch_slug=define-slot-job-maps(S2 skeleton を S6 uc-bdd で実装)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/slot ごとのジョブマップを定義する/spec.md#E2E完了条件(BDD)
// step 文言は feature から転写したリテラルを正規表現で完全一致させる。
// World / Before / After は features/uc/steps/configure-feature-flags.steps.js が定義済み(同一 require glob で読まれる)。
// ここでは setWorldConstructor を呼ばない(World は 1 つだけ)。
//
// I/O 境界は実体で検証する: World の sandbox root(Scenario ごとの一時ディレクトリ)配下に、feature の絶対パス
// (/etc/relay-gate/*-job-map.csv)と同じ相対位置でジョブマップの実ファイルを置き、facade/bin/validate-config.sh を
// 実プロセスとして起動する。出力中の sandbox root 接頭辞は World.unsandbox で落として feature の文言と突き合わせる。
// パスを省略した When(「validate-config.sh --job-map を実行する」)は、Given が用意した green-job-map.csv を渡す。
// 入力の守備範囲(NUL / 不正な UTF-8 / BOM / CR / 制御文字)は Buffer で実バイトを書く。単一スナップショットの差し替えと
// 複製失敗(終了コード 6)は TMPDIR を Scenario 専用(root/tmp)にして観測する。
// UC 横断 Scenario の扱い: docs/impl/latest/eff24f55/issues/20260919_161456_cross-uc-scenarios.md
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const REPO_ROOT = path.resolve(__dirname, '../../..');
const VALIDATE_CONFIG = path.join(REPO_ROOT, 'facade/bin/validate-config.sh');

// feature に書かれた絶対パス(仕様の例示値)
const SPEC_GREEN_MAP = '/etc/relay-gate/green-job-map.csv';
const SPEC_BLUE_MAP = '/etc/relay-gate/blue-job-map.csv';
const RUN_ID = '20260830T113000-JOB001-3f9a1c2e';

// 単一スナップショットの一時ファイル名(契約 config_input_rules.snapshot.validate_config: 接頭辞 relay-gate-、作業中は末尾 .part)
const SNAPSHOT_PREFIX = 'relay-gate-';
const SNAPSHOT_WORK_SUFFIX = '.part';

const HEADER_LOCAL = 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes';
const HEADER_7 = 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes';
const HEADER_9 = `${HEADER_7},credential_ref,map_version`;

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

// 7 列ヘッダー用の有効な行(fixed_params は CSV セルの表記をそのまま渡す)
function row7(jobId, { host = 'host-green-01', user = 'batch', fixedParams = '"[]"', hang = '60' } = {}) {
  return `${jobId},${host},${user},/var/app/work,/opt/app/bin/${jobId.toLowerCase()}.sh,${fixedParams},${hang}`;
}

// 9 列ヘッダー用の有効な行
function row9(jobId, { hang = '60', credentialRef = 'ssh-key-green', mapVersion = 'map-v3' } = {}) {
  return `${row7(jobId, { hang })},${credentialRef},${mapVersion}`;
}

// host / user 列を持たないローカル実行用の行
function rowLocal(jobId, { hang = '0' } = {}) {
  return `${jobId},/var/app/work,/opt/app/bin/${jobId.toLowerCase()}.sh,"[]",${hang}`;
}

// ジョブマップを sandbox 配下の実ファイルとして書く(lines[0] がヘッダー = 1 行目)
function writeMap(world, specPath, lines) {
  const file = world.sandbox(specPath);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, lines.join('\n') + '\n');
  world.mapLines = world.mapLines || {};
  world.mapLines[specPath] = lines;
}

function appendRows(world, specPath, rows) {
  const lines = (world.mapLines && world.mapLines[specPath]) || [];
  assert.ok(lines.length > 0, `header must be written before rows: ${specPath}`);
  writeMap(world, specPath, [...lines, ...rows]);
}

// 実バイトをそのまま書く(NUL / 不正な UTF-8 / BOM / CR / 制御文字 / 末尾改行なし)。mapLines は追跡しない
function writeMapBytes(world, specPath, buffer) {
  const file = world.sandbox(specPath);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, buffer);
  return file;
}

// Scenario 専用の TMPDIR(単一スナップショットの置き場所を観測する。create=false なら存在しないディレクトリ = 書き込めない)
function useScenarioTmpDir(world, { create = true } = {}) {
  world.tmpDir = path.join(world.root, 'tmp');
  if (create) {
    fs.mkdirSync(world.tmpDir, { recursive: true });
  }
  return world.tmpDir;
}

function spawnEnv(world) {
  const env = { ...process.env, RELAY_GATE_CONFIG_DIR: world.configDir };
  if (world.tmpDir) {
    env.TMPDIR = world.tmpDir;
  }
  return env;
}

function runJobMap(world, specPath, extraArgs = []) {
  const file = world.sandbox(specPath);
  assert.ok(fs.existsSync(file), `job map fixture should exist: ${specPath}`);
  const proc = spawnSync(VALIDATE_CONFIG, ['--job-map', file, ...extraArgs], {
    cwd: world.root,
    encoding: 'utf8',
    env: spawnEnv(world),
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  world.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
  return world.result;
}

// 最終名の一時ファイル(relay-gate-* で .part の付かないもの)が TMPDIR に現れたか
function snapshotFinalNameExists(tmpDir) {
  let entries;
  try {
    entries = fs.readdirSync(tmpDir);
  } catch {
    return false;
  }
  return entries.some((name) => name.startsWith(SNAPSHOT_PREFIX) && !name.endsWith(SNAPSHOT_WORK_SUFFIX));
}

// 差し替えつきの実行: 複製の最終名が TMPDIR に現れた直後に、用意した新しいファイルを mv(rename)で同じパスへ置き換える
// (契約 edit_rule どおりの運用。tier BDD facade/features/steps/define-slot-job-maps.steps.js の runWithSwap と同じ観測方法)
function runJobMapWithSwap(world, specPath, extraArgs = []) {
  const file = world.sandbox(specPath);
  assert.ok(fs.existsSync(file), `job map fixture should exist: ${specPath}`);
  return new Promise((resolve, reject) => {
    const proc = spawn(VALIDATE_CONFIG, ['--job-map', file, ...extraArgs], { cwd: world.root, env: spawnEnv(world) });
    let stdout = '';
    let stderr = '';
    proc.stdout.setEncoding('utf8');
    proc.stderr.setEncoding('utf8');
    proc.stdout.on('data', (chunk) => {
      stdout += chunk;
    });
    proc.stderr.on('data', (chunk) => {
      stderr += chunk;
    });
    let finished = false;
    const poll = () => {
      if (finished || world.swapDone) {
        return;
      }
      if (snapshotFinalNameExists(world.tmpDir)) {
        fs.renameSync(world.swapPlan.nextPath, file);
        world.swapDone = true;
        return;
      }
      setImmediate(poll);
    };
    setImmediate(poll);
    proc.on('error', (error) => {
      finished = true;
      reject(error);
    });
    proc.on('close', (code) => {
      finished = true;
      world.result = { status: code, stdout, stderr };
      resolve(world.result);
    });
  });
}

// swap 計画があれば差し替えつき、なければ同期実行
async function runJobMapMaybeSwap(world, specPath, extraArgs = []) {
  if (world.swapPlan) {
    return runJobMapWithSwap(world, specPath, extraArgs);
  }
  return runJobMap(world, specPath, extraArgs);
}

function outputDump(result) {
  return `--- stdout ---\n${result.stdout}\n--- stderr ---\n${result.stderr}`;
}

function assertExit(world, code) {
  assert.equal(world.result.status, code, `exit code\n${outputDump(world.result)}`);
}

function stdoutLines(world) {
  return world.unsandbox(world.result.stdout).split('\n').filter((line) => line.length > 0);
}

function stderrLines(world) {
  return world.unsandbox(world.result.stderr).split('\n').filter((line) => line.length > 0);
}

function assertStdoutIncludes(world, expected) {
  assert.ok(stdoutLines(world).includes(expected), `stdout should include line "${expected}"\n${outputDump(world.result)}`);
}

function assertStderrIncludes(world, expected) {
  assert.ok(stderrLines(world).includes(expected), `stderr should include line "${expected}"\n${outputDump(world.result)}`);
}

// `info: resolved job_id=JOB001` の行がちょうど 1 行で、fragment を含むこと
function assertResolvedLine(world, fragment) {
  const resolved = stderrLines(world).filter((line) => line.includes('info: resolved job_id=JOB001'));
  assert.equal(resolved.length, 1, `stderr should have exactly one resolved line for JOB001\n${outputDump(world.result)}`);
  assert.ok(resolved[0].includes(fragment), `resolved line should include ${fragment}\n${outputDump(world.result)}`);
}

function executionSpecPath(world) {
  return path.join(world.root, 'var/relay-gate/runs', RUN_ID, 'execution-spec.json');
}

// ---- Given ----

Given(literal('/etc/relay-gate/green-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version" である'), function () {
  writeMap(this, SPEC_GREEN_MAP, [HEADER_9]);
});

Given(literal('行 \'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[""--mode"",""full""]",60,ssh-key-green,map-v3\' と \'JOB002,host-green-01,batch,/var/app/work,/opt/app/bin/job002.sh,"[]",0,ssh-key-green,map-v3\' がある'), function () {
  appendRows(this, SPEC_GREEN_MAP, [
    'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[""--mode"",""full""]",60,ssh-key-green,map-v3',
    'JOB002,host-green-01,batch,/var/app/work,/opt/app/bin/job002.sh,"[]",0,ssh-key-green,map-v3',
  ]);
});

Given(literal('green-job-map.csv のヘッダーが元資料どおりの "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" の 7 列である'), function () {
  writeMap(this, SPEC_GREEN_MAP, [HEADER_7]);
});

Given(literal('行 \'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60\' がある'), function () {
  appendRows(this, SPEC_GREEN_MAP, ['JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60']);
});

Given(literal('green-job-map.csv の JOB001 行の fixed_params セルが \'"[""p1"",""p2 p3""]"\' である(二重引用符で囲み、内部の二重引用符を二重化)'), function () {
  writeMap(this, SPEC_GREEN_MAP, [HEADER_7, row7('JOB001', { fixedParams: '"[""p1"",""p2 p3""]"' })]);
});

Given(literal('blue-job-map.csv のヘッダーが "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" で host / user 列が無い'), function () {
  writeMap(this, SPEC_BLUE_MAP, [HEADER_LOCAL]);
});

Given(literal('行 \'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",0\' がある'), function () {
  appendRows(this, SPEC_BLUE_MAP, ['JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",0']);
});

Given(literal('green-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" である'), function () {
  // 後続の When「各行に ... を追記」が意味を持つよう、有効な 2 行を置く
  writeMap(this, SPEC_GREEN_MAP, [HEADER_7, row7('JOB001'), row7('JOB002', { hang: '0' })]);
});

Given(literal('run_id=20260830T113000-JOB001-3f9a1c2e が execution-spec.json の slots.green.hang_detect_limit_minutes=60 で実行中である'), function () {
  // UC 横断の前提(execution-spec.json の生成は UC「execution-spec.json を確定保存する」の責務)。
  // 根拠: docs/impl/latest/eff24f55/issues/20260919_161456_cross-uc-scenarios.md
  // 他 UC のプロセス起動や状態遷移の注入は行わず、最小形の fixture を実ファイルとして置くだけにする
  // (execution-spec.json の全体形式は担当 UC の契約が正本)。
  const file = executionSpecPath(this);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify({ run_id: RUN_ID, slots: { green: { hang_detect_limit_minutes: 60 } } }) + '\n');
  this.executionSpecBefore = fs.readFileSync(file);
  this.runDirBefore = fs.readdirSync(path.dirname(file)).sort();
});

Given(literal('green-job-map.csv の JOB001 行の hang_detect_limit_minutes を 60 から 90 に変更した'), function () {
  // 変更前(60)のジョブマップを実ファイルで置いてから、JOB001 行だけを 90 に書き換える
  writeMap(this, SPEC_GREEN_MAP, [HEADER_9, row9('JOB001', { hang: '60' }), row9('JOB002', { hang: '60' })]);
  const before = row9('JOB001', { hang: '60' });
  const after = row9('JOB001', { hang: '90' });
  assert.notEqual(before, after);
  const lines = this.mapLines[SPEC_GREEN_MAP].map((line) => (line === before ? after : line));
  writeMap(this, SPEC_GREEN_MAP, lines);
  assert.ok(fs.readFileSync(this.sandbox(SPEC_GREEN_MAP), 'utf8').includes(after));
});

Given(literal('並行稼働モード(blue foreground / green background)で導入する'), function () {
  // 前提の記録のみ(feature flag の組合せは UC「feature flag を設定する」の責務。When / Then は feature flag を読まない)。
  // 根拠: docs/impl/latest/eff24f55/issues/20260919_161456_cross-uc-scenarios.md
  this.operationMode = { blue: 'foreground', green: 'background' };
});

Given(literal('green-job-map.csv の 3 行目(JOB003)の fixed_params セルが \'"p1,p2"\' である'), function () {
  writeMap(this, SPEC_GREEN_MAP, [HEADER_7, row7('JOB001'), row7('JOB003', { fixedParams: '"p1,p2"' })]);
});

Given(literal('green-job-map.csv の 2 行目の fixed_params セルが \'"[""--mode"",""full""]\' で閉じ引用符が無い'), function () {
  writeMap(this, SPEC_GREEN_MAP, [HEADER_7, row7('JOB001', { fixedParams: '"[""--mode"",""full""]' }), row7('JOB002')]);
});

Given(literal('green-job-map.csv に job_id=JOB001 の行が 2 行目と 5 行目にある'), function () {
  writeMap(this, SPEC_GREEN_MAP, [HEADER_7, row7('JOB001'), row7('JOB002'), row7('JOB003'), row7('JOB001')]);
});

Given(literal('green-job-map.csv のヘッダーに hang_detect_limit_minutes 列が無い'), function () {
  writeMap(this, SPEC_GREEN_MAP, ['job_id,host,user,work_dir,script,fixed_params', 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]"']);
});

Given(literal('green-job-map.csv のヘッダーに host 列はあるが user 列が無い'), function () {
  writeMap(this, SPEC_GREEN_MAP, ['job_id,host,work_dir,script,fixed_params,hang_detect_limit_minutes', 'JOB001,host-green-01,/var/app/work,/opt/app/bin/job001.sh,"[]",60']);
});

Given(literal('green-job-map.csv の 2 行目(JOB001)の host が host-green-01 で user が空である'), function () {
  writeMap(this, SPEC_GREEN_MAP, [HEADER_7, row7('JOB001', { host: 'host-green-01', user: '' })]);
});

Given(literal('green-job-map.csv の 2 行目の hang_detect_limit_minutes が "60m" である'), function () {
  writeMap(this, SPEC_GREEN_MAP, [HEADER_7, row7('JOB001', { hang: '60m' })]);
});

Given(literal('green-job-map.csv のヘッダー末尾に impl_version 列がある'), function () {
  writeMap(this, SPEC_GREEN_MAP, [`${HEADER_9},impl_version`, `${row9('JOB001')},green-1.4.0`]);
});

Given(literal('green-job-map.csv の credential_ref が /home/batch/.ssh/id_green である'), function () {
  writeMap(this, SPEC_GREEN_MAP, [HEADER_9, row9('JOB001', { credentialRef: '/home/batch/.ssh/id_green' })]);
});

// ---- When ----

When(literal('基盤適用設計者が validate-config.sh --job-map /etc/relay-gate/green-job-map.csv を実行する'), function () {
  runJobMap(this, SPEC_GREEN_MAP);
});

When(literal('validate-config.sh --job-map を実行する'), function () {
  runJobMap(this, SPEC_GREEN_MAP);
});

When(literal('validate-config.sh --job-map --verbose を実行する'), function () {
  runJobMap(this, SPEC_GREEN_MAP, ['--verbose']);
});

When(literal('validate-config.sh --job-map /etc/relay-gate/blue-job-map.csv --verbose を実行する'), function () {
  runJobMap(this, SPEC_BLUE_MAP, ['--verbose']);
});

When(literal('ヘッダー末尾に credential_ref,map_version を加え各行に ssh-key-green,map-v3 を追記して再実行する'), function () {
  const [header, ...rows] = this.mapLines[SPEC_GREEN_MAP];
  assert.equal(header, HEADER_7);
  assert.ok(rows.length > 0, 'rows should exist before appending optional columns');
  writeMap(this, SPEC_GREEN_MAP, [`${header},credential_ref,map_version`, ...rows.map((row) => `${row},ssh-key-green,map-v3`)]);
  runJobMap(this, SPEC_GREEN_MAP);
});

When(literal('validate-config.sh --job-map /etc/relay-gate/green-job-map.csv --verbose を実行する'), async function () {
  // Scenario「検証中に差し替わったファイル」では前段の And が swap 計画を立てている(差し替えつき実行に切り替わる)
  await runJobMapMaybeSwap(this, SPEC_GREEN_MAP, ['--verbose']);
});

When(literal('blue-job-map.csv の全行に hang_detect_limit_minutes=0、green-job-map.csv の全行に 60 を定義して validate-config.sh を実行する'), function () {
  // foreground slot(blue)はローカル実行のためハング検知なし(0)、background slot(green)は導入時の 60 分
  writeMap(this, SPEC_BLUE_MAP, [HEADER_LOCAL, rowLocal('JOB001', { hang: '0' }), rowLocal('JOB002', { hang: '0' })]);
  writeMap(this, SPEC_GREEN_MAP, [HEADER_9, row9('JOB001', { hang: '60' }), row9('JOB002', { hang: '60' })]);
  this.bothResults = {
    blue: { ...runJobMap(this, SPEC_BLUE_MAP) },
    green: { ...runJobMap(this, SPEC_GREEN_MAP) },
  };
});

// ---- Then ----

Then(literal('終了コード 0 で stdout に "map_path: /etc/relay-gate/green-job-map.csv" "rows=2" "map_version=map-v3" が出る'), function () {
  assertExit(this, 0);
  for (const expected of ['map_path: /etc/relay-gate/green-job-map.csv', 'rows=2', 'map_version=map-v3']) {
    assertStdoutIncludes(this, expected);
  }
});

Then(literal('終了コード 0 で stdout に "rows=1" "map_version=-" が出る'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'rows=1');
  assertStdoutIncludes(this, 'map_version=-');
});

Then(literal('stderr に "warn: unknown column" で始まる行は出ない'), function () {
  const warns = stderrLines(this).filter((line) => line.startsWith('warn: unknown column'));
  assert.deepEqual(warns, [], outputDump(this.result));
});

Then(literal('終了コード 0 で stderr に \'info: resolved job_id=JOB001\' と \'fixed_params=["p1","p2 p3"]\' を含む 1 行が出る(固定引数は p1 と "p2 p3" の 2 要素)'), function () {
  assertExit(this, 0);
  assertResolvedLine(this, 'fixed_params=["p1","p2 p3"]');
});

Then(literal('終了コード 0 で stderr に "info: resolved job_id=JOB001 host=- user=- exec=local" で始まる行が出る'), function () {
  assertExit(this, 0);
  const prefix = 'info: resolved job_id=JOB001 host=- user=- exec=local';
  assert.ok(
    stderrLines(this).some((line) => line.startsWith(prefix)),
    `stderr should have a line starting with "${prefix}"\n${outputDump(this.result)}`,
  );
});

Then(literal('終了コード 0 で stdout に "map_version=-" が出る'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'map_version=-');
});

Then(literal('終了コード 0 で stdout に "map_version=map-v3" が出る'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'map_version=map-v3');
});

Then(literal('終了コード 0 で stderr に "info: resolved job_id=JOB001" と "hang_detect_limit_minutes=90" を含む 1 行が出る'), function () {
  assertExit(this, 0);
  assertResolvedLine(this, 'hang_detect_limit_minutes=90');
});

Then(literal('20260830T113000-JOB001-3f9a1c2e の execution-spec.json の slots.green.hang_detect_limit_minutes は 60 のままである'), function () {
  // 検証コマンドが読み取り専用で、既存 run の成果物を書き換えないこと(内容のバイト一致 + run ディレクトリの構成不変)
  const file = executionSpecPath(this);
  const after = fs.readFileSync(file);
  assert.ok(after.equals(this.executionSpecBefore), 'execution-spec.json must not be rewritten by validate-config.sh');
  assert.equal(JSON.parse(after.toString('utf8')).slots.green.hang_detect_limit_minutes, 60);
  assert.deepEqual(fs.readdirSync(path.dirname(file)).sort(), this.runDirBefore);
});

Then(literal('両ファイルとも終了コード 0 で検証を通過する'), function () {
  assert.deepEqual(this.operationMode, { blue: 'foreground', green: 'background' });
  for (const slot of ['blue', 'green']) {
    const result = this.bothResults[slot];
    assert.equal(result.status, 0, `${slot}-job-map.csv exit code\n${outputDump(result)}`);
    const errors = result.stderr.split('\n').filter((line) => line.startsWith('error:'));
    assert.deepEqual(errors, [], `${slot}-job-map.csv\n${outputDump(result)}`);
    assert.ok(this.unsandbox(result.stdout).split('\n').includes(`map_path: /etc/relay-gate/${slot}-job-map.csv`), outputDump(result));
    assert.ok(result.stdout.split('\n').includes('rows=2'), outputDump(result));
  }
});

Then(literal('終了コード 2 で stderr に "error: fixed_params is not a json array of strings line=3 job_id=JOB003 value=p1,p2" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: fixed_params is not a json array of strings line=3 job_id=JOB003 value=p1,p2');
});

Then(literal('終了コード 2 で stderr に "error: csv quote is invalid line=2 path: /etc/relay-gate/green-job-map.csv" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: csv quote is invalid line=2 path: /etc/relay-gate/green-job-map.csv');
});

Then(literal('終了コード 2 で stderr に "error: job map header mismatch missing=hang_detect_limit_minutes path: /etc/relay-gate/green-job-map.csv" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: job map header mismatch missing=hang_detect_limit_minutes path: /etc/relay-gate/green-job-map.csv');
});

Then(literal('終了コード 2 で stderr に "error: job map header mismatch missing=user path: /etc/relay-gate/green-job-map.csv" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: job map header mismatch missing=user path: /etc/relay-gate/green-job-map.csv');
});

Then(literal('終了コード 2 で stderr に "error: user is empty line=2 job_id=JOB001 value=" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: user is empty line=2 job_id=JOB001 value=');
});

Then(literal('終了コード 2 で stderr に "error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=60m" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=60m');
});

Then(literal('終了コード 0 で stderr に "warn: unknown column column=impl_version path: /etc/relay-gate/green-job-map.csv" が出る'), function () {
  assertExit(this, 0);
  assertStderrIncludes(this, 'warn: unknown column column=impl_version path: /etc/relay-gate/green-job-map.csv');
});

Then(literal('終了コード 0 で stderr に "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" が出る'), function () {
  assertExit(this, 0);
  assertStderrIncludes(this, 'warn: credential_ref looks like a secret or path line=2 job_id=JOB001');
});

// ---- spec event 20260921_100000_feedback_impl_feedback_eff24f55 で追加された 7 Scenario の step(S2 skeleton を S6 で実装)----
// 文言は feature から転写したリテラル。keyword の And は直前の step 種別に従うが、cucumber は種別を区別しないため Then で登録する。

// 方針資料の例(Windows 形式パス・非 ASCII のホスト名)。バックスラッシュ・日本語は 1 バイトも変えずに書く
const POLICY_WINDOWS_ROW = 'TOMM0410010100,督促AP,saiken,G:\\scripts,G:\\scripts\\xxx.bat,"[""param1"",""param2"",""param3""]",60';
const POLICY_WINDOWS_RESOLVED =
  'info: resolved job_id=TOMM0410010100 host=督促AP user=saiken exec=ssh work_dir=G:\\scripts script=G:\\scripts\\xxx.bat fixed_params=["param1","param2","param3"] hang_detect_limit_minutes=60';
// 方針資料の例(相対パス)
const POLICY_RELATIVE_ROW = 'TOMM0410010100,./beam-batches,./beam-batches/TOMM0410010100.sh,"[""param1"",""param2"",""param3""]",60';

// 形式から外れた 5 つのジョブマップ(a〜e)。Scenario 内で同時に存在させるため、名前を分けて同じディレクトリに置く
const MALFORMED_MAPS = [
  {
    label: 'a',
    specPath: '/etc/relay-gate/green-job-map-a.csv',
    // 2 行目の job_id セルが J<NUL>2
    bytes: () => Buffer.concat([Buffer.from(`${HEADER_LOCAL}\n`), Buffer.from([0x4a, 0x00, 0x32]), Buffer.from(',/w,/s,"[]",60\n')]),
    expectedError: 'error: nul byte is not allowed line=2',
  },
  {
    label: 'b',
    specPath: '/etc/relay-gate/green-job-map-b.csv',
    // 2 行目が Shift_JIS(cp932)のコメント行 "# 督促"(93 C2 91 A3。93 と 91 は UTF-8 の継続バイトで先頭バイトが無いため不正)
    bytes: () =>
      Buffer.concat([Buffer.from(`${HEADER_LOCAL}\n`), Buffer.from('# '), Buffer.from([0x93, 0xc2, 0x91, 0xa3]), Buffer.from('\n'), Buffer.from('J1,/w,/s,"[]",60\n')]),
    expectedError: 'error: encoding is not utf-8 line=2',
  },
  {
    label: 'c',
    specPath: '/etc/relay-gate/green-job-map-c.csv',
    // 先頭 3 バイトが EF BB BF(BOM)
    bytes: () => Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(`${HEADER_LOCAL}\nJ1,/w,/s,"[]",60\n`)]),
    expectedError: 'error: byte order mark is not allowed line=1',
  },
  {
    label: 'd',
    specPath: '/etc/relay-gate/green-job-map-d.csv',
    // 全行が CRLF で終わる
    bytes: () => Buffer.from(`${HEADER_LOCAL}\r\nJ1,/w,/s,"[]",60\r\n`),
    expectedError: 'error: carriage return is not allowed line=1',
    expectedHint: 'hint: use LF line endings',
  },
  {
    label: 'e',
    specPath: '/etc/relay-gate/green-job-map-e.csv',
    // ヘッダーに job_id 列が 2 つある
    bytes: () => Buffer.from(`${HEADER_LOCAL},job_id\nJ1,/w,/s,"[]",60,J1\n`),
    expectedError: 'error: duplicate column column=job_id',
  },
];

function malformedResult(world, label) {
  const entry = (world.malformed || []).find((item) => item.label === label);
  assert.ok(entry && entry.result, `job map (${label}) should have been validated`);
  return entry;
}

function stderrLinesOf(world, result) {
  return world.unsandbox(result.stderr).split('\n').filter((line) => line.length > 0);
}

// -- 方針資料の Windows 形式パスと非 ASCII の値を含むジョブマップを受理する --

Given(literal("blue-job-map.csv がヘッダー \"job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes\" と方針資料の例の行 'TOMM0410010100,督促AP,saiken,G:\\scripts,G:\\scripts\\xxx.bat,\"[\"\"param1\"\",\"\"param2\"\",\"\"param3\"\"]\",60' である"), function () {
  writeMap(this, SPEC_BLUE_MAP, [HEADER_7, POLICY_WINDOWS_ROW]);
  // fixture が方針資料の例と 1 バイトも違わないこと(バックスラッシュが逃げていない)
  const written = fs.readFileSync(this.sandbox(SPEC_BLUE_MAP), 'utf8');
  assert.ok(written.includes('G:\\scripts\\xxx.bat'), 'fixture must keep backslashes as-is');
  assert.ok(written.includes('督促AP'), 'fixture must keep the non-ASCII host name as-is');
});

When(literal('基盤適用設計者が validate-config.sh --job-map /etc/relay-gate/blue-job-map.csv --verbose を実行する'), function () {
  runJobMap(this, SPEC_BLUE_MAP, ['--verbose']);
});

Then(literal('終了コード 0 で stdout に "rows=1" が出て、stderr に "error:" で始まる行は出ない'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'rows=1');
  const errors = stderrLines(this).filter((line) => line.startsWith('error:'));
  assert.deepEqual(errors, [], outputDump(this.result));
});

Then(literal("stderr に 'info: resolved job_id=TOMM0410010100 host=督促AP user=saiken exec=ssh work_dir=G:\\scripts script=G:\\scripts\\xxx.bat fixed_params=[\"param1\",\"param2\",\"param3\"] hang_detect_limit_minutes=60' が出る(ホスト名・バックスラッシュは 1 バイトも変わらない)"), function () {
  // 行全体の完全一致(unsandbox はパスの接頭辞にしか作用しないので、この行は生の stderr と同じ)
  const rawLines = this.result.stderr.split('\n');
  assert.ok(rawLines.includes(POLICY_WINDOWS_RESOLVED), `stderr should include the exact resolved line\n${outputDump(this.result)}`);
  const resolved = rawLines.filter((line) => line.startsWith('info: resolved job_id=TOMM0410010100'));
  assert.equal(resolved.length, 1, `exactly one resolved line\n${outputDump(this.result)}`);
});

// -- 方針資料の相対パスのジョブマップを受理する --

Given(literal("green-job-map.csv がヘッダー \"job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\" と方針資料の例の行 'TOMM0410010100,./beam-batches,./beam-batches/TOMM0410010100.sh,\"[\"\"param1\"\",\"\"param2\"\",\"\"param3\"\"]\",60' である"), function () {
  writeMap(this, SPEC_GREEN_MAP, [HEADER_LOCAL, POLICY_RELATIVE_ROW]);
});

When(literal('validate-config.sh --job-map /etc/relay-gate/green-job-map.csv を実行する'), function () {
  runJobMap(this, SPEC_GREEN_MAP);
});

// -- データ行 0 件のジョブマップは受理される --

Given(literal('green-job-map.csv がヘッダー行と行頭 # のコメント行だけで、最終行に改行が無い'), function () {
  // 最終行(コメント行)の後に改行を付けない
  writeMapBytes(this, SPEC_GREEN_MAP, Buffer.from(`${HEADER_LOCAL}\n# no data rows`));
  const written = fs.readFileSync(this.sandbox(SPEC_GREEN_MAP));
  assert.notEqual(written[written.length - 1], 0x0a, 'fixture must not end with a newline');
});

Then(literal('終了コード 0 で stdout は "map_path: /etc/relay-gate/green-job-map.csv" "rows=0" "map_version=-" の 3 行である'), function () {
  assertExit(this, 0);
  assert.deepEqual(stdoutLines(this), ['map_path: /etc/relay-gate/green-job-map.csv', 'rows=0', 'map_version=-'], outputDump(this.result));
});

// -- 検証中に差し替わったファイルは複製した時点の内容だけで判定される --

Given(literal("green-job-map.csv のデータ行が 'J1,/old,/s,\"[]\",60' である"), function () {
  writeMap(this, SPEC_GREEN_MAP, [HEADER_LOCAL, 'J1,/old,/s,"[]",60']);
});

// And(前段の Given に続く)。差し替えの計画を立てる。実際の差し替えは When の実行中に runJobMapWithSwap が行う
Then(literal('検証コマンドが入力を一時ファイルへ複製した直後に、基盤適用設計者が job_id に NUL バイトを含む新しいファイルを mv で同じパスへ置き換える(契約 edit_rule どおりの運用。テストは TMPDIR 配下に最終名の一時ファイル(接頭辞 relay-gate-、末尾 .part の付かないもの)が現れたことを監視して置き換えのタイミングを決める。最終名が現れた時点で複製は完了している)'), function () {
  useScenarioTmpDir(this);
  // 新しいファイルは同じディレクトリに用意し、mv(同一ファイルシステム内の rename)で置き換える
  const nextPath = path.join(this.configDir, 'green-job-map.csv.next');
  fs.writeFileSync(nextPath, Buffer.concat([Buffer.from(`${HEADER_LOCAL}\n`), Buffer.from([0x4a, 0x00, 0x32]), Buffer.from(',/new,/s,"[]",60\n')]));
  this.swapPlan = { nextPath };
  this.swapDone = false;
});

Then(literal('終了コード 0 で stderr に "info: resolved job_id=J1" と "work_dir=/old" を含む行が出る(旧内容と新内容を混ぜた結果は返さない)'), function () {
  // 差し替えは実際に起きている(最終名の出現を捉えて mv した)
  assert.equal(this.swapDone, true, 'the map file should have been swapped while the snapshot existed');
  assert.equal(fs.existsSync(this.swapPlan.nextPath), false, 'the new file should have been moved onto green-job-map.csv');
  assertExit(this, 0);
  const matched = stderrLines(this).filter((line) => line.includes('info: resolved job_id=J1') && line.includes('work_dir=/old'));
  assert.equal(matched.length, 1, `stderr should have one resolved line for J1\n${outputDump(this.result)}`);
  // 新内容(NUL を含む job_id・/new)は結果に混ざらない
  assert.equal(this.result.stderr.includes('/new'), false, `stderr should not include the swapped-in row\n${outputDump(this.result)}`);
  assert.equal(this.result.stderr.includes('nul byte'), false, `stderr should not judge the swapped-in row\n${outputDump(this.result)}`);
});

Then(literal('stdout の "map_path:" は /etc/relay-gate/green-job-map.csv で、TMPDIR 配下の一時ファイルのパスは出ない'), function () {
  assertStdoutIncludes(this, 'map_path: /etc/relay-gate/green-job-map.csv');
  assert.equal(this.result.stdout.includes(this.tmpDir), false, `stdout should not include TMPDIR path\n${outputDump(this.result)}`);
  assert.equal(this.result.stderr.includes(this.tmpDir), false, `stderr should not include TMPDIR path\n${outputDump(this.result)}`);
});

Then(literal('終了後に TMPDIR 配下に一時ファイルは残らない'), function () {
  assert.deepEqual(fs.readdirSync(this.tmpDir), [], 'TMPDIR should be empty after validate-config.sh exits');
});

// -- 形式から外れた入力は原因ごとの文言で拒否される --

Given(literal('次の 5 つのジョブマップがある: (a) 2 行目の job_id に NUL バイトを含む (b) 2 行目が Shift_JIS のコメント行 (c) 先頭に BOM がある (d) 全行が CRLF で終わる (e) ヘッダーに job_id 列が 2 つある'), function () {
  this.malformed = MALFORMED_MAPS.map((entry) => {
    writeMapBytes(this, entry.specPath, entry.bytes());
    return { ...entry, result: null };
  });
});

When(literal('それぞれに validate-config.sh --job-map を実行する'), function () {
  for (const entry of this.malformed) {
    entry.result = { ...runJobMap(this, entry.specPath) };
  }
});

Then(literal('いずれも終了コード 2 で、stderr は順に "error: nul byte is not allowed line=2 path: ..." / "error: encoding is not utf-8 line=2 path: ..." / "error: byte order mark is not allowed line=1 path: ..." / "error: carriage return is not allowed line=1 path: ..." と "hint: use LF line endings" / "error: duplicate column column=job_id path: ..." を含む'), function () {
  for (const entry of this.malformed) {
    const label = `job map (${entry.label})`;
    assert.equal(entry.result.status, 2, `${label}: exit code\n${outputDump(entry.result)}`);
    const lines = stderrLinesOf(this, entry.result);
    // "path: ..." の ... は当該ファイルのパス(unsandbox 後は仕様の絶対パス)
    const expected = `${entry.expectedError} path: ${entry.specPath}`;
    assert.ok(lines.includes(expected), `${label}: stderr should include line "${expected}"\n${outputDump(entry.result)}`);
    if (entry.expectedHint) {
      assert.ok(lines.includes(entry.expectedHint), `${label}: stderr should include line "${entry.expectedHint}"\n${outputDump(entry.result)}`);
    }
  }
});

Then(literal('(a)(b) の stderr に "csv quote is invalid" は出ず、(c) の stderr に "job map header mismatch" は出ない(利用者が error 行だけで原因を区別できる)'), function () {
  for (const label of ['a', 'b']) {
    const entry = malformedResult(this, label);
    assert.equal(entry.result.stderr.includes('csv quote is invalid'), false, `job map (${label})\n${outputDump(entry.result)}`);
  }
  const c = malformedResult(this, 'c');
  assert.equal(c.result.stderr.includes('job map header mismatch'), false, `job map (c)\n${outputDump(c.result)}`);
});

// -- 検証器の内部障害は検証結果にならない --

Given(literal('TMPDIR が書き込めないディレクトリを指している'), function () {
  // 存在しないディレクトリは書き込めない(複製先の mktemp が失敗する)
  useScenarioTmpDir(this, { create: false });
  assert.equal(fs.existsSync(this.tmpDir), false);
  // 入力自体は有効(検証 OK になり得る内容)。それでも結果は返さないことを見る
  writeMap(this, SPEC_GREEN_MAP, [HEADER_LOCAL, rowLocal('JOB001', { hang: '60' })]);
});

Then(literal('終了コード 6 で stderr に "error: config snapshot failed path: /etc/relay-gate/green-job-map.csv" と "hint: check TMPDIR is writable" が出る'), function () {
  assertExit(this, 6);
  assertStderrIncludes(this, 'error: config snapshot failed path: /etc/relay-gate/green-job-map.csv');
  assertStderrIncludes(this, 'hint: check TMPDIR is writable');
});

Then(literal('stdout は 0 行で、"rows=" は出ない(検証 OK も違反も返さない)'), function () {
  assert.deepEqual(stdoutLines(this), [], outputDump(this.result));
  assert.equal(this.result.stdout.includes('rows='), false, outputDump(this.result));
  assert.equal(this.result.stderr.includes('rows='), false, outputDump(this.result));
});

// -- 出力する値の制御文字は可視表記になる --

Given(literal('green-job-map.csv の JOB001 行の hang_detect_limit_minutes が "6<TAB>0"(タブを含む)で、ヘッダー末尾に列名 "note<ESC>[31m"(ESC を含む)がある'), function () {
  // 実バイトの TAB(0x09)と ESC(0x1b)を含めて書く
  writeMapBytes(this, SPEC_GREEN_MAP, Buffer.from(`${HEADER_LOCAL},note\u001b[31m\nJOB001,/w,/s,"[]",6\t0,x\n`));
});

Then(literal("終了コード 2 で stderr に 'error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=6\\t0' と 'warn: unknown column column=note\\u001b[31m path: /etc/relay-gate/green-job-map.csv' が出る"), function () {
  assertExit(this, 2);
  // 可視表記(バックスラッシュ + t / バックスラッシュ + u001b)で出る
  assertStderrIncludes(this, 'error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=6\\t0');
  assertStderrIncludes(this, 'warn: unknown column column=note\\u001b[31m path: /etc/relay-gate/green-job-map.csv');
});

Then(literal('stderr のどの行にも生の ESC・タブは含まれず、行数は増えない(1 行 1 事実)'), function () {
  const lines = stderrLines(this);
  const raw = lines.filter((line) => /[\u001b\t]/.test(line));
  assert.deepEqual(raw, [], `stderr should not include raw ESC or TAB\n${outputDump(this.result)}`);
  // 1 行 1 事実: 全行が既知の接頭辞で始まり(制御文字で行が割れて接頭辞の無い断片が生じていない)、上の 2 事実は各 1 行
  const orphan = lines.filter((line) => !/^(error|warn|hint|info): /.test(line));
  assert.deepEqual(orphan, [], `every stderr line should start with a known prefix\n${outputDump(this.result)}`);
  assert.equal(lines.filter((line) => line.includes('value=6\\t0')).length, 1, outputDump(this.result));
  assert.equal(lines.filter((line) => line.includes('column=note\\u001b[31m')).length, 1, outputDump(this.result));
});
// ---- spec event 20260923_112000_feedback_impl_feedback_eff24f55_cycle2 で追加・変更された step(S2 skeleton を S6 で実装)----
// 文言は feature から転写したリテラル。keyword の And は直前の step 種別に従うが、cucumber は種別を区別しないため Then で登録する。

// -- job_id が重複するジョブマップは拒否される(初出行を含む lines= と 1 行だけの報告)--

Then(literal("終了コード 2 で stderr に \"error: duplicate job_id job_id=JOB001 lines=2,5\" が出る(初出行 2 を含む)"), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: duplicate job_id job_id=JOB001 lines=2,5');
});

Then(literal("stderr に \"duplicate job_id\" を含む行は 1 行だけである"), function () {
  const dup = stderrLines(this).filter((line) => line.includes('duplicate job_id'));
  assert.equal(dup.length, 1, `stderr should have exactly one duplicate job_id line\n${outputDump(this.result)}`);
});

// -- credential_ref の値は診断行に一切出さない(契約 columns.credential_ref.output_rule)--

function assertNotInOutput(world, secret) {
  // sandbox 接頭辞の有無に関わらず、生の stdout / stderr に値が現れないこと
  assert.equal(world.result.stdout.includes(secret), false, `stdout must not include "${secret}"\n${outputDump(world.result)}`);
  assert.equal(world.result.stderr.includes(secret), false, `stderr must not include "${secret}"\n${outputDump(world.result)}`);
}

Then(literal("stdout と stderr のどこにも \"/home/batch/.ssh/id_green\" は出ない"), function () {
  assertNotInOutput(this, '/home/batch/.ssh/id_green');
});

// -- 参照名の形式に合わない credential_ref は同じ警告で受理され値は出力されない --

Given(literal("green-job-map.csv の 2 行目(JOB001)の credential_ref が \"ssh key green\"(空白を含み、\"/\" も \"BEGIN\" も含まない)である"), function () {
  const value = 'ssh key green';
  assert.equal(value.includes('/'), false);
  assert.equal(value.includes('BEGIN'), false);
  writeMap(this, SPEC_GREEN_MAP, [HEADER_9, row9('JOB001', { credentialRef: value })]);
});

Then(literal("終了コード 0 で stderr に \"warn: credential_ref looks like a secret or path line=2 job_id=JOB001\" が 1 行だけ出る"), function () {
  assertExit(this, 0);
  const expected = 'warn: credential_ref looks like a secret or path line=2 job_id=JOB001';
  const matched = stderrLines(this).filter((line) => line === expected);
  assert.equal(matched.length, 1, `stderr should include exactly one line "${expected}"\n${outputDump(this.result)}`);
  const allCredWarns = stderrLines(this).filter((line) => line.startsWith('warn: credential_ref'));
  assert.equal(allCredWarns.length, 1, `credential_ref warn should be one line\n${outputDump(this.result)}`);
});

Then(literal("stderr に \"error:\" で始まる行は出ず、stdout に \"rows=\" が出る(受理される)"), function () {
  const errors = stderrLines(this).filter((line) => line.startsWith('error:'));
  assert.deepEqual(errors, [], outputDump(this.result));
  assert.ok(stdoutLines(this).some((line) => line.startsWith('rows=')), `stdout should include "rows="\n${outputDump(this.result)}`);
});

Then(literal("stdout と stderr のどこにも \"ssh key green\" は出ない"), function () {
  assertNotInOutput(this, 'ssh key green');
});
