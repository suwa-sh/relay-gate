#!/usr/bin/env bats
# UC eff24f55 × tier-facade: domain 層 JobMap / JobMapRow / HangDetectLimit の検証表(純粋関数)の単体テスト。
# 仕様: tier-facade.md「設定契約(slot ジョブマップ CSV)」列の検証表 / ヘッダー検証 / JSON 配列の判定

HEADER_9=(job_id host user work_dir script fixed_params hang_detect_limit_minutes credential_ref map_version)

setup() {
	# 任意入力の表示(制御文字の可視表記)は domain/cli_field.sh に依存する
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/cli_field.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/job_map.sh"
}

# 有効な 9 列の行を JobMapRow に載せる
bind_valid_row() {
	job_map_header_bind "${HEADER_9[@]}"
	job_map_row_bind JOB001 host-green-01 batch /var/app/work /opt/app/bin/job001.sh '["--mode","full"]' 60 ssh-key-green map-v3
}

# ---- validate_job_map_header ----

@test "validate_job_map_header_契約の9列の場合_出力なしで0を返すこと" {
	# Arrange / Act
	run validate_job_map_header map.csv "${HEADER_9[@]}"

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_job_map_header_hostとuserの列が無い必須5列の場合_0を返すこと" {
	# Arrange / Act
	run validate_job_map_header map.csv job_id work_dir script fixed_params hang_detect_limit_minutes

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_job_map_header_必須列が複数欠けた場合_契約の列順でmissingに並べて1を返すこと" {
	# Arrange / Act
	run validate_job_map_header map.csv job_id work_dir fixed_params

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: job map header mismatch missing=script,hang_detect_limit_minutes path: map.csv" ]
}

@test "validate_job_map_header_hostだけあってuserが無い場合_missing=userで1を返すこと" {
	# Arrange / Act
	run validate_job_map_header map.csv job_id host work_dir script fixed_params hang_detect_limit_minutes

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: job map header mismatch missing=user path: map.csv" ]
}

@test "validate_job_map_header_userだけあってhostが無い場合_missing=hostで1を返すこと" {
	# Arrange / Act
	run validate_job_map_header map.csv job_id user work_dir script fixed_params hang_detect_limit_minutes

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: job map header mismatch missing=host path: map.csv" ]
}

@test "validate_job_map_header_impl_version列がある場合_unknown columnのwarnを出して0を返すこと" {
	# Arrange / Act
	run validate_job_map_header map.csv "${HEADER_9[@]}" impl_version

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "warn: unknown column column=impl_version path: map.csv" ]
}

@test "validate_job_map_header_同じ列名が2回ある場合_duplicate columnで1を返すこと" {
	# Arrange / Act(tier-facade.md 入力の守備範囲「ヘッダー列名の重複」。spec reflux 20260921_100000 で追加)
	run validate_job_map_header map.csv job_id work_dir script fixed_params hang_detect_limit_minutes job_id

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: duplicate column column=job_id path: map.csv" ]
}

@test "validate_job_map_header_任意列と未知列が重複する場合_重複した列名ごとにduplicate columnを出して1を返すこと" {
	# Arrange / Act(map_version(任意列)と note(未知列)がそれぞれ 2 回。同種の違反は全件を 1 行ずつ報告する)
	run validate_job_map_header map.csv "${HEADER_9[@]}" map_version note note

	# Assert(行の並びは仕様が定めないため、存在だけを確認する)
	[ "$status" -eq 1 ]
	local found_map_version=false found_note=false line
	for line in "${lines[@]}"; do
		[ "$line" = "error: duplicate column column=map_version path: map.csv" ] && found_map_version=true
		[ "$line" = "error: duplicate column column=note path: map.csv" ] && found_note=true
	done
	[ "$found_map_version" = true ]
	[ "$found_note" = true ]
}

@test "validate_job_map_header_ヘッダーが空の場合_必須5列すべてをmissingに並べて1を返すこと" {
	# Arrange / Act
	run validate_job_map_header map.csv

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: job map header mismatch missing=job_id,work_dir,script,fixed_params,hang_detect_limit_minutes path: map.csv" ]
}

