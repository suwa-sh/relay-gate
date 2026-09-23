#!/usr/bin/env bats
# UC eff24f55 × tier-facade: usecase 層 ValidateJobMapQuery の単体テスト。
# 仕様: tier-facade.md「出力契約」「UC ロジック」(全行を検査してから全件報告 / 読み取り専用)
# I/O 境界は実ファイル(一時ディレクトリ)で検証する。
# run は stdout と stderr を結合して受ける(既存テストと同じ方式。CI の bats 版に依存しない)。

HEADER_7='job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes'
HEADER_9='job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version'

setup() {
	SRC_DIR="$BATS_TEST_DIRNAME/../../src"
	# shellcheck source=/dev/null
	source "$SRC_DIR/domain/cli_field.sh"
	# shellcheck source=/dev/null
	source "$SRC_DIR/domain/job_map.sh"
	# shellcheck source=/dev/null
	source "$SRC_DIR/repository/job_map_repo.sh"
	# shellcheck source=/dev/null
	source "$SRC_DIR/usecase/validate_job_map.sh"
	MAP="$BATS_TEST_TMPDIR/map.csv"
}

# 結合出力に期待行があるか
output_has_line() {
	local expected="$1" line
	for line in "${lines[@]}"; do
		if [ "$line" = "$expected" ]; then
			return 0
		fi
	done
	return 1
}

@test "validate_job_map_query_ファイルが読めない場合_config file is not readableで2を返すこと" {
	# Arrange(ディレクトリは通常ファイルではない)
	mkdir "$BATS_TEST_TMPDIR/dir.csv"

	# Act
	run validate_job_map_query "$BATS_TEST_TMPDIR/dir.csv" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: config file is not readable path: $BATS_TEST_TMPDIR/dir.csv" ]
}

@test "validate_job_map_query_列順が入れ替わったヘッダーの場合_0を返すこと" {
	# Arrange
	{
		printf '%s\n' 'host,job_id,user,script,work_dir,fixed_params,hang_detect_limit_minutes,credential_ref,map_version'
		printf '%s\n' 'host-green-01,JOB001,batch,/opt/app/bin/job001.sh,/var/app/work,"[]",60,ssh-key-green,map-v3'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[1]}" = "rows=1" ]
	[ "${lines[2]}" = "map_version=map-v3" ]
}

@test "validate_job_map_query_コメント行と空行がある場合_データ行だけをrowsに数えること" {
	# Arrange
	{
		printf '%s\n' '# green slot'
		printf '%s\n' "$HEADER_7"
		printf '%s\n' ''
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60'
		printf '%s\n' '# JOB002 is not migrated yet'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[1]}" = "rows=1" ]
	[ "${lines[2]}" = "map_version=-" ]
}

