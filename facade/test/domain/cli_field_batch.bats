#!/usr/bin/env bats
# UC fd678b04 × tier-facade: domain 層 制御文字の可視表記を、外部コマンド(sed / tr)でまとめて変換する経路の単体テスト。
# 2026-11-13 S4 attempt-5 で追加(S5 の指摘 F-001: 制御文字の種類が多い値 5,000 行・約 5 MB で 10 秒を超えていた)。
# 性能目標は「5,000 行以内かつ 8 MB 以内のファイルを、内容によらず 10 秒以内」(目標値。入力を制限する仕様ではない)。
# 値の個数によらず sed 1 回(値に 0xC2 があるときは sed 2 回と tr 1 回)で置き換えるため、次を固定する:
#   - 出力のバイト列が bash の経路(cli_field_escape_paths.bats が参照実装と比べて固定)と同じで、小さな値は参照実装とも同じであること
#   - 外部コマンドを使うのは cli_field_safe_text_list / cli_field_safe_text_prepare(と内部の cli_field_escape_batch)だけで、
#     値ごとの cli_field_safe_text は外部コマンドを起動しないこと
#   - 外部コマンドが失敗した・想定外の出力をしたときは、戻り値と失敗したコマンド名で伝えること(CLI 契約 config_input_rules.internal_failure の
#     「補助コマンドの失敗」として報告するのは呼び出し元)
#   - 呼び出し元のシェルの設定(IFS・パス名展開)を変えないこと
bats_require_minimum_version 1.5.0

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/cli_field.sh"
	load cli_field_reference
}

# 決まった乱数列(線形合同法)。結果は RANDOM_VALUE
RANDOM_SEED=20261113
next_random() {
	RANDOM_SEED=$(((RANDOM_SEED * 1103515245 + 12345) % 2147483648))
	RANDOM_VALUE=$((RANDOM_SEED / 65536))
}

# 何もせず失敗する代わりのコマンドを PATH の先頭に置く(名前は sed / tr)
install_failing_command() {
	local name="$1" fake_bin="$BATS_TEST_TMPDIR/fake-bin"
	mkdir -p "$fake_bin"
	printf '%s\n' '#!/bin/sh' 'echo "fake failure" >&2' 'exit 1' >"$fake_bin/$name"
	chmod +x "$fake_bin/$name"
	PATH="$fake_bin:$PATH"
}

@test "cli_field_escape_batch_制御文字の全種類とC1制御文字と多バイト文字と不正なUTF-8の場合_値ごとに参照実装と同じバイト列になること" {
	# Arrange(1 バイトの制御文字 32 種(改行を含む)、C1 制御文字 32 種、U+00A0 / U+00BF、0xC2 だけ、0xC2 の連続、
	#   多バイト文字の後続バイトが 0x80〜0x9F のもの、UTF-8 として不正な並び、DEL)
	local c1="" index
	for index in "${!CLI_FIELD_C1_SEQUENCES[@]}"; do
		c1+="${CLI_FIELD_C1_SEQUENCES[index]}"
	done
	local values=(
		"x$CLI_FIELD_CONTROL_CHARS"
		"$c1"
		"$CLI_FIELD_CONTROL_CHARS$c1$CLI_FIELD_CONTROL_CHARS"
		$'\xc2\xa0\xc2\xbf\xc2\xc2\x85y\xc2'
		$'\xc2'
		$'\xe3\x81\x82\xe3\x80\x81\xf0\x9f\x98\x80'
		$'\x80\x9f\x85\xff\xfe'
		$'\177\177a\177'
		'plain value / with = and \ and "quotes" and &'
		$'\\u0001 \\n \\t are already escaped'
	)
	local -a escaped=()

	# Act
	cli_field_escape_batch escaped "${values[@]}"

	# Assert
	[ "${#escaped[@]}" -eq "${#values[@]}" ]
	for index in "${!values[@]}"; do
		reference_escape "${values[index]}"
		[ "${escaped[index]}" = "$REFERENCE_ESCAPED" ]
	done
	[ "${escaped[3]}" = $'\xc2\xa0\xc2\xbf\xc2''\u0085y'$'\xc2' ]
	[ "${escaped[7]}" = '\u007f\u007fa\u007f' ]
	[ "${escaped[8]}" = 'plain value / with = and \ and "quotes" and &' ]
	[ -z "$CLI_FIELD_BATCH_FAILED_COMMANDS" ]
}

