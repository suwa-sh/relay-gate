// UC BDD(②)step definition。uc_id=dcd8234d / branch_slug=define-crosscheck-job-map-and-comparison-definitions(S6 uc-bdd で実装)。
// 2026-11-10 S2 再生成: feedback run 2〜9 後の spec に合わせ、error 行が 1 行だけであることの Then・
// 「引数部分の内容は検査しない」・「クロスチェックジョブマップと対象カタログの検証種別は無い」の step を追加した。
// source: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md#E2E完了条件(BDD)
// step 文言は feature から転写したリテラルを正規表現で完全一致させる(S2 skeleton の方式を踏襲)。
//
// ハーネス設計は features/uc/steps/configure-feature-flags.steps.js(UC fd678b04)を踏襲する:
//   World / Before / After は同ファイルが定義済み(同一 require glob で読まれる。World は 1 つだけ)。
//   Scenario ごとの一時ディレクトリ(this.root)を sandbox root とし、仕様の絶対パス(/etc/relay-gate, /opt/compare)を
//   root 配下の同じ相対位置に配置する(/etc /opt へは書き込まない)。
//   RAPID_COMPARE_COMMAND のコマンド部分(先頭の語)が絶対パスのときだけ sandbox へ写像して env に書く
//   (相対パスは仕様どおりそのまま書く)。出力は root の接頭辞を落として feature の文言と突き合わせる。
// 「管理 DB への接続は行われず」は PATH の先頭に置いた psql / pg_isready の記録スタブが呼ばれないことで、
// 「relay-gate のスクリプトは変更されていない」は facade/bin・facade/src の全ファイルの内容ハッシュが実行前後で同じことで確認する。
// 実行時に外部接続(DB・ネットワーク)は行わない。tier 実装は変更しない。
'use strict';
const { Given, When, Then } = require('@cucumber/cucumber');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const REPO_ROOT = path.resolve(__dirname, '../../..');
const VALIDATE_CONFIG = path.join(REPO_ROOT, 'facade/bin/validate-config.sh');
const FACADE_SCRIPT_DIRS = [path.join(REPO_ROOT, 'facade/bin'), path.join(REPO_ROOT, 'facade/src')];

// feature に書かれた絶対パス(仕様の例示値)
const SPEC_RAPID_ENV_PATH = '/etc/relay-gate/rapid-crosscheck.env';
const SPEC_COMPARE = '/opt/compare/compare.sh';
const SPEC_COMPARE_V2 = '/opt/compare/compare-v2.sh';
const DB_CLIENT_STUBS = ['psql', 'pg_isready'];

function literal(text) {
  return new RegExp('^' + text.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&') + '$');
}

function writeExecutable(file, body) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, body, { mode: 0o755 });
}

function writeCompareStub(world, specPath) {
  writeExecutable(world.sandbox(specPath), '#!/usr/bin/env bash\nexit 0\n');
}

// 起動コマンドのコマンド部分(先頭の語)が絶対パスなら sandbox へ写像する(引数部分は書き換えない)
function sandboxCommand(world, command) {
  const match = /^(\S+)(.*)$/s.exec(command);
  if (!match || !match[1].startsWith('/')) {
    return command;
  }
  return world.sandbox(match[1]) + match[2];
}

// env の内容を書く。RAPID_COMPARE_COMMAND の行だけコマンド部分を sandbox へ写像する
function writeRapidEnv(world, lines) {
  const mapped = lines.map((line) => {
    const prefix = 'RAPID_COMPARE_COMMAND=';
    return line.startsWith(prefix) ? prefix + sandboxCommand(world, line.slice(prefix.length)) : line;
  });
  const file = world.sandbox(SPEC_RAPID_ENV_PATH);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, mapped.join('\n') + '\n');
}

function writeRapidEnvWithCommand(world, command) {
  writeRapidEnv(world, ['RAPID_DB_CONN_REF=rapid_db', `RAPID_COMPARE_COMMAND=${command}`]);
}

// DB クライアントの記録スタブ(呼ばれたら root/var/db-client.invoked に記録する)
function prepareDbClientStubs(world) {
  const binDir = path.join(world.root, 'stub-bin');
  const sentinel = path.join(world.root, 'var', 'db-client.invoked');
  for (const name of DB_CLIENT_STUBS) {
    writeExecutable(
      path.join(binDir, name),
      '#!/usr/bin/env bash\nmkdir -p "$(dirname "$RELAY_GATE_UC_BDD_DB_SENTINEL")"\n' +
        'printf \'%s %s\\n\' "' + name + '" "$*" >>"$RELAY_GATE_UC_BDD_DB_SENTINEL"\nexit 0\n',
    );
  }
  world.dbSentinel = sentinel;
  return binDir;
}

