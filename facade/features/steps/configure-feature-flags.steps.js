// tier BDD(③)step definition。tier-facade / uc_id=fd678b04(feature flag を設定する)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/tier-facade.md#ティア完了条件(BDD)
// S2 skeleton の step 文言(feature から転写したリテラル)を完全一致の正規表現で受け、S4 で実装した。
// 2026-11-13 の S2 再実行で、env 形式の共通規則(契約 config_input_rules.env_files)と --verbose の info 行の
// Scenario の step を末尾に追加した(既存 step は変更なし)。
// I/O 境界は実体で検証する: Scenario ごとの一時ディレクトリに ff.env / runner スタブ / ジョブマップを置き、
// bin/validate-config.sh を実プロセスとして起動する(cwd = 一時ディレクトリ。`path: ff.env` は相対パスのまま出る)。
'use strict';
const { Given, When, Then, Before, After } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPT = path.resolve(__dirname, '../../bin/validate-config.sh');

// runner スタブ: --help で runner-if-version=1 を返す(UC「slot runner の実体スクリプトを割り当てる」の runner IF)
const RUNNER_STUB =
  '#!/usr/bin/env bash\n' +
  'if [ "${1:-}" = "--help" ]; then echo "usage: runner-stub.sh"; echo "runner-if-version=1"; exit 0; fi\n' +
  'exit 6\n';

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

Before(function () {
  this.workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-gate-ff-'));
  this.configDir = path.join(this.workDir, 'config');
  fs.mkdirSync(this.configDir);
  this.envPath = path.join(this.workDir, 'ff.env');
  this.env = {};
  this.rawEnv = null;
  this.result = null;
});

After(function () {
  if (this.workDir) {
    fs.rmSync(this.workDir, { recursive: true, force: true });
  }
});

function writeRunner(world, name) {
  const runner = path.join(world.workDir, name);
  fs.writeFileSync(runner, RUNNER_STUB, { mode: 0o755 });
  return runner;
}

