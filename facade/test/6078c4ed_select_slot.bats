#!/usr/bin/env bats
# UC 6078c4ed(select-and-launch-slots-by-feature-flags)の TDD 単体テスト(④)。
# spec 20260819_114307 還流前のテストを S4 attempt 5 で新仕様(execution_specs / slot_execution_specs の分離、
# runner_results STARTING + runner_result_events、起動前監査ゲート、RELAYGATE_OPERATOR 必須)へ整理したもの。
# deadline / プロセスグループ掃除 / 入力検証のテスト意図(CTP-009 10 秒以内)は旧テストから引き継ぐ。
# スキーマは契約定数(packages/contracts/relay-gate-db/schema-constants.sh)の列と rdb-schema.yaml の PK / UNIQUE に
# 合わせた SQLite(限定検証境界: issues/20260817T230000Z・issues/20260821T220045Z §1)。

setup() {
	bats_require_minimum_version 1.5.0
	project_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	test_dir="$(mktemp -d)"
	db_path="$test_dir/relaygate.db"
	job_map_path="$test_dir/job-map.json"
	launch_log="$test_dir/launch.log"
	system_sqlite="$(command -v sqlite3)"
	system_jq="$(command -v jq)"
	mkdir -p "$test_dir/bin"

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
fail-green) case "$*" in *RELAYGATE_SLOT=green*) exit 255 ;; esac ;;
*) exit 64 ;;
esac
EOF
	chmod +x "$test_dir/bin/ssh"

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
  job_id TEXT NOT NULL, additional_args TEXT, job_map_version TEXT NOT NULL,
  hang_detect_limit_minutes INTEGER NOT NULL
);
CREATE TABLE slot_execution_specs (
  run_id TEXT NOT NULL REFERENCES execution_specs(run_id), slot_type TEXT NOT NULL,
  host TEXT NOT NULL, exec_user TEXT NOT NULL, script_path TEXT NOT NULL, work_dir TEXT NOT NULL,
  fixed_args TEXT, impl_version TEXT NOT NULL, credential_ref TEXT,
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
  stderr_path TEXT, exit_code INTEGER, status TEXT NOT NULL, updated_at TEXT,
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

	# ジョブマップ fixture(run 共通項目 + slot 別項目。形式は job_map_gateway.sh 冒頭コメントの検証境界形式)
	cat >"$job_map_path" <<'JSON'
{
  "version": "map-v1",
  "jobs": {
    "JOB-2026-0817-001": {
      "hang_detect_limit_minutes": 15,
      "slots": {
        "blue": {
          "host": "runner.example.test", "exec_user": "relay", "script_path": "/opt/jobs/blue.sh",
          "work_dir": "/var/tmp/relay", "fixed_args": ["--fixed"], "impl_version": "blue-v1",
          "credential_ref": "ssh-key-reference"
        },
        "green": {
          "host": "runner.example.test", "exec_user": "relay", "script_path": "/opt/jobs/example.sh",
          "work_dir": "/var/tmp/relay", "fixed_args": ["--fixed"], "impl_version": "green-v1",
          "credential_ref": "ssh-key-reference"
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

# set_job_field はジョブマップの run 共通項目を書き換える。
set_job_field() {
	local field="$1" value="$2"
	jq --argjson value "$value" ".jobs[\"JOB-2026-0817-001\"].$field = \$value" "$job_map_path" >"$job_map_path.next"
	mv "$job_map_path.next" "$job_map_path"
}

# set_slot_field はジョブマップの slot 別項目を書き換える。
set_slot_field() {
	local slot="$1" field="$2" value="$3"
	jq --argjson value "$value" ".jobs[\"JOB-2026-0817-001\"].slots.$slot.$field = \$value" "$job_map_path" >"$job_map_path.next"
	mv "$job_map_path.next" "$job_map_path"
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
		RELAYGATE_JOB_MAP_PATH="$job_map_path" \
		RELAYGATE_OPERATOR="ops-tanaka" \
		BLUE_MODE="$blue_mode" GREEN_MODE="$green_mode" RAPID_CROSSCHECK_MODE="$rapid_mode" \
		"$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id "$job_id" "$@"
}

count_rows() {
	sqlite3 "$db_path" "SELECT COUNT(*) FROM $1;"
}

# source_facade_libraries は純粋関数(SQL 生成・ハッシュ)を直接検証するために層別ライブラリを読み込む。
source_facade_libraries() {
	source "$project_root/packages/contracts/relay-gate-db/schema-constants.sh"
	source "$project_root/facade/src/presentation.sh"
	source "$project_root/facade/src/domain.sh"
	source "$project_root/facade/src/rdb_gateway.sh"
}

@test "relaygate_concurrent_run_select_slot_初期化filesystemが遅延した場合_CLI全体deadline内に打ち切ること" {
	# Arrange
	cat >"$test_dir/bin/dirname" <<'EOF'
#!/usr/bin/env bash
sleep 20
exec /usr/bin/dirname "$@"
EOF
	chmod +x "$test_dir/bin/dirname"
	started_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Act
	run --separate-stderr run_select_slot foreground off on JOB-2026-0817-001
	elapsed_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Assert
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"initialization"* ]]
	awk -v started="$started_seconds" -v ended="$elapsed_seconds" 'BEGIN { exit !(ended - started < 10) }'
}

@test "relaygate_concurrent_run_select_slot_job_map可読性確認が遅延した場合_CLI全体deadline内に打ち切ること" {
	# Arrange
	cat >"$test_dir/bin/test" <<'EOF'
#!/usr/bin/env bash
sleep 20
exec /usr/bin/test "$@"
EOF
	chmod +x "$test_dir/bin/test"
	started_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Act
	run --separate-stderr run_select_slot foreground off on JOB-2026-0817-001
	elapsed_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Assert
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"boundary=job_map, field=path, category=unavailable"* ]]
	awk -v started="$started_seconds" -v ended="$elapsed_seconds" 'BEGIN { exit !(ended - started < 10) }'
}

@test "relaygate_concurrent_run_select_slot_SSHが子プロセスを生成した場合_deadline後に子PIDを残さないこと" {
	# Arrange
	export RELAYGATE_TEST_SSH_MODE=spawn-child-hang
	export RELAYGATE_TEST_CHILD_PID_PATH="$test_dir/child.pid"
	started_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Act
	run --separate-stderr run_select_slot foreground off on JOB-2026-0817-001
	elapsed_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Assert
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"reason=timeout"* ]]
	awk -v started="$started_seconds" -v ended="$elapsed_seconds" 'BEGIN { exit !(ended - started < 10) }'
	child_pid="$(<"$RELAYGATE_TEST_CHILD_PID_PATH")"
	! kill -0 "$child_pid" 2>/dev/null
}

