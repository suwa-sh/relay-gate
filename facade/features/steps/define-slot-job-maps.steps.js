// tier BDD(③)step definition。tier-facade / uc_id=eff24f55(slot ごとのジョブマップを定義する)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/slot ごとのジョブマップを定義する/tier-facade.md#ティア完了条件(BDD)
// S2 skeleton の step 文言(feature から転写したリテラル)を完全一致の正規表現で受け、S4 で実装した。
// I/O 境界は実体で検証する: Scenario ごとの一時ディレクトリに map.csv を置き、
// bin/validate-config.sh を実プロセスとして起動する(cwd = 一時ディレクトリ。`path: map.csv` は相対パスのまま出る)。
// 入力の守備範囲(NUL / 不正な UTF-8 / BOM / CR)は Buffer で実バイトを書く。単一スナップショットの差し替えは TMPDIR を
// Scenario 専用にし、最終名の一時ファイル(relay-gate-*、末尾 .part なし)の出現を監視して mv する。
// Before / After(一時ディレクトリ this.workDir)は facade/features/steps/configure-feature-flags.steps.js と共有される(同一 require glob)。
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const SCRIPT = path.resolve(__dirname, '../../bin/validate-config.sh');
const MAP_NAME = 'map.csv';

const HEADER_5 = 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes';
const HEADER_7 = 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes';
const HEADER_9 = `${HEADER_7},credential_ref,map_version`;
const SNAPSHOT_PREFIX = 'relay-gate-';
const SNAPSHOT_WORK_SUFFIX = '.part';

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

// 7 列ヘッダー用の有効な行(fixed_params は CSV セルの表記をそのまま渡す)
function row7(jobId, { host = 'host-green-01', user = 'batch', workDir = '/var/app/work', fixedParams = '"[]"', hang = '60' } = {}) {
  return `${jobId},${host},${user},${workDir},/opt/app/bin/${jobId.toLowerCase()}.sh,${fixedParams},${hang}`;
}

// 9 列ヘッダー用の有効な行
function row9(jobId, { hang = '60', credentialRef = 'ssh-key-green', mapVersion = 'map-v3' } = {}) {
  return `${row7(jobId, { hang })},${credentialRef},${mapVersion}`;
}

function mapPath(world) {
  return path.join(world.workDir, MAP_NAME);
}

function writeMap(world, lines) {
  fs.writeFileSync(mapPath(world), lines.join('\n') + '\n');
}

// 実バイトをそのまま書く(NUL / 不正な UTF-8 / BOM / CR)
function writeMapBytes(world, buffer) {
  fs.writeFileSync(mapPath(world), buffer);
}

// Scenario 専用の TMPDIR(単一スナップショットの置き場所を観測する)
function useScenarioTmpDir(world, { create = true } = {}) {
  world.tmpDir = path.join(world.workDir, 'tmp');
  if (create) {
    fs.mkdirSync(world.tmpDir, { recursive: true });
  }
  return world.tmpDir;
}

function spawnEnv(world) {
  const env = { ...process.env };
  if (world.tmpDir) {
    env.TMPDIR = world.tmpDir;
  }
  if (world.pathPrefix) {
    env.PATH = `${world.pathPrefix}:${env.PATH || ''}`;
  }
  return env;
}

function setResult(world, proc) {
  world.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
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

// 差し替えつきの実行: 複製の最終名が現れた直後に、用意した新しいファイルを mv で map.csv のパスへ置き換える
function runWithSwap(world, args) {
  return new Promise((resolve, reject) => {
    const proc = spawn(SCRIPT, args, { cwd: world.workDir, env: spawnEnv(world) });
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
        fs.renameSync(world.swapPlan.nextPath, mapPath(world));
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
      resolve();
    });
  });
}

async function runValidateConfig(world, args) {
  if (world.swapPlan) {
    await runWithSwap(world, args);
    return;
  }
  const proc = spawnSync(SCRIPT, args, { cwd: world.workDir, encoding: 'utf8', env: spawnEnv(world) });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  setResult(world, proc);
}

function stdoutLines(world) {
  return world.result.stdout.split('\n').filter((line) => line.length > 0);
}

function stderrLines(world) {
  return world.result.stderr.split('\n').filter((line) => line.length > 0);
}

