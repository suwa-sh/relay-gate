#!/usr/bin/env bats
# UC eff24f55 × tier-facade: repository 層 JobMapRepository(CSV セルのクォート解析と読み込み)の単体テスト。
# 仕様: tier-facade.md「設定契約(slot ジョブマップ CSV)」形式 / CSV セルのクォート解析規則 / 入力の守備範囲
#       (CLI 契約 config_input_rules: NUL / 不正な UTF-8 / BOM / CR は原因ごとに行番号を記録し malformed として解析しない。
#        入力の複製の失敗と補助コマンドの失敗は別の状態で返す)
# I/O 境界は実ファイル(一時ディレクトリ)で検証する。

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/repository/job_map_repo.sh"
	MAP="$BATS_TEST_TMPDIR/map.csv"
}

@test "csv_parse_囲まないセルだけの行の場合_カンマ区切りでセルに分解すること" {
	# Arrange / Act
	csv_parse 'JOB001,host-green-01,batch'

	# Assert
	[ "${#CSV_CELLS[@]}" -eq 3 ]
	[ "${CSV_CELLS[0]}" = "JOB001" ]
	[ "${CSV_CELLS[1]}" = "host-green-01" ]
	[ "${CSV_CELLS[2]}" = "batch" ]
}

@test "csv_parse_二重化された引用符とカンマを含む囲みセルの場合_引用符を1文字に戻しカンマをセル内に残すこと" {
	# Arrange / Act
	csv_parse 'JOB001,"[""p2 p3"",""a,b""]",60'

	# Assert
	[ "${#CSV_CELLS[@]}" -eq 3 ]
	[ "${CSV_CELLS[1]}" = '["p2 p3","a,b"]' ]
	[ "${CSV_CELLS[2]}" = "60" ]
}

@test "csv_parse_空セルと行末の空セルがある場合_空文字のセルとして数えること" {
	# Arrange / Act
	csv_parse 'JOB001,,batch,'

	# Assert
	[ "${#CSV_CELLS[@]}" -eq 4 ]
	[ "${CSV_CELLS[1]}" = "" ]
	[ "${CSV_CELLS[3]}" = "" ]
}

@test "csv_parse_空の囲みセルの場合_空文字のセルになること" {
	# Arrange / Act
	csv_parse 'JOB001,"",60'

	# Assert
	[ "${#CSV_CELLS[@]}" -eq 3 ]
	[ "${CSV_CELLS[1]}" = "" ]
}

@test "csv_parse_閉じ引用符が無い場合_クォート不正として1を返すこと" {
	# Arrange / Act
	run csv_parse 'JOB001,"[""p1""],60'

	# Assert
	[ "$status" -eq 1 ]
}

@test "csv_parse_囲み外に二重引用符がある場合_クォート不正として1を返すこと" {
	# Arrange / Act
	run csv_parse 'JOB001,ab"c,60'

	# Assert
	[ "$status" -eq 1 ]
}

@test "csv_parse_閉じ引用符の直後がカンマでも行末でもない場合_クォート不正として1を返すこと" {
	# Arrange / Act
	run csv_parse 'JOB001,"abc"x,60'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_repo_load_コメント行と空行を含むCSVの場合_ヘッダーとデータ行を物理行番号付きで読み込むこと" {
	# Arrange
	{
		printf '%s\n' '# slot job map'
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' ''
		printf '%s\n' 'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",0'
		printf '%s\n' '# comment'
		printf '%s\n' 'JOB002,/var/app/work,/opt/app/bin/job002.sh,"[""a""]",60'
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$JOB_MAP_PATH" = "$MAP" ]
	[ "$JOB_MAP_HEADER_STATUS" = "ok" ]
	[ "$JOB_MAP_HEADER_LINE" -eq 2 ]
	[ "${#JOB_MAP_HEADER[@]}" -eq 5 ]
	[ "${JOB_MAP_HEADER[0]}" = "job_id" ]
	[ "$(job_map_repo_row_count)" -eq 2 ]
	[ "${JOB_MAP_ROW_LINES[0]}" -eq 4 ]
	[ "${JOB_MAP_ROW_LINES[1]}" -eq 6 ]
	job_map_repo_row 1
	[ "${#JOB_MAP_ROW[@]}" -eq 5 ]
	[ "${JOB_MAP_ROW[0]}" = "JOB002" ]
	[ "${JOB_MAP_ROW[3]}" = '["a"]' ]
}

@test "job_map_repo_load_クォート不正のデータ行がある場合_その行をquote_invalidとして記録し残りの行も読むこと" {
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[""p1""],60'
		printf '%s\n' 'JOB002,/var/app/work,/opt/app/bin/job002.sh,"[]",60'
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "${JOB_MAP_ROW_STATUSES[0]}" = "quote_invalid" ]
	[ "${JOB_MAP_ROW_CELL_COUNTS[0]}" -eq 0 ]
	[ "${JOB_MAP_ROW_STATUSES[1]}" = "ok" ]
	job_map_repo_row 1
	[ "${JOB_MAP_ROW[0]}" = "JOB002" ]
}

