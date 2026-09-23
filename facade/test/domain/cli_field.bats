#!/usr/bin/env bats
# UC fd678b04 × tier-facade: domain 層 CLI 出力フィールド(ui-design.md「出力フォーマット」)の単体テスト。
# 任意文字列の値(echo がオプションとして解釈する `-n` 等・空白を含む値)の境界を検証する。

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/cli_field.sh"
}

@test "cli_field_line_値に空白を含まない場合_key=value形式で出すこと" {
	# Arrange / Act
	run cli_field_line blue_impl blue-2.3.1

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "blue_impl=blue-2.3.1" ]
}

@test "cli_field_line_値に半角空白を含む場合_key: value形式で出すこと" {
	# Arrange / Act
	run cli_field_line green_impl "release 1"

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "green_impl: release 1" ]
}

@test "cli_field_line_値にタブを含む場合_key: value形式でタブを可視表記にして出すこと" {
	# Arrange / Act(形式は元の値の空白で決める。生のタブは出さない)
	run cli_field_line green_impl $'rel\t1'

	# Assert
	[ "$output" = 'green_impl: rel\t1' ]
}

@test "cli_field_line_値が空の場合_空値表記-で出すこと" {
	# Arrange / Act
	run cli_field_line blue_impl ""

	# Assert
	[ "$output" = "blue_impl=-" ]
}

@test "cli_field_line_値が-nの場合_echoのオプションと解釈せず値を保持すること" {
	# Arrange / Act
	run cli_field_line green_impl -n

	# Assert
	[ "$output" = "green_impl=-n" ]
}

@test "cli_field_line_値が-eの場合_echoのオプションと解釈せず値を保持すること" {
	# Arrange / Act
	run cli_field_line green_impl -e

	# Assert
	[ "$output" = "green_impl=-e" ]
}

@test "cli_field_line_値が-neの場合_echoのオプションと解釈せず値を保持すること" {
	# Arrange / Act
	run cli_field_line green_impl -ne

	# Assert
	[ "$output" = "green_impl=-ne" ]
}

@test "cli_path_field_line_パス値の場合_空白の有無によらずkey: value形式で出すこと" {
	# Arrange / Act
	run cli_path_field_line blue_runner /opt/relay-gate/runners/blue-runner.sh

	# Assert
	[ "$output" = "blue_runner: /opt/relay-gate/runners/blue-runner.sh" ]
}

@test "cli_path_field_line_値が空の場合_key: -で出すこと" {
	# Arrange / Act
	run cli_path_field_line blue_runner ""

	# Assert
	[ "$output" = "blue_runner: -" ]
}

@test "cli_field_display_value_値が-nの場合_そのまま出力すること" {
	# Arrange / Act
	run cli_field_display_value -n

	# Assert
	[ "$output" = "-n" ]
}

# --- 制御文字の可視表記(UC eff24f55 attempt 3 の独立検証 F-001。ANSI 禁止と 1 行 1 事実) ---

# cli_field_safe_text の結果(グローバル)を stdout へ出す(run で受けるため)
safe_text() {
	cli_field_safe_text "$1"
	printf '%s' "$CLI_FIELD_SAFE_TEXT"
}

# 制御文字(U+0001〜U+001F と U+007F)の生バイトを含むか
has_control_byte() {
	local LC_ALL=C
	[[ "$1" == *[$'\001'-$'\037'$'\177']* ]]
}

@test "cli_field_safe_text_ESCを含む値の場合_u001bの可視表記に置き換えること" {
	# Arrange / Act
	run safe_text $'\033[31mred\033[0m'

	# Assert
	[ "$output" = '\u001b[31mred\u001b[0m' ]
}

@test "cli_field_safe_text_改行とタブとCRとDELを含む値の場合_1行の可視表記に置き換えること" {
	# Arrange / Act
	run safe_text $'a\nb\tc\rd\177e'

	# Assert
	[ "$output" = 'a\nb\tc\u000dd\u007fe' ]
}

@test "cli_field_safe_text_UTF-8で符号化したC1制御文字を含む値の場合_u0080からu009fの可視表記に置き換えること" {
	# Arrange / Act(U+009B は端末が CSI として解釈する。U+0080 と U+009F は範囲の両端)
	run safe_text $'a\xc2\x9b31mb\xc2\x80c\xc2\x9fd'

	# Assert
	[ "$output" = 'a\u009b31mb\u0080c\u009fd' ]
}

