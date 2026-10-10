// UC BDD(②)step definition。uc_id=dcd8234d / branch_slug=define-crosscheck-job-map-and-comparison-definitions(S2 skeleton を S6 uc-bdd で実装)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md#E2E完了条件(BDD)
// step 文言は feature から転写したリテラルを正規表現で完全一致させる(DocString 付き step も文言は同じ)。
// World / Before / After は features/uc/steps/configure-feature-flags.steps.js が定義済み(同一 require glob で読まれる)。
// ここでは setWorldConstructor を呼ばない(World は 1 つだけ)。
//
// I/O 境界は実体で検証する: World の sandbox root(Scenario ごとの一時ディレクトリ)配下に、feature の絶対パス
// (/etc/relay-gate/*.csv、/opt/compare/*.sh)と同じ相対位置で実ファイルを置き、facade/bin/validate-config.sh を実プロセスとして
// 起動する(facade の handler 登録 hook により rapid-crosscheck / final-crosscheck の検査が同一プロセスに source される)。
// 出力中の sandbox root 接頭辞は World.unsandbox で落として feature の文言と突き合わせる。
// Scenario は独立しているため、「前シナリオの ...」「crosscheck-job-map.csv の JOB002 行 ...」のように SPEC-004-01 の fixture を
// 前提とする Given は、同じ内容の基準 fixture(宣言 3 行 + ヘッダー + JOB001 + JOB002 / ヘッダー + table 行 + file 行)を
// 書き直してから差分を加える。
// UC 横断 Scenario の扱い: docs/impl/latest/dcd8234d/issues/20261010_084142_cross-uc-scenarios.md
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const REPO_ROOT = path.resolve(__dirname, '../../..');
const VALIDATE_CONFIG = path.join(REPO_ROOT, 'facade/bin/validate-config.sh');

// feature に書かれた絶対パス(仕様の例示値)
const SPEC_MAP = '/etc/relay-gate/crosscheck-job-map.csv';
const SPEC_CATALOG = '/etc/relay-gate/target-catalog.csv';
const SPEC_COMPARE_DIR = '/opt/compare';
const SPEC_COMPARE = '/opt/compare/compare.sh';
const SPEC_COMPARE_V2 = '/opt/compare/compare-v2.sh';
const SPEC_COMPARE_V3 = '/opt/compare/compare-v3.sh';
const SPEC_MISSING = '/opt/compare/missing.sh';

const MAP_HEADER = 'job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version';
const CATALOG_HEADER = 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling';

// 比較ツールは外部システム(どの UC の成果物でもない)。sandbox に exit 0 の実行可能スタブを置く fixture で足りる。
// 根拠: docs/impl/latest/dcd8234d/issues/20261010_084142_cross-uc-scenarios.md(#1)
const COMPARE_STUB = '#!/usr/bin/env bash\nexit 0\n';

// 「管理 DB への接続は行われない」の観測: PATH 先頭に psql の番兵を置き、起動されたら記録を残して失敗させる
const PSQL_SENTINEL = '#!/usr/bin/env bash\nmkdir -p "$RELAY_GATE_UC_BDD_VAR_DIR"\nprintf \'%s\\n\' "$*" >>"$RELAY_GATE_UC_BDD_VAR_DIR/psql.invoked"\nexit 97\n';

// 「relay-gate のスクリプトは変更されていない」の観測対象(検証コマンドが source する tier 実装の全体)
const SCRIPT_DIRS = ['facade/bin', 'facade/src', 'rapid-crosscheck/src', 'final-crosscheck/src'];

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

// ---- fixture helpers ----

// feature の DocString / 行に書かれた仕様の絶対パスを sandbox 配下へ写像する(/data/out/... のような対象識別子は触らない)
function sandboxText(world, text) {
  return text.split('/etc/relay-gate/').join(world.sandbox('/etc/relay-gate') + '/').split(`${SPEC_COMPARE_DIR}/`).join(world.sandbox(SPEC_COMPARE_DIR) + '/');
}

function writeLines(world, specPath, lines) {
  const file = world.sandbox(specPath);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, lines.map((line) => sandboxText(world, line)).join('\n') + '\n');
  world.csvLines = world.csvLines || {};
  world.csvLines[specPath] = lines;
  return file;
}

function readLines(world, specPath) {
  const lines = world.csvLines && world.csvLines[specPath];
  assert.ok(lines, `fixture must be written first: ${specPath}`);
  return lines;
}

function writeCompareStub(world, specPath) {
  const file = world.sandbox(specPath);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, COMPARE_STUB, { mode: 0o755 });
  fs.accessSync(file, fs.constants.X_OK);
}

