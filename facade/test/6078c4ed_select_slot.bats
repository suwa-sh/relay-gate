#!/usr/bin/env bats

setup() {
	bats_require_minimum_version 1.5.0
	project_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
	test_dir="$(mktemp -d)"
	db_path="$test_dir/relaygate.db"
	job_map_path="$test_dir/job-map.json"
	launch_log="$test_dir/launch.log"
	execution_spec_dir="$test_dir/execution-specs"
	system_sqlite="$(command -v sqlite3)"
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

set_job_map_field() {
	local field="$1" value="$2"
	jq --argjson value "$value" ".jobs[\"JOB-2026-0817-001\"].$field = \$value" "$job_map_path" >"$job_map_path.next"
	mv "$job_map_path.next" "$job_map_path"
}

run_select_slot() {
	env \
		PATH="$test_dir/bin:$PATH" \
		RELAYGATE_TEST_SYSTEM_SQLITE3="$system_sqlite" \
		RELAYGATE_TEST_LAUNCH_LOG="$launch_log" \
		RELAYGATE_RDB_DSN="sqlite://$db_path" \
		RELAYGATE_JOB_MAP_PATH="$job_map_path" \
		RELAYGATE_EXECUTION_SPEC_DIR="$execution_spec_dir" \
		BLUE_MODE="$1" GREEN_MODE="$2" RAPID_CROSSCHECK_MODE="$3" \
		"$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id "$4"
}

run_select_slot_with_args() {
	env \
		PATH="$test_dir/bin:$PATH" \
		RELAYGATE_TEST_SYSTEM_SQLITE3="$system_sqlite" \
		RELAYGATE_TEST_LAUNCH_LOG="$launch_log" \
		RELAYGATE_RDB_DSN="sqlite://$db_path" \
		RELAYGATE_JOB_MAP_PATH="$job_map_path" \
		RELAYGATE_EXECUTION_SPEC_DIR="$execution_spec_dir" \
		BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off \
		"$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id JOB-2026-0817-001 -- --date 2026-08-17
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
exec /usr/bin/jq "$@"
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
	[ "$(sqlite3 "$db_path" 'SELECT additional_args IS NULL FROM execution_specs;')" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT credential_ref FROM execution_specs;')" = "ssh-key-reference" ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || role_type || ":" || status FROM runner_results;')" = "blue:foreground:RUNNING" ]
	[ "$(wc -l <"$launch_log" | tr -d ' ')" = "2" ]
	run_id="$(sqlite3 "$db_path" 'SELECT run_id FROM execution_specs;')"
	execution_spec_path="$execution_spec_dir/$run_id/execution-spec.json"
	[ -f "$execution_spec_path" ]
	[ ! -e "$execution_spec_dir/$run_id/.execution-spec.json.tmp" ]
	jq -e --arg run_id "$run_id" '. == {
		run_id: $run_id,
		parent_run_id: null,
		job_id: "JOB-2026-0817-001",
		host: "runner.example.test",
		exec_user: "relay",
		script_path: "/opt/jobs/example.sh",
		work_dir: "/var/tmp/relay",
		fixed_args: ["--fixed"],
		additional_args: null,
		job_map_version: "map-v1",
		impl_version: "green-v1",
		hang_detect_limit_minutes: 15,
		credential_ref: "ssh-key-reference",
		blue_mode: "foreground",
		green_mode: "background",
		rapid_crosscheck_mode: "on"
	}' "$execution_spec_path" >/dev/null
	[[ "$(<"$launch_log")" == *"RELAYGATE_RUN_ID=$run_id"* ]]
	[[ "$(<"$launch_log")" == *"RELAYGATE_EXECUTION_SPEC_PATH=$execution_spec_path"* ]]
	[[ "$(<"$launch_log")" == *"RELAYGATE_BLUE_MODE=foreground"* ]]
	[[ "$(<"$launch_log")" == *"RELAYGATE_GREEN_MODE=background"* ]]
	[[ "$(<"$launch_log")" == *"RELAYGATE_RAPID_CROSSCHECK_MODE=on"* ]]
	[[ "$(<"$launch_log")" == *"-n -o BatchMode=yes -- relay@runner.example.test"* ]]
}

@test "relaygate_concurrent_run_select_slot_fixed_argsに改行がある場合_SSHへ単一引数として伝播すること" {
	# Arrange
	set_job_map_field fixed_args '["--fixed=first\nsecond", "spaced value"]'
	expected_fixed_args="$(printf '%q %q' $'--fixed=first\nsecond' 'spaced value')"

	# Act
	run --separate-stderr run_select_slot off foreground off JOB-2026-0817-001

	# Assert
	[ "$status" -eq 0 ]
	[[ "$(<"$launch_log")" == *"$expected_fixed_args"* ]]
}