@test "validate_job_map_query_複数の行に違反がある場合_全件を行番号付きで報告して2を返しstdoutを出さないこと" {
	# Arrange
	{
		printf '%s\n' "$HEADER_7"
		printf '%s\n' 'JOB001,host-green-01,,/var/app/work,/opt/app/bin/job001.sh,"[]",60'
		printf '%s\n' 'JOB002,host-green-01,batch,,/opt/app/bin/job002.sh,"[]",60m'
		printf '%s\n' 'JOB003,host-green-01,batch,/var/app/work,/opt/app/bin/job003.sh,"[]"'
		printf '%s\n' 'JOB004,host-green-01,batch,/var/app/work,/opt/app/bin/job004.sh,"[""p1""],60'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert(work_dir は非空のみ検証する。形式は検査しない)
	[ "$status" -eq 2 ]
	[ "${#lines[@]}" -eq 5 ]
	[ "${lines[0]}" = "error: user is empty line=2 job_id=JOB001 value=" ]
	[ "${lines[1]}" = "error: work_dir is empty line=3 job_id=JOB002 value=" ]
	[ "${lines[2]}" = "error: hang_detect_limit_minutes is not a non-negative integer line=3 job_id=JOB002 value=60m" ]
	[ "${lines[3]}" = "error: column count mismatch line=4 expected=7 actual=6" ]
	[ "${lines[4]}" = "error: csv quote is invalid line=5 path: $MAP" ]
}

@test "validate_job_map_query_job_idが重複する場合_duplicate job_idで2を返すこと" {
	# Arrange
	{
		printf '%s\n' "$HEADER_7"
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60'
		printf '%s\n' 'JOB002,host-green-01,batch,/var/app/work,/opt/app/bin/job002.sh,"[]",60'
		printf '%s\n' 'JOB003,host-green-01,batch,/var/app/work,/opt/app/bin/job003.sh,"[]",60'
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001b.sh,"[]",60'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: duplicate job_id job_id=JOB001 lines=2,5" ]
}

@test "validate_job_map_query_ヘッダーに必須列が無い場合_header mismatchだけを報告して行の列検証に進まないこと" {
	# Arrange(script 列が無い。データ行の hang_detect_limit_minutes も不正だが列検証には進まない)
	{
		printf '%s\n' 'job_id,host,user,work_dir,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,"[]",60m'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: job map header mismatch missing=script path: $MAP" ]
}

@test "validate_job_map_query_ヘッダー行がクォート不正の場合_ヘッダー行のcsv quote is invalidで2を返すこと" {
	# Arrange
	{
		printf '%s\n' 'job_id,"work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",0'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: csv quote is invalid line=1 path: $MAP" ]
}

@test "validate_job_map_query_空ファイルの場合_必須5列のheader mismatchで2を返すこと" {
	# Arrange
	: >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: job map header mismatch missing=job_id,work_dir,script,fixed_params,hang_detect_limit_minutes path: $MAP" ]
}

@test "validate_job_map_query_版が混在する場合_warnを出して0を返しmap_versionにdistinct値を出すこと" {
	# Arrange
	{
		printf '%s\n' "$HEADER_9"
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60,ssh-key-green,map-v3'
		printf '%s\n' 'JOB002,host-green-01,batch,/var/app/work,/opt/app/bin/job002.sh,"[]",60,ssh-key-green,map-v4'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 0 ]
	output_has_line "warn: mixed map_version values=map-v3,map-v4"
	output_has_line "map_version=map-v3,map-v4"
}

@test "validate_job_map_query_map_versionが空の行と値のある行が混在する場合_mixed map_versionのwarnを出して0を返すこと" {
	# Arrange(計算ルール「版の集計」: 列があれば全行の distinct 値。空も 1 つの値として数える)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,map_version'
		printf '%s\n' 'J1,/w,/s,[],60,'
		printf '%s\n' 'J2,/w,/s,[],60,v1'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 4 ]
	output_has_line "warn: mixed map_version values=-,v1"
	output_has_line "rows=2"
	output_has_line "map_version=-,v1"
}

@test "validate_job_map_query_map_version列があって全行空の場合_warnを出さずmap_version=-を返すこと" {
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,map_version'
		printf '%s\n' 'J1,/w,/s,[],60,'
		printf '%s\n' 'J2,/w,/s,[],60,'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[2]}" = "map_version=-" ]
}

@test "validate_job_map_query_fixed_paramsの文字列内に生のタブがある場合_fixed_paramsの違反で2を返すこと" {
	# Arrange(実バイト 0x09。エスケープした \t だけが JSON の文字列に置ける)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J1,/w,/s,"[""a\tb""]",60\n'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" true

	# Assert
	[ "$status" -eq 2 ]
	[ "${#lines[@]}" -eq 1 ]
	# value= は生のタブを出さず可視表記にする
	[ "$output" = 'error: fixed_params is not a json array of strings line=2 job_id=J1 value=["a\tb"]' ]
}

@test "validate_job_map_query_fixed_paramsの文字列内に生のCRがある場合_carriage return is not allowedで2を返しinfo resolvedを出さないこと" {
	# Arrange(実バイト 0x0d。CR はセル内でも形式違反(config_input_rules)なので、fixed_params の値検証には流さない。
	#         S4 attempt 5 再実行で旧期待値(fixed_params is not a json array of strings)を新仕様の文言へ書き換えた)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J1,/w,/s,"[""a\rb""]",60\n'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" true

	# Assert
	[ "$status" -eq 2 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "error: carriage return is not allowed line=2 path: $MAP" ]
	[ "${lines[1]}" = "hint: use LF line endings" ]
	[[ "$output" != *"info: resolved"* ]]
	[[ "$output" != *"is not a json array of strings"* ]]
}

@test "validate_job_map_query_fixed_paramsの文字列内に生のESCがある場合_info resolvedを出さず2を返すこと" {
	# Arrange(実バイト 0x1b)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J1,/w,/s,"[""a\033b""]",60\n'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" true

	# Assert
	[ "$status" -eq 2 ]
	[[ "$output" == "error: fixed_params is not a json array of strings line=2 job_id=J1 value="* ]]
	[[ "$output" != *"info: resolved"* ]]
}

# --- 入力の守備範囲(CLI 契約 config_input_rules。spec reflux 20260921_100000 で原因ごとの文言に変更) ---
# NUL / 不正な UTF-8 / BOM / CR は形式違反として原因ごとの error 行で拒否する(csv quote is invalid や header mismatch に流用しない)。

@test "validate_job_map_query_fixed_paramsの文字列内にNULバイトがある場合_その行のnul byte is not allowedで2を返しinfo resolvedを出さないこと" {
	# Arrange(実バイト 0x00。NUL を落とした ["ab"] を受理しない)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J1,/w,/s,"[""a\000b""]",60\n'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" true

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: nul byte is not allowed line=2 path: $MAP" ]
}

@test "validate_job_map_query_job_idにNULバイトがある場合_その行のnul byte is not allowedで2を返すこと" {
	# Arrange(NUL を落とすと有効な job_id=J1 に見える行)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J\0001,/w,/s,"[]",60\n'
		printf '%s\n' 'J2,/w,/s,"[]",60'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: nul byte is not allowed line=2 path: $MAP" ]
}

@test "validate_job_map_query_ヘッダー行にNULバイトがある場合_ヘッダー行のnul byte is not allowedで2を返すこと" {
	# Arrange(NUL を落とすと有効な列名 script に見えるヘッダー)
	{
		printf 'job_id,work_dir,scr\000ipt,fixed_params,hang_detect_limit_minutes\n'
		printf '%s\n' 'J1,/w,/s,"[]",60'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: nul byte is not allowed line=1 path: $MAP" ]
}

@test "validate_job_map_query_NULバイトだけの行が複数ある場合_全件をnul byte is not allowedで報告して2を返すこと" {
	# Arrange(改行の無い最終行も NUL だけ)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '\000\n'
		printf '%s\n' 'J1,/w,/s,"[]",60'
		printf '\000'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "error: nul byte is not allowed line=2 path: $MAP" ]
	[ "${lines[1]}" = "error: nul byte is not allowed line=4 path: $MAP" ]
}

@test "validate_job_map_query_コメント行にNULバイトがある場合_コメント行でもnul byte is not allowedで2を返すこと" {
	# Arrange(NUL はコメント行を含めて拒否する)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '# com\000ment\n'
		printf '%s\n' 'J1,/w,/s,"[]",60'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: nul byte is not allowed line=2 path: $MAP" ]
}

@test "validate_job_map_query_全行がCRLFの場合_行ごとのcarriage return is not allowedとhintで2を返しheader mismatchを出さないこと" {
	# Arrange(改行コードは LF だけ。CR は行ごとに拒否し、hint を 1 行添える)
	printf 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\r\nJ1,/w,/s,"[]",60\r\n' >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	output_has_line "error: carriage return is not allowed line=1 path: $MAP"
	output_has_line "error: carriage return is not allowed line=2 path: $MAP"
	output_has_line "hint: use LF line endings"
	[[ "$output" != *"job map header mismatch"* ]]
	[[ "$output" != *"hang_detect_limit_minutes is not a non-negative integer"* ]]
}

@test "validate_job_map_query_データ行だけがCRLFの場合_その行のcarriage return is not allowedで2を返し値の検証には流さないこと" {
	# Arrange(ヘッダーは LF、データ行だけ CRLF)
	printf 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\nJ1,/w,/s,"[]",60\r\n' >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	output_has_line "error: carriage return is not allowed line=2 path: $MAP"
	output_has_line "hint: use LF line endings"
	[[ "$output" != *"carriage return is not allowed line=1 "* ]]
	[[ "$output" != *"is not a non-negative integer"* ]]
}

@test "validate_job_map_query_セルの途中にCRがある場合_その行のcarriage return is not allowedで2を返すこと" {
	# Arrange(行末でなくセル内の CR も拒否する)
	printf 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\nJ1,/w,/s\r,"[]",60\n' >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	output_has_line "error: carriage return is not allowed line=2 path: $MAP"
	output_has_line "hint: use LF line endings"
}

@test "validate_job_map_query_先頭にUTF-8のBOMがある場合_byte order mark is not allowedで2を返しheader mismatchを出さないこと" {
	# Arrange(実バイト 0xef 0xbb 0xbf)
	printf '\357\273\277job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\nJ1,/w,/s,"[]",60\n' >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	output_has_line "error: byte order mark is not allowed line=1 path: $MAP"
	[[ "$output" != *"job map header mismatch"* ]]
}

@test "validate_job_map_query_fixed_paramsに不正なUTF-8バイト列がある場合_その行のencoding is not utf-8で2を返しinfo resolvedを出さないこと" {
	# Arrange(実バイト 0xff。設定契約の文字コードは UTF-8。attempt 3 の独立検証 F-025 の再現入力)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,map_version'
		printf 'J1,/w,/s,"[""a\377b""]",60,v1\n'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" true

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: encoding is not utf-8 line=2 path: $MAP" ]
}

@test "validate_job_map_query_不正なUTF-8の種類が違う行が複数ある場合_全件をencoding is not utf-8で報告して2を返すこと" {
	# Arrange(過長形式 c0 af / サロゲート ed a0 80 / U+10FFFF 超 f4 90 80 80 / 先頭バイトの無い継続バイト 81 /
	#          続きの無い先頭バイト e3 が行末 / 続きが足りない e3 81 の直後にカンマ)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,map_version'
		printf 'J1,/w,/s,"[]",60,\300\257\n'
		printf 'J2,/w,/s,"[]",60,\355\240\200\n'
		printf 'J3,/w,/s,"[]",60,\364\220\200\200\n'
		printf 'J4,/w,/s,"[]",60,a\201b\n'
		printf 'J5,/w,/s,"[]",60,v\343\n'
		printf 'J6,/w/\343\201,/s,"[]",60,v1\n'
		printf '%s\n' 'J7,/w,/s,"[]",60,v1'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "${#lines[@]}" -eq 6 ]
	[ "${lines[0]}" = "error: encoding is not utf-8 line=2 path: $MAP" ]
	[ "${lines[1]}" = "error: encoding is not utf-8 line=3 path: $MAP" ]
	[ "${lines[2]}" = "error: encoding is not utf-8 line=4 path: $MAP" ]
	[ "${lines[3]}" = "error: encoding is not utf-8 line=5 path: $MAP" ]
	[ "${lines[4]}" = "error: encoding is not utf-8 line=6 path: $MAP" ]
	[ "${lines[5]}" = "error: encoding is not utf-8 line=7 path: $MAP" ]
}

@test "validate_job_map_query_ヘッダー行に不正なUTF-8バイト列がある場合_ヘッダー行のencoding is not utf-8で2を返すこと" {
	# Arrange
	{
		printf 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,x\377\n'
		printf '%s\n' 'J1,/w,/s,"[]",60,a'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: encoding is not utf-8 line=1 path: $MAP" ]
}

@test "validate_job_map_query_コメント行に不正なUTF-8バイト列がある場合_その行のencoding is not utf-8で2を返すこと" {
	# Arrange(文字コード UTF-8 はファイル全体の形式。コメント行でも UTF-8 でないファイルは受理しない。Shift_JIS の「コメント」)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '# \203R\203\201\203\223\203g\n'
		printf '%s\n' 'J1,/w,/s,"[]",60'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: encoding is not utf-8 line=2 path: $MAP" ]
}

@test "validate_job_map_query_NULと不正なUTF-8とCRが別々の行にある場合_原因ごとの文言を行番号順に全件報告して2を返すこと" {
	# Arrange(2 行目 NUL / 3 行目 不正な UTF-8 / 4 行目 CR。同種でなくても全件を 1 行ずつ報告する)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J\0001,/w,/s,"[]",60\n'
		printf 'J2,/w\377,/s,"[]",60\n'
		printf 'J3,/w,/s,"[]",60\r\n'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	output_has_line "error: nul byte is not allowed line=2 path: $MAP"
	output_has_line "error: encoding is not utf-8 line=3 path: $MAP"
	output_has_line "error: carriage return is not allowed line=4 path: $MAP"
	output_has_line "hint: use LF line endings"
	[[ "$output" != *"csv quote is invalid"* ]]
	[[ "$output" != *"rows="* ]]
}

@test "validate_job_map_query_ヘッダーに同じ列名が2回ある場合_duplicate columnで2を返すこと" {
	# Arrange(入力の守備範囲「ヘッダー列名の重複」)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,job_id'
		printf '%s\n' 'J1,/w,/s,"[]",60,J1'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	output_has_line "error: duplicate column column=job_id path: $MAP"
	[[ "$output" != *"rows="* ]]
}

@test "validate_job_map_query_work_dirとscriptが方針資料のWindows形式パスと非ASCIIのホスト名の場合_受理して表示を1バイトも変えないこと" {
	# Arrange(方針資料のジョブマップ例。パスの形式は検査せず、バックスラッシュも置き換えない)
	{
		printf '%s\n' "$HEADER_7"
		printf '%s\n' 'TOMM0410010100,督促AP,saiken,G:\scripts,G:\scripts\xxx.bat,"[""param1"",""param2"",""param3""]",60'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" true

	# Assert
	[ "$status" -eq 0 ]
	output_has_line 'info: resolved job_id=TOMM0410010100 host=督促AP user=saiken exec=ssh work_dir=G:\scripts script=G:\scripts\xxx.bat fixed_params=["param1","param2","param3"] hang_detect_limit_minutes=60'
	output_has_line "rows=1"
	[[ "$output" != *"error:"* ]]
}

@test "validate_job_map_query_work_dirとscriptが方針資料の相対パスの場合_受理して0を返すこと" {
	# Arrange(方針資料のジョブマップ例。./ で始まる相対パス)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'TOMM0410010100,./beam-batches,./beam-batches/TOMM0410010100.sh,"[""param1"",""param2"",""param3""]",60'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 0 ]
	output_has_line "rows=1"
	[[ "$output" != *"error:"* ]]
}

@test "validate_job_map_query_妥当なUTF-8の多バイト文字がある場合_ロケールに関係なく受理すること" {
	# Arrange(2 / 3 / 4 バイト文字と各範囲の両端: U+0080 は C1 なので除き U+00A0、U+07FF、U+0800、U+D7FF、U+E000、U+FFFD、U+10000、U+10FFFF)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,map_version'
		printf '# コメント \360\237\230\200\n'
		printf 'J1,/w/日本語,/s,"[""\303\251"",""\360\237\230\200""]",60,\302\240\337\277\340\240\200\355\237\277\356\200\200\357\277\275\360\220\200\200\364\217\277\277\n'
	} >"$MAP"

	# Act / Assert
	LC_ALL=C run validate_job_map_query "$MAP" false
	[ "$status" -eq 0 ]
	[ "${lines[1]}" = "rows=1" ]
	# UTF-8 ロケールは環境にあるものを使う(無い環境では C ロケールの検証だけ行う)
	local utf8_locale
	utf8_locale="$(locale -a 2>/dev/null | grep -i -E '^(en_US|C)\.utf-?8$' | head -n 1 || true)"
	if [ -n "$utf8_locale" ]; then
		LC_ALL="$utf8_locale" run validate_job_map_query "$MAP" false
		[ "$status" -eq 0 ]
		[ "${lines[1]}" = "rows=1" ]
	fi
}

# --- 制御文字の可視表記(attempt 3 の独立検証 F-001。任意入力が出る全経路) ---

# 改行以外の制御文字(U+0001〜U+001F と U+007F)の生バイトを含むか
has_control_byte() {
	local LC_ALL=C
	[[ "$1" == *[$'\001'-$'\011'$'\013'-$'\037'$'\177']* ]]
}

@test "validate_job_map_query_map_versionにANSIエスケープがある場合_stdoutに生のESCを出さず可視表記で出すこと" {
	# Arrange(F-001 の再現入力)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,map_version'
		printf 'J1,/w,/s,[],60,\033[31mred\033[0m\n'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[2]}" = 'map_version=\u001b[31mred\u001b[0m' ]
	! has_control_byte "$output"
}

@test "validate_job_map_query_ファイル名に改行とESCがある場合_stdoutが3行のままでmap_pathを可視表記で出すこと" {
	# Arrange(F-001 の再現入力。パスは引数の任意のバイト列)
	local map="$BATS_TEST_TMPDIR"/$'ma\np\033.csv'
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$map"

	# Act
	run validate_job_map_query "$map" false

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[0]}" = "map_path: $BATS_TEST_TMPDIR"'/ma\np\u001b.csv' ]
	! has_control_byte "$output"
}

