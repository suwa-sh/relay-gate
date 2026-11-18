#!/usr/bin/env bats
# UC 09730858(slot 実行モードを選択して runner を起動する)× tier-facade: domain/feature_flag.sh の feature_flag_flush_first_violation。
# 対象: 契約 commands の facade.sh の config_violation_report(最初の違反の error 行と、続く hint だけを出す)。

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/feature_flag.sh"
	FEATURE_FLAG_REPORT_SINK="$FEATURE_FLAG_REPORT_SINK_ARRAY"
	feature_flag_reset_report_lines
}

@test "feature_flag_flush_first_violation_最初の違反にhintが続く場合_error行とhintの2行だけを出すこと" {
	# Arrange
	validate_feature_flag_mode_key RAPID_CROSSCHECK_MODE ff.env maybe || true
	feature_flag_emit "error: option required option=BLUE_IMPL path: ff.env"

	# Act
	run feature_flag_flush_first_violation

	# Assert
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe" ]
	[ "${lines[1]}" = "hint: use foreground, background or off" ]
}

@test "feature_flag_flush_first_violation_最初の違反にhintが続かない場合_error行の1行だけを出すこと" {
	# Arrange
	feature_flag_emit "error: file not executable key=BLUE_RUNNER path=/etc/relay-gate/relative/blue-runner.sh"
	feature_flag_emit "error: option required option=GREEN_IMPL path: ff.env"

	# Act
	run feature_flag_flush_first_violation

	# Assert
	[ "$output" = "error: file not executable key=BLUE_RUNNER path=/etc/relay-gate/relative/blue-runner.sh" ]
}

@test "feature_flag_flush_first_violation_値の表示を後回しにした長い値の行の場合_値を付けて1行で出すこと" {
	# Arrange(FEATURE_FLAG_REPORT_DEFERRED_MIN_BYTES 以上の値は、出すときに可視表記を付ける)
	local long
	printf -v long '%*s' "$FEATURE_FLAG_REPORT_DEFERRED_MIN_BYTES" ''
	long="${long// /a}"
	feature_flag_emit_value_line "error: invalid value key=BLUE_MODE value=" "$long"
	feature_flag_emit "$FEATURE_FLAG_MODE_HINT"

	# Act
	run feature_flag_flush_first_violation

	# Assert
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "error: invalid value key=BLUE_MODE value=$long" ]
	[ "${lines[1]}" = "$FEATURE_FLAG_MODE_HINT" ]
}

@test "feature_flag_flush_first_violation_出した後_報告行の配列が空になること" {
	# Arrange
	feature_flag_emit "error: option required option=BLUE_MODE path: ff.env"

	# Act
	feature_flag_flush_first_violation >/dev/null

	# Assert
	[ "${#FEATURE_FLAG_REPORT_LINES[@]}" -eq 0 ]
}