@test "job_map_repo_load_最終行に改行が無い場合_最終行もデータ行として読むこと" {
	# Arrange
	printf '%s\n%s' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes' 'JOB001,/w,/s.sh,"[]",0' >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$(job_map_repo_row_count)" -eq 1 ]
}

@test "csv_parse_不正なUTF-8バイト列の直後に区切りがある場合_バイト列を変えずにセルへ分解すること" {
	# Arrange(0xe3 は UTF-8 の 3 バイト文字の先頭バイト。続きのバイトが無いまま引用符・カンマが来る)
	local line=$'J1,/w\xe3,"[""a\xe3""]",60'

	# Act
	csv_parse "$line"

	# Assert
	[ "${#CSV_CELLS[@]}" -eq 4 ]
	[ "${CSV_CELLS[1]}" = $'/w\xe3' ]
	[ "${CSV_CELLS[2]}" = $'["a\xe3"]' ]
	[ "${CSV_CELLS[3]}" = "60" ]
}

@test "csv_parse_取り込みの窓が1バイトの場合_窓の境界をまたぐ二重化引用符と閉じ引用符を正しく解析すること" {
	# Arrange(長い行は窓ごとに取り込む。窓の大きさで結果が変わらないこと)
	CSV_PARSE_WINDOW_BYTES=1

	# Act
	csv_parse 'J1,"a""b","",x,"[""p2 p3"",""a,b""]",日本語,'

	# Assert
	[ "${#CSV_CELLS[@]}" -eq 7 ]
	[ "${CSV_CELLS[1]}" = 'a"b' ]
	[ "${CSV_CELLS[2]}" = "" ]
	[ "${CSV_CELLS[3]}" = "x" ]
	[ "${CSV_CELLS[4]}" = '["p2 p3","a,b"]' ]
	[ "${CSV_CELLS[5]}" = "日本語" ]
	[ "${CSV_CELLS[6]}" = "" ]
}

@test "csv_parse_取り込みの窓が2バイトの場合_窓の末尾の二重引用符を続きと合わせて判定すること" {
	# Arrange(`""` の 1 文字目が窓の末尾、2 文字目が次の窓の先頭になる位置)
	CSV_PARSE_WINDOW_BYTES=2

	# Act
	csv_parse '"a""b",c'

	# Assert
	[ "${#CSV_CELLS[@]}" -eq 2 ]
	[ "${CSV_CELLS[0]}" = 'a"b' ]
	[ "${CSV_CELLS[1]}" = "c" ]
}

@test "csv_parse_取り込みの窓が3バイトで閉じ引用符の直後に文字がある場合_クォート不正として1を返すこと" {
	# Arrange
	CSV_PARSE_WINDOW_BYTES=3

	# Act
	run csv_parse 'J1,"abc"x,60'

	# Assert
	[ "$status" -eq 1 ]
}

@test "csv_parse_取り込みの窓が1バイトで閉じ引用符が無い場合_クォート不正として1を返すこと" {
	# Arrange
	CSV_PARSE_WINDOW_BYTES=1

	# Act
	run csv_parse 'J1,"[""p1""],60'

	# Assert
	[ "$status" -eq 1 ]
}

@test "csv_parse_20万文字の囲みセルの場合_10秒以内にセルへ分解すること" {
	# Arrange(行の長さに上限は無い。文字数の 2 乗の時間をかけない)
	local long_value
	long_value="$(head -c 200000 /dev/zero | tr '\000' 'a')"
	SECONDS=0

	# Act
	csv_parse "J1,\"$long_value\",60"

	# Assert
	[ "${#CSV_CELLS[@]}" -eq 3 ]
	[ "${#CSV_CELLS[1]}" -eq 200000 ]
	[ "$SECONDS" -lt 10 ]
}