@test "validate_job_map_query_改行を含むパスのファイルが無い場合_config file not foundを1行で出すこと" {
	# Arrange / Act
	run validate_job_map_query "$BATS_TEST_TMPDIR"/$'no\nsuch\033.csv' false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: config file not found path: $BATS_TEST_TMPDIR"'/no\nsuch\u001b.csv' ]
}

@test "validate_job_map_query_改行を含むパスが通常ファイルでない場合_config file is not readableを1行で出すこと" {
	# Arrange
	mkdir "$BATS_TEST_TMPDIR"/$'di\nr'

	# Act
	run validate_job_map_query "$BATS_TEST_TMPDIR"/$'di\nr' false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: config file is not readable path: $BATS_TEST_TMPDIR"'/di\nr' ]
}

@test "validate_job_map_query_全部の列と列名に制御文字があるverboseの場合_errorとwarnとinfoのどの行にも生の制御文字を出さないこと" {
	# Arrange(パス・未知列名・各列の値・重複する job_id・版の混在。ESC / CR / タブ / DEL / C1 の U+009B)
	local map="$BATS_TEST_TMPDIR"/$'m\033.csv'
	{
		printf 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version,x\033y\n'
		printf 'J\0331,h,u,w\033,s\013,p\177,6\0330,c\033,v\0331,z\n'
		printf 'J\0331,h,u,/w,/s,[],60,c,v\302\2332,z\n'
		printf 'OK1,h\033,u\t,/w\033,/s\177,"[""a\\tb"",""\177"",""\302\233""]",60,c,v\0331,z\n'
		printf 'OK2,,u\033,/w,/s,[],60,c,v\0331,z\n'
		printf 'OK3,h,u,/w,/s,[],60,c,v\0331\n'
		printf 'OK4,h,u,/w,/s,"[""a\033""]",60,c,v\0331,z\n'
	} >"$map"

	# Act
	run validate_job_map_query "$map" true

	# Assert
	[ "$status" -eq 2 ]
	! has_control_byte "$output"
	local LC_ALL=C
	[[ "$output" != *$'\xc2\x9b'* ]]
	output_has_line 'warn: unknown column column=x\u001by path: '"$BATS_TEST_TMPDIR"'/m\u001b.csv'
	output_has_line 'error: job_id is invalid line=2 job_id=J\u001b1 value=J\u001b1'
	# work_dir=w<ESC> / script=s<VT> は非空なので違反にしない(パスの形式は検査しない。CR は形式違反になるため VT に置き換えた)
	[[ "$output" != *"work_dir is not absolute"* ]]
	[[ "$output" != *"script is not absolute"* ]]
	output_has_line 'error: fixed_params is not a json array of strings line=2 job_id=J\u001b1 value=p\u007f'
	output_has_line 'error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=J\u001b1 value=6\u001b0'
	output_has_line 'warn: credential_ref looks like a secret or path line=2 job_id=J\u001b1'
	output_has_line 'info: resolved job_id=OK1 host=h\u001b user=u\t exec=ssh work_dir=/w\u001b script=/s\u007f fixed_params=["a\tb","\u007f","\u009b"] hang_detect_limit_minutes=60'
	output_has_line 'error: host is empty line=5 job_id=OK2 value='
	output_has_line 'error: column count mismatch line=6 expected=10 actual=9'
	output_has_line 'error: fixed_params is not a json array of strings line=7 job_id=OK4 value=["a\u001b"]'
	output_has_line 'error: duplicate job_id job_id=J\u001b1 lines=2,3'
	output_has_line 'warn: mixed map_version values=v\u001b1,v\u009b2'
}

