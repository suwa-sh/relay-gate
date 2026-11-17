#!/usr/bin/env bats
# UC eff24f55 × tier-facade: domain 層 JobMap の「報告行の可視表記を後からまとめて作る」経路の単体テスト。
# 仕様: tier-facade.md「出力契約」(任意入力の制御文字は可視表記。cli-command-contract.yaml conventions.output_format.control_chars)
# JOB_MAP_REPORT_DEFER_ESCAPE=true のとき、報告行に元の値を埋め込み、usecase が行全体をまとめて置き換える。
# 行全体を置き換えた結果が、値ごとに置き換えた結果(JOB_MAP_REPORT_DEFER_ESCAPE=false)と同じバイト列になることを確かめる。
# S4 tier-impl(2026-11-16 attempt-6)で追加: 性能の目標値(config_input_rules.performance_target)に近づけるための変更の確認。

HEADER_9=(job_id host user work_dir script fixed_params hang_detect_limit_minutes credential_ref map_version)

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/cli_field.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/job_map.sh"
	load cli_field_reference
	# 値の境界をまたいで C1 制御文字に見える並び(0xC2 で終わる値・0x85 で始まる値)と、置き換える文字すべてを含む値
	TRICKY=$'a\001\t\033\x7f\xc2\x85\xe3\x81\x82\xc2'
	TRICKY_HEAD=$'\x85\x9f\037b'
}

# 報告行を、値ごとに置き換える経路と、行全体をまとめて置き換える経路の両方で作る。
# 結果は LINES_PER_VALUE / LINES_DEFERRED(行を改行でつないだもの)
# 引数: 実行するコマンド...(JOB_MAP_REPORT_LINES に報告行を溜めるもの)
emit_both_ways() {
	local shown=() line
	JOB_MAP_REPORT_SINK="$JOB_MAP_REPORT_SINK_ARRAY"
	JOB_MAP_REPORT_DEFER_ESCAPE=false
	JOB_MAP_REPORT_LINES=()
	"$@" || true
	LINES_PER_VALUE="$(printf '%s\n' "${JOB_MAP_REPORT_LINES[@]}")"
	JOB_MAP_REPORT_DEFER_ESCAPE=true
	JOB_MAP_REPORT_LINES=()
	"$@" || true
	JOB_MAP_REPORT_DEFER_ESCAPE=false
	# usecase と同じく、行ごとに cli_field_safe_text と同じ規則で置き換える
	for line in "${JOB_MAP_REPORT_LINES[@]}"; do
		cli_field_safe_text "$line"
		shown+=("$CLI_FIELD_SAFE_TEXT")
	done
	LINES_DEFERRED="$(printf '%s\n' "${shown[@]}")"
}

# 行の検証と解決結果の行を、1 行分続けて出す
# 引数: cells...(HEADER_9 の並び)
validate_and_resolve() {
	job_map_header_bind "${HEADER_9[@]}"
	job_map_row_bind "$@"
	if validate_job_map_row 2; then
		job_map_row_resolved_line
	fi
}

@test "job_map_shown_value_JOB_MAP_REPORT_DEFER_ESCAPEがtrueの場合_元の値のままにすること" {
	# Arrange
	JOB_MAP_REPORT_DEFER_ESCAPE=true

	# Act
	job_map_shown_value "$TRICKY"

	# Assert
	[ "$JOB_MAP_SHOWN" = "$TRICKY" ]
}

@test "job_map_shown_value_JOB_MAP_REPORT_DEFER_ESCAPEがfalseの場合_可視表記にすること" {
	# Arrange
	reference_escape "$TRICKY"

	# Act
	job_map_shown_value "$TRICKY"

	# Assert
	[ "$JOB_MAP_SHOWN" = "$REFERENCE_ESCAPED" ]
}

@test "job_map_fixed_params_json_join_状態機械で解析した値の場合_後から行全体を可視表記にした表記がjob_map_fixed_params_json_buildと同じになること" {
	# Arrange(`\"` `\\` `\/` `\n` `\t` のエスケープ、要素の外の空白、C1 制御文字・DEL・多バイト文字、0xC2 で終わる要素、空の要素)
	local tail=$'\x7f\xc2\x85\xe3\x81\x82\xc2' head=$'\x85\x9fb'
	job_map_fixed_params_parse '[ "a\"b\\c\/d\n\te'"$tail"'" , "'"$head"'","", "\\\"\n\n" ]'
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 4 ]
	job_map_fixed_params_json_build
	local expected="$JOB_MAP_FIXED_PARAMS_JSON"

	# Act
	job_map_fixed_params_json_join
	cli_field_safe_text "fixed_params=$JOB_MAP_FIXED_PARAMS_JSON hang"

	# Assert
	[ "$CLI_FIELD_SAFE_TEXT" = "fixed_params=$expected hang" ]
	[[ "$JOB_MAP_FIXED_PARAMS_JSON" != *$'\n'* ]]
}

