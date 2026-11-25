// tier BDD(③)の step 定義: ジョブマップで JOB_ID から実行先を解決する(uc_id=7c41c7cd、tier-facade)。
// feature: facade/features/resolve-execution-target-from-job-map.feature(tier-facade.md「ティア完了条件(BDD)」の転写)。
// S2 test-scaffold が生成した skeleton の step 文言(feature から転写したリテラル)を完全一致の正規表現で受け、S4 で実装した。
// ここに定義するのは、同じディレクトリの既存の step 定義に一致しない文言だけ(既存の step と同じ文言を再定義しない)。
// World と Before / After は configure-feature-flags.steps.js のものを使う(ここには置かない)。
// I/O 境界は実体で検証する:
//   - 「実行する」: 標準の slot runner(facade/runners/standard-runner.sh)を、facade が渡すのと同じ環境変数と runner IF の引数で
//     実プロセスとして起動する。終了コード・成果物ファイル・実行ログを見る
//   - 「解決フェーズまで実行する」: 上と同じ起動(実行ログを見る)に加えて、自作の runner と同じく共通ライブラリ
//     (facade/lib/runner-resolve.sh)を source して resolve_execution_target を直接呼び、解決結果と引数列を受け取る。
//     解決結果のうち実行ログに出ない項目(user / script / work_dir / 引数列など)は、後続の機能(execution-spec.json の保存・実装の実行)が
//     できるまで runner の外から見えないため(docs/impl/latest/7c41c7cd/issues/20261123_142047_cross-uc-scenarios.md の 4)。
//     関数の名前・引数・結果の受け取り方は契約 runner IF の standard_runner.runner_resolve_library(spec-decision-042)
//   - 「CSV 行分解関数 `parse_csv_row` …を呼ぶ」「引数連結関数 `build_argument_list` …を呼ぶ」: 同じ共通ライブラリの関数を直接呼ぶ
//   - 「自作の runner が … を呼ぶ」: 自作の runner と同じく、別の bash プロセスで lib/runner-resolve.sh を source し、
//     契約 runner IF の standard_runner.runner_resolve_library の呼び方で関数を呼ぶ(ファイル末尾。2026-11-24 の再実行で追加)
// Given が要点だけを書いている Scenario は、書かれていない列を仕様のほかの Scenario の例示の値で補う(同 issue の 5。書かれた値は変えない)。
// この機能は管理 DB に触らない(一時 PostgreSQL を起動しない。RAPID_CROSSCHECK_MODE=off)。
// リポジトリの中にはファイルを書かない。書くのは Before が作る一時ディレクトリ(this.workDir)の中だけ。
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

// 配置ディレクトリ(RELAY_GATE_HOME)は tier dir(facade/)。契約 standard_runner.home: runners/ の 1 つ上
const FACADE_HOME = path.resolve(__dirname, '../..');
const STANDARD_RUNNER = path.join(FACADE_HOME, 'runners', 'standard-runner.sh');
const RESOLVE_LIBRARY = path.join(FACADE_HOME, 'lib', 'runner-resolve.sh');
const RUNNER_SCRIPT_NAME = 'standard-runner.sh';

const HEADER_7 = 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes';
// 仕様のほかの Scenario の例示の行(Given が行を書いていないときに補う)
const ROW_JOB001 = 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60';
const ROW_JOB999 = 'JOB999,host-green-01,batch,/var/app/work,/opt/app/bin/job999.sh,[],60';

const RESULT_FILES = ['started-at.txt', 'stdout.log', 'stderr.log', 'exitcode.txt'];

// 文言そのものに一致する正規表現(cucumber 式の記号を解釈させない)
function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

// ---- 置き場(Scenario ごとの一時ディレクトリの下) ----

function artifactRoot(world) {
  return path.join(world.workDir, 'artifacts');
}

function logDir(world) {
  return path.join(world.workDir, 'logs');
}

function mapsDir(world) {
  if (!world.mapsDir) {
    world.mapsDir = path.join(world.workDir, 'maps');
    fs.mkdirSync(world.mapsDir, { recursive: true });
  }
  return world.mapsDir;
}

function defaultMap(world, slot) {
  return path.join(world.configDir, `${slot}-job-map.csv`);
}

// feature のパスの置き場を、Scenario が用意した実際のパスへ置き換える
function expandPlaceholders(world, text) {
  return text.split('<RELAY_GATE_CONFIG_DIR>').join(world.configDir).split('<maps>').join(mapsDir(world));
}

// ジョブマップを書く(1 行目ヘッダー、2 行目以降は行。改行は LF)。続く Given の「行がある」は、最後に書いたジョブマップへ足す
function writeMap(world, file, header, rows) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, [header, ...rows].map((line) => `${line}\n`).join(''));
  world.currentMap = file;
}

function appendRow(world, row) {
  assert.ok(world.currentMap, 'a job map header should be given before a row');
  fs.appendFileSync(world.currentMap, `${row}\n`);
}

// runner へ渡す環境変数のうち、ジョブマップの場所(Scenario が設定したものだけ。未設定は渡さない)
function jobMapEnv(world) {
  return world.jobMapEnv || {};
}

// facade が runner へ渡すのと同じ環境変数(契約 commands「$BLUE_RUNNER / $GREEN_RUNNER」の environment)。テストのプロセスの環境は引き継がない
function runnerEnv(world, role, overrides) {
  const env = {
    PATH: process.env.PATH,
    RELAY_GATE_CONFIG_DIR: world.configDir,
    RELAY_GATE_ARTIFACT_ROOT: artifactRoot(world),
    RELAY_GATE_LOG_DIR: logDir(world),
    RAPID_CROSSCHECK_MODE: 'off',
    [`${role.toUpperCase()}_IMPL`]: `${role}-1.0.0`,
    ...jobMapEnv(world),
    ...overrides,
  };
  if (process.env.TMPDIR) {
    env.TMPDIR = process.env.TMPDIR;
  }
  return env;
}

