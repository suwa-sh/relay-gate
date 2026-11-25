#!/usr/bin/env bats
# UC 7c41c7cd(ジョブマップで JOB_ID から実行先を解決する)× tier-facade: domain/execution_target.sh の単体テスト。
# 対象: spec.md「分岐条件一覧」(ジョブマップ解決条件 / 引数連結規則)「計算ルール一覧」(引数連結)と
#       tier-facade.md「UC ロジック」バリデーション (6)〜(9) の順。

setup() {
	local src="$BATS_TEST_DIRNAME/../../src/domain"
	# shellcheck source=/dev/null
	source "$src/cli_field.sh"
	# shellcheck source=/dev/null
	source "$src/job_map.sh"
	# shellcheck source=/dev/null
	source "$src/execution_target.sh"
	JOB_MAP_REPORT_SINK="$JOB_MAP_REPORT_SINK_ARRAY"
	JOB_MAP_REPORT_LINES=()
}

# JobMapRow を JOB_MAP_COLUMNS の並び(job_id host user work_dir script fixed_params hang_detect_limit_minutes credential_ref map_version)で載せる
bind_row() {
	job_map_row_assign "$@"
}

@test "execution_target_from_row_hostとuserがある行の場合_全項目を載せて実行方式がsshであること" {
	# Arrange
	bind_row JOB001 host-green-01 batch /var/app/work /opt/app/bin/job001.sh '["--mode","full"]' 60 ssh-key-green map-v3

	# Act
	execution_target_from_row 2

	# Assert
	[ "$EXECUTION_TARGET_HOST" = "host-green-01" ]
	[ "$EXECUTION_TARGET_USER" = "batch" ]
	[ "$EXECUTION_TARGET_SCRIPT" = "/opt/app/bin/job001.sh" ]
	[ "$EXECUTION_TARGET_WORK_DIR" = "/var/app/work" ]
	[ "${#EXECUTION_TARGET_FIXED_PARAMS[@]}" -eq 2 ]
	[ "${EXECUTION_TARGET_FIXED_PARAMS[0]}" = "--mode" ]
	[ "${EXECUTION_TARGET_FIXED_PARAMS[1]}" = "full" ]
	[ "$EXECUTION_TARGET_HANG_DETECT_LIMIT_MINUTES" = "60" ]
	[ "$EXECUTION_TARGET_CREDENTIAL_REF" = "ssh-key-green" ]
	[ "$EXECUTION_TARGET_MAP_VERSION" = "map-v3" ]
	[ "$EXECUTION_TARGET_EXEC" = "ssh" ]
	[ "${#JOB_MAP_REPORT_LINES[@]}" -eq 0 ]
}

@test "execution_target_from_row_hostとuserが両方空の行の場合_実行方式がlocalで任意の項目が空であること" {
	# Arrange(ハング検知上限 0 は変換せずそのまま載せる)
	bind_row JOB001 "" "" /var/app/work /opt/app/bin/job001.sh '[]' 0 "" ""

	# Act
	execution_target_from_row 2

	# Assert
	[ "$EXECUTION_TARGET_EXEC" = "local" ]
	[ -z "$EXECUTION_TARGET_HOST" ]
	[ -z "$EXECUTION_TARGET_USER" ]
	[ -z "$EXECUTION_TARGET_CREDENTIAL_REF" ]
	[ -z "$EXECUTION_TARGET_MAP_VERSION" ]
	[ "${#EXECUTION_TARGET_FIXED_PARAMS[@]}" -eq 0 ]
	[ "$EXECUTION_TARGET_HANG_DETECT_LIMIT_MINUTES" = "0" ]
}

@test "execution_target_from_row_Windows形式と相対パスのscriptとwork_dirの場合_形式を検査せずそのまま載せること" {
	# Arrange
	bind_row JOB001 "" "" './beam-batches' 'G:\scripts\xxx.bat' '[]' 0 "" ""

	# Act
	execution_target_from_row 2

	# Assert
	[ "$EXECUTION_TARGET_SCRIPT" = 'G:\scripts\xxx.bat' ]
	[ "$EXECUTION_TARGET_WORK_DIR" = "./beam-batches" ]
}

