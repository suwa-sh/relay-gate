#!/usr/bin/env bats
# UC 6078c4ed(select-and-launch-slots-by-feature-flags)の TDD 単体テスト(④)— deadline / プロセス掃除 / 入力検証 / 純粋関数。
# S4 attempt 6(spec 20260829_210828_spec_generation 還流後の再実行)で新契約へ整理した:
# - ジョブマップは slot 別ファイル(RELAYGATE_JOB_MAP_PATH_BLUE / _GREEN。cli-command-contract.yaml job_map_contract)
# - 認証情報は認証情報ディレクトリ(RELAYGATE_CREDENTIAL_DIR/{credential_ref}、0600。credential_resolution)
# - 引数は JSON 配列で保存(argument_serialization)、送出失敗 / timeout は FAILED / UNKNOWN へ補償記録
# - event_hash は audit-event-contract.yaml hash_chain.canonical_form(エスケープ付き 13 項目 + previous_hash)
# 主経路の受け入れ検証は select-and-launch-slots-by-feature-flags.bats(SQLite)と 6078c4ed_select_slot_postgresql.bats(正本 PostgreSQL)が担い、
# 本ファイルは CTP-009(10 秒以内)の deadline・子プロセス掃除・契約の細部(検証順序 / 認証情報 / outbox / 時刻の単調増加)を担う。
# スキーマは契約定数(packages/contracts/relay-gate-db/schema-constants.sh)の列と rdb-schema.yaml の PK / UNIQUE に合わせた SQLite
# (限定検証境界: issues/20260817T230000Z)。

setup() {
	bats_require_minimum_version 1.5.0
	project_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	test_dir="$(mktemp -d)"
	db_path="$test_dir/relaygate.db"
	etc_dir="$test_dir/etc/relaygate"
	credential_dir="$etc_dir/credentials"
	job_map_blue="$etc_dir/job-map.blue.json"
	job_map_green="$etc_dir/job-map.green.json"
	launch_log="$test_dir/launch.log"
	system_sqlite="$(command -v sqlite3)"
	system_jq="$(command -v jq)"
	mkdir -p "$test_dir/bin" "$credential_dir"

	# ssh スタブ: RELAYGATE_TEST_SSH_MODE で振る舞いを切り替え、起動イベント(引数列)を起動ログへ追記する
	cat >"$test_dir/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RELAYGATE_TEST_LAUNCH_LOG"
case "${RELAYGATE_TEST_SSH_MODE:-success}" in
success) ;;
fail) exit 255 ;;
hang) sleep 20 ;;
spawn-child-hang) sleep 20 & child_pid=$!; printf '%s' "$child_pid" >"$RELAYGATE_TEST_CHILD_PID_PATH"; wait "$child_pid" ;;
spawn-term-ignoring-child) bash -c 'trap "" TERM; sleep 20' & child_pid=$!; printf '%s' "$child_pid" >"$RELAYGATE_TEST_CHILD_PID_PATH"; wait "$child_pid" ;;
delayed-success) sleep "${RELAYGATE_TEST_SSH_DELAY_SECONDS:-4}" ;;
*) exit 64 ;;
esac
EOF
	chmod +x "$test_dir/bin/ssh"

	# sqlite3 スタブ: RDB 書込みの遅延を再現する
	cat >"$test_dir/bin/sqlite3" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${RELAYGATE_TEST_SQLITE_DELAY_SECONDS:-}" ]]; then
  sleep "$RELAYGATE_TEST_SQLITE_DELAY_SECONDS"
fi
exec "$RELAYGATE_TEST_SYSTEM_SQLITE3" "$@"
EOF
	chmod +x "$test_dir/bin/sqlite3"

	sqlite3 "$db_path" <<'SQL'