@test "job_map_fixed_params_json_join_要素が無い場合_空の配列表記にすること" {
	# Arrange
	job_map_fixed_params_parse ' [ ] '

	# Act
	job_map_fixed_params_json_join

	# Assert
	[ "$JOB_MAP_FIXED_PARAMS_JSON" = "[]" ]
}

@test "validate_job_map_row_制御文字を含む値の違反がある場合_まとめて置き換えた行が値ごとに置き換えた行と同じになること" {
	# Arrange / Act(job_id・hang_detect_limit_minutes・fixed_params の違反と、host だけの行・credential_ref の warn)
	emit_both_ways validate_and_resolve "$TRICKY" "h$TRICKY_HEAD" "" /w /s "[\"$TRICKY\"]" "$TRICKY" "/k$TRICKY" "v$TRICKY"

	# Assert
	[ -n "$LINES_PER_VALUE" ]
	[ "$LINES_DEFERRED" = "$LINES_PER_VALUE" ]
	[ "$(printf '%s\n' "$LINES_PER_VALUE" | wc -l | tr -d ' ')" -eq 5 ]
}

@test "job_map_row_resolved_line_制御文字とJSONのエスケープを含む行の場合_まとめて置き換えた行が値ごとに置き換えた行と同じになること" {
	# Arrange(fixed_params の要素は `\"` `\\` `\n` `\t` のエスケープと、JSON の文字列にそのまま置ける C1 制御文字・DEL・多バイト文字を含む。
	#   要素の境界に 0xC2 / 0x85 を置く)
	local json_tail=$'\x7f\xc2\x85\xe3\x81\x82\xc2' json_head=$'\x85\x9fb'
	local fixed_params='["x\"y\\z\n\t'"$json_tail"'","'"$json_head"'",""]'

	# Act
	emit_both_ways validate_and_resolve J1 "h$TRICKY" "u$TRICKY_HEAD" "/w$TRICKY" "$TRICKY_HEAD/s$TRICKY" "$fixed_params" 60 ref map-v1

	# Assert
	[ "${LINES_PER_VALUE:0:22}" = "info: resolved job_id=" ]
	[ "$LINES_DEFERRED" = "$LINES_PER_VALUE" ]
}

@test "job_map_row_resolved_line_ローカル実行の行の場合_まとめて置き換えた行が値ごとに置き換えた行と同じになること" {
	# Arrange / Act
	emit_both_ways validate_and_resolve J1 "" "" "$TRICKY" "$TRICKY" '[]' 0 "" ""

	# Assert
	[[ "$LINES_PER_VALUE" == *"host=- user=- exec=local "* ]]
	[ "$LINES_DEFERRED" = "$LINES_PER_VALUE" ]
}

@test "validate_job_map_unique_job_ids_制御文字を含むjob_idが重複する場合_まとめて置き換えた行が値ごとに置き換えた行と同じになること" {
	# Arrange / Act
	emit_both_ways validate_job_map_unique_job_ids 2 "$TRICKY" 3 "$TRICKY_HEAD" 4 "$TRICKY" 5 "$TRICKY_HEAD"

	# Assert
	reference_escape "$TRICKY"
	[[ "$LINES_PER_VALUE" == "error: duplicate job_id job_id=$REFERENCE_ESCAPED lines=2,4"* ]]
	[ "$LINES_DEFERRED" = "$LINES_PER_VALUE" ]
}

@test "job_map_version_summary_制御文字を含む版が混在する場合_まとめて置き換えた行が値ごとに置き換えた行と同じになること" {
	# Arrange / Act
	emit_both_ways job_map_version_summary "$TRICKY" "$TRICKY_HEAD" ""

	# Assert
	[[ "$LINES_PER_VALUE" == "warn: mixed map_version values="* ]]
	[ "$LINES_DEFERRED" = "$LINES_PER_VALUE" ]
}