@test "execution_target_from_row_userだけが空の行の場合_user is emptyのerror行を1行だけ出して1であること" {
	# Arrange
	bind_row JOB004 host-green-01 "" /var/app/work /opt/app/bin/job004.sh '[]' 60 "" ""

	# Act
	run_status=0
	execution_target_from_row 2 || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${#JOB_MAP_REPORT_LINES[@]}" -eq 1 ]
	[ "${JOB_MAP_REPORT_LINES[0]}" = "error: user is empty line=2 job_id=JOB004 value=" ]
	[ -z "$EXECUTION_TARGET_SCRIPT" ]
}

@test "execution_target_from_row_hostだけが空の行の場合_host is emptyのerror行であること" {
	# Arrange
	bind_row JOB004 "" batch /var/app/work /opt/app/bin/job004.sh '[]' 60 "" ""

	# Act
	run_status=0
	execution_target_from_row 2 || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${JOB_MAP_REPORT_LINES[0]}" = "error: host is empty line=2 job_id=JOB004 value=" ]
}

@test "execution_target_from_row_fixed_paramsがJSON配列でない行の場合_固定引数不正のerror行であること" {
	# Arrange
	bind_row JOB003 host-green-01 batch /var/app/work /opt/app/bin/job003.sh 'p1 p2' 60 "" ""

	# Act
	run_status=0
	execution_target_from_row 3 || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${JOB_MAP_REPORT_LINES[0]}" = "error: fixed_params is not a json array of strings line=3 job_id=JOB003 value=p1 p2" ]
}

@test "execution_target_from_row_hang_detect_limit_minutesが非負整数でない行の場合_上限不正のerror行であること" {
	# Arrange
	bind_row JOB003 host-green-01 batch /var/app/work /opt/app/bin/job003.sh '[]' abc "" ""

	# Act
	run_status=0
	execution_target_from_row 3 || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${JOB_MAP_REPORT_LINES[0]}" = "error: hang_detect_limit_minutes is not a non-negative integer line=3 job_id=JOB003 value=abc" ]
}

@test "execution_target_from_row_scriptが空の行の場合_script is emptyのerror行であること" {
	# Arrange
	bind_row JOB004 "" "" /var/app/work "" '[]' 0 "" ""

	# Act
	run_status=0
	execution_target_from_row 2 || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${JOB_MAP_REPORT_LINES[0]}" = "error: script is empty line=2 job_id=JOB004 value=" ]
}

@test "execution_target_from_row_work_dirが空の行の場合_work_dir is emptyのerror行であること" {
	# Arrange
	bind_row JOB004 "" "" "" /opt/app/bin/job004.sh '[]' 0 "" ""

	# Act
	run_status=0
	execution_target_from_row 2 || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${JOB_MAP_REPORT_LINES[0]}" = "error: work_dir is empty line=2 job_id=JOB004 value=" ]
}

@test "execution_target_from_row_複数の違反がある行の場合_バリデーションの順で最初の違反だけを出すこと" {
	# Arrange(user が空 (6)、fixed_params 不正 (7)、上限不正 (8)、script が空 (9))
	bind_row JOB004 host-green-01 "" /var/app/work "" 'p1' abc "" ""

	# Act
	run_status=0
	execution_target_from_row 2 || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${#JOB_MAP_REPORT_LINES[@]}" -eq 1 ]
	[ "${JOB_MAP_REPORT_LINES[0]}" = "error: user is empty line=2 job_id=JOB004 value=" ]
}

@test "execution_target_from_row_fixed_paramsと上限とscriptに違反がある行の場合_fixed_paramsの違反を先に出すこと" {
	# Arrange
	bind_row JOB004 "" "" /var/app/work "" 'p1' abc "" ""

	# Act
	run_status=0
	execution_target_from_row 2 || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${#JOB_MAP_REPORT_LINES[@]}" -eq 1 ]
	[[ "${JOB_MAP_REPORT_LINES[0]}" == "error: fixed_params is not a json array of strings "* ]]
}

@test "execution_target_from_row_credential_refがパスらしい値の行の場合_値を出さないwarn行を出して受理し値をそのまま載せること" {
	# Arrange(契約 columns.credential_ref.on_format_violation / output_rule。検証コマンドと同じ判定・同じ文)
	bind_row JOB001 host-green-01 batch /var/app/work /opt/app/bin/job001.sh '[]' 60 /etc/keys/green.pem map-v3

	# Act
	run_status=0
	execution_target_from_row 2 || run_status=$?

	# Assert
	[ "$run_status" -eq 0 ]
	[ "${#JOB_MAP_REPORT_LINES[@]}" -eq 1 ]
	[ "${JOB_MAP_REPORT_LINES[0]}" = "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" ]
	[ "$EXECUTION_TARGET_CREDENTIAL_REF" = "/etc/keys/green.pem" ]
}

@test "execution_target_from_row_credential_refが参照名の形の行の場合_warn行を出さないこと" {
	# Arrange
	bind_row JOB001 host-green-01 batch /var/app/work /opt/app/bin/job001.sh '[]' 60 ssh-key.green_01 map-v3

	# Act
	execution_target_from_row 2

	# Assert
	[ "${#JOB_MAP_REPORT_LINES[@]}" -eq 0 ]
}

@test "execution_target_from_row_credential_refがパスらしく値の違反もある行の場合_warn行と最初の違反のerror行を出して1であること" {
	# Arrange
	bind_row JOB001 host-green-01 batch /var/app/work "" '[]' 60 "has space" map-v3

	# Act
	run_status=0
	execution_target_from_row 2 || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${#JOB_MAP_REPORT_LINES[@]}" -eq 2 ]
	[ "${JOB_MAP_REPORT_LINES[0]}" = "warn: credential_ref looks like a secret or path line=2 job_id=JOB001" ]
	[ "${JOB_MAP_REPORT_LINES[1]}" = "error: script is empty line=2 job_id=JOB001 value=" ]
}

@test "build_argument_list_空白とカンマを含む要素とPARAMの場合_要素を1引数のまま固定引数の後ろにPARAMを順序どおり足すこと" {
	# Act
	build_argument_list '["p1","p2 p3","a,b"]' x y

	# Assert
	[ "${#ARGUMENT_LIST[@]}" -eq 5 ]
	[ "${ARGUMENT_LIST[0]}" = "p1" ]
	[ "${ARGUMENT_LIST[1]}" = "p2 p3" ]
	[ "${ARGUMENT_LIST[2]}" = "a,b" ]
	[ "${ARGUMENT_LIST[3]}" = "x" ]
	[ "${ARGUMENT_LIST[4]}" = "y" ]
}

@test "build_argument_list_固定引数が空の配列の場合_PARAMだけであること" {
	# Act
	build_argument_list '[]' 20260830

	# Assert
	[ "${#ARGUMENT_LIST[@]}" -eq 1 ]
	[ "${ARGUMENT_LIST[0]}" = "20260830" ]
}

@test "build_argument_list_固定引数もPARAMも無い場合_引数が0個であること" {
	# Act
	build_argument_list '[]'

	# Assert
	[ "${#ARGUMENT_LIST[@]}" -eq 0 ]
}

@test "build_argument_list_要素にエスケープがある場合_エスケープを解除して1要素1引数であること" {
	# Act(JSON の文字列のエスケープ \" と \\ を解除する)
	build_argument_list '["a\"b","c\\d"]' 'e f'

	# Assert
	[ "${#ARGUMENT_LIST[@]}" -eq 3 ]
	[ "${ARGUMENT_LIST[0]}" = 'a"b' ]
	[ "${ARGUMENT_LIST[1]}" = 'c\d' ]
	[ "${ARGUMENT_LIST[2]}" = "e f" ]
}

@test "build_argument_list_PARAMがglob文字や空文字の場合_展開せずそのまま1引数であること" {
	# Act
	build_argument_list '["*"]' '?' ''

	# Assert
	[ "${#ARGUMENT_LIST[@]}" -eq 3 ]
	[ "${ARGUMENT_LIST[0]}" = "*" ]
	[ "${ARGUMENT_LIST[1]}" = "?" ]
	[ "${ARGUMENT_LIST[2]}" = "" ]
}

@test "build_argument_list_固定引数がJSON配列でない場合_1を返して引数列が空であること" {
	# Act
	run_status=0
	build_argument_list 'p1 p2' x || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${#ARGUMENT_LIST[@]}" -eq 0 ]
}
