#!/usr/bin/env bats
# UC 6078c4ed(select-and-launch-slots-by-feature-flags)の TDD 単体テスト(④)。
# S2 scoped 再実行(spec 20260819_114307 還流)で追加した red テスト。
# 旧仕様の単体テストは 6078c4ed_select_slot.bats に残している(既存実装に対して green。
# 新仕様と食い違う assertion は同ファイル先頭のコメントに列挙し、S4 が整理する)。
# スキーマは契約定数(packages/contracts/relay-gate-db/schema-constants.sh)の列と
# rdb-schema.yaml の PK / UNIQUE に合わせた SQLite(限定検証境界: issues/20260817T230000Z)。

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
exit 0
EOF
	chmod +x "$test_dir/bin/ssh"

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

	# ジョブマップ fixture(spec.md の Given 値)。ファイル形式は未契約(issues/20260817T000000Z)のため
	# 検証境界の仮形式(JSON・slot 別エントリ)。S4 が実装形式に合わせて調整してよい
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

# run_select_slot は新仕様の必須環境変数(RELAYGATE_OPERATOR を含む)を与えて select-slot を実行する。
# 引数: BLUE_MODE GREEN_MODE RAPID_CROSSCHECK_MODE JOB_ID [追加引数...]
run_select_slot() {
	local blue_mode="$1" green_mode="$2" rapid_mode="$3" job_id="$4"
	shift 4
	env \
		PATH="$test_dir/bin:$PATH" \
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

@test "relaygate_concurrent_run_select_slot_排他制約を満たす場合_execution_specsとslot_execution_specsをrun共通とslot別に分離して保存すること" {
	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	[ "$(count_rows execution_specs)" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT job_id || "|" || job_map_version || "|" || hang_detect_limit_minutes || "|" || (parent_run_id IS NULL) FROM execution_specs;')" = "daily-settlement|v1.4.0|30|1" ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || host || ":" || impl_version || ":" || credential_ref FROM slot_execution_specs ORDER BY slot_type;')" = $'blue:blue-host-01:blue-2.3.1:cred-blue-batch\ngreen:green-host-01:green-0.9.0:cred-green-batch' ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(DISTINCT run_id) FROM slot_execution_specs;')" = "1" ]
}

@test "relaygate_concurrent_run_select_slot_排他制約を満たす場合_runner_resultsのSTARTING_snapshotとrunner_result_eventsのattempt_started履歴をslotごとに記録すること" {
	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || role_type || ":" || attempt_no || ":" || status || ":" || (accepted_at IS NOT NULL) || ":" || (attempt_id <> "") FROM runner_results ORDER BY slot_type;')" = $'blue:foreground:1:STARTING:1:1\ngreen:background:1:STARTING:1:1' ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || event_name || ":" || status FROM runner_result_events ORDER BY slot_type;')" = $'blue:attempt_started:STARTING\ngreen:attempt_started:STARTING' ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM runner_results r JOIN runner_result_events e ON e.run_id = r.run_id AND e.slot_type = r.slot_type AND e.role_type = r.role_type AND e.attempt_id = r.attempt_id;')" = "2" ]
}

@test "relaygate_concurrent_run_select_slot_排他制約を満たす場合_起動前監査イベントをaudit_logsへ追記しaudit_chain_headsを更新すること" {
	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	[ "$(sqlite3 "$db_path" 'SELECT event_name || ":" || slot || ":" || attempt_id || ":" || actor || ":" || operation || ":" || outcome || ":" || schema_version FROM audit_logs WHERE event_name = "slot_launch_accepted";')" = "slot_launch_accepted:-:-:ops-tanaka:slot_launch:accepted:1.0" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_logs WHERE event_name = "slot_launch_attempted" AND slot IN ("blue", "green") AND attempt_id <> "-";')" = "2" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_chain_heads h JOIN audit_logs a ON a.event_id = h.head_event_id AND a.event_hash = h.head_hash AND a.run_id = h.run_id;')" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT chain_length FROM audit_chain_heads;')" = "$(count_rows audit_logs)" ]
}

@test "relaygate_concurrent_run_select_slot_排他制約を満たす場合_選択slotごとにrun_id_slot_type_role_attempt_id_STARTINGを1行ずつ標準出力すること" {
	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	run_id="$(sqlite3 "$db_path" 'SELECT run_id FROM execution_specs;')"
	blue_attempt="$(sqlite3 "$db_path" 'SELECT attempt_id FROM runner_results WHERE slot_type = "blue";')"
	green_attempt="$(sqlite3 "$db_path" 'SELECT attempt_id FROM runner_results WHERE slot_type = "green";')"
	[ "$(printf '%s\n' "$output" | grep -c "$run_id")" = "2" ]
	printf '%s\n' "$output" | grep -E "^.*${run_id}.*blue.*foreground.*${blue_attempt}.*STARTING" >/dev/null
	printf '%s\n' "$output" | grep -E "^.*${run_id}.*green.*background.*${green_attempt}.*STARTING" >/dev/null
}

@test "relaygate_concurrent_run_select_slot_audit_logsへのINSERTが失敗する場合_全テーブルをrollbackして外部slotを起動しないこと" {
	# Arrange
	sqlite3 "$db_path" "CREATE TRIGGER reject_audit BEFORE INSERT ON audit_logs BEGIN SELECT RAISE(ABORT, 'injected audit failure'); END;"

	# Act & Assert
	run --separate-stderr run_select_slot foreground background on daily-settlement
	[ "$status" -eq 1 ]
	[ -n "$stderr" ]
	[ "$(count_rows execution_specs)" = "0" ]
	[ "$(count_rows slot_execution_specs)" = "0" ]
	[ "$(count_rows runner_results)" = "0" ]
	[ "$(count_rows runner_result_events)" = "0" ]
	[ "$(count_rows audit_chain_heads)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_RELAYGATE_OPERATORが未設定の場合_起動前監査を記録できないため永続化も起動もしないこと" {
	# Act & Assert
	run --separate-stderr env -u RELAYGATE_OPERATOR \
		PATH="$test_dir/bin:$PATH" \
		RELAYGATE_TEST_LAUNCH_LOG="$launch_log" \
		RELAYGATE_RDB_DSN="sqlite://$db_path" \
		RELAYGATE_JOB_MAP_PATH="$job_map_path" \
		BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=on \
		"$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id daily-settlement
	[ "$status" -ne 0 ]
	[[ "$stderr" == *"RELAYGATE_OPERATOR"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ "$(count_rows audit_logs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_追加引数がある場合_additional_argsをexecution_specsにfixed_argsをslot_execution_specsに分けて保存し固定引数の後ろに連結して起動すること" {
	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement -- --target-date 2026-08-18 --retry 3

	# Assert
	[ "$status" -eq 0 ]
	[[ "$(sqlite3 "$db_path" 'SELECT additional_args FROM execution_specs;')" == *"--target-date"*"2026-08-18"*"--retry"*"3"* ]]
	[[ "$(sqlite3 "$db_path" 'SELECT fixed_args FROM slot_execution_specs WHERE slot_type = "blue";')" == *"--mode"*"batch"* ]]
	grep -E 'blue-host-01.*--mode batch --target-date 2026-08-18 --retry 3' "$launch_log" >/dev/null
}
