#!/usr/bin/env bats
# UC fd678b04 × tier-facade: validate-config.sh --feature-flag の入力の守備範囲と --verbose の info 行の単体テスト。
# エントリポイント経由で実プロセスとして起動する。I/O 境界は実ファイル(一時ディレクトリ)。
# 仕様: tier-facade.md「設定契約」「出力契約」「UC ロジック」、CLI 契約 config_input_rules
#       (rules / byte_checks / snapshot / internal_failure / env_files)、conventions.output_format.control_chars
# 2026-11-13 S2 再実行で追加: 2026-09 の完了後に env 形式の全設定ファイルへ共通化された規則
#   (検査の段 (i) バイト・改行 → (ii) invalid line・同じキーの重複 → (iii) キーごとの検査、
#    --verbose の info 行の文言・出す回・順。spec-decision-023 / 026 / 028〜031 / 033)を --feature-flag に適用する。
#   現行実装(facade/src/)は未追従で、S4 の再実行まで red になるテストを含む。
# error 行が 2 行以上出るときの error 行どうしの順は、(i)(ii) の段の中だけを検証する
#   ((iii) のキーごとの検査の error 行どうしの順は、このファイルを書いた時点では仕様に定めが無かったため固定していない。
#    docs/impl/latest/fd678b04/issues/20261113_021600_feature-flag-error-line-order-undefined.md。
#    2026-11-15 に CLI 契約 config_files.feature-flag.env.error_order が定めた。その順の検証は validate_feature_flag_error_order.bats)
bats_require_minimum_version 1.5.0

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../bin/validate-config.sh"
	CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	mkdir -p "$CONFIG_DIR"
	export RELAY_GATE_CONFIG_DIR="$CONFIG_DIR"
	ENV_FILE="$BATS_TEST_TMPDIR/ff.env"
	RUNNER="$BATS_TEST_TMPDIR/runner.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'if [ "${1:-}" = "--help" ]; then echo "runner-if-version=1"; exit 0; fi' 'exit 6' >"$RUNNER"
	chmod +x "$RUNNER"
	SILENT_RUNNER="$BATS_TEST_TMPDIR/silent.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$SILENT_RUNNER"
	chmod +x "$SILENT_RUNNER"
	touch "$CONFIG_DIR/green-job-map.csv"
}

# 有効な単独本番設定(5 行。単体なら終了コード 0・operation_mode=green_only)
write_green_only_env() {
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=%s\n' "$RUNNER" >"$ENV_FILE"
}

# ---- (i) バイト・改行の検査(config_input_rules.byte_checks) ----

@test "validate-config_sh_--feature-flagで全行がCRLF改行の場合_行ごとにcarriage returnを出しhintを最後に1回出して終了コード2であること" {
	# Arrange
	printf 'BLUE_MODE=off\r\nGREEN_MODE=foreground\r\nRAPID_CROSSCHECK_MODE=off\r\nGREEN_IMPL=green-1.4.0\r\nGREEN_RUNNER=%s\r\n' "$RUNNER" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(CR を黙って落として受理しない。--feature-flag の stdout は検証 OK のときだけ)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 6 ]
	[ "${stderr_lines[0]}" = "error: carriage return is not allowed line=1 path: $ENV_FILE" ]
	[ "${stderr_lines[4]}" = "error: carriage return is not allowed line=5 path: $ENV_FILE" ]
	[ "${stderr_lines[5]}" = "hint: use LF line endings" ]
}

@test "validate-config_sh_--feature-flagでBOMとNULとUTF-8違反とCRが複数行にある場合_行番号の昇順で同じ行はNUL_UTF-8_BOM_CRの順に出すこと" {
	# Arrange(契約 config_input_rules.byte_checks.example と同じ並び: 1 行目 BOM + CRLF、2 行目 NUL + 不正な UTF-8 + CR、
	#   3 行目 CR、4 行目 NUL。2・4 行目はコメント行(コメント行も検査する))
	printf '\xef\xbb\xbfBLUE_MODE=off\r\n# a\000\xff\r\nGREEN_MODE=sideways\r\n# b\000\n' >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(hint は最後の CR の error 行の直後。(i) で止め、列挙外の GREEN_MODE や必須キーの欠落は報告しない)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 8 ]
	[ "${stderr_lines[0]}" = "error: byte order mark is not allowed line=1 path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "error: carriage return is not allowed line=1 path: $ENV_FILE" ]
	[ "${stderr_lines[2]}" = "error: nul byte is not allowed line=2 path: $ENV_FILE" ]
	[ "${stderr_lines[3]}" = "error: encoding is not utf-8 line=2 path: $ENV_FILE" ]
	[ "${stderr_lines[4]}" = "error: carriage return is not allowed line=2 path: $ENV_FILE" ]
	[ "${stderr_lines[5]}" = "error: carriage return is not allowed line=3 path: $ENV_FILE" ]
	[ "${stderr_lines[6]}" = "hint: use LF line endings" ]
	[ "${stderr_lines[7]}" = "error: nul byte is not allowed line=4 path: $ENV_FILE" ]
}

@test "validate-config_sh_--feature-flagで有効な設定のコメント行だけにUTF-8違反がある場合_encoding is not utf-8で終了コード2であること" {
	# Arrange(文字コードの検査はコメント行を含む)
	write_green_only_env
	printf '# memo \xff\xfe\n' >>"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: encoding is not utf-8 line=6 path: $ENV_FILE" ]
}

@test "validate-config_sh_--feature-flagで最終行に改行が無い有効な設定の場合_終了コード0であること" {
	# Arrange(config_input_rules.rules「最終行の改行なし」は受理)
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=%s' "$RUNNER" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 15 ]
	[ "${lines[10]}" = "operation_mode=green_only" ]
	[ "${#stderr_lines[@]}" -eq 0 ]
}

# ---- (ii) 行の構造の検査(config_input_rules.env_files) ----