function writeJobMap(world, slot) {
  fs.writeFileSync(path.join(world.configDir, `${slot}-job-map.csv`), 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\n');
}

// 有効な並行稼働設定(全 runner スタブは実行可能・--help 応答あり・両ジョブマップあり)
function arrangeParallel(world) {
  world.env = {
    BLUE_MODE: 'foreground',
    GREEN_MODE: 'background',
    RAPID_CROSSCHECK_MODE: 'background',
    BLUE_IMPL: 'blue-2.3.1',
    GREEN_IMPL: 'green-1.4.0',
    BLUE_RUNNER: writeRunner(world, 'blue-runner.sh'),
    GREEN_RUNNER: writeRunner(world, 'green-runner.sh'),
    RAPID_CROSSCHECK_RUNNER: writeRunner(world, 'rapid-crosscheck-runner.sh'),
    RAPID_CROSSCHECK_WORKER: writeRunner(world, 'rapid-crosscheck-worker.sh'),
  };
  writeJobMap(world, 'blue');
  writeJobMap(world, 'green');
}

function envLines(world) {
  return Object.entries(world.env).map(([key, value]) => `${key}=${value}`);
}

// world.rawEnv(Buffer)があればそのバイト列をそのまま書く(CR / 不正な UTF-8 / 行の挿入を含む Scenario 用)。
// 無ければ world.env の KEY=value を LF 区切りで書く
function flushEnv(world) {
  if (world.rawEnv) {
    fs.writeFileSync(world.envPath, world.rawEnv);
    return;
  }
  fs.writeFileSync(world.envPath, envLines(world).join('\n') + '\n');
}

// 行の並びをそのまま ff.env の内容にする(各行は LF で終わる)
function arrangeRawLines(world, lines) {
  world.rawEnv = Buffer.from(lines.map((line) => `${line}\n`).join(''), 'utf8');
}

// <SP> は半角空白 1 個、<TAB> はタブ 1 個に置き換える(tier-facade.md の Given の注記どおり)
function expandWhitespaceMarkers(text) {
  return text.split('<SP>').join(' ').split('<TAB>').join('\t');
}

// 有効な並行稼働設定(1 行目が BLUE_MODE=foreground)の 1 行目の後に行を挿入する
function arrangeParallelWithInsertedLines(world, inserted) {
  arrangeParallel(world);
  const lines = envLines(world);
  assert.equal(lines[0], 'BLUE_MODE=foreground');
  arrangeRawLines(world, [lines[0], ...inserted.map(expandWhitespaceMarkers), ...lines.slice(1)]);
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');
}

function stderrLines(world) {
  return world.result.stderr.split('\n').filter((line) => line.length > 0);
}

function quotedItems(text) {
  return [...text.matchAll(/"([^"]*)"/g)].map((m) => m[1]);
}

function assertNoStderrLineStartsWith(world, prefixes) {
  const hits = stderrLines(world).filter((line) => prefixes.some((prefix) => line.startsWith(prefix)));
  assert.deepEqual(hits, [], `no line starting with ${prefixes.join(' / ')} expected\n--- stderr ---\n${world.result.stderr}`);
}

function assertStdoutEmpty(world) {
  assert.equal(world.result.stdout, '', `stdout should be empty\n--- stdout ---\n${world.result.stdout}`);
}

function runValidateConfig(world, args) {
  flushEnv(world);
  const proc = spawnSync(SCRIPT, args, {
    cwd: world.workDir,
    encoding: 'utf8',
    env: { ...process.env, RELAY_GATE_CONFIG_DIR: world.configDir },
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  world.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
}

function stdoutLines(world) {
  return world.result.stdout.split('\n').filter((line) => line.length > 0);
}

function assertStderrIncludes(world, expected) {
  assert.ok(
    world.result.stderr.split('\n').includes(expected),
    `stderr should include line "${expected}"\n--- stderr ---\n${world.result.stderr}`,
  );
}

function assertStdoutIncludes(world, expected) {
  assert.ok(stdoutLines(world).includes(expected), `stdout should include line "${expected}"\n--- stdout ---\n${world.result.stdout}`);
}

function assertExit(world, code) {
  assert.equal(world.result.status, code, `exit code\n--- stdout ---\n${world.result.stdout}\n--- stderr ---\n${world.result.stderr}`);
}

// ---- Given ----

Given(
  literal(
    '一時ファイル ff.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=<実行可能な一時スクリプト> GREEN_RUNNER=<実行可能な一時スクリプト> RAPID_CROSSCHECK_RUNNER=<実行可能な一時スクリプト> RAPID_CROSSCHECK_WORKER=<実行可能な一時スクリプト> を書く',
  ),
  function () {
    arrangeParallel(this);
  },
);

Given(literal('両 runner スタブは --help で "runner-if-version=1" を返し、RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある'), function () {
  // arrangeParallel が runner スタブ(--help 応答)と両ジョブマップを配置済み。ここでは実体を確認する
  for (const key of ['BLUE_RUNNER', 'GREEN_RUNNER']) {
    const help = spawnSync(this.env[key], ['--help'], { encoding: 'utf8' });
    assert.equal(help.status, 0);
    assert.ok(help.stdout.includes('runner-if-version=1'));
  }
  assert.ok(fs.existsSync(path.join(this.configDir, 'blue-job-map.csv')));
  assert.ok(fs.existsSync(path.join(this.configDir, 'green-job-map.csv')));
});

Given(literal('ff.env に BLUE_MODE=foreground GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off を書く'), function () {
  this.env = { BLUE_MODE: 'foreground', GREEN_MODE: 'foreground', RAPID_CROSSCHECK_MODE: 'off' };
});

Given(
  literal(
    'ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> を書き BLUE_IMPL / BLUE_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER を書かない',
  ),
  function () {
    this.env = {
      BLUE_MODE: 'off',
      GREEN_MODE: 'foreground',
      RAPID_CROSSCHECK_MODE: 'off',
      GREEN_IMPL: 'green-1.4.0',
      GREEN_RUNNER: writeRunner(this, 'green-runner.sh'),
    };
  },
);

Given(literal('RELAY_GATE_CONFIG_DIR に green-job-map.csv がある(blue-job-map.csv は無くてよい)'), function () {
  writeJobMap(this, 'green');
  assert.ok(!fs.existsSync(path.join(this.configDir, 'blue-job-map.csv')));
});

Given(literal('ff.env に GREEN_MODE=foreground GREEN_IMPL=green-1.4.0 GREEN_RUNNER=/nonexistent/green.sh を書く'), function () {
  this.env = { GREEN_MODE: 'foreground', GREEN_IMPL: 'green-1.4.0', GREEN_RUNNER: '/nonexistent/green.sh' };
});

Given(literal('ff.env に GREEN_MODE=foreground GREEN_RUNNER=<実行可能> を書き GREEN_IMPL を書かない'), function () {
  this.env = { GREEN_MODE: 'foreground', GREEN_RUNNER: writeRunner(this, 'green-runner.sh') };
});

Given(literal('有効な並行稼働設定の RAPID_CROSSCHECK_WORKER を /nonexistent/worker.sh に書き換える'), function () {
  arrangeParallel(this);
  this.env.RAPID_CROSSCHECK_WORKER = '/nonexistent/worker.sh';
});

Given(literal('有効な設定に加えて CONFIG_VERSION=cfg-v1 を書く'), function () {
  arrangeParallel(this);
  this.env.CONFIG_VERSION = 'cfg-v1';
});

// ---- S2 test-scaffold 再実行(spec event 20260917_100000_feedback_impl_feedback_fd678b04_cycle2)で追加 ----
// Scenario「validate-config_sh_feature-flag は FINAL_ で始まるキーを未知キーではなく終了コード 2 で拒否する」。
// 拒否範囲 = キー名が FINAL_ で始まる全キー(接頭辞判定。正本: cli-command-contract.yaml
// config_files.feature-flag.env.validation_rules)。final-crosscheck.env のキー(FINAL_DB_CONN_REF)の誤配置と
// 制御キー(FINAL_CROSSCHECK_MODE)の両方を 1 ファイルに置き、該当キーごとの error 行と warn 不在を確認する。

Given(literal('有効な並行稼働設定に加えて FINAL_DB_CONN_REF=final-db と FINAL_CROSSCHECK_MODE=background を書く'), function () {
  arrangeParallel(this);
  this.env.FINAL_DB_CONN_REF = 'final-db';
  this.env.FINAL_CROSSCHECK_MODE = 'background';
});

Then(
  literal(
    '終了コード 2 で stderr に "error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF" と "error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE" の両方が出る',
  ),
  function () {
    assertExit(this, 2);
    assertStderrIncludes(this, 'error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF');
    assertStderrIncludes(this, 'error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE');
  },
);

// ---- When ----

When(literal('`validate-config.sh --feature-flag ff.env` を実行する'), function () {
  runValidateConfig(this, ['--feature-flag', 'ff.env']);
});

When(literal('`validate-config.sh --feature-flag /nonexistent.env` を実行する'), function () {
  runValidateConfig(this, ['--feature-flag', '/nonexistent.env']);
});

// ---- Then ----

Then(literal('終了コード 0 で stdout は 15 行で、11 行目は "operation_mode=parallel" である'), function () {
  assertExit(this, 0);
  const lines = stdoutLines(this);
  assert.equal(lines.length, 15, `stdout lines\n${this.result.stdout}`);
  assert.equal(lines[10], 'operation_mode=parallel');
});

Then(literal('stdout の 2 行目は "blue_mode=foreground"、4 行目は "blue_impl=blue-2.3.1" である'), function () {
  const lines = stdoutLines(this);
  assert.equal(lines[1], 'blue_mode=foreground');
  assert.equal(lines[3], 'blue_impl=blue-2.3.1');
});

Then(literal('stdout の最終行は "green_runner_if_version=1" である(mode=off の slot なら "-")'), function () {
  const lines = stdoutLines(this);
  const expected = this.env.GREEN_MODE === 'off' ? 'green_runner_if_version=-' : 'green_runner_if_version=1';
  assert.equal(lines[lines.length - 1], expected);
});

Then(literal('stderr に "warn: unknown key" で始まる行は出ない'), function () {
  const warns = this.result.stderr.split('\n').filter((line) => line.startsWith('warn: unknown key'));
  assert.deepEqual(warns, []);
});

Then(literal('終了コード 2 で stderr に "error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground');
});

Then(literal('終了コード 0 で stdout に "blue_impl=-" "blue_runner: -" "rapid_crosscheck_runner: -" と "operation_mode=green_only" が出る'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'blue_impl=-');
  assertStdoutIncludes(this, 'blue_runner: -');
  assertStdoutIncludes(this, 'rapid_crosscheck_runner: -');
  assertStdoutIncludes(this, 'operation_mode=green_only');
});

Then(literal('終了コード 2 で stderr に "error: file not executable key=GREEN_RUNNER path=/nonexistent/green.sh" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: file not executable key=GREEN_RUNNER path=/nonexistent/green.sh');
});

