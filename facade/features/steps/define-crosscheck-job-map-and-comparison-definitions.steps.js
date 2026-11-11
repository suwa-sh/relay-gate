// tier BDD(③)step definition。tier-facade / uc_id=dcd8234d(クロスチェックのジョブマップと比較定義を定義する)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-facade.md#ティア完了条件(BDD)
// S2 skeleton の step 文言(feature から転写したリテラル)を完全一致の正規表現で受け、S4 で実装した。
// I/O 境界は実体で検証する: Scenario ごとの一時ディレクトリ(this.workDir。Before / After は
// configure-feature-flags.steps.js が定義済み)に rapid-crosscheck.env と比較ツールのスタブを置き、
// bin/validate-config.sh を実プロセスとして起動する。
// feature のパス /opt/compare/ はホストに作れないため、一時ディレクトリ配下の同名ディレクトリへ読み替える
// (env の値と期待する出力の両方を同じ規則で読み替える)。
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPT = path.resolve(__dirname, '../../bin/validate-config.sh');
const FEATURE_COMPARE_DIR = '/opt/compare/';
const COMPARE_STUB = '#!/usr/bin/env bash\nexit 0\n';

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

function compareDir(world) {
  return path.join(world.workDir, 'opt', 'compare') + path.sep;
}

// feature 上の /opt/compare/ を一時ディレクトリ配下へ読み替える
function localize(world, text) {
  return text.split(FEATURE_COMPARE_DIR).join(compareDir(world));
}

function arrangeCommand(world, command, executable) {
  fs.mkdirSync(compareDir(world), { recursive: true });
  if (executable) {
    fs.writeFileSync(path.join(compareDir(world), executable), COMPARE_STUB, { mode: 0o755 });
  }
  world.rapidEnvPath = path.join(world.workDir, 'rapid-crosscheck.env');
  fs.writeFileSync(world.rapidEnvPath, `RAPID_DB_CONN_REF=rapid_db\nRAPID_COMPARE_COMMAND=${localize(world, command)}\n`);
}

function stdoutLines(world) {
  return world.result.stdout.split('\n').filter((line) => line.length > 0);
}

function assertExit(world, code) {
  assert.equal(world.result.status, code, `exit code\n--- stdout ---\n${world.result.stdout}\n--- stderr ---\n${world.result.stderr}`);
}

function assertStdoutIncludes(world, expected) {
  const line = localize(world, expected);
  assert.ok(stdoutLines(world).includes(line), `stdout should include line "${line}"\n--- stdout ---\n${world.result.stdout}`);
}

function assertStderrIncludes(world, expected) {
  const line = localize(world, expected);
  assert.ok(world.result.stderr.split('\n').includes(line), `stderr should include line "${line}"\n--- stderr ---\n${world.result.stderr}`);
}

// ---- Given ----

Given(literal('RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} で /opt/compare/compare.sh が実行可能'), function () {
  arrangeCommand(this, '/opt/compare/compare.sh --job {job_id}', 'compare.sh');
});

Given(literal('RAPID_COMPARE_COMMAND=/opt/compare/missing.sh --job {job_id} でコマンド部分が存在しない'), function () {
  arrangeCommand(this, '/opt/compare/missing.sh --job {job_id}', null);
});

Given(literal('RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --run {run_id} で {job_id} を含まない'), function () {
  arrangeCommand(this, '/opt/compare/compare.sh --run {run_id}', 'compare.sh');
});

Given(literal('RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} --args={params} で {params} が引数の一部になっている'), function () {
  arrangeCommand(this, '/opt/compare/compare.sh --job {job_id} --args={params}', 'compare.sh');
});

Given(literal('RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} {params} で /opt/compare/compare.sh が実行可能'), function () {
  arrangeCommand(this, '/opt/compare/compare.sh --job {job_id} {params}', 'compare.sh');
});

Given(
  literal('RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} --in /no/such/path unknown-word で /opt/compare/compare.sh が実行可能'),
  function () {
    arrangeCommand(this, '/opt/compare/compare.sh --job {job_id} --in /no/such/path unknown-word', 'compare.sh');
  },
);

