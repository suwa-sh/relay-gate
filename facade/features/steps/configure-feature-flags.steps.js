// tier BDD(③)step definition。tier-facade / uc_id=fd678b04(feature flag を設定する)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/tier-facade.md#ティア完了条件(BDD)
// S2 skeleton の step 文言(feature から転写したリテラル)を完全一致の正規表現で受け、S4 で実装した。
// 2026-11-13 の S2 再実行で、env 形式の共通規則(契約 config_input_rules.env_files)と --verbose の info 行の
// Scenario の step を末尾に追加した(既存 step は変更なし)。
// 2026-11-15 の S2 再実行で、error 行どうしの順・mode が列挙外/空/欠落の slot の検査・9 キー以外の値を取り込まない
// Scenario の step を末尾に追加した(既存 step は変更なし)。
// 2026-11-16 の S2 再実行で、slot ジョブマップの場所を書く任意の 2 キー(BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV)の Scenario の step を
// 末尾に追加した(既存 step の変更は、GREEN_RUNNER=<value> の正規表現の絞り込み 1 件と、パスの置き場 2 件の追加だけ)。
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
    // 2026-11-15(spec event 20261115_164000): 行の中の <conf の絶対パス> などのパスの置き場を実際のパスへ置き換える(置き場が無い行は元のまま)
    const expected = quotedItems(items).map((item) => expandPathPlaceholders(this, item));
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

// ==== S2 test-scaffold 再実行(2026-11-15。spec event 20261115_142000_feedback_impl_feedback_fd678b04_cycle3)で追加 ====
// 出典: tier-facade.md「ティア完了条件(BDD)」の末尾に足された Scenario 4 本と Scenario Outline 1 本。
// 規則の正本は cli-command-contract.yaml の config_files.feature-flag.env(error_order / validation_rules / error_messages)と
// config_input_rules.env_files「feature-flag.env から値を取り込むキーの範囲」。既存 step は変更していない。
// この仕様更新は現行実装の挙動を仕様に書いたもの(spec-decision-034)のため、追加 Scenario は現行実装で green になる。

// 起動されるたびに受け取った引数を <スタブのパス>.invoked へ 1 行ずつ記録する runner スタブ(--help で runner-if-version=1 を返す)
const RECORDING_RUNNER_STUB =
  '#!/usr/bin/env bash\n' +
  'printf \'%s\\n\' "$*" >>"$0.invoked"\n' +
  'if [ "${1:-}" = "--help" ]; then echo "usage: runner-stub.sh"; echo "runner-if-version=1"; exit 0; fi\n' +
  'exit 6\n';

function writeRecordingRunner(world, name) {
  const runner = path.join(world.workDir, name);
  fs.writeFileSync(runner, RECORDING_RUNNER_STUB, { mode: 0o755 });
  return runner;
}

function invocations(runner) {
  const log = `${runner}.invoked`;
  if (!fs.existsSync(log)) {
    return [];
  }
  return fs
    .readFileSync(log, 'utf8')
    .split('\n')
    .filter((line) => line.length > 0);
}

// feature の <RELAY_GATE_CONFIG_DIR> を、テストが環境変数 RELAY_GATE_CONFIG_DIR に渡すディレクトリへ置き換える
function expandConfigDir(world, text) {
  return text.split('<RELAY_GATE_CONFIG_DIR>').join(world.configDir);
}

// feature のパスの置き場(<RELAY_GATE_CONFIG_DIR> / <ff.env のあるディレクトリの絶対パス> / <conf の絶対パス> / <work の絶対パス> /
// <link の絶対パス>)を、その Scenario が用意した実際のパスへ置き換える。用意していない置き場は置き換えない
// (2026-11-15 の S2 再実行で追加。spec event 20261115_164000_feedback_runner_relative_path)
function expandPathPlaceholders(world, text) {
  const dirs = {
    '<ff.env のあるディレクトリの絶対パス>': path.dirname(world.envPath),
    '<conf の絶対パス>': world.confDir,
    '<work の絶対パス>': world.cwdDir,
    '<link の絶対パス>': world.linkDir,
    // 2026-11-16 の S2 再実行で追加(ジョブマップの場所を書く Scenario が用意する一時ディレクトリ maps)
    '<一時ディレクトリ maps の絶対パス>': world.mapsDir,
    '<maps の絶対パス>': world.mapsDir,
  };
  let expanded = expandConfigDir(world, text);
  for (const [placeholder, dir] of Object.entries(dirs)) {
    if (dir) {
      expanded = expanded.split(placeholder).join(dir);
    }
  }
  return expanded;
}

function assertJobMapAbsent(world, slot) {
  assert.ok(!fs.existsSync(path.join(world.configDir, `${slot}-job-map.csv`)), `${slot}-job-map.csv should not exist`);
}

// ---- Given: error 行どうしの順(契約 error_order) ----

Given(
  literal(
    'ff.env の 1 行目が BLUE_MODE=foreground、2 行目が GREEN_MODE=foreground、3 行目が RAPID_CROSSCHECK_MODE=maybe、4 行目が GREEN_IMPL=green-1.4.0、5 行目が BLUE_RUNNER=relative/blue-runner.sh、6 行目が FINAL_POLL_LIMIT_SEC=60、7 行目が FINAL_CROSSCHECK_MODE=background である(BLUE_IMPL / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER は書かない)',
  ),
  function () {
    arrangeRawLines(this, [
      'BLUE_MODE=foreground',
      'GREEN_MODE=foreground',
      'RAPID_CROSSCHECK_MODE=maybe',
      'GREEN_IMPL=green-1.4.0',
      'BLUE_RUNNER=relative/blue-runner.sh',
      'FINAL_POLL_LIMIT_SEC=60',
      'FINAL_CROSSCHECK_MODE=background',
    ]);
  },
);

Given(literal('RELAY_GATE_CONFIG_DIR に blue-job-map.csv も green-job-map.csv も無い'), function () {
  assertJobMapAbsent(this, 'blue');
  assertJobMapAbsent(this, 'green');
});

// ---- Given: mode が列挙外・空・欠落の slot(契約 validation_rules) ----