CREATE TABLE execution_specs (
  run_id TEXT PRIMARY KEY, parent_run_id TEXT REFERENCES execution_specs(run_id),
  job_id TEXT NOT NULL, additional_args TEXT, hang_detect_limit_minutes INTEGER NOT NULL
);
CREATE TABLE slot_execution_specs (
  run_id TEXT NOT NULL REFERENCES execution_specs(run_id), slot_type TEXT NOT NULL,
  host TEXT NOT NULL, exec_user TEXT NOT NULL, script_path TEXT NOT NULL, work_dir TEXT NOT NULL,
  fixed_args TEXT, impl_version TEXT NOT NULL, credential_ref TEXT, job_map_version TEXT NOT NULL,
  PRIMARY KEY (run_id, slot_type)
);
CREATE TABLE runner_result_events (
  event_id TEXT PRIMARY KEY, run_id TEXT NOT NULL, slot_type TEXT NOT NULL, role_type TEXT NOT NULL,
  attempt_id TEXT NOT NULL, attempt_no INTEGER NOT NULL, event_name TEXT NOT NULL, status TEXT NOT NULL,
  occurred_at TEXT NOT NULL, started_at TEXT, stdout_path TEXT, stderr_path TEXT, exit_code INTEGER,
  UNIQUE (run_id, slot_type, role_type, attempt_id, event_name)
);
CREATE TABLE runner_results (
  run_id TEXT NOT NULL, slot_type TEXT NOT NULL, role_type TEXT NOT NULL, attempt_id TEXT NOT NULL,
  attempt_no INTEGER NOT NULL, accepted_at TEXT NOT NULL, started_at TEXT, stdout_path TEXT,
  stderr_path TEXT, exit_code INTEGER, status TEXT NOT NULL, updated_at TEXT NOT NULL,
  PRIMARY KEY (run_id, slot_type, role_type, attempt_id),
  UNIQUE (run_id, slot_type, role_type, attempt_no)
);
CREATE TABLE audit_logs (
  event_id TEXT PRIMARY KEY, event_name TEXT NOT NULL, schema_version TEXT NOT NULL,
  run_id TEXT NOT NULL, parent_run_id TEXT, slot TEXT NOT NULL, attempt_id TEXT NOT NULL,
  occurred_at TEXT NOT NULL, actor TEXT NOT NULL, operation TEXT NOT NULL, outcome TEXT NOT NULL,
  final_status TEXT, error_code TEXT, previous_hash TEXT, event_hash TEXT NOT NULL,
  UNIQUE (run_id, slot, attempt_id, event_name)
);
CREATE TABLE audit_chain_heads (
  run_id TEXT PRIMARY KEY, head_event_id TEXT NOT NULL, head_hash TEXT NOT NULL,
  chain_length INTEGER NOT NULL, updated_at TEXT NOT NULL
);
CREATE TABLE rapid_crosscheck_requests (
  run_id TEXT PRIMARY KEY, parent_run_id TEXT, job_id TEXT, blue_run_id TEXT, green_run_id TEXT,
  blue_attempt_id TEXT, green_attempt_id TEXT, comparison_definition_valid_from TEXT,
  requested_at TEXT, status TEXT, lease_expires_at TEXT, worker_id TEXT
);
SQL

	# ジョブマップ fixture(cli-command-contract.yaml job_map_contract の slot 別ファイル。値は spec.md の Background)
	cat >"$job_map_blue" <<'JSON'
{
  "job_map_version": "v1.4.0",
  "slot_type": "blue",
  "jobs": {
    "daily-settlement": {
      "host": "blue-host-01", "exec_user": "batchuser", "script_path": "/opt/blue/run.sh",
      "work_dir": "/opt/relaygate/work", "fixed_args": ["--mode", "batch"],
      "impl_version": "blue-2.3.1", "credential_ref": "cred-blue-batch", "hang_detect_limit_minutes": 30
    }
  }
}
JSON
	cat >"$job_map_green" <<'JSON'
{
  "job_map_version": "v1.4.0",
  "slot_type": "green",
  "jobs": {
    "daily-settlement": {
      "host": "green-host-01", "exec_user": "batchuser", "script_path": "/opt/green/run.sh",
      "work_dir": "/opt/relaygate/work", "fixed_args": ["--mode", "batch"],
      "impl_version": "green-0.9.0", "credential_ref": "cred-green-batch", "hang_detect_limit_minutes": 45
    }
  }
}
JSON
	printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nbats-test-key cred-blue-batch\n-----END OPENSSH PRIVATE KEY-----\n' >"$credential_dir/cred-blue-batch"
	printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nbats-test-key cred-green-batch\n-----END OPENSSH PRIVATE KEY-----\n' >"$credential_dir/cred-green-batch"
	chmod 0600 "$credential_dir/cred-blue-batch" "$credential_dir/cred-green-batch"
}

teardown() {
	rm -rf "$test_dir"
}

# set_job_field は slot のジョブマップの jobs."daily-settlement" のフィールドを JSON 値で書き換える。
set_job_field() {
	local slot="$1" field="$2" value="$3" path
	if [[ $slot == blue ]]; then path="$job_map_blue"; else path="$job_map_green"; fi
	jq --argjson value "$value" ".jobs[\"daily-settlement\"].$field = \$value" "$path" >"$path.next"
	mv "$path.next" "$path"
}

# run_select_slot は必須環境変数を与えて select-slot を実行する。引数: BLUE_MODE GREEN_MODE RAPID_CROSSCHECK_MODE JOB_ID [追加引数...]
run_select_slot() {
	local blue_mode="$1" green_mode="$2" rapid_mode="$3" job_id="$4"
	shift 4
	env \
		PATH="$test_dir/bin:$PATH" \
		RELAYGATE_TEST_SYSTEM_SQLITE3="$system_sqlite" \
		RELAYGATE_TEST_SYSTEM_JQ="$system_jq" \
		RELAYGATE_TEST_LAUNCH_LOG="$launch_log" \
		RELAYGATE_RDB_DSN="sqlite://$db_path" \
		RELAYGATE_JOB_MAP_PATH_BLUE="$job_map_blue" \
		RELAYGATE_JOB_MAP_PATH_GREEN="$job_map_green" \
		RELAYGATE_CREDENTIAL_DIR="$credential_dir" \
		RELAYGATE_OPERATOR="ops-tanaka" \
		BLUE_MODE="$blue_mode" GREEN_MODE="$green_mode" RAPID_CROSSCHECK_MODE="$rapid_mode" \
		"$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id "$job_id" "$@"
}

count_rows() {
	sqlite3 "$db_path" "SELECT COUNT(*) FROM $1;"
}

# strip_test_dir は標準エラー中の一時ディレクトリ接頭辞を取り除き、仕様の /etc/relaygate/... 表記と比較できる形にする
strip_test_dir() {
	printf '%s' "${1//"$test_dir"/}"
}

# elapsed_under は開始時刻からの経過秒が上限未満であることを検証する。
elapsed_under() {
	local started="$1" limit="$2" ended
	ended="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"
	awk -v started="$started" -v ended="$ended" -v limit="$limit" 'BEGIN { exit !(ended - started < limit) }'
}

now_seconds() {
	perl -MTime::HiRes=time -e 'printf "%.6f", time'
}

# source_facade_libraries は純粋関数(SQL 生成・ハッシュ)を直接検証するために層別ライブラリを読み込む。
source_facade_libraries() {
	source "$project_root/packages/contracts/relay-gate-db/schema-constants.sh"
	source "$project_root/facade/src/presentation.sh"
	source "$project_root/facade/src/domain.sh"
	source "$project_root/facade/src/rdb_gateway.sh"
}

