#!/usr/bin/env bats
# UC 6078c4ed(select-and-launch-slots-by-feature-flags)の TDD 単体テスト(④)— PostgreSQL 経路。
# RDB の正本は PostgreSQL(rdb-schema.yaml)。S5 attempt 5 findings F-001(PostgreSQL 経路未実装)への対応として、
# テストごとに使い捨ての実 PostgreSQL を起動し、psql クライアント経由の起動トランザクション
# (audit_chain_heads の run_id 行 SELECT ... FOR UPDATE + 6 テーブルの同一 transaction)を実体で検証する。
# - 既定は pg_ctl / initdb(PATH 上)の一時インスタンス。RELAYGATE_TEST_PG_BACKEND=docker で postgres:16-alpine コンテナに切替
# - PostgreSQL を起動できない環境では skip せず fail にする(実体テスト必須)。明示的に外す場合だけ RELAYGATE_TEST_SKIP_PG=1
# - DDL は facade/test/fixtures/relay-gate-db.postgresql.sql(rdb-schema.yaml から生成したテスト fixture。正本は worker/migrations)
# - エアーギャップ制約は実行時の制約であり、テスト時の一時 PostgreSQL は対象外

setup_file() {
	bats_require_minimum_version 1.5.0
	export PG_TEST_PROJECT_ROOT
	PG_TEST_PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	export PG_TEST_USER=relaygate
	if [[ ${RELAYGATE_TEST_SKIP_PG:-} == 1 ]]; then
		export PG_TEST_SKIPPED=1
		return 0
	fi
	export PG_TEST_DIR
	PG_TEST_DIR="$(mktemp -d)"
	export PG_TEST_PORT
	PG_TEST_PORT="$(free_tcp_port)"
	export PG_TEST_BACKEND="${RELAYGATE_TEST_PG_BACKEND:-}"
	if [[ -z $PG_TEST_BACKEND ]]; then
		if command -v initdb >/dev/null 2>&1 && command -v pg_ctl >/dev/null 2>&1; then
			PG_TEST_BACKEND=pg_ctl
		elif command -v docker >/dev/null 2>&1; then
			PG_TEST_BACKEND=docker
		else
			printf '%s\n' "PostgreSQL is required for this test file: install postgresql (initdb/pg_ctl/psql) or docker, or set RELAYGATE_TEST_SKIP_PG=1 to skip explicitly" >&2
			return 1
		fi
	fi
	command -v psql >/dev/null 2>&1 || {
		printf '%s\n' "psql client is required for this test file" >&2
		return 1
	}
	case "$PG_TEST_BACKEND" in
	pg_ctl) start_pg_ctl_instance ;;
	docker) start_docker_instance ;;
	*)
		printf '%s\n' "unknown RELAYGATE_TEST_PG_BACKEND: $PG_TEST_BACKEND" >&2
		return 1
		;;
	esac
	export PG_TEST_ADMIN_DSN="postgresql://$PG_TEST_USER@127.0.0.1:$PG_TEST_PORT/postgres"
}

teardown_file() {
	[[ -z ${PG_TEST_SKIPPED:-} ]] || return 0
	case "${PG_TEST_BACKEND:-}" in
	pg_ctl) pg_ctl -D "$PG_TEST_DIR/data" -m immediate stop >/dev/null 2>&1 || true ;;
	docker) [[ -z ${PG_TEST_CONTAINER:-} ]] || docker stop "$PG_TEST_CONTAINER" >/dev/null 2>&1 || true ;;
	esac
	rm -rf "$PG_TEST_DIR"
}

# free_tcp_port は 127.0.0.1 で未使用の TCP ポートを 1 つ返す。
free_tcp_port() {
	perl -MIO::Socket::INET -e 'my $s = IO::Socket::INET->new(LocalAddr => "127.0.0.1", LocalPort => 0, Listen => 1) or die; print $s->sockport'
}

# start_pg_ctl_instance は一時ディレクトリへ initdb した PostgreSQL を起動する(全 SQL を statement ログへ出す)。
start_pg_ctl_instance() {
	initdb -D "$PG_TEST_DIR/data" -U "$PG_TEST_USER" -A trust >"$PG_TEST_DIR/initdb.log" 2>&1 || {
		cat "$PG_TEST_DIR/initdb.log" >&2
		return 1
	}
	pg_ctl -D "$PG_TEST_DIR/data" -l "$PG_TEST_DIR/server.log" -w -t 60 \
		-o "-p $PG_TEST_PORT -c listen_addresses=127.0.0.1 -c unix_socket_directories=$PG_TEST_DIR -c log_statement=all" start >"$PG_TEST_DIR/pg_ctl.log" 2>&1 || {
		cat "$PG_TEST_DIR/pg_ctl.log" "$PG_TEST_DIR/server.log" >&2
		return 1
	}
}

