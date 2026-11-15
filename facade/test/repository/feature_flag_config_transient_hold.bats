#!/usr/bin/env bats
# UC fd678b04 × tier-facade: feature-flag.env の値を取り込むキーの範囲と、読み取りの途中の一時的な保持の単体テスト。
# 仕様: CLI 契約 config_input_rules.env_files「feature-flag.env から値を取り込むキーの範囲」「読み取りの途中の一時的な保持」
#       (作業用の変数の名前をキー名から決めない / (a) 環境変数にしない・補助コマンドへ環境変数で渡さない /
#        (b) 読み終えたとき・失敗したときに作業用の領域を空にする / (c) 取り込まないキーは値を残さない)、
#       config_files.feature-flag.env.keys(値を取り込むのは 9 キー + 任意の 2 キー)
# I/O 境界(ファイル・補助コマンド)は実体で検証する。
# 取り込まないキーの値は「hold」+ 2 文字 +「marker」の形にし、テストのコマンドにその文字列を直接書かない
# (シェルの変数の一覧に、テスト自身の変数として現れないようにする)。

bats_require_minimum_version 1.5.0

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/feature_flag.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/repository/feature_flag_config.sh"
	ENV_FILE="$BATS_TEST_TMPDIR/ff.env"
	VARIABLES="$BATS_TEST_TMPDIR/variables.txt"
	CHILD_ENV="$BATS_TEST_TMPDIR/child-env.txt"
}

# 取り込まないキー(未知キーと FINAL_ で始まるキー)の行を、有効な設定の後ろに足す
write_env_with_uncaptured_values() {
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=/bin/sh\n' >"$ENV_FILE"
	printf 'PATH=/hold%smarker\nSITE_NOTE=hold%smarker\nFINAL_DB_CONN_REF=hold%smarker\n' AA BB CC >>"$ENV_FILE"
}

# シェルの変数の一覧と、子プロセスの環境変数を書き出す
dump_variables_and_child_env() {
	declare -p >"$VARIABLES"
	env >"$CHILD_ENV"
}

@test "feature_flag_config_load_任意の2キーを書いた場合_同名のグローバル変数に値が載りexportしないこと" {
	# Arrange
	printf 'BLUE_MODE=foreground\nBLUE_JOB_MAP_CSV=./blue-jobs.csv\nGREEN_JOB_MAP_CSV="/srv/maps/green-jobs.csv"\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"
	dump_variables_and_child_env

	# Assert
	[ "$BLUE_JOB_MAP_CSV" = "./blue-jobs.csv" ]
	[ "$GREEN_JOB_MAP_CSV" = "/srv/maps/green-jobs.csv" ]
	[ "${#FEATURE_FLAG_KEYS[@]}" -eq 3 ]
	run ! grep -q -E '^(BLUE|GREEN)_JOB_MAP_CSV=' "$CHILD_ENV"
}

@test "feature_flag_config_load_プロセス環境に任意の2キーと同じ名前の変数がある場合_ファイルに無いキーは未設定に戻ること" {
	# Arrange
	export BLUE_JOB_MAP_CSV=/from/process/blue.csv
	export GREEN_JOB_MAP_CSV=/from/process/green.csv
	printf 'BLUE_MODE=foreground\nGREEN_JOB_MAP_CSV=\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert(値が空のキーは空で載る。無いキーは未設定)
	[ -z "${BLUE_JOB_MAP_CSV+x}" ]
	[ -n "${GREEN_JOB_MAP_CSV+x}" ]
	[ -z "$GREEN_JOB_MAP_CSV" ]
}

@test "feature_flag_config_load_取り込まないキーに値がある場合_読み終えた後のどの変数にも子プロセスの環境にも値が残らないこと" {
	# Arrange
	write_env_with_uncaptured_values
	local path_before="$PATH"

	# Act
	feature_flag_config_load "$ENV_FILE"
	dump_variables_and_child_env

	# Assert(キー名だけを残す。キーと同じ名前の変数へ代入しない)
	[ "$PATH" = "$path_before" ]
	[ -z "${SITE_NOTE+x}" ]
	[ -z "${FINAL_DB_CONN_REF+x}" ]
	[ "${FEATURE_FLAG_KEYS[*]}" = "BLUE_MODE GREEN_MODE RAPID_CROSSCHECK_MODE GREEN_IMPL GREEN_RUNNER PATH SITE_NOTE FINAL_DB_CONN_REF" ]
	[ "$GREEN_IMPL" = "green-1.4.0" ]
	run ! grep -q -E 'hold[A-Z]{2}marker' "$VARIABLES"
	run ! grep -q -E 'hold[A-Z]{2}marker' "$CHILD_ENV"
}