@test "cli_field_escape_batch_値に改行と空の値と値の終わりの目印と同じ文字を含む場合_値の境目を取り違えず同じ並びで返すこと" {
	# Arrange(1 行 1 値で sed へ渡す。値の中の改行、空の値、値の終わりの目印に使う U+001F、成功の証跡と同じ文字列)
	local values=(
		$'first\nsecond\n'
		''
		$'\037'
		$'a\037b\037'
		'ok:0 0 0'
		$'\037ok:0 0 0'
		''
		$'\n'
		$'last\xc2\x9f\n\xc2\x80'
	)
	local -a escaped=()

	# Act
	cli_field_escape_batch escaped "${values[@]}"

	# Assert
	[ "${#escaped[@]}" -eq 9 ]
	[ "${escaped[0]}" = 'first\nsecond\n' ]
	[ "${escaped[1]}" = '' ]
	[ "${escaped[2]}" = '\u001f' ]
	[ "${escaped[3]}" = 'a\u001fb\u001f' ]
	[ "${escaped[4]}" = 'ok:0 0 0' ]
	[ "${escaped[5]}" = '\u001fok:0 0 0' ]
	[ "${escaped[6]}" = '' ]
	[ "${escaped[7]}" = '\n' ]
	[ "${escaped[8]}" = 'last\u009f\n\u0080' ]
}

@test "cli_field_escape_batch_決まった乱数列で作った150個の値の場合_1回の呼び出しで全件がbashの経路と同じバイト列になること" {
	# Arrange(制御文字・C1 の先頭と後続・DEL・多バイト文字の断片・引用符・バックスラッシュ・& ・パス名展開の文字を多めに混ぜる)
	local alphabet=($'\001' $'\033' $'\n' $'\t' $'\r' $'\177' $'\037' $'\xc2' $'\xc2' $'\x80' $'\x9f' $'\x9b' $'\xa0' $'\xe3' $'\x81' '"' "\\" '&' 'a' ' ' '=' '*' '?' '[' ']' '/')
	local round length position value index
	local -a values=() escaped=()
	for ((round = 0; round < 150; round++)); do
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
		values+=("$value")
	done

	# Act
	cli_field_escape_batch escaped "${values[@]}"

	# Assert(全件を bash の経路と比べ、先頭 25 件は参照実装とも比べる)
	[ "${#escaped[@]}" -eq 150 ]
	for index in "${!values[@]}"; do
		cli_field_escape_text "${values[index]}"
		[ "${escaped[index]}" = "$CLI_FIELD_ESCAPED" ]
	done
	for ((index = 0; index < 25; index++)); do
		reference_escape "${values[index]}"
		[ "${escaped[index]}" = "$REFERENCE_ESCAPED" ]
	done
}

@test "cli_field_escape_batch_値にパス名展開の文字と空白を含む場合_展開も分割もせずシェルの設定を変えないこと" {
	# Arrange(結果は単語分割で値に分ける。関数の外の IFS とパス名展開の設定に影響させない)
	cd "$BATS_TEST_TMPDIR"
	touch a1 a2
	local ifs_before="$IFS" options_before="$-"
	local -a escaped=()

	# Act
	cli_field_escape_batch escaped $'a*\033 a? \033[a]*  \033' '*' 'a? a*'

	# Assert
	[ "${#escaped[@]}" -eq 3 ]
	[ "${escaped[0]}" = 'a*\u001b a? \u001b[a]*  \u001b' ]
	[ "${escaped[1]}" = '*' ]
	[ "${escaped[2]}" = 'a? a*' ]
	[ "$IFS" = "$ifs_before" ]
	[ "$-" = "$options_before" ]
}

@test "cli_field_escape_batch_sedが失敗する場合_戻り値1で結果を空にし失敗したコマンド名sedを載せstderrへ何も出さないこと" {
	# Arrange
	install_failing_command sed
	local -a escaped=(stale)
	local status_code=0

	# Act(stderr をファイルへ受ける。sed 自身の stderr も出さない)
	cli_field_escape_batch escaped $'a\033' 'b' 2>"$BATS_TEST_TMPDIR/err.txt" || status_code=$?

	# Assert
	[ "$status_code" -eq 1 ]
	[ "${#escaped[@]}" -eq 0 ]
	[ "$CLI_FIELD_BATCH_FAILED_COMMANDS" = "sed" ]
	[ ! -s "$BATS_TEST_TMPDIR/err.txt" ]
}

