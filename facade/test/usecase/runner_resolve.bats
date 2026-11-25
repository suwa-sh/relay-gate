#!/usr/bin/env bats
# UC 7c41c7cd(ジョブマップで JOB_ID から実行先を解決する)× tier-facade: 共通ライブラリ lib/runner-resolve.sh
# (本体 usecase/runner_resolve.sh)の単体テスト。自作の runner と同じく、ライブラリを source して関数を直接呼ぶ。
# 対象: spec.md「処理フロー」「分岐条件一覧」「計算ルール一覧」と tier-facade.md「出力契約」「UC ロジック」。
# I/O 境界は実体(BATS_TEST_TMPDIR の実ファイル)で確かめる。管理 DB は使わない。
# 時間を確かめるテスト、大きな入力を作るテストは書かない。

bats_require_minimum_version 1.5.0

SCRIPT_NAME="standard-runner.sh"
RUN_ID="20260830T113000-JOB001-3f9a1c2e"
HEADER_7="job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes"
HEADER_9="$HEADER_7,credential_ref,map_version"
ROW_JOB001_7="JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60"

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../lib/runner-resolve.sh"
	export RELAY_GATE_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	export RELAY_GATE_ARTIFACT_ROOT="$BATS_TEST_TMPDIR/artifacts"
	export RELAY_GATE_LOG_DIR="$BATS_TEST_TMPDIR/logs"
	unset BLUE_JOB_MAP_CSV GREEN_JOB_MAP_CSV RELAY_GATE_NOW
	GREEN_MAP="$RELAY_GATE_CONFIG_DIR/green-job-map.csv"
	BLUE_MAP="$RELAY_GATE_CONFIG_DIR/blue-job-map.csv"
	ROLE_DIR="$RELAY_GATE_ARTIFACT_ROOT/facade/$RUN_ID/green"
	RUNNER_LOG="$RELAY_GATE_LOG_DIR/$SCRIPT_NAME.log"
	mkdir -p "$RELAY_GATE_CONFIG_DIR"
	resolve_status=0
}

write_map() {
	local file="$1"
	shift
	mkdir -p "$(dirname "$file")"
	printf '%s\n' "$@" >"$file"
}

# green の解決を同じシェルで呼ぶ(結果のグローバルを読むため run を使わない)
resolve_green() {
	resolve_status=0
	resolve_execution_target "$SCRIPT_NAME" "$RUN_ID" "$@" || resolve_status=$?
}

assert_failure_files() {
	local code="$1" line="$2"
	[ "$resolve_status" -eq "$code" ]
	[ -f "$ROLE_DIR/started-at.txt" ]
	[ -f "$ROLE_DIR/stdout.log" ]
	[ ! -s "$ROLE_DIR/stdout.log" ]
	[ "$(sed -n 1p "$ROLE_DIR/stderr.log")" = "$line" ] || {
		echo "stderr.log: $(cat "$ROLE_DIR/stderr.log")"
		return 1
	}
	[ "$(cat "$ROLE_DIR/exitcode.txt")" = "$code" ]
	[ -z "$(find "$ROLE_DIR" -name '*.tmp')" ]
}

# ---- 解決成功 ----

@test "resolve_execution_target_9列のジョブマップにJOB_IDの行がある場合_全項目と引数列を載せて0であること" {
	# Arrange(列はヘッダー名で対応付ける。fixed_params セルは二重引用符で囲み "" を二重化する)
	write_map "$GREEN_MAP" "$HEADER_9" 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[""--mode"",""full""]",60,ssh-key-green,map-v3'

	# Act
	resolve_green JOB001 green 20260830

	# Assert
	[ "$resolve_status" -eq 0 ]
	[ "$RUNNER_RESOLVE_MAP_PATH" = "$GREEN_MAP" ]
	[ "$EXECUTION_TARGET_HOST" = "host-green-01" ]
	[ "$EXECUTION_TARGET_USER" = "batch" ]
	[ "$EXECUTION_TARGET_SCRIPT" = "/opt/app/bin/job001.sh" ]
	[ "$EXECUTION_TARGET_WORK_DIR" = "/var/app/work" ]
	[ "$EXECUTION_TARGET_HANG_DETECT_LIMIT_MINUTES" = "60" ]
	[ "$EXECUTION_TARGET_CREDENTIAL_REF" = "ssh-key-green" ]
	[ "$EXECUTION_TARGET_MAP_VERSION" = "map-v3" ]
	[ "$EXECUTION_TARGET_EXEC" = "ssh" ]
	[ "${#ARGUMENT_LIST[@]}" -eq 3 ]
	[ "${ARGUMENT_LIST[0]}" = "--mode" ]
	[ "${ARGUMENT_LIST[1]}" = "full" ]
	[ "${ARGUMENT_LIST[2]}" = "20260830" ]
	grep -qE "^standard-runner\.sh $RUN_ID [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} INFO job map resolved job_id=JOB001 slot=green host=host-green-01 map_version=map-v3\$" "$RUNNER_LOG"
}