// Scenario Outline。Examples の <blue_mode_line> は step 文中に 2 回現れる(書く行と、「(書かない)」の注記)
Given(
  new RegExp(
    '^' +
      escapeRegExp('ff.env に ') +
      '(.+)' +
      escapeRegExp(
        ' GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off BLUE_RUNNER=<実行可能な blue スタブ> GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<実行可能な green スタブ> を書き BLUE_IMPL を書かない(',
      ) +
      '(.+)' +
      escapeRegExp(' が「(書かない)」のときは BLUE_MODE の行を書かない)') +
      '$',
  ),
  function (blueModeLine, blueModeLineInNote) {
    assert.equal(blueModeLineInNote, blueModeLine, 'both <blue_mode_line> placeholders should carry the same example value');
    this.recordingRunners = {
      blue: writeRecordingRunner(this, 'blue-runner.sh'),
      green: writeRecordingRunner(this, 'green-runner.sh'),
    };
    const lines = blueModeLine === '(書かない)' ? [] : [blueModeLine];
    lines.push(
      'GREEN_MODE=foreground',
      'RAPID_CROSSCHECK_MODE=off',
      `BLUE_RUNNER=${this.recordingRunners.blue}`,
      'GREEN_IMPL=green-1.4.0',
      `GREEN_RUNNER=${this.recordingRunners.green}`,
    );
    arrangeRawLines(this, lines);
  },
);

Given(literal('両 runner スタブは --help で "runner-if-version=1" を返し、起動されるたびに受け取った引数を記録する'), function () {
  // スタブを 1 回ずつ直接起動して応答と記録を確認し、記録を消してから When に進む
  for (const runner of Object.values(this.recordingRunners)) {
    const help = spawnSync(runner, ['--help'], { encoding: 'utf8' });
    assert.equal(help.status, 0);
    assert.ok(help.stdout.split('\n').includes('runner-if-version=1'));
    assert.deepEqual(invocations(runner), ['--help']);
    fs.rmSync(`${runner}.invoked`);
  }
});

Given(literal('RELAY_GATE_CONFIG_DIR に green-job-map.csv があり blue-job-map.csv は無い'), function () {
  writeJobMap(this, 'green');
  assertJobMapAbsent(this, 'blue');
});

Given(literal('ff.env の 1 行目が CONFIG_VERSION=cfg-v1、2 行目が GREEN_MODE=(値が空)で、ほかの行は無い'), function () {
  arrangeRawLines(this, ['CONFIG_VERSION=cfg-v1', 'GREEN_MODE=']);
});

Given(
  literal(
    'ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=maybe GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> を書き RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER を書かない',
  ),
  function () {
    this.env = {
      BLUE_MODE: 'off',
      GREEN_MODE: 'foreground',
      RAPID_CROSSCHECK_MODE: 'maybe',
      GREEN_IMPL: 'green-1.4.0',
      GREEN_RUNNER: writeRunner(this, 'green-runner.sh'),
    };
  },
);

// ---- Given: 9 キー以外のキーの値を取り込まない(契約 config_input_rules.env_files) ----

Given(
  literal('有効な並行稼働設定の 1 行目の前に PATH=/nonexistent を、最終行の後に RELAY_GATE_CONFIG_DIR=/nonexistent を書いた ff.env がある'),
  function () {
    arrangeParallel(this);
    arrangeRawLines(this, ['PATH=/nonexistent', ...envLines(this), 'RELAY_GATE_CONFIG_DIR=/nonexistent']);
  },
);

Given(
  literal(
    '両 runner スタブは --help で "runner-if-version=1" を返し、RELAY_GATE_CONFIG_DIR(環境変数)のディレクトリに blue-job-map.csv と green-job-map.csv がある',
  ),
  function () {
    // arrangeParallel が配置済みの実体を確認する。環境変数 RELAY_GATE_CONFIG_DIR は runValidateConfig が this.configDir を渡す
    for (const key of ['BLUE_RUNNER', 'GREEN_RUNNER']) {
      const help = spawnSync(this.env[key], ['--help'], { encoding: 'utf8' });
      assert.equal(help.status, 0);
      assert.ok(help.stdout.includes('runner-if-version=1'));
    }
    assert.notEqual(this.configDir, '/nonexistent');
    assert.ok(fs.existsSync(path.join(this.configDir, 'blue-job-map.csv')));
    assert.ok(fs.existsSync(path.join(this.configDir, 'green-job-map.csv')));
  },
);

// ---- Then: error 行どうしの順 / mode が列挙外・空・欠落の slot ----

// 「終了コード 2 で stdout は 0 行、stderr は次の N 行だけがこの順に出る(契約 ...)」: stderr の全行が表の N 行とこの順で完全に一致する
Then(/^終了コード 2 で stdout は 0 行、stderr は次の (\d+) 行だけがこの順に出る\(.*\)$/, function (count, table) {
  assertExit(this, 2);
  assertStdoutEmpty(this);
  // 2026-11-15(spec event 20261115_164000): <ff.env のあるディレクトリの絶対パス> も置き換える(error_order の表の 5 行目が解決後のパスになった)
  const expected = table.raw().map((row) => expandPathPlaceholders(this, row[0].trim()));
  assert.equal(expected.length, Number(count), `feature table should have ${count} rows`);
  assert.deepEqual(stderrLines(this), expected, `stderr lines\n--- stderr ---\n${this.result.stderr}`);
});

// Examples の <mode_lines> は `"error: ..."` または `"error: ..." / "hint: ..."`。その後に BLUE_IMPL と blue のジョブマップの error 行が続く
Then(
  new RegExp(
    '^' +
      escapeRegExp('終了コード 2 で stdout は 0 行、stderr は ') +
      '(.+)' +
      escapeRegExp(
        ' に続けて "error: option required option=BLUE_IMPL path: ff.env" / "error: job map not found slot=blue map=<RELAY_GATE_CONFIG_DIR>/blue-job-map.csv" がこの順に出て、ほかの行は出ない(契約 config_files.feature-flag.env.validation_rules)',
      ) +
      '$',
  ),
  function (modeLines) {
    assertExit(this, 2);
    assertStdoutEmpty(this);
    const head = quotedItems(modeLines);
    assert.ok(head.length > 0, `feature should list mode lines: ${modeLines}`);
    const expected = [
      ...head,
      'error: option required option=BLUE_IMPL path: ff.env',
      expandConfigDir(this, 'error: job map not found slot=blue map=<RELAY_GATE_CONFIG_DIR>/blue-job-map.csv'),
    ];
    assert.deepEqual(stderrLines(this), expected, `stderr lines\n--- stderr ---\n${this.result.stderr}`);
  },
);