// step 文言のバッククォートの中の runner IF の引数を読む(先頭の <runner> などの実体の表記は除く)
function parseInvocation(text) {
  const command = text.match(/`([^`]+)`/)[1];
  const tokens = command.split(' ').slice(1);
  const invocation = { args: tokens, runId: null, jobId: null, role: null, params: [] };
  for (let index = 0; index < tokens.length; index += 1) {
    if (tokens[index] === '--') {
      invocation.params = tokens.slice(index + 1);
      break;
    }
    if (tokens[index] === '--run-id') invocation.runId = tokens[index + 1];
    if (tokens[index] === '--job-id') invocation.jobId = tokens[index + 1];
    if (tokens[index] === '--role') invocation.role = tokens[index + 1];
  }
  return invocation;
}

function roleDir(world, invocation) {
  return path.join(artifactRoot(world), 'facade', invocation.runId, invocation.role);
}

// 標準の slot runner を実プロセスとして起動する。role ディレクトリは facade が作るもの(runner を直接起動するここでは、起動前に用意する)。
// runner はプロセスの stdout / stderr に出さない(runner IF)ことも、起動のたびに確かめる
function runRunner(world, invocation) {
  fs.mkdirSync(roleDir(world, invocation), { recursive: true });
  const proc = spawnSync(STANDARD_RUNNER, invocation.args, {
    cwd: world.workDir,
    encoding: 'utf8',
    env: runnerEnv(world, invocation.role, {}),
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  assert.equal(proc.stdout, '', `the runner should not write to stdout\n${proc.stdout}`);
  assert.equal(proc.stderr, '', `the runner should not write to stderr\n${proc.stderr}`);
  world.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
  world.lastInvocation = invocation;
}

// 共通ライブラリを source して関数を呼び、結果のグローバル変数を `名前=値` の行で受け取る bash の断片
const LIBRARY_PRELUDE = ['set -u', 'source "$1"', 'shift', 'status=0'];
const PRINT_STATUS = "printf 'status=%s\\n' \"$status\"";
const RESOLVE_SCRIPT = [
  ...LIBRARY_PRELUDE,
  'resolve_execution_target "$@" || status=$?',
  PRINT_STATUS,
  "printf 'host=%s\\n' \"$EXECUTION_TARGET_HOST\"",
  "printf 'user=%s\\n' \"$EXECUTION_TARGET_USER\"",
  "printf 'script=%s\\n' \"$EXECUTION_TARGET_SCRIPT\"",
  "printf 'work_dir=%s\\n' \"$EXECUTION_TARGET_WORK_DIR\"",
  "printf 'hang_detect_limit_minutes=%s\\n' \"$EXECUTION_TARGET_HANG_DETECT_LIMIT_MINUTES\"",
  "printf 'credential_ref=%s\\n' \"$EXECUTION_TARGET_CREDENTIAL_REF\"",
  "printf 'map_version=%s\\n' \"$EXECUTION_TARGET_MAP_VERSION\"",
  "printf 'exec=%s\\n' \"$EXECUTION_TARGET_EXEC\"",
  'for value in ${ARGUMENT_LIST[@]+"${ARGUMENT_LIST[@]}"}; do printf \'arg=%s\\n\' "$value"; done',
].join('\n');
const PARSE_CSV_ROW_SCRIPT = [
  ...LIBRARY_PRELUDE,
  'parse_csv_row "$1" || status=$?',
  PRINT_STATUS,
  'for value in ${CSV_CELLS[@]+"${CSV_CELLS[@]}"}; do printf \'cell=%s\\n\' "$value"; done',
].join('\n');
const BUILD_ARGUMENT_LIST_SCRIPT = [
  ...LIBRARY_PRELUDE,
  'build_argument_list "$@" || status=$?',
  PRINT_STATUS,
  'for value in ${ARGUMENT_LIST[@]+"${ARGUMENT_LIST[@]}"}; do printf \'arg=%s\\n\' "$value"; done',
].join('\n');

// 断片を実行し、`名前=値` の行を読む(同じ名前が複数あれば配列の要素。値は改行を含まない)
function callLibrary(world, script, args, env) {
  // 断片はファイルにして渡す(`bash -c` は、標準入力がソケットのとき利用者の ~/.bashrc を読むことがあり、テストの環境に左右される)
  const scriptFile = path.join(world.workDir, 'library-call.sh');
  fs.writeFileSync(scriptFile, `${script}\n`);
  const proc = spawnSync('bash', [scriptFile, RESOLVE_LIBRARY, ...args], {
    cwd: world.workDir,
    encoding: 'utf8',
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  assert.equal(proc.status, 0, `the library call should finish\n--- stdout ---\n${proc.stdout}\n--- stderr ---\n${proc.stderr}`);
  assert.equal(proc.stderr, '', `the library should not write to stderr\n${proc.stderr}`);
  const values = {};
  const lists = { arg: [], cell: [] };
  for (const line of proc.stdout.split('\n').slice(0, -1)) {
    const separator = line.indexOf('=');
    const name = line.slice(0, separator);
    const value = line.slice(separator + 1);
    if (name in lists) {
      lists[name].push(value);
    } else {
      values[name] = value;
    }
  }
  return { ...values, args: lists.arg, cells: lists.cell };
}

// 共通ライブラリの resolve_execution_target を直接呼ぶ。実行ログと成果物の置き場は、実プロセスの起動のものと分ける
// (実行ログの Then が見るのは実プロセスの実行ログだけにする)
function resolveWithLibrary(world, invocation) {
  const env = runnerEnv(world, invocation.role, {
    RELAY_GATE_ARTIFACT_ROOT: path.join(world.workDir, 'library-artifacts'),
    RELAY_GATE_LOG_DIR: path.join(world.workDir, 'library-logs'),
  });
  const resolved = callLibrary(world, RESOLVE_SCRIPT, [RUNNER_SCRIPT_NAME, invocation.runId, invocation.jobId, invocation.role, ...invocation.params], env);
  world.resolved = resolved;
  world.resolvedByRole = { ...(world.resolvedByRole || {}), [invocation.role]: resolved };
}

function runResolvePhase(world, invocation) {
  runRunner(world, invocation);
  resolveWithLibrary(world, invocation);
}

// ---- 確かめる ----

function dump(world) {
  return `--- exit code ---\n${world.result && world.result.status}\n--- execution log ---\n${readLog(world)}`;
}

function readLog(world) {
  const file = path.join(logDir(world), `${RUNNER_SCRIPT_NAME}.log`);
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
}

// 実行ログに、行形式 `{script} {run_id} {ローカル日時} {LEVEL} {message}` で LEVEL と message の行がある
function assertLogLine(world, level, message) {
  const pattern = /^(\S+) (\S+) (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}) (\S+) (.*)$/;
  const hit = readLog(world)
    .split('\n')
    .map((line) => line.match(pattern))
    .some((match) => match && match[1] === RUNNER_SCRIPT_NAME && match[4] === level && match[5] === message);
  assert.ok(hit, `execution log should include "${level} ${message}"\n${dump(world)}`);
}

function assertResolvedLogged(world, message) {
  assertLogLine(world, 'INFO', message);
}

function assertExit(world, code) {
  assert.equal(world.result.status, code, `exit code\n${dump(world)}`);
}

function readResultFile(world, name) {
  return fs.readFileSync(path.join(roleDir(world, world.lastInvocation), name), 'utf8');
}

function assertExitcodeFile(world, code) {
  assert.equal(readResultFile(world, 'exitcode.txt'), `${code}\n`, 'exitcode.txt should be one line');
}

function assertStderrLogIncludes(world, expected) {
  const lines = readResultFile(world, 'stderr.log').split('\n');
  assert.ok(lines.includes(expected), `stderr.log should include line "${expected}"\n--- stderr.log ---\n${lines.join('\n')}`);
}

// 解決フェーズの失敗は終了コード 2(検証エラー)。成功したときは、後続の段が無い間の仮の終了コード(前提)で、成果物を書かない
function assertResolved(world, resolved) {
  assert.equal(resolved.status, '0', `resolve_execution_target should succeed: ${JSON.stringify(resolved)}`);
  assert.notEqual(world.result.status, 2, `the runner should not fail the resolve phase\n${dump(world)}`);
}

// 「host=... user=... script=...」の並びを読む(null は、列が無い・値が空 = 空文字)
function expectedTarget(text) {
  const expected = {};
  for (const match of text.matchAll(/([a-z_]+)=([^\s()()]+)/g)) {
    expected[match[1]] = match[2] === 'null' ? '' : match[2];
  }
  return expected;
}

function assertTarget(world, resolved, text) {
  assertResolved(world, resolved);
  const expected = expectedTarget(text);
  assert.ok(Object.keys(expected).length > 0, `step should list resolved values: ${text}`);
  for (const [name, value] of Object.entries(expected)) {
    assert.equal(resolved[name], value, `resolved ${name}: ${JSON.stringify(resolved)}`);
  }
}

// ---- Given: ジョブマップ ----

Given(
  literal(
    'RELAY_GATE_CONFIG_DIR/green-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version" である',
  ),
  function () {
    writeMap(this, defaultMap(this, 'green'), `${HEADER_7},credential_ref,map_version`, []);
  },
);

Given(
  literal("CSV 行 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,\"[\"\"--mode\"\",\"\"full\"\"]\",60,ssh-key-green,map-v3' がある"),
  function () {
    appendRow(this, 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[""--mode"",""full""]",60,ssh-key-green,map-v3');
  },
);

Given(literal('環境変数 GREEN_JOB_MAP_CSV は未設定である(既定の場所を使う)'), function () {
  assert.ok(!('GREEN_JOB_MAP_CSV' in jobMapEnv(this)));
});

// Scenario「parse_csv_row は二重化された二重引用符を 1 文字に戻す」: ジョブマップのファイルではなく、関数へ渡す 1 行
Given(literal("CSV 行 'JOB001,,,/var/app/work,/opt/app/bin/job001.sh,\"[\"\"p1\"\",\"\"p2 p3\"\",\"\"a,b\"\"]\",60' がある"), function () {
  this.csvLine = 'JOB001,,,/var/app/work,/opt/app/bin/job001.sh,"[""p1"",""p2 p3"",""a,b""]",60';
});

Given(literal('RELAY_GATE_CONFIG_DIR/blue-job-map.csv のヘッダーが "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" である'), function () {
  writeMap(this, defaultMap(this, 'blue'), 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes', []);
});

Given(literal('行 "JOB001,/var/app/work,/opt/app/bin/job001.sh,[],0" がある'), function () {
  appendRow(this, 'JOB001,/var/app/work,/opt/app/bin/job001.sh,[],0');
});

// ヘッダーで拒否される Scenario(行は読まれない。書かれていないため置かない)
Given(literal('RELAY_GATE_CONFIG_DIR/green-job-map.csv のヘッダーが "job_id,host,work_dir,script,fixed_params,hang_detect_limit_minutes" である'), function () {
  writeMap(this, defaultMap(this, 'green'), 'job_id,host,work_dir,script,fixed_params,hang_detect_limit_minutes', []);
});

// Given は行を書いていない。JOB001 の行を例示の値で補う(未知列 impl_version のセルは任意の値)
Given(
  literal('RELAY_GATE_CONFIG_DIR/green-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,impl_version" である'),
  function () {
    writeMap(this, defaultMap(this, 'green'), `${HEADER_7},impl_version`, [`${ROW_JOB001},green-1.4.0`]);
  },
);

Given(literal('fixed_params が ["p1","p2 p3","a,b"] で PARAM が x y である'), function () {
  this.fixedParams = '["p1","p2 p3","a,b"]';
  this.params = ['x', 'y'];
});

// 「JOB999 の行が無い」: 例示の JOB001 の行だけがある
Given(literal('RELAY_GATE_CONFIG_DIR/green-job-map.csv に JOB999 の行が無い'), function () {
  writeMap(this, defaultMap(this, 'green'), HEADER_7, [ROW_JOB001]);
});

Given(literal('正しいジョブマップがある'), function () {
  writeMap(this, defaultMap(this, 'green'), HEADER_7, [ROW_JOB001]);
});

Given(
  literal(
    'RELAY_GATE_CONFIG_DIR/green-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" で、行 "JOB001,host-default-99,other,/var/default,/opt/default/job001.sh,[],60" がある',
  ),
  function () {
    writeMap(this, defaultMap(this, 'green'), HEADER_7, ['JOB001,host-default-99,other,/var/default,/opt/default/job001.sh,[],60']);
  },
);

Given(
  literal(
    'RELAY_GATE_CONFIG_DIR とは別のディレクトリ maps の green-jobs.csv のヘッダーが同じ 7 列で、行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60" がある',
  ),
  function () {
    assert.notEqual(mapsDir(this), this.configDir);
    writeMap(this, path.join(mapsDir(this), 'green-jobs.csv'), HEADER_7, [ROW_JOB001]);
  },
);

Given(literal('環境変数 GREEN_JOB_MAP_CSV=<maps>/green-jobs.csv が設定されている'), function () {
  this.jobMapEnv = { ...jobMapEnv(this), GREEN_JOB_MAP_CSV: path.join(mapsDir(this), 'green-jobs.csv') };
});

Given(
  literal(
    'RELAY_GATE_CONFIG_DIR/green-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" で、行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60" がある',
  ),
  function () {
    writeMap(this, defaultMap(this, 'green'), HEADER_7, [ROW_JOB001]);
  },
);

Given(literal('環境変数 GREEN_JOB_MAP_CSV が空文字で設定されている'), function () {
  this.jobMapEnv = { ...jobMapEnv(this), GREEN_JOB_MAP_CSV: '' };
});

Given(literal('RELAY_GATE_CONFIG_DIR/green-job-map.csv に JOB999 の行がある'), function () {
  writeMap(this, defaultMap(this, 'green'), HEADER_7, [ROW_JOB999]);
});

Given(literal('RELAY_GATE_CONFIG_DIR とは別のディレクトリ maps の green-jobs.csv に JOB999 の行が無い'), function () {
  writeMap(this, path.join(mapsDir(this), 'green-jobs.csv'), HEADER_7, [ROW_JOB001]);
});

Given(literal('RELAY_GATE_CONFIG_DIR/green-job-map.csv に JOB001 の行がある'), function () {
  writeMap(this, defaultMap(this, 'green'), HEADER_7, [ROW_JOB001]);
});

Given(literal('RELAY_GATE_CONFIG_DIR とは別のディレクトリ maps に green-jobs.csv は存在しない'), function () {
  assert.ok(!fs.existsSync(path.join(mapsDir(this), 'green-jobs.csv')));
});

Given(
  literal(
    'RELAY_GATE_CONFIG_DIR/blue-job-map.csv のヘッダーが "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" で、行 "JOB001,,,/var/app/work,/opt/app/bin/job001.sh,[],0"(host と user が両方空)がある',
  ),
  function () {
    writeMap(this, defaultMap(this, 'blue'), HEADER_7, ['JOB001,,,/var/app/work,/opt/app/bin/job001.sh,[],0']);
  },
);

Given(
  literal('RELAY_GATE_CONFIG_DIR/green-job-map.csv のヘッダーが同じ 7 列で、行 "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60" がある'),
  function () {
    writeMap(this, defaultMap(this, 'green'), HEADER_7, [ROW_JOB001]);
  },
);

Given(literal('環境変数 BLUE_JOB_MAP_CSV と GREEN_JOB_MAP_CSV は未設定である'), function () {
  assert.ok(!('BLUE_JOB_MAP_CSV' in jobMapEnv(this)));
  assert.ok(!('GREEN_JOB_MAP_CSV' in jobMapEnv(this)));
});

// ---- When ----

// 「解決フェーズまで実行する」: 実プロセスの起動 + 共通ライブラリの直接呼び出し
for (const text of [
  '`<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background -- 20260830` を解決フェーズまで実行する',
  '`<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role blue --mode foreground` を解決フェーズまで実行する',
  '`<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background` を解決フェーズまで実行する',
  '標準の slot runner を `<RELAY_GATE_HOME>/runners/standard-runner.sh --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role blue --mode foreground` で解決フェーズまで実行する',
  '同じ実体を `<RELAY_GATE_HOME>/runners/standard-runner.sh --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background` で解決フェーズまで実行する',
]) {
  When(literal(text), function () {
    runResolvePhase(this, parseInvocation(text));
  });
}

// 「実行する」: 実プロセスの起動だけ(終了コード・成果物・実行ログを見る)
for (const text of [
  '`<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --job-id JOB001 --role green --mode background` を実行する',
  '`<runner> --run-id 20260830T113000-JOB999-a1b2c3d4 --job-id JOB999 --role green --mode background` を実行する',
  '`<runner> --run-id 20260830T113000-JOB001-3f9a1c2e --role green --mode background` を実行する',
]) {
  When(literal(text), function () {
    runRunner(this, parseInvocation(text));
  });
}

// 2026-11-24 S2 scoped 再実行: 仕様の文言が関数名と結果の配列名を明示する形に変わった(契約 runner IF の standard_runner.runner_resolve_library)。
// 呼ぶ関数と確かめる内容は前の文言と同じため、既存の step の文言だけを新しい文言へ置き換えた
When(literal('CSV 行分解関数 `parse_csv_row` にこの行を渡して呼ぶ(呼び方は契約 runner IF の standard_runner.runner_resolve_library)'), function () {
  this.parsedRow = callLibrary(this, PARSE_CSV_ROW_SCRIPT, [this.csvLine], { PATH: process.env.PATH });
});

When(literal('引数連結関数 `build_argument_list` に \'["p1","p2 p3","a,b"]\' と x y を渡して呼ぶ'), function () {
  this.argumentList = callLibrary(this, BUILD_ARGUMENT_LIST_SCRIPT, [this.fixedParams, ...this.params], { PATH: process.env.PATH });
});

// ---- Then: 解決結果と引数列 ----

for (const text of [
  '解決結果は host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work hang_detect_limit_minutes=60 credential_ref=ssh-key-green map_version=map-v3 である',
  '解決結果は host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work である',
]) {
  Then(literal(text), function () {
    assertTarget(this, this.resolved, text);
    assert.equal(this.resolved.exec, 'ssh');
  });
}

Then(literal('引数列は --mode / full / 20260830 の 3 個である'), function () {
  assert.deepEqual(this.resolved.args, ['--mode', 'full', '20260830']);
});

Then(literal('解決結果は host=null user=null(ローカル実行)credential_ref=null map_version=null である'), function () {
  assertTarget(this, this.resolved, 'host=null user=null credential_ref=null map_version=null');
  assert.equal(this.resolved.exec, 'local');
});

Then(
  literal('解決結果は host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work である(host-default-99 ではない)'),
  function () {
    assertTarget(this, this.resolved, 'host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work');
    assert.notEqual(this.resolved.host, 'host-default-99');
  },
);

Then(literal('role=blue の解決結果は host=null user=null(ローカル実行)script=/opt/app/bin/job001.sh work_dir=/var/app/work である'), function () {
  const resolved = this.resolvedByRole.blue;
  assertTarget(this, resolved, 'host=null user=null script=/opt/app/bin/job001.sh work_dir=/var/app/work');
  assert.equal(resolved.exec, 'local');
});

Then(
  literal('role=green の解決結果は host=host-green-01 user=batch(SSH 実行)script=/opt/app/bin/job001.sh work_dir=/var/app/work である'),
  function () {
    const resolved = this.resolvedByRole.green;
    assertTarget(this, resolved, 'host=host-green-01 user=batch script=/opt/app/bin/job001.sh work_dir=/var/app/work');
    assert.equal(resolved.exec, 'ssh');
  },
);

Then(literal('戻り値は 0 で、配列 CSV_CELLS のセルは 7 個で、fixed_params セルは ["p1","p2 p3","a,b"] であり host と user のセルは空である'), function () {
  // 列の並びは元資料の job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes
  assert.equal(this.parsedRow.status, '0');
  assert.equal(this.parsedRow.cells.length, 7, JSON.stringify(this.parsedRow.cells));
  assert.equal(this.parsedRow.cells[5], '["p1","p2 p3","a,b"]');
  assert.equal(this.parsedRow.cells[1], '');
  assert.equal(this.parsedRow.cells[2], '');
});

Then(literal('配列 ARGUMENT_LIST は p1 / "p2 p3" / "a,b" / x / y の 5 個である'), function () {
  assert.equal(this.argumentList.status, '0');
  assert.deepEqual(this.argumentList.args, ['p1', 'p2 p3', 'a,b', 'x', 'y']);
});

// ---- Then: 実行ログ ----

for (const message of [
  'job map resolved job_id=JOB001 slot=blue host=- map_version=-',
  'job map resolved job_id=JOB001 slot=green host=host-green-01 map_version=-',
]) {
  Then(literal(`実行ログに "${message}" が出る`), function () {
    assertResolvedLogged(this, message);
  });
}

Then(
  literal(
    '実行ログに "job map resolved job_id=JOB001 slot=blue host=- map_version=-" と "job map resolved job_id=JOB001 slot=green host=host-green-01 map_version=-" が出る',
  ),
  function () {
    assertResolvedLogged(this, 'job map resolved job_id=JOB001 slot=blue host=- map_version=-');
    assertResolvedLogged(this, 'job map resolved job_id=JOB001 slot=green host=host-green-01 map_version=-');
  },
);

Then(
  literal('解決は成功し、実行ログに "WARN unknown column column=impl_version path: <RELAY_GATE_CONFIG_DIR>/green-job-map.csv" が出る'),
  function () {
    assertResolved(this, this.resolved);
    assertLogLine(this, 'WARN', expandPlaceholders(this, 'unknown column column=impl_version path: <RELAY_GATE_CONFIG_DIR>/green-job-map.csv'));
    assertResolvedLogged(this, 'job map resolved job_id=JOB001 slot=green host=host-green-01 map_version=-');
  },
);

Then(literal('終了コード 2 で終了し、実行ログに "ERROR option required option=--job-id" が出る'), function () {
  assertExit(this, 2);
  assertLogLine(this, 'ERROR', 'option required option=--job-id');
});

// ---- Then: 終了コードと成果物 ----

Then(literal('終了コード 2 で終了する'), function () {
  assertExit(this, 2);
});

Then(
  literal('終了コード 2 で終了し、stderr.log は "error: job map header mismatch missing=user path: <RELAY_GATE_CONFIG_DIR>/green-job-map.csv" を含む'),
  function () {
    assertExit(this, 2);
    assertStderrLogIncludes(this, expandPlaceholders(this, 'error: job map header mismatch missing=user path: <RELAY_GATE_CONFIG_DIR>/green-job-map.csv'));
  },
);

Then(
  literal('RELAY_GATE_ARTIFACT_ROOT/facade/20260830T113000-JOB999-a1b2c3d4/green/ に started-at.txt stdout.log stderr.log exitcode.txt が揃う'),
  function () {
    const dir = path.join(artifactRoot(this), 'facade', '20260830T113000-JOB999-a1b2c3d4', 'green');
    for (const name of RESULT_FILES) {
      assert.ok(fs.statSync(path.join(dir, name)).isFile(), `${name} should exist`);
    }
    // 実装は実行していないため stdout.log は空。started-at.txt は UTC ISO 8601 秒精度 Z 付きの 1 行
    assert.equal(fs.readFileSync(path.join(dir, 'stdout.log'), 'utf8'), '');
    assert.match(fs.readFileSync(path.join(dir, 'started-at.txt'), 'utf8'), /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\n$/);
  },
);

Then(
  literal(
    'exitcode.txt は "2" の 1 行、stderr.log は "error: job_id=JOB999 not found in job map slot=green map=<RELAY_GATE_CONFIG_DIR>/green-job-map.csv" を含む',
  ),
  function () {
    assertExitcodeFile(this, 2);
    assertStderrLogIncludes(
      this,
      expandPlaceholders(this, 'error: job_id=JOB999 not found in job map slot=green map=<RELAY_GATE_CONFIG_DIR>/green-job-map.csv'),
    );
  },
);

Then(literal('同ディレクトリに .tmp サフィックスのファイルは残っていない'), function () {
  const leftovers = fs.readdirSync(roleDir(this, this.lastInvocation)).filter((name) => name.endsWith('.tmp'));
  assert.deepEqual(leftovers, []);
});

Then(literal('終了コード 2 で終了し、exitcode.txt は "2" の 1 行である'), function () {
  assertExit(this, 2);
  assertExitcodeFile(this, 2);
});

for (const line of [
  'error: job_id=JOB999 not found in job map slot=green map=<maps>/green-jobs.csv',
  'error: job map not found slot=green map=<maps>/green-jobs.csv',
]) {
  Then(literal(`stderr.log は "${line}" を含む`), function () {
    assertStderrLogIncludes(this, expandPlaceholders(this, line));
  });
}

// ---- 自作の runner(2026-11-24 S2 scoped 再実行で足した Scenario。spec-decision-042 / 043) ----
// 自作の runner と同じく、別の bash プロセスで lib/runner-resolve.sh を source し、契約 runner IF の
// standard_runner.runner_resolve_library の呼び方で関数を呼ぶ。step 文言のバッククォートの中の呼び出しを、そのまま bash の 1 行として実行する。
// 結果はプロセスの stdout ではなく結果ファイルへ書く(Then が「プロセスの stdout と stderr には何も出ていない」を確かめるため)。

const CUSTOM_RUNNER_SCRIPT_NAME = 'my-runner.sh';

// 自作の runner の断片。$1 = ライブラリ、$2 = 結果ファイル。source の前後の set のオプションと EXIT の trap を比べる
function customRunnerScript(callLine) {
  return [
    'set -u',
    "trap ': custom runner exit' EXIT",
    'result_file="$2"',
    'before_options="$(set +o)"',
    'before_flags="$-"',
    'before_trap="$(trap -p EXIT)"',
    'source "$1"',
    'after_options="$(set +o)"',
    'after_flags="$-"',
    'after_trap="$(trap -p EXIT)"',
    'status=0',
    `${callLine} || status=$?`,
    '{',
    "  printf 'status=%s\\n' \"$status\"",
    "  printf 'exit_code=%s\\n' \"${RUNNER_RESOLVE_EXIT_CODE-}\"",
    "  printf 'not_resolved=%s\\n' \"${RUNNER_RESOLVE_STATUS_NOT_RESOLVED-}\"",
    "  printf 'map_path=%s\\n' \"${RUNNER_RESOLVE_MAP_PATH-}\"",
    "  printf 'exec=%s\\n' \"${EXECUTION_TARGET_EXEC-}\"",
    "  printf 'host=%s\\n' \"${EXECUTION_TARGET_HOST-}\"",
    "  printf 'user=%s\\n' \"${EXECUTION_TARGET_USER-}\"",
    "  printf 'credential_ref=%s\\n' \"${EXECUTION_TARGET_CREDENTIAL_REF-}\"",
    "  printf 'map_version=%s\\n' \"${EXECUTION_TARGET_MAP_VERSION-}\"",
    "  printf 'script=%s\\n' \"${EXECUTION_TARGET_SCRIPT-}\"",
    '  for value in ${ARGUMENT_LIST[@]+"${ARGUMENT_LIST[@]}"}; do printf \'arg=%s\\n\' "$value"; done',
    '  [ "$before_options" = "$after_options" ] && [ "$before_flags" = "$after_flags" ] && printf \'options_kept=1\\n\'',
    '  [ "$before_trap" = "$after_trap" ] && [ -n "$after_trap" ] && printf \'trap_kept=1\\n\'',
    '} >"$result_file"',
    'trap - EXIT',
  ].join('\n');
}

// 呼び出しの 1 行から run_id と role を読む(成果物ディレクトリを決めるため。引数の並びは契約の usage)
function customCallTarget(callLine) {
  const tokens = callLine.split(' ');
  switch (tokens[0]) {
    case 'resolve_execution_target':
      return { runId: tokens[2], role: tokens[4] };
    case 'runner_resolve_guard_existing_result':
      return { runId: tokens[1], role: tokens[2] };
    case 'runner_resolve_reject_invocation':
      return { runId: null, role: tokens[3] };
    default:
      throw new Error(`unknown library function: ${tokens[0]}`);
  }
}

function runCustomRunner(world, text) {
  const callLine = text.match(/`([^`]+)`/)[1];
  const target = customCallTarget(callLine);
  const scriptFile = path.join(world.workDir, 'my-runner.sh');
  const resultFile = path.join(world.workDir, 'my-runner.result');
  fs.writeFileSync(scriptFile, `${customRunnerScript(callLine)}\n`);
  const proc = spawnSync('bash', [scriptFile, RESOLVE_LIBRARY, resultFile], {
    cwd: world.workDir,
    encoding: 'utf8',
    env: runnerEnv(world, target.role, {}),
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  assert.equal(proc.status, 0, `the custom runner should finish\n--- stdout ---\n${proc.stdout}\n--- stderr ---\n${proc.stderr}`);
  const values = {};
  const args = [];
  for (const line of fs.readFileSync(resultFile, 'utf8').split('\n').slice(0, -1)) {
    const separator = line.indexOf('=');
    const name = line.slice(0, separator);
    const value = line.slice(separator + 1);
    if (name === 'arg') {
      args.push(value);
    } else {
      values[name] = value;
    }
  }
  world.custom = { ...values, args, stdout: proc.stdout, stderr: proc.stderr };
  if (target.runId) {
    world.lastInvocation = { runId: target.runId, role: target.role };
  }
}

// 公開済みの Runner Result(exitcode.txt が "0" の 1 行)を置き、置いた後のファイルの一覧と中身を控える
function publishExitcode(world, runId, role) {
  const invocation = { runId, role };
  const dir = roleDir(world, invocation);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'exitcode.txt'), '0\n');
  world.lastInvocation = invocation;
  world.publishedSnapshot = snapshotDir(dir);
}

