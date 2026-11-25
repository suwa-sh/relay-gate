#!/usr/bin/env bats
# UC 7c41c7cd × tier-facade: Runner Result の確定名(started-at.txt / stdout.log / stderr.log / exitcode.txt)に
# 通常のファイルでないもの(ディレクトリ・リンク)が先にあるとき、その中やリンク先へ成果物を移さず、
# exitcode.txt を公開しないことの単体テスト(2026-11-24 の S4 attempt 5 で追加。独立検証の指摘への対応)。
# 仕様: tier-facade.md「出力契約」の終了コード 6(3 ファイルを揃えられない場合。実行ログに ERROR)と
#       「UC ロジック」のエラーハンドリング(書き込みに失敗したら exitcode.txt が無い状態)、
#       CLI 契約 artifact_layout(publish_rule: 確定名の存在で完了を判定する。exitcode.txt は 3 ファイル契約の完了マーカー)。
# I/O 境界は実体(BATS_TEST_TMPDIR の実ファイル・標準の slot runner の実プロセス)で確かめる。コマンドは差し替えない。

bats_require_minimum_version 1.5.0

RUN_ID="20261124T000000-JOB999-00000002"

setup() {
	HOME_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	# shellcheck source=/dev/null
	source "$HOME_DIR/src/gateway/filesystem_adapter.sh"
	RUNNER="$HOME_DIR/runners/standard-runner.sh"
	CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	ARTIFACT_ROOT="$BATS_TEST_TMPDIR/artifacts"
	LOG_DIR="$BATS_TEST_TMPDIR/logs"
	RUNNER_TMPDIR="$BATS_TEST_TMPDIR/tmp"
	ROLE_DIR="$ARTIFACT_ROOT/facade/$RUN_ID/green"
	mkdir -p "$CONFIG_DIR" "$ROLE_DIR" "$LOG_DIR" "$RUNNER_TMPDIR"
	printf '%s\n' "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" "JOB001,/w,/s,[],0" >"$CONFIG_DIR/green-job-map.csv"
}

# JOB999 の行が無いジョブマップで green の runner を起動する(解決失敗 → Runner Result を揃える経路)
run_runner() {
	run --separate-stderr env -i PATH="$PATH" RELAY_GATE_CONFIG_DIR="$CONFIG_DIR" RELAY_GATE_ARTIFACT_ROOT="$ARTIFACT_ROOT" \
		RELAY_GATE_LOG_DIR="$LOG_DIR" TMPDIR="$RUNNER_TMPDIR" \
		"$RUNNER" --run-id "$RUN_ID" --job-id JOB999 --role green --mode background
}

# 確定名を公開できなかった runner の結果: 終了コード 6、exitcode.txt なし、実行ログに ERROR、書きかけの一時ファイルなし
assert_runner_write_failed() {
	[ "$status" -eq 6 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ ! -e "$ROLE_DIR/exitcode.txt" ]
	[ ! -L "$ROLE_DIR/exitcode.txt" ]
	grep -q "ERROR runner result write failed run_id=$RUN_ID role=green" "$LOG_DIR/standard-runner.sh.log"
	[ -z "$(find "$BATS_TEST_TMPDIR" -name '*.tmp')" ]
}

@test "標準のslot runner_確定名にディレクトリが先にある場合_その中へ移さずexitcode_txtを公開せず終了コード6であること" {
	local name
	for name in started-at.txt stdout.log stderr.log; do
		# Arrange
		rm -rf "$ROLE_DIR"
		mkdir -p "$ROLE_DIR/$name"

		# Act
		run_runner

		# Assert
		assert_runner_write_failed || {
			echo "name=$name status=$status"
			return 1
		}
		[ -d "$ROLE_DIR/$name" ]
		[ -z "$(ls -A "$ROLE_DIR/$name")" ]
	done
}