@test "job_map_fixed_params_parse_区切りだけの要素と空の要素がある場合_空の要素を落とさないこと" {
	# Arrange / Act / Assert(区切りを置き換えて単語分割で分ける早期判定の経路)
	job_map_fixed_params_parse '[""]'
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 1 ]
	[ "${JOB_MAP_FIXED_PARAMS[0]}" = "" ]
	job_map_fixed_params_parse '["","a",""]'
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 3 ]
	[ "${JOB_MAP_FIXED_PARAMS[0]}" = "" ]
	[ "${JOB_MAP_FIXED_PARAMS[1]}" = "a" ]
	[ "${JOB_MAP_FIXED_PARAMS[2]}" = "" ]
	job_map_fixed_params_parse '["a b","  "]'
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 2 ]
	[ "${JOB_MAP_FIXED_PARAMS[0]}" = "a b" ]
	[ "${JOB_MAP_FIXED_PARAMS[1]}" = "  " ]
}

@test "job_map_fixed_params_parse_globに一致する要素の場合_パス名展開をせず呼び出し元のset_fの状態を変えないこと" {
	# Arrange
	cd "$BATS_TEST_TMPDIR"
	touch a1 a2
	set +f

	# Act
	job_map_fixed_params_parse '["a*","a?","[a]"]'

	# Assert
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 3 ]
	[ "${JOB_MAP_FIXED_PARAMS[0]}" = "a*" ]
	[ "${JOB_MAP_FIXED_PARAMS[1]}" = "a?" ]
	[ "${JOB_MAP_FIXED_PARAMS[2]}" = "[a]" ]
	[[ "$-" != *f* ]]
}

@test "job_map_fixed_params_parse_要素が多数ある場合_早期判定と状態機械で同じ要素になること" {
	# Arrange(早期判定の形の値と、空白を足して状態機械で解析させる値。要素 300 個)
	local plain="[" spaced="[ " index
	for ((index = 0; index < 300; index++)); do
		plain+="\"e$index\","
		spaced+="\"e$index\" , "
	done
	plain+='"last"]'
	spaced+='"last" ]'

	# Act
	job_map_fixed_params_parse "$plain"
	local -a from_plain=("${JOB_MAP_FIXED_PARAMS[@]}")
	job_map_fixed_params_parse "$spaced"

	# Assert
	[ "${#from_plain[@]}" -eq 301 ]
	[ "${from_plain[299]}" = "e299" ]
	[ "${from_plain[300]}" = "last" ]
	[ "${JOB_MAP_FIXED_PARAMS[*]}" = "${from_plain[*]}" ]
}

@test "job_map_fixed_params_parse_長い要素にエスケープが多数ある場合_エスケープを解除して1つの要素にすること" {
	# Arrange(状態機械の経路。要素の値は断片を最後に 1 回だけつないで作る)
	local unit='ab\"c\\d\ne\t' expected_unit=$'ab"c\\d\ne\t' text="" expected="" index
	for ((index = 0; index < 300; index++)); do
		text+="$unit"
		expected+="$expected_unit"
	done

	# Act
	job_map_fixed_params_parse "[\"$text\",\"z\"]"

	# Assert
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 2 ]
	[ "${JOB_MAP_FIXED_PARAMS[0]}" = "$expected" ]
	[ "${JOB_MAP_FIXED_PARAMS[1]}" = "z" ]
}

@test "job_map_fixed_params_json_join_早期判定で解析した値の場合_job_map_fixed_params_json_buildと同じ表記になること" {
	# Arrange(エスケープも要素の外の空白も無い形。C1 制御文字・空白を含む要素と空の要素)
	job_map_fixed_params_parse '["a b","'$'\x7f\xc2\x85''","","x"]'
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 4 ]
	job_map_fixed_params_json_build
	local expected="$JOB_MAP_FIXED_PARAMS_JSON"

	# Act
	job_map_fixed_params_json_join
	cli_field_safe_text "$JOB_MAP_FIXED_PARAMS_JSON"

	# Assert
	[ "$CLI_FIELD_SAFE_TEXT" = "$expected" ]
}

@test "job_map_row_resolved_line_fixed_paramsが要素の外の空白とスラッシュのエスケープを含む場合_まとめて置き換えた行が値ごとに置き換えた行と同じになること" {
	# Arrange / Act(セルの値をそのまま表記に使えない形。要素を表記へ戻す経路)
	emit_both_ways validate_and_resolve J1 "" "" /w /s '[ "a\/b" , "c\\\"d\n\te" ,"'$'\xc2\x85''" ]' 60 "" ""

	# Assert
	[[ "$LINES_PER_VALUE" == *'fixed_params=["a/b","c\\\"d\n\te","\u0085"]'* ]]
	[ "$LINES_DEFERRED" = "$LINES_PER_VALUE" ]
}

