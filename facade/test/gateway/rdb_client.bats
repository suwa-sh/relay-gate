#!/usr/bin/env bats
# UC 09730858(slot 実行モードを選択して runner を起動する)× tier-facade: gateway/rdb_client.sh の単体テスト。
# 対象: 参照名の渡し方(接続サービス名)と psql の終了コードの読み替え。psql は PATH の先頭に置くスタブ
# (実 DB での確認は tier BDD の一時 PostgreSQL で行う)。

bats_require_minimum_version 1.5.0

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/gateway/rdb_client.sh"
	FAKE_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$FAKE_BIN"
	{
		printf '%s\n' '#!/usr/bin/env bash'
		printf '%s\n' 'printf "%s\n" "$@" >"$FAKE_PSQL_LOG.args"'
		printf '%s\n' 'cat >"$FAKE_PSQL_LOG.sql"'
		printf '%s\n' 'echo "secret connection detail host=db.example" >&2'
		printf '%s\n' 'echo out'
		printf '%s\n' 'exit "${FAKE_PSQL_EXIT:-0}"'
	} >"$FAKE_BIN/psql"
	chmod +x "$FAKE_BIN/psql"
	export FAKE_PSQL_LOG="$BATS_TEST_TMPDIR/psql"
	PATH="$FAKE_BIN:$PATH"
}

@test "rdb_client_conninfo_参照名に引用符とバックスラッシュがある場合_libpqの値の引用で囲むこと" {
	# Act
	rdb_client_conninfo "a'b\\c d"

	# Assert
	[ "$RDB_CLIENT_CONNINFO" = "service='a\\'b\\\\c d'" ]
}

@test "rdb_client_run_成功した場合_SQLを標準入力で渡し値を変数で渡しstdoutを受け取ること" {
	# Act
	rdb_client_run mgmt-db "SELECT :'v';" "v=it's"
	local status=$?

	# Assert
	[ "$status" -eq "$RDB_CLIENT_STATUS_OK" ]
	[ "$RDB_CLIENT_OUTPUT" = "out" ]
	grep -qx "service='mgmt-db'" "$FAKE_PSQL_LOG.args"
	grep -qx "v=it's" "$FAKE_PSQL_LOG.args"
	grep -qx -- "--single-transaction" "$FAKE_PSQL_LOG.args"
	grep -qx "ON_ERROR_STOP=1" "$FAKE_PSQL_LOG.args"
	[ "$(cat "$FAKE_PSQL_LOG.sql")" = "SELECT :'v';" ]
}

@test "rdb_client_run_psqlが接続できず2で終わった場合_接続失敗を返しpsqlのstderrを出さないこと" {
	# Arrange
	export FAKE_PSQL_EXIT=2

	# Act
	run --separate-stderr rdb_client_run mgmt-db "SELECT 1;"

	# Assert
	[ "$status" -eq "$RDB_CLIENT_STATUS_CONNECTION_FAILED" ]
	[ -z "$stderr" ]
}

@test "rdb_client_run_SQLが失敗して3で終わった場合_SQLの失敗を返すこと" {
	# Arrange
	export FAKE_PSQL_EXIT=3

	# Act
	run rdb_client_run mgmt-db "SELECT 1;"

	# Assert
	[ "$status" -eq "$RDB_CLIENT_STATUS_SQL_FAILED" ]
}

@test "rdb_client_run_psqlがPATHに無い場合_接続失敗を返すこと" {
	# Arrange
	RDB_CLIENT_COMMAND="$BATS_TEST_TMPDIR/no-such-psql"

	# Act
	run --separate-stderr rdb_client_run mgmt-db "SELECT 1;"

	# Assert
	[ "$status" -eq "$RDB_CLIENT_STATUS_CONNECTION_FAILED" ]
}

@test "rdb_client_require_rows_直前の出力に行がある場合_成功を返すこと" {
	# Arrange
	RDB_CLIENT_OUTPUT="run-1"

	# Act / Assert
	rdb_client_require_rows
}

@test "rdb_client_require_rows_直前の出力が空の場合_0件を返すこと" {
	# Arrange(条件付き UPDATE の RETURNING が 0 行)
	RDB_CLIENT_OUTPUT=""

	# Act
	run rdb_client_require_rows

	# Assert
	[ "$status" -eq "$RDB_CLIENT_STATUS_NO_ROWS" ]
}