@test "job_map_repo_load_データ行にNULバイトがある場合_その行をmalformedとして記録しNUL行の行番号に載せセルを取り込まないこと" {
	# Arrange(実バイト 0x00。bash の read は NUL を黙って落とすため、取り込む前に検出する)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J1,/w,/s,"[""a\000b""]",60\n'
		printf '%s\n' 'J2,/w,/s,"[]",60'
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$(job_map_repo_row_count)" -eq 2 ]
	[ "${JOB_MAP_ROW_LINES[0]}" -eq 2 ]
	[ "${JOB_MAP_ROW_STATUSES[0]}" = "malformed" ]
	[ "${JOB_MAP_ROW_CELL_COUNTS[0]}" -eq 0 ]
	[ "${JOB_MAP_ROW_STATUSES[1]}" = "ok" ]
	[ "${JOB_MAP_NUL_LINES[*]}" = "2" ]
	[ "${JOB_MAP_MALFORMED_LINES[*]}" = "2" ]
	[ "${#JOB_MAP_ENCODING_LINES[@]}" -eq 0 ]
	[ "${#JOB_MAP_CR_LINES[@]}" -eq 0 ]
	[ "$JOB_MAP_BOM_LINE" -eq 0 ]
}

@test "job_map_repo_load_ヘッダー行にNULバイトがある場合_ヘッダー状態がmalformedであること" {
	# Arrange
	{
		printf 'job_id,work_dir,scr\000ipt,fixed_params,hang_detect_limit_minutes\n'
		printf '%s\n' 'J1,/w,/s,"[]",60'
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$JOB_MAP_HEADER_STATUS" = "malformed" ]
	[ "$JOB_MAP_HEADER_LINE" -eq 1 ]
	[ "${JOB_MAP_NUL_LINES[*]}" = "1" ]
}

@test "job_map_repo_load_NULバイトだけの行がある場合_空行として読み飛ばさずmalformedとして記録すること" {
	# Arrange(NUL を落とすと空行に見える行)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '\000\000\n'
		printf '%s\n' 'J1,/w,/s,"[]",60'
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$(job_map_repo_row_count)" -eq 2 ]
	[ "${JOB_MAP_ROW_LINES[0]}" -eq 2 ]
	[ "${JOB_MAP_ROW_STATUSES[0]}" = "malformed" ]
	[ "${JOB_MAP_NUL_LINES[*]}" = "2" ]
}

@test "job_map_repo_load_改行の無い最終行がNULバイトだけの場合_その行をmalformedとして記録すること" {
	# Arrange(read が 1 文字も返さずに終端へ達する行)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,"[]",60'
		printf '\000'
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$(job_map_repo_row_count)" -eq 2 ]
	[ "${JOB_MAP_ROW_LINES[1]}" -eq 3 ]
	[ "${JOB_MAP_ROW_STATUSES[1]}" = "malformed" ]
	[ "${JOB_MAP_NUL_LINES[*]}" = "3" ]
}

@test "job_map_repo_load_NULバイトの直後に#がある行の場合_コメント行として読み飛ばさずmalformedとして記録すること" {
	# Arrange(NUL を落とすと行頭 # のコメント行に見える行。1 バイト目は # ではない)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '\000# not a comment\n'
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$(job_map_repo_row_count)" -eq 1 ]
	[ "${JOB_MAP_ROW_STATUSES[0]}" = "malformed" ]
}

@test "job_map_repo_load_行頭#のコメント行の途中にNULバイトがある場合_コメント行でも読み飛ばさずmalformedとして記録すること" {
	# Arrange(config_input_rules: NUL バイトはコメント行にあっても拒否する(ファイル全体の形式))
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '# com\000ment\n'
		printf '%s\n' 'J1,/w,/s,"[]",60'
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$(job_map_repo_row_count)" -eq 2 ]
	[ "${JOB_MAP_ROW_LINES[0]}" -eq 2 ]
	[ "${JOB_MAP_ROW_STATUSES[0]}" = "malformed" ]
	[ "${JOB_MAP_ROW_LINES[1]}" -eq 3 ]
	[ "${JOB_MAP_ROW_STATUSES[1]}" = "ok" ]
	[ "${JOB_MAP_NUL_LINES[*]}" = "2" ]
}

@test "job_map_repo_load_データにNという文字があってNULバイトが無い場合_すべての行をokとして読むこと" {
	# Arrange(NUL の検出が通常の文字に反応しないこと)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'JOBN,/w/N,/s/N,"[""N""]",60'
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$JOB_MAP_HEADER_STATUS" = "ok" ]
	[ "${JOB_MAP_ROW_STATUSES[0]}" = "ok" ]
}

@test "job_map_repo_load_CRLF改行のファイルの場合_CRを含む行をmalformedとして記録しCR行の行番号に載せること" {
	# Arrange(改行コードは LF だけ。config_input_rules: CR は CRLF 改行・行末・セル内のどこにあっても拒否する)
	printf 'job_id,work_dir\r\nJ1,/w\r\nJ2,/w\nJ3,/w\r,x\n' >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert(ヘッダー行も CR を含むため malformed。CR の無い 3 行目は ok)
	[ "$JOB_MAP_HEADER_STATUS" = "malformed" ]
	[ "$JOB_MAP_HEADER_LINE" -eq 1 ]
	[ "$(job_map_repo_row_count)" -eq 3 ]
	[ "${JOB_MAP_ROW_STATUSES[0]}" = "malformed" ]
	[ "${JOB_MAP_ROW_STATUSES[1]}" = "ok" ]
	[ "${JOB_MAP_ROW_STATUSES[2]}" = "malformed" ]
	[ "${JOB_MAP_CR_LINES[*]}" = "1 2 4" ]
	[ "${JOB_MAP_MALFORMED_LINES[*]}" = "1 2 4" ]
	[ "${#JOB_MAP_NUL_LINES[@]}" -eq 0 ]
	[ "${#JOB_MAP_ENCODING_LINES[@]}" -eq 0 ]
}

@test "job_map_repo_load_先頭にUTF-8のBOMがある場合_1行目をmalformedとして記録しBOM行を1にすること" {
	# Arrange(実バイト 0xef 0xbb 0xbf。BOM は妥当な UTF-8 なので文字コードの違反には数えない)
	printf '\357\273\277job_id,work_dir\nJ1,/w\n' >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$JOB_MAP_HEADER_STATUS" = "malformed" ]
	[ "$JOB_MAP_BOM_LINE" -eq 1 ]
	[ "${JOB_MAP_MALFORMED_LINES[*]}" = "1" ]
	[ "${#JOB_MAP_ENCODING_LINES[@]}" -eq 0 ]
	[ "$(job_map_repo_row_count)" -eq 1 ]
	[ "${JOB_MAP_ROW_STATUSES[0]}" = "ok" ]
}

@test "job_map_repo_load_1行目がコメント行でBOMがある場合_BOM行は1でコメント行をmalformedとして記録すること" {
	# Arrange(BOM は物理 1 行目の先頭だけを見る)
	printf '\357\273\277# comment\njob_id,work_dir\nJ1,/w\n' >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert(1 行目は malformed としてヘッダー行の位置を占める。BOM のあるファイルは usecase が拒否する)
	[ "$JOB_MAP_BOM_LINE" -eq 1 ]
	[ "$JOB_MAP_HEADER_LINE" -eq 1 ]
	[ "$JOB_MAP_HEADER_STATUS" = "malformed" ]
}

@test "job_map_repo_load_NULと不正なUTF-8とCRが同じ行と別の行にある場合_原因ごとの行番号を昇順に載せmalformedは重複なしであること" {
	# Arrange(2 行目 NUL + CR / 3 行目 不正な UTF-8 / 4 行目 CR)
	{
		printf '%s\n' 'job_id,work_dir'
		printf 'J\0001,/w\r\n'
		printf 'J2,/w\377\n'
		printf 'J3,/w\r\n'
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "${JOB_MAP_NUL_LINES[*]}" = "2" ]
	[ "${JOB_MAP_ENCODING_LINES[*]}" = "3" ]
	[ "${JOB_MAP_CR_LINES[*]}" = "2 4" ]
	[ "${JOB_MAP_MALFORMED_LINES[*]}" = "2 3 4" ]
	[ "$JOB_MAP_HEADER_STATUS" = "ok" ]
	[ "$(job_map_repo_row_count)" -eq 3 ]
	[ "${JOB_MAP_ROW_STATUSES[*]}" = "malformed malformed malformed" ]
}

@test "job_map_repo_load_空白だけの行の場合_空行として読み飛ばさず1セルのデータ行として読むこと" {
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir'
		printf '%s\n' '   '
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$(job_map_repo_row_count)" -eq 1 ]
	[ "${JOB_MAP_ROW_CELL_COUNTS[0]}" -eq 1 ]
}

@test "job_map_repo_load_引用符で囲んだセルの途中に改行がある場合_物理行ごとにquote_invalidとして記録すること" {
	# Arrange(セル内に改行は置けない)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J1,/w,/s,"[""a\nb""]",60\n'
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$(job_map_repo_row_count)" -eq 2 ]
	[ "${JOB_MAP_ROW_STATUSES[0]}" = "quote_invalid" ]
	[ "${JOB_MAP_ROW_STATUSES[1]}" = "quote_invalid" ]
}

@test "job_map_repo_load_行末がバックスラッシュの行の場合_次の行と連結せずバックスラッシュをセルの値に残すこと" {
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir'
		printf '%s\n' 'J1,/w\'
		printf '%s\n' 'J2,/w'
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$(job_map_repo_row_count)" -eq 2 ]
	job_map_repo_row 0
	[ "${JOB_MAP_ROW[1]}" = '/w\' ]
}

@test "job_map_repo_load_ヘッダー行が無い空ファイルの場合_ヘッダー状態がmissingであること" {
	# Arrange
	: >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$JOB_MAP_HEADER_STATUS" = "missing" ]
	[ "$JOB_MAP_HEADER_LINE" -eq 0 ]
	[ "$(job_map_repo_row_count)" -eq 0 ]
}

# --- 不正な UTF-8(attempt 3 の独立検証 F-025)と補助コマンドの失敗(F-002) ---

@test "job_map_repo_load_データ行に不正なUTF-8バイト列がある場合_その行をmalformedとして記録し文字コード行の行番号に載せセルを取り込まないこと" {
	# Arrange(実バイト 0xff。設定契約の文字コードは UTF-8)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J1,/w,/s,"[""a\377b""]",60\n'
		printf 'J2,/w/\343\201\202,/s,"[]",60\n'
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert(2 行目の「あ」は妥当な UTF-8)
	[ "$(job_map_repo_row_count)" -eq 2 ]
	[ "${JOB_MAP_ROW_LINES[0]}" -eq 2 ]
	[ "${JOB_MAP_ROW_STATUSES[0]}" = "malformed" ]
	[ "${JOB_MAP_ROW_CELL_COUNTS[0]}" -eq 0 ]
	[ "${JOB_MAP_ROW_STATUSES[1]}" = "ok" ]
	[ "${#JOB_MAP_CELLS[@]}" -eq 5 ]
	[ "${JOB_MAP_ENCODING_LINES[*]}" = "2" ]
	[ "${#JOB_MAP_NUL_LINES[@]}" -eq 0 ]
}

@test "job_map_repo_load_行頭#のコメント行に不正なUTF-8バイト列がある場合_読み飛ばさずmalformedとして記録すること" {
	# Arrange(コメント行でも UTF-8 でないファイルは設定契約の形式に合わない)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '# \203R\n'
		printf '%s\n' 'J1,/w,/s,"[]",60'
	} >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$(job_map_repo_row_count)" -eq 2 ]
	[ "${JOB_MAP_ROW_LINES[0]}" -eq 2 ]
	[ "${JOB_MAP_ROW_STATUSES[0]}" = "malformed" ]
	[ "${JOB_MAP_ROW_STATUSES[1]}" = "ok" ]
	[ "${JOB_MAP_ENCODING_LINES[*]}" = "2" ]
}

@test "job_map_repo_load_改行の無い最終行が不正なUTF-8バイト列の場合_その行をmalformedとして記録すること" {
	# Arrange
	printf 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\nJ1,/w,/s,"[]",60\n\355\240\200' >"$MAP"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$(job_map_repo_row_count)" -eq 2 ]
	[ "${JOB_MAP_ROW_LINES[1]}" -eq 3 ]
	[ "${JOB_MAP_ROW_STATUSES[1]}" = "malformed" ]
	[ "${JOB_MAP_ENCODING_LINES[*]}" = "3" ]
}

@test "job_map_repo_scan_malformed_lines_妥当なUTF-8の範囲の両端と不正な並びが混在する場合_不正な行の行番号だけを昇順で返すこと" {
	# Arrange(奇数行 = 妥当、偶数行 = 不正。RFC 3629 の範囲の両端)
	{
		printf 'ascii \177 only\n'
		printf '\200\n'
		printf '\302\200 \337\277\n'
		printf '\301\277\n'
		printf '\340\240\200 \357\277\277\n'
		printf '\340\237\277\n'
		printf '\355\237\277 \356\200\200\n'
		printf '\355\240\200\n'
		printf '\360\220\200\200 \364\217\277\277\n'
		printf '\360\217\277\277\n'
		printf 'N x\n'
		printf '\364\220\200\200\n'
		printf '\343\201\202\343\201\204\n'
		printf '\343\201\n'
		printf 'ok\n'
		printf '\343x\201\201\n'
		printf 'ok\n'
		printf '\365\200\200\200\n'
		printf 'ok\n'
		printf '\343\201\202\201\n'
	} >"$MAP"

	# Act
	job_map_repo_scan_malformed_lines "$MAP"

	# Assert(文字コードの違反だけで、NUL / CR / BOM は無い)
	[ "${JOB_MAP_MALFORMED_LINES[*]}" = "2 4 6 8 10 12 14 16 18 20" ]
	[ "${JOB_MAP_ENCODING_LINES[*]}" = "2 4 6 8 10 12 14 16 18 20" ]
	[ "${#JOB_MAP_NUL_LINES[@]}" -eq 0 ]
	[ "${#JOB_MAP_CR_LINES[@]}" -eq 0 ]
	[ "$JOB_MAP_BOM_LINE" -eq 0 ]
}

@test "job_map_repo_load_trが失敗する場合_行を読み込まず失敗の状態とコマンド名trを返すこと" {
	# Arrange(F-002 と同じ障害注入。走査が未実施のまま NUL を落とした行を ok にしない)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J\0001,/w,/s,"[]",60\n'
	} >"$MAP"
	tr() { return 1; }

	# Act
	local status=0
	job_map_repo_load "$MAP" || status=$?

	# Assert
	[ "$status" -eq "$JOB_MAP_REPO_STATUS_COMMAND_FAILED" ]
	[ "$JOB_MAP_REPO_FAILED_COMMANDS" = "tr" ]
	[ "$(job_map_repo_row_count)" -eq 0 ]
	[ "$JOB_MAP_HEADER_STATUS" = "missing" ]
}