@test "validate_job_map_query_クォート不正の行があり改行を含むパスの場合_csv quote is invalidを1行で出すこと" {
	# Arrange(ヘッダー行のクォート不正・ヘッダー不一致後のクォート不正・データ行のクォート不正の 3 経路)
	local map="$BATS_TEST_TMPDIR"/$'q\nq.csv' shown="$BATS_TEST_TMPDIR"'/q\nq.csv'
	printf 'job_id,"x\nJ1,"y\n' >"$map"
	run validate_job_map_query "$map" false
	[ "$status" -eq 2 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "error: csv quote is invalid line=1 path: $shown" ]
	[ "${lines[1]}" = "error: csv quote is invalid line=2 path: $shown" ]

	printf 'job_id\nJ1,"y\n' >"$map"
	run validate_job_map_query "$map" false
	[ "$status" -eq 2 ]
	[ "${#lines[@]}" -eq 2 ]
	[[ "${lines[0]}" == "error: job map header mismatch missing="*" path: $shown" ]]
	[ "${lines[1]}" = "error: csv quote is invalid line=2 path: $shown" ]

	printf 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\nJ1,"y\n' >"$map"
	run validate_job_map_query "$map" false
	[ "$status" -eq 2 ]
	[ "$output" = "error: csv quote is invalid line=2 path: $shown" ]
}

