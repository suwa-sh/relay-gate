#!/usr/bin/env bats
# UC eff24f55 × tier-facade: repository 層 csv_parse の 2 つの経路(窓なしの単語分割 / 窓ありの状態機械)が同じ結果になることの単体テスト。
# 仕様: tier-facade.md「設定契約(slot ジョブマップ CSV)」CSV セルのクォート解析規則
#       (cli-command-contract.yaml config_files[<slot>-job-map.csv].csv_rules。bash 単独で解析する)
# 既定はすべての行を窓なしで解析する(CSV_PARSE_SHORT_MAX_BYTES が空)。窓ありの状態機械は CSV_PARSE_SHORT_MAX_BYTES=0 で選ぶ。
# S4 tier-impl(2026-11-16 attempt-6)で追加: 性能の目標値(config_input_rules.performance_target)に近づけるため、
# 長い行も窓なしで解析するようにした変更の確認。

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/repository/job_map_repo.sh"
}

# 経路ごとの結果(戻り値とセル)を 1 つの文字列にする。セルの区切りは改行(セルは改行を含まない)。結果は PARSE_RESULT
# 引数: line
parse_result() {
	local status=0
	csv_parse "$1" || status=$?
	PARSE_RESULT="status=$status"
	if [ "$status" -eq 0 ]; then
		PARSE_RESULT+=$'\n'"count=${#CSV_CELLS[@]}"
		local cell
		for cell in "${CSV_CELLS[@]}"; do
			PARSE_RESULT+=$'\n'"[$cell]"
		done
	fi
}

# 窓なしと、窓の大きさを変えた状態機械で同じ結果になるか
# 引数: line
assert_same_on_all_paths() {
	local line="$1" short window
	CSV_PARSE_SHORT_MAX_BYTES=""
	parse_result "$line"
	short="$PARSE_RESULT"
	for window in 1 2 3 1024; do
		CSV_PARSE_SHORT_MAX_BYTES=0
		CSV_PARSE_WINDOW_BYTES="$window"
		parse_result "$line"
		if [ "$PARSE_RESULT" != "$short" ]; then
			printf 'line=%s window=%s\nshort:\n%s\nstate machine:\n%s\n' "$line" "$window" "$short" "$PARSE_RESULT" >&2
			return 1
		fi
	done
	CSV_PARSE_SHORT_MAX_BYTES=""
	CSV_PARSE_WINDOW_BYTES=1024
}

@test "csv_parse_既定の場合_窓の大きさより長い行も窓なしの解析で分解すること" {
	# Arrange(窓を 1 バイトにしても、既定では窓なしの解析を使う。窓なしの解析は窓の大きさを読まない)
	CSV_PARSE_WINDOW_BYTES=1
	csv_parse_short() {
		CSV_CELLS=(short-path)
		return 0
	}

	# Act
	csv_parse 'J1,"a""b",60'

	# Assert
	[ "${CSV_CELLS[*]}" = "short-path" ]
}

@test "csv_parse_CSV_PARSE_SHORT_MAX_BYTESより長い行の場合_窓ありの状態機械で分解すること" {
	# Arrange
	CSV_PARSE_SHORT_MAX_BYTES=4
	csv_parse_short() {
		CSV_CELLS=(short-path)
		return 0
	}

	# Act
	csv_parse 'J1,"a""b",60'

	# Assert(5 バイト以上の行は状態機械。4 バイト以下は窓なし)
	[ "${#CSV_CELLS[@]}" -eq 3 ]
	[ "${CSV_CELLS[1]}" = 'a"b' ]
	csv_parse 'J1,x'
	[ "${CSV_CELLS[*]}" = "short-path" ]
}

# bats test_tags=heavy
@test "csv_parse_引用符とカンマの並びが様々な行の場合_窓なしと窓ありの状態機械で同じ戻り値とセルになること" {
	# Arrange(受理する行とクォート不正の行の両方)
	local -a samples=(
		'a,b,c'
		'a,,c,'
		','
		'""'
		'"",""'
		'"""",x'
		'""""""'
		'"""a""",b'
		'x,"a,b","c""d"",e",'
		'"[""p1"",""p2""]",60,"",'
		'J1,"""abc",60'
		'J1,"abc""",60'
		'J1,"a""""b",60'
		$'J1,"\t a\001b\x7f\xc2\x85\xe3\x81\x82",60'
		'J1,"abc"x,60'
		'J1,"abc'
		'J1,ab"c,60'
		'J1,"a"",60'
		'"a"b'
		'"'
		'a,"'
		'a,"b""'
	)
	local sample

	# Act / Assert
	for sample in "${samples[@]}"; do
		assert_same_on_all_paths "$sample"
	done
}

# bats test_tags=heavy
@test "csv_parse_長い囲みセルに二重化された引用符が多数ある場合_引用符を1文字ずつに戻して1つのセルにすること" {
	# Arrange(`""` 300 個。窓なしの解析は `""` の数によらず値を 1 回だけつなぐ)
	local unit='abc""' value_unit='abc"' cell="" expected="" index
	for ((index = 0; index < 300; index++)); do
		cell+="$unit"
		expected+="$value_unit"
	done

	# Act
	csv_parse "J1,\"$cell\",60"

	# Assert
	[ "${#CSV_CELLS[@]}" -eq 3 ]
	[ "${CSV_CELLS[0]}" = "J1" ]
	[ "${CSV_CELLS[1]}" = "$expected" ]
	[ "${CSV_CELLS[2]}" = "60" ]
	assert_same_on_all_paths "J1,\"$cell\",60"
}

@test "csv_parse_窓なしで解析した場合_パス名展開をせず呼び出し元のset_fの状態を変えないこと" {
	# Arrange(作業ディレクトリに glob に一致するファイルを置く)
	cd "$BATS_TEST_TMPDIR"
	touch a1 a2
	set +f

	# Act
	csv_parse 'a*,"a?",[a]'

	# Assert
	[ "${CSV_CELLS[0]}" = "a*" ]
	[ "${CSV_CELLS[1]}" = "a?" ]
	[ "${CSV_CELLS[2]}" = "[a]" ]
	[[ "$-" != *f* ]]
}
