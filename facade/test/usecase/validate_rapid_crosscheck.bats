#!/usr/bin/env bats
# UC dcd8234d × tier-facade: usecase 層 ValidateRapidCrosscheckCommand の単体テスト(入力の守備範囲・出力の形)。
# エントリポイント経由で実プロセスとして起動する。I/O 境界は実ファイル(一時ディレクトリ)。
# 仕様: tier-facade.md「コマンド契約」、CLI 契約 commands[validate-config.sh].stdout、config_input_rules(env_files / snapshot / internal_failure)
# 2026-11-10 S2 再生成: feedback run 2〜9 の仕様変更(spec-decision-026 字下げしたコメント行 / 028 同じキーの重複と
#   止めたときの stdout / 029 同じ行のバイト違反の順 / 030 未知キーの warn)に合わせて期待を書き換え・追加した。
#   これらは現行実装との差分として判断記録に残っており、S4 の再実装まで red になる。
# 2026-11-11 S2 再生成: feedback run 20261110_080548(spec-decision-033 --verbose の info 行の文言・出す回・順)に合わせて
#   --verbose のテストを追加し、@ / * のキーのテストに info → warn の順の検証を加えた。
bats_require_minimum_version 1.5.0

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../bin/validate-config.sh"
	ENV_FILE="$BATS_TEST_TMPDIR/rapid-crosscheck.env"
	COMPARE="$BATS_TEST_TMPDIR/compare.sh"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$COMPARE"
	chmod 755 "$COMPARE"
}

# 入力の守備範囲((i) バイト・改行 / (ii) invalid line・同じキーの重複)で止めたときの stdout 固定順 6 行
# (CLI 契約 commands[validate-config.sh].stdout、config_input_rules.env_files。spec-decision-028 の 4)
assert_stopped_stdout() {
	local violations="$1"
	[ "${#lines[@]}" -eq 6 ]
	[ "${lines[0]}" = "config=rapid-crosscheck" ]
	[ "${lines[1]}" = "path: $ENV_FILE" ]
	[ "${lines[2]}" = "command_path: -" ]
	[ "${lines[3]}" = "has_job_id_placeholder=-" ]
	[ "${lines[4]}" = "status=invalid" ]
	[ "${lines[5]}" = "violations=$violations" ]
}

