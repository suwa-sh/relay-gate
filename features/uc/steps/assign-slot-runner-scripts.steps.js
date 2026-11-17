// UC BDD(②)step definition。uc_id=65b09d93 / branch_slug=assign-slot-runner-scripts(S6 uc-bdd で実装)。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/slot runner の実体スクリプトを割り当てる/spec.md#E2E完了条件(BDD)
// このファイルが定義するのは、他 UC の step ファイルに定義の無い step だけ(同じ文言を再定義すると ambiguous になる)。
// 既存 step(configure-feature-flags.steps.js の「基盤適用設計者が validate-config.sh --feature-flag … を実行する」
// 「validate-config.sh --feature-flag を実行する」「基盤適用設計者が作業ディレクトリ /tmp で …」
// 「基盤適用設計者が RELAY_GATE_CONFIG_DIR=/etc/relay-gate で …」)を再利用する。
// 再利用する When は、同ファイルの Before が作る World(root / configDir / envPath / env / sandbox() / unsandbox())と
// flushEnv(this.env を KEY=value の行で this.envPath へ書く)を前提にする。同ファイルを require すると step が
// 二重登録されるため、使う補助関数はここに写している。
// このファイルには Before / After を置かない(同じディレクトリの全 feature の全 Scenario に掛かるため)。
// リポジトリの中にはファイルを書かない。書くのは Before が作る一時ディレクトリ(this.root)の中だけ。
//
// feature-flag.env の Given が仕様の例示として一部のキーだけを挙げ、終了コード 0 を期待する Scenario では、
// 「がある」を「それらの行を含む」と読み、挙げられていない必須キー(BLUE_IMPL / GREEN_IMPL / RAPID_CROSSCHECK_MODE)を
// 有効な値で補う。必須の根拠は CLI 契約 config_files.feature-flag.env の keys / validation_rules
// (docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml)と UC「feature flag を設定する」の
// GREEN_IMPL 欠落の Scenario(既存の規則の適用であり、新しい前提ではない)。
'use strict';
const { Given, Then, When } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const REPO_ROOT = path.resolve(__dirname, '../../..');
const FACADE_HOME = path.join(REPO_ROOT, 'facade');
const FACADE_SH = path.join(FACADE_HOME, 'bin', 'facade.sh');
const VALIDATE_CONFIG = path.join(FACADE_HOME, 'bin', 'validate-config.sh');
// 配置ディレクトリの複製に写すディレクトリ(入口の runners/ と lib/、入口が読む本体の src/)
const DEPLOY_DIRS = ['runners', 'lib', 'src'];
const LIB_FILES = ['runner-resolve.sh', 'runner-spec.sh', 'runner-result.sh', 'runner-notify.sh'];

// feature に書かれた絶対パス(仕様の例示値)。World.sandbox() で一時ディレクトリ配下へ写像する
const SPEC_HOME = '/opt/relay-gate';
const SPEC_STANDARD_RUNNER = '/opt/relay-gate/runners/standard-runner.sh';
const SPEC_BLUE_RUNNER = '/opt/relay-gate/runners/blue-runner.sh';
const SPEC_GREEN_RUNNER = '/opt/relay-gate/runners/green-runner.sh';
const SPEC_GREEN_NEXT_RUNNER = '/opt/relay-gate/runners/green-next-runner.sh';
const SPEC_MISSING_RUNNER = '/opt/relay-gate/runners/missing.sh';
const SPEC_CONF_BLUE_RUNNER = '/etc/relay-gate/blue-runner.sh';
const SPEC_CONF_GREEN_RUNNER = '/etc/relay-gate/green-runner.sh';

const JOB_MAP_HEADER = 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes';
const JOB001_ROW = 'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",60';

// --help で runner-if-version=1 を返す runner スタブ
const RUNNER_STUB =
  '#!/usr/bin/env bash\n' +
  'if [ "${1:-}" = "--help" ]; then echo "usage: runner-stub.sh"; echo "runner-if-version=1"; exit 0; fi\n' +
  'exit 6\n';