# ---- deadline(CTP-009: 10 秒以内)とプロセス掃除 ----

@test "relaygate_concurrent_run_select_slot_初期化filesystemが遅延した場合_CLI全体deadline内に打ち切ること" {
	# Arrange
	cat >"$test_dir/bin/dirname" <<'EOF'
#!/usr/bin/env bash
sleep 20
exec /usr/bin/dirname "$@"
EOF
	chmod +x "$test_dir/bin/dirname"
	started_seconds="$(now_seconds)"

	# Act
	run --separate-stderr run_select_slot foreground off on daily-settlement

	# Assert
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"initialization"* ]]
	elapsed_under "$started_seconds" 10
}

@test "relaygate_concurrent_run_select_slot_job_map可読性確認が遅延した場合_タイムアウトとしてCLI全体deadline内に打ち切ること" {
	# Arrange
	cat >"$test_dir/bin/test" <<'EOF'
#!/usr/bin/env bash
sleep 20
exec /usr/bin/test "$@"
EOF
	chmod +x "$test_dir/bin/test"
	started_seconds="$(now_seconds)"

	# Act
	run --separate-stderr run_select_slot foreground off on daily-settlement

	# Assert
	[ "$status" -eq 124 ]
	[[ "$stderr" == *"ジョブマップを読み込めません: slot_type=blue"*"reason=timeout"* ]]
	elapsed_under "$started_seconds" 10
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_SSHが子プロセスを生成した場合_deadline後に子PIDを残さずUNKNOWNを記録すること" {
	# Arrange
	export RELAYGATE_TEST_SSH_MODE=spawn-child-hang
	export RELAYGATE_TEST_CHILD_PID_PATH="$test_dir/child.pid"
	started_seconds="$(now_seconds)"

	# Act
	run --separate-stderr run_select_slot foreground off on daily-settlement

	# Assert
	[ "$status" -eq 124 ]
	[[ "$stderr" == *"blue実装への起動イベント送出がtimeoutしました"* ]]
	elapsed_under "$started_seconds" 10
	child_pid="$(<"$RELAYGATE_TEST_CHILD_PID_PATH")"
	! kill -0 "$child_pid" 2>/dev/null
	[ "$(sqlite3 "$db_path" 'SELECT status FROM runner_results;')" = "UNKNOWN" ]
}

@test "relaygate_concurrent_run_select_slot_SSHの子プロセスがTERMを無視する場合_KILLでPIDを残さないこと" {
	# Arrange
	export RELAYGATE_TEST_SSH_MODE=spawn-term-ignoring-child
	export RELAYGATE_TEST_CHILD_PID_PATH="$test_dir/child.pid"

	# Act
	run --separate-stderr run_select_slot foreground off on daily-settlement

	# Assert
	[ "$status" -eq 124 ]
	child_pid="$(<"$RELAYGATE_TEST_CHILD_PID_PATH")"
	! kill -0 "$child_pid" 2>/dev/null
}

@test "relaygate_concurrent_run_select_slot_fixed_argsの復元が遅延しSSH待機の残余が無い場合_送出せずFAILEDへ補償記録しdeadlineを超えないこと" {
	# Arrange
	# argv 復元(jq -j。ジョブマップ抽出の jq -j --arg は除く)だけを 7 秒遅らせ、補償記録の予約時間を差し引いた SSH 待機の残余を無くす
	cat >"$test_dir/bin/jq" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-j" && "$2" != "--arg" ]]; then sleep 7; fi
exec "$RELAYGATE_TEST_SYSTEM_JQ" "$@"
EOF
	chmod +x "$test_dir/bin/jq"
	export RELAYGATE_TEST_SSH_MODE=hang
	started_seconds="$(now_seconds)"

	# Act
	run --separate-stderr run_select_slot off foreground off daily-settlement

	# Assert
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"green実装への起動イベント送出に失敗しました"*"reason=deadline_exhausted"* ]]
	elapsed_under "$started_seconds" 10
	[ ! -e "$launch_log" ]
	[ "$(sqlite3 "$db_path" 'SELECT status FROM runner_results;')" = "FAILED" ]
}