Then(literal('blue スタブと green スタブは、それぞれ引数 --help で 1 回ずつ起動されている'), function () {
  assert.deepEqual(invocations(this.recordingRunners.blue), ['--help'], 'blue runner stub invocations');
  assert.deepEqual(invocations(this.recordingRunners.green), ['--help'], 'green runner stub invocations');
});

// ---- Then: 9 キー以外のキーの値を取り込まない ----

Then(
  literal(
    '終了コード 0 で stderr は "warn: unknown key key=PATH path: ff.env" / "warn: unknown key key=RELAY_GATE_CONFIG_DIR path: ff.env" の 2 行だけがこの順に出る(契約 config_input_rules.env_files。キー名を表示に使うだけ)',
  ),
  function () {
    assertExit(this, 0);
    assert.deepEqual(
      stderrLines(this),
      ['warn: unknown key key=PATH path: ff.env', 'warn: unknown key key=RELAY_GATE_CONFIG_DIR path: ff.env'],
      `stderr lines\n--- stderr ---\n${this.result.stderr}`,
    );
  },
);

Then(
  literal(
    'stdout は 15 行で、12 行目は "blue_job_map: <環境変数 RELAY_GATE_CONFIG_DIR>/blue-job-map.csv"、最終行は "green_runner_if_version=1" である(ファイルの PATH / RELAY_GATE_CONFIG_DIR の値は使われない)',
  ),
  function () {
    const lines = stdoutLines(this);
    assert.equal(lines.length, 15, `stdout lines\n${this.result.stdout}`);
    assert.equal(lines[11], `blue_job_map: ${path.join(this.configDir, 'blue-job-map.csv')}`);
    assert.equal(lines[14], 'green_runner_if_version=1');
    // ファイルに書いた値(/nonexistent)がジョブマップの解決にも runner の探索にも使われていない
    assert.deepEqual(
      lines.filter((line) => line.includes('/nonexistent')),
      [],
      `stdout should not use values of non-defined keys\n${this.result.stdout}`,
    );
  },
);

// ==== S2 test-scaffold 再実行(2026-11-15。spec event 20261115_164000_feedback_runner_relative_path)で追加 ====
// 出典: tier-facade.md「ティア完了条件(BDD)」の末尾に足された Scenario 4 本と Scenario Outline 2 本、
// および置換された Scenario「error 行が 2 行以上のとき契約の error_order の順に出す」の Given 1 行と When。
// 規則の正本は cli-command-contract.yaml の config_files.feature-flag.env.runner_path_resolution
// (BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER の相対パスは、設定ファイルのあるディレクトリを
// 基準に解決する。作業ディレクトリは、設定ファイルのパス自体が相対パスのときの絶対化にだけ使う)。
// 既存 step の変更は、stderr の行を照合する Then 2 件にパスの置き場の置き換えを足しただけ。
// 現行実装は 4 キーの相対パスを `error: path is not absolute` で拒否するため、ここの Scenario は実装が追従するまで assertion failure で fail する。

const GREEN_ONLY_KEYS = { BLUE_MODE: 'off', GREEN_MODE: 'foreground', RAPID_CROSSCHECK_MODE: 'off', GREEN_IMPL: 'green-1.4.0' };

// 起動されたら <スタブのパス>.invoked に記録を残し、--help で runner-if-version=9 を返す別の実行可能ファイル。
// 作業ディレクトリを基準に解決する実装なら、こちらが起動されて green_runner_if_version=9 になる
const DECOY_RUNNER_STUB =
  '#!/usr/bin/env bash\n' +
  'printf \'%s\\n\' "$*" >>"$0.invoked"\n' +
  'if [ "${1:-}" = "--help" ]; then echo "usage: decoy.sh"; echo "runner-if-version=9"; exit 0; fi\n' +
  'exit 6\n';

function writeExecutableAt(file, body) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, body, { mode: 0o755 });
  return file;
}

function assertRespondsVersion(file, version) {
  const help = spawnSync(file, ['--help'], { encoding: 'utf8' });
  assert.equal(help.status, 0, `${file} --help exit code`);
  assert.ok(help.stdout.split('\n').includes(`runner-if-version=${version}`), `${file} --help should print runner-if-version=${version}`);
}

// conf と work を、親ディレクトリも別になるように置く(<workDir>/a/conf と <workDir>/b/work)。ff.env は conf に置く
function arrangeConfAndWork(world) {
  world.confDir = path.join(world.workDir, 'a', 'conf');
  world.cwdDir = path.join(world.workDir, 'b', 'work');
  fs.mkdirSync(world.confDir, { recursive: true });
  fs.mkdirSync(world.cwdDir, { recursive: true });
  world.envPath = path.join(world.confDir, 'ff.env');
}

// 作業ディレクトリを指定して validate-config.sh を起動する。
// 契約の「作業ディレクトリ」はシェルの $PWD の論理パスのため、環境変数 PWD も作業ディレクトリに合わせて渡す
// (渡さないと、一時ディレクトリがシンボリックリンクを含む環境で $PWD が物理パスになり、期待する字面と食い違う)
function runValidateConfigIn(world, cwd, args) {
  flushEnv(world);
  const env = { ...process.env, RELAY_GATE_CONFIG_DIR: world.configDir, PWD: cwd };
  if (world.homeDir) {
    env.HOME = world.homeDir;
  }
  const proc = spawnSync(SCRIPT, args, { cwd, encoding: 'utf8', env });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  world.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
}

// ---- Given: error 行どうしの順(置換された 2 行目の Given) ----

Given(
  literal('RELAY_GATE_CONFIG_DIR に blue-job-map.csv も green-job-map.csv も無く、ff.env のあるディレクトリに relative/blue-runner.sh は無い'),
  function () {
    assertJobMapAbsent(this, 'blue');
    assertJobMapAbsent(this, 'green');
    assert.ok(!fs.existsSync(path.join(path.dirname(this.envPath), 'relative', 'blue-runner.sh')), 'relative/blue-runner.sh should not exist');
  },
);