function assertExit(world, code) {
  assert.equal(world.result.status, code, `exit code\n--- stdout ---\n${world.result.stdout}\n--- stderr ---\n${world.result.stderr}`);
}

function assertStderrIncludes(world, expected) {
  assert.ok(stderrLines(world).includes(expected), `stderr should include line "${expected}"\n--- stderr ---\n${world.result.stderr}`);
}

function assertStdoutIncludes(world, expected) {
  assert.ok(stdoutLines(world).includes(expected), `stdout should include line "${expected}"\n--- stdout ---\n${world.result.stdout}`);
}

function assertNoStderrLineStartingWith(world, prefix) {
  const matched = stderrLines(world).filter((line) => line.startsWith(prefix));
  assert.deepEqual(matched, [], `stderr should not have lines starting with "${prefix}"\n--- stderr ---\n${world.result.stderr}`);
}

function assertNoStderrLineIncluding(world, text) {
  const matched = stderrLines(world).filter((line) => line.includes(text));
  assert.deepEqual(matched, [], `stderr should not have lines including "${text}"\n--- stderr ---\n${world.result.stderr}`);
}

// ---- Given ----

Given(literal('一時ファイル map.csv に契約どおりのヘッダー(9 列)と 2 行(JOB001 hang_detect_limit_minutes=60、JOB002 hang_detect_limit_minutes=0、map_version=map-v3)を書く'), function () {
  writeMap(this, [HEADER_9, row9('JOB001', { hang: '60' }), row9('JOB002', { hang: '0' })]);
});

Given(literal('map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" である'), function () {
  writeMap(this, [HEADER_7, row7('JOB001')]);
});

Given(literal('map.csv のヘッダーが "host,job_id,user,script,work_dir,fixed_params,hang_detect_limit_minutes,credential_ref,map_version" の順である'), function () {
  writeMap(this, [
    'host,job_id,user,script,work_dir,fixed_params,hang_detect_limit_minutes,credential_ref,map_version',
    'host-green-01,JOB001,batch,/opt/app/bin/job001.sh,/var/app/work,"[]",60,ssh-key-green,map-v3',
  ]);
});

Given(literal('map.csv のヘッダーが "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" で、行 \'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",0\' がある'), function () {
  writeMap(this, [HEADER_5, 'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",0']);
});

Given(literal('map.csv の JOB001 行の fixed_params セルが \'"[""p2 p3"",""a,b""]"\' である'), function () {
  writeMap(this, [HEADER_7, row7('JOB001', { fixedParams: '"[""p2 p3"",""a,b""]"' })]);
});

Given(literal('map.csv の 3 行目(JOB003)の fixed_params セルが \'"p1,p2"\' である'), function () {
  writeMap(this, [HEADER_7, row7('JOB002'), row7('JOB003', { fixedParams: '"p1,p2"' })]);
});

Given(literal('map.csv の 2 行目の fixed_params セルが \'"[""p1""]\' で閉じ引用符が無い'), function () {
  writeMap(this, [HEADER_7, row7('JOB001', { fixedParams: '"[""p1""]' })]);
});

Given(literal('map.csv の 2 行目と 5 行目が job_id=JOB001 である'), function () {
  writeMap(this, [HEADER_7, row7('JOB001'), row7('JOB002'), row7('JOB003'), row7('JOB001')]);
});

Given(literal('map.csv のヘッダーに script 列が無い'), function () {
  writeMap(this, ['job_id,host,user,work_dir,fixed_params,hang_detect_limit_minutes', 'JOB001,host-green-01,batch,/var/app/work,"[]",60']);
});

Given(literal('map.csv のヘッダーが "job_id,host,work_dir,script,fixed_params,hang_detect_limit_minutes" で user 列が無い'), function () {
  writeMap(this, ['job_id,host,work_dir,script,fixed_params,hang_detect_limit_minutes', 'JOB001,host-green-01,/var/app/work,/opt/app/bin/job001.sh,"[]",60']);
});

Given(literal('map.csv の 2 行目(JOB001)の host が空で user が batch である'), function () {
  writeMap(this, [HEADER_7, row7('JOB001', { host: '', user: 'batch' })]);
});

