#!/usr/bin/env bats

setup() {
	bats_require_minimum_version 1.5.0
	project_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	test_dir="$(mktemp -d)"
	db_path="$test_dir/relaygate.db"
	job_map_path="$test_dir/job-map.json"
	launch_log="$test_dir/launch.log"
	mkdir -p "$test_dir/bin"

	cat >"$test_dir/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RELAYGATE_TEST_LAUNCH_LOG"
EOF
	chmod +x "$test_dir/bin/ssh"

	sqlite3 "$db_path" <<'SQL'
CREATE TABLE execution_specs (
  run_id TEXT PRIMARY KEY, parent_run_id TEXT, job_id TEXT, host TEXT,
  exec_user TEXT, script_path TEXT, work_dir TEXT, fixed_args TEXT,
  additional_args TEXT, job_map_version TEXT, impl_version TEXT,
  hang_detect_limit_minutes INTEGER, credential_ref TEXT
);
CREATE TABLE runner_results (
  run_id TEXT, slot_type TEXT, role_type TEXT, started_at TEXT,
  stdout_path TEXT, stderr_path TEXT, exit_code INTEGER, status TEXT,
  PRIMARY KEY (run_id, role_type)
);
SQL

	cat >"$job_map_path" <<'JSON'
{
  "version": "map-v1",
  "jobs": {
    "JOB-2026-0817-001": {
      "host": "runner.example.test",
      "exec_user": "relay",
      "script_path": "/opt/jobs/example.sh",
      "work_dir": "/var/tmp/relay",
      "fixed_args": ["--fixed"],
      "impl_version": "green-v1",
      "hang_detect_limit_minutes": 15,
      "credential_ref": "ssh-key-reference"
    }
  }
}
JSON
}

teardown() {
	rm -rf "$test_dir"
}

run_select_slot() {
	env \
		PATH="$test_dir/bin:$PATH" \
		RELAYGATE_TEST_LAUNCH_LOG="$launch_log" \
		RELAYGATE_RDB_DSN="sqlite://$db_path" \
		RELAYGATE_JOB_MAP_PATH="$job_map_path" \
		BLUE_MODE="$1" GREEN_MODE="$2" RAPID_CROSSCHECK_MODE="$3" \
		"$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id "$4"
}

run_select_slot_with_args() {
	env \
		PATH="$test_dir/bin:$PATH" \
		RELAYGATE_TEST_LAUNCH_LOG="$launch_log" \
		RELAYGATE_RDB_DSN="sqlite://$db_path" \
		RELAYGATE_JOB_MAP_PATH="$job_map_path" \
		BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off \
		"$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id JOB-2026-0817-001 -- --date 2026-08-17
}

@test "relaygate_concurrent_run_select_slot_排他的foreground設定の場合_execution_specとforeground結果を保存して両slotを起動すること" {
	# Arrange
	:

	# Act
	run --separate-stderr run_select_slot foreground background on JOB-2026-0817-001

	# Assert
	[ "$status" -eq 0 ]
	[[ "$output" == *"blue: foreground"* ]]
	[[ "$output" == *"green: background"* ]]
	[[ "$output" == *"run_id: "* ]]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM execution_specs;')" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT job_id FROM execution_specs;')" = "JOB-2026-0817-001" ]
	[ "$(sqlite3 "$db_path" 'SELECT additional_args FROM execution_specs;')" = "[]" ]
	[ "$(sqlite3 "$db_path" 'SELECT credential_ref FROM execution_specs;')" = "ssh-key-reference" ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || role_type || ":" || status FROM runner_results;')" = "blue:foreground:RUNNING" ]
	[ "$(wc -l <"$launch_log" | tr -d ' ')" = "2" ]
}

@test "relaygate_concurrent_run_select_slot_追加引数がある場合_execution_specへそのままJSON配列で保存すること" {
	# Arrange
	:

	# Act
	run --separate-stderr run_select_slot_with_args

	# Assert
	[ "$status" -eq 0 ]
	[ "$(sqlite3 "$db_path" 'SELECT additional_args FROM execution_specs;')" = '["--date","2026-08-17"]' ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type FROM runner_results;')" = "green" ]
}

@test "relaygate_concurrent_run_select_slot_両slotがforegroundの場合_検証エラーで永続化も起動もしないこと" {
	# Arrange
	:

	# Act & Assert
	run --separate-stderr run_select_slot foreground foreground on JOB-2026-0817-001
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"BLUE_MODEとGREEN_MODEを同時にforegroundにすることはできません"* ]]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM execution_specs;')" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_ジョブマップにJOB_IDがない場合_業務エラーで永続化しないこと" {
	# Arrange
	:

	# Act & Assert
	run --separate-stderr run_select_slot foreground background on JOB-UNKNOWN-999
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"JOB_IDに対応するジョブマップが見つかりません: JOB-UNKNOWN-999"* ]]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM execution_specs;')" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_不正なfeature_flagの場合_検証エラーで永続化しないこと" {
	# Arrange
	:

	# Act & Assert
	run --separate-stderr run_select_slot invalid background on JOB-2026-0817-001
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"BLUE_MODE must be off, background, or foreground"* ]]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM execution_specs;')" = "0" ]
}