function snapshotDir(dir) {
  return fs
    .readdirSync(dir)
    .sort()
    .map((name) => [name, fs.readFileSync(path.join(dir, name), 'utf8')]);
}

function listFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { recursive: true }).filter((name) => fs.statSync(path.join(dir, name)).isFile());
}

function assertCustomStatus(world, predicate, exitCode) {
  assert.ok(predicate(world.custom.status), `return status: ${JSON.stringify(world.custom)}`);
  assert.equal(world.custom.exit_code, exitCode, `RUNNER_RESOLVE_EXIT_CODE: ${JSON.stringify(world.custom)}`);
}

// 自作の runner の実行ログ(行形式 `{script} {run_id} {ローカル日時} {LEVEL} {message}`)
function assertCustomLogLine(world, runId, level, message) {
  const file = path.join(logDir(world), `${CUSTOM_RUNNER_SCRIPT_NAME}.log`);
  const content = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
  const pattern = /^(\S+) (\S+) (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}) (\S+) (.*)$/;
  const hit = content
    .split('\n')
    .map((line) => line.match(pattern))
    .some((match) => match && match[1] === CUSTOM_RUNNER_SCRIPT_NAME && match[2] === runId && match[4] === level && match[5] === message);
  assert.ok(hit, `execution log should include "${level} ${message}"\n--- execution log ---\n${content}`);
}