@test "resolve_execution_target_解決に成功した場合_成果物ディレクトリに何も書かずプロセスのstdoutとstderrに出さないこと" {
	# Arrange
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7"

	# Act
	run --separate-stderr resolve_execution_target "$SCRIPT_NAME" "$RUN_ID" JOB001 green

	# Assert(解決フェーズは副作用を持たない。ファイル書き込みは失敗時のみ)
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ ! -e "$RELAY_GATE_ARTIFACT_ROOT" ]
}

@test "resolve_execution_target_列の順が違うジョブマップの場合_ヘッダー名で列位置を決めること" {
	# Arrange
	write_map "$GREEN_MAP" "hang_detect_limit_minutes,script,job_id,fixed_params,work_dir" "15,/opt/app/bin/job001.sh,JOB001,[],/var/app/work"

	# Act
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 0 ]
	[ "$EXECUTION_TARGET_SCRIPT" = "/opt/app/bin/job001.sh" ]
	[ "$EXECUTION_TARGET_WORK_DIR" = "/var/app/work" ]
	[ "$EXECUTION_TARGET_HANG_DETECT_LIMIT_MINUTES" = "15" ]
}

@test "resolve_execution_target_hostとuserの列が無いblueのジョブマップの場合_ローカル実行として解決し実行ログのhostとmap_versionが-であること" {
	# Arrange
	write_map "$BLUE_MAP" "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" "JOB001,/var/app/work,/opt/app/bin/job001.sh,[],0"

	# Act
	resolve_green JOB001 blue

	# Assert
	[ "$resolve_status" -eq 0 ]
	[ "$EXECUTION_TARGET_EXEC" = "local" ]
	[ -z "$EXECUTION_TARGET_HOST" ]
	[ -z "$EXECUTION_TARGET_USER" ]
	[ -z "$EXECUTION_TARGET_CREDENTIAL_REF" ]
	[ -z "$EXECUTION_TARGET_MAP_VERSION" ]
	[ "${#ARGUMENT_LIST[@]}" -eq 0 ]
	grep -qE " INFO job map resolved job_id=JOB001 slot=blue host=- map_version=-\$" "$RUNNER_LOG"
}

@test "resolve_execution_target_コメント行と空行がある場合_読み飛ばしてJOB_IDの完全一致の行を解決すること" {
	# Arrange(JOB0011 と JOB00 は JOB001 と一致しない)
	write_map "$GREEN_MAP" "# memo" "$HEADER_7" "" "JOB0011,h1,u1,/w1,/s1.sh,[],1" "JOB00,h2,u2,/w2,/s2.sh,[],2" "# JOB001,hx,ux,/wx,/sx.sh,[],9" "$ROW_JOB001_7"

	# Act
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 0 ]
	[ "$EXECUTION_TARGET_HOST" = "host-green-01" ]
}

@test "resolve_execution_target_未知の列がある場合_解決に成功し実行ログにWARNを出すこと" {
	# Arrange
	write_map "$GREEN_MAP" "$HEADER_7,impl_version" "$ROW_JOB001_7,v9"

	# Act
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 0 ]
	grep -qE " WARN unknown column column=impl_version path: $GREEN_MAP\$" "$RUNNER_LOG"
}

@test "resolve_execution_target_同じJOB_IDの行が複数ある場合_先頭の行を採用し全行の行番号を実行ログにWARNで出すこと" {
	# Arrange(2 行目と 4 行目が JOB001)
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7" "JOB002,h2,u2,/w2,/s2.sh,[],2" "JOB001,host-second,u3,/w3,/s3.sh,[],3"

	# Act
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 0 ]
	[ "$EXECUTION_TARGET_HOST" = "host-green-01" ]
	grep -qE " WARN duplicate job_id in job map job_id=JOB001 lines=2,4\$" "$RUNNER_LOG"
}

# ---- ジョブマップの場所 ----

@test "resolve_execution_target_環境変数GREEN_JOB_MAP_CSVがある場合_その場所のジョブマップで解決し既定の場所を使わないこと" {
	# Arrange
	local maps="$BATS_TEST_TMPDIR/maps"
	write_map "$GREEN_MAP" "$HEADER_7" "JOB001,host-default-99,other,/var/default,/opt/default/job001.sh,[],60"
	write_map "$maps/green-jobs.csv" "$HEADER_7" "$ROW_JOB001_7"
	export GREEN_JOB_MAP_CSV="$maps/green-jobs.csv"

	# Act
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 0 ]
	[ "$RUNNER_RESOLVE_MAP_PATH" = "$maps/green-jobs.csv" ]
	[ "$EXECUTION_TARGET_HOST" = "host-green-01" ]
}

@test "resolve_execution_target_環境変数GREEN_JOB_MAP_CSVが空の場合_既定の場所のジョブマップで解決すること" {
	# Arrange
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7"
	export GREEN_JOB_MAP_CSV=""

	# Act
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 0 ]
	[ "$RUNNER_RESOLVE_MAP_PATH" = "$GREEN_MAP" ]
}