@test "relaygate_concurrent_run_select_slot_SSHの子プロセスがTERMを無視する場合_KILLでPIDを残さないこと" {
	# Arrange
	export RELAYGATE_TEST_SSH_MODE=spawn-term-ignoring-child
	export RELAYGATE_TEST_CHILD_PID_PATH="$test_dir/child.pid"

	# Act
	run --separate-stderr run_select_slot foreground off on JOB-2026-0817-001

	# Assert
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"reason=timeout"* ]]
	child_pid="$(<"$RELAYGATE_TEST_CHILD_PID_PATH")"
	! kill -0 "$child_pid" 2>/dev/null
}

@test "relaygate_concurrent_run_select_slot_fixed_args抽出が遅延した場合_SSH直前の残余時間でdeadlineを超えないこと" {
	# Arrange
	cat >"$test_dir/bin/jq" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *'@sh'* ]]; then sleep 5; fi
exec "$RELAYGATE_TEST_SYSTEM_JQ" "$@"
EOF
	chmod +x "$test_dir/bin/jq"
	export RELAYGATE_TEST_SSH_MODE=hang
	started_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Act
	run --separate-stderr run_select_slot off foreground off JOB-2026-0817-001
	elapsed_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Assert
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"reason=timeout"* ]]
	awk -v started="$started_seconds" -v ended="$elapsed_seconds" 'BEGIN { exit !(ended - started < 10) }'
}

