#!/usr/bin/env bash
# 制御文字の可視表記(conventions.output_format.control_chars)の参照実装。テストの期待値を作る。
# 規則を 1 バイトずつ適用する(遅いが単純)。実装(domain/cli_field.sh)の置き換えの経路(bash の経路 / sed でまとめて変換する経路)
# とは別の書き方にして、どの経路でも同じバイト列になることを比べる。
# cli_field_escape_paths.bats と cli_field_batch.bats が load する(domain/cli_field.sh を source した後に使う)。

# 規則を 1 バイトずつ適用する参照実装。結果は REFERENCE_ESCAPED
# 引数: text [backslash_escaped_chars]
reference_escape() {
	local text="$1" backslash_escaped="${2:-}" index=0 char next number code
	local LC_ALL=C
	REFERENCE_ESCAPED=""
	while [ "$index" -lt "${#text}" ]; do
		char="${text:index:1}"
		index=$((index + 1))
		next="${text:index:1}"
		if [ "$char" = $'\xc2' ] && [[ -n "$next" && ! "$next" < $'\x80' && ! "$next" > $'\x9f' ]]; then
			printf -v number '%d' "'$next"
			printf -v code '%04x' "$((number & 255))"
			REFERENCE_ESCAPED+="\\u$code"
			index=$((index + 1))
		elif [ "$char" = $'\xc2' ]; then
			REFERENCE_ESCAPED+="$char"
		elif [ "$char" = $'\n' ]; then
			REFERENCE_ESCAPED+="\\n"
		elif [ "$char" = $'\t' ]; then
			REFERENCE_ESCAPED+="\\t"
		elif [ -n "$backslash_escaped" ] && [[ "$backslash_escaped" == *"$char"* ]]; then
			REFERENCE_ESCAPED+="\\$char"
		elif [[ "$CLI_FIELD_CONTROL_CHARS" == *"$char"* ]]; then
			printf -v code '%04x' "'$char"
			REFERENCE_ESCAPED+="\\u$code"
		else
			REFERENCE_ESCAPED+="$char"
		fi
	done
}

# 同じ文字列を count 回つなげる。結果は REPEATED
repeat_text() {
	local text="$1" count="$2" index
	REPEATED=""
	for ((index = 0; index < count; index++)); do
		REPEATED+="$text"
	done
}