// ---- Given(env の行・バイト列を直接組み立てる Scenario。2026-11-10 S2 再生成で追加) ----
// <SP> は半角空白 1 個、<TAB> はタブ 1 個に置き換えて書き込む(tier-facade.md の Given の注記どおり)。

const COMMAND_LINE = 'RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id}';

function expandWhitespaceMarkers(text) {
  return text.split('<SP>').join(' ').split('<TAB>').join('\t');
}

// env をバイト列で書く(BOM / NUL / 不正な UTF-8 / CR を含む Scenario のため Buffer で組み立てる)
function arrangeRawEnv(world, chunks) {
  fs.mkdirSync(compareDir(world), { recursive: true });
  fs.writeFileSync(path.join(compareDir(world), 'compare.sh'), COMPARE_STUB, { mode: 0o755 });
  world.rapidEnvPath = path.join(world.workDir, 'rapid-crosscheck.env');
  const buffers = chunks.map((chunk) => (Buffer.isBuffer(chunk) ? chunk : Buffer.from(localize(world, chunk), 'utf8')));
  fs.writeFileSync(world.rapidEnvPath, Buffer.concat(buffers));
}

// feature の <path> を実際の env のパスへ置き換える(Scenario Outline の列ではなく、Then の文言に書かれたリテラル)
function withPath(world, text) {
  return text.split('<path>').join(world.rapidEnvPath);
}

Given(
  new RegExp(
    '^rapid-crosscheck\\.env の 1 行目が (.+) で、2 行目が RAPID_COMPARE_COMMAND=/opt/compare/compare\\.sh --job \\{job_id\\} である' +
      '\\(/opt/compare/compare\\.sh は実行可能。<SP> は半角空白 1 個、<TAB> はタブ 1 個に置き換えて書き込む\\)$',
  ),
  function (line) {
    arrangeRawEnv(this, [`${expandWhitespaceMarkers(line)}\n${COMMAND_LINE}\n`]);
  },
);

Given(
  literal(
    'rapid-crosscheck.env の 1 行目が RAPID_COMPARE_COMMAND=/opt/compare/old.sh --job {job_id}、2 行目が RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} である(どちらのコマンドも実行可能)',
  ),
  function () {
    fs.mkdirSync(compareDir(this), { recursive: true });
    fs.writeFileSync(path.join(compareDir(this), 'old.sh'), COMPARE_STUB, { mode: 0o755 });
    arrangeRawEnv(this, [`RAPID_COMPARE_COMMAND=/opt/compare/old.sh --job {job_id}\n${COMMAND_LINE}\n`]);
  },
);

Given(
  literal(
    'rapid-crosscheck.env が `<SP># RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id}` の 1 行だけである(<SP> は半角空白 1 個に置き換えて書き込む。/opt/compare/compare.sh は実行可能)',
  ),
  function () {
    arrangeRawEnv(this, [`${expandWhitespaceMarkers('<SP>')}# ${COMMAND_LINE}\n`]);
  },
);

Given(
  literal(
    'rapid-crosscheck.env の 1 行目が BOM 付きの "# compare" + CR + LF、2 行目が NUL バイトと UTF-8 として不正なバイト列を含み CR + LF で終わる行、3 行目が "RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id}" + CR + LF、4 行目が NUL バイトを含む行である',
  ),
  function () {
    arrangeRawEnv(this, [
      Buffer.from([0xef, 0xbb, 0xbf]),
      '# compare\r\n',
      Buffer.from('# a', 'utf8'),
      Buffer.from([0x00, 0xff, 0xfe]),
      '\r\n',
      `${COMMAND_LINE}\r\n`,
      Buffer.from('# tail', 'utf8'),
      Buffer.from([0x00]),
      '\n',
    ]);
  },
);

// ---- Given(--verbose の info 行の Scenario。2026-11-11 S2 再生成で追加。spec-decision-033) ----

Given(literal('rapid-crosscheck.env の 1 行目が ZZ=x、2 行目が RAPID_COMPARE_COMMAND=relative、3 行目が AA=x である'), function () {
  arrangeRawEnv(this, ['ZZ=x\nRAPID_COMPARE_COMMAND=relative\nAA=x\n']);
});