// --help に runner-if-version= を含まない出力を返す実行可能ファイル(終了コードは 0)
const NO_VERSION_RUNNER_STUB = '#!/usr/bin/env bash\necho "usage: green-runner.sh"\nexit 0\n';

// --help を受けると応答せず 30 秒終了しないスタブ。exec で sleep に置き換わるため、記録した PID は sleep のプロセス
const SLEEPING_RUNNER_STUB =
  '#!/usr/bin/env bash\n' +
  'if [ "${1:-}" = "--help" ]; then printf \'%s\\n\' "$$" >>"$0.pids"; exec sleep 30; fi\n' +
  'exit 6\n';

// 起動引数と環境変数を記録し、Runner Result 3 ファイルを書く自作 runner(facade.sh を起動する Scenario 用)
const RECORDING_RESULT_RUNNER_STUB =
  '#!/usr/bin/env bash\n' +
  'if [ "${1:-}" = "--help" ]; then echo "usage: custom-runner.sh"; echo "runner-if-version=1"; exit 0; fi\n' +
  'printf \'%s\\n\' "$*" >"$0.args"\n' +
  'env >"$0.env"\n' +
  'run_id=""; role=""\n' +
  'while [ "$#" -gt 0 ]; do case "$1" in --run-id) run_id="$2"; shift 2 ;; --role) role="$2"; shift 2 ;; --) break ;; *) shift ;; esac; done\n' +
  'dir="$RELAY_GATE_ARTIFACT_ROOT/facade/$run_id/$role"\n' +
  'mkdir -p "$dir" && : >"$dir/stdout.log" && : >"$dir/stderr.log" && echo 0 >"$dir/exitcode.txt"\n' +
  'exit 0\n';

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

function writeExecutable(file, body) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, body, { mode: 0o755 });
  return file;
}

function writeJobMap(world, slot, rows = []) {
  fs.writeFileSync(path.join(world.configDir, `${slot}-job-map.csv`), [JOB_MAP_HEADER, ...rows].join('\n') + '\n');
}

function assertHelpVersion(file) {
  const help = spawnSync(file, ['--help'], { encoding: 'utf8' });
  assert.equal(help.status, 0, `${file} --help exit code`);
  assert.ok(help.stdout.split('\n').includes('runner-if-version=1'), `${file} --help should print runner-if-version=1`);
}

// relay-gate を sandbox の /opt/relay-gate に配置する(リンクではなく複製。リポジトリの facade/ には書かない)
function deployRelayGate(world) {
  const home = world.sandbox(SPEC_HOME);
  for (const dir of DEPLOY_DIRS) {
    fs.cpSync(path.join(FACADE_HOME, dir), path.join(home, dir), { recursive: true });
  }
  fs.accessSync(world.sandbox(SPEC_STANDARD_RUNNER), fs.constants.X_OK);
  return home;
}

// 終了コード 0 を期待する Scenario で補う必須キー(冒頭のコメントを参照)
function requiredKeysFor(blueMode, greenMode) {
  const keys = { RAPID_CROSSCHECK_MODE: 'off' };
  if (blueMode !== 'off') {
    keys.BLUE_IMPL = 'blue-2.3.1';
  }
  if (greenMode !== 'off') {
    keys.GREEN_IMPL = 'green-1.4.0';
  }
  return keys;
}

function dump(world) {
  return `--- stdout ---\n${world.unsandbox(world.result.stdout)}\n--- stderr ---\n${world.unsandbox(world.result.stderr)}`;
}

function assertExit(world, code) {
  assert.equal(world.result.status, code, `exit code\n${dump(world)}`);
}

function stdoutLines(world) {
  return world.unsandbox(world.result.stdout).split('\n').filter((line) => line.length > 0);
}

function stderrLines(world) {
  return world.unsandbox(world.result.stderr).split('\n').filter((line) => line.length > 0);
}

function assertStdoutIncludes(world, expected) {
  assert.ok(stdoutLines(world).includes(expected), `stdout should include line "${expected}"\n${dump(world)}`);
}