# --- 補助コマンドの失敗(attempt 3 の独立検証 F-002。失敗を成功扱いにしない) ---

@test "validate_job_map_query_sortが失敗しjob_idが重複する場合_成功サマリーを出さず実行エラー6を返すこと" {
	# Arrange(F-002 と同じ障害注入。関数は外部コマンドより先に解決される)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"
	sort() { return 1; }

	# Act
	run validate_job_map_query "$MAP" false

	# Assert(config_input_rules.internal_failure: commands= には実際に失敗したコマンド名だけ。path: に利用者のパス)
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=sort path: $MAP" ]
}

@test "validate_job_map_query_sortが失敗しjob_idが一意の場合_成功サマリーを出さず実行エラー6を返すこと" {
	# Arrange(重複検査が未実施のまま検証 OK にしない)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
		printf '%s\n' 'J2,/w,/s,[],60'
	} >"$MAP"
	sort() { return 1; }

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=sort path: $MAP" ]
}

@test "validate_job_map_query_trが失敗する場合_NULを含む行を受理せず実行エラー6を返すこと" {
	# Arrange(F-002 と同じ障害注入。NUL の事前走査が未実施のまま検証 OK にしない)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J\0001,/w,/s,[],60\n'
	} >"$MAP"
	tr() { return 1; }

	# Act
	run validate_job_map_query "$MAP" false

	# Assert(commands= には実際に失敗したコマンド名だけを書く。cli-command-contract validate-config.sh の 6)
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=tr path: $MAP" ]
}