@test "標準のslot runner_確定名にディレクトリへのリンクが先にある場合_リンク先へ移さずexitcode_txtを公開せず終了コード6であること" {
	local name outside="$BATS_TEST_TMPDIR/outside"
	for name in started-at.txt stdout.log stderr.log exitcode.txt; do
		# Arrange(exitcode.txt がディレクトリへのリンクのときは、公開済みの判定が先に働き、値を読めずに 6 になる)
		rm -rf "$ROLE_DIR" "$outside" "$LOG_DIR"
		mkdir -p "$ROLE_DIR" "$outside" "$LOG_DIR"
		ln -s "$outside" "$ROLE_DIR/$name"

		# Act
		run_runner

		# Assert
		[ "$status" -eq 6 ] || {
			echo "name=$name status=$status"
			return 1
		}
		[ -z "$output" ]
		[ -z "$stderr" ]
		[ -L "$ROLE_DIR/$name" ]
		[ -z "$(ls -A "$outside")" ]
		[ ! -f "$ROLE_DIR/exitcode.txt" ]
		[ -z "$(find "$BATS_TEST_TMPDIR" -name '*.tmp')" ]
	done
}

@test "標準のslot runner_exitcode_txtの確定名に切れたリンクが先にある場合_リンク先を作らず終了コード6であること" {
	# Arrange(切れたリンクは「公開済み」と判定されない。完了マーカーをリンク越しに公開しない)
	ln -s "$BATS_TEST_TMPDIR/absent" "$ROLE_DIR/exitcode.txt"

	# Act
	run_runner

	# Assert
	[ "$status" -eq 6 ]
	[ -L "$ROLE_DIR/exitcode.txt" ]
	[ ! -e "$BATS_TEST_TMPDIR/absent" ]
	grep -q "ERROR runner result write failed run_id=$RUN_ID role=green" "$LOG_DIR/standard-runner.sh.log"
	[ -z "$(find "$BATS_TEST_TMPDIR" -name '*.tmp')" ]
}

@test "filesystem_adapter_publish_failure_確定名にファイルへのリンクが先にある場合_リンク先を書き換えず1であること" {
	# Arrange
	printf 'keep\n' >"$BATS_TEST_TMPDIR/target"
	ln -s "$BATS_TEST_TMPDIR/target" "$ROLE_DIR/stderr.log"

	# Act
	run --separate-stderr filesystem_adapter_publish_failure "$ROLE_DIR" "2026-11-24T00:00:00Z" 2 "error: x"

	# Assert
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ "$(cat "$BATS_TEST_TMPDIR/target")" = "keep" ]
	[ -L "$ROLE_DIR/stderr.log" ]
	[ ! -e "$ROLE_DIR/exitcode.txt" ]
	[ -z "$(find "$ROLE_DIR" -name '*.tmp')" ]
}

@test "filesystem_adapter_publish_failure_一時ファイルの名前にリンクが先にある場合_リンク先へ書かず1であること" {
	# Arrange(リンク越しに書いた後で mv すると、確定名がリンクになる)
	printf 'keep\n' >"$BATS_TEST_TMPDIR/target"
	ln -s "$BATS_TEST_TMPDIR/target" "$ROLE_DIR/stderr.log.tmp"

	# Act
	run --separate-stderr filesystem_adapter_publish_failure "$ROLE_DIR" "2026-11-24T00:00:00Z" 2 "error: x"

	# Assert
	[ "$status" -eq 1 ]
	[ "$(cat "$BATS_TEST_TMPDIR/target")" = "keep" ]
	[ ! -e "$ROLE_DIR/stderr.log" ]
	[ ! -L "$ROLE_DIR/stderr.log" ]
	[ ! -e "$ROLE_DIR/exitcode.txt" ]
}

@test "filesystem_adapter_publish_failure_確定名に通常のファイルが先にある場合_置き換えて4ファイルを揃えること" {
	# Arrange(exitcode.txt が無い slot に残った前回の途中の成果物。通常起動では上書きする)
	printf '2026-01-01T00:00:00Z\n' >"$ROLE_DIR/started-at.txt"
	printf 'old\n' >"$ROLE_DIR/stdout.log"
	printf 'old\n' >"$ROLE_DIR/stderr.log"

	# Act
	run --separate-stderr filesystem_adapter_publish_failure "$ROLE_DIR" "2026-11-24T00:00:00Z" 2 "error: x"

	# Assert
	[ "$status" -eq 0 ]
	[ "$(cat "$ROLE_DIR/started-at.txt")" = "2026-11-24T00:00:00Z" ]
	[ ! -s "$ROLE_DIR/stdout.log" ]
	[ "$(cat "$ROLE_DIR/stderr.log")" = "error: x" ]
	[ "$(cat "$ROLE_DIR/exitcode.txt")" = "2" ]
}