# start_docker_instance は postgres:16-alpine コンテナを起動し、接続可能になるまで待つ。
start_docker_instance() {
	export PG_TEST_CONTAINER
	PG_TEST_CONTAINER="$(docker run --rm -d -e POSTGRES_USER="$PG_TEST_USER" -e POSTGRES_HOST_AUTH_METHOD=trust -p "127.0.0.1:$PG_TEST_PORT:5432" postgres:16-alpine -c log_statement=all)" || return 1
	local attempt
	for attempt in $(seq 1 60); do
		if psql -X -w -q "postgresql://$PG_TEST_USER@127.0.0.1:$PG_TEST_PORT/postgres" -c 'SELECT 1;' >/dev/null 2>&1; then
			return 0
		fi
		sleep 1
	done
	printf '%s\n' "PostgreSQL container did not become ready within 60s" >&2
	return 1
}

# pg_statement_log はサーバーの statement ログ全文を返す(backend により取得元が異なる)。
pg_statement_log() {
	case "$PG_TEST_BACKEND" in
	pg_ctl) cat "$PG_TEST_DIR/server.log" ;;
	docker) docker logs "$PG_TEST_CONTAINER" 2>&1 ;;
	esac
}

setup() {
	[[ -z ${PG_TEST_SKIPPED:-} ]] || skip "RELAYGATE_TEST_SKIP_PG=1"
	project_root="$PG_TEST_PROJECT_ROOT"
	test_dir="$(mktemp -d)"
	job_map_path="$test_dir/job-map.json"
	launch_log="$test_dir/launch.log"
	db_name="relaygate_test_$BATS_TEST_NUMBER"
	db_dsn="postgresql://$PG_TEST_USER@127.0.0.1:$PG_TEST_PORT/$db_name"
	mkdir -p "$test_dir/bin"

	cat >"$test_dir/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RELAYGATE_TEST_LAUNCH_LOG"
exit 0
EOF
	chmod +x "$test_dir/bin/ssh"

	# テストごとに空のデータベースを作り、契約 fixture の DDL を流す
	psql -X -w -q -v ON_ERROR_STOP=1 "$PG_TEST_ADMIN_DSN" -c "DROP DATABASE IF EXISTS $db_name;" -c "CREATE DATABASE $db_name;"
	psql -X -w -q -v ON_ERROR_STOP=1 "$db_dsn" -f "$project_root/facade/test/fixtures/relay-gate-db.postgresql.sql"

	cat >"$job_map_path" <<'JSON'
{
  "version": "v1.4.0",
  "jobs": {
    "daily-settlement": {
      "hang_detect_limit_minutes": 30,
      "slots": {
        "blue": {
          "host": "blue-host-01", "exec_user": "batchuser", "script_path": "/opt/blue/run.sh",
          "work_dir": "/opt/relaygate/work", "fixed_args": ["--mode", "batch"],
          "impl_version": "blue-2.3.1", "credential_ref": "cred-blue-batch"
        },
        "green": {
          "host": "green-host-01", "exec_user": "batchuser", "script_path": "/opt/green/run.sh",
          "work_dir": "/opt/relaygate/work", "fixed_args": [],
          "impl_version": "green-0.9.0", "credential_ref": "cred-green-batch"
        }
      }
    }
  }
}
JSON
}

teardown() {
	rm -rf "$test_dir"
}

# run_select_slot は PostgreSQL DSN と必須環境変数を与えて select-slot を実行する。引数: BLUE_MODE GREEN_MODE RAPID_CROSSCHECK_MODE JOB_ID [追加引数...]
run_select_slot() {
	local blue_mode="$1" green_mode="$2" rapid_mode="$3" job_id="$4"
	shift 4
	env \
		PATH="$test_dir/bin:$PATH" \
		RELAYGATE_TEST_LAUNCH_LOG="$launch_log" \
		RELAYGATE_RDB_DSN="$db_dsn" \
		RELAYGATE_JOB_MAP_PATH="$job_map_path" \
		RELAYGATE_OPERATOR="ops-tanaka" \
		BLUE_MODE="$blue_mode" GREEN_MODE="$green_mode" RAPID_CROSSCHECK_MODE="$rapid_mode" \
		"$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id "$job_id" "$@"
}