Then(literal('終了コード 2 で stderr に "error: option required option=GREEN_IMPL path: ff.env" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: option required option=GREEN_IMPL path: ff.env');
});

Then(literal('終了コード 2 で stderr に "error: file not executable key=RAPID_CROSSCHECK_WORKER path=/nonexistent/worker.sh" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: file not executable key=RAPID_CROSSCHECK_WORKER path=/nonexistent/worker.sh');
});

Then(literal('終了コード 0 で stderr に "warn: unknown key key=CONFIG_VERSION path: ff.env" が出る'), function () {
  assertExit(this, 0);
  assertStderrIncludes(this, 'warn: unknown key key=CONFIG_VERSION path: ff.env');
});

Then(literal('終了コード 2 で stderr に "error: config file not found path: /nonexistent.env" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: config file not found path: /nonexistent.env');
});

// ==== S2 test-scaffold 再実行(2026-11-13。spec event 20261110_153000 までの仕様更新に追従)で追加 ====
// 出典: tier-facade.md「ティア完了条件(BDD)」の追加 Scenario。規則の正本は cli-command-contract.yaml の
// config_input_rules(byte_checks / env_files)と conventions.output_format.control_chars。
// 実装(facade/src/)が未追従の Scenario は assertion failure で fail する(S4 の再実行で追従する)。