@test "relaygate_concurrent_run_select_slot_初期DB書込みが遅延した場合_全体deadline内にファイル補償すること" {
	# Arrange
	export RELAYGATE_TEST_SQLITE_DELAY_SECONDS=20
	started_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Act
	run --separate-stderr run_select_slot foreground off on JOB-2026-0817-001
	elapsed_seconds="$(perl -MTime::HiRes=time -e 'printf "%.6f", time')"

	# Assert
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"boundary=rdb"* ]]
	awk -v started="$started_seconds" -v ended="$elapsed_seconds" 'BEGIN { exit !(ended - started < 10) }'
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM execution_specs;')" = "0" ]
	[ "$(find "$execution_spec_dir" -name execution-spec.json -print 2>/dev/null | wc -l | tr -d ' ')" = "0" ]
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

@test "relaygate_concurrent_run_select_slot_事前runner結果のINSERTが失敗した場合_execution_specもrollbackすること" {
	# Arrange
	sqlite3 "$db_path" "CREATE TRIGGER reject_runner_result BEFORE INSERT ON runner_results BEGIN SELECT RAISE(ABORT, 'injected'); END;"

	# Act & Assert
	run --separate-stderr run_select_slot foreground off on JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"boundary=rdb"* ]]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM execution_specs;')" = "0" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM runner_results;')" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_必須項目が文字列以外の場合_業務エラーで永続化しないこと" {
	# Arrange
	set_job_map_field host '{"unexpected":"object"}'

	# Act & Assert
	run --separate-stderr run_select_slot off background off JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"JOB_IDに対応するジョブマップが見つかりません"* ]]
	[[ "$stderr" == *"boundary=job_map, field=entry, category=invalid_type"* ]]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM execution_specs;')" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_credential_refが文字列でもnullでもない場合_業務エラーで永続化しないこと" {
	# Arrange
	set_job_map_field credential_ref 42

	# Act & Assert
	run --separate-stderr run_select_slot off background off JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM execution_specs;')" = "0" ]
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
	[[ "$(<"$launch_log")" == *"--fixed --date 2026-08-17"* ]]
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

@test "relaygate_concurrent_run_select_slot_SSH起動失敗の場合_foreground結果をFAILEDへ補償して診断情報を返すこと" {
	# Arrange
	export RELAYGATE_TEST_SSH_MODE=fail

	# Act & Assert
	run --separate-stderr run_select_slot foreground off on JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Failed to start blue slot"* ]]
	[[ "$stderr" == *"boundary=ssh"* ]]
	[[ "$stderr" == *"run_id="* ]]
	[ "$(sqlite3 "$db_path" 'SELECT status FROM runner_results;')" = "FAILED" ]
	[ "$(sqlite3 "$db_path" 'SELECT exit_code FROM runner_results;')" = "255" ]
}

@test "relaygate_concurrent_run_select_slot_SSHが応答しない場合_10秒以内にFAILEDへ補償すること" {
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
	[ "$(sqlite3 "$db_path" 'SELECT status FROM runner_results;')" = "FAILED" ]
	[ "$(sqlite3 "$db_path" 'SELECT exit_code FROM runner_results;')" = "124" ]
}

@test "relaygate_concurrent_run_select_slot_後続slotのSSH起動失敗の場合_成功済みslotを保ったまま失敗slotを記録すること" {
	# Arrange
	export RELAYGATE_TEST_SSH_MODE=fail-green

	# Act & Assert
	run --separate-stderr run_select_slot foreground background on JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"Failed to start green slot"* ]]
	[ "$(sqlite3 "$db_path" "SELECT slot_type || ':' || role_type || ':' || status FROM runner_results ORDER BY role_type;")" = $'green:background:FAILED\nblue:foreground:RUNNING' ]
}

@test "relaygate_concurrent_run_select_slot_不正なハング検知しきい値の場合_業務エラーで永続化しないこと" {
	# Arrange
	set_job_map_field hang_detect_limit_minutes '"15; DROP TABLE execution_specs;"'

	# Act & Assert
	run --separate-stderr run_select_slot off background off JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"JOB_IDに対応するジョブマップが見つかりません"* ]]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM execution_specs;')" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_fixed_argsが文字列配列以外の場合_業務エラーで永続化しないこと" {
	# Arrange
	set_job_map_field fixed_args '["--fixed", 42]'

	# Act & Assert
	run --separate-stderr run_select_slot off background off JOB-2026-0817-001
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"JOB_IDに対応するジョブマップが見つかりません"* ]]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM execution_specs;')" = "0" ]
}

@test "relaygate_concurrent_run_select_slot_credential_refが欠落した場合_NULLを保存すること" {
	# Arrange
	set_job_map_field credential_ref null

	# Act
	run --separate-stderr run_select_slot off background off JOB-2026-0817-001

	# Assert
	[ "$status" -eq 0 ]
	[ "$(sqlite3 "$db_path" 'SELECT credential_ref IS NULL FROM execution_specs;')" = "1" ]
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