// Scenario: 自作の runner は共通ライブラリの解決の入口を呼んで標準の slot runner と同じ結果を受け取る
Given(
  literal(
    'RELAY_GATE_CONFIG_DIR / RELAY_GATE_ARTIFACT_ROOT / RELAY_GATE_LOG_DIR を設定し、RELAY_GATE_CONFIG_DIR/blue-job-map.csv のヘッダーが "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" で行 \'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[""--mode"",""full""]",0\' がある',
  ),
  function () {
    // 3 つの環境変数は runnerEnv が自作の runner のプロセスへ渡す
    writeMap(this, defaultMap(this, 'blue'), 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes', [
      'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[""--mode"",""full""]",0',
    ]);
  },
);

// EXIT の trap の設定と source は、When の自作の runner の断片が行う(customRunnerScript)
Given(literal('自作の runner が EXIT の trap を設定してから lib/runner-resolve.sh を source する'), function () {
  assert.ok(fs.statSync(RESOLVE_LIBRARY).isFile());
});

for (const text of [
  '`resolve_execution_target my-runner.sh 20260830T113000-JOB001-3f9a1c2e JOB001 blue 20260830` を呼ぶ',
  '自作の runner が `runner_resolve_reject_invocation my-runner.sh "" green "option required option=--run-id"` を呼ぶ',
  '自作の runner が `resolve_execution_target my-runner.sh 20260830T113000-JOB999-a1b2c3d4 JOB999 green` を呼ぶ',
  '自作の runner が `runner_resolve_guard_existing_result 20260830T113000-JOB001-3f9a1c2e green` を呼ぶ',
]) {
  When(literal(text), function () {
    runCustomRunner(this, text);
  });
}