@test "validate-config_sh_--feature-flagで=の無い行と空白だけの行とキーが空の行がある場合_invalid lineを行番号の昇順に全件出して終了コード2であること" {
	# Arrange(2 行目 `broken`、4 行目 空白だけ、6 行目 ` =abc`。値の取り出しとキーごとの検査は行わない)
	printf 'BLUE_MODE=parallel\nbroken\nGREEN_MODE=foreground\n \t \nRAPID_CROSSCHECK_MODE=off\n =abc\n' >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(1 行目の列挙外 BLUE_MODE=parallel は (iii) のため報告しない)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 3 ]
	[ "${stderr_lines[0]}" = "error: invalid line line=2 path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "error: invalid line line=4 path: $ENV_FILE" ]
	[ "${stderr_lines[2]}" = "error: invalid line line=6 path: $ENV_FILE" ]
}

@test "validate-config_sh_--feature-flagでinvalid lineと同じキーの重複がある場合_invalid lineの後に重複キーを初出行の昇順で出すこと" {
	# Arrange(契約 config_input_rules.env_files の例と同じ 5 行。3 行目は invalid line でキーを持たず重複に数えない)
	printf 'BLUE_MODE=foreground\nGREEN_MODE=background\nBLUE_MODE\nBLUE_MODE=off\nGREEN_MODE=background\n' >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert((iii) を行わないため option required などは出ない)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 3 ]
	[ "${stderr_lines[0]}" = "error: invalid line line=3 path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "error: duplicate key key=BLUE_MODE lines=1,4 path: $ENV_FILE" ]
	[ "${stderr_lines[2]}" = "error: duplicate key key=GREEN_MODE lines=2,5 path: $ENV_FILE" ]
}

@test "validate-config_sh_--feature-flagで有効な設定の末尾に同じ値の同じキーを加えた場合_後の行を採らずduplicate keyだけで終了コード2であること" {
	# Arrange(値が同じでも重複。lines= は初出行を含む全行番号)
	write_green_only_env
	printf 'GREEN_MODE=foreground\n' >>"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: duplicate key key=GREEN_MODE lines=2,6 path: $ENV_FILE" ]
}

@test "validate-config_sh_--feature-flagで字下げした#行と=を含むコメント行がある場合_コメント行として読み飛ばし終了コード0であること" {
	# Arrange(コメント行の判定は = での分割より先。`KEY=#abc` は値)
	write_green_only_env
	printf '  # x\n\t# BLUE_MODE=foreground\n # GREEN_MODE=off\n' >>"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[10]}" = "operation_mode=green_only" ]
	[ "${#stderr_lines[@]}" -eq 0 ]
}

# ---- (iii) の中の順と --verbose の info 行(config_input_rules.env_files「validate-config.sh の --verbose の info 行」) ----

@test "validate-config_sh_--feature-flagで未知キーと検証違反がある場合_未知キーのwarnをキーごとの検査のerrorより先に出すこと" {
	# Arrange(--verbose が無いときは info 行だけが無くなり、ほかの行とその順は変わらない)
	printf 'ZZ=x\nBLUE_MODE=off\nGREEN_MODE=off\nRAPID_CROSSCHECK_MODE=off\n' >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 2 ]
	[ "${stderr_lines[0]}" = "warn: unknown key key=ZZ path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "error: foreground slot must be exactly one blue_mode=off green_mode=off" ]
}

@test "validate-config_sh_--feature-flagのverboseで未知キーと検証違反がある場合_info全件_warn全件_errorの順に出すこと" {
	# Arrange(契約 config_input_rules.env_files の例 3 と同じ 4 行)
	printf 'ZZ=x\nBLUE_MODE=off\nGREEN_MODE=off\nRAPID_CROSSCHECK_MODE=off\n' >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE" --verbose

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 6 ]
	[ "${stderr_lines[0]}" = "info: key loaded key=ZZ path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "info: key loaded key=BLUE_MODE path: $ENV_FILE" ]
	[ "${stderr_lines[2]}" = "info: key loaded key=GREEN_MODE path: $ENV_FILE" ]
	[ "${stderr_lines[3]}" = "info: key loaded key=RAPID_CROSSCHECK_MODE path: $ENV_FILE" ]
	[ "${stderr_lines[4]}" = "warn: unknown key key=ZZ path: $ENV_FILE" ]
	[ "${stderr_lines[5]}" = "error: foreground slot must be exactly one blue_mode=off green_mode=off" ]
}

@test "validate-config_sh_--feature-flagのverboseで未知キーが2つとFINAL_で始まるキーと値が空のキーがある場合_全キーのinfoの後に未知キーのwarnを初出順に出しFINAL_キーはerrorだけであること" {
	# Arrange(info の対象はコメント行を除く全キー。未知キー・値が空のキー・FINAL_ で始まるキーも含む。値は出さない)
	printf 'ZZ=x\n# memo\nFINAL_X=1\nBLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=%s\nAA=\n' "$RUNNER" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE" --verbose

	# Assert(error 行は 1 行だけの入力にして、error 行どうしの順には依存しない)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 11 ]
	[ "${stderr_lines[0]}" = "info: key loaded key=ZZ path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "info: key loaded key=FINAL_X path: $ENV_FILE" ]
	[ "${stderr_lines[2]}" = "info: key loaded key=BLUE_MODE path: $ENV_FILE" ]
	[ "${stderr_lines[3]}" = "info: key loaded key=GREEN_MODE path: $ENV_FILE" ]
	[ "${stderr_lines[4]}" = "info: key loaded key=RAPID_CROSSCHECK_MODE path: $ENV_FILE" ]
	[ "${stderr_lines[5]}" = "info: key loaded key=GREEN_IMPL path: $ENV_FILE" ]
	[ "${stderr_lines[6]}" = "info: key loaded key=GREEN_RUNNER path: $ENV_FILE" ]
	[ "${stderr_lines[7]}" = "info: key loaded key=AA path: $ENV_FILE" ]
	[ "${stderr_lines[8]}" = "warn: unknown key key=ZZ path: $ENV_FILE" ]
	[ "${stderr_lines[9]}" = "warn: unknown key key=AA path: $ENV_FILE" ]
	[ "${stderr_lines[10]}" = "error: final crosscheck key is not allowed key=FINAL_X" ]
}

@test "validate-config_sh_--feature-flagのverboseで未知キーがありrunnerがhelpに応答しない場合_info_未知キーのwarn_runnerのwarnの順に出し終了コード0であること" {
	# Arrange(runner --help 問い合わせの warn 行はキーごとの検査のあと)
	printf 'ZZ=x\nBLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=%s\n' "$SILENT_RUNNER" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE" --verbose

	# Assert(info 行と warn 行は終了コードに数えず、stdout を変えない)
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 15 ]
	[ "${lines[14]}" = "green_runner_if_version=-" ]
	[ "${#stderr_lines[@]}" -eq 8 ]
	[ "${stderr_lines[0]}" = "info: key loaded key=ZZ path: $ENV_FILE" ]
	[ "${stderr_lines[5]}" = "info: key loaded key=GREEN_RUNNER path: $ENV_FILE" ]
	[ "${stderr_lines[6]}" = "warn: unknown key key=ZZ path: $ENV_FILE" ]
	[ "${stderr_lines[7]}" = "warn: runner does not respond to --help slot=green runner=$SILENT_RUNNER" ]
}