Given(
  literal(
    'rapid-crosscheck.env の 1 行目がコメント行 # memo、2 行目が RAPID_DB_CONN_REF=、3 行目が RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} である(/opt/compare/compare.sh は実行可能)',
  ),
  function () {
    arrangeRawEnv(this, [`# memo\nRAPID_DB_CONN_REF=\n${COMMAND_LINE}\n`]);
  },
);

Given(
  literal(
    'rapid-crosscheck.env の 1 行目が ZZ=x、2 行目が broken、3 行目が RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} である(/opt/compare/compare.sh は実行可能)',
  ),
  function () {
    arrangeRawEnv(this, [`ZZ=x\nbroken\n${COMMAND_LINE}\n`]);
  },
);

Given(
  literal('rapid-crosscheck.env の 1 行目が ZZ=x + CR + LF、2 行目が RAPID_COMPARE_COMMAND=/opt/compare/compare.sh --job {job_id} である'),
  function () {
    arrangeRawEnv(this, [`ZZ=x\r\n${COMMAND_LINE}\n`]);
  },
);

// ---- When ----

function runRapidCrosscheck(world, extraArgs) {
  const proc = spawnSync(SCRIPT, ['--rapid-crosscheck', world.rapidEnvPath, ...extraArgs], {
    cwd: world.workDir,
    encoding: 'utf8',
    env: { ...process.env, RELAY_GATE_CONFIG_DIR: world.configDir },
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  return { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
}

When(literal('validate-config.sh --rapid-crosscheck <path> を実行する'), function () {
  this.result = runRapidCrosscheck(this, []);
});

When(literal('validate-config.sh --rapid-crosscheck <path> --verbose を実行する'), function () {
  this.result = runRapidCrosscheck(this, ['--verbose']);
});

// ---- Then ----

Then(literal('終了コード 0 で stdout に status=valid、command_path: /opt/compare/compare.sh、has_job_id_placeholder=true が出る'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'status=valid');
  assertStdoutIncludes(this, 'command_path: /opt/compare/compare.sh');
  assertStdoutIncludes(this, 'has_job_id_placeholder=true');
});

Then(literal('終了コード 2 で stderr に `error: file not executable key=RAPID_COMPARE_COMMAND path=/opt/compare/missing.sh` が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: file not executable key=RAPID_COMPARE_COMMAND path=/opt/compare/missing.sh');
});

Then(
  literal(
    '終了コード 2 で stderr に `error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --run {run_id}` が出る',
  ),
  function () {
    assertExit(this, 2);
    assertStderrIncludes(this, 'error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --run {run_id}');
  },
);

Then(
  literal(
    '終了コード 2 で stderr に `error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --job {job_id} --args={params}` が出る',
  ),
  function () {
    assertExit(this, 2);
    assertStderrIncludes(
      this,
      'error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --job {job_id} --args={params}',
    );
  },
);

Then(literal('終了コード 0 で stdout に status=valid が出る'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'status=valid');
});

// ---- Then(2026-11-10 S2 再生成で追加) ----

function stderrLines(world) {
  return world.result.stderr.split('\n').filter((line) => line.length > 0);
}

function errorLines(world) {
  return stderrLines(world).filter((line) => line.startsWith('error:'));
}

Then(literal('終了コード 0 で stdout に status=valid が出て、stderr に error 行は出ない'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'status=valid');
  assert.deepEqual(errorLines(this), [], `no error line expected\n--- stderr ---\n${this.result.stderr}`);
});

Then(
  literal('終了コード 0 で stdout に status=valid が出て、stderr に "error: invalid line" で始まる行は出ない(契約 config_input_rules.env_files。全 env 設定ファイル共通)'),
  function () {
    assertExit(this, 0);
    assertStdoutIncludes(this, 'status=valid');
    const invalid = stderrLines(this).filter((line) => line.startsWith('error: invalid line'));
    assert.deepEqual(invalid, [], `no invalid line error expected\n--- stderr ---\n${this.result.stderr}`);
  },
);