# ---- job_map_header_bind / job_map_row_bind ----

@test "job_map_row_bind_列順が入れ替わったヘッダーの場合_ヘッダー名で値を対応付けること" {
	# Arrange
	job_map_header_bind host job_id user script work_dir fixed_params hang_detect_limit_minutes credential_ref map_version

	# Act
	job_map_row_bind host-green-01 JOB001 batch /opt/app/bin/job001.sh /var/app/work '[]' 60 ssh-key-green map-v3

	# Assert
	[ "$JOB_MAP_ROW_JOB_ID" = "JOB001" ]
	[ "$JOB_MAP_ROW_HOST" = "host-green-01" ]
	[ "$JOB_MAP_ROW_WORK_DIR" = "/var/app/work" ]
	[ "$JOB_MAP_ROW_SCRIPT" = "/opt/app/bin/job001.sh" ]
	[ "$JOB_MAP_ROW_MAP_VERSION" = "map-v3" ]
}

@test "job_map_row_bind_任意列が無いヘッダーの場合_無い列の値が空であること" {
	# Arrange
	job_map_header_bind job_id work_dir script fixed_params hang_detect_limit_minutes

	# Act
	job_map_row_bind JOB001 /var/app/work /opt/app/bin/job001.sh '[]' 0

	# Assert
	[ "$JOB_MAP_ROW_JOB_ID" = "JOB001" ]
	[ -z "$JOB_MAP_ROW_HOST" ]
	[ -z "$JOB_MAP_ROW_USER" ]
	[ -z "$JOB_MAP_ROW_CREDENTIAL_REF" ]
	[ -z "$JOB_MAP_ROW_MAP_VERSION" ]
	[ "$JOB_MAP_ROW_HANG_DETECT_LIMIT_MINUTES" = "0" ]
}

# ---- job_map_fixed_params_parse / job_map_fixed_params_to_json ----

@test "job_map_fixed_params_parse_空配列の場合_要素0件で0を返すこと" {
	# Arrange / Act
	job_map_fixed_params_parse '[]'

	# Assert
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 0 ]
}

@test "job_map_fixed_params_parse_空白とカンマを含む文字列要素の場合_引数の数と空白とカンマを維持すること" {
	# Arrange / Act
	job_map_fixed_params_parse '["p2 p3","a,b"]'

	# Assert
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 2 ]
	[ "${JOB_MAP_FIXED_PARAMS[0]}" = "p2 p3" ]
	[ "${JOB_MAP_FIXED_PARAMS[1]}" = "a,b" ]
}

@test "job_map_fixed_params_parse_許可されたエスケープを含む場合_エスケープを解除した要素になること" {
	# Arrange / Act
	job_map_fixed_params_parse '["a\"b","c\\d","e\/f","g\th"]'

	# Assert
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 4 ]
	[ "${JOB_MAP_FIXED_PARAMS[0]}" = 'a"b' ]
	[ "${JOB_MAP_FIXED_PARAMS[1]}" = 'c\d' ]
	[ "${JOB_MAP_FIXED_PARAMS[2]}" = 'e/f' ]
	[ "${JOB_MAP_FIXED_PARAMS[3]}" = $'g\th' ]
}

@test "job_map_fixed_params_parse_要素の間に空白がある場合_JSON配列として受け付けること" {
	# Arrange / Act
	job_map_fixed_params_parse '[ "a" , "b" ]'

	# Assert
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 2 ]
	[ "${JOB_MAP_FIXED_PARAMS[1]}" = "b" ]
}

@test "job_map_fixed_params_parse_配列でない文字列の場合_1を返すこと" {
	# Arrange / Act
	run job_map_fixed_params_parse 'p1,p2'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_parse_数値要素の場合_1を返すこと" {
	# Arrange / Act
	run job_map_fixed_params_parse '["a",1]'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_parse_ネストした配列の場合_1を返すこと" {
	# Arrange / Act
	run job_map_fixed_params_parse '[["a"]]'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_parse_末尾カンマの場合_1を返すこと" {
	# Arrange / Act
	run job_map_fixed_params_parse '["a",]'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_parse_閉じ括弧が無い場合_1を返すこと" {
	# Arrange / Act
	run job_map_fixed_params_parse '["a"'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_parse_配列の後ろに余剰文字がある場合_1を返すこと" {
	# Arrange / Act
	run job_map_fixed_params_parse '["a"]x'

	# Assert
	[ "$status" -eq 1 ]
}