@test "validate-config_sh_--feature-flagのverboseでinvalid lineがある場合_infoとwarnを出さずinvalid lineだけを出すこと" {
	# Arrange((ii) で止めた回は値を使わないため、キーを読み込んだと示さない)
	printf 'ZZ=x\nbroken\nBLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\n' >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE" --verbose

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: invalid line line=2 path: $ENV_FILE" ]
}

@test "validate-config_sh_--feature-flagのverboseで同じキーが2行ある場合_infoを出さずduplicate keyだけを出すこと" {
	# Arrange
	write_green_only_env
	printf 'ZZ=a\nZZ=b\n' >>"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE" --verbose

	# Assert(未知キーの行も重複に数える。未知キーの warn は出ない)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: duplicate key key=ZZ lines=6,7 path: $ENV_FILE" ]
}

@test "validate-config_sh_--feature-flagのverboseでCR改行がある場合_infoを出さずcarriage returnとhintだけを出すこと" {
	# Arrange((i) で止めた回)
	printf 'ZZ=x\r\nBLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\n' >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE" --verbose

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: carriage return is not allowed line=1 path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "hint: use LF line endings" ]
}

@test "validate-config_sh_--feature-flagのverboseでファイルが無い場合_config file not foundの1行だけを出すこと" {
	# Arrange
	local missing="$BATS_TEST_TMPDIR/nonexistent.env"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$missing" --verbose

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: config file not found path: $missing" ]
}

# ---- 入力の複製(config_input_rules.snapshot / internal_failure) ----

@test "validate-config_sh_--feature-flagのverboseでTMPDIRに書き込めない場合_config snapshot failedとhintだけで終了コード6でstdoutは空であること" {
	# Arrange(入力の複製の失敗。内部障害の回は info 行も他の error / warn 行も出さない)
	write_green_only_env

	# Act
	TMPDIR="$BATS_TEST_TMPDIR/no-such-dir" run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE" --verbose

	# Assert
	[ "$status" -eq 6 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: config snapshot failed path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "hint: check TMPDIR is writable" ]
}

@test "validate-config_sh_--feature-flagで検証を終えた場合_TMPDIRに複製や一時ファイルが残らないこと" {
	# Arrange
	local tmp="$BATS_TEST_TMPDIR/snap"
	mkdir "$tmp"
	write_green_only_env

	# Act
	TMPDIR="$tmp" run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$(ls -A "$tmp")" ]
}

# ---- 制御文字の表記(conventions.output_format.control_chars。key= / value= / path: の任意入力) ----

@test "validate-config_sh_--feature-flagで列挙外の値にESCを含む場合_value=を可視表記で出し生のESCを出さないこと" {
	# Arrange(tier-facade.md 出力契約の例: 値が `on<ESC>` なら value=on\u001b。
	#   違反を列挙外の 1 件だけにするため、blue の実装版・runner・ジョブマップも有効な値で置く)
	touch "$CONFIG_DIR/blue-job-map.csv"
	printf 'BLUE_MODE=on\033\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nBLUE_IMPL=blue-2.3.1\nBLUE_RUNNER=%s\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=%s\n' "$RUNNER" "$RUNNER" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 2 ]
	[ "${stderr_lines[0]}" = 'error: invalid value key=BLUE_MODE value=on\u001b' ]
	[ "${stderr_lines[1]}" = "hint: use foreground, background or off" ]
	[[ "$stderr" != *$'\033'* ]]
}

@test "validate-config_sh_--feature-flagのverboseで未知キーの名前にESCを含む場合_infoとwarnのkey=を可視表記で出すこと" {
	# Arrange(info / warn の key= は前後の空白を除いたキーの可視表記)
	write_green_only_env
	printf 'Z\033=x\n' >>"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE" --verbose

	# Assert
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 7 ]
	[ "${stderr_lines[5]}" = "info: key loaded key=Z\\u001b path: $ENV_FILE" ]
	[ "${stderr_lines[6]}" = "warn: unknown key key=Z\\u001b path: $ENV_FILE" ]
	[[ "$stderr" != *$'\033'* ]]
}

# ---- 性能の共通前提(NFR B.1.1.2: 1 ファイル最大 5,000 行・内容によらず 10 秒) ----

@test "validate-config_sh_--feature-flagで5000行のうち4995行が未知キーの場合_10秒以内に検証を終え未知キーを全件warnで出すこと" {
	# Arrange(重複検査・未知キーの warn をすべての行に対して行う最悪ケース。runner は --help にすぐ応答する)
	local i
	{
		for ((i = 1; i <= 4995; i++)); do
			printf 'UNKNOWN_%s=value-%s\n' "$i" "$i"
		done
		printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=%s\n' "$RUNNER"
	} >"$ENV_FILE"

	# Act
	local started=$SECONDS
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ $((SECONDS - started)) -lt 10 ]
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 4995 ]
	[ "${stderr_lines[0]}" = "warn: unknown key key=UNKNOWN_1 path: $ENV_FILE" ]
	[ "${lines[10]}" = "operation_mode=green_only" ]
}