@test "feature_flag_config_load_同じキーの重複で止まる場合_取り込まないキーの値も所有するキーの値もどの変数にも残らないこと" {
	# Arrange(行の構造の違反。そのファイルの値を 1 つも使わない)
	write_env_with_uncaptured_values
	printf 'SITE_NOTE=hold%smarker\nGREEN_IMPL=hold%smarker\n' DD EE >>"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"
	dump_variables_and_child_env

	# Assert
	[ "${FEATURE_FLAG_CONFIG_DUPLICATE_KEYS[*]}" = "GREEN_IMPL SITE_NOTE" ]
	[ -z "${GREEN_IMPL+x}" ]
	run ! grep -q -E 'hold[A-Z]{2}marker' "$VARIABLES"
	run ! grep -q -E 'hold[A-Z]{2}marker' "$CHILD_ENV"
}

@test "feature_flag_config_load_バイト点検の違反で止まる場合_行の内容がどの変数にも残らないこと" {
	# Arrange(CR を含む行がある。行の読み取りには進まない)
	write_env_with_uncaptured_values
	printf 'SITE_MEMO=hold%smarker\r\n' FF >>"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"
	dump_variables_and_child_env

	# Assert
	[ "${#JOB_MAP_MALFORMED_LINES[@]}" -gt 0 ]
	[ "${#FEATURE_FLAG_KEYS[@]}" -eq 0 ]
	run ! grep -q -E 'hold[A-Z]{2}marker' "$VARIABLES"
	run ! grep -q -E 'hold[A-Z]{2}marker' "$CHILD_ENV"
}

@test "feature_flag_config_load_行の構造を取り出すsedが想定外の出力をする場合_内部障害で打ち切り行の内容がどの変数にも残らないこと" {
	# Arrange(sed の代わりに、入力をそのまま出すコマンドを PATH の先頭に置く。種類を表す文字で始まらない行が出る)
	write_env_with_uncaptured_values
	mkdir -p "$BATS_TEST_TMPDIR/bin"
	printf '%s\n' '#!/bin/sh' 'exec cat' >"$BATS_TEST_TMPDIR/bin/sed"
	chmod +x "$BATS_TEST_TMPDIR/bin/sed"
	local path_before="$PATH" status_code=0

	# Act
	PATH="$BATS_TEST_TMPDIR/bin:$PATH"
	feature_flag_config_load "$ENV_FILE" || status_code=$?
	PATH="$path_before"
	dump_variables_and_child_env

	# Assert
	[ "$status_code" -eq "$FEATURE_FLAG_CONFIG_STATUS_COMMAND_FAILED" ]
	[ "${#FEATURE_FLAG_KEYS[@]}" -eq 0 ]
	[ -z "${GREEN_IMPL+x}" ]
	run ! grep -q -E 'hold[A-Z]{2}marker' "$VARIABLES"
	run ! grep -q -E 'hold[A-Z]{2}marker' "$CHILD_ENV"
}

@test "feature_flag_config_load_補助コマンドを起動する場合_行の内容を環境変数で渡さないこと" {
	# Arrange(sed と tr の代わりに、受け取った環境変数を記録してから本物を起動するコマンドを PATH の先頭に置く)
	write_env_with_uncaptured_values
	local record="$BATS_TEST_TMPDIR/helper-env.txt" name real path_before="$PATH"
	mkdir -p "$BATS_TEST_TMPDIR/bin"
	for name in sed tr; do
		real="$(command -v "$name")"
		printf '%s\n' '#!/bin/sh' "env >>'$record'" "exec '$real' \"\$@\"" >"$BATS_TEST_TMPDIR/bin/$name"
		chmod +x "$BATS_TEST_TMPDIR/bin/$name"
	done

	# Act
	PATH="$BATS_TEST_TMPDIR/bin:$PATH"
	feature_flag_config_load "$ENV_FILE"
	PATH="$path_before"

	# Assert(補助コマンドは起動されている。行の内容もキーの値も環境変数に無い)
	[ -s "$record" ]
	[ "$GREEN_IMPL" = "green-1.4.0" ]
	run ! grep -q -E 'hold[A-Z]{2}marker' "$record"
	run ! grep -q -E '^GREEN_IMPL=' "$record"
}

@test "feature_flag_config_load_読み終えた場合_入力の複製の一時ファイルを残さないこと" {
	# Arrange
	write_env_with_uncaptured_values
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir -p "$TMPDIR"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ -z "$(ls -A "$TMPDIR")" ]
}