# JSON の文字列は未エスケープの制御文字(U+0000〜U+001F)を含められない(エスケープした \t は許可)

@test "job_map_fixed_params_parse_文字列内に生のタブがある場合_1を返すこと" {
	# Arrange / Act
	run job_map_fixed_params_parse $'["a\tb"]'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_parse_文字列内に生のCRがある場合_1を返すこと" {
	# Arrange / Act
	run job_map_fixed_params_parse $'["a\rb"]'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_parse_文字列内に生のESCがある場合_1を返すこと" {
	# Arrange / Act
	run job_map_fixed_params_parse $'["a\eb"]'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_parse_文字列内に生の改行がある場合_1を返すこと" {
	# Arrange / Act
	run job_map_fixed_params_parse $'["a\nb"]'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_parse_文字列内にDELや非ASCII文字がある場合_JSON文字列として受け付けること" {
	# Arrange / Act(U+0020 以上は JSON の文字列にそのまま置ける)
	job_map_fixed_params_parse $'["a\x7fb","日本語"]'

	# Assert
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 2 ]
	[ "${JOB_MAP_FIXED_PARAMS[1]}" = "日本語" ]
}

@test "job_map_fixed_params_parse_配列の前後に空白がある場合_JSON配列として受け付けること" {
	# Arrange / Act(文字列の外の半角空白とタブは読み飛ばす)
	job_map_fixed_params_parse $'  [ "a" ,\t"b" ] \t'

	# Assert
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 2 ]
	[ "${JOB_MAP_FIXED_PARAMS[1]}" = "b" ]
}

@test "job_map_fixed_params_parse_配列の後ろにスラッシュがある場合_1を返すこと" {
	# Arrange / Act
	run job_map_fixed_params_parse '["a"]/'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_parse_文字列の外に生のCRがある場合_1を返すこと" {
	# Arrange / Act(文字列の外で読み飛ばすのは半角空白とタブだけ)
	run job_map_fixed_params_parse $'["a"]\r'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_parse_文字列の閉じ引用符が無い場合_1を返すこと" {
	# Arrange / Act
	run job_map_fixed_params_parse '["a'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_parse_バックスラッシュで終わる場合_1を返すこと" {
	# Arrange / Act
	run job_map_fixed_params_parse '["a\'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_parse_文字列内に不正なUTF-8バイト列がある場合_バイト列を変えずに要素へ取り込むこと" {
	# Arrange / Act(0xe3 は続きのバイトが無い先頭バイト。直後の閉じ引用符を巻き込まない)
	job_map_fixed_params_parse $'["a\xe3","\xff\xfe"]'

	# Assert
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 2 ]
	[ "${JOB_MAP_FIXED_PARAMS[0]}" = $'a\xe3' ]
	[ "${JOB_MAP_FIXED_PARAMS[1]}" = $'\xff\xfe' ]
}

@test "job_map_fixed_params_parse_取り込みの窓が1バイトの場合_窓の境界をまたぐエスケープと空白を正しく解析すること" {
	# Arrange(長い値は窓ごとに取り込む。窓の大きさで結果が変わらないこと)
	JOB_MAP_PARSE_WINDOW_BYTES=1

	# Act
	job_map_fixed_params_parse '  [ "p2 p3" , "a\"b\\c\/d\n\t" ,"日本語","" ]  '

	# Assert
	[ "${#JOB_MAP_FIXED_PARAMS[@]}" -eq 4 ]
	[ "${JOB_MAP_FIXED_PARAMS[0]}" = "p2 p3" ]
	[ "${JOB_MAP_FIXED_PARAMS[1]}" = $'a"b\\c/d\n\t' ]
	[ "${JOB_MAP_FIXED_PARAMS[2]}" = "日本語" ]
	[ "${JOB_MAP_FIXED_PARAMS[3]}" = "" ]
}

