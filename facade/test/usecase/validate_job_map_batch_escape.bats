#!/usr/bin/env bats
# UC eff24f55 × tier-facade: usecase 層 ValidateJobMapQuery の「報告行の可視表記をまとめて作る」経路の単体テスト。
# 仕様: tier-facade.md「出力契約」(任意入力の制御文字は可視表記)/
#       cli-command-contract.yaml config_input_rules.internal_failure(補助コマンドの失敗は error 行 1 つだけ・終了コード 6・stdout なし)
# 行ごとの検証の報告行と stdout の map_version の可視表記は、外部コマンド(sed / tr)でまとめて作る(値の合計が 4,096 バイト以上のとき)。
# S4 tier-impl(2026-11-16 attempt-6)で追加: 性能の目標値(config_input_rules.performance_target)に近づけるための変更の確認。

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
	load ../domain/cli_field_reference
	MAP="$BATS_TEST_TMPDIR/map.csv"
	STDOUT_FILE="$BATS_TEST_TMPDIR/out.txt"
	STDERR_FILE="$BATS_TEST_TMPDIR/err.txt"
	# 制御文字(改行と CR を除く U+0001〜U+001F と DEL)
	local code char
	CONTROLS=""
	for code in 1 2 3 4 5 6 7 8 9 11 12 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 127; do
		printf -v char "\\$(printf '%03o' "$code")"
		CONTROLS+="$char"
	done
}