Then(
  literal(
    '終了コード 2 で stderr の error 行は `error: duplicate key key=RAPID_COMPARE_COMMAND lines=1,2 path: <path>` の 1 行だけである(契約 config_input_rules.env_files。後の行の値で検証しない)',
  ),
  function () {
    assertExit(this, 2);
    assert.deepEqual(
      errorLines(this),
      [withPath(this, 'error: duplicate key key=RAPID_COMPARE_COMMAND lines=1,2 path: <path>')],
      `error lines\n--- stderr ---\n${this.result.stderr}`,
    );
  },
);

// 「stdout は `a` / `b` / ... の 6 行である」: stdout の行がこの 6 行とこの順で完全に一致する(末尾の括弧書きは出典の注記)
Then(/^stdout は (`[^`]*`(?: \/ `[^`]*`)*) の 6 行である(?:\(.*\))?$/, function (items) {
  const expected = [...items.matchAll(/`([^`]*)`/g)].map((m) => withPath(this, m[1]));
  assert.equal(expected.length, 6, `feature should list 6 lines: ${items}`);
  assert.deepEqual(stdoutLines(this), expected, `stdout lines\n--- stdout ---\n${this.result.stdout}`);
});

Then(
  literal(
    '終了コード 2 で stderr に `error: option required option=RAPID_COMPARE_COMMAND path: <path>` が出て、"error: invalid line" で始まる行は出ない(コメント行として読み飛ばすため、起動コマンドが無い設定になる)',
  ),
  function () {
    assertExit(this, 2);
    assertStderrIncludes(this, withPath(this, 'error: option required option=RAPID_COMPARE_COMMAND path: <path>'));
    const invalid = stderrLines(this).filter((line) => line.startsWith('error: invalid line'));
    assert.deepEqual(invalid, [], `no invalid line error expected\n--- stderr ---\n${this.result.stderr}`);
  },
);

// 「終了コード 2 で stderr は次の N 行がこの順に出る」: stderr の行が表の N 行とこの順で完全に一致する
// (8 行 = バイト・改行の違反、7 行 = --verbose の info → warn → error の順)
Then(/^終了コード 2 で stderr は次の (\d+) 行がこの順に出る$/, function (count, table) {
  assertExit(this, 2);
  const expected = table.raw().map((row) => withPath(this, localize(this, row[0].trim())));
  assert.equal(expected.length, Number(count), `feature table should have ${count} rows`);
  assert.deepEqual(stderrLines(this), expected, `stderr lines\n--- stderr ---\n${this.result.stderr}`);
});

// ---- Then(--verbose の info 行の Scenario。2026-11-11 S2 再生成で追加。spec-decision-033) ----

function backtickItems(world, items) {
  return [...items.matchAll(/`([^`]*)`/g)].map((m) => withPath(world, localize(world, m[1])));
}

// 「終了コード N で stderr は `a` / `b` の M 行だけである」「... の M 行だけがこの順に出る」:
// stderr の行がこの M 行とこの順で完全に一致する(末尾の括弧書きは出典の注記)
Then(
  /^終了コード (\d+) で stderr は (`[^`]*`(?: \/ `[^`]*`)*) の (\d+) 行だけ(?:である|がこの順に出る)(?:\(.*\))?$/,
  function (code, items, count) {
    assertExit(this, Number(code));
    const expected = backtickItems(this, items);
    assert.equal(expected.length, Number(count), `feature should list ${count} lines: ${items}`);
    assert.deepEqual(stderrLines(this), expected, `stderr lines\n--- stderr ---\n${this.result.stderr}`);
  },
);

// 「stdout は --verbose を付けないときと同じ `a` / ... の 5 行である」: stdout がこの 5 行と完全に一致し、
// 同じ env を --verbose なしで検証した stdout とも一致する(--verbose は stdout に影響しない)
Then(/^stdout は --verbose を付けないときと同じ (`[^`]*`(?: \/ `[^`]*`)*) の 5 行である$/, function (items) {
  const expected = backtickItems(this, items);
  assert.equal(expected.length, 5, `feature should list 5 lines: ${items}`);
  assert.deepEqual(stdoutLines(this), expected, `stdout lines\n--- stdout ---\n${this.result.stdout}`);
  const plain = runRapidCrosscheck(this, []);
  assert.equal(plain.status, this.result.status, 'exit code without --verbose');
  assert.equal(plain.stdout, this.result.stdout, 'stdout without --verbose');
});