// SPEC-004-01 と同じ基準 fixture(宣言 3 行 + ヘッダー + JOB001(物理行 5)+ JOB002(物理行 6))
function baselineMapLines() {
  return [
    '# exit_code_contract=0:OK,3:NG,6:ERROR',
    `# target_catalog_path=${SPEC_CATALOG}`,
    '# catalog_version=v1',
    MAP_HEADER,
    `JOB001,job,output.csv,${SPEC_COMPARE},--blue {blue} --green {green},v1`,
    `JOB002,job,summary.tsv,${SPEC_COMPARE_V2},--blue {blue} --green {green} --ignore-header,v1`,
  ];
}

// SPEC-004-01 と同じ基準 fixture(ヘッダー + table 行(物理行 2)+ file 行(物理行 3))
function baselineCatalogLines() {
  return [CATALOG_HEADER, 'v1,table,SALES_DAILY,key=sales_id,column=business_date', 'v1,file,/data/out/summary_{business_date}.tsv,-,filename'];
}

function arrangeBaseline(world) {
  writeCompareStub(world, SPEC_COMPARE);
  writeCompareStub(world, SPEC_COMPARE_V2);
  writeLines(world, SPEC_MAP, baselineMapLines());
  writeLines(world, SPEC_CATALOG, baselineCatalogLines());
}

// 基準 fixture の物理行 N(1 始まり)を差し替える
function replaceLine(world, specPath, lineNo, replacer) {
  const lines = [...readLines(world, specPath)];
  const index = lineNo - 1;
  assert.ok(index >= 0 && index < lines.length, `line ${lineNo} must exist in ${specPath}`);
  lines[index] = replacer(lines[index]);
  writeLines(world, specPath, lines);
}

// ---- run helpers ----

function installPsqlSentinel(world) {
  const binDir = path.join(world.root, 'sentinel-bin');
  fs.mkdirSync(binDir, { recursive: true });
  fs.writeFileSync(path.join(binDir, 'psql'), PSQL_SENTINEL, { mode: 0o755 });
  return binDir;
}

function scriptsSnapshot() {
  const entries = [];
  const walk = (dir) => {
    for (const name of fs.readdirSync(dir).sort()) {
      const file = path.join(dir, name);
      if (fs.statSync(file).isDirectory()) {
        walk(file);
      } else {
        entries.push(`${path.relative(REPO_ROOT, file)} ${crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')}`);
      }
    }
  };
  for (const dir of SCRIPT_DIRS) {
    walk(path.join(REPO_ROOT, dir));
  }
  return entries.join('\n');
}

function spawnEnv(world) {
  return {
    ...process.env,
    PATH: `${installPsqlSentinel(world)}:${process.env.PATH}`,
    RELAY_GATE_CONFIG_DIR: world.configDir,
    RELAY_GATE_UC_BDD_VAR_DIR: world.varDir,
  };
}

function runValidateConfig(world, option, specPath, extraArgs = []) {
  const file = world.sandbox(specPath);
  assert.ok(fs.existsSync(file), `fixture should exist: ${specPath}`);
  if (!world.scriptsBefore) {
    world.scriptsBefore = scriptsSnapshot();
  }
  const proc = spawnSync(VALIDATE_CONFIG, [option, file, ...extraArgs], { cwd: world.root, encoding: 'utf8', env: spawnEnv(world) });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  world.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
  return world.result;
}

function runCrosscheckMap(world, specPath = SPEC_MAP) {
  return runValidateConfig(world, '--crosscheck-job-map', specPath);
}

function runTargetCatalog(world, specPath = SPEC_CATALOG) {
  return runValidateConfig(world, '--target-catalog', specPath);
}

// ---- assert helpers ----

function outputDump(result) {
  return `--- stdout ---\n${result.stdout}\n--- stderr ---\n${result.stderr}`;
}

function assertExit(result, code) {
  assert.equal(result.status, code, `exit code\n${outputDump(result)}`);
}

function stdoutLines(world, result = world.result) {
  return world.unsandbox(result.stdout).split('\n').filter((line) => line.length > 0);
}

function stderrLines(world, result = world.result) {
  return world.unsandbox(result.stderr).split('\n').filter((line) => line.length > 0);
}

function assertStdoutIncludes(world, expected, result = world.result) {
  assert.ok(stdoutLines(world, result).includes(expected), `stdout should include line "${expected}"\n${outputDump(result)}`);
}

function assertStderrIncludes(world, expected, result = world.result) {
  assert.ok(stderrLines(world, result).includes(expected), `stderr should include line "${expected}"\n${outputDump(result)}`);
}