@test "resolve_execution_target_roleがgreenで環境変数BLUE_JOB_MAP_CSVだけがある場合_相手slotの変数を使わないこと" {
	# Arrange
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7"
	export BLUE_JOB_MAP_CSV="$BATS_TEST_TMPDIR/maps/blue-jobs.csv"

	# Act
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 0 ]
	[ "$RUNNER_RESOLVE_MAP_PATH" = "$GREEN_MAP" ]
}

@test "resolve_execution_target_環境変数の値が相対パスの場合_解決も正規化もせずそのままmap=に出すこと" {
	# Arrange(相対パスの先にファイルは無い)
	export GREEN_JOB_MAP_CSV="./maps/../missing.csv"

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: job map not found slot=green map=./maps/../missing.csv"
}

# ---- 解決失敗(exitcode.txt=2) ----

@test "resolve_execution_target_JOB_IDの行が無い場合_実行ログにERRORを1回だけ出し同じ文をstderr_logに書いて2であること" {
	# Arrange
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7"
	ROLE_DIR="$RELAY_GATE_ARTIFACT_ROOT/facade/$RUN_ID/green"

	# Act
	resolve_green JOB999 green

	# Assert
	assert_failure_files 2 "error: job_id=JOB999 not found in job map slot=green map=$GREEN_MAP"
	[ "$(wc -l <"$ROLE_DIR/stderr.log" | tr -d ' ')" = "1" ]
	grep -qE " ERROR job_id=JOB999 not found in job map slot=green map=$GREEN_MAP\$" "$RUNNER_LOG"
	[ "$(grep -c ' ERROR ' "$RUNNER_LOG")" = "1" ]
	grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$ROLE_DIR/started-at.txt"
}

@test "resolve_execution_target_解決に失敗した場合_プロセスのstdoutとstderrに出さないこと" {
	# Arrange
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7"

	# Act
	run --separate-stderr resolve_execution_target "$SCRIPT_NAME" "$RUN_ID" JOB999 green

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
}

@test "resolve_execution_target_ジョブマップがディレクトリの場合_config file is not readableで2であること" {
	# Arrange(存在するが通常ファイルとして読めない。ui-design.md の定型文「読めないとき」。検証コマンドと同じ判定)
	mkdir -p "$GREEN_MAP"

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: config file is not readable path: $GREEN_MAP"
	grep -qE " ERROR config file is not readable path: $GREEN_MAP\$" "$RUNNER_LOG"
}

@test "resolve_execution_target_ジョブマップに読み取り権限が無い場合_config file is not readableで2であること" {
	# Arrange(権限を無視して読める利用者(root)では成り立たないため、その環境では確かめない)
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7"
	chmod 000 "$GREEN_MAP"
	if [ -r "$GREEN_MAP" ]; then
		skip "the test user can read a file without the read permission"
	fi

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: config file is not readable path: $GREEN_MAP"
}

@test "resolve_execution_target_host列だけがあるヘッダーの場合_header mismatchで2であること" {
	# Arrange
	write_map "$GREEN_MAP" "job_id,host,work_dir,script,fixed_params,hang_detect_limit_minutes" "JOB001,h1,/w,/s.sh,[],60"

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: job map header mismatch missing=user path: $GREEN_MAP"
}

@test "resolve_execution_target_空のジョブマップの場合_必須列すべてのheader mismatchで2であること" {
	# Arrange
	: >"$GREEN_MAP"

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: job map header mismatch missing=job_id,work_dir,script,fixed_params,hang_detect_limit_minutes path: $GREEN_MAP"
}

@test "resolve_execution_target_列名が重複するヘッダーの場合_duplicate columnの1行だけで2であること" {
	# Arrange
	write_map "$GREEN_MAP" "$HEADER_7,script" "$ROW_JOB001_7,/other.sh"

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: duplicate column column=script path: $GREEN_MAP"
	[ "$(wc -l <"$ROLE_DIR/stderr.log" | tr -d ' ')" = "1" ]
}

@test "resolve_execution_target_重複した列名が2つあるヘッダーの場合_列名ごとに1行をstderr_logに書き実行ログのERRORは1回であること" {
	# Arrange(host と user が 2 回ずつ。契約 config_input_rules.rules「ヘッダー列名の重複」: 重複した列名ごとに 1 行)
	write_map "$GREEN_MAP" "$HEADER_7,host,user" "$ROW_JOB001_7,h2,u2"

	# Act
	resolve_green JOB001 green

	# Assert(検証コマンドと同じ順・同じ件数)
	assert_failure_files 2 "error: duplicate column column=host path: $GREEN_MAP"
	[ "$(sed -n 2p "$ROLE_DIR/stderr.log")" = "error: duplicate column column=user path: $GREEN_MAP" ]
	[ "$(wc -l <"$ROLE_DIR/stderr.log" | tr -d ' ')" = "2" ]
	[ "$(grep -c ' ERROR ' "$RUNNER_LOG")" = "1" ]
	grep -qE " ERROR duplicate column column=host path: $GREEN_MAP\$" "$RUNNER_LOG"
}