// ---- Given: 相対パスの解決 ----

Given(
  literal(
    '一時ディレクトリ conf に ff.env があり、BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=./blue-runner.sh GREEN_RUNNER=./green-runner.sh RAPID_CROSSCHECK_RUNNER=./rapid-crosscheck-runner.sh RAPID_CROSSCHECK_WORKER=./rapid-crosscheck-worker.sh が書いてある',
  ),
  function () {
    arrangeConfAndWork(this);
    this.env = {
      BLUE_MODE: 'foreground',
      GREEN_MODE: 'background',
      RAPID_CROSSCHECK_MODE: 'background',
      BLUE_IMPL: 'blue-2.3.1',
      GREEN_IMPL: 'green-1.4.0',
      BLUE_RUNNER: './blue-runner.sh',
      GREEN_RUNNER: './green-runner.sh',
      RAPID_CROSSCHECK_RUNNER: './rapid-crosscheck-runner.sh',
      RAPID_CROSSCHECK_WORKER: './rapid-crosscheck-worker.sh',
    };
  },
);

Given(
  literal(
    'conf に実行可能な blue-runner.sh / green-runner.sh / rapid-crosscheck-runner.sh / rapid-crosscheck-worker.sh があり、両 runner は --help で "runner-if-version=1" を返す',
  ),
  function () {
    for (const name of ['blue-runner.sh', 'green-runner.sh', 'rapid-crosscheck-runner.sh', 'rapid-crosscheck-worker.sh']) {
      writeExecutableAt(path.join(this.confDir, name), RUNNER_STUB);
    }
    assertRespondsVersion(path.join(this.confDir, 'blue-runner.sh'), 1);
    assertRespondsVersion(path.join(this.confDir, 'green-runner.sh'), 1);
  },
);

Given(literal('RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある'), function () {
  writeJobMap(this, 'blue');
  writeJobMap(this, 'green');
});

// Scenario Outline「相対パスの基準を作業ディレクトリではなく設定ファイルのあるディレクトリにする」
Given(
  new RegExp(
    '^' +
      escapeRegExp(
        '一時ディレクトリ conf に ff.env があり、BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=',
      ) +
      // 2026-11-16: 同じ書き出しで GREEN_JOB_MAP_CSV=<value> が続く step(ジョブマップの場所の相対パス)と両方に一致しないよう、
      // GREEN_RUNNER の値の取り出しを「 GREEN_JOB_MAP_CSV=」の手前までに限った(この Scenario Outline の値は変わらない)
      '((?:(?! GREEN_JOB_MAP_CSV=).)+)' +
      escapeRegExp(' が書いてある') +
      '$',
  ),
  function (value) {
    arrangeConfAndWork(this);
    this.runnerValue = value;
    this.env = { ...GREEN_ONLY_KEYS, GREEN_RUNNER: value };
  },
);

// Examples の <location> は `conf/<名前>` または `conf の親の <相対パス>`
Given(
  new RegExp('^(.+)' + escapeRegExp(' に、--help で "runner-if-version=1" を返す実行可能な green スタブがある') + '$'),
  function (location) {
    const parentPrefix = 'conf の親の ';
    let file;
    if (location.startsWith(parentPrefix)) {
      file = path.join(path.dirname(this.confDir), location.slice(parentPrefix.length));
    } else {
      assert.ok(location.startsWith('conf/'), `unexpected location: ${location}`);
      file = path.join(this.confDir, location.slice('conf/'.length));
    }
    writeExecutableAt(file, RUNNER_STUB);
    assertRespondsVersion(file, 1);
  },
);

Given(
  literal(
    '作業ディレクトリにするディレクトリ work(conf とは別で、親ディレクトリも conf の親とは別)から見た同じ相対位置に、起動されたら記録を残し --help で "runner-if-version=9" を返す別の実行可能ファイルがある',
  ),
  function () {
    assert.notEqual(path.dirname(this.cwdDir), path.dirname(this.confDir));
    // work から見た <value> の位置(.. を含む値は work の親をたどる)。conf から見た位置とは別のファイルになる
    this.decoy = writeExecutableAt(path.join(this.cwdDir, this.runnerValue), DECOY_RUNNER_STUB);
    assert.notEqual(this.decoy, path.join(this.confDir, this.runnerValue));
    assertRespondsVersion(this.decoy, 9);
    fs.rmSync(`${this.decoy}.invoked`);
  },
);

// ---- Given: 設定ファイルのパスが相対パス / シンボリックリンク ----

Given(
  literal(
    'ディレクトリ work の下の conf/ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=green-runner.sh が書いてある',
  ),
  function () {
    this.cwdDir = path.join(this.workDir, 'b', 'work');
    this.confDir = path.join(this.cwdDir, 'conf');
    fs.mkdirSync(this.confDir, { recursive: true });
    this.envPath = path.join(this.confDir, 'ff.env');
    this.env = { ...GREEN_ONLY_KEYS, GREEN_RUNNER: 'green-runner.sh' };
  },
);

Given(literal('work/conf/green-runner.sh は --help で "runner-if-version=1" を返す実行可能なスタブで、work/green-runner.sh は無い'), function () {
  const runner = writeExecutableAt(path.join(this.cwdDir, 'conf', 'green-runner.sh'), RUNNER_STUB);
  assertRespondsVersion(runner, 1);
  assert.ok(!fs.existsSync(path.join(this.cwdDir, 'green-runner.sh')), 'work/green-runner.sh should not exist');
});

Given(
  literal(
    'ディレクトリ real に ff.env(BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=./green-runner.sh)があり、real に green-runner.sh は無い',
  ),
  function () {
    this.realDir = path.join(this.workDir, 'real');
    fs.mkdirSync(this.realDir);
    // ff.env の実体は real に書く(flushEnv の書き込み先)。検証には link 側のパスを渡す
    this.envPath = path.join(this.realDir, 'ff.env');
    this.env = { ...GREEN_ONLY_KEYS, GREEN_RUNNER: './green-runner.sh' };
    flushEnv(this);
    assert.ok(!fs.existsSync(path.join(this.realDir, 'green-runner.sh')), 'real/green-runner.sh should not exist');
  },
);