@test "job_map_fixed_params_parse_取り込みの窓が1バイトで閉じ引用符が無い場合_1を返すこと" {
	# Arrange
	JOB_MAP_PARSE_WINDOW_BYTES=1

	# Act
	run job_map_fixed_params_parse '["abc'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_to_json_取り込みの窓が1バイトの場合_窓の大きさに関係なく同じJSON配列表記になること" {
	# Arrange
	JOB_MAP_PARSE_WINDOW_BYTES=1
	JOB_MAP_FIXED_PARAMS=($'a"b\\c\n\t\r' "日本語" "")

	# Act
	run job_map_fixed_params_to_json

	# Assert
	[ "$output" = '["a\"b\\c\n\t\u000d","日本語",""]' ]
}

@test "job_map_fixed_params_parse_20万文字の要素の場合_10秒以内に解析してJSON配列表記へ戻せること" {
	# Arrange(要素の長さに上限は無い。文字数の 2 乗の時間をかけない)
	local long_value json
	long_value="$(head -c 200000 /dev/zero | tr '\000' 'a')"
	SECONDS=0

	# Act
	job_map_fixed_params_parse "[\"$long_value\"]"
	json="$(job_map_fixed_params_to_json)"

	# Assert
	[ "${#JOB_MAP_FIXED_PARAMS[0]}" -eq 200000 ]
	[ "${#json}" -eq 200004 ]
	[ "$SECONDS" -lt 10 ]
}

@test "job_map_is_valid_job_id_アクセント付き文字を含む場合_1を返すこと" {
	# Arrange / Act(文字範囲は ASCII のバイトとして判定する)
	run job_map_is_valid_job_id 'JOBé'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_is_valid_job_id_全角英数字の場合_1を返すこと" {
	# Arrange / Act
	run job_map_is_valid_job_id 'ＪＯＢ１'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_is_valid_hang_detect_limit_全角数字の場合_1を返すこと" {
	# Arrange / Act
	run job_map_is_valid_hang_detect_limit '６０'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_parse_許可されていないエスケープの場合_1を返すこと" {
	# Arrange / Act
	run job_map_fixed_params_parse '["a\bz"]'

	# Assert
	[ "$status" -eq 1 ]
}

@test "job_map_fixed_params_to_json_解析後の配列の場合_空白を詰めたJSON配列表記に戻すこと" {
	# Arrange
	job_map_fixed_params_parse '[ "p2 p3" , "a\"b" , "c\\d" , "e\tf" ]'

	# Act
	run job_map_fixed_params_to_json

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = '["p2 p3","a\"b","c\\d","e\tf"]' ]
}

@test "job_map_fixed_params_to_json_エスケープを解除した改行とタブを含む要素の場合_エスケープし直して1行のJSONにすること" {
	# Arrange
	job_map_fixed_params_parse '["a\nb\tc"]'

	# Act
	run job_map_fixed_params_to_json

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 1 ]
	[ "$output" = '["a\nb\tc"]' ]
}

@test "job_map_fixed_params_to_json_要素にCRやESCの制御文字がある場合_u00XXにエスケープして生の制御文字を出さないこと" {
	# Arrange(runner と共有する関数。解析を経ない配列を渡されても JSON 配列表記を崩さない)
	JOB_MAP_FIXED_PARAMS=($'a\rb' $'c\ed' $'e\x01f')

	# Act
	run job_map_fixed_params_to_json

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = '["a\u000db","c\u001bd","e\u0001f"]' ]
}

# ---- validate_job_map_row ----

@test "validate_job_map_row_fixed_paramsの文字列内に生の制御文字がある場合_is not a json array of stringsで1を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_FIXED_PARAMS=$'["a\eb"]'

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 1 ]
	# value= は生の ESC を出さず可視表記にする
	[ "$output" = 'error: fixed_params is not a json array of strings line=2 job_id=JOB001 value=["a\u001bb"]' ]
}

@test "validate_job_map_row_有効な行の場合_出力なしで0を返すこと" {
	# Arrange
	bind_valid_row

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_job_map_row_job_idに使えない文字がある場合_job_id is invalidで1を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_JOB_ID='JOB 001'

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: job_id is invalid line=2 job_id=JOB 001 value=JOB 001" ]
}

