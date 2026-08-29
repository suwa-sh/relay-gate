#!/usr/bin/env bats
# UC 6078c4ed(select-and-launch-slots-by-feature-flags)の TDD 単体テスト(④)。
# S2 scoped 再実行(spec 20260829_210828_spec_generation 還流: CR-6078c4ed-011〜018)で新契約に追随した red テスト。
# - ジョブマップは slot 別ファイル(RELAYGATE_JOB_MAP_PATH_BLUE / _GREEN。cli-command-contract.yaml job_map_contract)
# - 認証情報は認証情報ディレクトリ(RELAYGATE_CREDENTIAL_DIR/{credential_ref}、0600。credential_resolution)
# - スキーマは契約定数(packages/contracts/relay-gate-db/schema-constants.sh)の列と rdb-schema.yaml の PK / UNIQUE に
#   合わせた SQLite(限定検証境界: issues/20260817T230000Z)。job_map_version は slot_execution_specs 側
# - 追加引数・固定引数は JSON 配列で保存する(rdb-schema.yaml argument_serialization)
# - 起動イベント送出の失敗 / timeout は PATH 先頭の ssh スタブが接続先ホスト名で再現する
# 旧仕様の単体テストは 6078c4ed_select_slot.bats に残している(旧契約前提の assertion は S4 が整理する)。

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
	mkdir -p "$test_dir/bin" "$credential_dir"

	# ssh スタブ: 起動イベント(引数列)を起動ログへ追記し、接続先ホストにより成功 / 接続失敗(exit 255)/ 応答しない を切り替える
	cat >"$test_dir/bin/ssh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RELAYGATE_TEST_LAUNCH_LOG"
target="$5"
if [[ -n ${RELAYGATE_TEST_SSH_FAIL_HOST:-} && $target == *"@${RELAYGATE_TEST_SSH_FAIL_HOST}" ]]; then exit 255; fi
if [[ -n ${RELAYGATE_TEST_SSH_HANG_HOST:-} && $target == *"@${RELAYGATE_TEST_SSH_HANG_HOST}" ]]; then sleep 120; fi
exit 0
EOF
	chmod +x "$test_dir/bin/ssh"

	# 認証情報ディレクトリ(credential_ref と同名の秘密鍵ファイル、0600)
	printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nbats-test-key cred-blue-batch\n-----END OPENSSH PRIVATE KEY-----\n' >"$credential_dir/cred-blue-batch"
	printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nbats-test-key cred-green-batch\n-----END OPENSSH PRIVATE KEY-----\n' >"$credential_dir/cred-green-batch"
	chmod 0600 "$credential_dir/cred-blue-batch" "$credential_dir/cred-green-batch"

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

	# ジョブマップ fixture(cli-command-contract.yaml job_map_contract の形式。値は spec.md の Background)
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
}

teardown() {
	rm -rf "$test_dir"
}

# run_select_slot は新契約の必須環境変数を与えて select-slot を実行する。
# 引数: BLUE_MODE GREEN_MODE RAPID_CROSSCHECK_MODE JOB_ID [追加引数...]
run_select_slot() {
	local blue_mode="$1" green_mode="$2" rapid_mode="$3" job_id="$4"
	shift 4
	env \
		PATH="$test_dir/bin:$PATH" \
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

@test "relaygate_concurrent_run_select_slot_排他制約を満たす場合_execution_specsをrun共通で・slot_execution_specsをslot別のjob_map_version付きで保存すること" {
	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	[ "$(count_rows execution_specs)" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT job_id || "|" || hang_detect_limit_minutes || "|" || (parent_run_id IS NULL) FROM execution_specs;')" = "daily-settlement|45|1" ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || host || ":" || impl_version || ":" || credential_ref || ":" || job_map_version FROM slot_execution_specs ORDER BY slot_type;')" = $'blue:blue-host-01:blue-2.3.1:cred-blue-batch:v1.4.0\ngreen:green-host-01:green-0.9.0:cred-green-batch:v1.4.0' ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(DISTINCT run_id) FROM slot_execution_specs;')" = "1" ]
}