Given(
  literal(
    '別のディレクトリ link に、real/ff.env へのシンボリックリンク ff.env と、--help で "runner-if-version=1" を返す実行可能な green-runner.sh がある',
  ),
  function () {
    this.linkDir = path.join(this.workDir, 'link');
    fs.mkdirSync(this.linkDir);
    fs.symlinkSync(path.join(this.realDir, 'ff.env'), path.join(this.linkDir, 'ff.env'));
    assert.ok(fs.lstatSync(path.join(this.linkDir, 'ff.env')).isSymbolicLink());
    const runner = writeExecutableAt(path.join(this.linkDir, 'green-runner.sh'), RUNNER_STUB);
    assertRespondsVersion(runner, 1);
  },
);

// ---- Given: 実体が無いとき / ~・環境変数・コマンド置換 ----

Given(
  literal(
    '一時ディレクトリ conf の ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=./green-runner.sh が書いてあり、conf に green-runner.sh は無い',
  ),
  function () {
    arrangeConfAndWork(this);
    this.env = { ...GREEN_ONLY_KEYS, GREEN_RUNNER: './green-runner.sh' };
    assert.ok(!fs.existsSync(path.join(this.confDir, 'green-runner.sh')), 'conf/green-runner.sh should not exist');
  },
);

Given(literal('作業ディレクトリにするディレクトリ work(conf とは別)に実行可能な green-runner.sh がある'), function () {
  assert.notEqual(this.cwdDir, this.confDir);
  const runner = writeExecutableAt(path.join(this.cwdDir, 'green-runner.sh'), RUNNER_STUB);
  fs.accessSync(runner, fs.constants.X_OK);
});

// Scenario Outline「~ と環境変数とコマンド置換を展開せず文字のまま相対パスとして扱う」
Given(
  new RegExp(
    '^' +
      escapeRegExp(
        '一時ディレクトリ conf の ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=',
      ) +
      '(.+)' +
      escapeRegExp(' が書いてある') +
      '$',
  ),
  function (value) {
    arrangeConfAndWork(this);
    this.runnerValue = value;
    this.env = { ...GREEN_ONLY_KEYS, GREEN_RUNNER: value };
  },
);

Given(literal('環境変数 HOME のディレクトリに実行可能な green-runner.sh があり、conf に marker という名前のファイルは無い'), function () {
  // 検証コマンドへ渡す HOME を一時ディレクトリにし、そこへ実体を置く(~ や $HOME を展開する実装なら検証を通ってしまう)
  this.homeDir = path.join(this.workDir, 'home');
  const runner = writeExecutableAt(path.join(this.homeDir, 'green-runner.sh'), RUNNER_STUB);
  fs.accessSync(runner, fs.constants.X_OK);
  assert.ok(!fs.existsSync(path.join(this.confDir, 'marker')), 'conf/marker should not exist');
});

// ---- When ----

When(literal('ff.env のあるディレクトリを作業ディレクトリにして `validate-config.sh --feature-flag ff.env` を実行する'), function () {
  runValidateConfigIn(this, path.dirname(this.envPath), ['--feature-flag', 'ff.env']);
});

When(
  literal('conf とは別のディレクトリを作業ディレクトリにして `validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する'),
  function () {
    assert.notEqual(this.cwdDir, this.confDir);
    runValidateConfigIn(this, this.cwdDir, ['--feature-flag', path.join(this.confDir, 'ff.env')]);
  },
);

When(literal('work を作業ディレクトリにして `validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する'), function () {
  runValidateConfigIn(this, this.cwdDir, ['--feature-flag', path.join(this.confDir, 'ff.env')]);
});

When(literal('work を作業ディレクトリにして `validate-config.sh --feature-flag conf/ff.env` を実行する'), function () {
  runValidateConfigIn(this, this.cwdDir, ['--feature-flag', 'conf/ff.env']);
});

When(literal('`validate-config.sh --feature-flag <link の絶対パス>/ff.env` を実行する'), function () {
  runValidateConfigIn(this, this.workDir, ['--feature-flag', path.join(this.linkDir, 'ff.env')]);
});

When(literal('conf を作業ディレクトリにして `validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する'), function () {
  runValidateConfigIn(this, this.confDir, ['--feature-flag', path.join(this.confDir, 'ff.env')]);
});

// ---- Then ----

Then(literal('終了コード 0 で stderr は 0 行である'), function () {
  assertExit(this, 0);
  assert.deepEqual(stderrLines(this), [], `stderr should be empty\n--- stderr ---\n${this.result.stderr}`);
});

Then(
  literal(
    'stdout の 6 行目は "blue_runner: <conf の絶対パス>/./blue-runner.sh"、7 行目は "green_runner: <conf の絶対パス>/./green-runner.sh"、9 行目は "rapid_crosscheck_runner: <conf の絶対パス>/./rapid-crosscheck-runner.sh"、10 行目は "rapid_crosscheck_worker: <conf の絶対パス>/./rapid-crosscheck-worker.sh" である(契約 config_files.feature-flag.env.runner_path_resolution)',
  ),
  function () {
    // 解決後のパス = 基準のディレクトリ + / + 値(. を畳まない)
    const lines = stdoutLines(this);
    assert.equal(lines[5], `blue_runner: ${this.confDir}/./blue-runner.sh`, `stdout\n${this.result.stdout}`);
    assert.equal(lines[6], `green_runner: ${this.confDir}/./green-runner.sh`);
    assert.equal(lines[8], `rapid_crosscheck_runner: ${this.confDir}/./rapid-crosscheck-runner.sh`);
    assert.equal(lines[9], `rapid_crosscheck_worker: ${this.confDir}/./rapid-crosscheck-worker.sh`);
  },
);

Then(literal('stdout の最終行は "green_runner_if_version=1" である'), function () {
  const lines = stdoutLines(this);
  assert.equal(lines[lines.length - 1], 'green_runner_if_version=1', `stdout\n${this.result.stdout}`);
});

Then(
  new RegExp(
    '^' +
      escapeRegExp('終了コード 0 で stdout の 7 行目は "green_runner: <conf の絶対パス>/') +
      '(.+)' +
      escapeRegExp('"、最終行は "green_runner_if_version=1" である') +
      '$',
  ),
  function (value) {
    assert.equal(value, this.runnerValue, 'the <value> in Then should be the value written to ff.env');
    assertExit(this, 0);
    const lines = stdoutLines(this);
    assert.equal(lines[6], `green_runner: ${this.confDir}/${value}`, `stdout\n${this.result.stdout}`);
    assert.equal(lines[lines.length - 1], 'green_runner_if_version=1', `stdout\n${this.result.stdout}`);
  },
);