@test "validate_job_map_row_hostが空でuserに値がある場合_host is emptyで1を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_HOST=""

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: host is empty line=2 job_id=JOB001 value=" ]
}

@test "validate_job_map_row_hostに値があってuserが空の場合_user is emptyで1を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_USER=""

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: user is empty line=2 job_id=JOB001 value=" ]
}

@test "validate_job_map_row_hostとuserが両方空の場合_ローカル実行として0を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_HOST=""
	JOB_MAP_ROW_USER=""

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_job_map_row_work_dirとscriptが相対パスの場合_形式を検査せず受理して0を返すこと" {
	# Arrange(tier-facade.md 設定契約: work_dir / script は非空のみ検証し、パスの形式(Linux / Windows / 相対)は検査しない。
	#         spec reflux 20260921_100000 で絶対パス検査を撤回)
	bind_valid_row
	JOB_MAP_ROW_WORK_DIR="var/app/work"
	JOB_MAP_ROW_SCRIPT="bin/job001.sh"

	# Act
	run validate_job_map_row 4

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_job_map_row_work_dirとscriptが方針資料のWindows形式パスの場合_受理して0を返すこと" {
	# Arrange(方針資料のジョブマップ例。ドライブ文字 + バックスラッシュ)
	bind_valid_row
	JOB_MAP_ROW_WORK_DIR='G:\scripts'
	JOB_MAP_ROW_SCRIPT='G:\scripts\xxx.bat'

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_job_map_row_work_dirとscriptが方針資料の相対パスの場合_受理して0を返すこと" {
	# Arrange(方針資料のジョブマップ例。./ で始まる相対パス)
	bind_valid_row
	JOB_MAP_ROW_WORK_DIR='./beam-batches'
	JOB_MAP_ROW_SCRIPT='./beam-batches/TOMM0410010100.sh'

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_job_map_row_fixed_paramsがJSON配列でない場合_is not a json array of stringsで1を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_JOB_ID="JOB003"
	JOB_MAP_ROW_FIXED_PARAMS="p1,p2"

	# Act
	run validate_job_map_row 3

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: fixed_params is not a json array of strings line=3 job_id=JOB003 value=p1,p2" ]
}

@test "validate_job_map_row_hang_detect_limit_minutesが非負整数でない場合_is not a non-negative integerで1を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_HANG_DETECT_LIMIT_MINUTES="60m"

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=60m" ]
}

@test "validate_job_map_row_hang_detect_limit_minutesが0の場合_検知対象外として0を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_HANG_DETECT_LIMIT_MINUTES="0"

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_job_map_row_必須列のセルが空の場合_is emptyで1を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_SCRIPT=""

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: script is empty line=2 job_id=JOB001 value=" ]
}

@test "validate_job_map_row_credential_refがパス形式の場合_値を出さないwarnを出して0を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_CREDENTIAL_REF="/home/batch/.ssh/id_green"

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" ]
}

@test "validate_job_map_row_credential_refがBEGINを含む場合_warnを出して0を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_CREDENTIAL_REF="-----BEGIN-KEY-----"

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" ]
}

@test "validate_job_map_row_credential_refが空の場合_warnを出さず0を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_CREDENTIAL_REF=""

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# ---- S2 test-scaffold scoped 再生成(spec event 20260923_112000_feedback_impl_feedback_eff24f55_cycle2)----
# 条件「認証情報の非保存」: 参照名 `^[A-Za-z0-9_.-]*$` に合わない値は理由を問わず同じ warn 1 行で受理し、値は出さない。
# 正規表現に合っていても BEGIN を含む値は同じ warn。

@test "validate_job_map_row_credential_refが空白を含む場合_値を出さない同じwarnを1行出して0を返すこと" {
	# Arrange("/" も "BEGIN" も含まない。空白だけで参照名の形式に合わない)
	bind_valid_row
	JOB_MAP_ROW_CREDENTIAL_REF="ssh key green"

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 1 ]
	[ "$output" = "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" ]
}