@test "cli_field_escape_batch_値に0xC2がありtrが失敗する場合_戻り値1で結果を空にし失敗したコマンド名trを載せること" {
	# Arrange(tr を使うのは、値に 0xC2 があるとき(C1 制御文字の置き換えのために行を分けて、つなぎ直す)と空の値があるとき)
	install_failing_command tr
	local -a escaped=()
	local status_code=0

	# Act
	cli_field_escape_batch escaped $'a\033\xc2\x85' 'b' 2>"$BATS_TEST_TMPDIR/err.txt" || status_code=$?

	# Assert
	[ "$status_code" -eq 1 ]
	[ "${#escaped[@]}" -eq 0 ]
	[ "$CLI_FIELD_BATCH_FAILED_COMMANDS" = "tr" ]
	[ ! -s "$BATS_TEST_TMPDIR/err.txt" ]
}

@test "cli_field_escape_batch_sedが成功の終了状態で値を1件落とす場合_件数の不一致として戻り値1にし使ったコマンドをすべて載せること" {
	# Arrange(終了状態 0 でも、出力の件数が合わなければ使わない。どのコマンドで欠けたかは判別できない)
	local fake_bin="$BATS_TEST_TMPDIR/fake-bin" real_sed
	real_sed="$(command -v sed)"
	mkdir -p "$fake_bin"
	printf '%s\n' '#!/bin/sh' "\"$real_sed\" \"\$@\" | \"$real_sed\" '\$d'" >"$fake_bin/sed"
	chmod +x "$fake_bin/sed"
	PATH="$fake_bin:$PATH"
	local -a escaped=()
	local status_code=0

	# Act(1 回目は 0xC2 の無い値だけ = sed 1 回。2 回目は 0xC2 のある値 = sed 2 回と tr 1 回)
	cli_field_escape_batch escaped $'a\033' 'b' 'c' || status_code=$?
	local first_failed="$CLI_FIELD_BATCH_FAILED_COMMANDS" first_count="${#escaped[@]}" second_status=0
	cli_field_escape_batch escaped $'a\033' $'b\xc2\x85' 'c' || second_status=$?

	# Assert
	[ "$status_code" -eq 1 ]
	[ "$first_count" -eq 0 ]
	[ "$first_failed" = "sed" ]
	[ "$second_status" -eq 1 ]
	[ "${#escaped[@]}" -eq 0 ]
	[ "$CLI_FIELD_BATCH_FAILED_COMMANDS" = "sed,tr" ]
}

@test "cli_field_escape_batch_どの値にも0xC2が無く空の値も無い場合_trを使わずsedだけで置き換えること" {
	# Arrange(tr を失敗するものに差し替えても成功する = tr を起動していない。制御文字 31 種(改行を除く)と DEL、多バイト文字、空白だけの値)
	install_failing_command tr
	local values=("K${CLI_FIELD_CONTROL_CHARS//$'\n'/}" $'\xe3\x81\x82\033' ' ' 'plain' $'two\nlines') index
	local -a escaped=()

	# Act
	cli_field_escape_batch escaped "${values[@]}"

	# Assert
	[ "${#escaped[@]}" -eq 5 ]
	for index in "${!values[@]}"; do
		reference_escape "${values[index]}"
		[ "${escaped[index]}" = "$REFERENCE_ESCAPED" ]
	done
	[ "${escaped[2]}" = ' ' ]
	[ "${escaped[4]}" = 'two\nlines' ]
}

@test "cli_field_escape_batch_0xC2の無い値だけの中に空の値がある場合_値の境目を取り違えず同じ並びで返すこと" {
	# Arrange(空の値があるときは、値の終わりの目印で区切る経路を使う)
	local -a escaped=()

	# Act
	cli_field_escape_batch escaped $'a\033' '' 'c' ''

	# Assert
	[ "${#escaped[@]}" -eq 4 ]
	[ "${escaped[0]}" = 'a\u001b' ]
	[ "${escaped[1]}" = '' ]
	[ "${escaped[2]}" = 'c' ]
	[ "${escaped[3]}" = '' ]
}

@test "cli_field_escape_batch_失敗の後に成功した場合_失敗したコマンド名を空に戻すこと" {
	# Arrange
	local saved_path="$PATH" status_code=0
	local -a escaped=()
	install_failing_command sed
	cli_field_escape_batch escaped $'a\033' || status_code=$?
	PATH="$saved_path"

	# Act
	cli_field_escape_batch escaped $'a\033'

	# Assert
	[ "$status_code" -eq 1 ]
	[ "${escaped[0]}" = 'a\u001b' ]
	[ -z "$CLI_FIELD_BATCH_FAILED_COMMANDS" ]
}