Then(
  literal(
    '戻り値は 0 で、EXECUTION_TARGET_EXEC は local、EXECUTION_TARGET_HOST と EXECUTION_TARGET_USER と EXECUTION_TARGET_CREDENTIAL_REF と EXECUTION_TARGET_MAP_VERSION は空文字、EXECUTION_TARGET_SCRIPT は /opt/app/bin/job001.sh である',
  ),
  function () {
    const custom = this.custom;
    assert.equal(custom.status, '0', JSON.stringify(custom));
    assert.equal(custom.exec, 'local');
    for (const name of ['host', 'user', 'credential_ref', 'map_version']) {
      assert.equal(custom[name], '', `${name}: ${JSON.stringify(custom)}`);
    }
    assert.equal(custom.script, '/opt/app/bin/job001.sh');
  },
);

Then(literal('配列 ARGUMENT_LIST は --mode / full / 20260830 の 3 個で、RUNNER_RESOLVE_MAP_PATH は <RELAY_GATE_CONFIG_DIR>/blue-job-map.csv である'), function () {
  assert.deepEqual(this.custom.args, ['--mode', 'full', '20260830']);
  assert.equal(this.custom.map_path, expandPlaceholders(this, '<RELAY_GATE_CONFIG_DIR>/blue-job-map.csv'));
});