# pg_query はテスト用データベースへ SQL を投げ、タブ区切り・ヘッダー無しで返す。
pg_query() {
	psql -X -w -A -t -F $'\t' -v ON_ERROR_STOP=1 "$db_dsn" -c "$1"
}

count_rows() {
	pg_query "SELECT COUNT(*) FROM $1;"
}

@test "relaygate_concurrent_run_select_slot_PostgreSQL_DSNの場合_6テーブルへの記録を1つのtransactionでcommitしてからslotを起動すること" {
	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement -- --target-date 2026-08-18

	# Assert
	[ "$status" -eq 0 ]
	run_id="$(pg_query 'SELECT run_id FROM execution_specs;')"
	[[ "$run_id" =~ ^[0-9a-f-]{36}$ ]]
	[ "$(pg_query "SELECT job_id || '|' || job_map_version || '|' || hang_detect_limit_minutes || '|' || additional_args || '|' || (parent_run_id IS NULL) FROM execution_specs;")" = "daily-settlement|v1.4.0|30|--target-date 2026-08-18|true" ]
	[ "$(pg_query "SELECT slot_type || ':' || host || ':' || COALESCE(fixed_args, '<null>') || ':' || impl_version || ':' || credential_ref FROM slot_execution_specs ORDER BY slot_type;")" = $'blue:blue-host-01:--mode batch:blue-2.3.1:cred-blue-batch\ngreen:green-host-01:<null>:green-0.9.0:cred-green-batch' ]
	[ "$(pg_query "SELECT slot_type || ':' || role_type || ':' || attempt_no || ':' || status || ':' || (accepted_at = updated_at) FROM runner_results ORDER BY slot_type;")" = $'blue:foreground:1:STARTING:true\ngreen:background:1:STARTING:true' ]
	[ "$(pg_query "SELECT COUNT(*) FROM runner_result_events e JOIN runner_results r ON r.run_id = e.run_id AND r.slot_type = e.slot_type AND r.role_type = e.role_type AND r.attempt_id = e.attempt_id AND e.occurred_at = r.accepted_at WHERE e.event_name = 'attempt_started' AND e.status = 'STARTING';")" = "2" ]
	[ "$(pg_query "SELECT event_name || ':' || slot || ':' || attempt_id || ':' || actor || ':' || operation || ':' || outcome || ':' || (previous_hash IS NULL) FROM audit_logs WHERE event_name = 'slot_launch_accepted';")" = "slot_launch_accepted:-:-:ops-tanaka:slot_launch:accepted:true" ]
	[ "$(pg_query "SELECT COUNT(*) FROM audit_logs a JOIN audit_logs p ON p.event_hash = a.previous_hash AND p.run_id = a.run_id WHERE a.event_name = 'slot_launch_attempted';")" = "2" ]
	[ "$(pg_query "SELECT h.chain_length || ':' || (h.updated_at = a.occurred_at) FROM audit_chain_heads h JOIN audit_logs a ON a.event_id = h.head_event_id AND a.event_hash = h.head_hash AND a.run_id = h.run_id WHERE NOT EXISTS (SELECT 1 FROM audit_logs n WHERE n.previous_hash = a.event_hash);")" = "3:true" ]
	[ "$(printf '%s\n' "$output" | grep -c "^run_id=$run_id slot_type=.* role=.* attempt_id=.* status=STARTING$")" = "2" ]
	[ "$(wc -l <"$launch_log" | tr -d ' ')" = "2" ]
	# 起動トランザクションは psql への単一リクエスト(BEGIN ... FOR UPDATE ... COMMIT)として送られている(statement ログ)
	launch_statement="$(pg_statement_log | grep -F "statement: BEGIN; INSERT INTO execution_specs" | grep -F "'$run_id'")"
	[ "$(printf '%s\n' "$launch_statement" | wc -l | tr -d ' ')" = "1" ]
	[[ "$launch_statement" == *"SELECT head_hash FROM audit_chain_heads WHERE run_id = '$run_id' FOR UPDATE;"* ]]
	[[ "$launch_statement" == *"INSERT INTO audit_chain_heads"*"UPDATE audit_chain_heads SET"*"chain_length = 3"*" COMMIT;"* ]]
}