@test "relaygate_concurrent_run_select_slot_排他的foreground設定の場合_run共通とslot別の実行設定とSTARTING記録を保存して両slotを起動すること" {
	# Act
	run --separate-stderr run_select_slot foreground background on JOB-2026-0817-001

	# Assert
	[ "$status" -eq 0 ]
	run_id="$(sqlite3 "$db_path" 'SELECT run_id FROM execution_specs;')"
	[ "$(sqlite3 "$db_path" 'SELECT job_id || "|" || job_map_version || "|" || hang_detect_limit_minutes || "|" || (additional_args IS NULL) || "|" || (parent_run_id IS NULL) FROM execution_specs;')" = "JOB-2026-0817-001|map-v1|15|1|1" ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || host || ":" || exec_user || ":" || script_path || ":" || work_dir || ":" || fixed_args || ":" || impl_version || ":" || credential_ref FROM slot_execution_specs ORDER BY slot_type;')" = $'blue:runner.example.test:relay:/opt/jobs/blue.sh:/var/tmp/relay:--fixed:blue-v1:ssh-key-reference\ngreen:runner.example.test:relay:/opt/jobs/example.sh:/var/tmp/relay:--fixed:green-v1:ssh-key-reference' ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || role_type || ":" || attempt_no || ":" || status FROM runner_results ORDER BY slot_type;')" = $'blue:foreground:1:STARTING\ngreen:background:1:STARTING' ]
	[ "$(printf '%s\n' "$output" | grep -c "^run_id=$run_id slot_type=.* role=.* attempt_id=.* status=STARTING$")" = "2" ]
	[ "$(wc -l <"$launch_log" | tr -d ' ')" = "2" ]
	[[ "$(<"$launch_log")" == *"RELAYGATE_RUN_ID=$run_id"* ]]
	[[ "$(<"$launch_log")" == *"RELAYGATE_ATTEMPT_ID="* ]]
	[[ "$(<"$launch_log")" == *"RELAYGATE_RAPID_CROSSCHECK_MODE=on"* ]]
	[[ "$(<"$launch_log")" == *"-n -o BatchMode=yes -- relay@runner.example.test"* ]]
	[[ "$(<"$launch_log")" != *"ssh-key-reference"* ]]
}

@test "relaygate_concurrent_run_select_slot_BLUE_MODE=foreground_GREEN_MODE=backgroundの場合_backgroundのgreenをforegroundのblueより先に起動すること" {
	# Act
	run --separate-stderr run_select_slot foreground background on JOB-2026-0817-001

	# Assert
	[ "$status" -eq 0 ]
	[[ "$(sed -n 1p "$launch_log")" == *"RELAYGATE_SLOT=green RELAYGATE_ROLE=background"* ]]
	[[ "$(sed -n 2p "$launch_log")" == *"RELAYGATE_SLOT=blue RELAYGATE_ROLE=foreground"* ]]
}

@test "relaygate_concurrent_run_select_slot_BLUE_MODE=off_GREEN_MODE=foregroundの場合_greenの1slotだけを確定して起動すること" {
	# Act
	run --separate-stderr run_select_slot off foreground off JOB-2026-0817-001

	# Assert
	[ "$status" -eq 0 ]
	[ "$(count_rows execution_specs)" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type FROM slot_execution_specs;')" = "green" ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || role_type || ":" || status FROM runner_results;')" = "green:foreground:STARTING" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_logs WHERE event_name = "slot_launch_attempted";')" = "1" ]
	[ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "1" ]
	[[ "$output" == *"slot_type=green role=foreground"* ]]
}

@test "relaygate_concurrent_run_select_slot_fixed_argsに改行がある場合_SSHへ単一引数として伝播すること" {
	# Arrange
	set_slot_field green fixed_args '["--fixed=first\nsecond", "spaced value"]'
	expected_fixed_args="$(printf '%q %q' $'--fixed=first\nsecond' 'spaced value')"

	# Act
	run --separate-stderr run_select_slot off foreground off JOB-2026-0817-001

	# Assert
	[ "$status" -eq 0 ]
	[[ "$(<"$launch_log")" == *"$expected_fixed_args"* ]]
	[ "$(sqlite3 "$db_path" 'SELECT fixed_args FROM slot_execution_specs;')" = "$expected_fixed_args" ]
}