Then(literal('source の前後で set のオプションと EXIT の trap は変わらず、source と関数の呼び出しでプロセスの stdout と stderr には何も出ていない'), function () {
  assert.equal(this.custom.options_kept, '1', 'set options should not change by source');
  assert.equal(this.custom.trap_kept, '1', 'the EXIT trap should not change by source');
  assert.equal(this.custom.stdout, '');
  assert.equal(this.custom.stderr, '');
});

// Scenario: 引数の違反の報告は run_id が分からないとき成果物を書かず RUNNER_RESOLVE_EXIT_CODE を 2 にする
Then(literal('戻り値は 0 以外で、RUNNER_RESOLVE_EXIT_CODE は 2 である'), function () {
  assertCustomStatus(this, (status) => status !== '0', '2');
});

Then(literal('実行ログに "ERROR option required option=--run-id" が出て、RELAY_GATE_ARTIFACT_ROOT/facade/ 配下にファイルは作られない'), function () {
  // run_id が分からないときの {run_id} 列は `-`(ui-design.md の実行ログの行形式)
  assertCustomLogLine(this, '-', 'ERROR', 'option required option=--run-id');
  assert.deepEqual(listFiles(path.join(artifactRoot(this), 'facade')), []);
});

// Scenario: 自作の runner は解決できなかったとき RUNNER_RESOLVE_EXIT_CODE の値で終える
Then(literal('戻り値は 2 で、RUNNER_RESOLVE_EXIT_CODE は 2 である'), function () {
  assertCustomStatus(this, (status) => status === '2', '2');
});

