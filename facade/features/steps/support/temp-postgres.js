// テスト用の一時 PostgreSQL(tier BDD の補助。step 定義ではない。cucumber の読込対象のディレクトリにあるが、step も hook も登録しない)。
// test-strategy.md「実体テストの環境前提」: initdb + pg_ctl でテストが自前で起動・破棄する一時インスタンスを使い、常設のサービスに接続しない。
// initdb / pg_ctl / psql が PATH に無い環境は fail にする(暗黙に skip しない)。
// 接続は Unix ドメインソケットだけ(listen_addresses='')。ソケットの置き場は短いパス(/tmp/rgpg-XXXXXX)にする
// (macOS の os.tmpdir() は長く、ソケットのパスの長さの上限を超えるため)。
// 起動はプロセスで 1 回だけ(最初に使う Scenario で起動)、Scenario ごとに新しいデータベースを作る。停止は stopTempPostgres。
//
// テーブルの DDL は暫定: 契約の生成物 packages/contracts/management-db/schema.json(rdb-schema.yaml の写し)から組み立てる。
// 正本は datastore_owner(tier-ops)の ops/migrations/ で、未整備の間だけこの DDL を使う(test-strategy.md「テスト用 DDL は正本ではない」)。
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCHEMA_JSON = path.resolve(__dirname, '../../../../packages/contracts/management-db/schema.json');
// facade.sh が書く表(と外部キーの参照先)。作る順は参照先が先
const TABLES = ['parallel_runs', 'slot_executions', 'rapid_runs'];
const SUPERUSER = 'postgres';
const PORT = '5432';

const state = { started: false, root: null, socketDir: null, dbCount: 0 };

function which(command) {
  const proc = spawnSync('bash', ['-c', 'command -v "$1"', '_', command], { encoding: 'utf8' });
  return proc.status === 0 ? proc.stdout.trim() : null;
}

function requireBinaries() {
  const missing = ['initdb', 'pg_ctl', 'psql'].filter((command) => !which(command));
  if (missing.length > 0) {
    throw new Error(`environment: ${missing.join(', ')} not found on PATH (temporary PostgreSQL for tier BDD)`);
  }
}

function run(command, args, options = {}) {
  const proc = spawnSync(command, args, { encoding: 'utf8', ...options });
  if (proc.error || proc.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed: ${proc.error || proc.stderr}`);
  }
  return proc.stdout;
}

// 暫定 DDL(schema.json の列定義から)。型は string / text → text、integer → integer、datetime → timestamp(タイムゾーンなし)
function ddl() {
  const schema = JSON.parse(fs.readFileSync(SCHEMA_JSON, 'utf8'));
  const typeMap = { string: 'text', text: 'text', integer: 'integer', datetime: 'timestamp', date: 'date', boolean: 'boolean' };
  const statements = ['-- provisional DDL generated from packages/contracts/management-db/schema.json (tests only)'];
  for (const name of TABLES) {
    const table = schema.tables.find((t) => t.name === name);
    if (!table) {
      throw new Error(`table ${name} not found in ${SCHEMA_JSON}`);
    }
    const lines = table.columns.map((column) => {
      const type = typeMap[column.type];
      if (!type) {
        throw new Error(`unknown column type ${column.type} (${name}.${column.name})`);
      }
      let line = `  ${column.name} ${type}${column.nullable ? '' : ' NOT NULL'}`;
      if (Array.isArray(column.enum)) {
        line += ` CHECK (${column.name} IN (${column.enum.map((v) => `'${v}'`).join(', ')}))`;
      }
      return line;
    });
    lines.push(`  PRIMARY KEY (${table.primary_key.join(', ')})`);
    for (const fk of table.foreign_keys || []) {
      lines.push(`  FOREIGN KEY (${fk.columns.join(', ')}) REFERENCES ${fk.references.table} (${fk.references.columns.join(', ')})`);
    }
    statements.push(`CREATE TABLE ${name} (\n${lines.join(',\n')}\n);`);
  }
  return statements.join('\n') + '\n';
}

function ensureStarted() {
  if (state.started) {
    return;
  }
  requireBinaries();
  state.root = fs.mkdtempSync(path.join(os.tmpdir(), 'relay-gate-pg-'));
  state.socketDir = fs.mkdtempSync('/tmp/rgpg-');
  const dataDir = path.join(state.root, 'data');
  run('initdb', ['-D', dataDir, '-A', 'trust', '-U', SUPERUSER, '--no-locale', '-E', 'UTF8']);
  run('pg_ctl', ['-D', dataDir, '-o', `-k ${state.socketDir} -c listen_addresses='' -p ${PORT}`, '-l', path.join(state.root, 'server.log'), '-w', 'start']);
  state.started = true;
}

function psqlArgs(dbname) {
  return ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-h', state.socketDir, '-p', PORT, '-U', SUPERUSER, '-d', dbname];
}

// Scenario 用の新しいデータベースを作り、暫定 DDL を流す。戻り値は接続先(テストの中だけで使う)
function createDatabase() {
  ensureStarted();
  state.dbCount += 1;
  const dbname = `rg_${process.pid}_${state.dbCount}`;
  run('psql', [...psqlArgs('postgres'), '-c', `CREATE DATABASE ${dbname}`]);
  run('psql', [...psqlArgs(dbname), '-f', '-'], { input: ddl() });
  return { host: state.socketDir, port: PORT, user: SUPERUSER, dbname };
}

// 参照名(接続サービス名)を接続先に結び付ける pg_service.conf を書く
function writeServiceFile(file, serviceName, db) {
  fs.writeFileSync(file, `[${serviceName}]\nhost=${db.host}\nport=${db.port}\nuser=${db.user}\ndbname=${db.dbname}\n`);
}

// SELECT の結果を行(列は | 区切り)の配列で返す
function query(db, sql) {
  const out = run('psql', [...psqlArgs(db.dbname), '-c', sql]);
  return out.split('\n').filter((line) => line.length > 0);
}

function stopTempPostgres() {
  if (!state.started) {
    return;
  }
  spawnSync('pg_ctl', ['-D', path.join(state.root, 'data'), '-m', 'immediate', '-w', 'stop'], { encoding: 'utf8' });
  fs.rmSync(state.root, { recursive: true, force: true });
  fs.rmSync(state.socketDir, { recursive: true, force: true });
  state.started = false;
}

module.exports = { createDatabase, writeServiceFile, query, stopTempPostgres, which };