@test "validate_job_map_query_sedが失敗する場合_不正なUTF-8の行を受理せず実行エラー6を返すこと" {
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J1,/w\377,/s,[],60\n'
	} >"$MAP"
	sed() { return 1; }

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=sed path: $MAP" ]
}

@test "validate_job_map_query_sedが出力した後で失敗する場合_途中までの走査結果を使わず実行エラー6を返すこと" {
	# Arrange(出力があっても終了状態が非 0 なら走査は未完了)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"
	sed() {
		command cat >/dev/null
		return 3
	}

	# Act
	run validate_job_map_query "$MAP" true

	# Assert
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=sed path: $MAP" ]
}

@test "validate_job_map_query_job_idに非ASCII文字がある場合_job_id is invalidで2を返すこと" {
	# Arrange(ロケールの文字クラスに依存せず ASCII の英数字と _ - だけを許可する)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'JOBé,/w,/s,"[]",60'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: job_id is invalid line=2 job_id=JOBé value=JOBé" ]
}

@test "validate_job_map_query_hang_detect_limit_minutesが全角数字の場合_非負整数でないとして2を返すこと" {
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,"[]",６０'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=J1 value=６０" ]
}

@test "validate_job_map_query_引用符で囲んだセルの途中に改行がある場合_物理行ごとのcsv quote is invalidで2を返すこと" {
	# Arrange(セル内に改行は置けない)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J1,/w,/s,"[""a\nb""]",60\n'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "error: csv quote is invalid line=2 path: $MAP" ]
	[ "${lines[1]}" = "error: csv quote is invalid line=3 path: $MAP" ]
}