@test "resolve_execution_target_列名の重複と必須列の欠落が両方あるヘッダーの場合_検証コマンドと同じ順で全件をstderr_logに書くこと" {
	# Arrange(script が 2 回、work_dir が無い)
	write_map "$GREEN_MAP" "job_id,script,script,fixed_params,hang_detect_limit_minutes" "JOB001,/s.sh,/t.sh,[],60"

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: duplicate column column=script path: $GREEN_MAP"
	[ "$(sed -n 2p "$ROLE_DIR/stderr.log")" = "error: job map header mismatch missing=work_dir path: $GREEN_MAP" ]
	[ "$(wc -l <"$ROLE_DIR/stderr.log" | tr -d ' ')" = "2" ]
	[ "$(grep -c ' ERROR ' "$RUNNER_LOG")" = "1" ]
}

@test "resolve_execution_target_閉じていない二重引用符の行がある場合_csv quote is invalidで2であること" {
	# Arrange(2 行目の fixed_params セルが閉じていない)
	write_map "$GREEN_MAP" "$HEADER_7" 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[""p1"",60'

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: csv quote is invalid line=2 path: $GREEN_MAP"
}

@test "resolve_execution_target_採用した行の列数がヘッダーと違う場合_column count mismatchで2であること" {
	# Arrange
	write_map "$GREEN_MAP" "$HEADER_7" "JOB001,host-green-01,batch,/var/app/work"

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: column count mismatch line=2 expected=7 actual=4"
}

@test "resolve_execution_target_ほかのJOB_IDの行の値が不正な場合_値は自分の行だけを検査して解決すること" {
	# Arrange(JOB002 の行は列数は合っているが、fixed_params も上限も不正)
	write_map "$GREEN_MAP" "$HEADER_7" "JOB002,h2,,/w2,,p1,abc" "$ROW_JOB001_7"

	# Act
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 0 ]
	[ "$EXECUTION_TARGET_HOST" = "host-green-01" ]
}

@test "resolve_execution_target_ほかのJOB_IDの行の列数がヘッダーと違う場合_column count mismatchで2であること" {
	# Arrange(JOB001 の行は正しい。3 行目の JOB003 の行が 2 列。列数はファイルの構造で、どの行でも拒否する)
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7" "JOB003,h3"

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: column count mismatch line=3 expected=7 actual=2"
	[ "$(wc -l <"$ROLE_DIR/stderr.log" | tr -d ' ')" = "1" ]
	! grep -q ' INFO job map resolved ' "$RUNNER_LOG"
}

@test "resolve_execution_target_空白だけの行がある場合_1セルの行としてcolumn count mismatchで2であること" {
	# Arrange(3 行目は半角空白とタブだけ。契約 config_input_rules.rules「空白だけの行」)
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7" $' \t'

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: column count mismatch line=3 expected=7 actual=1"
}

@test "resolve_execution_target_列数の違う行とクォート不正の行が両方ある場合_行番号が先の1件だけを報告すること" {
	# Arrange(2 行目が列数不一致、3 行目がクォート不正)
	write_map "$GREEN_MAP" "$HEADER_7" "JOB003,h3" 'JOB004,"x' "$ROW_JOB001_7"

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: column count mismatch line=2 expected=7 actual=2"
	[ "$(wc -l <"$ROLE_DIR/stderr.log" | tr -d ' ')" = "1" ]
}

# ---- credential_ref の警告 ----

@test "resolve_execution_target_採用した行のcredential_refがパスらしい値の場合_解決に成功し値を出さないWARNを実行ログに出すこと" {
	# Arrange(契約 columns.credential_ref.on_format_violation / output_rule)
	write_map "$GREEN_MAP" "$HEADER_9" "$ROW_JOB001_7,/etc/keys/green.pem,map-v3"

	# Act
	resolve_green JOB001 green

	# Assert(受理して転記の値はそのまま。警告は位置だけ)
	[ "$resolve_status" -eq 0 ]
	[ "$EXECUTION_TARGET_CREDENTIAL_REF" = "/etc/keys/green.pem" ]
	grep -qE " WARN credential_ref looks like a secret or path line=2 job_id=JOB001\$" "$RUNNER_LOG"
	! grep -q 'green.pem' "$RUNNER_LOG"
	[ ! -e "$RELAY_GATE_ARTIFACT_ROOT" ]
}

@test "resolve_execution_target_ほかのJOB_IDの行のcredential_refがパスらしい値の場合_WARNを出さないこと" {
	# Arrange
	write_map "$GREEN_MAP" "$HEADER_9" "JOB002,h2,u2,/w2,/s2.sh,[],2,/etc/keys/other.pem,map-v3" "$ROW_JOB001_7,ssh-key-green,map-v3"

	# Act
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 0 ]
	! grep -q 'credential_ref looks like' "$RUNNER_LOG"
}