// ---- Given: 制御文字の表記 / バイト・改行の検査 ----

Given(literal('有効な設定の BLUE_MODE の値を "on<ESC>[0m"(ESC を含む)にする'), function () {
  arrangeParallel(this);
  this.env.BLUE_MODE = 'on\u001b[0m';
});

Given(literal('有効な設定の全行が CRLF で終わる'), function () {
  arrangeParallel(this);
  this.rawEnv = Buffer.from(
    envLines(this)
      .map((line) => `${line}\r\n`)
      .join(''),
    'utf8',
  );
});

Given(
  literal(
    'ff.env の 1 行目が "BLUE_MODE=foreground" + CR + LF、2 行目が UTF-8 として不正なバイト列を含むコメント行、3 行目が "GREEN_MODE=sideways"(列挙外)+ CR + LF である',
  ),
  function () {
    this.rawEnv = Buffer.concat([
      Buffer.from('BLUE_MODE=foreground\r\n', 'utf8'),
      Buffer.from('# memo ', 'utf8'),
      Buffer.from([0xff, 0xfe]),
      Buffer.from('\n', 'utf8'),
      Buffer.from('GREEN_MODE=sideways\r\n', 'utf8'),
    ]);
  },
);

// ---- Given: 行の構造の検査(invalid line / コメント行 / duplicate key) ----