// stdout に expected の各行が「この順で」現れること(行の完全一致。間に他の行が挟まってもよい)
function assertStdoutInOrder(world, expected, result = world.result) {
  const lines = stdoutLines(world, result);
  let cursor = 0;
  for (const line of expected) {
    const found = lines.indexOf(line, cursor);
    assert.notEqual(found, -1, `stdout should include line "${line}" after position ${cursor}\n${outputDump(result)}`);
    cursor = found + 1;
  }
}

function assertValid(world, result = world.result) {
  assertExit(result, 0);
  assertStdoutIncludes(world, 'status=valid', result);
  const errors = stderrLines(world, result).filter((line) => line.startsWith('error:'));
  assert.deepEqual(errors, [], outputDump(result));
}

// ---- Given ----

Given(literal('/etc/relay-gate/crosscheck-job-map.csv の内容が次である'), function (docString) {
  writeLines(this, SPEC_MAP, docString.split('\n'));
});

Given(literal('/opt/compare/compare.sh と /opt/compare/compare-v2.sh が実行可能である'), function () {
  // 比較ツールは外部システム。sandbox に実行可能なスタブを置く(ハーネス注入ではなく fixture 配置)。
  // 根拠: docs/impl/latest/dcd8234d/issues/20261010_084142_cross-uc-scenarios.md(#1)
  writeCompareStub(this, SPEC_COMPARE);
  writeCompareStub(this, SPEC_COMPARE_V2);
});

Given(literal('/etc/relay-gate/target-catalog.csv の内容が次である'), function (docString) {
  writeLines(this, SPEC_CATALOG, docString.split('\n'));
});

Given(literal('crosscheck-job-map.csv の JOB002 行の compare_command を /opt/compare/compare-v3.sh に変更し、実行可能である'), function () {
  arrangeBaseline(this);
  writeCompareStub(this, SPEC_COMPARE_V3);
  this.job001Before = readLines(this, SPEC_MAP)[4];
  replaceLine(this, SPEC_MAP, 6, (line) => {
    assert.ok(line.startsWith('JOB002,'), `line 6 should be JOB002: ${line}`);
    return line.replace(SPEC_COMPARE_V2, SPEC_COMPARE_V3);
  });
  assert.ok(fs.readFileSync(this.sandbox(SPEC_MAP), 'utf8').includes(this.sandbox(SPEC_COMPARE_V3)));
});

Given(literal('crosscheck-job-map.csv の JOB002 行の compare_targets セルが二重引用符で囲まれた `"output.csv,summary.csv"` である(カンマを含むセル)'), function () {
  arrangeBaseline(this);
  replaceLine(this, SPEC_MAP, 6, (line) => {
    assert.ok(line.startsWith('JOB002,job,summary.tsv,'), `line 6 should be JOB002: ${line}`);
    return line.replace('JOB002,job,summary.tsv,', 'JOB002,job,"output.csv,summary.csv",');
  });
  assert.ok(fs.readFileSync(this.sandbox(SPEC_MAP), 'utf8').includes('"output.csv,summary.csv"'));
});

Given(literal('target-catalog.csv の compare_condition セルが二重引用符で囲まれた `"key=sales_id,branch_id"` である'), function () {
  // table 行(物理行 2)の compare_condition を引用セルにする
  replaceLine(this, SPEC_CATALOG, 2, (line) => line.replace(',key=sales_id,', ',"key=sales_id,branch_id",'));
  assert.ok(fs.readFileSync(this.sandbox(SPEC_CATALOG), 'utf8').includes('"key=sales_id,branch_id"'));
});

Given(literal('前シナリオの crosscheck-job-map.csv(宣言 3 行 + ヘッダー + JOB001 + JOB002 の 6 行)の 6 行目(JOB002 行)を JOB001 行の複製に置き換える'), function () {
  arrangeBaseline(this);
  const lines = readLines(this, SPEC_MAP);
  assert.equal(lines.length, 6);
  replaceLine(this, SPEC_MAP, 6, () => lines[4]);
  assert.equal(readLines(this, SPEC_MAP)[5], readLines(this, SPEC_MAP)[4]);
});

Given(literal('crosscheck-job-map.csv の JOB001 行の compare_command が /opt/compare/missing.sh で存在しない'), function () {
  arrangeBaseline(this);
  replaceLine(this, SPEC_MAP, 5, (line) => line.replace(SPEC_COMPARE, SPEC_MISSING));
  assert.equal(fs.existsSync(this.sandbox(SPEC_MISSING)), false);
});