@test "validate_job_map_row_credential_refが参照名に使えない記号を含む場合_同じwarnを1行出して0を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_CREDENTIAL_REF="key@green:1"

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" ]
}

@test "validate_job_map_row_credential_refが非ASCII文字を含む場合_同じwarnを1行出して0を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_CREDENTIAL_REF="鍵-green"

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" ]
}

@test "validate_job_map_row_credential_refが参照名の形式でBEGINを含む場合_同じwarnを1行出して0を返すこと" {
	# Arrange(正規表現には合うが BEGIN を含む)
	bind_valid_row
	JOB_MAP_ROW_CREDENTIAL_REF="BEGIN_KEY"

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" ]
}

@test "validate_job_map_row_credential_refが英数字とドットとハイフンとアンダースコアだけの場合_warnを出さず0を返すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_CREDENTIAL_REF="ssh-key.green_01"

	# Act
	run validate_job_map_row 2

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

# ---- job_map_row_resolved_line ----

@test "job_map_row_resolved_line_SSH実行の行の場合_exec=sshと解析後のfixed_paramsを1行で出すこと" {
	# Arrange
	bind_valid_row

	# Act
	run job_map_row_resolved_line

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = 'info: resolved job_id=JOB001 host=host-green-01 user=batch exec=ssh work_dir=/var/app/work script=/opt/app/bin/job001.sh fixed_params=["--mode","full"] hang_detect_limit_minutes=60' ]
}

@test "job_map_row_resolved_line_hostとuserが空の行の場合_host=-とuser=-とexec=localを出すこと" {
	# Arrange
	bind_valid_row
	JOB_MAP_ROW_HOST=""
	JOB_MAP_ROW_USER=""
	JOB_MAP_ROW_FIXED_PARAMS="[]"
	JOB_MAP_ROW_HANG_DETECT_LIMIT_MINUTES="0"

	# Act
	run job_map_row_resolved_line

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = 'info: resolved job_id=JOB001 host=- user=- exec=local work_dir=/var/app/work script=/opt/app/bin/job001.sh fixed_params=[] hang_detect_limit_minutes=0' ]
}

# ---- validate_job_map_unique_job_ids ----

@test "validate_job_map_unique_job_ids_job_idが一意の場合_出力なしで0を返すこと" {
	# Arrange / Act
	run validate_job_map_unique_job_ids 2 JOB001 3 JOB002

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_job_map_unique_job_ids_2行目と5行目が同じjob_idの場合_lines=2,5で1を返すこと" {
	# Arrange / Act
	run validate_job_map_unique_job_ids 2 JOB001 3 JOB002 4 JOB003 5 JOB001

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: duplicate job_id job_id=JOB001 lines=2,5" ]
}

@test "validate_job_map_unique_job_ids_同じjob_idが3回と別の重複がある場合_job_idごとに1行で全行番号を並べること" {
	# Arrange / Act
	run validate_job_map_unique_job_ids 2 JOB001 3 JOB002 4 JOB001 5 JOB002 6 JOB001

	# Assert
	[ "$status" -eq 1 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "error: duplicate job_id job_id=JOB001 lines=2,4,6" ]
	[ "${lines[1]}" = "error: duplicate job_id job_id=JOB002 lines=3,5" ]
}

@test "validate_job_map_unique_job_ids_複数のjob_idが重複する場合_1回目の出現行が早いjob_idから順に出すこと" {
	# Arrange / Act(文字列の辞書順では AAA が先。出力は 1 回目の出現行の昇順)
	run validate_job_map_unique_job_ids 2 ZZZ 3 AAA 4 AAA 5 ZZZ 10 BBB 11 BBB

	# Assert
	[ "$status" -eq 1 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[0]}" = "error: duplicate job_id job_id=ZZZ lines=2,5" ]
	[ "${lines[1]}" = "error: duplicate job_id job_id=AAA lines=3,4" ]
	[ "${lines[2]}" = "error: duplicate job_id job_id=BBB lines=10,11" ]
}