Given(literal('map.csv の 2 行目が 8 セル(ヘッダーは 9 列)である'), function () {
  // 9 列の行から末尾の map_version セルを落として 8 セルにする
  writeMap(this, [HEADER_9, `${row7('JOB001')},ssh-key-green`]);
});

Given(literal('map.csv のヘッダー末尾に impl_version 列がある'), function () {
  writeMap(this, [`${HEADER_9},impl_version`, `${row9('JOB001')},green-1.4.0`]);
});

Given(literal('map.csv の JOB001 行の credential_ref が /home/batch/.ssh/id_green である'), function () {
  writeMap(this, [HEADER_9, row9('JOB001', { credentialRef: '/home/batch/.ssh/id_green' })]);
});

// 方針資料のジョブマップ例(非 ASCII のホスト名、Windows 形式のパス。バックスラッシュは 1 バイトも変えない)
Given(literal("map.csv がヘッダー \"job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes\" と行 'TOMM0410010100,督促AP,saiken,G:\\scripts,G:\\scripts\\xxx.bat,\"[\"\"param1\"\",\"\"param2\"\",\"\"param3\"\"]\",60' である"), function () {
  writeMap(this, [HEADER_7, 'TOMM0410010100,督促AP,saiken,G:\\scripts,G:\\scripts\\xxx.bat,"[""param1"",""param2"",""param3""]",60']);
});

Given(literal("map.csv がヘッダー \"job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\" と行 'TOMM0410010100,./beam-batches,./beam-batches/TOMM0410010100.sh,\"[\"\"param1\"\"]\",60' である"), function () {
  writeMap(this, [HEADER_5, 'TOMM0410010100,./beam-batches,./beam-batches/TOMM0410010100.sh,"[""param1""]",60']);
});

Given(literal('map.csv の 2 行目(JOB001)の work_dir セルが空である'), function () {
  writeMap(this, [HEADER_7, row7('JOB001', { workDir: '' })]);
});

Given(literal('map.csv がヘッダー行 "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" とコメント行 "# empty" だけである'), function () {
  writeMap(this, [HEADER_5, '# empty']);
});

Given(literal("map.csv の最終行 'J1,/w,/s,\"[]\",60' の後に改行が無い"), function () {
  writeMapBytes(this, Buffer.from(`${HEADER_5}\nJ1,/w,/s,"[]",60`));
});

Given(literal('map.csv の 2 行目の job_id セルが J<NUL>2(NUL バイトを含む)である'), function () {
  writeMapBytes(this, Buffer.concat([Buffer.from(`${HEADER_5}\n`), Buffer.from([0x4a, 0x00, 0x32]), Buffer.from(',/w,/s,"[]",60\n')]));
});

Given(literal('map.csv の 2 行目が Shift_JIS で符号化したコメント行 "# 督促" で、3 行目が有効なデータ行である'), function () {
  // 「督促」の Shift_JIS(cp932)は 93 C2 91 A3。93 と 91 は UTF-8 の継続バイトで先頭バイトが無いため不正
  const sjisComment = Buffer.concat([Buffer.from('# '), Buffer.from([0x93, 0xc2, 0x91, 0xa3]), Buffer.from('\n')]);
  writeMapBytes(this, Buffer.concat([Buffer.from(`${HEADER_5}\n`), sjisComment, Buffer.from('J1,/w,/s,"[]",60\n')]));
});

Given(literal('map.csv の先頭 3 バイトが EF BB BF で、続いて有効なヘッダーとデータ行がある'), function () {
  writeMapBytes(this, Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(`${HEADER_5}\nJ1,/w,/s,"[]",60\n`)]));
});

Given(literal('map.csv の全行が CRLF で終わる(ヘッダーと 1 データ行)'), function () {
  writeMapBytes(this, Buffer.from(`${HEADER_5}\r\nJ1,/w,/s,"[]",60\r\n`));
});

Given(literal('map.csv の 2 行目が半角空白 3 つだけで、ヘッダーは 5 列である'), function () {
  writeMap(this, [HEADER_5, '   ']);
});

Given(literal('map.csv のヘッダーが "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,job_id" である'), function () {
  writeMap(this, [`${HEADER_5},job_id`, 'J1,/w,/s,"[]",60,J1']);
});