@test "cli_field_safe_text_制御文字を含まない値の場合_1バイトも変えないこと" {
	# Arrange(印字可能な ASCII 全部・バックスラッシュ・引用符・多バイト文字・C1 の範囲のすぐ外 U+00A0 と U+007E)
	local value=' !"#$%&'"'"'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~'
	value+=$'\\n\\u001b 日本語 \xf0\x9f\x98\x80 \xc2\xa0 \xc2\xbf \xc3\x80'

	# Act
	run safe_text "$value"

	# Assert
	[ "$output" = "$value" ]
}

@test "cli_field_safe_text_UTF-8として不正なバイトを含む値の場合_制御文字だけを置き換えて他のバイトを変えないこと" {
	# Arrange(パスは任意のバイト列になりうる。0xc2 の直後が継続バイトでない並びも壊さない)
	local value=$'a\xffb\xc2c\033d'

	# Act
	run safe_text "$value"

	# Assert
	[ "$output" = $'a\xffb\xc2c\\u001bd' ]
}

@test "cli_field_safe_text_取り込みの窓の境界に制御文字がある長い値の場合_全部を可視表記に置き換えること" {
	# Arrange(窓 1024 バイトの末尾と先頭に ESC と C1 を置く)
	local head tail
	head="$(printf '%*s' 1023 '')"
	head="${head// /a}"
	tail="$(printf '%*s' 3000 '')"
	tail="${tail// /b}"

	# Act
	run safe_text "$head"$'\033\033'"$tail"$'\xc2\x9b'"$head"$'\xc2'$'\x85'

	# Assert
	[ "$output" = "$head"'\u001b\u001b'"$tail"'\u009b'"$head"'\u0085' ]
}

@test "cli_field_escape_text_取り込みの窓が1バイトの場合_2バイトのC1制御文字と通常の2バイト文字を窓の大きさに関係なく判定すること" {
	# Arrange / Act(0xc2 の次のバイトを取り込んでから判定する。末尾が 0xc2 だけの不正な並びも壊さない)
	cli_field_escape_text $'a\xc2\x9bb\xc2\xa0\033"\\\xc2' '"\' 1

	# Assert
	[ "$CLI_FIELD_ESCAPED" = $'a\\u009bb\xc2\xa0\\u001b\\"\\\\\xc2' ]
}

@test "cli_field_line_ESCを含む値の場合_生のESCを出さずkey=value形式で出すこと" {
	# Arrange / Act
	run cli_field_line map_version $'\033[31mred\033[0m'

	# Assert
	[ "$output" = 'map_version=\u001b[31mred\u001b[0m' ]
	! has_control_byte "$output"
}

@test "cli_field_line_改行を含む値の場合_1行で出すこと" {
	# Arrange / Act
	run cli_field_line map_version $'v1\nrows=999'

	# Assert
	[ "${#lines[@]}" -eq 1 ]
	[ "$output" = 'map_version: v1\nrows=999' ]
}

@test "cli_path_field_line_改行とESCを含むパスの場合_1行で可視表記にして出すこと" {
	# Arrange / Act
	run cli_path_field_line map_path $'/tmp/ma\np\033.csv'

	# Assert
	[ "${#lines[@]}" -eq 1 ]
	[ "$output" = 'map_path: /tmp/ma\np\u001b.csv' ]
}

@test "cli_field_display_value_制御文字を含む値の場合_可視表記にして出すこと" {
	# Arrange / Act
	run cli_field_display_value $'a\033b'

	# Assert
	[ "$output" = 'a\u001bb' ]
}

@test "cli_field_line_制御文字を含まない値の場合_可視表記の導入前と同じバイト列を出すこと" {
	# Arrange(先行 UC の出力を変えないこと。空白あり・なし・多バイト・バックスラッシュ)
	local spaced='release 1 \n 日本語' plain='blue-2.3.1\t日本語'

	# Act / Assert
	run cli_field_line green_impl "$spaced"
	[ "$output" = "green_impl: $spaced" ]
	run cli_field_line blue_impl "$plain"
	[ "$output" = "blue_impl=$plain" ]
	run cli_path_field_line blue_runner "/opt/relay gate/日本語/runner.sh"
	[ "$output" = "blue_runner: /opt/relay gate/日本語/runner.sh" ]
}