@test "validate_job_map_unique_job_ids_形式違反のjob_idが空白やタブや記号を含む場合_文字列の完全一致で重複を判定すること" {
	# Arrange / Act("A B" と "A" は別の値。タブ入り・glob 文字入りも値のまま比較する)
	run validate_job_map_unique_job_ids 2 'A B' 3 'A' 4 $'T\tX' 5 '*' 6 'A B' 7 $'T\tX' 8 '*' 9 'a b'

	# Assert
	[ "$status" -eq 1 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[0]}" = "error: duplicate job_id job_id=A B lines=2,6" ]
	[ "${lines[1]}" = 'error: duplicate job_id job_id=T\tX lines=4,7' ]
	[ "${lines[2]}" = "error: duplicate job_id job_id=* lines=5,8" ]
}

@test "validate_job_map_unique_job_ids_sortが失敗しjob_idが重複する場合_重複なしの0を返さず内部エラーの状態を返すこと" {
	# Arrange(attempt 3 の独立検証 F-002 と同じ障害注入)
	sort() { return 1; }

	# Act
	run validate_job_map_unique_job_ids 2 JOB001 3 JOB001

	# Assert
	[ "$status" -eq "$JOB_MAP_STATUS_COMMAND_FAILED" ]
	[ -z "$output" ]
}

@test "validate_job_map_unique_job_ids_sortが出力した後で失敗する場合_途中までの並びを使わず内部エラーの状態を返すこと" {
	# Arrange(出力があっても終了状態が非 0 なら並べ替えは未完了)
	sort() {
		command cat
		return 2
	}

	# Act
	run validate_job_map_unique_job_ids 2 JOB001 3 JOB002

	# Assert
	[ "$status" -eq "$JOB_MAP_STATUS_COMMAND_FAILED" ]
	[ -z "$output" ]
}

@test "validate_job_map_unique_job_ids_sortが終了状態0のまま行を返さない場合_重複なしの0を返さず内部エラーの状態を返すこと" {
	# Arrange(並べ替え結果の行数が入力と合わなければ、重複検査は未完了)
	sort() { command cat >/dev/null; }

	# Act
	run validate_job_map_unique_job_ids 2 JOB001 3 JOB001

	# Assert
	[ "$status" -eq "$JOB_MAP_STATUS_COMMAND_FAILED" ]
	[ -z "$output" ]
}

@test "validate_job_map_unique_job_ids_sortが並べ替えずに入力をそのまま返す場合_離れた行の重複を見逃さず内部エラーの状態を返すこと" {
	# Arrange(行数は合うが job_id の昇順になっていない)
	sort() { command cat; }

	# Act
	run validate_job_map_unique_job_ids 2 JOB002 3 JOB001 4 JOB002

	# Assert
	[ "$status" -eq "$JOB_MAP_STATUS_COMMAND_FAILED" ]
	[ -z "$output" ]
}

@test "job_map_split_lines_空白とタブとglob文字を含む行の場合_行を変えずに配列へ分けてnoglobの設定を元へ戻すこと" {
	# Arrange / Act
	job_map_split_lines $'2\tA B\n3\t*\n4\t T\tX '

	# Assert
	[ "${#JOB_MAP_LINES[@]}" -eq 3 ]
	[ "${JOB_MAP_LINES[0]}" = $'2\tA B' ]
	[ "${JOB_MAP_LINES[1]}" = $'3\t*' ]
	[ "${JOB_MAP_LINES[2]}" = $'4\t T\tX ' ]
	[[ "$-" != *f* ]]
}

@test "validate_job_map_unique_job_ids_重複の報告順を決める2回目のsortだけが失敗する場合_内部エラーの状態を返しduplicateの行を出さないこと" {
	# Arrange
	sort() {
		# run はサブシェルで動くため、呼び出し回数はファイルで数える
		printf 'x' >>"$BATS_TEST_TMPDIR/sort-calls"
		if [ "$(wc -c <"$BATS_TEST_TMPDIR/sort-calls")" -ge 2 ]; then
			return 1
		fi
		command sort "$@"
	}

	# Act
	run validate_job_map_unique_job_ids 2 JOB001 3 JOB001

	# Assert
	[ "$status" -eq "$JOB_MAP_STATUS_COMMAND_FAILED" ]
	[ -z "$output" ]
}