@test "resolve_execution_target_採用した行のcredential_refがパスらしく行の値も不正な場合_WARNを出しstderr_logには値の違反だけを書くこと" {
	# Arrange(上限が数値でない)
	write_map "$GREEN_MAP" "$HEADER_9" "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],abc,-----BEGIN KEY-----,map-v3"

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=abc"
	[ "$(wc -l <"$ROLE_DIR/stderr.log" | tr -d ' ')" = "1" ]
	grep -qE " WARN credential_ref looks like a secret or path line=2 job_id=JOB001\$" "$RUNNER_LOG"
	! grep -q 'BEGIN' "$RUNNER_LOG"
	! grep -q 'BEGIN' "$ROLE_DIR/stderr.log"
}

@test "resolve_execution_target_userだけが空の行の場合_user is emptyで2であること" {
	# Arrange
	write_map "$GREEN_MAP" "$HEADER_7" "JOB004,host-green-01,,/var/app/work,/opt/app/bin/job004.sh,[],60"

	# Act
	resolve_green JOB004 green

	# Assert
	assert_failure_files 2 "error: user is empty line=2 job_id=JOB004 value="
	grep -qE " ERROR user is empty line=2 job_id=JOB004 value=\$" "$RUNNER_LOG"
}

@test "resolve_execution_target_fixed_paramsがJSON配列でない行の場合_固定引数不正で2であること" {
	# Arrange
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7" "JOB003,host-green-01,batch,/var/app/work,/opt/app/bin/job003.sh,p1 p2,60"

	# Act
	resolve_green JOB003 green

	# Assert
	assert_failure_files 2 "error: fixed_params is not a json array of strings line=3 job_id=JOB003 value=p1 p2"
}

@test "resolve_execution_target_CRLF改行のジョブマップの場合_バイト点検の違反を全件とhintをstderr_logに書いて2であること" {
	# Arrange
	printf '%s\r\n' "$HEADER_7" "$ROW_JOB001_7" >"$GREEN_MAP"

	# Act
	resolve_green JOB001 green

	# Assert(検証コマンドと同じ順・同じ件数。実行ログの ERROR は 1 回だけ)
	assert_failure_files 2 "error: carriage return is not allowed line=1 path: $GREEN_MAP"
	[ "$(sed -n 2p "$ROLE_DIR/stderr.log")" = "error: carriage return is not allowed line=2 path: $GREEN_MAP" ]
	[ "$(sed -n 3p "$ROLE_DIR/stderr.log")" = "hint: use LF line endings" ]
	[ "$(wc -l <"$ROLE_DIR/stderr.log" | tr -d ' ')" = "3" ]
	[ "$(grep -c ' ERROR ' "$RUNNER_LOG")" = "1" ]
}

@test "resolve_execution_target_パスに制御文字がある場合_stderr_logと実行ログに可視表記で出すこと" {
	# Arrange(ESC を含む場所。ファイルは無い)
	export GREEN_JOB_MAP_CSV="$BATS_TEST_TMPDIR/"$'a\033b.csv'

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: job map not found slot=green map=$BATS_TEST_TMPDIR/a\\u001bb.csv"
	! grep -q $'\033' "$RUNNER_LOG"
}

# ---- テスト用の現在時刻 ----

@test "resolve_execution_target_RELAY_GATE_NOWがある場合_started-at_txtにその値を書き実行ログにWARNを残すこと" {
	# Arrange
	export RELAY_GATE_NOW="2026-08-30T11:30:05Z"

	# Act(ジョブマップは置かない)
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 2 ]
	[ "$(cat "$ROLE_DIR/started-at.txt")" = "2026-08-30T11:30:05Z" ]
	grep -qE " WARN test clock injected now=2026-08-30T11:30:05Z\$" "$RUNNER_LOG"
}

@test "resolve_execution_target_RELAY_GATE_NOWの形式が不正な場合_invalid valueで2であること" {
	# Arrange
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7"
	export RELAY_GATE_NOW="2026-08-30 11:30:05"

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: invalid value env=RELAY_GATE_NOW value=2026-08-30 11:30:05"
}

# ---- 二重起動・書き込み失敗・内部障害 ----

@test "resolve_execution_target_解決に成功した場合_RUNNER_RESOLVE_EXIT_CODEが空であること" {
	# Arrange
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7"

	# Act
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 0 ]
	[ -z "$RUNNER_RESOLVE_EXIT_CODE" ]
}

@test "resolve_execution_target_解決に失敗した場合_RUNNER_RESOLVE_EXIT_CODEが戻り値と同じ2であること" {
	# Act(ジョブマップは置かない)
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 2 ]
	[ "$RUNNER_RESOLVE_EXIT_CODE" = "2" ]
}