@test "job_map_repo_load_sedが失敗する場合_行を読み込まず失敗の状態とコマンド名sedだけを返すこと" {
	# Arrange(sed が読まずに終わると tr は SIGPIPE で終わるが、それは sed の失敗の結果なので commands= に含めない)
	printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes' >"$MAP"
	sed() { return 1; }

	# Act
	local status=0
	job_map_repo_load "$MAP" || status=$?

	# Assert
	[ "$status" -eq "$JOB_MAP_REPO_STATUS_COMMAND_FAILED" ]
	[ "$JOB_MAP_REPO_FAILED_COMMANDS" = "sed" ]
	[ "$(job_map_repo_row_count)" -eq 0 ]
}

@test "job_map_repo_load_sedが数値でない行を出力した場合_走査結果として使わず失敗の状態とコマンド名sedを返すこと" {
	# Arrange(補助コマンドが終了状態 0 のまま想定外の出力を返す)
	printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes' >"$MAP"
	sed() {
		command cat >/dev/null
		printf '%s\n' 'sed: unexpected'
	}

	# Act
	local status=0
	job_map_repo_load "$MAP" || status=$?

	# Assert
	[ "$status" -eq "$JOB_MAP_REPO_STATUS_COMMAND_FAILED" ]
	[ "$JOB_MAP_REPO_FAILED_COMMANDS" = "sed" ]
}