@test "relaygate_concurrent_run_select_slot_起動トランザクションのRDB書込みが遅延した場合_終了コード124で打ち切り永続化も起動もしないこと" {
	# Arrange
	export RELAYGATE_TEST_SQLITE_DELAY_SECONDS=20
	started_seconds="$(now_seconds)"

	# Act
	run --separate-stderr run_select_slot foreground off on daily-settlement

	# Assert
	[ "$status" -eq 124 ]
	[[ "$stderr" == *"boundary=rdb"* ]]
	[[ "$stderr" == *"reason=timeout"* ]]
	elapsed_under "$started_seconds" 10
	[ "$(count_rows execution_specs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_両slotの送出が遅延した場合_CLI全体deadline内に2回目をtimeoutとして打ち切りUNKNOWNを記録すること" {
	# Arrange
	export RELAYGATE_TEST_SSH_MODE=delayed-success
	export RELAYGATE_TEST_SSH_DELAY_SECONDS=4
	started_seconds="$(now_seconds)"

	# Act
	run --separate-stderr run_select_slot background background on daily-settlement

	# Assert
	[ "$status" -eq 124 ]
	[[ "$stderr" == *"green実装への起動イベント送出がtimeoutしました"* ]]
	[[ "$stderr" != *"blue実装への起動イベント送出"* ]]
	elapsed_under "$started_seconds" 10
	[ "$(wc -l <"$launch_log" | tr -d ' ')" = "2" ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || status FROM runner_results ORDER BY slot_type;')" = $'blue:STARTING\ngreen:UNKNOWN' ]
}

@test "relaygate_concurrent_run_select_slot_SSHが応答しない場合_seam未設定でも10秒以内に124で終了しUNKNOWNを記録すること" {
	# Arrange
	export RELAYGATE_TEST_SSH_MODE=hang
	started_seconds="$(now_seconds)"

	# Act
	run --separate-stderr run_select_slot foreground off on daily-settlement

	# Assert
	[ "$status" -eq 124 ]
	elapsed_under "$started_seconds" 10
	[ "$(sqlite3 "$db_path" 'SELECT status || ":" || (exit_code IS NULL) FROM runner_results;')" = "UNKNOWN:1" ]
	[ "$(sqlite3 "$db_path" 'SELECT event_name FROM runner_result_events ORDER BY occurred_at;')" = $'attempt_started\nattempt_unknown' ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_logs WHERE event_name = "slot_launch_timeout";')" = "1" ]
}

# ---- 起動イベントの構成 ----

@test "relaygate_concurrent_run_select_slot_排他制約を満たす場合_起動イベントを実行設定の値と解決した秘密鍵パスだけで構成すること" {
	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	run_id="$(sqlite3 "$db_path" 'SELECT run_id FROM execution_specs;')"
	[ "$(wc -l <"$launch_log" | tr -d ' ')" = "2" ]
	[[ "$(<"$launch_log")" == *"RELAYGATE_RUN_ID=$run_id"* ]]
	[[ "$(<"$launch_log")" == *"RELAYGATE_ATTEMPT_ID="* ]]
	[[ "$(<"$launch_log")" == *"RELAYGATE_RAPID_CROSSCHECK_MODE=on"* ]]
	[[ "$(<"$launch_log")" == *"-i $credential_dir/cred-blue-batch -oBatchMode=yes -oIdentitiesOnly=yes batchuser@blue-host-01 cd /opt/relaygate/work && "*"/opt/blue/run.sh --mode batch"* ]]
	[[ "$(<"$launch_log")" == *"-i $credential_dir/cred-green-batch -oBatchMode=yes -oIdentitiesOnly=yes batchuser@green-host-01 "* ]]
	# 鍵の内容・実装版・ジョブマップ版は起動イベントに現れない
	[[ "$(<"$launch_log")" != *"bats-test-key"* ]]
	[[ "$(<"$launch_log")" != *"blue-2.3.1"* ]]
	[[ "$(<"$launch_log")" != *"v1.4.0"* ]]
}

@test "relaygate_concurrent_run_select_slot_BLUE_MODE=foreground_GREEN_MODE=backgroundの場合_backgroundのgreenをforegroundのblueより先に起動すること" {
	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	[[ "$(sed -n 1p "$launch_log")" == *"RELAYGATE_SLOT=green RELAYGATE_ROLE=background"* ]]
	[[ "$(sed -n 2p "$launch_log")" == *"RELAYGATE_SLOT=blue RELAYGATE_ROLE=foreground"* ]]
}

@test "relaygate_concurrent_run_select_slot_fixed_argsに改行がある場合_JSON配列で保存しSSHへ単一引数として伝播すること" {
	# Arrange
	set_job_field green fixed_args '["--fixed=first\nsecond", "spaced value"]'
	expected_remote_args="$(printf '%q %q' $'--fixed=first\nsecond' 'spaced value')"

	# Act
	run --separate-stderr run_select_slot off foreground off daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	[[ "$(<"$launch_log")" == *"/opt/green/run.sh $expected_remote_args"* ]]
	[ "$(sqlite3 "$db_path" 'SELECT fixed_args FROM slot_execution_specs;' | jq -c .)" = '["--fixed=first\nsecond","spaced value"]' ]
}

@test "relaygate_concurrent_run_select_slot_RAPID_CROSSCHECK_MODEがoffの場合_rapid_crosscheck_requestsへ書き込まずに起動すること" {
	# Act
	run --separate-stderr run_select_slot foreground background off daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	[ "$(count_rows rapid_crosscheck_requests)" = "0" ]
	[[ "$(<"$launch_log")" == *"RELAYGATE_RAPID_CROSSCHECK_MODE=off"* ]]
}

# ---- 起動前監査ゲート ----

@test "relaygate_concurrent_run_select_slot_runner_resultsのINSERTが失敗した場合_execution_specsとslot_execution_specsもrollbackすること" {
	# Arrange
	sqlite3 "$db_path" "CREATE TRIGGER reject_runner_result BEFORE INSERT ON runner_results BEGIN SELECT RAISE(ABORT, 'injected'); END;"

	# Act & Assert
	run --separate-stderr run_select_slot foreground off on daily-settlement
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"boundary=rdb"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ "$(count_rows slot_execution_specs)" = "0" ]
	[ "$(count_rows runner_result_events)" = "0" ]
	[ "$(count_rows audit_logs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_監査イベントを追記した場合_previous_hashが直前のevent_hashに連なりaudit_chain_headsが末尾を指すこと" {
	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	[ "$(count_rows audit_logs)" = "3" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_logs WHERE previous_hash IS NULL AND event_name = "slot_launch_accepted";')" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_logs a JOIN audit_logs p ON p.event_hash = a.previous_hash AND p.run_id = a.run_id;')" = "2" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_logs a WHERE NOT EXISTS (SELECT 1 FROM audit_logs n WHERE n.previous_hash = a.event_hash);')" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_chain_heads h JOIN audit_logs a ON a.event_id = h.head_event_id AND a.event_hash = h.head_hash WHERE h.chain_length = 3 AND NOT EXISTS (SELECT 1 FROM audit_logs n WHERE n.previous_hash = a.event_hash);')" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(DISTINCT event_hash) FROM audit_logs;')" = "3" ]
}

@test "relaygate_concurrent_run_select_slot_起動を受け付けた場合_イベントごとに時刻を取得し記録順に単調増加させ派生カラムと同一値にすること" {
	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	# (a) attempt_started の occurred_at = 同じ試行の accepted_at = updated_at
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM runner_result_events e JOIN runner_results r ON r.run_id = e.run_id AND r.slot_type = e.slot_type AND r.attempt_id = e.attempt_id AND e.occurred_at = r.accepted_at AND r.updated_at = r.accepted_at;')" = "2" ]
	# (c) チェーン先頭の監査イベントの occurred_at = audit_chain_heads.updated_at
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_chain_heads h JOIN audit_logs a ON a.event_id = h.head_event_id AND h.updated_at = a.occurred_at;')" = "1" ]
	# 異なるイベント(blue / green の attempt_started、accepted / attempted)は別の時刻を持ち、記録順(green→blue→accepted→attempted)に単調増加する
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(DISTINCT occurred_at) FROM (SELECT occurred_at FROM runner_result_events UNION ALL SELECT occurred_at FROM audit_logs);')" = "5" ]
	[[ "$(sqlite3 "$db_path" 'SELECT occurred_at FROM runner_result_events WHERE slot_type = "green";')" < "$(sqlite3 "$db_path" 'SELECT occurred_at FROM runner_result_events WHERE slot_type = "blue";')" ]]
	[[ "$(sqlite3 "$db_path" 'SELECT MAX(occurred_at) FROM runner_result_events;')" < "$(sqlite3 "$db_path" 'SELECT occurred_at FROM audit_logs WHERE event_name = "slot_launch_accepted";')" ]]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_logs a JOIN audit_logs p ON p.event_hash = a.previous_hash WHERE NOT (p.occurred_at < a.occurred_at);')" = "0" ]
	[[ "$(sqlite3 "$db_path" 'SELECT accepted_at FROM runner_results LIMIT 1;')" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$ ]]
}

# ---- 補償記録の監査追記失敗(failure_contract.post_launch) ----

@test "relaygate_concurrent_run_select_slot_送出失敗後の監査追記が失敗した場合_補償記録のcommitを保ちoutboxへ退避すること" {
	# Arrange
	export RELAYGATE_TEST_SSH_MODE=fail
	export RELAYGATE_AUDIT_OUTBOX_DIR="$test_dir/outbox"
	sqlite3 "$db_path" "CREATE TRIGGER reject_post_launch BEFORE INSERT ON audit_logs WHEN NEW.event_name = 'slot_launch_failed' BEGIN SELECT RAISE(ABORT, 'injected'); END;"

	# Act
	run --separate-stderr run_select_slot foreground off on daily-settlement

	# Assert
	[ "$status" -eq 1 ]
	[ "$(sqlite3 "$db_path" 'SELECT status FROM runner_results;')" = "FAILED" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM runner_result_events WHERE event_name = "attempt_failed";')" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_logs WHERE event_name = "slot_launch_failed";')" = "0" ]
	[ "$(sqlite3 "$db_path" 'SELECT chain_length FROM audit_chain_heads;')" = "2" ]
	[[ "$stderr" == *"blue実装への起動イベント送出に失敗しました: slot_type=blue attempt_id="*" を FAILED として記録しました"* ]]
	[[ "$stderr" == *"saved to the local outbox"* ]]
	run_id="$(sqlite3 "$db_path" 'SELECT run_id FROM execution_specs;')"
	attempt_id="$(sqlite3 "$db_path" 'SELECT attempt_id FROM runner_results;')"
	outbox_file="$RELAYGATE_AUDIT_OUTBOX_DIR/${run_id}_blue_${attempt_id}_slot_launch_failed.json"
	[ -f "$outbox_file" ]
	[ "$(jq -r '[.event_name, .run_id, .slot, .attempt_id, .actor, .operation, .outcome, .error_code, (.parent_run_id == null), (.final_status == null)] | join("|")' "$outbox_file")" = "slot_launch_failed|$run_id|blue|$attempt_id|ops-tanaka|slot_launch|failed|launch_event_send_failed|true|true" ]
	[ ! -e "$outbox_file.tmp" ]
}

# ---- 入力検証(job_map_contract / credential_resolution / CLI) ----

@test "relaygate_concurrent_run_select_slot_起動対象slotのジョブマップ環境変数が未設定の場合_バリデーションエラーで永続化しないこと" {
	# Act & Assert
	run --separate-stderr env -u RELAYGATE_JOB_MAP_PATH_GREEN PATH="$test_dir/bin:$PATH" RELAYGATE_TEST_LAUNCH_LOG="$launch_log" RELAYGATE_RDB_DSN="sqlite://$db_path" RELAYGATE_JOB_MAP_PATH_BLUE="$job_map_blue" RELAYGATE_CREDENTIAL_DIR="$credential_dir" RELAYGATE_OPERATOR=ops-tanaka BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=on "$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id daily-settlement
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"ジョブマップのパスが未設定です: slot_type=green env=RELAYGATE_JOB_MAP_PATH_GREEN"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_ジョブマップファイルが存在しない場合_バリデーションエラーで永続化しないこと" {
	# Arrange
	rm -f "$job_map_green"

	# Act & Assert
	run --separate-stderr run_select_slot foreground background on daily-settlement
	[ "$status" -eq 2 ]
	[[ "$(strip_test_dir "$stderr")" == *"ジョブマップを読み込めません: slot_type=green path=/etc/relaygate/job-map.green.json reason=not_found"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_ジョブマップがJSONとして解析できない場合_バリデーションエラーで永続化しないこと" {
	# Arrange
	printf '{"job_map_version": "v1.4.0",' >"$job_map_green"

	# Act & Assert
	run --separate-stderr run_select_slot foreground background on daily-settlement
	[ "$status" -eq 2 ]
	[[ "$(strip_test_dir "$stderr")" == *"ジョブマップを読み込めません: slot_type=green path=/etc/relaygate/job-map.green.json reason=invalid_json"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_top_levelのjob_map_versionが欠落している場合_バリデーションエラーになること" {
	# Arrange
	jq 'del(.job_map_version)' "$job_map_blue" >"$job_map_blue.next" && mv "$job_map_blue.next" "$job_map_blue"

	# Act & Assert
	run --separate-stderr run_select_slot foreground background on daily-settlement
	[ "$status" -eq 2 ]
	[[ "$(strip_test_dir "$stderr")" == *"ジョブマップの必須フィールドが欠落しています: slot_type=blue path=/etc/relaygate/job-map.blue.json field=job_map_version"* ]]
}

@test "relaygate_concurrent_run_select_slot_job_entryの必須項目が文字列以外の場合_バリデーションエラーで永続化しないこと" {
	# Arrange
	set_job_field green host '{"unexpected":"object"}'

	# Act & Assert
	run --separate-stderr run_select_slot off background off daily-settlement
	[ "$status" -eq 2 ]
	[[ "$(strip_test_dir "$stderr")" == *"ジョブマップの必須フィールドが欠落しています: slot_type=green path=/etc/relaygate/job-map.green.json field=jobs.daily-settlement.host"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_hang_detect_limit_minutesが整数でない場合_バリデーションエラーで永続化しないこと" {
	# Arrange
	set_job_field green hang_detect_limit_minutes '"15; DROP TABLE execution_specs;"'

	# Act & Assert
	run --separate-stderr run_select_slot off background off daily-settlement
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"field=jobs.daily-settlement.hang_detect_limit_minutes"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_hang_detect_limit_minutesが0の場合_バリデーションエラーになること" {
	# Arrange
	set_job_field green hang_detect_limit_minutes 0

	# Act & Assert
	run --separate-stderr run_select_slot off background off daily-settlement
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"field=jobs.daily-settlement.hang_detect_limit_minutes"* ]]
}

@test "relaygate_concurrent_run_select_slot_fixed_argsが文字列配列以外の場合_バリデーションエラーで永続化しないこと" {
	# Arrange
	set_job_field green fixed_args '["--fixed", 42]'

	# Act & Assert
	run --separate-stderr run_select_slot off background off daily-settlement
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"field=jobs.daily-settlement.fixed_args"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_fixed_argsが省略された場合_空配列として保存すること" {
	# Arrange
	jq 'del(.jobs."daily-settlement".fixed_args)' "$job_map_green" >"$job_map_green.next" && mv "$job_map_green.next" "$job_map_green"

	# Act
	run --separate-stderr run_select_slot off foreground off daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	[ "$(sqlite3 "$db_path" 'SELECT fixed_args FROM slot_execution_specs;')" = "[]" ]
	[[ "$(<"$launch_log")" == *"/opt/green/run.sh"* ]]
}

@test "relaygate_concurrent_run_select_slot_credential_refが文字列でもnullでもない場合_バリデーションエラーで永続化しないこと" {
	# Arrange
	set_job_field green credential_ref 42

	# Act & Assert
	run --separate-stderr run_select_slot off background off daily-settlement
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"field=jobs.daily-settlement.credential_ref"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_credential_refがディレクトリ外を指す書式の場合_バリデーションエラーになること" {
	# Arrange
	set_job_field green credential_ref '"../etc/passwd"'

	# Act & Assert
	run --separate-stderr run_select_slot off background off daily-settlement
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"credential_ref の書式が不正です: slot_type=green"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_credential_refがnullの場合_RELAYGATE_SSH_KEY_PATHの鍵を用いNULLを保存すること" {
	# Arrange
	set_job_field green credential_ref null
	printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nbats-default-key\n-----END OPENSSH PRIVATE KEY-----\n' >"$test_dir/default-key"
	chmod 0600 "$test_dir/default-key"
	export RELAYGATE_SSH_KEY_PATH="$test_dir/default-key"

	# Act
	run --separate-stderr run_select_slot off background off daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	[ "$(sqlite3 "$db_path" 'SELECT credential_ref IS NULL FROM slot_execution_specs;')" = "1" ]
	[[ "$(<"$launch_log")" == *"-i $test_dir/default-key "* ]]
}

@test "relaygate_concurrent_run_select_slot_credential_refがnullでRELAYGATE_SSH_KEY_PATHも未設定の場合_業務エラーで永続化しないこと" {
	# Arrange
	set_job_field green credential_ref null

	# Act & Assert
	run --separate-stderr run_select_slot off background off daily-settlement
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"SSH認証情報を解決できません: credential_ref=null かつ RELAYGATE_SSH_KEY_PATH 未設定"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_秘密鍵のパーミッションが0600でない場合_業務エラーで永続化しないこと" {
	# Arrange
	chmod 0644 "$credential_dir/cred-green-batch"

	# Act & Assert
	run --separate-stderr run_select_slot foreground background on daily-settlement
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"SSH認証情報を解決できません: credential_ref=cred-green-batch"* ]]
	[[ "$stderr" != *"$credential_dir"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_RELAYGATE_CREDENTIAL_DIRが未設定の場合_バリデーションエラーで永続化しないこと" {
	# Act & Assert
	run --separate-stderr env PATH="$test_dir/bin:$PATH" RELAYGATE_TEST_LAUNCH_LOG="$launch_log" RELAYGATE_RDB_DSN="sqlite://$db_path" RELAYGATE_JOB_MAP_PATH_BLUE="$job_map_blue" RELAYGATE_JOB_MAP_PATH_GREEN="$job_map_green" RELAYGATE_OPERATOR=ops-tanaka BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=on "$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id daily-settlement
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"RELAYGATE_CREDENTIAL_DIR is required"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_複数のfeature_flag違反がある場合_全件を標準エラーへ出して検証エラーにすること" {
	# Act & Assert
	run --separate-stderr run_select_slot foreground foreground maybe daily-settlement
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"BLUE_MODEとGREEN_MODEを同時にforegroundにすることはできません"* ]]
	[[ "$stderr" == *"RAPID_CROSSCHECK_MODE must be on or off"* ]]
	[[ "$stderr" == *"Next action"* ]]
}

@test "relaygate_concurrent_run_select_slot_不正なfeature_flagの場合_検証エラーで永続化しないこと" {
	# Act & Assert
	run --separate-stderr run_select_slot invalid background on daily-settlement
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"BLUE_MODE must be off, background, or foreground"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_JOB_IDを省略した場合_検証エラーで終了すること" {
	# Act & Assert
	run --separate-stderr env PATH="$test_dir/bin:$PATH" RELAYGATE_RDB_DSN="sqlite://$db_path" RELAYGATE_JOB_MAP_PATH_BLUE="$job_map_blue" RELAYGATE_CREDENTIAL_DIR="$credential_dir" RELAYGATE_OPERATOR=ops-tanaka BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=on "$project_root/facade/bin/relaygate" concurrent-run select-slot
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"JOB_ID is required"* ]]
}

@test "relaygate_concurrent_run_select_slot_RDB_DSNが未対応の種別の場合_業務エラーで起動しないこと" {
	# Act & Assert
	run --separate-stderr env PATH="$test_dir/bin:$PATH" RELAYGATE_TEST_LAUNCH_LOG="$launch_log" RELAYGATE_RDB_DSN="mysql://db.example.test/relaygate" RELAYGATE_JOB_MAP_PATH_BLUE="$job_map_blue" RELAYGATE_CREDENTIAL_DIR="$credential_dir" RELAYGATE_OPERATOR=ops-tanaka BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=on "$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id daily-settlement
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"boundary=rdb"* ]]
	[ ! -e "$launch_log" ]
}

# ---- 純粋関数(canonical_form / SQL 生成 / 時刻) ----

@test "audit_event_canonical_契約のexampleと同じ入力の場合_同じ正規化文字列を返すこと" {
	# Arrange
	source_facade_libraries
	run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57"
	operator="ops-tanaka"

	# Act
	result="$(audit_event_canonical "0d3a6c1e-8b2f-4c7a-9e51-2f6b8d4a1c30" slot_launch_accepted - - "2026-08-18T00:00:00.000000Z" accepted "" "")"

	# Assert
	expected='0d3a6c1e-8b2f-4c7a-9e51-2f6b8d4a1c30|slot_launch_accepted|1.0|3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57||-|-|2026-08-18T00:00:00.000000Z|ops-tanaka|slot_launch|accepted||'
	[ "$result" = "$expected" ]
}

@test "audit_event_canonical_値にバックスラッシュと区切り文字を含む場合_この順でエスケープすること" {
	# Arrange
	source_facade_libraries
	run_id="run-1"
	operator='ops\|tanaka'

	# Act
	result="$(audit_event_canonical "ev-1" slot_launch_failed green "att|1" "2026-08-18T00:00:00.000000Z" failed "" launch_event_send_failed)"

	# Assert
	expected='ev-1|slot_launch_failed|1.0|run-1||green|att\|1|2026-08-18T00:00:00.000000Z|ops\\\|tanaka|slot_launch|failed||launch_event_send_failed'
	[ "$result" = "$expected" ]
}

@test "audit_event_hash_run内の最初のイベントの場合_末尾に空のprevious_hashを連結したSHA-256の16進小文字64桁を返すこと" {
	# Arrange
	source_facade_libraries
	canonical="a|b"
	expected="$(printf 'a|b|' | perl -MDigest::SHA=sha256_hex -e 'local $/; print sha256_hex(<STDIN>)')"

	# Act
	result="$(audit_event_hash "$canonical" "")"

	# Assert
	[ "$result" = "$expected" ]
	[[ "$result" =~ ^[0-9a-f]{64}$ ]]
}

@test "audit_event_hash_DBに保存した監査イベントを再計算した場合_保存済みevent_hashと一致すること" {
	# Arrange
	export RELAYGATE_TEST_SSH_MODE=fail
	run --separate-stderr run_select_slot off foreground off daily-settlement
	[ "$status" -eq 1 ]
	source_facade_libraries
	run_id="$(sqlite3 "$db_path" 'SELECT run_id FROM execution_specs;')"
	operator="ops-tanaka"
	mismatches=0

	# Act
	# 区切りは空白類でない文字にする(IFS が空白類だと空フィールドが詰められる)
	while IFS='~' read -r event_id event_name slot attempt_id occurred_at outcome error_code previous_hash stored_hash; do
		recomputed_hash="$(audit_event_hash "$(audit_event_canonical "$event_id" "$event_name" "$slot" "$attempt_id" "$occurred_at" "$outcome" "" "$error_code")" "$previous_hash")"
		[ "$recomputed_hash" = "$stored_hash" ] || mismatches=$((mismatches + 1))
	done < <(sqlite3 -separator '~' "$db_path" 'SELECT event_id, event_name, slot, attempt_id, occurred_at, outcome, COALESCE(error_code, ""), COALESCE(previous_hash, ""), event_hash FROM audit_logs;')

	# Assert
	[ "$(count_rows audit_logs)" = "3" ]
	[ "$mismatches" = "0" ]
}

@test "audit_chain_lock_sql_postgresqlの場合_audit_chain_headsのrun_id行をFOR_UPDATEで排他ロックするSELECTを返すこと" {
	# Arrange
	source_facade_libraries

	# Act
	result="$(audit_chain_lock_sql postgresql "'run-1'")"

	# Assert
	[ "$result" = "SELECT head_hash FROM audit_chain_heads WHERE run_id = 'run-1' FOR UPDATE;" ]
}

@test "audit_chain_lock_sql_sqliteの場合_FOR_UPDATEを付けずにBEGIN_IMMEDIATEの書込みロックで直列化すること" {
	# Arrange
	source_facade_libraries

	# Act
	lock_sql="$(audit_chain_lock_sql sqlite "'run-1'")"
	begin_sql="$(transaction_begin_sql sqlite)"

	# Assert
	[ "$lock_sql" = "SELECT head_hash FROM audit_chain_heads WHERE run_id = 'run-1';" ]
	[ "$begin_sql" = "BEGIN IMMEDIATE;" ]
}

@test "transaction_begin_sql_未知の接続種別の場合_失敗を返すこと" {
	# Arrange
	source_facade_libraries

	# Act & Assert
	! transaction_begin_sql oracle
	! audit_chain_lock_sql oracle "'run-1'"
}

@test "audit_chain_head_sql_run内の最初の監査イベントの場合_audit_chain_headsへINSERTする文を返すこと" {
	# Arrange
	source_facade_libraries

	# Act
	result="$(audit_chain_head_sql "'run-1'" "'ev-1'" "'hash-1'" 1 "'2026-08-22T00:00:00.000001Z'")"

	# Assert
	[ "$result" = "INSERT INTO audit_chain_heads (run_id,head_event_id,head_hash,chain_length,updated_at) VALUES ('run-1','ev-1','hash-1',1,'2026-08-22T00:00:00.000001Z');" ]
}

@test "audit_chain_head_sql_2件目以降の監査イベントの場合_同じrun_id行をUPDATEする文を返すこと" {
	# Arrange
	source_facade_libraries

	# Act
	result="$(audit_chain_head_sql "'run-1'" "'ev-2'" "'hash-2'" 2 "'2026-08-22T00:00:00.000001Z'")"

	# Assert
	[ "$result" = "UPDATE audit_chain_heads SET head_event_id = 'ev-2', head_hash = 'hash-2', chain_length = 2, updated_at = '2026-08-22T00:00:00.000001Z' WHERE run_id = 'run-1';" ]
}

@test "build_audit_append_transaction_sql_postgresqlの場合_run_id行をFOR_UPDATEでロックしhead_hash一致を条件にINSERTとUPDATEを行うこと" {
	# Arrange
	source_facade_libraries
	run_id="run-1"
	operator="ops-tanaka"

	# Act
	result="$(build_audit_append_transaction_sql postgresql ev-9 slot_launch_failed green att-1 "2026-08-22T00:00:00.000001Z" failed launch_event_send_failed prev-hash new-hash)"

	# Assert
	[[ "$result" == "BEGIN; SELECT head_hash FROM audit_chain_heads WHERE run_id = 'run-1' FOR UPDATE; INSERT INTO audit_logs (event_id,event_name,schema_version,run_id,parent_run_id,slot,attempt_id,occurred_at,actor,operation,outcome,final_status,error_code,previous_hash,event_hash) SELECT 'ev-9','slot_launch_failed','1.0','run-1',NULL,'green','att-1','2026-08-22T00:00:00.000001Z','ops-tanaka','slot_launch','failed',NULL,'launch_event_send_failed','prev-hash','new-hash' WHERE EXISTS (SELECT 1 FROM audit_chain_heads WHERE run_id = 'run-1' AND head_hash = 'prev-hash'); UPDATE audit_chain_heads SET head_event_id = 'ev-9', head_hash = 'new-hash', chain_length = chain_length + 1, updated_at = '2026-08-22T00:00:00.000001Z' WHERE run_id = 'run-1' AND head_hash = 'prev-hash'; COMMIT;" ]]
}

@test "resolve_hang_detect_limit_minutes_backgroundが無い場合_起動対象の唯一のslotの値を採用すること" {
	# Arrange
	source_facade_libraries
	selected_slots=(blue)
	slot_role[blue]=foreground
	slot_hang_detect_limit_minutes[blue]=30

	# Act
	resolve_hang_detect_limit_minutes

	# Assert
	[ "$hang_detect_limit_minutes" = "30" ]
}

@test "clock_now_utc_呼び出した場合_UTCのISO8601マイクロ秒精度で返すこと" {
	# Arrange
	source_facade_libraries
	source "$project_root/facade/src/id_gateway.sh"
	deadline_run() { "$@"; }

	# Act
	result="$(clock_now_utc)"

	# Assert
	[[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$ ]]
}

@test "next_event_time_時計が同じ値を返し続ける場合_直前より後の時刻が得られるまで取り直すこと" {
	# Arrange
	source_facade_libraries
	source "$project_root/facade/src/id_gateway.sh"
	# 時計の呼び出し回数はサブシェル越しに数えるためファイルで持つ
	clock_calls_path="$test_dir/clock-calls"
	printf '0' >"$clock_calls_path"
	clock_now_utc() {
		local calls
		calls=$(($(<"$clock_calls_path") + 1))
		printf '%s' "$calls" >"$clock_calls_path"
		if ((calls < 3)); then printf '2026-08-22T00:00:00.000001Z'; else printf '2026-08-22T00:00:00.000002Z'; fi
	}
	last_event_time="2026-08-22T00:00:00.000001Z"

	# Act
	next_event_time

	# Assert
	[ "$event_time" = "2026-08-22T00:00:00.000002Z" ]
	[ "$(<"$clock_calls_path")" = "3" ]
}