Then(literal('work から見た位置に置いた別の実行可能ファイルは起動されていない'), function () {
  assert.deepEqual(invocations(this.decoy), [], 'the executable placed relative to the working directory must not be invoked');
});

Then(
  literal(
    '終了コード 0 で stdout の 7 行目は "green_runner: <work の絶対パス>/conf/green-runner.sh" である(<work の絶対パス> は作業ディレクトリの論理パス = シェルの $PWD)',
  ),
  function () {
    assertExit(this, 0);
    assert.equal(stdoutLines(this)[6], `green_runner: ${this.cwdDir}/conf/green-runner.sh`, `stdout\n${this.result.stdout}`);
  },
);

Then(
  literal(
    '終了コード 0 で stdout の 7 行目は "green_runner: <link の絶対パス>/./green-runner.sh" である(リンク先のディレクトリ real は基準にしない)',
  ),
  function () {
    assertExit(this, 0);
    assert.equal(stdoutLines(this)[6], `green_runner: ${this.linkDir}/./green-runner.sh`, `stdout\n${this.result.stdout}`);
  },
);

Then(literal('stderr に "path is not absolute" を含む行は出ない'), function () {
  const hits = stderrLines(this).filter((line) => line.includes('path is not absolute'));
  assert.deepEqual(hits, [], `--- stderr ---\n${this.result.stderr}`);
});

// Examples の <value> は step 文中に 2 回現れる(error 行の path= と、末尾の注記)
Then(
  new RegExp(
    '^' +
      escapeRegExp('終了コード 2 で stderr は "error: file not executable key=GREEN_RUNNER path=<conf の絶対パス>/') +
      '(.+)' +
      escapeRegExp('" の 1 行だけである(') +
      '(.+)' +
      escapeRegExp(' は設定に書いた文字のまま)') +
      '$',
  ),
  function (value, valueInNote) {
    assert.equal(valueInNote, value, 'both <value> placeholders should carry the same example value');
    assert.equal(value, this.runnerValue, 'the <value> in Then should be the value written to ff.env');
    assertExit(this, 2);
    assert.deepEqual(
      stderrLines(this),
      [`error: file not executable key=GREEN_RUNNER path=${this.confDir}/${value}`],
      `stderr lines\n--- stderr ---\n${this.result.stderr}`,
    );
  },
);

Then(literal('conf に marker という名前のファイルは作られていない(コマンド置換の中身は実行されない)'), function () {
  assert.ok(!fs.existsSync(path.join(this.confDir, 'marker')), 'conf/marker must not be created');
});

// ==== S2 test-scaffold 再実行(2026-11-16。slot ジョブマップの場所を書く任意の 2 キー)で追加 ====
// 出典: tier-facade.md「ティア完了条件(BDD)」に足された Scenario 6 本と Scenario Outline 2 本
// (duplicate key の Examples の 1 行と、改名された Scenario「9 キーと任意の 2 キーのどちらでもないキーの値を…取り込まない」は既存 step のまま)。
// 規則の正本は cli-command-contract.yaml の config_files.feature-flag.env.job_map_location
// (BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV は任意。無い・空なら $RELAY_GATE_CONFIG_DIR/<slot>-job-map.csv。値からパスを決める規則は
// runner_path_resolution と同じ。off の slot のキーは解決も検査もしない。2 キーは未知キーではない)。
// 追加時点の実装は 2 キーを未知キーとして warn し(値が空の行も同じ)、固定の名前だけを見るため、2 キーを書く Scenario は実装が
// 追従するまで assertion failure で fail する(2 キーを書かない・名前が違うキー・2 キーの重複の Scenario は現行実装でも通る)。

const JOB_MAP_HEADER = 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\n';

// 一時ディレクトリ maps(RELAY_GATE_CONFIG_DIR とも ff.env のあるディレクトリとも別)を用意する
function ensureMapsDir(world) {
  world.mapsDir = path.join(world.workDir, 'maps');
  fs.mkdirSync(world.mapsDir, { recursive: true });
  assert.notEqual(world.mapsDir, world.configDir);
  return world.mapsDir;
}

function writeJobMapAt(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JOB_MAP_HEADER);
  return file;
}

function removeFixedNameJobMap(world, slot) {
  fs.rmSync(path.join(world.configDir, `${slot}-job-map.csv`), { force: true });
  assertJobMapAbsent(world, slot);
}

function assertFixedNameJobMapExists(world, slot) {
  assert.ok(fs.existsSync(path.join(world.configDir, `${slot}-job-map.csv`)), `${slot}-job-map.csv should exist in RELAY_GATE_CONFIG_DIR`);
}

function assertStderrEmptyWithExit0(world) {
  assertExit(world, 0);
  assert.deepEqual(stderrLines(world), [], `stderr should be empty\n--- stderr ---\n${world.result.stderr}`);
}

// ---- Given: 2 キーに絶対パスを書く / 2 キーを書かない / 値が空 ----

Given(
  literal(
    '有効な並行稼働設定に加えて BLUE_JOB_MAP_CSV=<一時ディレクトリ maps の絶対パス>/jobs.csv と GREEN_JOB_MAP_CSV=<一時ディレクトリ maps の絶対パス>/jobs.csv を書いた ff.env がある',
  ),
  function () {
    arrangeParallel(this);
    const maps = ensureMapsDir(this);
    this.env.BLUE_JOB_MAP_CSV = path.join(maps, 'jobs.csv');
    this.env.GREEN_JOB_MAP_CSV = path.join(maps, 'jobs.csv');
  },
);

Given(literal('maps に jobs.csv があり、RELAY_GATE_CONFIG_DIR に blue-job-map.csv も green-job-map.csv も無い'), function () {
  writeJobMapAt(path.join(this.mapsDir, 'jobs.csv'));
  // 有効な並行稼働設定の準備が置いた固定の名前のファイルを取り除く(固定の名前を見る実装なら job map not found になる)
  removeFixedNameJobMap(this, 'blue');
  removeFixedNameJobMap(this, 'green');
});