@test "relaygate_concurrent_run_select_slot_起動トランザクションのRDB書込みが遅延した場合_終了コード124で打ち切り永続化も起動もしないこと" {
	# Arrange
	export RELAYGATE_TEST_SQLITE_DELAY_SECONDS=20
	started_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Act
	run --separate-stderr run_select_slot foreground off on JOB-2026-0817-001
	elapsed_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Assert
	[ "$status" -eq 124 ]
	[[ "$stderr" == *"boundary=rdb"* ]]
	[[ "$stderr" == *"reason=timeout"* ]]
	awk -v started="$started_seconds" -v ended="$elapsed_seconds" 'BEGIN { exit !(ended - started < 10) }'
	[ "$(count_rows execution_specs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_両slotが遅延した場合_CLI全体deadline内に2回目を打ち切ること" {
	# Arrange
	export RELAYGATE_TEST_SSH_MODE=delayed-success
	export RELAYGATE_TEST_SSH_DELAY_SECONDS=4
	started_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Act
	run --separate-stderr run_select_slot background background on JOB-2026-0817-001
	elapsed_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Assert
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Failed to start green slot"* ]]
	[[ "$stderr" == *"reason=timeout"* ]]
	awk -v started="$started_seconds" -v ended="$elapsed_seconds" 'BEGIN { exit !(ended - started < 10) }'
	[ "$(wc -l <"$launch_log" | tr -d ' ')" = "2" ]
}

@test "relaygate_concurrent_run_select_slot_runner_resultsのINSERTが失敗した場合_execution_specsとslot_execution_specsもrollbackすること" {
	# Arrange
	sqlite3 "$db_path" "CREATE TRIGGER reject_runner_result BEFORE INSERT ON runner_results BEGIN SELECT RAISE(ABORT, 'injected'); END;"

	# Act & Assert
	run --separate-stderr run_select_slot foreground off on JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"boundary=rdb"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ "$(count_rows slot_execution_specs)" = "0" ]
	[ "$(count_rows runner_result_events)" = "0" ]
	[ "$(count_rows audit_logs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_slot別必須項目が文字列以外の場合_業務エラーで永続化しないこと" {
	# Arrange
	set_slot_field green host '{"unexpected":"object"}'

	# Act & Assert
	run --separate-stderr run_select_slot off background off JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"JOB_IDに対応するジョブマップが見つかりません"* ]]
	[[ "$stderr" == *"boundary=job_map, field=slots.green, category=invalid_type"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_選択slotがジョブマップに無い場合_業務エラーで永続化しないこと" {
	# Arrange
	set_job_field slots '{"blue": {"host": "runner.example.test", "exec_user": "relay", "script_path": "/opt/jobs/blue.sh", "work_dir": "/var/tmp/relay", "fixed_args": [], "impl_version": "blue-v1", "credential_ref": null}}'

	# Act & Assert
	run --separate-stderr run_select_slot foreground background on JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"boundary=job_map, field=slots.green, category=not_found"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_credential_refが文字列でもnullでもない場合_業務エラーで永続化しないこと" {
	# Arrange
	set_slot_field green credential_ref 42

	# Act & Assert
	run --separate-stderr run_select_slot off background off JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_追加引数がある場合_additional_argsを固定引数と分けて保存し固定引数の後ろに連結して起動すること" {
	# Act
	run --separate-stderr run_select_slot off foreground off JOB-2026-0817-001 -- --date 2026-08-17

	# Assert
	[ "$status" -eq 0 ]
	[ "$(sqlite3 "$db_path" 'SELECT additional_args FROM execution_specs;')" = '--date 2026-08-17' ]
	[ "$(sqlite3 "$db_path" 'SELECT fixed_args FROM slot_execution_specs WHERE slot_type = "green";')" = '--fixed' ]
	[[ "$(<"$launch_log")" == *"/opt/jobs/example.sh --fixed --date 2026-08-17"* ]]
}

@test "relaygate_concurrent_run_select_slot_両slotがforegroundの場合_検証エラーで永続化も起動もしないこと" {
	# Act & Assert
	run --separate-stderr run_select_slot foreground foreground on JOB-2026-0817-001
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"BLUE_MODEとGREEN_MODEを同時にforegroundにすることはできません"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ "$(count_rows audit_logs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_複数のfeature_flag違反がある場合_全件を標準エラーへ出して検証エラーにすること" {
	# Act & Assert
	run --separate-stderr run_select_slot foreground foreground maybe JOB-2026-0817-001
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"BLUE_MODEとGREEN_MODEを同時にforegroundにすることはできません"* ]]
	[[ "$stderr" == *"RAPID_CROSSCHECK_MODE must be on or off"* ]]
	[[ "$stderr" == *"Next action"* ]]
}

@test "relaygate_concurrent_run_select_slot_JOB_IDを省略した場合_検証エラーで終了すること" {
	# Act & Assert
	run --separate-stderr env PATH="$test_dir/bin:$PATH" RELAYGATE_RDB_DSN="sqlite://$db_path" RELAYGATE_JOB_MAP_PATH="$job_map_path" RELAYGATE_OPERATOR=ops-tanaka BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=on "$project_root/facade/bin/relaygate" concurrent-run select-slot
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"JOB_ID is required"* ]]
}