@test "job_map_repo_load_mktempが失敗する場合_入力を読まず複製失敗の状態を返し一時ファイルを残さないこと" {
	# Arrange(config_input_rules.internal_failure: 一時ファイルの作成の失敗は「入力の複製の失敗」)
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	printf '%s\n' 'job_id,work_dir' >"$MAP"
	mktemp() { return 1; }

	# Act
	local status=0
	job_map_repo_load "$MAP" || status=$?

	# Assert
	[ "$status" -eq "$JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED" ]
	[ "$JOB_MAP_HEADER_STATUS" = "missing" ]
	[ -z "$(ls -A "$TMPDIR")" ]
}

@test "job_map_repo_load_複製先への書き込みが失敗する場合_複製失敗の状態を返し作業名の一時ファイルを残さないこと" {
	# Arrange(cat が失敗する。作業名(.part)のまま残さない)
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	printf '%s\n' 'job_id,work_dir' >"$MAP"
	cat() { return 1; }

	# Act
	local status=0
	job_map_repo_load "$MAP" || status=$?

	# Assert
	[ "$status" -eq "$JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED" ]
	[ -z "$(ls -A "$TMPDIR")" ]
}

@test "job_map_repo_load_TMPDIRが存在しない場合_複製失敗の状態を返すこと" {
	# Arrange(置き場所に書き込めない)
	export TMPDIR="$BATS_TEST_TMPDIR/no-such-dir"
	printf '%s\n' 'job_id,work_dir' >"$MAP"

	# Act
	local status=0
	job_map_repo_load "$MAP" || status=$?

	# Assert
	[ "$status" -eq "$JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED" ]
}