@test "resolve_execution_target_既存のexitcode_txtが非0の場合_上書きせずその値を戻り値とRUNNER_RESOLVE_EXIT_CODEに返すこと" {
	# Arrange
	mkdir -p "$ROLE_DIR"
	printf '3\n' >"$ROLE_DIR/exitcode.txt"

	# Act(ジョブマップは置かない = 解決失敗)
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 3 ]
	[ "$RUNNER_RESOLVE_EXIT_CODE" = "3" ]
	[ "$(cat "$ROLE_DIR/exitcode.txt")" = "3" ]
}

@test "resolve_execution_target_既存のexitcode_txtが0の場合_上書きせず実行ログにWARNを残し解決成功と区別できる非0を返して終了コードは0であること" {
	# Arrange(この run の成果物が既にある)
	mkdir -p "$ROLE_DIR"
	printf '0\n' >"$ROLE_DIR/exitcode.txt"
	printf 'previous\n' >"$ROLE_DIR/stderr.log"

	# Act(ジョブマップは置かない = 解決失敗)
	resolve_green JOB001 green

	# Assert(戻り値 0 は解決成功だけ。runner が終える値は既存の exitcode.txt の 0)
	[ "$resolve_status" -ne 0 ]
	[ "$RUNNER_RESOLVE_EXIT_CODE" = "0" ]
	[ -z "$EXECUTION_TARGET_SCRIPT" ]
	[ "$(cat "$ROLE_DIR/exitcode.txt")" = "0" ]
	[ "$(cat "$ROLE_DIR/stderr.log")" = "previous" ]
	[ ! -e "$ROLE_DIR/started-at.txt" ]
	grep -qE " WARN runner result already published run_id=$RUN_ID role=green\$" "$RUNNER_LOG"
}

@test "resolve_execution_target_started-at_txtだけがある場合_上書きして4ファイルを揃えること" {
	# Arrange
	mkdir -p "$ROLE_DIR"
	printf 'old\n' >"$ROLE_DIR/started-at.txt"

	# Act
	resolve_green JOB001 green

	# Assert
	assert_failure_files 2 "error: job map not found slot=green map=$GREEN_MAP"
	[ "$(cat "$ROLE_DIR/started-at.txt")" != "old" ]
}

@test "resolve_execution_target_成果物ディレクトリに書けない場合_実行ログにERRORを残して6でexitcode_txtが無いこと" {
	# Arrange(成果物ルートの位置に通常ファイルがある)
	printf 'x\n' >"$RELAY_GATE_ARTIFACT_ROOT"

	# Act
	run --separate-stderr resolve_execution_target "$SCRIPT_NAME" "$RUN_ID" JOB001 green

	# Assert
	[ "$status" -eq 6 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	grep -qE " ERROR runner result write failed run_id=$RUN_ID role=green path: $ROLE_DIR\$" "$RUNNER_LOG"
}

@test "resolve_execution_target_実行ログの置き場に書けない場合_何も出力せず解決を続けること" {
	# Arrange(実行ログの置き場の位置に通常ファイルがある)
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7"
	printf 'x\n' >"$RELAY_GATE_LOG_DIR"

	# Act
	run --separate-stderr resolve_execution_target "$SCRIPT_NAME" "$RUN_ID" JOB001 green

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
}

@test "resolve_execution_target_補助コマンドが失敗する場合_internal command failedをstderr_logに書いて6であること" {
	# Arrange(PATH の先頭に失敗する sed を置く。契約 config_input_rules.internal_failure)
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7"
	local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
	mkdir -p "$fake_bin"
	printf '%s\n' '#!/bin/sh' 'exit 1' >"$fake_bin/sed"
	chmod +x "$fake_bin/sed"
	local saved_path="$PATH"

	# Act
	PATH="$fake_bin:$PATH"
	resolve_green JOB001 green
	PATH="$saved_path"

	# Assert
	assert_failure_files 6 "error: internal command failed commands=sed path: $GREEN_MAP"
}

@test "resolve_execution_target_入力の複製を作れない場合_config snapshot failedとhintをstderr_logに書いて6であること" {
	# Arrange(TMPDIR が存在しない)
	write_map "$GREEN_MAP" "$HEADER_7" "$ROW_JOB001_7"
	local saved_tmpdir="${TMPDIR:-}"

	# Act
	TMPDIR="$BATS_TEST_TMPDIR/no-such-dir"
	resolve_green JOB001 green
	TMPDIR="$saved_tmpdir"

	# Assert
	assert_failure_files 6 "error: config snapshot failed path: $GREEN_MAP"
	[ "$(sed -n 2p "$ROLE_DIR/stderr.log")" = "hint: check TMPDIR is writable" ]
}

@test "resolve_execution_target_roleがblueでもgreenでもない場合_実行ログにだけ残して2であること" {
	# Act
	resolve_green JOB001 red

	# Assert
	[ "$resolve_status" -eq 2 ]
	grep -qE " ERROR invalid value option=--role value=red\$" "$RUNNER_LOG"
	[ ! -e "$RELAY_GATE_ARTIFACT_ROOT" ]
}

@test "resolve_execution_target_検証コマンドの報告行の出力先を変えていた場合_呼び出しの後に元へ戻すこと" {
	# Arrange
	write_map "$GREEN_MAP" "$HEADER_7,impl_version" "$ROW_JOB001_7,v9"
	JOB_MAP_REPORT_SINK=""
	JOB_MAP_REPORT_DEFER_ESCAPE=true

	# Act
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 0 ]
	[ -z "$JOB_MAP_REPORT_SINK" ]
	[ "$JOB_MAP_REPORT_DEFER_ESCAPE" = true ]
	[ "${#JOB_MAP_REPORT_LINES[@]}" -eq 0 ]
}