Then(
  literal('RELAY_GATE_ARTIFACT_ROOT/facade/20260830T113000-JOB999-a1b2c3d4/green/exitcode.txt は "2" の 1 行である(関数が Runner Result を揃え済み)'),
  function () {
    const dir = path.join(artifactRoot(this), 'facade', '20260830T113000-JOB999-a1b2c3d4', 'green');
    assert.equal(fs.readFileSync(path.join(dir, 'exitcode.txt'), 'utf8'), '2\n');
    for (const name of RESULT_FILES) {
      assert.ok(fs.statSync(path.join(dir, name)).isFile(), `${name} should exist`);
    }
  },
);

// Scenario: 解決の入口は既存の exitcode.txt が 0 の二重起動のとき RUNNER_RESOLVE_STATUS_NOT_RESOLVED を返す
Given(
  literal(
    'RELAY_GATE_ARTIFACT_ROOT/facade/20260830T113000-JOB999-a1b2c3d4/green/exitcode.txt が "0" の 1 行で公開済みで、RELAY_GATE_CONFIG_DIR/green-job-map.csv に JOB999 の行が無い',
  ),
  function () {
    publishExitcode(this, '20260830T113000-JOB999-a1b2c3d4', 'green');
    writeMap(this, defaultMap(this, 'green'), HEADER_7, [ROW_JOB001]);
  },
);