count_lines() {
	local expected="$1" count=0 line
	for line in "${stderr_lines[@]}"; do
		if [ "$line" = "$expected" ]; then
			count=$((count + 1))
		fi
	done
	printf '%s\n' "$count"
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

@test "validate_rapid_crosscheck_同じキーが2行ある場合_duplicate keyで終了コード2になりどちらの値も使わないこと" {
	# Arrange(仕様: config_input_rules.env_files の同じキーの重複。spec-decision-028。後の行の値で検証しない)
	printf 'RAPID_COMPARE_COMMAND=relative.sh\nRAPID_COMPARE_COMMAND=%s {job_id}\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: duplicate key key=RAPID_COMPARE_COMMAND lines=1,2 path: $ENV_FILE" ]
	assert_stopped_stdout 1
}

@test "validate_rapid_crosscheck_invalid lineと前後に空白のある同じキーがある場合_invalid lineの後に重複キーを初出行の昇順で出すこと" {
	# Arrange(仕様: env_files の (ii) は invalid line を行番号の昇順 → duplicate key を重複したキーの初出行の昇順。
	#   キーは前後の空白を除いて大文字小文字を区別した完全一致で比べる。値が同じ行も数える。spec-decision-028 の 1・3)
	{
		printf 'RAPID_COMPARE_COMMAND=%s {job_id}\n' "$COMPARE"
		printf 'not-a-pair\n'
		printf 'RAPID_DB_CONN_REF=rapid_db\n'
		printf ' RAPID_COMPARE_COMMAND =%s {job_id}\n' "$COMPARE"
		printf 'RAPID_DB_CONN_REF=rapid_db\n'
		printf 'rapid_compare_command=%s {job_id}\n' "$COMPARE"
	} >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 3 ]
	[ "${stderr_lines[0]}" = "error: invalid line line=2 path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "error: duplicate key key=RAPID_COMPARE_COMMAND lines=1,4 path: $ENV_FILE" ]
	[ "${stderr_lines[2]}" = "error: duplicate key key=RAPID_DB_CONN_REF lines=3,5 path: $ENV_FILE" ]
	assert_stopped_stdout 3
}

@test "validate_rapid_crosscheck_KEY=VALUEでない行と空白だけの行がある場合_invalid lineを行ごとに出し固定順のstdoutで終了コード2であること" {
	# Arrange
	printf 'RAPID_COMPARE_COMMAND=%s {job_id}\nnot-a-pair\n  \n=value\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert(stdout は spec-decision-028 の 4: 値を使わないときも固定順の行を出す)
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 3 ]
	[ "${stderr_lines[0]}" = "error: invalid line line=2 path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "error: invalid line line=3 path: $ENV_FILE" ]
	[ "${stderr_lines[2]}" = "error: invalid line line=4 path: $ENV_FILE" ]
	assert_stopped_stdout 3
}

@test "validate_rapid_crosscheck_字下げした#行がある場合_コメント行として読み飛ばし終了コード0であること" {
	# Arrange(仕様: env_files のコメント行 = 行の前後の空白(半角空白とタブ)を除いた結果が # で始まる行。
	#   コメント行の中に = があってもコメント行。KEY=#abc はコメント行ではなく値 #abc。spec-decision-026)
	{
		printf '  # memo\n'
		printf '\t# memo\n'
		printf '  # A=B\n'
		printf 'RAPID_DB_CONN_REF=#abc\n'
		printf 'RAPID_COMPARE_COMMAND=%s --job {job_id}\n' "$COMPARE"
	} >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert(コメント行はキーを取り出さないため、"# A" の未知キーの warn も invalid line も出ない)
	[ "$status" -eq 0 ]
	[ "${lines[4]}" = "status=valid" ]
	[ -z "$stderr" ]
}

@test "validate_rapid_crosscheck_キー表に無いキーがある場合_unknown keyをwarnで出して継続し終了コード0であること" {
	# Arrange(仕様: tier-facade.md コマンド契約 stderr、config_files.rapid-crosscheck.env の note。spec-decision-030 の 2・5。
	#   他の読み手が使う RAPID_DB_CONN_REF / RAPID_LEASE_SEC / RAPID_POLL_INTERVAL_SEC は未知キーではない)
	{
		printf 'RAPID_DB_CONN_REF=rapid_db\n'
		printf 'RAPID_LEASE_SEC=600\n'
		printf 'RAPID_POLL_INTERVAL_SEC=30\n'
		printf 'RAPID_FOO=bar\n'
		printf 'RAPID_COMPARE_COMMAND=%s --job {job_id}\n' "$COMPARE"
	} >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert(warn は終了コード・violations に数えない)
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 5 ]
	[ "${lines[4]}" = "status=valid" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "warn: unknown key key=RAPID_FOO path: $ENV_FILE" ]
}

@test "validate_rapid_crosscheck_CRLF改行の場合_carriage returnで拒否しhintを1回出し固定順のstdoutを出すこと" {
	# Arrange
	printf 'RAPID_DB_CONN_REF=rapid_db\r\nRAPID_COMPARE_COMMAND=%s {job_id}\r\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert(violations は hint を数えない。config_input_rules.byte_checks.violations)
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 3 ]
	[ "${stderr_lines[0]}" = "error: carriage return is not allowed line=1 path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "error: carriage return is not allowed line=2 path: $ENV_FILE" ]
	[ "${stderr_lines[2]}" = "hint: use LF line endings" ]
	assert_stopped_stdout 2
}

