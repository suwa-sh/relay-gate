#!/usr/bin/env bats
# UC dcd8234d × tier-facade: presentation 層 validate-config.sh --rapid-crosscheck の単体テスト
# (S2 test-scaffold の red baseline。S4 で green にする)。
# エントリポイント(bin/validate-config.sh)経由で実プロセスとして起動する。I/O 境界は実ファイル(一時ディレクトリ)。
# 仕様: tier-facade.md「コマンド契約 / 検証ルール(domain: launch_command_rules)」
# 比較ツールは外部システムのため、一時ディレクトリに exit 0 の実行可能スタブを置く。
bats_require_minimum_version 1.5.0

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../bin/validate-config.sh"
	ENV_FILE="$BATS_TEST_TMPDIR/rapid-crosscheck.env"
	COMPARE="$BATS_TEST_TMPDIR/compare.sh"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$COMPARE"
	chmod 755 "$COMPARE"
}

write_env() {
	printf 'RAPID_DB_CONN_REF=rapid_db\nRAPID_COMPARE_COMMAND=%s\n' "$1" >"$ENV_FILE"
}

@test "validate-config_sh_--rapid-crosscheckで絶対パスで実行可能かつjob_idを含む場合_終了コード0で固定順のstdoutを出すこと" {
	# Arrange
	write_env "$COMPARE --job {job_id} --run {run_id}"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 5 ]
	[ "${lines[0]}" = "config=rapid-crosscheck" ]
	[ "${lines[1]}" = "path: $ENV_FILE" ]
	[ "${lines[2]}" = "command_path: $COMPARE" ]
	[ "${lines[3]}" = "has_job_id_placeholder=true" ]
	[ "${lines[4]}" = "status=valid" ]
	[ -z "$stderr" ]
}

@test "validate-config_sh_--rapid-crosscheckでコマンド部分が存在しない場合_file not executableで終了コード2であること" {
	# Arrange
	missing="$BATS_TEST_TMPDIR/missing.sh"
	write_env "$missing --job {job_id}"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: file not executable key=RAPID_COMPARE_COMMAND path=$missing" ]
}

@test "validate-config_sh_--rapid-crosscheckでコマンド部分が絶対パスでない場合_path is not absoluteで終了コード2であること" {
	# Arrange
	write_env "compare.sh --job {job_id}"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: path is not absolute key=RAPID_COMPARE_COMMAND path=compare.sh" ]
}

@test "validate-config_sh_--rapid-crosscheckでjob_idを含まない場合_placeholder job_id is missingで終了コード2であること" {
	# Arrange
	write_env "$COMPARE --run {run_id}"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=$COMPARE --run {run_id}" ]
}

@test "validate-config_sh_--rapid-crosscheckでparamsが引数の一部にある場合_must be a whole argumentで終了コード2であること" {
	# Arrange
	write_env "$COMPARE --job {job_id} --args={params}"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=$COMPARE --job {job_id} --args={params}" ]
}

@test "validate-config_sh_--rapid-crosscheckでparamsが独立した1引数の場合_終了コード0でstatus=validを出すこと" {
	# Arrange
	write_env "$COMPARE --job {job_id} {params}"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[4]}" = "status=valid" ]
	[ -z "$stderr" ]
}

@test "validate-config_sh_--rapid-crosscheckで引数部分に存在しないパスや未知の語がある場合_引数部分を検査せず終了コード0であること" {
	# Arrange(ほかの引数部分の内容は検査しない。記号を含む値も拒否しない)
	write_env "$COMPARE --job {job_id} --ref /no/such/path unknown-word ;&|"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[2]}" = "command_path: $COMPARE" ]
	[ "${lines[4]}" = "status=valid" ]
	[ -z "$stderr" ]
}