Given(literal("map.csv のデータ行が 'J1,/old,/s,\"[]\",60' である"), function () {
  writeMap(this, [HEADER_5, 'J1,/old,/s,"[]",60']);
});

// And(前段の Given に続く。差し替えの計画を立てる。実際の差し替えは When の実行中に runWithSwap が行う)
Then(literal("検証コマンドが入力を複製した直後に、job_id に NUL バイトを含む行 'J<NUL>2,/new,/s,\"[]\",60' を持つ新しいファイルを mv で map.csv のパスへ置き換える(テストは TMPDIR 配下に最終名の一時ファイル(接頭辞 relay-gate-、末尾 .part の付かないもの)が現れたことを監視して置き換えのタイミングを決める。最終名が現れた時点で複製は完了している(契約 config_input_rules.snapshot.validate_config))"), function () {
  useScenarioTmpDir(this);
  const nextPath = path.join(this.workDir, 'next.csv');
  fs.writeFileSync(nextPath, Buffer.concat([Buffer.from(`${HEADER_5}\n`), Buffer.from([0x4a, 0x00, 0x32]), Buffer.from(',/new,/s,"[]",60\n')]));
  this.swapPlan = { nextPath };
  this.swapDone = false;
});

Given(literal('TMPDIR が書き込めないディレクトリを指している'), function () {
  // 存在しないディレクトリは書き込めない(mktemp が失敗する)
  useScenarioTmpDir(this, { create: false });
  writeMap(this, [HEADER_5, 'J1,/w,/s,"[]",60']);
});

Given(literal('検証器が複製完了後に実際に呼ぶ補助コマンドのうち 1 つ(実装が使うコマンド。例: 重複検査に sort を使う実装なら sort、バイト点検の tr)を、テストが PATH の先頭に置いた「常に終了コード 1 で終わる代替」に差し替える(テスト fixture は実装が呼ぶコマンド名に合わせる。連想配列だけで重複検査する実装ならバイト点検のコマンドを差し替える)'), function () {
  // 実装は job_id の重複検査に sort を使う(facade/src/domain/job_map.sh validate_job_map_unique_job_ids)
  this.replacedCommand = 'sort';
  this.pathPrefix = path.join(this.workDir, 'fakebin');
  fs.mkdirSync(this.pathPrefix);
  fs.writeFileSync(path.join(this.pathPrefix, this.replacedCommand), '#!/bin/sh\nexit 1\n', { mode: 0o755 });
  // 違反行と未知列を含む入力でも、内部障害では他の error / warn 行を出さないことを確かめる
  writeMap(this, [`${HEADER_5},impl_version`, 'J1,/w,/s,"[]",60m,x', 'J1,/w,/s,"[]",60,x']);
});

Given(literal('map.csv のヘッダー末尾に列名 "note<ESC>[31m"(ESC を含む)があり、JOB001 行の hang_detect_limit_minutes が "6<TAB>0" である'), function () {
  writeMapBytes(this, Buffer.from(`${HEADER_5},note\u001b[31m\nJOB001,/w,/s,"[]",6\t0,x\n`));
});

// ---- When ----

When(literal('`validate-config.sh --job-map map.csv` を実行する'), async function () {
  await runValidateConfig(this, ['--job-map', MAP_NAME]);
});

When(literal('`validate-config.sh --job-map map.csv --verbose` を実行する'), async function () {
  await runValidateConfig(this, ['--job-map', MAP_NAME, '--verbose']);
});

// ---- Then ----

Then(literal('終了コード 0 で stdout は "map_path: <path>" "rows=2" "map_version=map-v3" の 3 行である'), function () {
  assertExit(this, 0);
  // <path> は --job-map に渡した引数どおり
  assert.deepEqual(stdoutLines(this), [`map_path: ${MAP_NAME}`, 'rows=2', 'map_version=map-v3']);
});

Then(literal('終了コード 0 で stdout に "map_version=-" が出て、stderr に "warn: unknown column" は出ない'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'map_version=-');
  assertNoStderrLineStartingWith(this, 'warn: unknown column');
});

Then(literal('終了コード 0 である'), function () {
  assertExit(this, 0);
});

