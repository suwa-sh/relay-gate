#!/usr/bin/env bats
# UC fd678b04 × tier-facade: domain 層 制御文字の可視表記(cli_field_escape_text / cli_field_safe_text)の単体テスト。
# 2026-11-13 S4 attempt-4 で追加(S5 の指摘 F-001: 制御文字の多い値で処理時間が制御文字の個数 × 数十マイクロ秒かかっていた)。
# 可視表記の処理を「同じ文字の一括置き換え」と「断片の連結」に分けたため、どちらの経路でも出力のバイト列が
# 規則(conventions.output_format.control_chars)どおりで、経路の切り替わる境界でも変わらないことを固定する。
# 期待値は、規則を 1 バイトずつ適用する参照実装(cli_field_reference.bash の reference_escape。遅いが単純)で作る。
# 2026-11-13 S4 attempt-5: 行数に比例する個数の値や数 MB の値を表示する呼び出し元は、表示の前に sed でまとめて変換するようになった
# (cli_field_safe_text_list / cli_field_safe_text_prepare。test/domain/cli_field_batch.bats)。
# このファイルは、値ごとの関数(cli_field_escape_text / cli_field_safe_text)が使う bash の経路を固定する(外部コマンドを起動しない)。

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/cli_field.sh"
	load cli_field_reference
}

@test "cli_field_escape_text_同じ制御文字が1窓に多数ある場合_一括置き換えの経路でも1個ずつの規則と同じバイト列になること" {
	# Arrange(ESC 128 個。S5 の指摘 F-001 のキーと同じ形)
	repeat_text $'\033' 128
	local value="K0$REPEATED=x"
	repeat_text '\u001b' 128

	# Act
	cli_field_escape_text "$value"

	# Assert
	[ "$CLI_FIELD_ESCAPED" = "K0$REPEATED=x" ]
}

@test "cli_field_escape_text_制御文字の個数が経路の切り替わる境界の前後の場合_どの個数でも参照実装と同じバイト列になること" {
	# Arrange(1 窓の合計が CLI_FIELD_ESCAPE_COUNT_MIN_TOTAL の前後、1 種類の個数が CLI_FIELD_ESCAPE_BULK_MIN_COUNT の前後)
	local total few value
	for total in 0 1 3 4 5 62 63 64 65 66 127; do
		for few in 0 1 3 4 5; do
			repeat_text $'\033' "$total"
			value="a$REPEATED"
			repeat_text $'b\001' "$few"
			value+="$REPEATED"$'\037c\177\t\n'

			# Act
			cli_field_escape_text "$value"
			reference_escape "$value"

			# Assert
			[ "$CLI_FIELD_ESCAPED" = "$REFERENCE_ESCAPED" ]
		done
	done
}

@test "cli_field_escape_text_1バイトの制御文字とC1制御文字の全種類を含む場合_種類ごとの可視表記になり通常の2バイト文字と不正な0xC2は変えないこと" {
	# Arrange(1 バイトの制御文字 32 種、C1 制御文字 32 種、U+00A0、U+00BF、末尾に 0xC2 だけ)
	local value="x$CLI_FIELD_CONTROL_CHARS" index
	for index in "${!CLI_FIELD_C1_SEQUENCES[@]}"; do
		value+="${CLI_FIELD_C1_SEQUENCES[index]}"
	done
	value+=$'\xc2\xa0\xc2\xbf\xc2\xc2\x85y\xc2'

	# Act
	cli_field_escape_text "$value"
	reference_escape "$value"

	# Assert
	[ "$CLI_FIELD_ESCAPED" = "$REFERENCE_ESCAPED" ]
	[[ "$CLI_FIELD_ESCAPED" == 'x\u0001\u0002'*'\u001f\u007f\u0080\u0081'*'\u009f'$'\xc2\xa0\xc2\xbf\xc2''\u0085y'$'\xc2' ]]
}

@test "cli_field_escape_text_決まった乱数列で作った値の場合_窓の大きさと前にバックスラッシュを付ける文字によらず参照実装と同じバイト列になること" {
	# Arrange(線形合同法の固定の乱数列。制御文字・C1 の先頭と後続・引用符・バックスラッシュ・& ・パス名展開の文字を多めに混ぜる)
	local alphabet=($'\001' $'\033' $'\n' $'\t' $'\r' $'\177' $'\037' $'\xc2' $'\xc2' $'\x80' $'\x9f' $'\x9b' $'\xa0' $'\xe3' $'\x81' '"' "\\" '&' 'a' ' ' '=' '*' '?' '[' ']' '/')
	local seed=20261113 round length position value set_chars window
	local sets=('' "\"\\" "\\" '&"' $'\037"\\')
	local windows=(1 2 7 64 1024)
	next_random() {
		seed=$(((seed * 1103515245 + 12345) % 2147483648))
		RANDOM_VALUE=$((seed / 65536))
	}
	for ((round = 0; round < 400; round++)); do
		next_random
		length=$((RANDOM_VALUE % 48))
		if [ $((round % 8)) -eq 0 ]; then
			length=$((length * 6))
		fi
		value=""
		for ((position = 0; position < length; position++)); do
			next_random
			value+="${alphabet[RANDOM_VALUE % ${#alphabet[@]}]}"
		done
		next_random
		set_chars="${sets[RANDOM_VALUE % ${#sets[@]}]}"
		next_random
		window="${windows[RANDOM_VALUE % ${#windows[@]}]}"

		# Act
		cli_field_escape_text "$value" "$set_chars" "$window"
		reference_escape "$value" "$set_chars"

		# Assert
		[ "$CLI_FIELD_ESCAPED" = "$REFERENCE_ESCAPED" ]
	done
}