Given(literal('crosscheck-job-map.csv のヘッダー行が `job_id,host,comparison_type,compare_targets,compare_command,compare_options,definition_version` である(slot ジョブマップの host 列が混入している)'), function () {
  arrangeBaseline(this);
  replaceLine(this, SPEC_MAP, 4, (line) => {
    assert.equal(line, MAP_HEADER);
    return 'job_id,host,comparison_type,compare_targets,compare_command,compare_options,definition_version';
  });
});

Given(literal('前シナリオの target-catalog.csv(ヘッダー + 2 行)の 3 行目(file 行)の target_type を view に変える'), function () {
  arrangeBaseline(this);
  replaceLine(this, SPEC_CATALOG, 3, (line) => {
    assert.ok(line.startsWith('v1,file,'), `line 3 should be the file row: ${line}`);
    return line.replace('v1,file,', 'v1,view,');
  });
});

// ---- When ----

When(literal('基盤適用設計者が `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する'), function () {
  this.firstResult = { ...runCrosscheckMap(this) };
});

When(literal('続けて `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する'), function () {
  this.secondResult = { ...runTargetCatalog(this) };
});

When(literal('`validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` を実行する'), function () {
  runCrosscheckMap(this);
});

When(literal('`validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.csv` と `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する'), function () {
  this.bothResults = {
    map: { ...runCrosscheckMap(this) },
    catalog: { ...runTargetCatalog(this) },
  };
});

When(literal('`validate-config.sh --target-catalog /etc/relay-gate/target-catalog.csv` を実行する'), function () {
  runTargetCatalog(this);
});

// ---- Then ----

Then(literal('1 回目は終了コード 0 で stdout に `config=crosscheck-job-map`、`path: /etc/relay-gate/crosscheck-job-map.csv`、`rows=2`、`target_catalog_path: /etc/relay-gate/target-catalog.csv`、`catalog_version=v1`、`exit_code_contract=0:OK,3:NG,6:ERROR`、`status=valid` がこの順で出る'), function () {
  assertExit(this.firstResult, 0);
  assertStdoutInOrder(
    this,
    [
      'config=crosscheck-job-map',
      `path: ${SPEC_MAP}`,
      'rows=2',
      `target_catalog_path: ${SPEC_CATALOG}`,
      'catalog_version=v1',
      'exit_code_contract=0:OK,3:NG,6:ERROR',
      'status=valid',
    ],
    this.firstResult,
  );
});

Then(literal('2 回目は終了コード 0 で stdout に `config=target-catalog`、`path: /etc/relay-gate/target-catalog.csv`、`rows=2`、`catalog_versions=v1`、`tables=1`、`files=1`、`status=valid` がこの順で出る'), function () {
  assertExit(this.secondResult, 0);
  assertStdoutInOrder(this, ['config=target-catalog', `path: ${SPEC_CATALOG}`, 'rows=2', 'catalog_versions=v1', 'tables=1', 'files=1', 'status=valid'], this.secondResult);
});

Then(literal('管理 DB への接続は行われず、relay-gate のスクリプトは変更されていない'), function () {
  // 管理 DB: PATH 先頭の psql 番兵が一度も起動されていない(起動されれば記録が残り、終了コード 97 で結果も崩れる)
  const invoked = path.join(this.varDir, 'psql.invoked');
  assert.equal(fs.existsSync(invoked), false, `psql must not be invoked by validate-config.sh: ${fs.existsSync(invoked) ? fs.readFileSync(invoked, 'utf8') : ''}`);
  for (const result of [this.firstResult, this.secondResult]) {
    assert.equal(result.stderr.includes('psql'), false, outputDump(result));
  }
  // スクリプト: 検証コマンドが source する tier 実装(bin / src)の内容が実行前後で 1 バイトも変わっていない
  assert.ok(this.scriptsBefore, 'scripts snapshot should be taken before the first run');
  assert.equal(scriptsSnapshot(), this.scriptsBefore, 'relay-gate scripts must not be modified by validate-config.sh');
});

Then(literal('終了コード 0 で `status=valid` が出て、JOB001 の定義は変更されていない'), function () {
  assertValid(this);
  // JOB001 行(物理行 5)は Given で書いた基準どおりのまま(ファイル実体と fixture 記録の両方で確認)
  const fileLines = fs.readFileSync(this.sandbox(SPEC_MAP), 'utf8').split('\n');
  assert.equal(this.unsandbox(fileLines[4]), this.job001Before);
  assert.equal(readLines(this, SPEC_MAP)[4], this.job001Before);
  assert.equal(this.job001Before, `JOB001,job,output.csv,${SPEC_COMPARE},--blue {blue} --green {green},v1`);
});