// Scenario Outline「キーが空の行と KEY=VALUE でない行を invalid line で拒否する」
Given(
  new RegExp(
    '^' +
      escapeRegExp('有効な並行稼働設定の 1 行目の後に ') +
      '(.+)' +
      escapeRegExp(' の 1 行を挿入した ff.env がある(<SP> は半角空白 1 個に置き換えて書き込む)') +
      '$',
  ),
  function (line) {
    arrangeParallelWithInsertedLines(this, [line]);
  },
);

// Scenario Outline「前後の空白を除いて # で始まる行をコメントとして読み飛ばす」
Given(
  new RegExp(
    '^' +
      escapeRegExp('有効な並行稼働設定の 1 行目の後に ') +
      '(.+)' +
      escapeRegExp(' の 1 行を挿入した ff.env がある(<SP> は半角空白 1 個、<TAB> はタブ 1 個に置き換えて書き込む)') +
      '$',
  ),
  function (line) {
    arrangeParallelWithInsertedLines(this, [line]);
  },
);

Given(literal('有効な並行稼働設定の BLUE_IMPL の行を `BLUE_IMPL=#v1` に置き換えた ff.env がある'), function () {
  arrangeParallel(this);
  this.env.BLUE_IMPL = '#v1';
});

// Scenario Outline「同じキーが 2 行以上ある設定を duplicate key で拒否する」。
// Examples の <lines> は step 文中に 2 回現れる(挿入する行と、区切りの注記)。「 と 」で区切った各行を 2 行目から挿入する
Given(
  new RegExp(
    '^' +
      escapeRegExp('有効な並行稼働設定(1 行目が BLUE_MODE=foreground)の 1 行目の後に ') +
      '(.+)' +
      escapeRegExp(' を挿入した ff.env がある(') +
      '(.+)' +
      escapeRegExp(
        ' の「 と 」は行の区切りで、区切った各行をこの順に 2 行目から 1 行ずつ挿入する。<SP> は半角空白 1 個に置き換えて書き込む)',
      ) +
      '$',
  ),
  function (lines, linesInNote) {
    assert.equal(linesInNote, lines, 'both <lines> placeholders should carry the same example value');
    arrangeParallelWithInsertedLines(this, lines.split(' と '));
  },
);

Given(literal('有効な並行稼働設定に加えて blue_mode=off を書く'), function () {
  arrangeParallel(this);
  this.env.blue_mode = 'off';
});

// ---- Given: --verbose の info 行 ----

Given(literal('ff.env の 1 行目が ZZ=x、2 行目が BLUE_MODE=off、3 行目が GREEN_MODE=off、4 行目が RAPID_CROSSCHECK_MODE=off である'), function () {
  arrangeRawLines(this, ['ZZ=x', 'BLUE_MODE=off', 'GREEN_MODE=off', 'RAPID_CROSSCHECK_MODE=off']);
});

Given(
  literal(
    'ff.env の 1 行目がコメント行 # memo、2 行目が BLUE_MODE=off、3 行目が GREEN_MODE=foreground、4 行目が RAPID_CROSSCHECK_MODE=off、5 行目が GREEN_IMPL=green-1.4.0、6 行目が GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> である',
  ),
  function () {
    const runner = writeRunner(this, 'green-runner.sh');
    arrangeRawLines(this, ['# memo', 'BLUE_MODE=off', 'GREEN_MODE=foreground', 'RAPID_CROSSCHECK_MODE=off', 'GREEN_IMPL=green-1.4.0', `GREEN_RUNNER=${runner}`]);
  },
);