function hashScripts() {
  const hash = crypto.createHash('sha256');
  const walk = (dir) => {
    for (const name of fs.readdirSync(dir).sort()) {
      const full = path.join(dir, name);
      const stat = fs.statSync(full);
      if (stat.isDirectory()) {
        walk(full);
      } else {
        hash.update(path.relative(REPO_ROOT, full) + '\0' + stat.mode.toString(8) + '\0');
        hash.update(fs.readFileSync(full));
        hash.update('\0');
      }
    }
  };
  FACADE_SCRIPT_DIRS.forEach(walk);
  return hash.digest('hex');
}

function runRapidCrosscheck(world) {
  const file = world.sandbox(SPEC_RAPID_ENV_PATH);
  assert.ok(fs.existsSync(file), `rapid-crosscheck.env fixture should exist: ${SPEC_RAPID_ENV_PATH}`);
  const stubBin = prepareDbClientStubs(world);
  world.scriptsHashBefore = hashScripts();
  const proc = spawnSync(VALIDATE_CONFIG, ['--rapid-crosscheck', file], {
    cwd: world.root,
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${stubBin}${path.delimiter}${process.env.PATH}`,
      RELAY_GATE_CONFIG_DIR: world.sandbox('/etc/relay-gate'),
      RELAY_GATE_UC_BDD_DB_SENTINEL: world.dbSentinel,
    },
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  world.scriptsHashAfter = hashScripts();
  world.result = {
    status: proc.status,
    stdout: world.unsandbox(proc.stdout),
    stderr: world.unsandbox(proc.stderr),
  };
  return world.result;
}

function lines(text) {
  return text.split('\n').filter((line) => line !== '');
}

function assertExit(world, code) {
  assert.equal(world.result.status, code, `exit code\nstdout:\n${world.result.stdout}\nstderr:\n${world.result.stderr}`);
}

function assertStdoutHas(world, expected) {
  const out = lines(world.result.stdout);
  for (const line of expected) {
    assert.ok(out.includes(line), `stdout should include "${line}"\nstdout:\n${world.result.stdout}`);
  }
}

function errorLines(world) {
  return lines(world.result.stderr).filter((line) => line.startsWith('error:'));
}

function assertStderrHas(world, expected) {
  assert.ok(
    lines(world.result.stderr).includes(expected),
    `stderr should include "${expected}"\nstderr:\n${world.result.stderr}`,
  );
}

// 「<文言> の 1 行だけが error 行として出る」: error: で始まる行がちょうど 1 行で、その行が期待の文言と一致する
function assertOnlyErrorLine(world, expected) {
  assert.deepEqual(errorLines(world), [expected], `error lines should be exactly ["${expected}"]\nstderr:\n${world.result.stderr}`);
}

// 廃止された検証種別(クロスチェックジョブマップ / 対象カタログ)の Scenario Outline の Examples の値だけを受ける。
// 汎用の正規表現にすると `--rapid-crosscheck` の When と曖昧一致するため、値を列挙する。
const ABOLISHED_OPTION = '(--crosscheck-job-map|--target-catalog)';
const ABOLISHED_FILE = '(crosscheck-job-map\\.csv|target-catalog\\.csv)';

// --- 速報の起動コマンドを検証する(SPEC-004-01) ---

Given(literal('/etc/relay-gate/rapid-crosscheck.env の内容が次である'), function (docString) {
  writeRapidEnv(this, docString.split('\n').filter((line) => line !== ''));
});

Given(literal('/opt/compare/compare.sh が実行可能である'), function () {
  writeCompareStub(this, SPEC_COMPARE);
});

When(literal('基盤適用設計者が `validate-config.sh --rapid-crosscheck /etc/relay-gate/rapid-crosscheck.env` を実行する'), function () {
  runRapidCrosscheck(this);
});

Then(
  literal('終了コード 0 で stdout に `config=rapid-crosscheck`、`path: /etc/relay-gate/rapid-crosscheck.env`、`command_path: /opt/compare/compare.sh`、`has_job_id_placeholder=true`、`status=valid` がこの順で出る'),
  function () {
    assertExit(this, 0);
    // 「この順で出る」: stdout の行の並びが仕様の固定順と一致する(valid 時は violations 行を出さない)
    assert.deepEqual(lines(this.result.stdout), [
      'config=rapid-crosscheck',
      `path: ${SPEC_RAPID_ENV_PATH}`,
      `command_path: ${SPEC_COMPARE}`,
      'has_job_id_placeholder=true',
      'status=valid',
    ]);
  },
);

Then(literal('stderr に error 行は出ない'), function () {
  assert.deepEqual(errorLines(this), [], `no error line expected\nstderr:\n${this.result.stderr}`);
});

Then(literal('管理 DB への接続は行われず、relay-gate のスクリプトは変更されていない'), function () {
  assert.equal(fs.existsSync(this.dbSentinel), false, 'DB client (psql / pg_isready) should not be invoked');
  assert.equal(this.scriptsHashAfter, this.scriptsHashBefore, 'facade scripts should be unchanged');
});

// --- 起動コマンドを差し替えて検証する ---

Given(
  literal('rapid-crosscheck.env の RAPID_COMPARE_COMMAND を `/opt/compare/compare-v2.sh --job {job_id}` に変更し、/opt/compare/compare-v2.sh が実行可能である'),
  function () {
    // 差し替え前の状態(compare.sh の起動コマンド)を置いてから、値だけを compare-v2.sh へ変更する
    writeCompareStub(this, SPEC_COMPARE);
    writeRapidEnvWithCommand(this, `${SPEC_COMPARE} --job {job_id} --run {run_id}`);
    writeCompareStub(this, SPEC_COMPARE_V2);
    writeRapidEnvWithCommand(this, `${SPEC_COMPARE_V2} --job {job_id}`);
  },
);

When(literal('`validate-config.sh --rapid-crosscheck /etc/relay-gate/rapid-crosscheck.env` を実行する'), function () {
  runRapidCrosscheck(this);
});

Then(literal('終了コード 0 で stdout に `command_path: /opt/compare/compare-v2.sh`、`status=valid` が出る'), function () {
  assertExit(this, 0);
  assertStdoutHas(this, [`command_path: ${SPEC_COMPARE_V2}`, 'status=valid']);
});

// --- 引数部分の内容は検査しない(SPEC-004-04) ---

Given(
  literal(
    'rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `/opt/compare/compare.sh --job {job_id} --in /no/such/path unknown-word` で、引数部分に存在しないパスと未知の語を含み、`{params}` を引数の一部に含まない',
  ),
  function () {
    // 引数部分(/no/such/path)は sandbox へ写像しない(存在しないパスのまま書く)
    writeRapidEnvWithCommand(this, `${SPEC_COMPARE} --job {job_id} --in /no/such/path unknown-word`);
    assert.equal(fs.existsSync('/no/such/path'), false, 'fixture premise: /no/such/path should not exist');
  },
);

Then(
  literal('終了コード 0 で stdout に `command_path: /opt/compare/compare.sh`、`has_job_id_placeholder=true`、`status=valid` が出る'),
  function () {
    assertExit(this, 0);
    assertStdoutHas(this, [`command_path: ${SPEC_COMPARE}`, 'has_job_id_placeholder=true', 'status=valid']);
  },
);

// --- コマンド部分が実行できない ---

Given(
  literal('rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `/opt/compare/missing.sh --job {job_id}` でコマンド部分が存在しない'),
  function () {
    writeRapidEnvWithCommand(this, '/opt/compare/missing.sh --job {job_id}');
    assert.equal(fs.existsSync(this.sandbox('/opt/compare/missing.sh')), false);
  },
);

Then(
  literal('終了コードは 2 で stderr に `error: file not executable key=RAPID_COMPARE_COMMAND path=/opt/compare/missing.sh` の 1 行だけが error 行として出る'),
  function () {
    assertExit(this, 2);
    assertOnlyErrorLine(this, 'error: file not executable key=RAPID_COMPARE_COMMAND path=/opt/compare/missing.sh');
  },
);

// --- コマンド部分が絶対パスでない ---

Given(literal('rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `compare.sh --job {job_id}` で先頭の語が絶対パスでない'), function () {
  writeRapidEnvWithCommand(this, 'compare.sh --job {job_id}');
});

Then(
  literal('終了コードは 2 で stderr に `error: path is not absolute key=RAPID_COMPARE_COMMAND path=compare.sh` の 1 行だけが error 行として出る'),
  function () {
    assertExit(this, 2);
    assertOnlyErrorLine(this, 'error: path is not absolute key=RAPID_COMPARE_COMMAND path=compare.sh');
  },
);

// --- {job_id} プレースホルダが無い ---

Given(literal('rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `/opt/compare/compare.sh --run {run_id}` で `{job_id}` を含まない'), function () {
  // {job_id} 欠落だけを違反にするため、コマンド部分は実行可能にしておく
  writeCompareStub(this, SPEC_COMPARE);
  writeRapidEnvWithCommand(this, `${SPEC_COMPARE} --run {run_id}`);
});

Then(
  literal('終了コードは 2 で stderr に `error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --run {run_id}` の 1 行だけが error 行として出る'),
  function () {
    assertExit(this, 2);
    assertOnlyErrorLine(this,'error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --run {run_id}');
  },
);

// --- {params} が引数全体でない位置にある ---

Given(
  literal('rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `/opt/compare/compare.sh --job {job_id} --args={params}` で、`{params}` が `--args=` と同じ引数の一部になっている'),
  function () {
    writeCompareStub(this, SPEC_COMPARE);
    writeRapidEnvWithCommand(this, `${SPEC_COMPARE} --job {job_id} --args={params}`);
  },
);

Then(
  literal('終了コードは 2 で stderr に `error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --job {job_id} --args={params}` の 1 行だけが error 行として出る'),
  function () {
    assertExit(this, 2);
    assertOnlyErrorLine(
      this,
      'error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=/opt/compare/compare.sh --job {job_id} --args={params}',
    );
  },
);

// --- {params} が引数 1 つ全体なら valid ---

Given(
  literal('rapid-crosscheck.env の RAPID_COMPARE_COMMAND が `/opt/compare/compare.sh --job {job_id} {params}` で、`{params}` が独立した 1 引数であり /opt/compare/compare.sh が実行可能である'),
  function () {
    writeCompareStub(this, SPEC_COMPARE);
    writeRapidEnvWithCommand(this, `${SPEC_COMPARE} --job {job_id} {params}`);
  },
);

Then(literal('終了コード 0 で stdout に `status=valid` が出る'), function () {
  assertExit(this, 0);
  assertStdoutHas(this, ['status=valid']);
});

// --- クロスチェックジョブマップと対象カタログの検証種別は無い(SPEC-004-04) ---

Given(new RegExp(`^/etc/relay-gate/${ABOLISHED_FILE} が存在する$`), function (file) {
  // 旧形式の CSV を設定ファイル置き場に実ファイルとして置く(中身は検証されない前提のため最小のヘッダー行)
  const target = this.sandbox(`/etc/relay-gate/${file}`);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, 'job_id\n');
});

When(new RegExp(`^\`validate-config\\.sh ${ABOLISHED_OPTION} /etc/relay-gate/${ABOLISHED_FILE}\` を実行する$`), function (option, file) {
  const target = this.sandbox(`/etc/relay-gate/${file}`);
  assert.ok(fs.existsSync(target), `fixture should exist: /etc/relay-gate/${file}`);
  const proc = spawnSync(VALIDATE_CONFIG, [option, target], {
    cwd: this.root,
    encoding: 'utf8',
    env: { ...process.env, RELAY_GATE_CONFIG_DIR: this.sandbox('/etc/relay-gate') },
  });
  assert.equal(proc.error, undefined, `spawn failed: ${proc.error}`);
  this.result = { status: proc.status, stdout: this.unsandbox(proc.stdout), stderr: this.unsandbox(proc.stderr) };
  this.abolishedOption = option;
});

Then(new RegExp(`^終了コードは 2 で stderr に \`error: unknown option option=${ABOLISHED_OPTION}\` が出る$`), function (option) {
  // S6 自己点検で強化: Then の option が When で実際に渡した option と同じであることを確かめる(取り違えの見逃し防止)
  assert.equal(option, this.abolishedOption, 'Then option should match the option passed in When');
  assertExit(this, 2);
  assertStderrHas(this, `error: unknown option option=${option}`);
});

Then(literal('stdout に検証結果(`config=` 行)は出ない'), function () {
  assert.equal(
    lines(this.result.stdout).some((line) => line.startsWith('config=')),
    false,
    `stdout should not include config= line\nstdout:\n${this.result.stdout}`,
  );
});