@test "validate-config_sh_--feature-flagで5000行すべてが同じキーの場合_10秒以内に重複キーを1行で出し終了コード2であること" {
	# Arrange(重複の行番号を全件並べる最悪ケース)
	local i expected_lines
	for ((i = 0; i < 5000; i++)); do
		printf 'BLUE_MODE=off\n'
	done >"$ENV_FILE"
	expected_lines=1
	for ((i = 2; i <= 5000; i++)); do
		expected_lines+=",$i"
	done

	# Act
	local started=$SECONDS
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ $((SECONDS - started)) -lt 10 ]
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: duplicate key key=BLUE_MODE lines=$expected_lines path: $ENV_FILE" ]
}

# ---- S4 tier-impl(2026-11-13 attempt-3)で追加: runner --help 問い合わせの準備失敗の回の stderr ----

@test "validate-config_sh_--feature-flagのverboseで未知キーがありrunner問い合わせの準備に失敗した場合_runner probe failedの1行だけで終了コード6でstdoutは空であること" {
	# Arrange(契約 config_input_rules.env_files「validate-config.sh の --verbose の info 行」(b): 準備失敗の回は
	#   その error 行だけを出し、info 行を出さない。internal_failure: 他の error / warn 行も出さない。
	#   PATH の先頭に代替の mktemp を置き、入力の複製の作業名(`.part`)だけを本物へ通す(test/presentation/validate_config.bats と同じ方法))
	local real_mktemp fake_bin="$BATS_TEST_TMPDIR/fake-bin"
	real_mktemp="$(command -v mktemp)"
	mkdir -p "$fake_bin"
	printf '%s\n' '#!/usr/bin/env bash' 'for arg in "$@"; do' '  case "$arg" in' "    *.part) exec \"$real_mktemp\" \"\$@\" ;;" '  esac' 'done' 'exit 1' >"$fake_bin/mktemp"
	chmod +x "$fake_bin/mktemp"
	write_green_only_env
	printf 'ZZ=x\n' >>"$ENV_FILE"

	local stdout_file="$BATS_TEST_TMPDIR/out.txt" stderr_file="$BATS_TEST_TMPDIR/err.txt"

	# Act(bats の run --separate-stderr も mktemp を使うため、run を使わずファイルへ受ける)
	set +e
	PATH="$fake_bin:$PATH" "$SCRIPT" --feature-flag "$ENV_FILE" --verbose >"$stdout_file" 2>"$stderr_file"
	local exit_status=$?
	set -e

	# Assert
	[ "$exit_status" -eq 6 ]
	[ ! -s "$stdout_file" ]
	[ "$(wc -l <"$stderr_file" | tr -d ' ')" -eq 1 ]
	grep -q '^error: runner probe failed slot=green reason=' "$stderr_file"
}

# ---- S4 tier-impl(2026-11-13 attempt-4 / attempt-5)で追加: 制御文字の多いキーでの性能(S5 の指摘 F-001) ----
# 性能目標「5,000 行以内かつ 8 MB 以内のファイルを、内容によらず 10 秒以内」(2026-11-13 の利用者決定。目標値であり、
# 入力を制限する仕様ではない。5,000 行または 8 MB を超えるファイルも拒否・警告せずに処理する)。
# 可視表記(制御文字 → `\u00XX`)は、行数によらず一定回数の外部コマンド(sed / tr)でまとめて作る。
# 出力が数十 MB になるため、bats の run で変数へ受けずファイルへ受け、コマンドの実行時間だけを計る。

@test "validate-config_sh_--feature-flagのverboseで5000行のうち4995行がESCを128個含む未知キーの場合_10秒以内に検証を終えinfoとwarnを全件可視表記で出すこと" {
	# Arrange(S5 の指摘 F-001 の再現入力: 有効な単独本番設定 5 行 + 「K<連番> + ESC 128 個」の未知キー 4,995 行。約 68 万バイト)
	local i escapes="" shown=""
	for ((i = 0; i < 128; i++)); do
		escapes+=$'\033'
		shown+='\u001b'
	done
	write_green_only_env
	for ((i = 0; i < 4995; i++)); do
		printf 'K%s%s=x\n' "$i" "$escapes"
	done >>"$ENV_FILE"
	local stdout_file="$BATS_TEST_TMPDIR/out.txt" stderr_file="$BATS_TEST_TMPDIR/err.txt"

	# Act
	local started=$SECONDS exit_status=0
	LC_ALL=C "$SCRIPT" --feature-flag "$ENV_FILE" --verbose >"$stdout_file" 2>"$stderr_file" || exit_status=$?
	local elapsed=$((SECONDS - started))

	# Assert(info 5,000 行 → warn 4,995 行。生の ESC を 1 つも出さない)
	[ "$elapsed" -lt 10 ]
	[ "$exit_status" -eq 0 ]
	[ "$(wc -l <"$stdout_file" | tr -d ' ')" -eq 15 ]
	[ "$(wc -l <"$stderr_file" | tr -d ' ')" -eq 9995 ]
	[ "$(sed -n '6p' "$stderr_file")" = "info: key loaded key=K0$shown path: $ENV_FILE" ]
	[ "$(sed -n '5000p' "$stderr_file")" = "info: key loaded key=K4994$shown path: $ENV_FILE" ]
	[ "$(sed -n '5001p' "$stderr_file")" = "warn: unknown key key=K0$shown path: $ENV_FILE" ]
	[ "$(sed -n '9995p' "$stderr_file")" = "warn: unknown key key=K4994$shown path: $ENV_FILE" ]
	! LC_ALL=C grep -q $'\033' "$stderr_file"
}