@test "cli_field_safe_text_list_値の合計が小さい場合_外部コマンドを使わず値ごとの結果と同じ並びで返すこと" {
	# Arrange(sed と tr を失敗するものに差し替えても結果が変わらない = 外部コマンドを起動していない)
	install_failing_command sed
	install_failing_command tr
	local -a shown=()

	# Act
	cli_field_safe_text_list shown 'BLUE_MODE' $'K\033' '' $'tab\there'

	# Assert
	[ "${#shown[@]}" -eq 4 ]
	[ "${shown[0]}" = 'BLUE_MODE' ]
	[ "${shown[1]}" = 'K\u001b' ]
	[ "${shown[2]}" = '' ]
	[ "${shown[3]}" = 'tab\there' ]
}

@test "cli_field_safe_text_list_値が0個の場合_空の配列を返すこと" {
	# Arrange
	local -a shown=(stale)

	# Act
	cli_field_safe_text_list shown

	# Assert
	[ "${#shown[@]}" -eq 0 ]
}

@test "cli_field_safe_text_list_値の合計が大きい場合_値ごとのcli_field_safe_textと同じ結果を同じ並びで返すこと" {
	# Arrange(合計が CLI_FIELD_ESCAPE_EXTERNAL_MIN_BYTES 以上。置き換えの要らない値と空の値も混ぜる)
	repeat_text $'\001\033\177\xc2\x85あ' 400
	local values=("K1$REPEATED" 'plain' '' $'\xc2\x9b' "K2$REPEATED"$'\n' 'GREEN_MODE') index
	local -a shown=()

	# Act
	cli_field_safe_text_list shown "${values[@]}"

	# Assert
	[ "${#shown[@]}" -eq 6 ]
	for index in "${!values[@]}"; do
		cli_field_safe_text "${values[index]}"
		[ "${shown[index]}" = "$CLI_FIELD_SAFE_TEXT" ]
	done
	[ "${shown[0]:0:26}" = 'K1\u0001\u001b\u007f\u0085' ]
	[ "${shown[1]}" = 'plain' ]
	[ "${shown[3]}" = '\u009b' ]
	[ "${shown[5]}" = 'GREEN_MODE' ]
}

@test "cli_field_safe_text_list_値の合計が大きくsedが失敗する場合_戻り値1で結果を空にし失敗したコマンド名を載せること" {
	# Arrange(呼び出し元は補助コマンドの失敗として扱うか、値ごとの cli_field_safe_text で置き換え直す)
	repeat_text $'\001\033\177\xc2\x85あ' 400
	local -a shown=(stale)
	local status_code=0
	install_failing_command sed

	# Act
	cli_field_safe_text_list shown "K1$REPEATED" 'plain' "K2$REPEATED" 2>"$BATS_TEST_TMPDIR/err.txt" || status_code=$?

	# Assert
	[ "$status_code" -eq 1 ]
	[ "${#shown[@]}" -eq 0 ]
	[ "$CLI_FIELD_BATCH_FAILED_COMMANDS" = "sed" ]
	[ ! -s "$BATS_TEST_TMPDIR/err.txt" ]
}

@test "cli_field_safe_text_大きな値でsedとtrが失敗する場合_外部コマンドを使わずbashだけで可視表記にすること" {
	# Arrange(値ごとの関数は外部コマンドを起動しない。他の検証種別の呼び出し元の挙動を変えない)
	repeat_text $'a\001\033\177\xc2\x85' 1000
	local value="$REPEATED"
	repeat_text 'a\u0001\u001b\u007f\u0085' 1000
	install_failing_command sed
	install_failing_command tr

	# Act
	cli_field_safe_text "$value" 2>"$BATS_TEST_TMPDIR/err.txt"

	# Assert
	[ "${#value}" -ge "$CLI_FIELD_ESCAPE_EXTERNAL_MIN_BYTES" ]
	[ "$CLI_FIELD_SAFE_TEXT" = "$REPEATED" ]
	[ "${#CLI_FIELD_SAFE_CACHE[@]}" -eq 0 ]
	[ ! -s "$BATS_TEST_TMPDIR/err.txt" ]
}

