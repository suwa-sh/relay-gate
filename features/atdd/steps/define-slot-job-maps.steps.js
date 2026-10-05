// ATDD(①)step definition。uc_id=eff24f55 / branch_slug=define-slot-job-maps(S2 skeleton を S7 atdd で実装)。
// source: features/atdd/SPEC-004-04.feature(@atdd_SPEC-004-04-4)/ features/atdd/SPEC-008-05.feature(@atdd_SPEC-008-05-2)
//   対象は uc-map eff24f55 の atdd_scenarios に列挙された 2 Scenario のみ(同 feature の他 Scenario は他 UC の担当)。
// step 文言は feature から転写したリテラルを正規表現で完全一致させる。
// World / Before / After は features/atdd/steps/configure-feature-flags.steps.js が定義済み(同一 require glob で読まれる)。
// ここでは setWorldConstructor を呼ばない(World は 1 つだけ)。
//
// I/O 境界は実体で検証する(features/uc/steps/define-slot-job-maps.steps.js のハーネスを踏襲):
//   World の sandbox root(Scenario ごとの一時ディレクトリ)配下に、仕様の絶対パス(/etc/relay-gate/green-job-map.csv)と
//   同じ相対位置でジョブマップの実ファイルを置き、facade/bin/validate-config.sh を実プロセスとして起動する。
//   実行時に外部接続(DB・ネットワーク)は行わない。tier 実装は変更しない。
//
// When「設定を検証する」(@atdd_SPEC-004-04-4)は configure-feature-flags.steps.js の定義を共有する。
//   同じ文言をここで再定義すると ambiguous step になるため定義しない。Given が this.validation に
//   検証種別(job-map)と対象パスを置き、共有 step が --job-map で起動する。
// UC 横断 Scenario の扱い: docs/impl/latest/eff24f55/issues/20260919_161456_cross-uc-scenarios.md
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const REPO_ROOT = path.resolve(__dirname, '../../..');
const VALIDATE_CONFIG = path.join(REPO_ROOT, 'facade/bin/validate-config.sh');

// 仕様の例示値(spec.md E2E 完了条件の絶対パス)
const SPEC_GREEN_MAP = '/etc/relay-gate/green-job-map.csv';

// 元資料どおりの 7 列と、末尾の任意 2 列(spec.md「ジョブマップ解決条件」。契約は合計 9 列)
const HEADER_7 = 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes';
const OPTIONAL_COLUMNS = ['credential_ref', 'map_version'];
const CONTRACT_COLUMNS = [...HEADER_7.split(','), ...OPTIONAL_COLUMNS];

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

function row7(jobId, hang) {
  return `${jobId},host-green-01,batch,/var/app/work,/opt/app/bin/${jobId.toLowerCase()}.sh,"[]",${hang}`;
}

// ジョブマップを sandbox 配下の実ファイルとして書く(lines[0] がヘッダー = 1 行目)
function writeMap(world, lines) {
  const file = world.sandbox(SPEC_GREEN_MAP);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, lines.join('\n') + '\n');
  world.mapLines = lines;
  return file;
}