@test "validate-config_sh_--feature-flagのverboseで5000行のうち4995行が全種類の制御文字を含む未知キーの場合_10秒以内に検証を終え種類ごとの可視表記で出すこと" {
	# Arrange(同じ文字の繰り返しではなく、種類の多い入力: キー 1 つに 1 バイトの制御文字 30 種(改行と CR を除く)と
	#   C1 制御文字 32 種を 1 個ずつ。約 50 万バイト)
	local i code controls="" shown=""
	for code in 1 2 3 4 5 6 7 8 9 11 12 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 127; do
		printf -v i '\\%03o' "$code"
		printf -v i '%b' "$i"
		controls+="$i"
		if [ "$code" -eq 9 ]; then
			shown+='\t'
		else
			printf -v i '\\u%04x' "$code"
			shown+="$i"
		fi
	done
	for ((code = 128; code < 160; code++)); do
		printf -v i '\\302\\%03o' "$code"
		printf -v i '%b' "$i"
		controls+="$i"
		printf -v i '\\u%04x' "$code"
		shown+="$i"
	done
	write_green_only_env
	for ((i = 0; i < 4995; i++)); do
		printf 'K%s%s=x\n' "$i" "$controls"
	done >>"$ENV_FILE"
	local stdout_file="$BATS_TEST_TMPDIR/out.txt" stderr_file="$BATS_TEST_TMPDIR/err.txt"

	# Act
	local started=$SECONDS exit_status=0
	LC_ALL=C "$SCRIPT" --feature-flag "$ENV_FILE" --verbose >"$stdout_file" 2>"$stderr_file" || exit_status=$?
	local elapsed=$((SECONDS - started))

	# Assert
	[ "$elapsed" -lt 10 ]
	[ "$exit_status" -eq 0 ]
	[ "$(wc -l <"$stdout_file" | tr -d ' ')" -eq 15 ]
	[ "$(wc -l <"$stderr_file" | tr -d ' ')" -eq 9995 ]
	[ "$(sed -n '6p' "$stderr_file")" = "info: key loaded key=K0$shown path: $ENV_FILE" ]
	[ "$(sed -n '9995p' "$stderr_file")" = "warn: unknown key key=K4994$shown path: $ENV_FILE" ]
	! LC_ALL=C grep -q '[[:cntrl:]]' "$stderr_file"
}

# ---- S4 tier-impl(2026-11-13 attempt-5)で追加: S5 attempt-4 の指摘 F-001 の再現入力と、性能目標の上限(8 MB)付近の入力 ----