@test "job_map_repo_load_複製の削除が失敗する場合_読み込み結果を使わず失敗の状態とコマンド名rmを返すこと" {
	# Arrange(attempt 5 F-002: 複製が残ったまま検証 OK を返さない。rm は stderr に診断を出して失敗する)
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"
	rm() {
		printf '%s\n' 'rm: simulated I/O failure' >&2
		return 1
	}

	# Act
	local status=0 stderr_file="$BATS_TEST_TMPDIR/stderr.txt"
	job_map_repo_load "$MAP" 2>"$stderr_file" || status=$?
	unset -f rm

	# Assert(rm 自身の stderr も出さない。残った複製は後片付けする)
	[ "$status" -eq "$JOB_MAP_REPO_STATUS_COMMAND_FAILED" ]
	[ "$JOB_MAP_REPO_FAILED_COMMANDS" = "rm" ]
	[ "$(job_map_repo_row_count)" -eq 0 ]
	[ "$JOB_MAP_HEADER_STATUS" = "missing" ]
	[ ! -s "$stderr_file" ]
	[ -n "$(ls -A "$TMPDIR")" ]
	command rm -f -- "$TMPDIR"/relay-gate-*
}

@test "job_map_repo_load_sedと複製の削除の両方が失敗する場合_失敗した順のコマンド名sed_rmを返すこと" {
	# Arrange(補助コマンドの失敗と削除の失敗が重なる。commands= は実際に失敗したコマンド名を失敗した順に)
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes' >"$MAP"
	sed() { return 1; }
	rm() { return 1; }

	# Act
	local status=0
	job_map_repo_load "$MAP" || status=$?
	unset -f rm

	# Assert
	[ "$status" -eq "$JOB_MAP_REPO_STATUS_COMMAND_FAILED" ]
	[ "$JOB_MAP_REPO_FAILED_COMMANDS" = "sed,rm" ]
	command rm -f -- "$TMPDIR"/relay-gate-*
}