@test "relaygate_concurrent_run_select_slot_ジョブマップにJOB_IDがない場合_業務エラーで永続化しないこと" {
	# Act & Assert
	run --separate-stderr run_select_slot foreground background on JOB-UNKNOWN-999
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"JOB_IDに対応するジョブマップが見つかりません: JOB-UNKNOWN-999"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_RDB_DSNがsqlite以外の場合_業務エラーで起動しないこと" {
	# Act & Assert
	run --separate-stderr env PATH="$test_dir/bin:$PATH" RELAYGATE_TEST_LAUNCH_LOG="$launch_log" RELAYGATE_RDB_DSN="mysql://db.example.test/relaygate" RELAYGATE_JOB_MAP_PATH="$job_map_path" RELAYGATE_OPERATOR=ops-tanaka BLUE_MODE=foreground GREEN_MODE=off RAPID_CROSSCHECK_MODE=on "$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"boundary=rdb"* ]]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_SSH起動失敗の場合_foreground結果をFAILEDへ補償しattempt_failed履歴を追記して診断情報を返すこと" {
	# Arrange
	export RELAYGATE_TEST_SSH_MODE=fail

	# Act & Assert
	run --separate-stderr run_select_slot foreground off on JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Failed to start blue slot"* ]]
	[[ "$stderr" == *"boundary=ssh"* ]]
	[[ "$stderr" == *"run_id="* ]]
	[ "$(sqlite3 "$db_path" 'SELECT status || ":" || exit_code || ":" || (updated_at IS NOT NULL) FROM runner_results;')" = "FAILED:255:1" ]
	[ "$(sqlite3 "$db_path" 'SELECT event_name || ":" || status || ":" || IFNULL(exit_code, "null") FROM runner_result_events ORDER BY occurred_at, event_name;')" = $'attempt_started:STARTING:null\nattempt_failed:FAILED:255' ]
	[[ "$output" == *"slot_type=blue role=foreground"*"status=FAILED"* ]]
}

@test "relaygate_concurrent_run_select_slot_SSHが応答しない場合_10秒以内に推測でFAILEDにせずUNKNOWNへ補償すること" {
	# Arrange
	export RELAYGATE_TEST_SSH_MODE=hang
	export RELAYGATE_SSH_TIMEOUT_SECONDS=8
	started_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Act
	run --separate-stderr run_select_slot foreground off on JOB-2026-0817-001
	elapsed_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Assert
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"reason=timeout"* ]]
	awk -v started="$started_seconds" -v ended="$elapsed_seconds" 'BEGIN { exit !(ended - started < 10) }'
	[ "$(sqlite3 "$db_path" 'SELECT status || ":" || (exit_code IS NULL) FROM runner_results;')" = "UNKNOWN:1" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM runner_result_events WHERE event_name = "attempt_unknown" AND status = "UNKNOWN";')" = "1" ]
}

@test "relaygate_concurrent_run_select_slot_先行するbackground_slotのSSH起動が失敗した場合_失敗slotを記録したうえで残りのslotも起動すること" {
	# Arrange
	export RELAYGATE_TEST_SSH_MODE=fail-green

	# Act & Assert
	run --separate-stderr run_select_slot foreground background on JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Failed to start green slot"* ]]
	[ "$(sqlite3 "$db_path" "SELECT slot_type || ':' || role_type || ':' || status FROM runner_results ORDER BY slot_type;")" = $'blue:foreground:STARTING\ngreen:background:FAILED' ]
	[ "$(wc -l <"$launch_log" | tr -d ' ')" = "2" ]
}

@test "relaygate_concurrent_run_select_slot_不正なハング検知しきい値の場合_業務エラーで永続化しないこと" {
	# Arrange
	set_job_field hang_detect_limit_minutes '"15; DROP TABLE execution_specs;"'

	# Act & Assert
	run --separate-stderr run_select_slot off background off JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"JOB_IDに対応するジョブマップが見つかりません"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_fixed_argsが文字列配列以外の場合_業務エラーで永続化しないこと" {
	# Arrange
	set_slot_field green fixed_args '["--fixed", 42]'

	# Act & Assert
	run --separate-stderr run_select_slot off background off JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"JOB_IDに対応するジョブマップが見つかりません"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_credential_refが欠落した場合_slot_execution_specsにNULLを保存すること" {
	# Arrange
	set_slot_field green credential_ref null

	# Act
	run --separate-stderr run_select_slot off background off JOB-2026-0817-001

	# Assert
	[ "$status" -eq 0 ]
	[ "$(sqlite3 "$db_path" 'SELECT credential_ref IS NULL FROM slot_execution_specs;')" = "1" ]
}