Then(literal('終了コード 0 で stderr に "info: resolved job_id=JOB001 host=- user=- exec=local" で始まる行が出る'), function () {
  assertExit(this, 0);
  const prefix = 'info: resolved job_id=JOB001 host=- user=- exec=local';
  assert.ok(
    stderrLines(this).some((line) => line.startsWith(prefix)),
    `stderr should have a line starting with "${prefix}"\n--- stderr ---\n${this.result.stderr}`,
  );
});

Then(literal('終了コード 0 で stderr に \'info: resolved job_id=JOB001\' と \'fixed_params=["p2 p3","a,b"]\' を含む行が出る'), function () {
  assertExit(this, 0);
  const matched = stderrLines(this).filter((line) => line.includes('info: resolved job_id=JOB001') && line.includes('fixed_params=["p2 p3","a,b"]'));
  assert.equal(matched.length, 1, `stderr should have one resolved line for JOB001\n--- stderr ---\n${this.result.stderr}`);
});

Then(literal('終了コード 2 で stderr に "error: fixed_params is not a json array of strings line=3 job_id=JOB003 value=p1,p2" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: fixed_params is not a json array of strings line=3 job_id=JOB003 value=p1,p2');
});

Then(literal('終了コード 2 で stderr に "error: csv quote is invalid line=2 path: map.csv" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: csv quote is invalid line=2 path: map.csv');
});

Then(literal('終了コード 2 で stderr に "error: job map header mismatch missing=script path: map.csv" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: job map header mismatch missing=script path: map.csv');
});

Then(literal('終了コード 2 で stderr に "error: job map header mismatch missing=user path: map.csv" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: job map header mismatch missing=user path: map.csv');
});

Then(literal('終了コード 2 で stderr に "error: host is empty line=2 job_id=JOB001 value=" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: host is empty line=2 job_id=JOB001 value=');
});

Then(literal('終了コード 2 で stderr に "error: column count mismatch line=2 expected=9 actual=8" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: column count mismatch line=2 expected=9 actual=8');
});

Then(literal('終了コード 0 で stderr に "warn: unknown column column=impl_version path: map.csv" が出る'), function () {
  assertExit(this, 0);
  assertStderrIncludes(this, 'warn: unknown column column=impl_version path: map.csv');
});

Then(literal('終了コード 0 で stderr に "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" が出る'), function () {
  assertExit(this, 0);
  assertStderrIncludes(this, 'warn: credential_ref looks like a secret or path line=2 job_id=JOB001');
});

// ---- spec event 20260921_100000_feedback_impl_feedback_eff24f55 で追加された Scenario の step(S4 attempt 5 再実行で実装) ----
// keyword の And / But は直前の step 種別に従うが、Then として登録する(cucumber は種別を区別しない)。

Then(literal('終了コード 0 で stdout に "rows=1" が出る'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'rows=1');
});

Then(literal("stderr に 'info: resolved job_id=TOMM0410010100 host=督促AP user=saiken exec=ssh work_dir=G:\\scripts script=G:\\scripts\\xxx.bat fixed_params=[\"param1\",\"param2\",\"param3\"] hang_detect_limit_minutes=60' が出る"), function () {
  assertStderrIncludes(this, 'info: resolved job_id=TOMM0410010100 host=督促AP user=saiken exec=ssh work_dir=G:\\scripts script=G:\\scripts\\xxx.bat fixed_params=["param1","param2","param3"] hang_detect_limit_minutes=60');
});

Then(literal('stderr に "error:" で始まる行は出ない'), function () {
  assertNoStderrLineStartingWith(this, 'error:');
});

Then(literal('終了コード 0 で stdout に "rows=1" が出て、stderr に "error:" で始まる行は出ない'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'rows=1');
  assertNoStderrLineStartingWith(this, 'error:');
});

Then(literal('終了コード 2 で stderr に "error: work_dir is empty line=2 job_id=JOB001 value=" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: work_dir is empty line=2 job_id=JOB001 value=');
});

Then(literal('終了コード 0 で stdout は "map_path: <path>" "rows=0" "map_version=-" の 3 行である'), function () {
  assertExit(this, 0);
  assert.deepEqual(stdoutLines(this), [`map_path: ${MAP_NAME}`, 'rows=0', 'map_version=-']);
});