@test "validate_job_map_query_最終行に改行が無い場合_最終行も検証して集計すること" {
	# Arrange(最終行の hang_detect_limit_minutes を違反にして、最終行が検証されたことを確かめる。相対パスは違反にならない)
	printf 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\nJ1,/w,/s,"[]",60\nJ2,relative,/s,"[]",60m' >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: hang_detect_limit_minutes is not a non-negative integer line=3 job_id=J2 value=60m" ]
}

@test "validate_job_map_query_最終行に改行が無く違反も無い場合_最終行をrowsに数えて0を返すこと" {
	# Arrange(入力の守備範囲: 最終行の改行なしは受理する例外)
	printf 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\nJ1,/w,/s,"[]",60\nJ2,relative,/s,"[]",60' >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[1]}" = "rows=2" ]
}

@test "validate_job_map_query_ヘッダー行だけでデータ行が無い場合_rows=0で0を返すこと" {
	# Arrange
	printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes' >"$MAP"

	# Act
	run validate_job_map_query "$MAP" true

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[1]}" = "rows=0" ]
	[ "${lines[2]}" = "map_version=-" ]
}

@test "validate_job_map_query_コメント行だけのファイルの場合_必須5列のheader mismatchで2を返すこと" {
	# Arrange
	printf '# a\n\n# b\n' >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: job map header mismatch missing=job_id,work_dir,script,fixed_params,hang_detect_limit_minutes path: $MAP" ]
}