# ---- runner IF の引数の違反の報告 ----

@test "runner_resolve_reject_invocation_run_idとroleが分かる場合_実行ログにERRORを残しRunner Resultを揃えて2であること" {
	# Act
	resolve_status=0
	runner_resolve_reject_invocation "$SCRIPT_NAME" "$RUN_ID" green "option required option=--job-id" || resolve_status=$?

	# Assert
	assert_failure_files 2 "error: option required option=--job-id"
	grep -qE "^standard-runner\.sh $RUN_ID [0-9T:-]+ ERROR option required option=--job-id\$" "$RUNNER_LOG"
}

@test "runner_resolve_reject_invocation_run_idが分からない場合_run_id欄を-にして実行ログにだけ残すこと" {
	# Act
	resolve_status=0
	runner_resolve_reject_invocation "$SCRIPT_NAME" "" green "option required option=--run-id" || resolve_status=$?

	# Assert
	[ "$resolve_status" -eq 2 ]
	grep -qE "^standard-runner\.sh - [0-9T:-]+ ERROR option required option=--run-id\$" "$RUNNER_LOG"
	[ ! -e "$RELAY_GATE_ARTIFACT_ROOT" ]
}

@test "runner_resolve_reject_invocation_既存のexitcode_txtが0の場合_上書きせず非0を返して終了コードは0であること" {
	# Arrange
	mkdir -p "$ROLE_DIR"
	printf '0\n' >"$ROLE_DIR/exitcode.txt"

	# Act
	resolve_status=0
	runner_resolve_reject_invocation "$SCRIPT_NAME" "$RUN_ID" green "option required option=--job-id" || resolve_status=$?

	# Assert
	[ "$resolve_status" -ne 0 ]
	[ "$RUNNER_RESOLVE_EXIT_CODE" = "0" ]
	[ ! -e "$ROLE_DIR/stderr.log" ]
}

# ---- 中止済みの slot(契約 runner IF の exit_codes 6 / idempotency。attempt 3) ----

# 中止済みの slot を用意する(abort-blue / abort-green が aborted.txt を置いた後。exitcode.txt は無い)
arrange_aborted_slot() {
	mkdir -p "$ROLE_DIR"
	printf '2026-08-30T11:30:05Z\n' >"$ROLE_DIR/started-at.txt"
	printf 'partial out\n' >"$ROLE_DIR/stdout.log"
	printf 'partial err\n' >"$ROLE_DIR/stderr.log"
	printf '2026-08-30T11:40:00Z\n' >"$ROLE_DIR/aborted.txt"
}

assert_aborted_slot_untouched() {
	[ ! -e "$ROLE_DIR/exitcode.txt" ]
	[ "$(cat "$ROLE_DIR/started-at.txt")" = "2026-08-30T11:30:05Z" ]
	[ "$(cat "$ROLE_DIR/stdout.log")" = "partial out" ]
	[ "$(cat "$ROLE_DIR/stderr.log")" = "partial err" ]
	[ "$(cat "$ROLE_DIR/aborted.txt")" = "2026-08-30T11:40:00Z" ]
	[ -z "$(find "$ROLE_DIR" -name '*.tmp')" ]
}

@test "resolve_execution_target_中止済みのslotで解決に失敗した場合_成果物を変えずWARNを残してexitcode_txtを書かず6であること" {
	# Arrange(ジョブマップに JOB001 の行が無い = 解決失敗)
	write_map "$GREEN_MAP" "$HEADER_7"
	arrange_aborted_slot

	# Act
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 6 ]
	[ "$RUNNER_RESOLVE_EXIT_CODE" = "6" ]
	assert_aborted_slot_untouched
	grep -qE "^standard-runner\.sh $RUN_ID [0-9T:-]+ WARN slot already aborted run_id=$RUN_ID role=green\$" "$RUNNER_LOG"
	[ "$(grep -c ' ERROR ' "$RUNNER_LOG")" = "1" ]
	! grep -q 'already published' "$RUNNER_LOG"
}

@test "resolve_execution_target_中止済みのslotでRELAY_GATE_NOWの形式が不正な場合_成果物を変えず6であること" {
	# Arrange
	arrange_aborted_slot
	export RELAY_GATE_NOW="2026-08-30 11:30:05"

	# Act
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 6 ]
	assert_aborted_slot_untouched
	grep -qE " WARN slot already aborted run_id=$RUN_ID role=green\$" "$RUNNER_LOG"
}