# ENV_FILE の後ろに、「<接頭辞><5 桁の連番><埋め草>=x」の行を count 行足す(キーの長さは key_bytes バイト)。
# 埋め草は pattern の繰り返し。行ごとに組み立てず、printf 1 回で全行を書く(入力の生成でテストの時間を延ばさない)。
# 接頭辞と pattern は `%` とバックスラッシュを含まないこと(printf の書式に埋め込む)
# 引数: prefix pattern key_bytes count
append_padded_key_lines() {
	local prefix="$1" pattern="$2" key_bytes="$3" count="$4" padding=""
	local LC_ALL=C
	local padding_bytes=$((key_bytes - ${#prefix} - 5))
	while [ "${#padding}" -lt "$padding_bytes" ]; do
		padding+="$pattern"
	done
	padding="${padding:0:padding_bytes}"
	# shellcheck disable=SC2046,SC2059  # 連番を引数に並べ、書式を使い回して 1 行ずつ出す
	printf "${prefix}%05d${padding}=x\n" $(seq 0 $((count - 1))) >>"$ENV_FILE"
}

# 行に生の制御文字(U+0001〜U+001F と U+007F)が 1 つも無いこと。出力が 100 MB 近くになるテストでは、全行を走査せず、
# 取り出した行(先頭・末尾・段の境目)をこの関数で確かめる(全行の長さは同じ式で決まり、行数は別に確かめる)
# 引数: line
line_has_no_control_chars() {
	local LC_ALL=C
	[[ "$1" != *[$'\001'-$'\037'$'\177']* ]]
}

# 1 バイトの制御文字 29 種(U+0001〜U+001F と U+007F から、タブ・改行・CR を除く)。結果は CONTROLS_29
build_controls_29() {
	local code char
	CONTROLS_29=""
	for code in 1 2 3 4 5 6 7 8 11 12 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 127; do
		printf -v char '\\%03o' "$code"
		printf -v char '%b' "$char"
		CONTROLS_29+="$char"
	done
}

@test "validate-config_sh_--feature-flagのverboseで29種の制御文字を並べた1023と1024と1025バイトのキーが4995行ある場合_どの長さでも10秒以内に検証を終えること" {
	# Arrange(S5 attempt-4 の指摘 F-001 の再現入力: 有効な単独本番設定 5 行 + 一意な未知キー 4,995 行。全体は約 5.1 MB。
	#   修正前は 14.3 / 14.7 / 24.9 秒(Linux)。1,024 バイトを境に結果の控えが効かなくなり、info 行と warn 行で置き換えを繰り返していた)
	build_controls_29
	local stdout_file="$BATS_TEST_TMPDIR/out.txt" stderr_file="$BATS_TEST_TMPDIR/err.txt"
	local key_bytes started elapsed exit_status line
	local LC_ALL=C
	for key_bytes in 1023 1024 1025; do
		write_green_only_env
		append_padded_key_lines K "$CONTROLS_29" "$key_bytes" 4995

		# Act
		started=$SECONDS
		exit_status=0
		LC_ALL=C "$SCRIPT" --feature-flag "$ENV_FILE" --verbose >"$stdout_file" 2>"$stderr_file" || exit_status=$?
		elapsed=$((SECONDS - started))

		# Assert(info 5,000 行 → warn 4,995 行。キー 1 つの可視表記は、連番までの 6 バイト + 制御文字 1 つにつき 6 バイト)
		[ "$elapsed" -lt 10 ]
		[ "$exit_status" -eq 0 ]
		[ "$(wc -l <"$stdout_file" | tr -d ' ')" -eq 15 ]
		[ "$(wc -l <"$stderr_file" | tr -d ' ')" -eq 9995 ]
		line="$(sed -n '6{p;q;}' "$stderr_file")"
		line_has_no_control_chars "$line"
		[ "${line:0:51}" = 'info: key loaded key=K00000\u0001\u0002\u0003\u0004' ]
		[ "${#line}" -eq $((21 + 6 + (key_bytes - 6) * 6 + 7 + ${#ENV_FILE})) ]
		line="$(sed -n '5001{p;q;}' "$stderr_file")"
		line_has_no_control_chars "$line"
		[ "${line:0:52}" = 'warn: unknown key key=K00000\u0001\u0002\u0003\u0004' ]
		line="$(sed -n '9995{p;q;}' "$stderr_file")"
		line_has_no_control_chars "$line"
		[ "${line:0:28}" = 'warn: unknown key key=K04994' ]
		[ "${#line}" -eq $((22 + 6 + (key_bytes - 6) * 6 + 7 + ${#ENV_FILE})) ]
	done
}

@test "validate-config_sh_--feature-flagのverboseで5000行8MBのうち4995行が29種の制御文字だけのキーの場合_10秒以内に検証を終えinfoとwarnを全件可視表記で出すこと" {
	# Arrange(性能目標の上限の大きさ: 5,000 行・8 MiB 弱。キー 1 つが 1,676 バイトで、ほぼ全バイトが制御文字。stderr は約 100 MB)
	build_controls_29
	write_green_only_env
	append_padded_key_lines K "$CONTROLS_29" 1676 4995
	local line
	local LC_ALL=C
	local stdout_file="$BATS_TEST_TMPDIR/out.txt" stderr_file="$BATS_TEST_TMPDIR/err.txt"

	# Act
	local started=$SECONDS exit_status=0
	LC_ALL=C "$SCRIPT" --feature-flag "$ENV_FILE" --verbose >"$stdout_file" 2>"$stderr_file" || exit_status=$?
	local elapsed=$((SECONDS - started))

	# Assert
	[ "$elapsed" -lt 10 ]
	[ "$exit_status" -eq 0 ]
	[ "$(wc -c <"$ENV_FILE" | tr -d ' ')" -gt 8380000 ]
	[ "$(wc -c <"$ENV_FILE" | tr -d ' ')" -le 8388608 ]
	[ "$(wc -l <"$stdout_file" | tr -d ' ')" -eq 15 ]
	[ "$(wc -l <"$stderr_file" | tr -d ' ')" -eq 9995 ]
	line="$(sed -n '5000{p;q;}' "$stderr_file")"
	line_has_no_control_chars "$line"
	[ "${line:0:39}" = 'info: key loaded key=K04994\u0001\u0002' ]
	[ "${#line}" -eq $((21 + 6 + 1670 * 6 + 7 + ${#ENV_FILE})) ]
	line="$(sed -n '9995{p;q;}' "$stderr_file")"
	line_has_no_control_chars "$line"
	[ "${line:0:40}" = 'warn: unknown key key=K04994\u0001\u0002' ]
	[ "${#line}" -eq $((22 + 6 + 1670 * 6 + 7 + ${#ENV_FILE})) ]
}

@test "validate-config_sh_--feature-flagのverboseで5000行8MBのうち4995行がC1制御文字とDELと多バイト文字を混ぜたキーの場合_10秒以内に検証を終え多バイト文字を変えずに出すこと" {
	# Arrange(C1 制御文字 32 種(各 2 バイト)、DEL、通常の多バイト文字(あ、U+00A0)、ESC を並べたキー。UTF-8 として有効)
	local pattern="" code char
	for ((code = 128; code < 160; code++)); do
		printf -v char '\\302\\%03o' "$code"
		printf -v char '%b' "$char"
		pattern+="$char"
	done
	pattern+=$'\177\xe3\x81\x82\xc2\xa0\033'
	write_green_only_env
	# 埋め草が多バイト文字の途中で切れないよう、キーの長さを繰り返しの倍数に合わせる(6 + 71 × 23 = 1,639 バイト)
	append_padded_key_lines K "$pattern" 1639 4995
	local stdout_file="$BATS_TEST_TMPDIR/out.txt" stderr_file="$BATS_TEST_TMPDIR/err.txt"

	# Act
	local started=$SECONDS exit_status=0
	LC_ALL=C "$SCRIPT" --feature-flag "$ENV_FILE" --verbose >"$stdout_file" 2>"$stderr_file" || exit_status=$?
	local elapsed=$((SECONDS - started))

	# Assert(キーの末尾は DEL・あ・U+00A0・ESC。あ と U+00A0 はバイトを変えない)
	[ "$elapsed" -lt 10 ]
	[ "$exit_status" -eq 0 ]
	[ "$(wc -c <"$ENV_FILE" | tr -d ' ')" -gt 8190000 ]
	[ "$(wc -l <"$stdout_file" | tr -d ' ')" -eq 15 ]
	[ "$(wc -l <"$stderr_file" | tr -d ' ')" -eq 9995 ]
	local expected_tail='\u009f\u007f'$'\xe3\x81\x82\xc2\xa0''\u001b'" path: $ENV_FILE"
	local line
	local LC_ALL=C
	line="$(sed -n '6{p;q;}' "$stderr_file")"
	line_has_no_control_chars "$line"
	[ "${line:0:39}" = 'info: key loaded key=K00000\u0080\u0081' ]
	line="$(sed -n '9995{p;q;}' "$stderr_file")"
	line_has_no_control_chars "$line"
	[ "${line: -${#expected_tail}}" = "$expected_tail" ]
	[ "${line:0:28}" = 'warn: unknown key key=K04994' ]
}

@test "validate-config_sh_--feature-flagで8MBのうち半分ずつが制御文字だらけの同じキー2497個の重複の場合_10秒以内にduplicate keyを全件可視表記で出すこと" {
	# Arrange(同じ 2,497 個のキーを 2 回並べる。(ii) の段で止まり、duplicate key を初出行の昇順に 2,497 行出す)
	build_controls_29
	: >"$ENV_FILE"
	append_padded_key_lines K "$CONTROLS_29" 1670 2497
	cat "$ENV_FILE" "$ENV_FILE" >"$BATS_TEST_TMPDIR/doubled.env"
	mv "$BATS_TEST_TMPDIR/doubled.env" "$ENV_FILE"
	local stdout_file="$BATS_TEST_TMPDIR/out.txt" stderr_file="$BATS_TEST_TMPDIR/err.txt"

	# Act
	local started=$SECONDS exit_status=0
	LC_ALL=C "$SCRIPT" --feature-flag "$ENV_FILE" --verbose >"$stdout_file" 2>"$stderr_file" || exit_status=$?
	local elapsed=$((SECONDS - started))

	# Assert
	[ "$elapsed" -lt 10 ]
	[ "$exit_status" -eq 2 ]
	[ ! -s "$stdout_file" ]
	[ "$(wc -l <"$stderr_file" | tr -d ' ')" -eq 2497 ]
	local line
	local LC_ALL=C
	line="$(sed -n '1{p;q;}' "$stderr_file")"
	line_has_no_control_chars "$line"
	[ "${line:0:43}" = 'error: duplicate key key=K00000\u0001\u0002' ]
	line="$(sed -n '2497{p;q;}' "$stderr_file")"
	line_has_no_control_chars "$line"
	[ "${line:0:31}" = 'error: duplicate key key=K02496' ]
	[ "${line: -$((23 + ${#ENV_FILE}))}" = " lines=2497,4994 path: $ENV_FILE" ]
}

@test "validate-config_sh_--feature-flagで列挙外のmodeの値が1行で8MBあり制御文字と多バイト文字を含む場合_10秒以内にinvalid valueとforeground排他を可視表記で出すこと" {
	# Arrange(1 行 1 つの値が 8 MiB 弱。BLUE_MODE の値は error 行 2 つ(invalid value と foreground slot の排他)に出る。
	#   16 バイトごとに ESC・DEL・C1 制御文字(U+0085)・多バイト文字(あ)が 1 つずつ。制御文字だけの入力は上のキーのテストが固定する)
	local chunk=$'abcdefgh\033\177\xc2\x85\xe3\x81\x82 ' value="" index
	for ((index = 0; index < 10; index++)); do
		chunk+="$chunk"
	done
	for ((index = 0; index < 511; index++)); do
		value+="$chunk"
	done
	printf 'BLUE_MODE=%s\nGREEN_MODE=off\nRAPID_CROSSCHECK_MODE=off\nBLUE_IMPL=b\nBLUE_RUNNER=%s\n' "${value}x" "$RUNNER" >"$ENV_FILE"
	touch "$CONFIG_DIR/blue-job-map.csv"
	local stdout_file="$BATS_TEST_TMPDIR/out.txt" stderr_file="$BATS_TEST_TMPDIR/err.txt"

	# Act
	local started=$SECONDS exit_status=0
	LC_ALL=C "$SCRIPT" --feature-flag "$ENV_FILE" >"$stdout_file" 2>"$stderr_file" || exit_status=$?
	local elapsed=$((SECONDS - started))

	# Assert(error 行どうしの順は固定しない。hint は invalid value の直後)
	[ "$elapsed" -lt 10 ]
	[ "$exit_status" -eq 2 ]
	[ "$(wc -c <"$ENV_FILE" | tr -d ' ')" -gt 8370000 ]
	[ "$(wc -c <"$ENV_FILE" | tr -d ' ')" -le 8388608 ]
	[ ! -s "$stdout_file" ]
	[ "$(wc -l <"$stderr_file" | tr -d ' ')" -eq 3 ]
	[ "$(LC_ALL=C grep -c '^error: invalid value key=BLUE_MODE value=abcdefgh\\u001b\\u007f\\u0085' "$stderr_file")" -eq 1 ]
	[ "$(grep -c '^hint: use foreground, background or off$' "$stderr_file")" -eq 1 ]
	[ "$(LC_ALL=C grep -c '^error: foreground slot must be exactly one blue_mode=abcdefgh\\u001b\\u007f\\u0085.*x green_mode=off$' "$stderr_file")" -eq 1 ]
}

# ---- S4 tier-impl(2026-11-13 attempt-5)で追加: 可視表記をまとめて作る外部コマンド(sed / tr)の失敗 ----
# CLI 契約 config_input_rules.internal_failure: 補助コマンドの失敗は error 行 1 つだけを出し、stdout も他の行も出さず終了コード 6。

# 可視表記をまとめて作る sed(スクリプトに y コマンドを含む)だけが失敗する代わりの sed を PATH の先頭に置く。
# バイト点検と行の構造の取り出しの sed は本物へ通す
install_sed_failing_on_escape() {
	local fake_bin="$BATS_TEST_TMPDIR/fake-bin" real_sed
	real_sed="$(command -v sed)"
	mkdir -p "$fake_bin"
	printf '%s\n' '#!/bin/sh' 'for arg in "$@"; do' '  case "$arg" in' "    y/*) echo 'fake failure' >&2; exit 1 ;;" '  esac' 'done' "exec \"$real_sed\" \"\$@\"" >"$fake_bin/sed"
	chmod +x "$fake_bin/sed"
}

# 改行を消す tr(`tr -d`)だけが失敗する代わりの tr を PATH の先頭に置く。バイト点検の tr は本物へ通す
install_tr_failing_on_delete() {
	local fake_bin="$BATS_TEST_TMPDIR/fake-bin" real_tr
	real_tr="$(command -v tr)"
	mkdir -p "$fake_bin"
	printf '%s\n' '#!/bin/sh' 'if [ "$1" = "-d" ]; then' "  echo 'fake failure' >&2" '  exit 1' 'fi' "exec \"$real_tr\" \"\$@\"" >"$fake_bin/tr"
	chmod +x "$fake_bin/tr"
}

@test "validate-config_sh_--feature-flagのverboseで制御文字だらけの未知キーが多数ありキー名の可視表記を作るsedが失敗する場合_internal command failedの1行だけで終了コード6でstdoutは空であること" {
	# Arrange(有効な設定 + 制御文字だらけの未知キー 50 行。キー名の合計が大きいため、可視表記を sed でまとめて作る)
	build_controls_29
	write_green_only_env
	append_padded_key_lines K "$CONTROLS_29" 300 50
	install_sed_failing_on_escape
	local stdout_file="$BATS_TEST_TMPDIR/out.txt" stderr_file="$BATS_TEST_TMPDIR/err.txt" exit_status=0

	# Act
	PATH="$BATS_TEST_TMPDIR/fake-bin:$PATH" "$SCRIPT" --feature-flag "$ENV_FILE" --verbose >"$stdout_file" 2>"$stderr_file" || exit_status=$?

	# Assert(info 行・warn 行・sed 自身の stderr を出さない)
	[ "$exit_status" -eq 6 ]
	[ ! -s "$stdout_file" ]
	[ "$(cat "$stderr_file")" = "error: internal command failed commands=sed path: $ENV_FILE" ]
}

@test "validate-config_sh_--feature-flagでC1制御文字を含む未知キーが多数あり改行を消すtrが失敗する場合_internal command failedの1行だけで終了コード6でstdoutは空であること" {
	# Arrange(キーに C1 制御文字(U+0085)を含める。tr を使うのは、値に 0xC2 があるとき。埋め草は 31 バイトの繰り返しで、
	#   多バイト文字の途中では切れない(294 = 31 × 9 + 15))
	build_controls_29
	write_green_only_env
	append_padded_key_lines K "$CONTROLS_29"$'\xc2\x85' 300 50
	install_tr_failing_on_delete
	local stdout_file="$BATS_TEST_TMPDIR/out.txt" stderr_file="$BATS_TEST_TMPDIR/err.txt" exit_status=0

	# Act
	PATH="$BATS_TEST_TMPDIR/fake-bin:$PATH" "$SCRIPT" --feature-flag "$ENV_FILE" >"$stdout_file" 2>"$stderr_file" || exit_status=$?

	# Assert
	[ "$exit_status" -eq 6 ]
	[ ! -s "$stdout_file" ]
	[ "$(cat "$stderr_file")" = "error: internal command failed commands=tr path: $ENV_FILE" ]
}

@test "validate-config_sh_--feature-flagで制御文字だらけの同じキーが多数重複しキー名の可視表記を作るsedが失敗する場合_duplicate keyを出さずinternal command failedの1行だけで終了コード6であること" {
	# Arrange((ii) の段の duplicate key の行に出すキー名も、まとめて可視表記にする)
	build_controls_29
	: >"$ENV_FILE"
	append_padded_key_lines K "$CONTROLS_29" 300 30
	cat "$ENV_FILE" "$ENV_FILE" >"$BATS_TEST_TMPDIR/doubled.env"
	mv "$BATS_TEST_TMPDIR/doubled.env" "$ENV_FILE"
	install_sed_failing_on_escape
	local stdout_file="$BATS_TEST_TMPDIR/out.txt" stderr_file="$BATS_TEST_TMPDIR/err.txt" exit_status=0

	# Act
	PATH="$BATS_TEST_TMPDIR/fake-bin:$PATH" "$SCRIPT" --feature-flag "$ENV_FILE" >"$stdout_file" 2>"$stderr_file" || exit_status=$?

	# Assert
	[ "$exit_status" -eq 6 ]
	[ ! -s "$stdout_file" ]
	[ "$(cat "$stderr_file")" = "error: internal command failed commands=sed path: $ENV_FILE" ]
}

@test "validate-config_sh_--feature-flagで実装版の値が大きく制御文字を含み可視表記を作るsedが失敗する場合_stdoutを出さずinternal command failedの1行だけで終了コード6であること" {
	# Arrange(検証 OK なら stdout に出す GREEN_IMPL の値が 6,000 バイト。stdout を出す前に可視表記を作る)
	local value="" index
	for ((index = 0; index < 1000; index++)); do
		value+=$'v1.4\033 '
	done
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=%sx\nGREEN_RUNNER=%s\n' "$value" "$RUNNER" >"$ENV_FILE"
	install_sed_failing_on_escape
	local stdout_file="$BATS_TEST_TMPDIR/out.txt" stderr_file="$BATS_TEST_TMPDIR/err.txt" exit_status=0

	# Act
	PATH="$BATS_TEST_TMPDIR/fake-bin:$PATH" "$SCRIPT" --feature-flag "$ENV_FILE" >"$stdout_file" 2>"$stderr_file" || exit_status=$?

	# Assert
	[ "$exit_status" -eq 6 ]
	[ ! -s "$stdout_file" ]
	[ "$(cat "$stderr_file")" = "error: internal command failed commands=sed path: $ENV_FILE" ]
}

@test "validate-config_sh_--feature-flagで実装版の値が大きく制御文字と空白を含む場合_stdoutのgreen_implを可視表記のkey_colon形式で出し終了コード0であること" {
	# Arrange(上と同じ入力で、外部コマンドが動く場合。値に空白を含むため `green_impl: <値>`)
	local value="" shown="" index
	for ((index = 0; index < 1000; index++)); do
		value+=$'v1.4\033 '
		shown+='v1.4\u001b '
	done
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=%sx\nGREEN_RUNNER=%s\n' "$value" "$RUNNER" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ "${#lines[@]}" -eq 15 ]
	[ "${lines[4]}" = "green_impl: ${shown}x" ]
	[ "${lines[10]}" = "operation_mode=green_only" ]
}

@test "validate-config_sh_--feature-flagのverboseで通常の大きさの設定の場合_可視表記を作る外部コマンドが失敗しても使わずに終了コード0であること" {
	# Arrange(キー名と値の合計が小さい設定は、外部コマンドを起動せずに置き換える。制御文字を含む未知キーが 1 つ)
	write_green_only_env
	printf 'ZZ\033=x\n' >>"$ENV_FILE"
	install_sed_failing_on_escape
	install_tr_failing_on_delete
	local stdout_file="$BATS_TEST_TMPDIR/out.txt" stderr_file="$BATS_TEST_TMPDIR/err.txt" exit_status=0

	# Act
	PATH="$BATS_TEST_TMPDIR/fake-bin:$PATH" "$SCRIPT" --feature-flag "$ENV_FILE" --verbose >"$stdout_file" 2>"$stderr_file" || exit_status=$?

	# Assert(info 6 行 → 未知キーの warn 1 行)
	[ "$exit_status" -eq 0 ]
	[ "$(wc -l <"$stdout_file" | tr -d ' ')" -eq 15 ]
	[ "$(wc -l <"$stderr_file" | tr -d ' ')" -eq 7 ]
	[ "$(sed -n '6p' "$stderr_file")" = "info: key loaded key=ZZ\\u001b path: $ENV_FILE" ]
	[ "$(sed -n '7p' "$stderr_file")" = "warn: unknown key key=ZZ\\u001b path: $ENV_FILE" ]
}
