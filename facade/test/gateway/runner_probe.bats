#!/usr/bin/env bats
# UC fd678b04 × tier-facade: gateway 層 runner --help 問い合わせの単体テスト(外部プロセスは実体のスタブで検証)。

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/gateway/runner_probe.sh"
	RUNNER="$BATS_TEST_TMPDIR/runner.sh"
}

write_runner() {
	printf '%s\n' "$1" >"$RUNNER"
	chmod +x "$RUNNER"
}

@test "runner_probe_if_version_helpがrunner-if-version=1を返す場合_1を出力すること" {
	# Arrange
	write_runner '#!/usr/bin/env bash
if [ "${1:-}" = "--help" ]; then echo "usage: runner.sh"; echo "runner-if-version=1"; exit 0; fi
exit 6'

	# Act
	run runner_probe_if_version "$RUNNER"

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "1" ]
}

@test "runner_probe_if_version_helpに応答せず非0で終わる場合_戻り値1で出力なしであること" {
	# Arrange
	write_runner '#!/usr/bin/env bash
echo "error: unknown option" >&2
exit 2'

	# Act
	run runner_probe_if_version "$RUNNER"

	# Assert
	[ "$status" -eq 1 ]
	[ -z "$output" ]
}

@test "runner_probe_if_version_runnerが待機上限内に終了しない場合_強制終了して戻り値1で出力なしであること" {
	# Arrange(--help に応答せず終了しない runner。子プロセスも残さないことを確認する)
	local marker="probe-hang-$$-$BATS_TEST_NUMBER"
	write_runner "#!/usr/bin/env bash
sleep 60 # $marker
"
	local started
	started="$(date +%s)"

	# Act(待機上限 1 秒)
	run runner_probe_if_version "$RUNNER" 1

	# Assert
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[ $(($(date +%s) - started)) -lt 5 ]
	sleep 0.3
	! pgrep -f "$marker" >/dev/null
}

@test "runner_probe_if_version_helpの出力が待機上限内に返る場合_版を出力すること" {
	# Arrange(上限 2 秒に対し 0.2 秒で応答する runner)
	write_runner '#!/usr/bin/env bash
sleep 0.2
echo "runner-if-version=1"
exit 0'

	# Act
	run runner_probe_if_version "$RUNNER" 2

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "1" ]
}

@test "runner_probe_if_version_helpにrunner-if-version行が無い場合_戻り値1であること" {
	# Arrange
	write_runner '#!/usr/bin/env bash
echo "usage: runner.sh"
exit 0'

	# Act
	run runner_probe_if_version "$RUNNER"

	# Assert
	[ "$status" -eq 1 ]
}

# ---- S2 test-scaffold 再実行(spec event 20260917_050000)で追加: 契約 cli-command-contract.yaml validate-config.sh runner_help_probe ----

@test "runner_probe_if_version_待機上限を省略した場合_契約のtimeout_seconds_per_slot=4を既定にすること" {
	# Arrange(契約 runner_help_probe.timeout_seconds_per_slot: 4)

	# Act
	local default_timeout="$RUNNER_PROBE_TIMEOUT_SEC"

	# Assert
	[ "$default_timeout" = "4" ]
}

@test "runner_probe_if_version_版の値の前後に空白がある場合_空白を除いた値を出力すること" {
	# Arrange(契約 runner_help_probe.version_line_selection: `=` より右の前後の空白を除いた文字列を版の値とする)
	write_runner '#!/usr/bin/env bash
printf "runner-if-version= 1 \n"
exit 0'

	# Act
	run runner_probe_if_version "$RUNNER"

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "1" ]
}

@test "runner_probe_if_version_一時ファイルの作成に失敗した場合_戻り値2で空白を含まない理由を出力すること" {
	# Arrange(契約 runner_help_probe.preparation_failure: 未応答と区別する。TMPDIR を存在しないディレクトリにして mktemp を失敗させる)
	write_runner '#!/usr/bin/env bash
echo "runner-if-version=1"
exit 0'
	export TMPDIR="$BATS_TEST_TMPDIR/nonexistent-tmp"

	# Act
	run runner_probe_if_version "$RUNNER"

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "temp-file-create-failed tmpdir=$TMPDIR" ]
}

@test "runner_probe_if_version_版の行が複数ある場合_最初の1行だけを採用すること" {
	# Arrange(契約 runner_help_probe.version_line_selection: 複数行は最初の 1 行を採用し 2 行目以降は無視)
	write_runner '#!/usr/bin/env bash
echo "runner-if-version=1"
echo "runner-if-version=2"
exit 0'

	# Act
	run runner_probe_if_version "$RUNNER"

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "1" ]
}