Given(literal('両 runner スタブは --help で "runner-if-version=1" を返す'), function () {
  for (const key of ['BLUE_RUNNER', 'GREEN_RUNNER']) {
    assertRespondsVersion(this.env[key], 1);
  }
});

Given(
  literal('一時ディレクトリ conf に 9 キーだけの有効な並行稼働設定 ff.env があり、conf に blue-job-map.csv も green-job-map.csv も無い'),
  function () {
    arrangeParallel(this);
    assert.equal(Object.keys(this.env).length, 9);
    // ff.env の置き場を conf へ移す(runner の実体は絶対パスで書いてあるため、置き場を移しても解決先は変わらない)
    arrangeConfAndWork(this);
    assert.ok(!fs.existsSync(path.join(this.confDir, 'blue-job-map.csv')), 'conf/blue-job-map.csv should not exist');
    assert.ok(!fs.existsSync(path.join(this.confDir, 'green-job-map.csv')), 'conf/green-job-map.csv should not exist');
  },
);

Given(literal('conf とは別のディレクトリを指す RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある'), function () {
  assert.notEqual(this.configDir, this.confDir);
  assertFixedNameJobMapExists(this, 'blue');
  assertFixedNameJobMapExists(this, 'green');
});

// Scenario Outline「値が空のキーと書いていないキーの slot に固定の名前を使う」。
// Examples の <lines> は step 文中に 2 回現れる(書く行と、区切りの注記)。「 と 」で区切った各行を 9 キーの後に書く
Given(
  new RegExp(
    '^' +
      escapeRegExp('有効な並行稼働設定(9 キー)に加えて ') +
      '(.+)' +
      escapeRegExp(' を書いた ff.env がある(') +
      '(.+)' +
      escapeRegExp(' の「 と 」は行の区切り)') +
      '$',
  ),
  function (lines, linesInNote) {
    assert.equal(linesInNote, lines, 'both <lines> placeholders should carry the same example value');
    arrangeParallel(this);
    ensureMapsDir(this);
    const added = lines.split(' と ').map((line) => expandPathPlaceholders(this, line));
    arrangeRawLines(this, [...envLines(this), ...added]);
  },
);

Given(
  literal('一時ディレクトリ maps に blue-jobs.csv と green-jobs.csv があり、RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある'),
  function () {
    writeJobMapAt(path.join(this.mapsDir, 'blue-jobs.csv'));
    writeJobMapAt(path.join(this.mapsDir, 'green-jobs.csv'));
    assertFixedNameJobMapExists(this, 'blue');
    assertFixedNameJobMapExists(this, 'green');
  },
);

// ---- Given: 相対パスのジョブマップの場所 ----

// Scenario Outline「相対パスのジョブマップの場所を作業ディレクトリではなく設定ファイルのあるディレクトリ基準で解決する」
Given(
  new RegExp(
    '^' +
      escapeRegExp(
        '一時ディレクトリ conf に ff.env があり、BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> GREEN_JOB_MAP_CSV=',
      ) +
      '(.+)' +
      escapeRegExp(' が書いてある') +
      '$',
  ),
  function (value) {
    arrangeConfAndWork(this);
    this.jobMapValue = value;
    this.env = { ...GREEN_ONLY_KEYS, GREEN_RUNNER: writeRunner(this, 'green-runner.sh'), GREEN_JOB_MAP_CSV: value };
    assertRespondsVersion(this.env.GREEN_RUNNER, 1);
  },
);

// Examples の <location> は `conf/<名前>` または `conf の親の <相対パス>`
Given(
  new RegExp(
    '^(.+)' +
      escapeRegExp(
        ' にジョブマップがあり、作業ディレクトリにするディレクトリ work(conf とは別で、親ディレクトリも conf の親とは別)から見た同じ相対位置にファイルは無い',
      ) +
      '$',
  ),
  function (location) {
    const parentPrefix = 'conf の親の ';
    let file;
    if (location.startsWith(parentPrefix)) {
      file = path.join(path.dirname(this.confDir), location.slice(parentPrefix.length));
    } else {
      assert.ok(location.startsWith('conf/'), `unexpected location: ${location}`);
      file = path.join(this.confDir, location.slice('conf/'.length));
    }
    writeJobMapAt(file);
    // 設定ファイルのあるディレクトリから値をたどった先が、置いたファイルである
    assert.equal(path.join(this.confDir, this.jobMapValue), file);
    assert.notEqual(path.dirname(this.cwdDir), path.dirname(this.confDir));
    assert.ok(!fs.existsSync(path.join(this.cwdDir, this.jobMapValue)), 'no file at the same relative position from work');
  },
);

Given(literal('RELAY_GATE_CONFIG_DIR に green-job-map.csv は無い'), function () {
  assertJobMapAbsent(this, 'green');
});

Given(
  literal(
    '一時ディレクトリ conf の ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> GREEN_JOB_MAP_CSV=./green-jobs.csv が書いてあり、conf に green-jobs.csv は無い',
  ),
  function () {
    arrangeConfAndWork(this);
    this.env = { ...GREEN_ONLY_KEYS, GREEN_RUNNER: writeRunner(this, 'green-runner.sh'), GREEN_JOB_MAP_CSV: './green-jobs.csv' };
    assertRespondsVersion(this.env.GREEN_RUNNER, 1);
    assert.ok(!fs.existsSync(path.join(this.confDir, 'green-jobs.csv')), 'conf/green-jobs.csv should not exist');
  },
);

Given(literal('作業ディレクトリにするディレクトリ work(conf とは別)に green-jobs.csv がある'), function () {
  assert.notEqual(this.cwdDir, this.confDir);
  // 作業ディレクトリを基準にする実装なら、このファイルを見つけて検証を通してしまう
  writeJobMapAt(path.join(this.cwdDir, 'green-jobs.csv'));
});

// ---- Given: 書いた場所に無い / off の slot / 名前が違うキー ----

Given(
  literal(
    '有効な並行稼働設定に加えて BLUE_JOB_MAP_CSV=<一時ディレクトリ maps の絶対パス>/missing.csv を書いた ff.env がある(GREEN_JOB_MAP_CSV は書かない)',
  ),
  function () {
    arrangeParallel(this);
    const maps = ensureMapsDir(this);
    this.env.BLUE_JOB_MAP_CSV = path.join(maps, 'missing.csv');
    assert.ok(!('GREEN_JOB_MAP_CSV' in this.env));
  },
);