@test "job_map_version_summary_値に制御文字がある場合_集計値は元の値のままでwarn行だけ可視表記にすること" {
	# Arrange / Act(集計値は usecase が cli_field_line で表示用に置き換える)
	run job_map_version_summary $'v\0331' v2

	# Assert
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = $'v\0331,v2' ]
	[ "${lines[1]}" = 'warn: mixed map_version values=v\u001b1,v2' ]
}

@test "validate_job_map_header_未知列名とパスに制御文字がある場合_warnとerrorを1行ずつ可視表記で出すこと" {
	# Arrange / Act
	run validate_job_map_header $'/tmp/m\n.csv' job_id $'x\033[0m'

	# Assert
	[ "$status" -eq 1 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = 'warn: unknown column column=x\u001b[0m path: /tmp/m\n.csv' ]
	[ "${lines[1]}" = 'error: job map header mismatch missing=work_dir,script,fixed_params,hang_detect_limit_minutes path: /tmp/m\n.csv' ]
}

@test "job_map_fixed_params_to_json_要素にDELとC1制御文字がある場合_u007fとu009bにエスケープすること" {
	# Arrange(U+009B は端末が CSI として解釈する。JSON としては同じ文字列を表す)
	JOB_MAP_FIXED_PARAMS=($'a\177b' $'c\xc2\x9bd')

	# Act
	run job_map_fixed_params_to_json

	# Assert
	[ "$output" = '["a\u007fb","c\u009bd"]' ]
}

@test "validate_job_map_unique_job_ids_空のjob_idが複数ある場合_重複として数えないこと" {
	# Arrange / Act
	run validate_job_map_unique_job_ids 2 "" 3 "" 4 JOB001

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_job_map_unique_job_ids_行が無い場合_出力なしで0を返すこと" {
	# Arrange / Act
	run validate_job_map_unique_job_ids

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_job_map_unique_job_ids_一意なjob_idが2000行ある場合_全組合せ比較をせず10秒以内に0を返すこと" {
	# Arrange(nfr-grade B.2.1.1 の CLI 応答 10 秒目標。全組合せ比較では約 200 万回の比較になる)
	local pairs=() index=1
	while [ "$index" -le 2000 ]; do
		pairs+=("$((index + 1))" "JOB$index")
		index=$((index + 1))
	done
	SECONDS=0

	# Act
	run validate_job_map_unique_job_ids "${pairs[@]}"

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ "$SECONDS" -lt 10 ]
}

# ---- job_map_version_summary ----

@test "job_map_version_summary_全行が同じ版の場合_その版だけを返すこと" {
	# Arrange / Act
	run job_map_version_summary map-v3 map-v3

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "map-v3" ]
}

@test "job_map_version_summary_列が無いか全行空の場合_空値表記を返すこと" {
	# Arrange / Act
	run job_map_version_summary "" ""

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "-" ]
}

@test "job_map_version_summary_行が無い場合_空値表記を返すこと" {
	# Arrange / Act
	run job_map_version_summary

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "-" ]
}

@test "job_map_version_summary_版が混在する場合_distinct値とmixed map_versionのwarnを返すこと" {
	# Arrange / Act
	run job_map_version_summary map-v3 map-v4 map-v3

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "map-v3,map-v4" ]
	[ "${lines[1]}" = "warn: mixed map_version values=map-v3,map-v4" ]
}

@test "job_map_version_summary_空の行と値のある行が混在する場合_空もdistinct値に数えてmixed map_versionのwarnを返すこと" {
	# Arrange / Act(計算ルール「版の集計」: 列があれば全行の distinct 値。`-` になるのは全行空のときだけ)
	run job_map_version_summary "" v1

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "-,v1" ]
	[ "${lines[1]}" = "warn: mixed map_version values=-,v1" ]
}

@test "job_map_version_summary_値のある行の後ろに空の行が複数ある場合_空を1つのdistinct値として初出順に並べること" {
	# Arrange / Act
	run job_map_version_summary map-v3 "" map-v4 "" map-v3

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "map-v3,-,map-v4" ]
	[ "${lines[1]}" = "warn: mixed map_version values=map-v3,-,map-v4" ]
}