function assertStderrIncludes(world, expected) {
  assert.ok(stderrLines(world).includes(expected), `stderr should include line "${expected}"\n${dump(world)}`);
}

function sha256(file) {
  return require('node:crypto').createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function processAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === 'EPERM';
  }
}

// ---- runner 割当を検証する(SPEC-001-04) ----

Given(literal('/opt/relay-gate/runners/blue-runner.sh と /opt/relay-gate/runners/green-runner.sh が実行可能で、--help に "runner-if-version=1" を返す'), function () {
  for (const specPath of [SPEC_BLUE_RUNNER, SPEC_GREEN_RUNNER]) {
    assertHelpVersion(writeExecutable(this.sandbox(specPath), RUNNER_STUB));
  }
});

Given(literal('/etc/relay-gate/blue-job-map.csv と green-job-map.csv が存在する'), function () {
  writeJobMap(this, 'blue');
  writeJobMap(this, 'green');
});

Given(
  literal('feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_RUNNER=/opt/relay-gate/runners/blue-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh がある'),
  function () {
    this.env = {
      BLUE_MODE: 'foreground',
      GREEN_MODE: 'background',
      BLUE_RUNNER: this.sandbox(SPEC_BLUE_RUNNER),
      GREEN_RUNNER: this.sandbox(SPEC_GREEN_RUNNER),
      ...requiredKeysFor('foreground', 'background'),
    };
  },
);

Then(
  literal(
    '終了コード 0 で stdout に "blue_runner: /opt/relay-gate/runners/blue-runner.sh" "green_runner: /opt/relay-gate/runners/green-runner.sh" "blue_job_map: /etc/relay-gate/blue-job-map.csv" "green_job_map: /etc/relay-gate/green-job-map.csv" が出る',
  ),
  function () {
    assertExit(this, 0);
    assertStdoutIncludes(this, 'blue_runner: /opt/relay-gate/runners/blue-runner.sh');
    assertStdoutIncludes(this, 'green_runner: /opt/relay-gate/runners/green-runner.sh');
    assertStdoutIncludes(this, 'blue_job_map: /etc/relay-gate/blue-job-map.csv');
    assertStdoutIncludes(this, 'green_job_map: /etc/relay-gate/green-job-map.csv');
  },
);

// ---- 標準の slot runner を blue と green の両方に割り当てた設定を検証する(SPEC-001-04) ----

Given(
  literal('relay-gate を /opt/relay-gate に配置してあり、relay-gate が提供する標準の slot runner /opt/relay-gate/runners/standard-runner.sh は実行可能である'),
  function () {
    deployRelayGate(this);
  },
);

Given(
  literal(
    '/etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 BLUE_RUNNER=/opt/relay-gate/runners/standard-runner.sh GREEN_RUNNER=/opt/relay-gate/runners/standard-runner.sh がある',
  ),
  function () {
    this.env = {
      BLUE_MODE: 'foreground',
      GREEN_MODE: 'background',
      RAPID_CROSSCHECK_MODE: 'off',
      BLUE_IMPL: 'blue-2.3.1',
      GREEN_IMPL: 'green-1.4.0',
      BLUE_RUNNER: this.sandbox(SPEC_STANDARD_RUNNER),
      GREEN_RUNNER: this.sandbox(SPEC_STANDARD_RUNNER),
    };
  },
);

Given(
  literal(
    '/etc/relay-gate/blue-job-map.csv と /etc/relay-gate/green-job-map.csv が存在する(基盤適用設計者が用意したのは feature-flag.env と 2 つの slot ジョブマップだけで、runner のスクリプトは書いていない)',
  ),
  function () {
    writeJobMap(this, 'blue');
    writeJobMap(this, 'green');
    // runner のスクリプトは書いていない: 割り当てた runner は配置した relay-gate の標準の slot runner だけ
    assert.equal(this.env.BLUE_RUNNER, this.sandbox(SPEC_STANDARD_RUNNER));
    assert.equal(this.env.GREEN_RUNNER, this.sandbox(SPEC_STANDARD_RUNNER));
    const prepared = fs.readdirSync(this.configDir).filter((name) => name !== path.basename(this.envPath));
    assert.deepEqual(prepared.sort(), ['blue-job-map.csv', 'green-job-map.csv']);
  },
);