@test "job_map_row_resolved_line_fixed_paramsが空白もスラッシュのエスケープも含まない場合_セルの値をそのまま表記に使い値ごとに置き換えた行と同じになること" {
	# Arrange / Act
	emit_both_ways validate_and_resolve J1 "" "" /w /s '["a\\b","c\"d\n","\t","'$'\x7f''",""]' 60 "" ""

	# Assert
	[[ "$LINES_PER_VALUE" == *'fixed_params=["a\\b","c\"d\n","\t","\u007f",""]'* ]]
	[ "$LINES_DEFERRED" = "$LINES_PER_VALUE" ]
}

@test "job_map_replace_char_区切りが連続し先頭と末尾にもある場合_すべて置き換えること" {
	# Arrange / Act / Assert(置き換え後の文字列の % と \ は書式として解釈しない)
	job_map_replace_char '\a\\b\' '\' '%\\'
	[ "$JOB_MAP_REPLACED" = '%\\a%\\%\\b%\\' ]
	job_map_replace_char '' '"' 'x'
	[ "$JOB_MAP_REPLACED" = '' ]
	job_map_replace_char '"' '"' '\"'
	[ "$JOB_MAP_REPLACED" = '\"' ]
	job_map_replace_char 'a*b' '"' 'x'
	[ "$JOB_MAP_REPLACED" = 'a*b' ]
}

@test "job_map_fixed_params_chunks_引用符とバックスラッシュを含む値の場合_つなぐと元の値になり断片は引用符の後とバックスラッシュの前で分かれること" {
	# Arrange / Act
	job_map_fixed_params_chunks '["a\\b\"c",""]'

	# Assert
	local joined
	printf -v joined '%s' "${JOB_MAP_PARSE_CHUNKS[@]}"
	[ "$joined" = '["a\\b\"c",""]' ]
	[ "${JOB_MAP_PARSE_CHUNKS[0]}" = '["' ]
	[ "${JOB_MAP_PARSE_CHUNKS[1]}" = 'a' ]
	[ "${JOB_MAP_PARSE_CHUNKS[2]}" = '\' ]
	[ "${JOB_MAP_PARSE_CHUNKS[3]}" = '\b' ]
	[ "${JOB_MAP_PARSE_CHUNKS[4]}" = '\"' ]
}

@test "job_map_fixed_params_parse_区切りが不正な値の場合_早期判定と状態機械のどちらでも1を返すこと" {
	# Arrange / Act / Assert
	local text
	for text in '["a",,"b"]' '["a""b"]' '["a","b""]' '["a"x"b"]' '[""",""]' '["a",]' '["a" "b"]'; do
		run job_map_fixed_params_parse "$text"
		[ "$status" -eq 1 ]
	done
}

@test "validate_job_map_header_制御文字を含む未知の列名と重複した列名がある場合_まとめて置き換えた行が値ごとに置き換えた行と同じになること" {
	# Arrange / Act(未知の列名の warn、列名の重複の error、必須列の欠落の error。パスにも制御文字)
	emit_both_ways validate_job_map_header "m$TRICKY.csv" job_id "$TRICKY" "$TRICKY_HEAD" "$TRICKY" work_dir script

	# Assert
	reference_escape "$TRICKY"
	[[ "$LINES_PER_VALUE" == "warn: unknown column column=$REFERENCE_ESCAPED path: "* ]]
	[ "$(printf '%s\n' "$LINES_PER_VALUE" | wc -l | tr -d ' ')" -eq 5 ]
	[ "$LINES_DEFERRED" = "$LINES_PER_VALUE" ]
}

@test "job_map_is_defined_column_契約の9列と未知の列名と空の列名の場合_契約の9列だけを0で返すこと" {
	# Arrange / Act / Assert
	local column
	for column in "${HEADER_9[@]}"; do
		job_map_is_defined_column "$column"
	done
	run job_map_is_defined_column impl_version
	[ "$status" -eq 1 ]
	run job_map_is_defined_column ""
	[ "$status" -eq 1 ]
	run job_map_is_defined_column "job_id "
	[ "$status" -eq 1 ]
}