@test "cli_field_safe_text_prepare_値の合計が大きい場合_まとめて作った可視表記を控えcli_field_safe_textが外部コマンドなしで同じ結果を返すこと" {
	# Arrange(大きな値 2 つ(置き換えの要る値と要らない値)と小さな値。空の値は控えない)
	repeat_text $'a\001\033\177\xc2\x85' 1000
	local big="$REPEATED"
	repeat_text 'a\u0001\u001b\u007f\u0085' 1000
	local big_shown="$REPEATED"
	repeat_text 'abc def/ghi=jkl ' 600
	local plain="$REPEATED"

	# Act(控えた後は sed と tr が失敗しても結果が変わらない)
	cli_field_safe_text_prepare "$big" '' "$plain" $'s\033'
	install_failing_command sed
	install_failing_command tr
	cli_field_safe_text "$big"
	local first="$CLI_FIELD_SAFE_TEXT"
	cli_field_safe_text "$plain"
	local second="$CLI_FIELD_SAFE_TEXT"
	cli_field_safe_text $'s\033'

	# Assert
	[ "$first" = "$big_shown" ]
	[ "$second" = "$plain" ]
	[ "$CLI_FIELD_SAFE_TEXT" = 's\u001b' ]
	[ "${#CLI_FIELD_SAFE_CACHE[@]}" -eq 3 ]
}

@test "cli_field_safe_text_prepare_値の合計が小さい場合_外部コマンドを使わず控えも作らないこと" {
	# Arrange
	install_failing_command sed
	install_failing_command tr

	# Act
	cli_field_safe_text_prepare 'foreground' $'x\033' '' '/opt/app/bin/runner.sh'

	# Assert(表示のときに bash で置き換える)
	[ "${#CLI_FIELD_SAFE_CACHE[@]}" -eq 0 ]
	cli_field_safe_text $'x\033'
	[ "$CLI_FIELD_SAFE_TEXT" = 'x\u001b' ]
}

@test "cli_field_safe_text_prepare_値の合計が大きくtrが失敗する場合_戻り値1で控えを変えず失敗したコマンド名を載せること" {
	# Arrange
	repeat_text $'a\001\033\177\xc2\x85' 1000
	local status_code=0
	install_failing_command tr
	# (値に 0xC2 があるため tr を使う)

	# Act
	cli_field_safe_text_prepare "$REPEATED" 2>"$BATS_TEST_TMPDIR/err.txt" || status_code=$?

	# Assert
	[ "$status_code" -eq 1 ]
	[ "${#CLI_FIELD_SAFE_CACHE[@]}" -eq 0 ]
	[ "$CLI_FIELD_BATCH_FAILED_COMMANDS" = "tr" ]
	[ ! -s "$BATS_TEST_TMPDIR/err.txt" ]
}

@test "cli_field_safe_text_prepare_値に改行と配列の添字として特別な文字を含む場合_値ごとに別の可視表記を控えること" {
	# Arrange(控えの添字に値を使う。@ / * / 式に見える値を取り違えない。合計を大きくするための埋め草を足す)
	repeat_text 'x' 5000
	local filler="$REPEATED" value
	local values=($'@\033' $'*\033' $'a[$(echo x)]\033' $'1+1\033' $']\n\033')

	# Act
	cli_field_safe_text_prepare "$filler" "${values[@]}"

	# Assert
	[ "${#CLI_FIELD_SAFE_CACHE[@]}" -eq 6 ]
	for value in "${values[@]}"; do
		cli_field_safe_text "$value"
		reference_escape "$value"
		[ "$CLI_FIELD_SAFE_TEXT" = "$REFERENCE_ESCAPED" ]
	done
	cli_field_safe_text $']\n\033'
	[ "$CLI_FIELD_SAFE_TEXT" = ']\n\u001b' ]
}

@test "cli_field_line_まとめて控えた大きな値に制御文字と空白を含む場合_元の値の空白で形式を選び可視表記で出すこと" {
	# Arrange(形式は元の値で決める。表示する値は控えた可視表記)
	repeat_text $'v\033' 3000
	local value="$REPEATED"
	repeat_text 'v\u001b' 3000
	cli_field_safe_text_prepare "$value " "$value"

	# Act
	run cli_field_line impl "$value "
	local with_space="$output"
	run cli_field_line impl "$value"

	# Assert
	[ "$with_space" = "impl: $REPEATED " ]
	[ "$output" = "impl=$REPEATED" ]
}