@test "resolve_execution_target_aborted_txtとexitcode_txtの両方がある場合_exitcode_txtを優先して既存の値で終えること" {
	# Arrange(中止後に実装が終了して exitcode.txt を公開した slot。状態導出では exitcode.txt が優先)
	arrange_aborted_slot
	printf '143\n' >"$ROLE_DIR/exitcode.txt"

	# Act(ジョブマップは置かない = 解決失敗)
	resolve_green JOB001 green

	# Assert
	[ "$resolve_status" -eq 143 ]
	[ "$RUNNER_RESOLVE_EXIT_CODE" = "143" ]
	[ "$(cat "$ROLE_DIR/exitcode.txt")" = "143" ]
	[ "$(cat "$ROLE_DIR/stderr.log")" = "partial err" ]
	grep -qE " WARN runner result already published run_id=$RUN_ID role=green\$" "$RUNNER_LOG"
	! grep -q 'slot already aborted' "$RUNNER_LOG"
}

@test "runner_resolve_reject_invocation_中止済みのslotの場合_成果物を変えずWARNを残して6であること" {
	# Arrange
	arrange_aborted_slot

	# Act
	resolve_status=0
	runner_resolve_reject_invocation "$SCRIPT_NAME" "$RUN_ID" green "option required option=--job-id" || resolve_status=$?

	# Assert
	[ "$resolve_status" -eq 6 ]
	[ "$RUNNER_RESOLVE_EXIT_CODE" = "6" ]
	assert_aborted_slot_untouched
	grep -qE " ERROR option required option=--job-id\$" "$RUNNER_LOG"
	grep -qE " WARN slot already aborted run_id=$RUN_ID role=green\$" "$RUNNER_LOG"
}

@test "runner_resolve_guard_existing_result_成果物が無い・started-at_txtだけの場合_何も出さず0であること" {
	# Arrange
	runner_resolve_open_log "$SCRIPT_NAME" "$RUN_ID"

	# Act / Assert(role ディレクトリなし)
	runner_resolve_guard_existing_result "$RUN_ID" green

	# Act / Assert(started-at.txt だけ)
	mkdir -p "$ROLE_DIR"
	printf 'old\n' >"$ROLE_DIR/started-at.txt"
	runner_resolve_guard_existing_result "$RUN_ID" green
	[ ! -s "$RUNNER_LOG" ]
}

@test "runner_resolve_guard_existing_result_中止済みのslotの場合_WARNを残して非0でRUNNER_RESOLVE_EXIT_CODEが6であること" {
	# Arrange
	arrange_aborted_slot
	runner_resolve_open_log "$SCRIPT_NAME" "$RUN_ID"

	# Act
	resolve_status=0
	runner_resolve_guard_existing_result "$RUN_ID" green || resolve_status=$?

	# Assert
	[ "$resolve_status" -eq 6 ]
	[ "$RUNNER_RESOLVE_EXIT_CODE" = "6" ]
	assert_aborted_slot_untouched
	grep -qE " WARN slot already aborted run_id=$RUN_ID role=green\$" "$RUNNER_LOG"
}

# ---- テスト用の現在時刻(引数の違反の経路。attempt 3) ----

@test "runner_resolve_reject_invocation_RELAY_GATE_NOWがある場合_started-at_txtにその値を書き実行ログにWARNを残すこと" {
	# Arrange
	export RELAY_GATE_NOW="2026-08-30T11:30:05Z"

	# Act
	resolve_status=0
	runner_resolve_reject_invocation "$SCRIPT_NAME" "$RUN_ID" green "option required option=--job-id" || resolve_status=$?

	# Assert
	assert_failure_files 2 "error: option required option=--job-id"
	[ "$(cat "$ROLE_DIR/started-at.txt")" = "2026-08-30T11:30:05Z" ]
	[ "$(grep -c ' WARN test clock injected now=2026-08-30T11:30:05Z$' "$RUNNER_LOG")" = "1" ]
}

# ---- CSV 行分解 ----

@test "parse_csv_row_二重化された二重引用符を含むセルの場合_1文字に戻してセルに分けること" {
	# Act
	parse_csv_row 'JOB001,,,/var/app/work,/opt/app/bin/job001.sh,"[""p1"",""p2 p3"",""a,b""]",60'

	# Assert
	[ "${#CSV_CELLS[@]}" -eq 7 ]
	[ "${CSV_CELLS[5]}" = '["p1","p2 p3","a,b"]' ]
	[ -z "${CSV_CELLS[1]}" ]
	[ -z "${CSV_CELLS[2]}" ]
}

@test "parse_csv_row_閉じていない二重引用符の場合_1であること" {
	# Act
	resolve_status=0
	parse_csv_row 'JOB001,"[""p1""' || resolve_status=$?

	# Assert
	[ "$resolve_status" -eq 1 ]
}