@test "relaygate_concurrent_run_select_slot_排他制約を満たす場合_runner_resultsのSTARTING_snapshotとattempt_started履歴を同一時刻で記録すること" {
	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || role_type || ":" || attempt_no || ":" || status || ":" || (accepted_at = updated_at) || ":" || (attempt_id <> "") FROM runner_results ORDER BY slot_type;')" = $'blue:foreground:1:STARTING:1:1\ngreen:background:1:STARTING:1:1' ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || event_name || ":" || status FROM runner_result_events ORDER BY slot_type;')" = $'blue:attempt_started:STARTING\ngreen:attempt_started:STARTING' ]
	# 履歴の occurred_at と snapshot の accepted_at / updated_at はマイクロ秒精度の UTC で同一値
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM runner_results r JOIN runner_result_events e ON e.run_id = r.run_id AND e.slot_type = r.slot_type AND e.role_type = r.role_type AND e.attempt_id = r.attempt_id AND e.occurred_at = r.accepted_at AND e.occurred_at = r.updated_at;')" = "2" ]
	[ "$(sqlite3 "$db_path" "SELECT COUNT(*) FROM runner_result_events WHERE occurred_at NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9][0-9][0-9][0-9]Z';")" = "0" ]
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
		RELAYGATE_JOB_MAP_PATH_BLUE="$job_map_blue" \
		RELAYGATE_JOB_MAP_PATH_GREEN="$job_map_green" \
		RELAYGATE_CREDENTIAL_DIR="$credential_dir" \
		BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=on \
		"$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id daily-settlement
	[ "$status" -ne 0 ]
	[[ "$stderr" == *"RELAYGATE_OPERATOR"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ "$(count_rows audit_logs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_追加引数がある場合_additional_argsとfixed_argsをJSON配列で保存し固定引数の後ろに要素順で連結して起動すること" {
	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement -- --target-date 2026-08-18 --retry 3

	# Assert
	[ "$status" -eq 0 ]
	[ "$(sqlite3 "$db_path" 'SELECT additional_args FROM execution_specs;' | jq -c .)" = '["--target-date","2026-08-18","--retry","3"]' ]
	[ "$(sqlite3 "$db_path" 'SELECT fixed_args FROM slot_execution_specs WHERE slot_type = "blue";' | jq -c .)" = '["--mode","batch"]' ]
	grep -E 'blue-host-01.*/opt/blue/run.sh --mode batch --target-date 2026-08-18 --retry 3' "$launch_log" >/dev/null
}

@test "relaygate_concurrent_run_select_slot_空白と引用符と改行を含む追加引数の場合_JSON配列の往復で要素が同一であること" {
	# Act
	run --separate-stderr run_select_slot foreground off off daily-settlement -- --note 'a b "c"' $'x\ny'

	# Assert
	[ "$status" -eq 0 ]
	saved="$(sqlite3 "$db_path" 'SELECT additional_args FROM execution_specs;')"
	[ "$(printf '%s' "$saved" | jq -c .)" = '["--note","a b \"c\"","x\ny"]' ]
	# 復元した 3 要素が渡した要素と 1 要素ずつ同一(再分割・トリム・クォート付与なし)
	[ "$(printf '%s' "$saved" | jq -r 'length')" = "3" ]
	[ "$(printf '%s' "$saved" | jq -r '.[1]')" = 'a b "c"' ]
	[ "$(printf '%s' "$saved" | jq -r '.[2]')" = $'x\ny' ]
}

@test "relaygate_concurrent_run_select_slot_BLUE_MODEがoffでRELAYGATE_JOB_MAP_PATH_BLUEが未設定の場合_blueのジョブマップを読まずgreenのみ起動すること" {
	# Act
	run --separate-stderr env -u RELAYGATE_JOB_MAP_PATH_BLUE \
		PATH="$test_dir/bin:$PATH" \
		RELAYGATE_TEST_LAUNCH_LOG="$launch_log" \
		RELAYGATE_RDB_DSN="sqlite://$db_path" \
		RELAYGATE_JOB_MAP_PATH_GREEN="$job_map_green" \
		RELAYGATE_CREDENTIAL_DIR="$credential_dir" \
		RELAYGATE_OPERATOR=ops-tanaka \
		BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off \
		"$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	[ "$(sqlite3 "$db_path" 'SELECT hang_detect_limit_minutes FROM execution_specs;')" = "45" ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || job_map_version FROM slot_execution_specs;')" = "green:v1.4.0" ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || role_type || ":" || status FROM runner_results;')" = "green:foreground:STARTING" ]
	[ "$(wc -l <"$launch_log" | tr -d ' ')" = "1" ]
}

# foreground はちょうど 1 件(ユーザー決定 2026-08-30、issues/20260830T034746Z_exactly-one-foreground-rule.md)。
# 両 background は現行 spec の「大きい方を採用する」Scenario から意図的に逸脱して検証エラーにする(S8 で仕様変更要求化)
@test "relaygate_concurrent_run_select_slot_両slotがbackgroundの場合_foreground不在のバリデーションエラーで永続化も起動もしないこと" {
	# Act & Assert
	run --separate-stderr run_select_slot background background on daily-settlement
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"BLUE_MODEとGREEN_MODEのどちらか1つをforegroundにする必要があります"* ]]
	[[ "$stderr" == *"Next action:"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ "$(count_rows audit_logs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_両slotがoffの場合_foreground不在のバリデーションエラーで永続化も起動もしないこと" {
	# Act & Assert
	run --separate-stderr run_select_slot off off off daily-settlement
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"BLUE_MODEとGREEN_MODEのどちらか1つをforegroundにする必要があります"* ]]
	[[ "$stderr" != *"unbound variable"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ "$(count_rows audit_logs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_両slotがforegroundの場合_排他制約のバリデーションエラーで永続化も起動もしないこと" {
	# Act & Assert
	run --separate-stderr run_select_slot foreground foreground on daily-settlement
	[ "$status" -eq 2 ]
	[[ "$stderr" == *"BLUE_MODEとGREEN_MODEを同時にforegroundにすることはできません"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_ジョブマップのslot_typeが環境変数の指すslotと一致しない場合_バリデーションエラーで永続化も起動もしないこと" {
	# Act & Assert
	# RELAYGATE_JOB_MAP_PATH_GREEN に blue のジョブマップ(slot_type="blue")を指す
	run --separate-stderr env \
		PATH="$test_dir/bin:$PATH" \
		RELAYGATE_TEST_LAUNCH_LOG="$launch_log" \
		RELAYGATE_RDB_DSN="sqlite://$db_path" \
		RELAYGATE_JOB_MAP_PATH_BLUE="$job_map_blue" \
		RELAYGATE_JOB_MAP_PATH_GREEN="$job_map_blue" \
		RELAYGATE_CREDENTIAL_DIR="$credential_dir" \
		RELAYGATE_OPERATOR=ops-tanaka \
		BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=on \
		"$project_root/facade/bin/relaygate" concurrent-run select-slot --job-id daily-settlement
	[ "$status" -eq 2 ]
	[[ "$(strip_test_dir "$stderr")" == *"ジョブマップの必須フィールドが欠落しています: slot_type=green path=/etc/relaygate/job-map.blue.json field=slot_type"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ "$(count_rows audit_logs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_必須フィールドhang_detect_limit_minutesが欠落している場合_バリデーションエラーで永続化も起動もしないこと" {
	# Arrange
	jq 'del(.jobs."daily-settlement".hang_detect_limit_minutes)' "$job_map_green" >"$job_map_green.tmp" && mv "$job_map_green.tmp" "$job_map_green"

	# Act & Assert
	run --separate-stderr run_select_slot foreground background on daily-settlement
	[ "$status" -eq 2 ]
	[[ "$(strip_test_dir "$stderr")" == *"ジョブマップの必須フィールドが欠落しています: slot_type=green path=/etc/relaygate/job-map.green.json field=jobs.daily-settlement.hang_detect_limit_minutes"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ "$(count_rows audit_logs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_JOB_IDがいずれのジョブマップにも無い場合_業務エラーで永続化も起動もしないこと" {
	# Act & Assert
	run --separate-stderr run_select_slot foreground background on unknown-job
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"JOB_IDに対応するジョブマップが見つかりません: unknown-job"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ "$(count_rows audit_logs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_credential_refの秘密鍵が認証情報ディレクトリに無い場合_業務エラーで永続化も起動もしないこと" {
	# Arrange
	rm -f "$credential_dir/cred-green-batch"

	# Act & Assert
	run --separate-stderr run_select_slot foreground background on daily-settlement
	[ "$status" -eq 1 ]
	[[ "$stderr" == *"SSH認証情報を解決できません: credential_ref=cred-green-batch"* ]]
	[[ "$stderr" != *"$credential_dir"* ]]
	[ "$(count_rows execution_specs)" = "0" ]
	[ "$(count_rows audit_logs)" = "0" ]
	[ ! -e "$launch_log" ]
}

@test "relaygate_concurrent_run_select_slot_認証情報の実値と余剰フィールド値_RDBと標準出力と標準エラーと起動イベントのいずれにも現れないこと" {
	# Arrange
	printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nRELAYGATE-TEST-SECRET-BLUE\n-----END OPENSSH PRIVATE KEY-----\n' >"$credential_dir/cred-blue-batch"
	chmod 0600 "$credential_dir/cred-blue-batch"
	jq '.jobs."daily-settlement".note = "RELAYGATE-TEST-SECRET-EXTRA"' "$job_map_blue" >"$job_map_blue.tmp" && mv "$job_map_blue.tmp" "$job_map_blue"

	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement

	# Assert
	[ "$status" -eq 0 ]
	dump="$(sqlite3 "$db_path" .dump)"
	[[ "$dump" != *"RELAYGATE-TEST-SECRET"* ]]
	[[ "$output" != *"RELAYGATE-TEST-SECRET"* ]]
	[[ "$stderr" != *"RELAYGATE-TEST-SECRET"* ]]
	run ! grep -q 'RELAYGATE-TEST-SECRET' "$launch_log"
	# 起動イベントは credential_ref から解決した秘密鍵ファイルを参照する(実値ではなくパス)
	grep -E "blue-host-01" "$launch_log" | grep -q -- "$credential_dir/cred-blue-batch"
}

@test "relaygate_concurrent_run_select_slot_起動イベントの送出に失敗した場合_当該試行をFAILEDへ補償記録しslot_launch_failedを追記して業務エラーで終了すること" {
	# Arrange
	export RELAYGATE_TEST_SSH_FAIL_HOST=green-host-01

	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement

	# Assert
	[ "$status" -eq 1 ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || status || ":" || (exit_code IS NULL) FROM runner_results ORDER BY slot_type;')" = $'blue:STARTING:1\ngreen:FAILED:1' ]
	[ "$(sqlite3 "$db_path" 'SELECT event_name || ":" || status FROM runner_result_events WHERE slot_type = "green" ORDER BY occurred_at;')" = $'attempt_started:STARTING\nattempt_failed:FAILED' ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM runner_results r JOIN runner_result_events e ON e.run_id = r.run_id AND e.slot_type = r.slot_type AND e.attempt_id = r.attempt_id AND e.event_name = "attempt_failed" AND e.occurred_at = r.updated_at;')" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT slot || ":" || outcome || ":" || error_code || ":" || actor FROM audit_logs WHERE event_name = "slot_launch_failed";')" = "green:failed:launch_event_send_failed:ops-tanaka" ]
	# slot_launch_failed は slot_launch_attempted の後ろにチェーンされ、チェーン先頭になる(run_id 単位の線形チェーンのため
	# 直前は起動前 transaction で最後に追記した slot_launch_attempted。同 slot のものとは限らない)
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_logs f JOIN audit_logs a ON a.event_hash = f.previous_hash WHERE f.event_name = "slot_launch_failed" AND a.event_name = "slot_launch_attempted";')" = "1" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_chain_heads h JOIN audit_logs f ON f.event_id = h.head_event_id AND f.event_hash = h.head_hash WHERE f.event_name = "slot_launch_failed" AND h.chain_length = 4;')" = "1" ]
	# 起動受付の記録(標準出力)は維持され、blue の起動イベントは送出される
	[ "$(printf '%s\n' "$output" | grep -c 'status=STARTING')" = "2" ]
	grep -q 'blue-host-01' "$launch_log"
	[[ "$stderr" == *"slot_type=green attempt_id="*" を FAILED として記録しました"* ]]
}

@test "relaygate_concurrent_run_select_slot_起動イベントの送出がtimeoutした場合_当該試行をUNKNOWNへ補償記録しslot_launch_timeoutを追記して124で終了すること" {
	# Arrange
	# ssh スタブが応答しない状態にし、テスト時間短縮のため SSH 待機上限(実装 seam)を 2 秒にする
	export RELAYGATE_TEST_SSH_HANG_HOST=blue-host-01
	export RELAYGATE_SSH_TIMEOUT_SECONDS=2

	# Act
	run --separate-stderr run_select_slot foreground background on daily-settlement

	# Assert
	[ "$status" -eq 124 ]
	[ "$(sqlite3 "$db_path" 'SELECT slot_type || ":" || status || ":" || (exit_code IS NULL) FROM runner_results ORDER BY slot_type;')" = $'blue:UNKNOWN:1\ngreen:STARTING:1' ]
	[ "$(sqlite3 "$db_path" 'SELECT event_name || ":" || status FROM runner_result_events WHERE slot_type = "blue" ORDER BY occurred_at;')" = $'attempt_started:STARTING\nattempt_unknown:UNKNOWN' ]
	[ "$(sqlite3 "$db_path" 'SELECT slot || ":" || outcome || ":" || error_code FROM audit_logs WHERE event_name = "slot_launch_timeout";')" = "blue:timeout:launch_event_send_timeout" ]
	[ "$(sqlite3 "$db_path" 'SELECT COUNT(*) FROM audit_logs WHERE event_name IN ("slot_launch_failed");')" = "0" ]
	[[ "$stderr" == *"slot_type=blue attempt_id="*" を UNKNOWN として記録しました"* ]]
}