Then(literal('終了コード 2 で stderr に "error: nul byte is not allowed line=2 path: map.csv" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: nul byte is not allowed line=2 path: map.csv');
});

Then(literal('stderr に "csv quote is invalid" を含む行は出ない'), function () {
  assertNoStderrLineIncluding(this, 'csv quote is invalid');
});

Then(literal('終了コード 2 で stderr に "error: encoding is not utf-8 line=2 path: map.csv" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: encoding is not utf-8 line=2 path: map.csv');
});

Then(literal('終了コード 2 で stderr に "error: byte order mark is not allowed line=1 path: map.csv" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: byte order mark is not allowed line=1 path: map.csv');
});

Then(literal('stderr に "job map header mismatch" を含む行は出ない'), function () {
  assertNoStderrLineIncluding(this, 'job map header mismatch');
});

Then(literal('終了コード 2 で stderr に "error: carriage return is not allowed line=1 path: map.csv" と "error: carriage return is not allowed line=2 path: map.csv" と "hint: use LF line endings" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: carriage return is not allowed line=1 path: map.csv');
  assertStderrIncludes(this, 'error: carriage return is not allowed line=2 path: map.csv');
  assertStderrIncludes(this, 'hint: use LF line endings');
});

Then(literal('終了コード 2 で stderr に "error: column count mismatch line=2 expected=5 actual=1" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: column count mismatch line=2 expected=5 actual=1');
});

Then(literal('終了コード 2 で stderr に "error: duplicate column column=job_id path: map.csv" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: duplicate column column=job_id path: map.csv');
});

Then(literal('終了コード 0 で stderr に "info: resolved job_id=J1" と "work_dir=/old" を含む行が出る'), function () {
  // 差し替えは実際に起きている(最終名の出現を捉えて mv した)。結果は差し替え前の内容だけから作られる
  assert.equal(this.swapDone, true, 'the map file should have been swapped while the snapshot existed');
  assert.equal(fs.existsSync(this.swapPlan.nextPath), false, 'next.csv should have been moved onto map.csv');
  assertExit(this, 0);
  const matched = stderrLines(this).filter((line) => line.includes('info: resolved job_id=J1') && line.includes('work_dir=/old'));
  assert.equal(matched.length, 1, `stderr should have one resolved line for J1\n--- stderr ---\n${this.result.stderr}`);
  assert.equal(this.result.stderr.includes('J2'), false, `stderr should not resolve the swapped-in row\n--- stderr ---\n${this.result.stderr}`);
});

Then(literal('stdout の "map_path:" は map.csv のパスで、TMPDIR 配下のパスは stdout / stderr に出ない'), function () {
  assertStdoutIncludes(this, `map_path: ${MAP_NAME}`);
  assert.equal(this.result.stdout.includes(this.tmpDir), false, `stdout should not include TMPDIR path\n--- stdout ---\n${this.result.stdout}`);
  assert.equal(this.result.stderr.includes(this.tmpDir), false, `stderr should not include TMPDIR path\n--- stderr ---\n${this.result.stderr}`);
});

Then(literal('終了後に TMPDIR 配下に relay-gate の一時ファイルは残っていない'), function () {
  const leftovers = fs.readdirSync(this.tmpDir).filter((name) => name.startsWith(SNAPSHOT_PREFIX));
  assert.deepEqual(leftovers, []);
});

Then(literal('終了コード 6 で stderr に "error: config snapshot failed path: map.csv" と "hint: check TMPDIR is writable" が出る'), function () {
  assertExit(this, 6);
  assertStderrIncludes(this, 'error: config snapshot failed path: map.csv');
  assertStderrIncludes(this, 'hint: check TMPDIR is writable');
});

Then(literal('stdout は 0 行である'), function () {
  assert.deepEqual(stdoutLines(this), []);
});

Then(literal('終了コード 6 で stderr に "error: internal command failed commands=<差し替えたコマンド名> path: map.csv" が出る'), function () {
  assertExit(this, 6);
  assertStderrIncludes(this, `error: internal command failed commands=${this.replacedCommand} path: map.csv`);
});