Given(literal('RELAY_GATE_CONFIG_DIR に green-job-map.csv がある'), function () {
  writeJobMap(this, 'green');
});

Given(
  literal('ff.env の 1 行目が ZZ=x、2 行目が broken、3 行目が BLUE_MODE=off、4 行目が GREEN_MODE=foreground、5 行目が RAPID_CROSSCHECK_MODE=off である'),
  function () {
    arrangeRawLines(this, ['ZZ=x', 'broken', 'BLUE_MODE=off', 'GREEN_MODE=foreground', 'RAPID_CROSSCHECK_MODE=off']);
  },
);

// ---- When ----

When(literal('`validate-config.sh --feature-flag ff.env --verbose` を実行する'), function () {
  runValidateConfig(this, ['--feature-flag', 'ff.env', '--verbose']);
});

// ---- Then: 制御文字の表記 / バイト・改行の検査 ----

Then(
  literal("終了コード 2 で stderr に 'error: invalid value key=BLUE_MODE value=on\\u001b[0m' が出る(出力規約「制御文字の表記」)"),
  function () {
    assertExit(this, 2);
    assertStderrIncludes(this, 'error: invalid value key=BLUE_MODE value=on\\u001b[0m');
  },
);

Then(literal('stderr のどの行にも生の ESC は含まれない'), function () {
  assert.ok(!this.result.stderr.includes('\u001b'), 'stderr should not contain a raw ESC');
});

Then(
  literal(
    '終了コード 2 で stderr に "error: carriage return is not allowed line=1 path: ff.env" と "hint: use LF line endings" が出る(契約 config_input_rules。CR を黙って落として受理しない)',
  ),
  function () {
    assertExit(this, 2);
    assertStderrIncludes(this, 'error: carriage return is not allowed line=1 path: ff.env');
    assertStderrIncludes(this, 'hint: use LF line endings');
  },
);

// 「終了コード 2 で stdout は 0 行、stderr は "a" / "b" / ... の N 行がこの順に出る」「... の 1 行だけである(注記)」:
// stderr の行がこの N 行とこの順で完全に一致する
Then(
  /^終了コード 2 で stdout は 0 行、stderr は ("[^"]*"(?: \/ "[^"]*")*) の (\d+) 行(?:がこの順に出る|だけである)(?:\(.*\))?$/,
  function (items, count) {
    assertExit(this, 2);
    assertStdoutEmpty(this);
    const expected = quotedItems(items);
    assert.equal(expected.length, Number(count), `feature should list ${count} lines: ${items}`);
    assert.deepEqual(stderrLines(this), expected, `stderr lines\n--- stderr ---\n${this.result.stderr}`);
  },
);

Then(literal('stderr に "invalid value" / "option required" を含む行は出ない(バイト・改行の違反で止める)'), function () {
  const hits = stderrLines(this).filter((line) => line.includes('invalid value') || line.includes('option required'));
  assert.deepEqual(hits, [], `--- stderr ---\n${this.result.stderr}`);
});

// ---- Then: 行の構造の検査 ----

Then(literal('終了コード 2 で stderr に "error: invalid line line=2 path: ff.env" が出る(契約 config_input_rules.env_files。読み飛ばさない)'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: invalid line line=2 path: ff.env');
});

Then(literal('終了コード 0 で、stderr に "error:" と "warn: unknown key" で始まる行は出ない(契約 config_input_rules.env_files)'), function () {
  assertExit(this, 0);
  assertNoStderrLineStartsWith(this, ['error:', 'warn: unknown key']);
});

Then(literal('終了コード 0 で stdout に blue_impl=#v1 が出る(値の先頭の # はコメントにしない)'), function () {
  assertExit(this, 0);
  assertStdoutIncludes(this, 'blue_impl=#v1');
});