function runJobMap(world, extraArgs = []) {
  const file = world.sandbox(SPEC_GREEN_MAP);
  assert.ok(fs.existsSync(file), `job map fixture should exist: ${SPEC_GREEN_MAP}`);
  const proc = spawnSync(VALIDATE_CONFIG, ['--job-map', file, ...extraArgs], {
    cwd: world.root,
    encoding: 'utf8',
    env: { ...process.env, RELAY_GATE_CONFIG_DIR: world.configDir },
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  return { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
}

function outputDump(result) {
  return `--- stdout ---\n${result.stdout}\n--- stderr ---\n${result.stderr}`;
}

function lines(world, text) {
  return world.unsandbox(text).split('\n').filter((line) => line.length > 0);
}

// 検証を通過したこと: 終了コード 0、error 行なし、未知列の警告なし
function assertAccepted(world, result, label) {
  assert.equal(result.status, 0, `${label}: exit code\n${outputDump(result)}`);
  const stderr = lines(world, result.stderr);
  assert.deepEqual(stderr.filter((line) => line.startsWith('error:')), [], `${label}\n${outputDump(result)}`);
  assert.deepEqual(stderr.filter((line) => line.startsWith('warn: unknown column')), [], `${label}\n${outputDump(result)}`);
}

function assertStdoutIncludes(world, result, expected, label) {
  assert.ok(lines(world, result.stdout).includes(expected), `${label}: stdout should include line "${expected}"\n${outputDump(result)}`);
}

// ---- @atdd_SPEC-004-04-4 ----

Given(literal('credential_ref と map_version の列を持たないジョブマップ'), function () {
  // 元資料どおりの 7 列だけのジョブマップ(任意 2 列を持たない)
  const file = writeMap(this, [HEADER_7, row7('JOB001', '60'), row7('JOB002', '0')]);
  const header = this.mapLines[0].split(',');
  for (const column of OPTIONAL_COLUMNS) {
    assert.ok(!header.includes(column), `fixture header must not contain ${column}`);
  }
  // 共有 step「設定を検証する」に検証種別を渡す(configure-feature-flags.steps.js の validationArgs)
  this.validation = { kind: 'job-map', path: file };
});

Then(literal('エラーにならず、両列がある場合は末尾の任意列として読み込まれる'), function () {
  // 前半「エラーにならず」: When が検証した 7 列のジョブマップの結果
  assertAccepted(this, this.result, 'without optional columns');
  assertStdoutIncludes(this, this.result, 'rows=2', 'without optional columns');
  // map_version 列が無いときは "-"(spec.md Scenario「credential_ref と map_version の列が無くてもエラーにならない」)
  assertStdoutIncludes(this, this.result, 'map_version=-', 'without optional columns');

  // 後半「両列がある場合は末尾の任意列として読み込まれる」: 同じジョブマップの末尾に両列を足して再検証する
  const [header, ...rows] = this.mapLines;
  writeMap(this, [`${header},${OPTIONAL_COLUMNS.join(',')}`, ...rows.map((row) => `${row},ssh-key-green,map-v3`)]);
  const withColumns = runJobMap(this);
  assertAccepted(this, withColumns, 'with optional columns');
  assertStdoutIncludes(this, withColumns, 'rows=2', 'with optional columns');
  // 読み込まれた証拠: 末尾列の値が出力に現れる(未知列なら warn: unknown column になり assertAccepted が落ちる)
  assertStdoutIncludes(this, withColumns, 'map_version=map-v3', 'with optional columns');
});

// ---- @atdd_SPEC-008-05-2 ----
// S0 再実行(P7)で Scenario 文言が変わった(旧: 「hang_detect_limit_minutes を調整した / 調整の記録を確認する /
// 調整日時と調整根拠(警告時経過時間)は適用構成文書に残り、ジョブマップの列には持たない」)。
// 新文言は relay-gate が読まない適用構成文書を判定対象に含めない(@manual の SPEC-008-05-3 へ分離)ため、
// 旧 step にあった代替判定は不要になり、「ジョブマップの列に調整記録の置き場が無い」ことだけを実体で確認する。

// 調整記録らしい列(ハーネスが対照用に足す列名。契約の 9 列には存在しない)
const ADJUSTMENT_RECORD_COLUMNS = ['adjusted_at', 'adjust_reason_elapsed_minutes'];
// 調整記録(調整日時・調整根拠)を保持する列名とみなす語(列名にこれらを含めば調整記録の列と判定する)
const ADJUSTMENT_RECORD_WORDS = ['adjust', 'reason', 'tuned', 'changed_at', 'updated_at', 'history'];

Given(literal('slot ジョブマップが定義されている'), function () {
  // 契約どおりの 9 列(元資料の 7 列 + 末尾の任意 2 列)で、hang_detect_limit_minutes を持つ有効なジョブマップ
  writeMap(this, [CONTRACT_COLUMNS.join(','), `${row7('JOB001', '60')},ssh-key-green,map-v3`, `${row7('JOB002', '0')},ssh-key-green,map-v3`]);
  this.jobMapHeader = this.mapLines[0].split(',');
  assert.ok(this.jobMapHeader.includes('hang_detect_limit_minutes'), 'fixture must have hang_detect_limit_minutes');
});

When(literal('ジョブマップの列を確認する'), function () {
  // 1. 定義したジョブマップをそのまま検証し、列が契約どおりに読まれる(未知列の警告が無い)ことを結果に採る
  this.defined = { header: this.jobMapHeader, result: runJobMap(this, ['--verbose']) };

  // 2. 対照: 調整記録(調整日時・調整根拠)の列を足したジョブマップの検証結果も採る(契約外の列として扱われるか)
  const [header, ...rows] = this.mapLines;
  writeMap(this, [`${header},${ADJUSTMENT_RECORD_COLUMNS.join(',')}`, ...rows.map((row) => `${row},2026-08-30T11:30:00+09:00,75`)]);
  this.withRecordColumns = runJobMap(this);
});

Then(literal('hang_detect_limit_minutes の調整記録(調整日時・調整根拠)を保持する列は存在しない'), function () {
  // a. 定義したジョブマップの列は契約の 9 列に閉じ、調整記録らしい列名を含まない
  for (const column of this.defined.header) {
    assert.ok(CONTRACT_COLUMNS.includes(column), `job map header must be a contract column: ${column}`);
    const lowered = column.toLowerCase();
    assert.ok(!ADJUSTMENT_RECORD_WORDS.some((word) => lowered.includes(word)), `job map header must not hold an adjustment record: ${column}`);
  }
  for (const column of ADJUSTMENT_RECORD_COLUMNS) {
    assert.ok(!CONTRACT_COLUMNS.includes(column), `${column} must not be a contract column`);
  }
  // b. その列だけで検証を通過し、hang_detect_limit_minutes は値として解決される(調整記録なしで完結する)
  assertAccepted(this, this.defined.result, 'defined job map');
  const resolved = lines(this, this.defined.result.stderr).filter((line) => line.includes('info: resolved job_id=JOB001'));
  assert.equal(resolved.length, 1, `stderr should have exactly one resolved line for JOB001\n${outputDump(this.defined.result)}`);
  assert.ok(resolved[0].includes('hang_detect_limit_minutes=60'), outputDump(this.defined.result));

  // c. 調整記録の列をジョブマップに足すと、契約外の未知列として警告される(= ジョブマップに調整記録の列は存在しない)
  const stderr = lines(this, this.withRecordColumns.stderr);
  for (const column of ADJUSTMENT_RECORD_COLUMNS) {
    const expected = `warn: unknown column column=${column} path: ${SPEC_GREEN_MAP}`;
    assert.ok(stderr.includes(expected), `stderr should include line "${expected}"\n${outputDump(this.withRecordColumns)}`);
  }
});