@test "job_map_repo_load_複製先への書き込みと削除の両方が失敗する場合_入力の複製の失敗の状態を返すこと" {
	# Arrange(複製の工程の失敗を優先する。置き場所の問題が原因で hint も同じ)
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	printf '%s\n' 'job_id,work_dir' >"$MAP"
	cat() { return 1; }
	rm() { return 1; }

	# Act
	local status=0
	job_map_repo_load "$MAP" || status=$?
	unset -f rm

	# Assert
	[ "$status" -eq "$JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED" ]
	command rm -f -- "$TMPDIR"/relay-gate-*
}

@test "job_map_repo_load_複製が完了した時点の一時ファイルの場合_relay-gate-で始まり_partで終わらない最終名だけが権限0600で存在すること" {
	# Arrange(config_input_rules.snapshot: 作業名 .part へ書き終えてから最終名へ rename。走査の tr が動く時点で複製は完了している)
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	printf '%s\n' 'job_id,work_dir' >"$MAP"
	SNAPSHOT_LIST="$BATS_TEST_TMPDIR/snapshot-list.txt"
	: >"$SNAPSHOT_LIST"
	tr() {
		if [ ! -s "$SNAPSHOT_LIST" ]; then
			command ls -l "$TMPDIR" | command grep -v '^total' >"$SNAPSHOT_LIST"
		fi
		command tr "$@"
	}

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$(wc -l <"$SNAPSHOT_LIST" | command tr -d ' ')" -eq 1 ]
	[ "$(awk '{print substr($1, 1, 10)}' "$SNAPSHOT_LIST")" = "-rw-------" ]
	snapshot_name="$(awk '{print $NF}' "$SNAPSHOT_LIST")"
	[[ "$snapshot_name" == relay-gate-* ]]
	[[ "$snapshot_name" != *.part ]]
	[ -z "$(ls -A "$TMPDIR")" ]
}

