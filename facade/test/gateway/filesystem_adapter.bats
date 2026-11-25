#!/usr/bin/env bats
# UC 7c41c7cd(ジョブマップで JOB_ID から実行先を解決する)× tier-facade: gateway/filesystem_adapter.sh の単体テスト。
# 対象: tier-facade.md「出力契約」(成果物(未定義・解決失敗時))と契約 artifact_layout.publish_rule(一時ファイル → mv)。
# I/O 境界は実体(BATS_TEST_TMPDIR の実ファイル)で確かめる。

bats_require_minimum_version 1.5.0

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/gateway/filesystem_adapter.sh"
	ROLE_DIR="$BATS_TEST_TMPDIR/artifacts/facade/r1/green"
}

@test "filesystem_adapter_publish_failure_roleディレクトリが無い場合_ディレクトリを作って4ファイルを揃えtmpを残さないこと" {
	# Act
	run --separate-stderr filesystem_adapter_publish_failure "$ROLE_DIR" "2026-08-30T11:30:05Z" 2 "error: job map not found slot=green map=/m.csv"

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ "$(cat "$ROLE_DIR/started-at.txt")" = "2026-08-30T11:30:05Z" ]
	[ -f "$ROLE_DIR/stdout.log" ]
	[ ! -s "$ROLE_DIR/stdout.log" ]
	[ "$(cat "$ROLE_DIR/stderr.log")" = "error: job map not found slot=green map=/m.csv" ]
	[ "$(cat "$ROLE_DIR/exitcode.txt")" = "2" ]
	[ "$(wc -l <"$ROLE_DIR/exitcode.txt" | tr -d ' ')" = "1" ]
	[ -z "$(find "$ROLE_DIR" -name '*.tmp')" ]
}

@test "filesystem_adapter_publish_failure_stderrの行が複数の場合_渡した順に1行ずつ書くこと" {
	# Act
	filesystem_adapter_publish_failure "$ROLE_DIR" "2026-08-30T11:30:05Z" 2 "error: carriage return is not allowed line=1 path: /m.csv" "hint: use LF line endings"

	# Assert
	[ "$(sed -n 1p "$ROLE_DIR/stderr.log")" = "error: carriage return is not allowed line=1 path: /m.csv" ]
	[ "$(sed -n 2p "$ROLE_DIR/stderr.log")" = "hint: use LF line endings" ]
	[ "$(wc -l <"$ROLE_DIR/stderr.log" | tr -d ' ')" = "2" ]
}

@test "filesystem_adapter_publish_failure_roleディレクトリを作れない場合_何も出力せず1であること" {
	# Arrange(成果物ルートの位置に通常ファイルがある)
	printf 'x\n' >"$BATS_TEST_TMPDIR/artifacts"

	# Act
	run --separate-stderr filesystem_adapter_publish_failure "$ROLE_DIR" "2026-08-30T11:30:05Z" 2 "error: x"

	# Assert
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
}

@test "filesystem_adapter_publish_failure_途中のファイルを書けない場合_exitcode_txtを公開せず1であること" {
	# Arrange(stderr.log の一時ファイルの名前にディレクトリを置く。権限に頼らないため、実行ユーザーによらず書けない)
	mkdir -p "$ROLE_DIR/stderr.log.tmp"

	# Act
	run --separate-stderr filesystem_adapter_publish_failure "$ROLE_DIR" "2026-08-30T11:30:05Z" 2 "error: x"

	# Assert(完了マーカーの exitcode.txt は最後に公開するため、途中で失敗したら存在しない)
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ ! -e "$ROLE_DIR/exitcode.txt" ]
	[ ! -e "$ROLE_DIR/stderr.log" ]
}

@test "filesystem_adapter_read_exit_code_数値1行のexitcode_txtの場合_値を載せること" {
	# Arrange
	mkdir -p "$ROLE_DIR"
	printf '7\n' >"$ROLE_DIR/exitcode.txt"

	# Act
	filesystem_adapter_read_exit_code "$ROLE_DIR"

	# Assert
	[ "$FILESYSTEM_ADAPTER_EXIT_CODE" = "7" ]
}

@test "filesystem_adapter_read_exit_code_最終行に改行が無く先頭に0がある場合_10進数として読むこと" {
	# Arrange
	mkdir -p "$ROLE_DIR"
	printf '010' >"$ROLE_DIR/exitcode.txt"

	# Act
	filesystem_adapter_read_exit_code "$ROLE_DIR"

	# Assert
	[ "$FILESYSTEM_ADAPTER_EXIT_CODE" = "10" ]
}

@test "filesystem_adapter_read_exit_code_ファイルが無い・数値でない・255を超える場合_1であること" {
	# Arrange
	mkdir -p "$ROLE_DIR"
	local content run_status

	# Act / Assert(ファイルなし)
	run_status=0
	filesystem_adapter_read_exit_code "$ROLE_DIR" || run_status=$?
	[ "$run_status" -eq 1 ]

	for content in "" "abc" "256" "-1" "1 2"; do
		printf '%s\n' "$content" >"$ROLE_DIR/exitcode.txt"
		run_status=0
		filesystem_adapter_read_exit_code "$ROLE_DIR" || run_status=$?
		[ "$run_status" -eq 1 ] || {
			echo "content=[$content] status=$run_status"
			return 1
		}
		[ -z "$FILESYSTEM_ADAPTER_EXIT_CODE" ]
	done
}

# ---- 起動時の二重起動判定(契約 runner IF の idempotency。attempt 3) ----

@test "filesystem_adapter_slot_state_roleディレクトリが無い・started-at_txtだけがある場合_openであること" {
	# Act / Assert(ディレクトリなし)
	filesystem_adapter_slot_state "$ROLE_DIR"
	[ "$FILESYSTEM_ADAPTER_SLOT_STATE" = "$FILESYSTEM_ADAPTER_SLOT_OPEN" ]

	# Act / Assert(started-at.txt だけ。通常起動では上書き再実行)
	mkdir -p "$ROLE_DIR"
	printf '2026-08-30T11:30:05Z\n' >"$ROLE_DIR/started-at.txt"
	filesystem_adapter_slot_state "$ROLE_DIR"
	[ "$FILESYSTEM_ADAPTER_SLOT_STATE" = "$FILESYSTEM_ADAPTER_SLOT_OPEN" ]
}

@test "filesystem_adapter_slot_state_exitcode_txtが無くaborted_txtがある場合_abortedであること" {
	# Arrange
	mkdir -p "$ROLE_DIR"
	printf '2026-08-30T11:40:00Z\n' >"$ROLE_DIR/aborted.txt"

	# Act
	run --separate-stderr filesystem_adapter_slot_state "$ROLE_DIR"
	filesystem_adapter_slot_state "$ROLE_DIR"

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ "$FILESYSTEM_ADAPTER_SLOT_STATE" = "$FILESYSTEM_ADAPTER_SLOT_ABORTED" ]
}

@test "filesystem_adapter_slot_state_exitcode_txtとaborted_txtの両方がある場合_exitcode_txtを優先してpublishedであること" {
	# Arrange(中止後に実装が終了して exitcode.txt を公開した slot)
	mkdir -p "$ROLE_DIR"
	printf '2026-08-30T11:40:00Z\n' >"$ROLE_DIR/aborted.txt"
	printf '143\n' >"$ROLE_DIR/exitcode.txt"

	# Act
	filesystem_adapter_slot_state "$ROLE_DIR"

	# Assert
	[ "$FILESYSTEM_ADAPTER_SLOT_STATE" = "$FILESYSTEM_ADAPTER_SLOT_PUBLISHED" ]
}