Then(literal('終了コード 0 で stderr に "error:" で始まる行も "warn:" で始まる行も出ない'), function () {
  assertExit(this, 0);
  const hits = stderrLines(this).filter((line) => line.startsWith('error:') || line.startsWith('warn:'));
  assert.deepEqual(hits, [], `no error: / warn: line expected\n${dump(this)}`);
});

Then(
  literal(
    'stdout に "blue_runner: /opt/relay-gate/runners/standard-runner.sh" "green_runner: /opt/relay-gate/runners/standard-runner.sh"(同じパス)と "blue_runner_if_version=1" "green_runner_if_version=1" が出る',
  ),
  function () {
    assertStdoutIncludes(this, 'blue_runner: /opt/relay-gate/runners/standard-runner.sh');
    assertStdoutIncludes(this, 'green_runner: /opt/relay-gate/runners/standard-runner.sh');
    assertStdoutIncludes(this, 'blue_runner_if_version=1');
    assertStdoutIncludes(this, 'green_runner_if_version=1');
  },
);

// ---- 設定ファイルと同じディレクトリに置いた runner を相対パスで割り当てる ----

Given(literal('/etc/relay-gate/blue-runner.sh と /etc/relay-gate/green-runner.sh が実行可能で、--help に "runner-if-version=1" を返す'), function () {
  for (const specPath of [SPEC_CONF_BLUE_RUNNER, SPEC_CONF_GREEN_RUNNER]) {
    assertHelpVersion(writeExecutable(this.sandbox(specPath), RUNNER_STUB));
  }
});

Given(
  literal(
    '/etc/relay-gate/feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background BLUE_IMPL=blue-2.3.1 GREEN_IMPL=green-1.4.0 RAPID_CROSSCHECK_MODE=off BLUE_RUNNER=./blue-runner.sh GREEN_RUNNER=./green-runner.sh がある',
  ),
  function () {
    this.env = {
      BLUE_MODE: 'foreground',
      GREEN_MODE: 'background',
      BLUE_IMPL: 'blue-2.3.1',
      GREEN_IMPL: 'green-1.4.0',
      RAPID_CROSSCHECK_MODE: 'off',
      BLUE_RUNNER: './blue-runner.sh',
      GREEN_RUNNER: './green-runner.sh',
    };
  },
);

Then(
  literal(
    '終了コード 0 で stdout に "blue_runner: /etc/relay-gate/./blue-runner.sh" "green_runner: /etc/relay-gate/./green-runner.sh" "blue_runner_if_version=1" "green_runner_if_version=1" が出る',
  ),
  function () {
    assertExit(this, 0);
    assertStdoutIncludes(this, 'blue_runner: /etc/relay-gate/./blue-runner.sh');
    assertStdoutIncludes(this, 'green_runner: /etc/relay-gate/./green-runner.sh');
    assertStdoutIncludes(this, 'blue_runner_if_version=1');
    assertStdoutIncludes(this, 'green_runner_if_version=1');
  },
);

// ---- facade.sh を起動する 2 Scenario ----
// facade.sh は UC「slot 実行モードを選択して runner を起動する」の担当で、この UC の時点では無い
// (docs/impl/latest/65b09d93/issues/20261118_012630_cross-uc-scenarios.md)。facade.sh を起動する step は、
// facade/bin/facade.sh が無い間は skipped を返し、有るのに未実装なら失敗させる(その UC が step を実装する)。
// facade.sh の代わりのスタブは注入しない(facade.sh の振る舞いそのものが判定対象のため)。