@test "job_map_repo_load_sedが終了状態0のまま何も出力しない場合_走査完了の証跡が無いため失敗の状態を返すこと" {
	# Arrange(出力なしが「異常な行なし」を意味しないこと。NUL を落とした行を ok にしない)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J\0001,/w,/s,"[]",60\n'
	} >"$MAP"
	sed() { command cat >/dev/null; }

	# Act
	local status=0
	job_map_repo_load "$MAP" || status=$?

	# Assert
	[ "$status" -eq "$JOB_MAP_REPO_STATUS_COMMAND_FAILED" ]
	[ "$(job_map_repo_row_count)" -eq 0 ]
}

@test "job_map_repo_load_trが終了状態0のまま何も出力しない場合_走査完了の証跡が無いため失敗の状態を返すこと" {
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J1,/w\377,/s,"[]",60\n'
	} >"$MAP"
	tr() { :; }

	# Act
	local status=0
	job_map_repo_load "$MAP" || status=$?

	# Assert
	[ "$status" -eq "$JOB_MAP_REPO_STATUS_COMMAND_FAILED" ]
	[ "$(job_map_repo_row_count)" -eq 0 ]
}

@test "job_map_repo_load_trが入力の途中までしか渡さない場合_総行数が読み込んだ行数と合わないため失敗の状態を返すこと" {
	# Arrange(先頭 1 行だけを走査した結果を、ファイル全体の走査結果として使わない)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J\0001,/w,/s,"[]",60\n'
	} >"$MAP"
	tr() { command head -n 1; }

	# Act
	local status=0
	job_map_repo_load "$MAP" || status=$?

	# Assert
	[ "$status" -eq "$JOB_MAP_REPO_STATUS_COMMAND_FAILED" ]
	[ "$(job_map_repo_row_count)" -eq 0 ]
}

@test "job_map_repo_load_空のファイルと改行の無い1行だけのファイルの場合_走査完了として読み込むこと" {
	# Arrange / Act / Assert(空のファイルは最終行が無く証跡も出ない)
	: >"$MAP"
	job_map_repo_load "$MAP"
	[ "$JOB_MAP_HEADER_STATUS" = "missing" ]
	[ "$JOB_MAP_SCANNED_LINE_COUNT" -eq 0 ]

	printf 'job_id' >"$MAP"
	job_map_repo_load "$MAP"
	[ "$JOB_MAP_HEADER_STATUS" = "ok" ]
	[ "$JOB_MAP_SCANNED_LINE_COUNT" -eq 1 ]
}

@test "job_map_repo_load_事前走査の直後に同じ行数のNULを含むファイルへmvで差し替えた場合_差し替え前の内容だけを読み込み元のパスを記録すること" {
	# Arrange(attempt 4 F-001。通常の tr の直後に差し替える)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/old,/s,[],60'
	} >"$MAP"
	NEXT="$BATS_TEST_TMPDIR/next.csv"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J\0002,/new,/s,[],60\n'
	} >"$NEXT"
	tr() {
		command tr "$@"
		command mv "$NEXT" "$MAP"
	}

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ ! -e "$NEXT" ]
	[ "$JOB_MAP_PATH" = "$MAP" ]
	[ "$(job_map_repo_row_count)" -eq 1 ]
	[ "${JOB_MAP_ROW_STATUSES[0]}" = "ok" ]
	job_map_repo_row 0
	[ "${JOB_MAP_ROW[0]}" = "J1" ]
	[ "${JOB_MAP_ROW[1]}" = "/old" ]
}

@test "job_map_repo_load_読み込みを終えた場合_呼び出し前のEXITとTERMのtrapを元に戻すこと" {
	# Arrange(読み込み中だけ一時ファイルの削除を trap に登録する。呼び出し元の trap を壊さない)
	# (bats 自身が登録した trap をそのまま呼び出し元の trap として使う)
	printf '%s\n' 'job_id' >"$MAP"
	local before
	before="$(trap -p EXIT INT TERM HUP)"

	# Act
	job_map_repo_load "$MAP"

	# Assert
	[ "$(trap -p EXIT INT TERM HUP)" = "$before" ]
}