@test "validate_job_map_query_末尾に空行が続く場合_空行をrowsに数えず0を返すこと" {
	# Arrange
	printf 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\nJ1,/w,/s,"[]",60\n\n\n' >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[1]}" = "rows=1" ]
}

@test "validate_job_map_query_空白だけの行がある場合_column count mismatchで2を返すこと" {
	# Arrange(空白だけの行は空行ではない)
	printf 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\nJ1,/w,/s,"[]",60\n   \n' >"$MAP"

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: column count mismatch line=3 expected=5 actual=1" ]
}

@test "validate_job_map_query_値にシェルの展開文字がある場合_展開せず文字どおりに扱うこと" {
	# Arrange(glob・変数・コマンド置換・オプション風の値)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' '-n,/w/*,/s/?,"[""*"",""-e"",""$HOME"",""`id`"",""$(id)""]",60'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" true

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = 'info: resolved job_id=-n host=- user=- exec=local work_dir=/w/* script=/s/? fixed_params=["*","-e","$HOME","`id`","$(id)"] hang_detect_limit_minutes=60' ]
}

@test "validate_job_map_query_fixed_paramsが10万文字の行の場合_verboseでも10秒以内に0を返すこと" {
	# Arrange(行の長さに上限は無い。nfr-grade B.2.1.1 の CLI 応答 10 秒目標)
	long_value="$(head -c 100000 /dev/zero | tr '\000' 'a')"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J1,/w,/s,"[""%s""]",60\n' "$long_value"
	} >"$MAP"
	SECONDS=0

	# Act
	run validate_job_map_query "$MAP" true

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[0]}" -gt 100000 ]
	[ "$SECONDS" -lt 10 ]
}

@test "validate_job_map_query_fixed_paramsにエスケープしたタブと改行がある場合_verboseのfixed_paramsが1行のJSON配列表記であること" {
	# Arrange(CSV セル内は \t と \n の 2 文字ずつ)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,"[""a\tb\nc""]",60'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" true

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = 'info: resolved job_id=J1 host=- user=- exec=local work_dir=/w script=/s fixed_params=["a\tb\nc"] hang_detect_limit_minutes=60' ]
}

@test "validate_job_map_query_一意なjob_idが4000行ある場合_10秒以内に0を返すこと" {
	# Arrange(nfr-grade B.2.1.1 の CLI 応答 10 秒目標。job_id 重複検査と行の取り出しを行数の 2 乗にしない)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		index=1
		while [ "$index" -le 4000 ]; do
			printf 'JOB%s,/w,/s,[],60\n' "$index"
			index=$((index + 1))
		done
	} >"$MAP"
	SECONDS=0

	# Act
	run validate_job_map_query "$MAP" false

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[1]}" = "rows=4000" ]
	[ "$SECONDS" -lt 10 ]
}

@test "validate_job_map_query_verboseで違反行と有効行が混在する場合_有効行だけinfo resolvedを出すこと" {
	# Arrange
	{
		printf '%s\n' "$HEADER_7"
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[""--mode"",""full""]",90'
		printf '%s\n' 'JOB002,host-green-01,batch,/var/app/work,/opt/app/bin/job002.sh,"p1,p2",60'
	} >"$MAP"

	# Act
	run validate_job_map_query "$MAP" true

	# Assert
	[ "$status" -eq 2 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = 'info: resolved job_id=JOB001 host=host-green-01 user=batch exec=ssh work_dir=/var/app/work script=/opt/app/bin/job001.sh fixed_params=["--mode","full"] hang_detect_limit_minutes=90' ]
	[ "${lines[1]}" = "error: fixed_params is not a json array of strings line=3 job_id=JOB002 value=p1,p2" ]
}

@test "validate_job_map_query_検証を実行した場合_ジョブマップのファイルを書き換えないこと" {
	# Arrange
	{
		printf '%s\n' "$HEADER_7"
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60'
	} >"$MAP"
	before="$(cksum "$MAP")"

	# Act
	run validate_job_map_query "$MAP" true

	# Assert
	[ "$status" -eq 0 ]
	[ "$(cksum "$MAP")" = "$before" ]
}