Given(literal('並行稼働モードで green runner が新実装 green-1.x 用である'), function () {
  deployRelayGate(this);
  writeJobMap(this, 'blue', [JOB001_ROW]);
  writeJobMap(this, 'green', [JOB001_ROW]);
  this.env = {
    BLUE_MODE: 'foreground',
    GREEN_MODE: 'background',
    RAPID_CROSSCHECK_MODE: 'off',
    BLUE_IMPL: 'blue-2.3.1',
    GREEN_IMPL: 'green-1.4.0',
    BLUE_RUNNER: this.sandbox(SPEC_STANDARD_RUNNER),
    GREEN_RUNNER: this.sandbox(SPEC_STANDARD_RUNNER),
  };
});

Given(
  literal(
    '次世代実装は標準の slot runner が扱わない接続で動くため、次世代実装用の自作の runner /opt/relay-gate/runners/green-next-runner.sh を作成し、runner IF と Runner Result Contract に従う',
  ),
  function () {
    assertHelpVersion(writeExecutable(this.sandbox(SPEC_GREEN_NEXT_RUNNER), RECORDING_RESULT_RUNNER_STUB));
  },
);

When(
  literal('feature-flag.env の GREEN_RUNNER を /opt/relay-gate/runners/green-next-runner.sh に変更し validate-config.sh が終了コード 0 を返した後、ジョブスケジューラが facade.sh JOB001 を実行する'),
  function () {
    // 差し替え前の relay-gate のファイル(この UC の時点で実在する標準の slot runner と共通ライブラリ)の内容を控える
    const home = this.sandbox(SPEC_HOME);
    const watched = [path.join(home, 'runners', 'standard-runner.sh'), ...LIB_FILES.map((name) => path.join(home, 'lib', name))];
    this.hashesBefore = Object.fromEntries(watched.map((file) => [file, sha256(file)]));
    this.env.GREEN_RUNNER = this.sandbox(SPEC_GREEN_NEXT_RUNNER);
    fs.writeFileSync(this.envPath, Object.entries(this.env).map(([key, value]) => `${key}=${value}\n`).join(''));
    const proc = spawnSync(VALIDATE_CONFIG, ['--feature-flag', this.envPath], {
      cwd: this.root,
      encoding: 'utf8',
      env: { ...process.env, RELAY_GATE_CONFIG_DIR: this.configDir },
    });
    assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
    this.result = { status: proc.status, stdout: proc.stdout, stderr: proc.stderr };
    assertExit(this, 0);
    assertStdoutIncludes(this, `green_runner: ${SPEC_GREEN_NEXT_RUNNER}`);
    if (!fs.existsSync(FACADE_SH)) {
      return 'skipped';
    }
    throw new Error(`not implemented: ${FACADE_SH} exists; implement this step in the UC that provides facade.sh`);
  },
);

Then(
  literal(
    'facade.sh・速報クロスチェック runner(RAPID_CROSSCHECK_RUNNER の実体)・速報クロスチェック worker(RAPID_CROSSCHECK_WORKER の実体)・hang-detector.sh・background-rerun.sh・abort-green.sh・標準の slot runner(runners/standard-runner.sh)・共通ライブラリ(lib/runner-*.sh)のファイルは変更されていない',
  ),
  function () {
    throw new Error('not implemented: requires facade.sh');
  },
);

Then(literal('green/ に Runner Result の 3 ファイルが揃う'), function () {
  throw new Error('not implemented: requires facade.sh');
});

Given(
  literal(
    'feature-flag.env に BLUE_MODE=foreground BLUE_IMPL=blue-2.3.1 BLUE_RUNNER=<Runner Result 3 ファイルを書くスタブ runner> GREEN_MODE=background GREEN_IMPL=green-1.4.0 RAPID_CROSSCHECK_MODE=off がある',
  ),
  function () {
    this.blueStub = writeExecutable(this.sandbox(SPEC_BLUE_RUNNER), RECORDING_RESULT_RUNNER_STUB);
    this.env = {
      BLUE_MODE: 'foreground',
      BLUE_IMPL: 'blue-2.3.1',
      BLUE_RUNNER: this.blueStub,
      GREEN_MODE: 'background',
      GREEN_IMPL: 'green-1.4.0',
      RAPID_CROSSCHECK_MODE: 'off',
    };
  },
);