Given(literal('maps に missing.csv は無く、RELAY_GATE_CONFIG_DIR に blue-job-map.csv があり green-job-map.csv は無い'), function () {
  assert.ok(!fs.existsSync(path.join(this.mapsDir, 'missing.csv')), 'maps/missing.csv should not exist');
  assertFixedNameJobMapExists(this, 'blue');
  removeFixedNameJobMap(this, 'green');
});

Given(
  literal(
    'ff.env に BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off GREEN_IMPL=green-1.4.0 GREEN_RUNNER=<実行可能。--help で runner-if-version=1 を返す> BLUE_JOB_MAP_CSV=/nonexistent/blue-jobs.csv を書く',
  ),
  function () {
    this.env = { ...GREEN_ONLY_KEYS, GREEN_RUNNER: writeRunner(this, 'green-runner.sh'), BLUE_JOB_MAP_CSV: '/nonexistent/blue-jobs.csv' };
    assertRespondsVersion(this.env.GREEN_RUNNER, 1);
    assert.ok(!fs.existsSync('/nonexistent/blue-jobs.csv'));
  },
);

Given(literal('RELAY_GATE_CONFIG_DIR に green-job-map.csv がある(blue-job-map.csv は無い)'), function () {
  writeJobMap(this, 'green');
  assertJobMapAbsent(this, 'blue');
});

Given(
  literal(
    '有効な並行稼働設定の最終行の後に BLUE_JOB_MAP=<一時ディレクトリ maps の絶対パス>/blue-jobs.csv と green_job_map_csv=<一時ディレクトリ maps の絶対パス>/green-jobs.csv の 2 行を書いた ff.env がある',
  ),
  function () {
    arrangeParallel(this);
    const maps = ensureMapsDir(this);
    arrangeRawLines(this, [
      ...envLines(this),
      `BLUE_JOB_MAP=${path.join(maps, 'blue-jobs.csv')}`,
      `green_job_map_csv=${path.join(maps, 'green-jobs.csv')}`,
    ]);
  },
);

Given(literal('maps に blue-jobs.csv と green-jobs.csv があり、RELAY_GATE_CONFIG_DIR に blue-job-map.csv と green-job-map.csv がある'), function () {
  writeJobMapAt(path.join(this.mapsDir, 'blue-jobs.csv'));
  writeJobMapAt(path.join(this.mapsDir, 'green-jobs.csv'));
  assertFixedNameJobMapExists(this, 'blue');
  assertFixedNameJobMapExists(this, 'green');
});

// ---- When ----

When(literal('`validate-config.sh --feature-flag <conf の絶対パス>/ff.env` を実行する'), function () {
  // 作業ディレクトリは conf でも RELAY_GATE_CONFIG_DIR でもない一時ディレクトリにする
  runValidateConfigIn(this, this.workDir, ['--feature-flag', path.join(this.confDir, 'ff.env')]);
});

// ---- Then ----

// 「終了コード 0 で stderr は 0 行である(注記)」: 注記つきの 3 通り(warn: unknown key が出ない / 値が空のキーに error も warn も出ない /
// job map not found も warn: unknown key も出ない)は、どれも stderr が 1 行も無いことで判定する
Then(/^終了コード 0 で stderr は 0 行である\(.+\)$/, function () {
  assertStderrEmptyWithExit0(this);
});

Then(
  literal('stdout は 15 行で、12 行目は "blue_job_map: <maps の絶対パス>/jobs.csv"、13 行目は "green_job_map: <maps の絶対パス>/jobs.csv" である'),
  function () {
    const lines = stdoutLines(this);
    assert.equal(lines.length, 15, `stdout lines\n${this.result.stdout}`);
    assert.equal(lines[11], `blue_job_map: ${path.join(this.mapsDir, 'jobs.csv')}`, `stdout\n${this.result.stdout}`);
    assert.equal(lines[12], `green_job_map: ${path.join(this.mapsDir, 'jobs.csv')}`, `stdout\n${this.result.stdout}`);
  },
);

// 「stdout の 12 行目は "blue_job_map: <場所>"、13 行目は "green_job_map: <場所>" である」:
// <場所> は <RELAY_GATE_CONFIG_DIR>/... または <maps の絶対パス>/... または -(off の slot)
Then(/^stdout の 12 行目は "blue_job_map: (.+)"、13 行目は "green_job_map: (.+)" である$/, function (blue, green) {
  const lines = stdoutLines(this);
  assert.equal(lines[11], `blue_job_map: ${expandPathPlaceholders(this, blue)}`, `stdout\n${this.result.stdout}`);
  assert.equal(lines[12], `green_job_map: ${expandPathPlaceholders(this, green)}`, `stdout\n${this.result.stdout}`);
});

Then(
  new RegExp(
    '^' +
      escapeRegExp('終了コード 0 で stdout の 13 行目は "green_job_map: <conf の絶対パス>/') +
      '(.+)' +
      escapeRegExp('" である(`.`・`..` を畳まない。契約 config_files.feature-flag.env の job_map_location / runner_path_resolution)') +
      '$',
  ),
  function (value) {
    assert.equal(value, this.jobMapValue, 'the <value> in Then should be the value written to ff.env');
    assertExit(this, 0);
    // 解決後のパス = 設定ファイルのあるディレクトリ + / + 値(. と .. を畳まない)
    assert.equal(stdoutLines(this)[12], `green_job_map: ${this.confDir}/${value}`, `stdout\n${this.result.stdout}`);
  },
);

Then(
  literal(
    '終了コード 0 で stderr は "warn: unknown key key=BLUE_JOB_MAP path: ff.env" / "warn: unknown key key=green_job_map_csv path: ff.env" の 2 行だけがこの順に出る(キーの比較は大文字小文字を区別した完全一致)',
  ),
  function () {
    assertExit(this, 0);
    assert.deepEqual(
      stderrLines(this),
      ['warn: unknown key key=BLUE_JOB_MAP path: ff.env', 'warn: unknown key key=green_job_map_csv path: ff.env'],
      `stderr lines\n--- stderr ---\n${this.result.stderr}`,
    );
  },
);