@test "cli_field_escape_text_値にパス名展開の文字と空白を含む場合_展開も分割もせずシェルの設定を変えないこと" {
	# Arrange(断片への分割は単語分割で行う。関数の外の IFS とパス名展開の設定に影響させない)
	cd "$BATS_TEST_TMPDIR"
	touch a1 a2
	local value=$'a*\033 a? \033[a]*  \033' ifs_before="$IFS" options_before="$-"

	# Act
	cli_field_escape_text "$value"

	# Assert
	[ "$CLI_FIELD_ESCAPED" = 'a*\u001b a? \u001b[a]*  \u001b' ]
	[ "$IFS" = "$ifs_before" ]
	[ "$-" = "$options_before" ]
}

@test "cli_field_escape_text_値と前にバックスラッシュを付ける文字に&を含む場合_&を一致部分として展開しないこと" {
	# Arrange(bash 5.2 以降は、囲まない置き換え文字列の & を一致部分として展開する)
	repeat_text $'&\033' 70
	local value="$REPEATED"
	repeat_text '\&\u001b' 70

	# Act
	cli_field_escape_text "$value" '&'

	# Assert
	[ "$CLI_FIELD_ESCAPED" = "$REPEATED" ]
}

@test "cli_field_safe_text_同じ値を2回渡した場合_2回目も同じ可視表記を返すこと" {
	# Arrange
	local value=$'K\033\xc2\x9b\tz'

	# Act
	cli_field_safe_text "$value"
	local first="$CLI_FIELD_SAFE_TEXT"
	cli_field_safe_text "plain"
	cli_field_safe_text "$value"

	# Assert
	[ "$first" = 'K\u001b\u009b\tz' ]
	[ "$CLI_FIELD_SAFE_TEXT" = "$first" ]
}

@test "cli_field_safe_text_配列の添字として特別な文字だけの値の場合_値ごとに別の可視表記を返すこと" {
	# Arrange / Act(結果の控えの添字に値を使う。@ / * / 式に見える値を取り違えない)
	local value expected
	for value in $'@\033' $'*\033' $'a[$(echo x)]\033' $'1+1\033' $']\033'; do
		cli_field_safe_text "$value"
		expected="${value%$'\033'}"'\u001b'

		# Assert
		[ "$CLI_FIELD_SAFE_TEXT" = "$expected" ]
		cli_field_safe_text "$value"
		[ "$CLI_FIELD_SAFE_TEXT" = "$expected" ]
	done
}

@test "cli_field_safe_text_控えの上限より長い値の場合_控えずに毎回同じ可視表記を返すこと" {
	# Arrange(CLI_FIELD_SAFE_CACHE_MAX_BYTES を超える値は控えない)
	repeat_text 'a' "$CLI_FIELD_SAFE_CACHE_MAX_BYTES"
	local value="$REPEATED"$'\033'
	local expected="$REPEATED"'\u001b'

	# Act
	cli_field_safe_text "$value"
	local first="$CLI_FIELD_SAFE_TEXT"
	cli_field_safe_text "$value"

	# Assert
	[ "$first" = "$expected" ]
	[ "$CLI_FIELD_SAFE_TEXT" = "$expected" ]
	[ "${#CLI_FIELD_SAFE_CACHE[@]}" -eq 0 ]
}

@test "cli_field_safe_text_置き換えの要らない小さな値の場合_控えに載せないこと" {
	# Arrange / Act(通常の値は行数に比例して渡される。控えを増やさない)
	cli_field_safe_text "BLUE_MODE"
	cli_field_safe_text "/opt/app/bin/runner.sh"

	# Assert
	[ "$CLI_FIELD_SAFE_TEXT" = "/opt/app/bin/runner.sh" ]
	[ "${#CLI_FIELD_SAFE_CACHE[@]}" -eq 0 ]
}

@test "cli_field_escape_text_制御文字が半分を占める100万バイトの値の場合_10秒以内に置き換えること" {
	# Arrange(行の長さに上限は無い。処理時間を値のバイト数に比例させる)
	local chunk="a"$'\033' value="" index
	for ((index = 0; index < 9; index++)); do
		chunk+="$chunk"
	done
	for ((index = 0; index < 1024; index++)); do
		value+="$chunk"
	done
	SECONDS=0

	# Act
	cli_field_escape_text "$value"

	# Assert
	[ "$SECONDS" -lt 10 ]
	[ "${#value}" -eq 1048576 ]
	[ "${#CLI_FIELD_ESCAPED}" -eq 3670016 ]
	[ "${CLI_FIELD_ESCAPED:0:14}" = 'a\u001ba\u001b' ]
}
