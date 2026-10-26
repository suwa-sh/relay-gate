#!/usr/bin/env bats
# UC dcd8234d × tier-facade: domain 層 LaunchCommandRules(launch_command.sh)の単体テスト。
# 仕様: tier-facade.md「検証ルール(domain: launch_command_rules)」、CLI 契約 shared_rules.compare_command_argv
bats_require_minimum_version 1.5.0

setup() {
	# shellcheck source=../../src/domain/cli_field.sh
	source "$BATS_TEST_DIRNAME/../../src/domain/cli_field.sh"
	# shellcheck source=../../src/domain/launch_command.sh
	source "$BATS_TEST_DIRNAME/../../src/domain/launch_command.sh"
	COMPARE="$BATS_TEST_TMPDIR/compare.sh"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$COMPARE"
	chmod 755 "$COMPARE"
}

@test "launch_command_split_スペースとタブの連続を1つの区切りとして扱う場合_空の引数を作らないこと" {
	# Arrange
	local value=$'  /a/b.sh \t --job\t\t{job_id}   x  '

	# Act
	launch_command_split "$value"

	# Assert
	[ "${#LAUNCH_COMMAND_ARGV[@]}" -eq 4 ]
	[ "${LAUNCH_COMMAND_ARGV[0]}" = "/a/b.sh" ]
	[ "${LAUNCH_COMMAND_ARGV[1]}" = "--job" ]
	[ "${LAUNCH_COMMAND_ARGV[2]}" = "{job_id}" ]
	[ "${LAUNCH_COMMAND_ARGV[3]}" = "x" ]
}

@test "launch_command_split_引用符やシェル記法を含む場合_解釈せず引数の中の文字として扱うこと" {
	# Arrange
	local value='/a/b.sh "x y" \$HOME * ;|&'

	# Act
	launch_command_split "$value"

	# Assert(引用符は区切りを変えない。* はパス名展開しない)
	[ "${#LAUNCH_COMMAND_ARGV[@]}" -eq 6 ]
	[ "${LAUNCH_COMMAND_ARGV[1]}" = '"x' ]
	[ "${LAUNCH_COMMAND_ARGV[2]}" = 'y"' ]
	[ "${LAUNCH_COMMAND_ARGV[3]}" = '\$HOME' ]
	[ "${LAUNCH_COMMAND_ARGV[4]}" = '*' ]
	[ "${LAUNCH_COMMAND_ARGV[5]}" = ';|&' ]
}

@test "launch_command_rules_キーが無い場合_option requiredだけを出し違反1件であること" {
	# Act
	run launch_command_rules false "" "r.env"
	launch_command_rules false "" "r.env" || true

	# Assert
	[ "$status" -eq 1 ]
	[ "${#LAUNCH_COMMAND_REPORT_LINES[@]}" -eq 1 ]
	[ "${LAUNCH_COMMAND_REPORT_LINES[0]}" = "error: option required option=RAPID_COMPARE_COMMAND path: r.env" ]
	[ "$LAUNCH_COMMAND_VIOLATIONS" -eq 1 ]
	[ -z "$LAUNCH_COMMAND_PATH" ]
	[ "$LAUNCH_COMMAND_HAS_JOB_ID" = false ]
}

@test "launch_command_rules_値が空白だけの場合_空とみなしoption requiredであること" {
	# Act
	launch_command_rules true $' \t ' "r.env" || true

	# Assert
	[ "${LAUNCH_COMMAND_REPORT_LINES[0]}" = "error: option required option=RAPID_COMPARE_COMMAND path: r.env" ]
	[ "$LAUNCH_COMMAND_VIOLATIONS" -eq 1 ]
}

@test "launch_command_rules_コマンド部分が実行権限の無いファイルの場合_file not executableであること" {
	# Arrange
	local plain="$BATS_TEST_TMPDIR/plain.sh"
	printf 'exit 0\n' >"$plain"
	chmod 644 "$plain"

	# Act
	launch_command_rules true "$plain --job {job_id}" "r.env" || true

	# Assert
	[ "${LAUNCH_COMMAND_REPORT_LINES[*]}" = "error: file not executable key=RAPID_COMPARE_COMMAND path=$plain" ]
}

@test "launch_command_rules_コマンド部分がディレクトリの場合_file not executableであること" {
	# Act
	launch_command_rules true "$BATS_TEST_TMPDIR --job {job_id}" "r.env" || true

	# Assert
	[ "${LAUNCH_COMMAND_REPORT_LINES[*]}" = "error: file not executable key=RAPID_COMPARE_COMMAND path=$BATS_TEST_TMPDIR" ]
}

@test "launch_command_rules_複数のルールに違反する場合_全件をルール順に出すこと" {
	# Act
	launch_command_rules true "compare.sh --args={params}" "r.env" || true

	# Assert
	[ "$LAUNCH_COMMAND_VIOLATIONS" -eq 3 ]
	[ "${LAUNCH_COMMAND_REPORT_LINES[0]}" = "error: path is not absolute key=RAPID_COMPARE_COMMAND path=compare.sh" ]
	[ "${LAUNCH_COMMAND_REPORT_LINES[1]}" = "error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=compare.sh --args={params}" ]
	[ "${LAUNCH_COMMAND_REPORT_LINES[2]}" = "error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=compare.sh --args={params}" ]
	[ "$LAUNCH_COMMAND_PATH" = "compare.sh" ]
}

@test "launch_command_rules_job_idが引数の一部にある場合_含むとみなし違反なしであること" {
	# Act
	launch_command_rules true "$COMPARE --job={job_id} {run_id} {blue_exit_code}" "r.env"

	# Assert
	[ "$LAUNCH_COMMAND_VIOLATIONS" -eq 0 ]
	[ "$LAUNCH_COMMAND_HAS_JOB_ID" = true ]
	[ "$LAUNCH_COMMAND_PATH" = "$COMPARE" ]
	[ "${#LAUNCH_COMMAND_REPORT_LINES[@]}" -eq 0 ]
}

@test "launch_command_rules_paramsが2回とも独立した引数の場合_違反なしであること" {
	# Act
	launch_command_rules true "$COMPARE {job_id} {params} {params}" "r.env"

	# Assert
	[ "$LAUNCH_COMMAND_VIOLATIONS" -eq 0 ]
}

@test "launch_command_rules_paramsが前後に文字を伴う場合_引数全体でない位置として違反であること" {
	# Act
	launch_command_rules true "$COMPARE {job_id} {params}x" "r.env" || true

	# Assert
	[ "$LAUNCH_COMMAND_VIOLATIONS" -eq 1 ]
	[ "${LAUNCH_COMMAND_REPORT_LINES[0]}" = "error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=$COMPARE {job_id} {params}x" ]
}