@test "relaygate_concurrent_run_select_slot_PostgreSQL_DSNでaudit_logsのINSERTが失敗する場合_6テーブルすべてをrollbackして起動しないこと" {
	# Arrange
	pg_query "CREATE FUNCTION reject_audit() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION 'injected audit failure'; END; \$\$; CREATE TRIGGER reject_audit BEFORE INSERT ON audit_logs FOR EACH ROW EXECUTE FUNCTION reject_audit();"

	# Act & Assert
	run --separate-stderr run_select_slot foreground background on daily-settlement
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"boundary=rdb"* ]]
	[[ "$stderr" == *"no slot was launched"* ]]
	for table in execution_specs slot_execution_specs runner_result_events runner_results audit_logs audit_chain_heads; do
		[ "$(count_rows "$table")" = "0" ]
	done
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_PostgreSQL_DSNでaudit_chain_headsのrun_id行が他transactionにロックされている場合_解放を待ってから既存チェーンへの分岐をrollbackすること" {
	# Arrange
	# run_id を固定し、同じ run_id のチェーン先頭行を別 transaction が FOR UPDATE で 3 秒間保持する
	fixed_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"
	cat >"$test_dir/bin/fixed-run-id" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == run_id ]]; then printf '%s' "$fixed_run_id"; else uuidgen | tr '[:upper:]' '[:lower:]'; fi
EOF
	chmod +x "$test_dir/bin/fixed-run-id"
	export RELAYGATE_ID_GENERATOR="$test_dir/bin/fixed-run-id"
	pg_query "INSERT INTO audit_chain_heads VALUES ('$fixed_run_id', '00000000-0000-4000-8000-000000000001', 'existing-head', 1, now());"
	psql -X -w -q -v ON_ERROR_STOP=1 "$db_dsn" -c "BEGIN; SELECT head_hash FROM audit_chain_heads WHERE run_id = '$fixed_run_id' FOR UPDATE; SELECT pg_sleep(3); COMMIT;" >/dev/null 2>&1 &
	lock_holder_pid=$!
	# ロック保持 transaction が FOR UPDATE を取得するまで待つ
	for _ in $(seq 1 50); do
		if [ "$(pg_query "SELECT COUNT(*) FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND state = 'active' AND query LIKE '%pg_sleep(3)%';")" = "1" ]; then break; fi
		sleep 0.1
	done
	started_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement
	elapsed_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"
	wait "$lock_holder_pid" || true

	# Assert
	# ロック解放(約 3 秒)まで待たされ、解放後は既存の head 行に対する INSERT が主キー違反となり transaction 全体が rollback される
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"boundary=rdb"* ]]
	awk -v started="$started_seconds" -v ended="$elapsed_seconds" 'BEGIN { exit !(ended - started >= 2.0) }'
	[ "$(count_rows audit_logs)" = "0" ]
	[ "$(count_rows execution_specs)" = "0" ]
	[ "$(pg_query "SELECT head_hash || ':' || chain_length FROM audit_chain_heads;")" = "existing-head:1" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_PostgreSQL_DSNでpsqlがPATHに無い場合_業務エラーで永続化も起動もしないこと" {
	# Arrange
	# relaygate が使う外部コマンドだけを持つ PATH を組み立て、psql を含めない
	mkdir -p "$test_dir/tools"
	for tool in bash perl jq uuidgen timeout dirname test env; do
		ln -s "$(type -P "$tool")" "$test_dir/tools/$tool"
	done

	# Act & Assert
	run --separate-stderr env -i PATH="$test_dir/bin:$test_dir/tools" RELAYGATE_TEST_LAUNCH_LOG="$launch_log" RELAYGATE_RDB_DSN="$db_dsn" RELAYGATE_JOB_MAP_PATH="$job_map_path" RELAYGATE_OPERATOR=ops-tanaka BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=on "$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id daily-settlement
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"reason=postgresql_client_unavailable"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_PostgreSQL_DSNの接続先が応答しない場合_業務エラーで起動しないこと" {
	# Arrange
	db_dsn="postgresql://$PG_TEST_USER@127.0.0.1:$(free_tcp_port)/$db_name"

	# Act & Assert
	run --separate-stderr run_select_slot foreground background on daily-settlement
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"boundary=rdb"* ]]
	[[ "$stderr" == *"reason=connection"* ]]
	[ ! -e "$launch_log" ]
}