@test "validate_rapid_crosscheck_1行目にNULとUTF-8違反とBOMとCRが重なる場合_NUL_UTF-8_BOM_CRの順に1種類1行で出すこと" {
	# Arrange(仕様: config_input_rules.byte_checks.order。同じ行は NUL → UTF-8 → BOM → CR。spec-decision-029 の 8)
	printf '\xef\xbb\xbfRAPID_DB_CONN_REF=a\000b\xff\r\nRAPID_COMPARE_COMMAND=%s {job_id}\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 5 ]
	[ "${stderr_lines[0]}" = "error: nul byte is not allowed line=1 path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "error: encoding is not utf-8 line=1 path: $ENV_FILE" ]
	[ "${stderr_lines[2]}" = "error: byte order mark is not allowed line=1 path: $ENV_FILE" ]
	[ "${stderr_lines[3]}" = "error: carriage return is not allowed line=1 path: $ENV_FILE" ]
	[ "${stderr_lines[4]}" = "hint: use LF line endings" ]
	assert_stopped_stdout 4
}

@test "validate_rapid_crosscheck_BOMやNULを含む場合_原因ごとの文言で拒否すること" {
	# Arrange
	printf '\xef\xbb\xbfRAPID_DB_CONN_REF=rapid_db\nRAPID_COMPARE_COMMAND=%s {job_id}\000\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: byte order mark is not allowed line=1 path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "error: nul byte is not allowed line=2 path: $ENV_FILE" ]
	assert_stopped_stdout 2
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

@test "validate_rapid_crosscheck_verboseでキーが@や*の場合_ほかのキーと同じくinfoとunknown keyのwarnを1回ずつ出すこと" {
	# Arrange(キーをグロブとして展開しない。@ と * はキー表に無いため未知キーの warn も出る。spec-decision-030)
	printf '@=a\n*=b\nRAPID_COMPARE_COMMAND=%s {job_id}\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE" --verbose

	# Assert(2026-11-11 S2 再生成: info 行をすべて → 未知キーの warn 行をすべての順が仕様に定まった。spec-decision-033)
	[ "$status" -eq 0 ]
	[ "$(count_lines "info: key loaded key=@ path: $ENV_FILE")" -eq 1 ]
	[ "$(count_lines "info: key loaded key=* path: $ENV_FILE")" -eq 1 ]
	[ "$(count_lines "warn: unknown key key=@ path: $ENV_FILE")" -eq 1 ]
	[ "$(count_lines "warn: unknown key key=* path: $ENV_FILE")" -eq 1 ]
	[ "${#stderr_lines[@]}" -eq 5 ]
	[ "${stderr_lines[0]}" = "info: key loaded key=@ path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "info: key loaded key=* path: $ENV_FILE" ]
	[ "${stderr_lines[2]}" = "info: key loaded key=RAPID_COMPARE_COMMAND path: $ENV_FILE" ]
	[ "${stderr_lines[3]}" = "warn: unknown key key=@ path: $ENV_FILE" ]
	[ "${stderr_lines[4]}" = "warn: unknown key key=* path: $ENV_FILE" ]
}

# ---- --verbose の info 行(2026-11-11 S2 再生成で追加。spec-decision-033。
#   仕様: tier-facade.md コマンド契約 stderr、CLI 契約 config_input_rules.env_files「validate-config.sh の --verbose の info 行」)

@test "validate_rapid_crosscheck_verboseで未知キーと検証違反がある場合_info全件_warn全件_errorの順に出しviolationsはerrorだけを数えること" {
	# Arrange
	printf 'ZZ=x\nRAPID_COMPARE_COMMAND=relative\nAA=x\n' >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE" --verbose

	# Assert
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 7 ]
	[ "${stderr_lines[0]}" = "info: key loaded key=ZZ path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "info: key loaded key=RAPID_COMPARE_COMMAND path: $ENV_FILE" ]
	[ "${stderr_lines[2]}" = "info: key loaded key=AA path: $ENV_FILE" ]
	[ "${stderr_lines[3]}" = "warn: unknown key key=ZZ path: $ENV_FILE" ]
	[ "${stderr_lines[4]}" = "warn: unknown key key=AA path: $ENV_FILE" ]
	[ "${stderr_lines[5]}" = "error: path is not absolute key=RAPID_COMPARE_COMMAND path=relative" ]
	[ "${stderr_lines[6]}" = "error: placeholder {job_id} is missing key=RAPID_COMPARE_COMMAND value=relative" ]
	[ "${#lines[@]}" -eq 6 ]
	[ "${lines[2]}" = "command_path: relative" ]
	[ "${lines[3]}" = "has_job_id_placeholder=false" ]
	[ "${lines[4]}" = "status=invalid" ]
	[ "${lines[5]}" = "violations=2" ]
}

@test "validate_rapid_crosscheck_verboseで値が空のキーとコメント行がある場合_値が空のキーにもinfoを出しコメント行と値は出さないこと" {
	# Arrange
	printf '# memo\nRAPID_DB_CONN_REF=\nRAPID_COMPARE_COMMAND=%s --job {job_id}\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE" --verbose

	# Assert(--verbose は終了コード・stdout に影響しない)
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 2 ]
	[ "${stderr_lines[0]}" = "info: key loaded key=RAPID_DB_CONN_REF path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "info: key loaded key=RAPID_COMPARE_COMMAND path: $ENV_FILE" ]
	local verbose_output="$output"
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"
	[ "$status" -eq 0 ]
	[ "$output" = "$verbose_output" ]
}

@test "validate_rapid_crosscheck_verboseでinvalid lineがある場合_infoとwarnを出さずinvalid lineだけを出すこと" {
	# Arrange
	printf 'ZZ=x\nbroken\nRAPID_COMPARE_COMMAND=%s --job {job_id}\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE" --verbose

	# Assert
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: invalid line line=2 path: $ENV_FILE" ]
	assert_stopped_stdout 1
}

@test "validate_rapid_crosscheck_verboseで同じキーが2行ある場合_infoを出さずduplicate keyだけを出すこと" {
	# Arrange
	printf 'ZZ=x\nRAPID_COMPARE_COMMAND=%s --job {job_id}\nRAPID_COMPARE_COMMAND=%s --job {job_id}\n' "$COMPARE" "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE" --verbose

	# Assert
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: duplicate key key=RAPID_COMPARE_COMMAND lines=2,3 path: $ENV_FILE" ]
	assert_stopped_stdout 1
}

@test "validate_rapid_crosscheck_verboseでCR改行がある場合_infoを出さずcarriage returnとhintだけを出すこと" {
	# Arrange
	printf 'ZZ=x\r\nRAPID_COMPARE_COMMAND=%s --job {job_id}\n' "$COMPARE" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE" --verbose

	# Assert
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: carriage return is not allowed line=1 path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "hint: use LF line endings" ]
	assert_stopped_stdout 1
}

@test "validate_rapid_crosscheck_5000行で未知キーが4999行のenvの場合_10秒以内に検証を終え未知キーを全件warnで出すこと" {
	# Arrange(NFR B.1.1.2 の共通前提: 1 ファイル最大 5,000 行・内容によらず 10 秒。
	#   重複検査・未知キーの warn をすべての行に対して行う最悪ケース)
	local i
	{
		for ((i = 1; i < 5000; i++)); do
			printf 'RAPID_UNKNOWN_%s=value-%s\n' "$i" "$i"
		done
		printf 'RAPID_COMPARE_COMMAND=%s --job {job_id} --run {run_id} {params}\n' "$COMPARE"
	} >"$ENV_FILE"

	# Act
	local started=$SECONDS
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ $((SECONDS - started)) -lt 10 ]
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 4999 ]
	[ "${stderr_lines[0]}" = "warn: unknown key key=RAPID_UNKNOWN_1 path: $ENV_FILE" ]
}

@test "validate_rapid_crosscheck_5000行すべてが同じキーのenvの場合_10秒以内に重複キーを1行で出し終了コード2であること" {
	# Arrange(NFR B.1.1.2 の共通前提: 1 ファイル最大 5,000 行・内容によらず 10 秒。重複の行番号を全件並べる最悪ケース)
	local i expected_lines
	for ((i = 0; i < 5000; i++)); do
		printf 'RAPID_COMPARE_COMMAND=%s --job {job_id} --run {run_id} {params}\n' "$COMPARE"
	done >"$ENV_FILE"
	# BSD seq -s は末尾にも区切りを付けるため、行番号の並びは bash だけで組み立てる
	expected_lines=1
	for ((i = 2; i <= 5000; i++)); do
		expected_lines+=",$i"
	done

	# Act
	local started=$SECONDS
	run --separate-stderr "$SCRIPT" --rapid-crosscheck "$ENV_FILE"

	# Assert
	[ $((SECONDS - started)) -lt 10 ]
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: duplicate key key=RAPID_COMPARE_COMMAND lines=$expected_lines path: $ENV_FILE" ]
	assert_stopped_stdout 1
}