// Examples の <errors> は `"error: ..."` または `"error: ..." と "error: ..."`。stderr の error 行がこの並びと完全に一致する
Then(
  new RegExp(
    '^' + escapeRegExp('終了コード 2 で stderr の error 行は ') + '(.+)' + escapeRegExp(' だけで、この順に出る(契約 config_input_rules.env_files)') + '$',
  ),
  function (errors) {
    assertExit(this, 2);
    const expected = quotedItems(errors);
    assert.ok(expected.length > 0, `feature should list error lines: ${errors}`);
    assert.deepEqual(
      stderrLines(this).filter((line) => line.startsWith('error:')),
      expected,
      `error lines\n--- stderr ---\n${this.result.stderr}`,
    );
  },
);

Then(
  literal(
    'stdout は 0 行で、stderr に "error: option required" / "error: invalid value" / "warn: unknown key" で始まる行は出ない(値を使わず、キーごとの検査を行わない)',
  ),
  function () {
    assertStdoutEmpty(this);
    assertNoStderrLineStartsWith(this, ['error: option required', 'error: invalid value', 'warn: unknown key']);
  },
);

Then(
  literal(
    '終了コード 0 で stderr に "warn: unknown key key=blue_mode path: ff.env" が出て、"error: duplicate key" で始まる行は出ない(キーの比較は大文字小文字を区別した完全一致)',
  ),
  function () {
    assertExit(this, 0);
    assertStderrIncludes(this, 'warn: unknown key key=blue_mode path: ff.env');
    assertNoStderrLineStartsWith(this, ['error: duplicate key']);
  },
);

Then(literal('stdout の 2 行目は "blue_mode=foreground" である'), function () {
  assert.equal(stdoutLines(this)[1], 'blue_mode=foreground');
});

// ---- Then: --verbose の info 行 ----

// stderr の行が表の 6 行とこの順で完全に一致する(info 全件 → 未知キーの warn 全件 → キーごとの検査の error)
Then(literal('終了コード 2 で stdout は 0 行、stderr は次の 6 行がこの順に出る(契約 config_input_rules.env_files)'), function (table) {
  assertExit(this, 2);
  assertStdoutEmpty(this);
  const expected = table.raw().map((row) => row[0].trim());
  assert.equal(expected.length, 6, 'feature table should have 6 rows');
  assert.deepEqual(stderrLines(this), expected, `stderr lines\n--- stderr ---\n${this.result.stderr}`);
});

Then(
  literal(
    '終了コード 0 で stderr は info 行 5 行だけで、key= が BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE / GREEN_IMPL / GREEN_RUNNER の順に "info: key loaded key=<KEY> path: ff.env" が出る(コメント行の info 行は出ず、値は出さない)',
  ),
  function () {
    assertExit(this, 0);
    const expected = ['BLUE_MODE', 'GREEN_MODE', 'RAPID_CROSSCHECK_MODE', 'GREEN_IMPL', 'GREEN_RUNNER'].map(
      (key) => `info: key loaded key=${key} path: ff.env`,
    );
    assert.deepEqual(stderrLines(this), expected, `stderr lines\n--- stderr ---\n${this.result.stderr}`);
  },
);

// stdout が 15 行で 11 行目が operation_mode=green_only、かつ同じ ff.env を --verbose なしで検証した stdout と一致する
Then(literal('stdout は --verbose を付けないときと同じ 15 行で、11 行目は "operation_mode=green_only" である'), function () {
  const verbose = this.result;
  const lines = stdoutLines(this);
  assert.equal(lines.length, 15, `stdout lines\n${verbose.stdout}`);
  assert.equal(lines[10], 'operation_mode=green_only');
  runValidateConfig(this, ['--feature-flag', 'ff.env']);
  const plain = this.result;
  this.result = verbose;
  assert.equal(plain.status, verbose.status, 'exit code without --verbose');
  assert.equal(plain.stdout, verbose.stdout, 'stdout without --verbose');
});