Given(literal('GREEN_RUNNER に起動引数と環境変数を記録するスタブ runner を割り当てた'), function () {
  this.greenStub = writeExecutable(this.sandbox(SPEC_GREEN_RUNNER), RECORDING_RESULT_RUNNER_STUB);
  this.env.GREEN_RUNNER = this.greenStub;
});

Given(literal('両スタブは --help で "runner-if-version=1" を返し、両 slot のジョブマップに JOB001 の行がある'), function () {
  assertHelpVersion(this.blueStub);
  assertHelpVersion(this.greenStub);
  writeJobMap(this, 'blue', [JOB001_ROW]);
  writeJobMap(this, 'green', [JOB001_ROW]);
});

When(literal('ジョブスケジューラが facade.sh JOB001 x y を実行する'), function () {
  if (!fs.existsSync(FACADE_SH)) {
    return 'skipped';
  }
  throw new Error(`not implemented: ${FACADE_SH} exists; implement this step in the UC that provides facade.sh`);
});

Then(literal('スタブは "--run-id <run_id> --job-id JOB001 --role green --mode background -- x y" で起動され、facade は実装固有の引数を追加していない'), function () {
  throw new Error('not implemented: requires facade.sh');
});

Then(literal('スタブの環境変数に GREEN_IMPL=green-1.4.0 があり、RAPID_CROSSCHECK_RUNNER は渡されていない(RAPID_CROSSCHECK_MODE=off)'), function () {
  throw new Error('not implemented: requires facade.sh');
});

// ---- runner 実体が存在しない割当は拒否される ----

Given(literal('feature-flag.env に GREEN_MODE=background GREEN_RUNNER=/opt/relay-gate/runners/missing.sh がある'), function () {
  assert.ok(!fs.existsSync(this.sandbox(SPEC_MISSING_RUNNER)), 'missing.sh should not exist');
  this.env = { GREEN_MODE: 'background', GREEN_RUNNER: this.sandbox(SPEC_MISSING_RUNNER) };
});

Then(literal('終了コード 2 で stderr に "error: file not executable key=GREEN_RUNNER path=/opt/relay-gate/runners/missing.sh" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: file not executable key=GREEN_RUNNER path=/opt/relay-gate/runners/missing.sh');
});

// ---- 対応するジョブマップが無い割当は拒否される ----

Given(literal('feature-flag.env に GREEN_MODE=background GREEN_RUNNER=<実行可能> があり /etc/relay-gate/green-job-map.csv が無い'), function () {
  this.env = { GREEN_MODE: 'background', GREEN_RUNNER: writeExecutable(this.sandbox(SPEC_GREEN_RUNNER), RUNNER_STUB) };
  assert.ok(!fs.existsSync(path.join(this.configDir, 'green-job-map.csv')), 'green-job-map.csv should not exist');
});

Then(literal('終了コード 2 で stderr に "error: job map not found slot=green map=/etc/relay-gate/green-job-map.csv" が出る'), function () {
  assertExit(this, 2);
  assertStderrIncludes(this, 'error: job map not found slot=green map=/etc/relay-gate/green-job-map.csv');
});

// ---- runner IF に応答しない実体は警告される ----

Given(literal('GREEN_RUNNER が --help に "runner-if-version=" を含まない実行可能ファイルである'), function () {
  // 終了コード 0 を期待するため、green だけを使う有効な設定(単独本番の組合せ)に必須キーを補う
  const runner = writeExecutable(this.sandbox(SPEC_GREEN_RUNNER), NO_VERSION_RUNNER_STUB);
  const help = spawnSync(runner, ['--help'], { encoding: 'utf8' });
  assert.ok(!help.stdout.includes('runner-if-version='), 'stub should not print runner-if-version=');
  this.env = { BLUE_MODE: 'off', GREEN_MODE: 'foreground', GREEN_RUNNER: runner, ...requiredKeysFor('off', 'foreground') };
  writeJobMap(this, 'green');
});