# 可視表記をまとめて作る sed(スクリプトに y コマンドを含む)だけを失敗させる。バイト点検の sed は本物へ通す
sed_failing_on_escape() {
	sed() {
		local arg
		for arg in "$@"; do
			case "$arg" in
			y/*)
				command cat >/dev/null
				return 1
				;;
			esac
		done
		command sed "$@"
	}
}

# 改行を消す tr(`tr -d`)だけを失敗させる。バイト点検の tr は本物へ通す
tr_failing_on_delete() {
	tr() {
		if [ "$1" = "-d" ]; then
			command cat >/dev/null
			return 1
		fi
		command tr "$@"
	}
}

# 有効な行を count 行書く(script は prefix + 番号。合計が 4,096 バイト以上になる数で使う)
# 引数: count script_prefix [map_version_prefix]
write_valid_rows() {
	local count="$1" prefix="$2" version="${3:-}" index
	{
		printf '%s\n' "$HEADER_9"
		for ((index = 1; index <= count; index++)); do
			if [ -n "$version" ]; then
				printf 'J%d,,,/w,%s%d,"[""a""]",60,,%s%d\n' "$index" "$prefix" "$index" "$version" "$index"
			else
				printf 'J%d,,,/w,%s%d,"[""a""]",60,,v1\n' "$index" "$prefix" "$index"
			fi
		done
	} >"$MAP"
}

# bats test_tags=heavy
@test "validate_job_map_query_verboseで制御文字を含む有効な行が多数あり可視表記を作るsedが失敗する場合_internal command failedの1行だけで6を返しstdoutを出さないこと" {
	# Arrange(info 行の合計が 4,096 バイト以上)
	write_valid_rows 40 "/s$CONTROLS"
	sed_failing_on_escape
	local status=0

	# Act
	validate_job_map_query "$MAP" true >"$STDOUT_FILE" 2>"$STDERR_FILE" || status=$?

	# Assert(info 行も sed 自身の stderr も出さない)
	[ "$status" -eq 6 ]
	[ ! -s "$STDOUT_FILE" ]
	[ "$(cat "$STDERR_FILE")" = "error: internal command failed commands=sed path: $MAP" ]
}

# bats test_tags=heavy
@test "validate_job_map_query_verboseでC1制御文字を含む有効な行が多数あり改行を消すtrが失敗する場合_internal command failedの1行だけで6を返すこと" {
	# Arrange(0xC2 を含む値は sed 2 回と tr 1 回で置き換える)
	write_valid_rows 40 $'/s\xc2\x85\xc2\x9b'
	tr_failing_on_delete
	local status=0

	# Act
	validate_job_map_query "$MAP" true >"$STDOUT_FILE" 2>"$STDERR_FILE" || status=$?

	# Assert
	[ "$status" -eq 6 ]
	[ ! -s "$STDOUT_FILE" ]
	[ "$(cat "$STDERR_FILE")" = "error: internal command failed commands=tr path: $MAP" ]
}

# bats test_tags=heavy
@test "validate_job_map_query_制御文字を含むjob_idの違反が多数あり可視表記を作るsedが失敗する場合_error行を出さずinternal command failedの1行だけで6を返すこと" {
	# Arrange
	local index
	{
		printf '%s\n' "$HEADER_9"
		for ((index = 1; index <= 80; index++)); do
			printf 'J%s%d,,,/w,/s,[],60,,v1\n' "$CONTROLS" "$index"
		done
	} >"$MAP"
	sed_failing_on_escape
	local status=0

	# Act
	validate_job_map_query "$MAP" false >"$STDOUT_FILE" 2>"$STDERR_FILE" || status=$?

	# Assert
	[ "$status" -eq 6 ]
	[ ! -s "$STDOUT_FILE" ]
	[ "$(cat "$STDERR_FILE")" = "error: internal command failed commands=sed path: $MAP" ]
}

@test "validate_job_map_query_制御文字を含む版が行ごとに違い可視表記を作るsedが失敗する場合_warnもstdoutも出さずinternal command failedの1行だけで6を返すこと" {
	# Arrange(検証 OK なら stdout の map_version に全行の版を連ねて出す。版の合計が 4,096 バイト以上)
	write_valid_rows 40 /s "v$CONTROLS$CONTROLS$CONTROLS$CONTROLS"
	sed_failing_on_escape
	local status=0

	# Act
	validate_job_map_query "$MAP" false >"$STDOUT_FILE" 2>"$STDERR_FILE" || status=$?

	# Assert
	[ "$status" -eq 6 ]
	[ ! -s "$STDOUT_FILE" ]
	[ "$(cat "$STDERR_FILE")" = "error: internal command failed commands=sed path: $MAP" ]
}

# bats test_tags=heavy
@test "validate_job_map_query_verboseで制御文字を含む有効な行が多数ある場合_info行を値ごとの可視表記と同じバイト列で出すこと" {
	# Arrange(sed でまとめて置き換える大きさ。期待値は参照実装で値ごとに作る)
	local index script expected=""
	write_valid_rows 40 $'/s\t'"$CONTROLS"$'\xc2\x85\xe3\x81\x82\xc2\xa0'
	for ((index = 1; index <= 40; index++)); do
		reference_escape $'/s\t'"$CONTROLS"$'\xc2\x85\xe3\x81\x82\xc2\xa0'"$index"
		script="$REFERENCE_ESCAPED"
		expected+="info: resolved job_id=J$index host=- user=- exec=local work_dir=/w script=$script fixed_params=[\"a\"] hang_detect_limit_minutes=60"$'\n'
	done
	local status=0

	# Act
	validate_job_map_query "$MAP" true >"$STDOUT_FILE" 2>"$STDERR_FILE" || status=$?

	# Assert
	[ "$status" -eq 0 ]
	[ "$(cat "$STDERR_FILE")"$'\n' = "$expected" ]
	[ "$(sed -n 2,3p "$STDOUT_FILE")" = $'rows=40\nmap_version=v1' ]
}

# bats test_tags=heavy
@test "validate_job_map_query_制御文字を含む版が行ごとに違う場合_warnとstdoutのmap_versionを値ごとの可視表記と同じバイト列で出すこと" {
	# Arrange
	local index joined=""
	write_valid_rows 40 /s "v$CONTROLS$CONTROLS$CONTROLS$CONTROLS"
	for ((index = 1; index <= 40; index++)); do
		joined+="${joined:+,}v$CONTROLS$CONTROLS$CONTROLS$CONTROLS$index"
	done
	reference_escape "$joined"
	local status=0

	# Act
	validate_job_map_query "$MAP" false >"$STDOUT_FILE" 2>"$STDERR_FILE" || status=$?

	# Assert(値に空白類(タブ)を含むため `map_version: <値>`)
	[ "$status" -eq 0 ]
	[ "$(cat "$STDERR_FILE")" = "warn: mixed map_version values=$REFERENCE_ESCAPED" ]
	[ "$(sed -n 3p "$STDOUT_FILE")" = "map_version: $REFERENCE_ESCAPED" ]
}

@test "validate_job_map_query_制御文字を含む未知の列名が多数ありヘッダー不一致で止まり可視表記を作るsedが失敗する場合_warnを出さずinternal command failedの1行だけで6を返すこと" {
	# Arrange(必須列 work_dir が無い。未知の列名の warn 行の合計が 4,096 バイト以上)
	local header="job_id,script,fixed_params,hang_detect_limit_minutes" index
	for ((index = 1; index <= 40; index++)); do
		header+=",x$CONTROLS$index"
	done
	printf '%s\n%s\n' "$header" 'J1,/s,[],60' >"$MAP"
	sed_failing_on_escape
	local status=0

	# Act
	validate_job_map_query "$MAP" false >"$STDOUT_FILE" 2>"$STDERR_FILE" || status=$?

	# Assert
	[ "$status" -eq 6 ]
	[ ! -s "$STDOUT_FILE" ]
	[ "$(cat "$STDERR_FILE")" = "error: internal command failed commands=sed path: $MAP" ]
}

# bats test_tags=heavy
@test "validate_job_map_query_制御文字を含む未知の列名が多数ありヘッダー不一致で止まる場合_warnとerrorを値ごとの可視表記と同じバイト列で出すこと" {
	# Arrange
	local header="job_id,script,fixed_params,hang_detect_limit_minutes" expected="" index
	for ((index = 1; index <= 40; index++)); do
		header+=",x$CONTROLS$index"
		reference_escape "x$CONTROLS$index"
		expected+="warn: unknown column column=$REFERENCE_ESCAPED path: $MAP"$'\n'
	done
	expected+="error: job map header mismatch missing=work_dir path: $MAP"$'\n'
	printf '%s\n%s\n' "$header" 'J1,/s,[],60' >"$MAP"
	local status=0

	# Act
	validate_job_map_query "$MAP" false >"$STDOUT_FILE" 2>"$STDERR_FILE" || status=$?

	# Assert
	[ "$status" -eq 2 ]
	[ ! -s "$STDOUT_FILE" ]
	[ "$(cat "$STDERR_FILE")"$'\n' = "$expected" ]
}