Then(literal('どちらも終了コード 0 で `status=valid` が出て、囲んだセルはカンマを含む 1 セルとして解析される'), function () {
  for (const key of ['map', 'catalog']) {
    assertValid(this, this.bothResults[key]);
    // 引用セルが 1 セルとして解析されなければ列数不一致の違反になり status=valid にならない。行数も 2 のまま
    assertStdoutIncludes(this, 'rows=2', this.bothResults[key]);
  }
});

Then(literal('slot ジョブマップの読み込みと同じ CSV クォート解析関数が使われ、タブ区切りのファイルは `error: header mismatch` で拒否される'), function () {
  // 前半「同じ CSV クォート解析関数が使われる」は実装の構造であり CLI の実行結果では判定できないため、
  // 「slot ジョブマップと同じ解析結果(カンマを含む引用セル・二重化した引用符を 1 セルとして受理)」と
  // 後半「タブ区切りの拒否」で代替する。根拠: docs/impl/latest/dcd8234d/issues/20261010_084142_cross-uc-scenarios.md(#2)
  // (1) 二重化した引用符を含む引用セル(slot ジョブマップの fixed_params と同じ書式)も 1 セルとして受理される
  const quotedMap = '/etc/relay-gate/crosscheck-job-map-quoted.csv';
  const quotedCatalog = '/etc/relay-gate/target-catalog-quoted.csv';
  writeLines(this, quotedMap, baselineMapLines().map((line) => (line.startsWith('JOB002,job,summary.tsv,') ? line.replace('JOB002,job,summary.tsv,', 'JOB002,job,"summary ""v2"",out.csv",') : line)));
  writeLines(this, quotedCatalog, baselineCatalogLines().map((line) => line.replace(',key=sales_id,', ',"key=""sales_id"",branch_id",')));
  const quotedResults = { map: { ...runCrosscheckMap(this, quotedMap) }, catalog: { ...runTargetCatalog(this, quotedCatalog) } };
  for (const key of ['map', 'catalog']) {
    assertValid(this, quotedResults[key]);
    assertStdoutIncludes(this, 'rows=2', quotedResults[key]);
  }
  // (2) タブ区切りのファイル(カンマをタブに置き換えたもの)は header mismatch で拒否される(終了コード 2)
  const tabMap = '/etc/relay-gate/crosscheck-job-map-tab.csv';
  const tabCatalog = '/etc/relay-gate/target-catalog-tab.csv';
  writeLines(this, tabMap, baselineMapLines().map((line) => (line.startsWith('#') ? line : line.split(',').join('\t'))));
  writeLines(this, tabCatalog, baselineCatalogLines().map((line) => line.split(',').join('\t')));
  const tabResults = { map: { ...runCrosscheckMap(this, tabMap) }, catalog: { ...runTargetCatalog(this, tabCatalog) } };
  for (const key of ['map', 'catalog']) {
    const result = tabResults[key];
    assertExit(result, 2);
    const mismatch = stderrLines(this, result).filter((line) => line.startsWith('error: header mismatch '));
    assert.equal(mismatch.length, 1, `stderr should have one header mismatch line (${key})\n${outputDump(result)}`);
    assert.equal(stdoutLines(this, result).includes('status=valid'), false, outputDump(result));
  }
});

Then(literal('終了コードは 2 で stderr に `error: duplicate job_id job_id=JOB001 lines=5,6` が出る(初出行 5 を含む)'), function () {
  assertExit(this.result, 2);
  assertStderrIncludes(this, 'error: duplicate job_id job_id=JOB001 lines=5,6');
});

Then(literal('終了コードは 2 で stderr に `error: compare_command is not executable line=5 job_id=JOB001 value=/opt/compare/missing.sh` が出る'), function () {
  assertExit(this.result, 2);
  assertStderrIncludes(this, `error: compare_command is not executable line=5 job_id=JOB001 value=${SPEC_MISSING}`);
});

Then(literal('終了コードは 2 で stderr に `error: header mismatch expected=job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version actual=job_id,host,comparison_type,compare_targets,compare_command,compare_options,definition_version path: /etc/relay-gate/crosscheck-job-map.csv` が出る'), function () {
  assertExit(this.result, 2);
  assertStderrIncludes(
    this,
    `error: header mismatch expected=${MAP_HEADER} actual=job_id,host,comparison_type,compare_targets,compare_command,compare_options,definition_version path: ${SPEC_MAP}`,
  );
});

Then(literal('終了コードは 2 で stderr に `error: target_type is not in table,file line=3 value=view` が出る'), function () {
  assertExit(this.result, 2);
  assertStderrIncludes(this, 'error: target_type is not in table,file line=3 value=view');
});