Then(literal('戻り値は RUNNER_RESOLVE_STATUS_NOT_RESOLVED(1)で、RUNNER_RESOLVE_EXIT_CODE は 0 である'), function () {
  assert.equal(this.custom.not_resolved, '1');
  assertCustomStatus(this, (status) => status === this.custom.not_resolved, '0');
});

Then(literal('exitcode.txt は "0" の 1 行のまま変わらない'), function () {
  assert.equal(readResultFile(this, 'exitcode.txt'), '0\n');
  assert.deepEqual(snapshotDir(roleDir(this, this.lastInvocation)), this.publishedSnapshot);
});

// Scenario: 二重起動の判定は既存の exitcode.txt が 0 のとき 0 以外を返して終了コード 0 を知らせる
Given(literal('RELAY_GATE_ARTIFACT_ROOT/facade/20260830T113000-JOB001-3f9a1c2e/green/exitcode.txt が "0" の 1 行で公開済みである'), function () {
  publishExitcode(this, '20260830T113000-JOB001-3f9a1c2e', 'green');
});

Then(literal('戻り値は 0 以外で、RUNNER_RESOLVE_EXIT_CODE は 0 である'), function () {
  assertCustomStatus(this, (status) => status !== '0', '0');
});

Then(literal('成果物ディレクトリのファイルは変わらない'), function () {
  assert.deepEqual(snapshotDir(roleDir(this, this.lastInvocation)), this.publishedSnapshot);
});

// Scenario: runner は使ったパスにあるがディレクトリのジョブマップを config file is not readable で報告する
Given(literal('RELAY_GATE_CONFIG_DIR とは別のディレクトリ maps に green-jobs.csv という名前のディレクトリがある'), function () {
  assert.notEqual(mapsDir(this), this.configDir);
  fs.mkdirSync(path.join(mapsDir(this), 'green-jobs.csv'));
});

Then(
  literal(
    'stderr.log は "error: config file is not readable path: <maps>/green-jobs.csv" を含み、"job map not found" を含まない(契約 job_map_location.presence_report)',
  ),
  function () {
    assertStderrLogIncludes(this, expandPlaceholders(this, 'error: config file is not readable path: <maps>/green-jobs.csv'));
    assert.ok(!readResultFile(this, 'stderr.log').includes('job map not found'), 'stderr.log should not include "job map not found"');
  },
);