@test "cli_field_safe_text_控えの合計が上限を超える場合_超える分は控えずに毎回同じ可視表記を返すこと" {
	# Arrange(控えの合計に上限がある。入力の大きさに上限は無いため、メモリの使用量を入力の大きさに比例させない)
	CLI_FIELD_SAFE_CACHE_MAX_TOTAL_BYTES=40
	local first=$'A\033' second=$'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\033' third=$'C\033'

	# Act
	cli_field_safe_text "$first"
	local shown_first="$CLI_FIELD_SAFE_TEXT"
	cli_field_safe_text "$second"
	local shown_second="$CLI_FIELD_SAFE_TEXT"
	cli_field_safe_text "$third"
	local shown_third="$CLI_FIELD_SAFE_TEXT"
	cli_field_safe_text "$second"

	# Assert(1 つ目(2 + 7 バイト)と 3 つ目(2 + 7 バイト)は控え、2 つ目(31 + 36 バイト)は控えない)
	[ "$shown_first" = 'A\u001b' ]
	[ "$shown_second" = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\u001b' ]
	[ "$shown_third" = 'C\u001b' ]
	[ "$CLI_FIELD_SAFE_TEXT" = "$shown_second" ]
	[ "${#CLI_FIELD_SAFE_CACHE[@]}" -eq 2 ]
	[ "$CLI_FIELD_SAFE_CACHE_TOTAL_BYTES" -eq 18 ]
}

@test "cli_field_safe_text_prepare_同じ値を2回以上渡した場合_1回だけ控え合計を二重に数えないこと" {
	# Arrange(mode 3 キーが同じ値のときなど)
	repeat_text $'m\033' 2500
	local value="$REPEATED"

	# Act
	cli_field_safe_text_prepare "$value" "$value" 'off' "$value"

	# Assert(元の値 5,000 バイト + 可視表記 17,500 バイト。小さな値 off も一緒に控える)
	[ "${#CLI_FIELD_SAFE_CACHE[@]}" -eq 2 ]
	[ "$CLI_FIELD_SAFE_CACHE_TOTAL_BYTES" -eq $((5000 + 17500 + 3 + 3)) ]
	cli_field_safe_text "$value"
	[ "${CLI_FIELD_SAFE_TEXT:0:14}" = 'm\u001bm\u001b' ]
}

@test "cli_field_print_safe_text_控えにある値と無い値の場合_どちらもcli_field_safe_textと同じバイト列を改行なしで出すこと" {
	# Arrange(控えにある大きな値は、控えから直接出す)
	repeat_text $'p\033' 2500
	local big="$REPEATED"
	repeat_text 'p\u001b' 2500
	local big_shown="$REPEATED"
	cli_field_safe_text_prepare "$big"

	# Act
	cli_field_print_safe_text "$big" >"$BATS_TEST_TMPDIR/big.txt"
	cli_field_print_safe_text $'small\t\xc2\x9b' >"$BATS_TEST_TMPDIR/small.txt"
	cli_field_print_safe_text 'plain' >"$BATS_TEST_TMPDIR/plain.txt"
	cli_field_print_safe_text '' >"$BATS_TEST_TMPDIR/empty.txt"

	# Assert
	[ "$(cat "$BATS_TEST_TMPDIR/big.txt")" = "$big_shown" ]
	[ "$(wc -c <"$BATS_TEST_TMPDIR/big.txt" | tr -d ' ')" -eq 17500 ]
	[ "$(cat "$BATS_TEST_TMPDIR/small.txt")" = 'small\t\u009b' ]
	[ "$(wc -c <"$BATS_TEST_TMPDIR/small.txt" | tr -d ' ')" -eq 13 ]
	[ "$(cat "$BATS_TEST_TMPDIR/plain.txt")" = 'plain' ]
	[ ! -s "$BATS_TEST_TMPDIR/empty.txt" ]
}

@test "cli_field_lineとcli_path_field_line_値が空や空白や制御文字の場合_空値は-で形式は元の値で選ぶこと" {
	# Arrange / Act
	run cli_field_line impl ''
	local empty_field="$output"
	run cli_path_field_line runner ''
	local empty_path="$output"
	run cli_field_line impl $'a\tb'
	local tab_field="$output"
	run cli_field_line impl $'a\033b'
	local esc_field="$output"
	run cli_path_field_line runner $'/opt/x\033'

	# Assert(タブは空白なので `key: value`。ESC は空白ではないので `key=value`)
	[ "$empty_field" = 'impl=-' ]
	[ "$empty_path" = 'runner: -' ]
	[ "$tab_field" = 'impl: a\tb' ]
	[ "$esc_field" = 'impl=a\u001bb' ]
	[ "$output" = 'runner: /opt/x\u001b' ]
}