Then(literal('stdout は 0 行で、stderr に "error:" で始まる行はその 1 行だけである'), function () {
  assert.deepEqual(stdoutLines(this), []);
  const errors = stderrLines(this).filter((line) => line.startsWith('error:'));
  assert.deepEqual(errors, [`error: internal command failed commands=${this.replacedCommand} path: map.csv`]);
});

Then(literal("終了コード 2 で stderr に 'warn: unknown column column=note\\u001b[31m path: map.csv' と 'error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=6\\t0' が出る"), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'warn: unknown column column=note\\u001b[31m path: map.csv');
  assertStderrIncludes(this, 'error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=6\\t0');
});

Then(literal('stderr のどの行にも生の ESC・タブは含まれない'), function () {
  const raw = stderrLines(this).filter((line) => /[\u001b\t]/.test(line));
  assert.deepEqual(raw, [], `stderr should not include raw ESC or TAB\n--- stderr ---\n${this.result.stderr}`);
});
// ---- spec event 20260923_112000_feedback_impl_feedback_eff24f55_cycle2 で追加・変更された Scenario の step(S4 attempt 6 再実行で実装) ----
// keyword の And / But は直前の step 種別に従うが、Given 以外は Then として登録する(cucumber は種別を区別しない)。

// 仕様: lines= は初出行を含む出現順の全行番号(tier-facade.md 設定契約 job_id 行)
Then(literal('終了コード 2 で stderr に "error: duplicate job_id job_id=JOB001 lines=2,5" が出る(初出行 2 を含む)'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: duplicate job_id job_id=JOB001 lines=2,5');
});

// 仕様: 重複した job_id ごとに 1 行
Then(literal('stderr に "duplicate job_id" を含む行は 1 行だけである'), function () {
  const matched = stderrLines(this).filter((line) => line.includes('duplicate job_id'));
  assert.equal(matched.length, 1, `stderr should have exactly one duplicate job_id line\n--- stderr ---\n${this.result.stderr}`);
});

Given(literal('map.csv の 2・3・4 行目が job_id=JOB001 である'), function () {
  writeMap(this, [HEADER_7, row7('JOB001'), row7('JOB001'), row7('JOB001')]);
});

Then(literal('終了コード 2 で stderr に "error: duplicate job_id job_id=JOB001 lines=2,3,4" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: duplicate job_id job_id=JOB001 lines=2,3,4');
});

// credential_ref の値は stdout / stderr のどこにも出さない(契約 conventions.credentials)
function assertValueAbsent(world, value) {
  assert.equal(world.result.stdout.includes(value), false, `stdout should not include "${value}"\n--- stdout ---\n${world.result.stdout}`);
  assert.equal(world.result.stderr.includes(value), false, `stderr should not include "${value}"\n--- stderr ---\n${world.result.stderr}`);
}

Then(literal('stdout と stderr のどこにも "/home/batch/.ssh/id_green" は出ない'), function () {
  assertValueAbsent(this, '/home/batch/.ssh/id_green');
});

Given(literal('map.csv の 2 行目(JOB001)の credential_ref が "ssh key green"(空白を含み、"/" も "BEGIN" も含まない)である'), function () {
  writeMap(this, [HEADER_9, row9('JOB001', { credentialRef: 'ssh key green' })]);
});

// 仕様: 1 行に複数の理由が重なっても warn は 1 行
Then(literal('終了コード 0 で stderr に "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" が 1 行だけ出る'), function () {
  assertExit(this, 0);
  const expected = 'warn: credential_ref looks like a secret or path line=2 job_id=JOB001';
  const matched = stderrLines(this).filter((line) => line.includes('credential_ref'));
  assert.deepEqual(matched, [expected], `stderr should have exactly one credential_ref warn line\n--- stderr ---\n${this.result.stderr}`);
});

Then(literal('stdout と stderr のどこにも "ssh key green" は出ない'), function () {
  assertValueAbsent(this, 'ssh key green');
});

Given(literal('map.csv の 2 行目(JOB001)の credential_ref が BEGIN_KEY である'), function () {
  writeMap(this, [HEADER_9, row9('JOB001', { credentialRef: 'BEGIN_KEY' })]);
});

Then(literal('stdout と stderr のどこにも "BEGIN_KEY" は出ない'), function () {
  assertValueAbsent(this, 'BEGIN_KEY');
});
