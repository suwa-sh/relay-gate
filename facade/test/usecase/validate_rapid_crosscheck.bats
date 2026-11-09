#!/usr/bin/env bats
# UC dcd8234d × tier-facade: usecase 層 ValidateRapidCrosscheckCommand の単体テスト(入力の守備範囲・出力の形)。
# エントリポイント経由で実プロセスとして起動する。I/O 境界は実ファイル(一時ディレクトリ)。
# 仕様: tier-facade.md「コマンド契約」、CLI 契約 commands[validate-config.sh].stdout、config_input_rules(env_files / snapshot / internal_failure)
bats_require_minimum_version 1.5.0

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../bin/validate-config.sh"
	ENV_FILE="$BATS_TEST_TMPDIR/rapid-crosscheck.env"
	COMPARE="$BATS_TEST_TMPDIR/compare.sh"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$COMPARE"
	chmod 755 "$COMPARE"
}

@test "validate_rapid_crosscheck_ファイルが無い場合_config file not foundで終了コード2でstdoutは空であること" {
	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$BATS_TEST_TMPDIR/none.env"

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "$stderr" = "error: config file not found path: $BATS_TEST_TMPDIR/none.env" ]
}

@test "validate_rapid_crosscheck_値が無い場合_option requiredで終了コード2であること" {
	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck

	# Assert
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: option required option=--rapid-crosscheck" ]
}

@test "validate_rapid_crosscheck_違反がある場合_stdoutにstatus=invalidとviolations=Nを固定順で出すこと" {
	# Arrange
	printf 'RAPID_COMPARE_COMMAND=compare.sh --run {run_id}\n' >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ "${#lines[@]}" -eq 6 ]
	[ "${lines[0]}" = "config=rapid-crosscheck" ]
	[ "${lines[1]}" = "path: $ENV_FILE" ]
	[ "${lines[2]}" = "command_path: compare.sh" ]
	[ "${lines[3]}" = "has_job_id_placeholder=false" ]
	[ "${lines[4]}" = "status=invalid" ]
	[ "${lines[5]}" = "violations=2" ]
	[ "${#stderr_lines[@]}" -eq 2 ]
}

@test "validate_rapid_crosscheck_RAPID_COMPARE_COMMANDが無い場合_option requiredとcommand_path -を出すこと" {
	# Arrange
	printf 'RAPID_DB_CONN_REF=rapid_db\n# comment\n\n' >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: option required option=RAPID_COMPARE_COMMAND path: $ENV_FILE" ]
	[ "${lines[2]}" = "command_path: -" ]
	[ "${lines[5]}" = "violations=1" ]
}

@test "validate_rapid_crosscheck_値が引用符で囲まれ最終行に改行が無い場合_引用符を除いて検証すること" {
	# Arrange
	printf 'RAPID_COMPARE_COMMAND="%s --job {job_id}"' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[2]}" = "command_path: $COMPARE" ]
	[ "${lines[4]}" = "status=valid" ]
}

@test "validate_rapid_crosscheck_同じキーが重複した場合_後の行の値で検証すること" {
	# Arrange
	printf 'RAPID_COMPARE_COMMAND=relative.sh\nRAPID_COMPARE_COMMAND=%s {job_id}\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[2]}" = "command_path: $COMPARE" ]
}

@test "validate_rapid_crosscheck_KEY=VALUEでない行と空白だけの行がある場合_invalid lineを行ごとに出し終了コード2であること" {
	# Arrange
	printf 'RAPID_COMPARE_COMMAND=%s {job_id}\nnot-a-pair\n  \n=value\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 3 ]
	[ "${stderr_lines[0]}" = "error: invalid line line=2 path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "error: invalid line line=3 path: $ENV_FILE" ]
	[ "${stderr_lines[2]}" = "error: invalid line line=4 path: $ENV_FILE" ]
}

@test "validate_rapid_crosscheck_CRLF改行の場合_carriage returnで拒否しhintを1回出すこと" {
	# Arrange
	printf 'RAPID_DB_CONN_REF=rapid_db\r\nRAPID_COMPARE_COMMAND=%s {job_id}\r\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${stderr_lines[0]}" = "error: carriage return is not allowed line=1 path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "error: carriage return is not allowed line=2 path: $ENV_FILE" ]
	[ "${stderr_lines[2]}" = "hint: use LF line endings" ]
}

@test "validate_rapid_crosscheck_BOMやNULを含む場合_原因ごとの文言で拒否すること" {
	# Arrange
	printf '\xef\xbb\xbfRAPID_DB_CONN_REF=rapid_db\nRAPID_COMPARE_COMMAND=%s {job_id}\000\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: byte order mark is not allowed line=1 path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "error: nul byte is not allowed line=2 path: $ENV_FILE" ]
}

@test "validate_rapid_crosscheck_TMPDIRに書き込めない場合_config snapshot failedで終了コード6でstdoutは空であること" {
	# Arrange
	printf 'RAPID_COMPARE_COMMAND=%s {job_id}\n' "$COMPARE" >"$ENV_FILE"

	# Act
	TMPDIR="$BATS_TEST_TMPDIR/no-such-dir" run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 6 ]
	[ -z "$output" ]
	[ "${stderr_lines[0]}" = "error: config snapshot failed path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "hint: check TMPDIR is writable" ]
}

@test "validate_rapid_crosscheck_読み込み後に複製が残らないこと" {
	# Arrange
	local tmp="$BATS_TEST_TMPDIR/snap"
	mkdir "$tmp"
	printf 'RAPID_COMPARE_COMMAND=%s {job_id}\n' "$COMPARE" >"$ENV_FILE"

	# Act
	TMPDIR="$tmp" run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$(ls -A "$tmp")" ]
}

@test "validate_rapid_crosscheck_verboseの場合_読み込んだキーをinfoでstderrに出し終了コードは変わらないこと" {
	# Arrange
	printf 'RAPID_DB_CONN_REF=rapid_db\nRAPID_COMPARE_COMMAND=%s {job_id}\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE" --verbose

	# Assert
	[ "$status" -eq 0 ]
	[ "${stderr_lines[0]}" = "info: key loaded key=RAPID_DB_CONN_REF path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "info: key loaded key=RAPID_COMPARE_COMMAND path: $ENV_FILE" ]
}

@test "validate_rapid_crosscheck_feature-flagと併用した場合_排他違反で終了コード2であること" {
	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE" --feature-flag a.env

	# Assert
	[ "$status" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: options are exclusive options=--rapid-crosscheck,--feature-flag" ]
}

@test "validate_rapid_crosscheck_verboseでキーが@や*の場合_ほかのキーと同じくinfoに1回ずつ出すこと" {
	# Arrange
	printf '@=a\n*=b\n@=c\nRAPID_COMPARE_COMMAND=%s {job_id}\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE" --verbose

	# Assert
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 3 ]
	[ "${stderr_lines[0]}" = "info: key loaded key=@ path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "info: key loaded key=* path: $ENV_FILE" ]
}

@test "validate_rapid_crosscheck_5000行のenvの場合_10秒以内に検証を終えること" {
	# Arrange(NFR B.1.1.2 の共通前提: 1 ファイル最大 5,000 行。全行が RAPID_COMPARE_COMMAND の最悪ケース)
	local i
	for ((i = 0; i < 5000; i++)); do
		printf 'RAPID_COMPARE_COMMAND=%s --job {job_id} --run {run_id} {params}\n' "$COMPARE"
	done >"$ENV_FILE"

	# Act
	local started=$SECONDS
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE" --verbose

	# Assert
	[ "$status" -eq 0 ]
	[ $((SECONDS - started)) -lt 10 ]
}
