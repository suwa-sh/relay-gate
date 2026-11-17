// ATDD(①)step definition。uc_id=65b09d93 / branch_slug=assign-slot-runner-scripts(S7 atdd で実装)。
// 対象は uc-map の atdd_scenarios(@atdd_SPEC-001-04-3 / @atdd_SPEC-001-04-8)だけ。features/atdd/SPEC-001-04.feature の本文は変更しない。
// このファイルが定義するのは、他 UC の step ファイルに定義の無い step だけ。
// When「設定を検証する」は configure-feature-flags.steps.js の既存 step を再利用する(再定義すると ambiguous になる)。
// 再利用する When は env を書き出さないため、Given が feature-flag.env(World の envPath)を書く。
// World(root / configDir / envPath / sandbox() / unsandbox())と Before / After は configure-feature-flags.steps.js のものを使う。
// このファイルには Before / After を置かない(同じディレクトリの全 feature の全 Scenario に掛かるため)。
// リポジトリの中にはファイルを書かない。書くのは Before が作る一時ディレクトリ(this.root)の中だけ。
'use strict';
const { Given, Then, When } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const YAML = require('yaml');

const REPO_ROOT = path.resolve(__dirname, '../../..');
const FACADE_HOME = path.join(REPO_ROOT, 'facade');
const CLI_CONTRACT = path.join(REPO_ROOT, 'docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml');
// 配置ディレクトリの複製に写すディレクトリ(入口の runners/ と lib/、入口が読む本体の src/)
const DEPLOY_DIRS = ['runners', 'lib', 'src'];
// 仕様の例示値(CLI 契約 standard_runner.feature_flag_example の配置ディレクトリ)
const SPEC_HOME = '/opt/relay-gate';
const SPEC_STANDARD_RUNNER = '/opt/relay-gate/runners/standard-runner.sh';
const RUNNER_COMMAND_NAME = '$BLUE_RUNNER / $GREEN_RUNNER';

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

function dump(world) {
  return `--- stdout ---\n${world.unsandbox(world.result.stdout)}\n--- stderr ---\n${world.unsandbox(world.result.stderr)}`;
}

// ---- @atdd_SPEC-001-04-3 ----

Given(
  literal('BLUE_RUNNER と GREEN_RUNNER に relay-gate が提供する標準の slot runner を割り当て、blue と green の slot ジョブマップを置いた feature flag 設定'),
  function () {
    // relay-gate を一時ディレクトリの /opt/relay-gate に配置する(リンクではなく複製。リポジトリの facade/ には書かない)
    const home = this.sandbox(SPEC_HOME);
    for (const dir of DEPLOY_DIRS) {
      fs.cpSync(path.join(FACADE_HOME, dir), path.join(home, dir), { recursive: true });
    }
    const standardRunner = this.sandbox(SPEC_STANDARD_RUNNER);
    fs.accessSync(standardRunner, fs.constants.X_OK);
    for (const slot of ['blue', 'green']) {
      fs.writeFileSync(path.join(this.configDir, `${slot}-job-map.csv`), 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\n');
    }
    // 割当以外のキーは並行稼働の有効な値(必須キーの根拠は CLI 契約 config_files.feature-flag.env の keys / validation_rules)
    this.env = {
      BLUE_MODE: 'foreground',
      GREEN_MODE: 'background',
      RAPID_CROSSCHECK_MODE: 'off',
      BLUE_IMPL: 'blue-2.3.1',
      GREEN_IMPL: 'green-1.4.0',
      BLUE_RUNNER: standardRunner,
      GREEN_RUNNER: standardRunner,
    };
    fs.writeFileSync(this.envPath, Object.entries(this.env).map(([key, value]) => `${key}=${value}\n`).join(''));
  },
);

Then(literal('エラーにならず終了コード 0 で終わる'), function () {
  assert.equal(this.result.status, 0, `exit code\n${dump(this)}`);
  const errors = this.unsandbox(this.result.stderr)
    .split('\n')
    .filter((line) => line.startsWith('error:'));
  assert.deepEqual(errors, [], `no error: line expected\n${dump(this)}`);
  // 割り当てた runner が標準の slot runner として受理され、runner IF の問い合わせにも応答したこと
  const stdout = this.unsandbox(this.result.stdout).split('\n');
  for (const line of [
    `blue_runner: ${SPEC_STANDARD_RUNNER}`,
    `green_runner: ${SPEC_STANDARD_RUNNER}`,
    'blue_runner_if_version=1',
    'green_runner_if_version=1',
  ]) {
    assert.ok(stdout.includes(line), `stdout should include line "${line}"\n${dump(this)}`);
  }
});

// ---- @atdd_SPEC-001-04-8 ----
// 「提供物の一覧」の照合先(docs/impl/latest/65b09d93/issues/20261118_012630_cross-uc-scenarios.md の 4):
//   (a) CLI 契約 commands「$BLUE_RUNNER / $GREEN_RUNNER」の standard_runner(一覧の正本)
//   (b) 配置ディレクトリ(facade/)の runners/ の実体

Given(literal('relay-gate の提供物の一覧'), function () {
  const contract = YAML.parse(fs.readFileSync(CLI_CONTRACT, 'utf8'));
  this.contractText = fs.readFileSync(CLI_CONTRACT, 'utf8');
  const runnerCommands = (contract.commands || []).filter((command) => command.name === RUNNER_COMMAND_NAME);
  assert.equal(runnerCommands.length, 1, `CLI contract should define exactly one "${RUNNER_COMMAND_NAME}" command`);
  this.runnerCommand = runnerCommands[0];
  this.runnersDir = path.join(FACADE_HOME, 'runners');
});

When(literal('slot runner の位置づけを確認する'), function () {
  this.standardRunner = this.runnerCommand.standard_runner;
  this.runnerEntries = fs.readdirSync(this.runnersDir).sort();
});

Then(literal('標準の slot runner は正式な提供物として載っており、参考実装(仮採用)という扱いの runner は無い'), function () {
  // (a) 契約: 標準の slot runner が正式な提供物として載っている
  assert.ok(this.standardRunner, 'CLI contract should have standard_runner');
  assert.equal(this.standardRunner.file, 'runners/standard-runner.sh');
  assert.ok(String(this.standardRunner.summary).includes('正式な提供物'), `standard_runner.summary should state an official deliverable: ${this.standardRunner.summary}`);
  // (a) 契約: 参考実装という扱いの runner(旧仕様の ssh-runner.sh)は載っていない
  assert.ok(!this.contractText.includes('ssh-runner'), 'CLI contract should not mention ssh-runner');
  assert.ok(!this.contractText.includes('参考実装'), 'CLI contract should not mention a reference implementation');
  // (b) 配置ディレクトリ: 標準の slot runner は実行可能な通常ファイルで、参考実装の ssh-runner.sh は無い
  const standard = path.join(this.runnersDir, 'standard-runner.sh');
  assert.ok(fs.lstatSync(standard).isFile(), 'runners/standard-runner.sh should be a regular file');
  fs.accessSync(standard, fs.constants.X_OK);
  assert.ok(!this.runnerEntries.includes('ssh-runner.sh'), `runners/ should not include ssh-runner.sh: ${this.runnerEntries}`);
});