Then(literal('終了コード 0 で stderr に "warn: runner does not respond to --help slot=green runner=<path>" が出る'), function () {
  assertExit(this, 0);
  assertStderrIncludes(this, `warn: runner does not respond to --help slot=green runner=${SPEC_GREEN_RUNNER}`);
});

Then(literal('stdout の green_runner_if_version は "-" である'), function () {
  assertStdoutIncludes(this, 'green_runner_if_version=-');
});

// ---- --help に応答しない runner の問い合わせは待機上限で打ち切られ 10 秒以内に復帰する ----
// 待機の上限という振る舞いの確認(性能の検査ではない)。経過時間は最後の Given の終わりから最初の Then の始まりまで
// (= When の validate-config.sh の実行だけ)を測る。

Given(literal('BLUE_RUNNER と GREEN_RUNNER が --help を受けると応答せずに 30 秒間終了しない実行可能ファイルである'), function () {
  this.sleepingRunners = [
    writeExecutable(this.sandbox(SPEC_BLUE_RUNNER), SLEEPING_RUNNER_STUB),
    writeExecutable(this.sandbox(SPEC_GREEN_RUNNER), SLEEPING_RUNNER_STUB),
  ];
});

Given(literal('feature-flag.env は BLUE_MODE=foreground GREEN_MODE=background の並行稼働の組合せで、runner 以外の検証はすべて通過する'), function () {
  this.env = {
    BLUE_MODE: 'foreground',
    GREEN_MODE: 'background',
    BLUE_RUNNER: this.sandbox(SPEC_BLUE_RUNNER),
    GREEN_RUNNER: this.sandbox(SPEC_GREEN_RUNNER),
    ...requiredKeysFor('foreground', 'background'),
  };
  writeJobMap(this, 'blue');
  writeJobMap(this, 'green');
  this.whenStartedAt = process.hrtime.bigint();
});

Then(
  literal(
    '終了コード 0 で、起動から終了までの経過時間は 10 秒以内である(契約 runner_help_probe.response_time_budget の問い合わせの上限 9.2 秒に、数行の設定の検査の時間を加えた、この入力での確認)',
  ),
  function () {
    const elapsedMs = Number(process.hrtime.bigint() - this.whenStartedAt) / 1e6;
    // 「終了時点で」残っている runner のプロセスを判定より先に控え、残っていれば片付ける(後続の判定が失敗しても残さない)
    const pids = this.sleepingRunners.flatMap((runner) =>
      fs.existsSync(`${runner}.pids`)
        ? fs
            .readFileSync(`${runner}.pids`, 'utf8')
            .split('\n')
            .filter((line) => line.length > 0)
            .map(Number)
        : [],
    );
    this.startedRunnerPids = pids;
    this.survivingRunnerPids = pids.filter((pid) => processAlive(pid));
    for (const pid of this.survivingRunnerPids) {
      try {
        process.kill(pid, 'SIGKILL');
      } catch {
        // 既に終了している
      }
    }
    assertExit(this, 0);
    assert.ok(elapsedMs <= 10000, `elapsed ${elapsedMs} ms should be within 10 seconds`);
  },
);

Then(
  literal('stderr に "warn: runner does not respond to --help slot=blue runner=<path>" と "warn: runner does not respond to --help slot=green runner=<path>" の両方が出る'),
  function () {
    assertStderrIncludes(this, `warn: runner does not respond to --help slot=blue runner=${SPEC_BLUE_RUNNER}`);
    assertStderrIncludes(this, `warn: runner does not respond to --help slot=green runner=${SPEC_GREEN_RUNNER}`);
  },
);

Then(literal('stdout の blue_runner_if_version と green_runner_if_version は "-" で、終了時点で runner のプロセスは残っていない'), function () {
  assertStdoutIncludes(this, 'blue_runner_if_version=-');
  assertStdoutIncludes(this, 'green_runner_if_version=-');
  assert.equal(this.startedRunnerPids.length, 2, `each stub should be started once: ${this.startedRunnerPids}`);
  assert.deepEqual(this.survivingRunnerPids, [], 'stub runner processes should not remain');
});