@test "relaygate_concurrent_run_select_slot_不正なfeature_flagの場合_検証エラーで永続化しないこと" {
	# Act & Assert
	run --separate-stderr run_select_slot invalid background on JOB-2026-0817-001
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"BLUE_MODE must be off, background, or foreground"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_RAPID_CROSSCHECK_MODEがoffの場合_rapid_crosscheck_requestsへ書き込まずに起動すること" {
	# Act
	run --separate-stderr run_select_slot foreground background off JOB-2026-0817-001

	# Assert
	[ "$status" -eq 0 ]
	[ "$(count_rows rapid_crosscheck_requests)" = "0" ]
	[[ "$(<"$launch_log")" == *"RELAYGATE_RAPID_CROSSCHECK_MODE=off"* ]]
}

@test "relaygate_concurrent_run_select_slot_RELAYGATE_ID_GENERATORが指定された場合_固定のrun_idとattempt_idで実行設定を確定すること" {
	# Arrange
	cat >"$test_dir/bin/fixed-ids" <<'EOF'
#!/usr/bin/env bash
case "$1" in
run_id) printf '3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57' ;;
attempt_id) printf 'att-%s-0001' "$2" ;;
*) uuidgen | tr '[:upper:]' '[:lower:]' ;;
esac
EOF
	chmod +x "$test_dir/bin/fixed-ids"
	export RELAYGATE_ID_GENERATOR="$test_dir/bin/fixed-ids"

	# Act
	run --separate-stderr run_select_slot foreground background on JOB-2026-0817-001

	# Assert
	[ "$status" -eq 0 ]
	[ "$(sqlite3 "$db_path" 'SELECT run_id FROM execution_specs;')" = "3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57" ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || attempt_id FROM runner_results ORDER BY slot_type;')" = $'blue:att-blue-0001\ngreen:att-green-0001' ]
	[[ "$output" == *"run_id=3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57 slot_type=green role=background attempt_id=att-green-0001 status=STARTING"* ]]
}

@test "relaygate_concurrent_run_select_slot_監査イベントを追記した場合_previous_hashが直前のevent_hashに連なりaudit_chain_headsが末尾を指すこと" {
	# Act
	run --separate-stderr run_select_slot foreground background on JOB-2026-0817-001

	# Assert
	[ "$status" -eq 0 ]
	[ "$(count_rows audit_logs)" = "3" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_logs WHERE previous_hash IS NULL AND event_name = "slot_launch_accepted";')" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_logs a JOIN audit_logs p ON p.event_hash = a.previous_hash AND p.run_id = a.run_id;')" = "2" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_logs a WHERE NOT EXISTS (SELECT 1 FROM audit_logs n WHERE n.previous_hash = a.event_hash);')" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_chain_heads h JOIN audit_logs a ON a.event_id = h.head_event_id AND a.event_hash = h.head_hash WHERE h.chain_length = 3 AND NOT EXISTS (SELECT 1 FROM audit_logs n WHERE n.previous_hash = a.event_hash);')" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(DISTINCT event_hash) FROM audit_logs;')" = "3" ]
}

@test "audit_event_hash_DBに保存した先頭監査イベントを再計算した場合_保存済みevent_hashと一致すること" {
	# Arrange
	run --separate-stderr run_select_slot off foreground off JOB-2026-0817-001
	[ "$status" -eq 0 ]
	source_facade_libraries
	run_id="$(sqlite3 "$db_path" 'SELECT run_id FROM execution_specs;')"
	operator="ops-tanaka"
	read -r event_id occurred_at stored_hash < <(sqlite3 -separator ' ' "$db_path" 'SELECT event_id, occurred_at, event_hash FROM audit_logs WHERE event_name = "slot_launch_accepted";')

	# Act
	recomputed_hash="$(audit_event_hash "$(audit_event_canonical "$event_id" slot_launch_accepted - - "$occurred_at")" "")"

	# Assert
	[ "$recomputed_hash" = "$stored_hash" ]
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
