#!/usr/bin/env bats
# UC 09730858(slot 実行モードを選択して runner を起動する)× tier-facade: bin/facade.sh の起動・待機・管理 DB 呼び出しの単体テスト。
# 出典: tier-facade.md「コマンド契約」「出力契約」「UC ロジック」/ cli-command-contract.yaml commands の facade.sh。
# runner は BATS_TEST_TMPDIR に置く実スクリプトのスタブ。RDB クライアント(psql)は PATH の先頭に置く記録用のスタブで、
# 渡された引数と標準入力の SQL を記録し、\echo の行を出して、FAKE_PSQL_EXIT の終了コードで終わる
# (実 DB での確認は tier BDD の一時 PostgreSQL で行う)。時間の上限を確かめるテストは書かない。

bats_require_minimum_version 1.5.0

setup() {
	HOME_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	FACADE="$HOME_DIR/bin/facade.sh"
	CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	ARTIFACT_ROOT="$BATS_TEST_TMPDIR/artifacts"
	LOG_DIR="$BATS_TEST_TMPDIR/logs"
	STUB_DIR="$BATS_TEST_TMPDIR/stubs"
	FAKE_BIN="$BATS_TEST_TMPDIR/bin"
	ORDER_LOG="$BATS_TEST_TMPDIR/order.log"
	mkdir -p "$CONFIG_DIR" "$ARTIFACT_ROOT" "$LOG_DIR" "$STUB_DIR" "$FAKE_BIN"
	export ORDER_LOG
}

teardown() {
	# 長く動くスタブ(exec sleep)を残さない
	local pid_file pid
	for pid_file in "$STUB_DIR"/*.pid; do
		[ -f "$pid_file" ] || continue
		pid="$(cat "$pid_file")"
		kill "$pid" 2>/dev/null || true
	done
}

# 起動引数を <スタブ>.invoked、環境変数を <スタブ>.env に記録し、ORDER_LOG に起動の順を残して、
# Runner Result の 3 ファイル(exitcode.txt は第 2 引数。既定 0。`none` なら書かない)を書くスタブ。
# 第 3 引数が sleep なら、PID を <スタブ>.pid に書いて exec sleep 30 する(exitcode.txt は書かない)
write_runner() {
	local file="$STUB_DIR/$1" code="${2:-0}" behavior="${3:-exit}"
	{
		printf '%s\n' '#!/usr/bin/env bash'
		printf '%s\n' 'printf "%s\n" "$$" >"$0.self"'
		# 動き出した時点で psql のスタブが記録済みの slot_executions の INSERT の数(管理 DB を使わないときは 0)
		printf '%s\n' 'n="$(grep -c "INSERT INTO slot_executions" "${FAKE_PSQL_LOG:-/nonexistent}.sql" 2>/dev/null)" || true; printf "%s\n" "${n:-0}" >"$0.inserts"'
		printf '%s\n' 'printf "%s\n" "$*" >>"$0.invoked"'
		printf '%s\n' 'env >"$0.env"'
		printf '%s\n' 'printf "launch %s\n" "$(basename "$0")" >>"$ORDER_LOG"'
		printf '%s\n' 'run_id=""; role=""'
		printf '%s\n' 'while [ "$#" -gt 0 ]; do case "$1" in --run-id) run_id="$2"; shift 2 ;; --role) role="$2"; shift 2 ;; --) break ;; *) shift ;; esac; done'
		printf '%s\n' 'dir="$RELAY_GATE_ARTIFACT_ROOT/facade/$run_id/$role"'
		if [ "$behavior" = sleep ]; then
			printf '%s\n' 'printf "%s\n" "$$" >"$0.pid"'
		fi
		# 記録を書き終えた印。facade は background を待たないため、background のスタブの記録はこの印を待ってから読む
		printf '%s\n' ': >"$0.ready"'
		if [ "$behavior" = sleep ]; then
			printf '%s\n' 'exec sleep 30'
		fi
		printf '%s\n' ': >"$dir/stdout.log"; : >"$dir/stderr.log"'
		if [ "$code" != none ]; then
			printf 'echo %s >"$dir/exitcode.txt"\n' "$code"
		fi
		printf '%s\n' 'exit 0'
	} >"$file"
	chmod +x "$file"
	printf '%s\n' "$file"
}

# スタブが記録を書き終えるまで待つ(上限 10 秒)
wait_ready() {
	local i
	for ((i = 0; i < 100; i++)); do
		[ -e "$1.ready" ] && return 0
		sleep 0.1
	done
	echo "timed out waiting for $1.ready" >&2
	return 1
}

write_executable() {
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$STUB_DIR/$1"
	chmod +x "$STUB_DIR/$1"
	printf '%s\n' "$STUB_DIR/$1"
}

# 記録用の psql スタブ(引数は 1 行 1 引数で psql.args へ、SQL は psql.sql へ追記。ORDER_LOG には SQL の 1 行目を残す)
write_fake_psql() {
	{
		printf '%s\n' '#!/usr/bin/env bash'
		printf '%s\n' 'printf "%s\n" "$@" >>"$FAKE_PSQL_LOG.args"'
		printf '%s\n' 'sql="$(cat)"'
		# FAKE_PSQL_SLOT_INSERT_DELAY があれば、slot_executions の INSERT を記録する前にその秒数だけ待つ
		printf '%s\n' 'case "$sql" in *"INSERT INTO slot_executions"*) [ -z "${FAKE_PSQL_SLOT_INSERT_DELAY:-}" ] || sleep "$FAKE_PSQL_SLOT_INSERT_DELAY" ;; esac'
		printf '%s\n' 'printf "%s\n---\n" "$sql" >>"$FAKE_PSQL_LOG.sql"'
		printf '%s\n' 'printf "sql %s\n" "$(printf "%s\n" "$sql" | grep -v "^\\\\echo" | head -1)" >>"$ORDER_LOG"'
		printf '%s\n' 'printf "%s\n" "$sql" | sed -n "s/^\\\\echo //p"'
		# RETURNING のある UPDATE は、FAKE_PSQL_ROWS=0 でなければ 1 行を返す(条件に合う行が 1 件あった扱い)
		printf '%s\n' 'case "$sql" in *RETURNING*) [ "${FAKE_PSQL_ROWS:-1}" = 0 ] || echo row ;; esac'
		printf '%s\n' 'exit "${FAKE_PSQL_EXIT:-0}"'
	} >"$FAKE_BIN/psql"
	chmod +x "$FAKE_BIN/psql"
	export FAKE_PSQL_LOG="$BATS_TEST_TMPDIR/psql"
}

write_feature_flag() {
	printf '%s\n' "$@" >"$CONFIG_DIR/feature-flag.env"
}

# 実行権限はあるが exec に失敗する runner(shebang のインタープリタが存在しない)
write_unexecutable_runner() {
	printf '%s\n' '#!/nonexistent/relay-gate-interpreter' 'exit 0' >"$STUB_DIR/$1"
	chmod +x "$STUB_DIR/$1"
	printf '%s\n' "$STUB_DIR/$1"
}

# 引数をそのまま exec する setsid のスタブ(setsid の無い開発機でも、setsid を介する起動経路を通す)
write_fake_setsid() {
	printf '%s\n' '#!/usr/bin/env bash' 'exec "$@"' >"$FAKE_BIN/setsid"
	chmod +x "$FAKE_BIN/setsid"
}

# 実行ログの ERROR 行(run_id 欄が `-`)の本文だけを並べる
log_errors_without_run_id() {
	sed -n 's/^facade\.sh - [0-9T:-]* ERROR //p' "$LOG_DIR/facade.sh.log"
}

run_facade() {
	run --separate-stderr env \
		PATH="$FAKE_BIN:$PATH" \
		RELAY_GATE_CONFIG_DIR="$CONFIG_DIR" \
		RELAY_GATE_ARTIFACT_ROOT="$ARTIFACT_ROOT" \
		RELAY_GATE_LOG_DIR="$LOG_DIR" \
		"$FACADE" "$@"
}

# 並行稼働の設定(blue foreground / green background)。第 1 引数は RAPID_CROSSCHECK_MODE
arrange_parallel() {
	local rapid="$1" blue green
	blue="$(write_runner blue-runner.sh 0)"
	green="$(write_runner green-runner.sh 0)"
	write_feature_flag "BLUE_MODE=foreground" "GREEN_MODE=background" "RAPID_CROSSCHECK_MODE=$rapid" \
		"BLUE_IMPL=v1" "GREEN_IMPL=v2" "BLUE_RUNNER=$blue" "GREEN_RUNNER=$green" \
		"RAPID_CROSSCHECK_RUNNER=$(write_executable rapid-crosscheck-runner.sh)" \
		"RAPID_CROSSCHECK_WORKER=$(write_executable rapid-crosscheck-worker.sh)"
}

@test "facade_sh_greenがbackgroundで長く動く場合_greenを先に起動しblueだけを待って終了しgreenは動き続けること" {
	# Arrange
	local blue green
	blue="$(write_runner blue-runner.sh 0)"
	green="$(write_runner green-runner.sh 0 sleep)"
	write_feature_flag "BLUE_MODE=foreground" "GREEN_MODE=background" "RAPID_CROSSCHECK_MODE=off" \
		"BLUE_IMPL=v1" "GREEN_IMPL=v2" "BLUE_RUNNER=$blue" "GREEN_RUNNER=$green"

	# Act
	run_facade JOB001 20260830 full

	# Assert(条件「slot 起動順序」: background をすべて起動 → foreground。foreground の PID だけを待つ)
	[ "$status" -eq 0 ]
	wait_ready "$green"
	kill -0 "$(cat "$green.pid")"
	[[ "$(cat "$green.invoked")" =~ ^--run-id\ [0-9]{8}T[0-9]{6}-JOB001-[0-9a-f]{8}\ --job-id\ JOB001\ --role\ green\ --mode\ background\ --\ 20260830\ full$ ]]
	# 起動の順は facade の実行ログの slot started の行で見る(行の pid は各スタブが記録した自分の PID。スタブの中の記録どうしの前後は
	# 起動直後のプロセスの進み方で入れ替わりうるため使わない)
	local green_line blue_line
	green_line="$(grep -n " INFO slot started slot=green mode=background pid=$(cat "$green.self")$" "$LOG_DIR/facade.sh.log" | cut -d: -f1)"
	blue_line="$(grep -n " INFO slot started slot=blue mode=foreground pid=$(cat "$blue.self")$" "$LOG_DIR/facade.sh.log" | cut -d: -f1)"
	[ "$green_line" -lt "$blue_line" ]
}

@test "facade_sh_runnerを起動する場合_自slotの実装版とジョブマップの場所と共通の環境変数だけを渡しRELAY_GATE_HOMEは渡さないこと" {
	# Arrange
	arrange_parallel off

	# Act
	BLUE_JOB_MAP_CSV=/tmp/other-blue.csv GREEN_IMPL=leak RELAY_GATE_HOME="$HOME_DIR/bin" run_facade JOB001

	# Assert(契約 commands の facade.sh の notes)
	[ "$status" -eq 0 ]
	local env_file="$STUB_DIR/blue-runner.sh.env"
	grep -qx "BLUE_IMPL=v1" "$env_file"
	grep -qx "BLUE_JOB_MAP_CSV=$CONFIG_DIR/blue-job-map.csv" "$env_file"
	grep -qx "RAPID_CROSSCHECK_MODE=off" "$env_file"
	grep -qx "RELAY_GATE_CONFIG_DIR=$CONFIG_DIR" "$env_file"
	grep -qx "RELAY_GATE_ARTIFACT_ROOT=$ARTIFACT_ROOT" "$env_file"
	grep -qx "RELAY_GATE_LOG_DIR=$LOG_DIR" "$env_file"
	run ! grep -q "^RAPID_CROSSCHECK_RUNNER=" "$env_file"
	run ! grep -q "^RELAY_GATE_HOME=" "$env_file"
	run ! grep -q "^GREEN_IMPL=" "$env_file"
	run ! grep -q "^GREEN_JOB_MAP_CSV=" "$env_file"
	run ! grep -q "^BLUE_MODE=" "$env_file"
	wait_ready "$STUB_DIR/green-runner.sh"
	grep -qx "GREEN_IMPL=v2" "$STUB_DIR/green-runner.sh.env"
	grep -qx "GREEN_JOB_MAP_CSV=$CONFIG_DIR/green-job-map.csv" "$STUB_DIR/green-runner.sh.env"
}

@test "facade_sh_foregroundのexitcode_txtが3の場合_終了コード3で終了しstdoutとstderrに何も出さないこと" {
	# Arrange
	local blue
	blue="$(write_runner blue-runner.sh 3)"
	write_feature_flag "BLUE_MODE=foreground" "GREEN_MODE=off" "RAPID_CROSSCHECK_MODE=off" "BLUE_IMPL=v1" "BLUE_RUNNER=$blue"

	# Act
	run_facade JOB001

	# Assert
	[ "$status" -eq 3 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
}

@test "facade_sh_foregroundがexitcode_txtを書かずに終わった場合_終了コード6で実行ログにERRORを残しstderrには出さないこと" {
	# Arrange
	local blue
	blue="$(write_runner blue-runner.sh none)"
	write_feature_flag "BLUE_MODE=foreground" "GREEN_MODE=off" "RAPID_CROSSCHECK_MODE=off" "BLUE_IMPL=v1" "BLUE_RUNNER=$blue"

	# Act
	run_facade JOB001

	# Assert(契約 facade.sh exit_codes の 6: foreground の exitcode.txt なし。foreground 起動後は stderr を汚さない)
	[ "$status" -eq 6 ]
	[ -z "$stderr" ]
	grep -q " ERROR foreground exit code not available slot=blue path: " "$LOG_DIR/facade.sh.log"
}

@test "facade_sh_JOB_IDより前に未知のオプションがある場合_unknown_optionで終了コード2であること" {
	# Arrange
	arrange_parallel off

	# Act
	run_facade --foo JOB001

	# Assert(契約 option_placement)
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: unknown option option=--foo" ]
	[ ! -e "$STUB_DIR/blue-runner.sh.invoked" ]
}

@test "facade_sh_JOB_IDに使えない文字がある場合_終了コード2でどのrunnerも起動しないこと" {
	# Arrange
	arrange_parallel off

	# Act
	run_facade "JOB.001"

	# Assert
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: invalid value key=JOB_ID value=JOB.001" ]
	[ ! -e "$STUB_DIR/blue-runner.sh.invoked" ]
	[ ! -e "$ARTIFACT_ROOT/facade" ]
}

@test "facade_sh_JOB_IDの後ろにハイフン始まりの引数がある場合_PARAMとして順序を変えずにrunnerへ渡すこと" {
	# Arrange
	local blue
	blue="$(write_runner blue-runner.sh 0)"
	write_feature_flag "BLUE_MODE=foreground" "GREEN_MODE=off" "RAPID_CROSSCHECK_MODE=off" "BLUE_IMPL=v1" "BLUE_RUNNER=$blue"

	# Act
	run_facade --verbose JOB001 --help -- x

	# Assert
	[ "$status" -eq 0 ]
	[[ "$(cat "$blue.invoked")" =~ --role\ blue\ --mode\ foreground\ --\ --help\ --\ x$ ]]
}

@test "facade_sh_設定の違反が2つある場合_未知キーのwarnの後に最初の違反のerror行だけを出すこと" {
	# Arrange
	local green
	green="$(write_runner green-runner.sh 0)"
	write_feature_flag "CONFIG_VERSION=2026-08-30" "BLUE_MODE=foreground" "GREEN_MODE=background" "RAPID_CROSSCHECK_MODE=off" \
		"BLUE_IMPL=blue-2.3.1" "BLUE_RUNNER=relative/blue-runner.sh" "GREEN_RUNNER=$green"

	# Act
	run_facade JOB001

	# Assert(契約 config_violation_report)
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 2 ]
	[ "${stderr_lines[0]}" = "warn: unknown key key=CONFIG_VERSION path: $CONFIG_DIR/feature-flag.env" ]
	[ "${stderr_lines[1]}" = "error: file not executable key=BLUE_RUNNER path=$CONFIG_DIR/relative/blue-runner.sh" ]
	[ ! -e "$green.invoked" ]
	[ ! -e "$ARTIFACT_ROOT/facade" ]
}

@test "facade_sh_RELAY_GATE_NOWが設定されている場合_その時刻のローカル表記をrun_idの時刻部にすること" {
	# Arrange
	local blue
	blue="$(write_runner blue-runner.sh 0)"
	write_feature_flag "BLUE_MODE=foreground" "GREEN_MODE=off" "RAPID_CROSSCHECK_MODE=off" "BLUE_IMPL=v1" "BLUE_RUNNER=$blue"

	# Act
	TZ=UTC RELAY_GATE_NOW=2026-08-30T11:30:00Z run_facade JOB001

	# Assert(shared_rules.run_id。時刻部に Z を付けない。RELAY_GATE_NOW は runner に引き継ぐ)
	[ "$status" -eq 0 ]
	[[ "$(cat "$blue.invoked")" =~ ^--run-id\ 20260830T113000-JOB001-[0-9a-f]{8}\  ]]
	grep -qx "RELAY_GATE_NOW=2026-08-30T11:30:00Z" "$blue.env"
	grep -q "^facade.sh 20260830T113000-JOB001-[0-9a-f]\{8\} 2026-08-30T11:30:00 WARN test clock injected now=2026-08-30T11:30:00Z$" "$LOG_DIR/facade.sh.log"
}

@test "facade_sh_RELAY_GATE_NOWの形式が違う場合_終了コード2でどのrunnerも起動しないこと" {
	# Arrange
	local blue
	blue="$(write_runner blue-runner.sh 0)"
	write_feature_flag "BLUE_MODE=foreground" "GREEN_MODE=off" "RAPID_CROSSCHECK_MODE=off" "BLUE_IMPL=v1" "BLUE_RUNNER=$blue"

	# Act
	RELAY_GATE_NOW=2026-08-30T11:30:00 run_facade JOB001

	# Assert(契約 conventions.environment_variables の RELAY_GATE_NOW)
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: invalid value env=RELAY_GATE_NOW value=2026-08-30T11:30:00" ]
	[ ! -e "$blue.invoked" ]
}

@test "facade_sh_RAPID_CROSSCHECK_MODEがoffの場合_RDBクライアントを呼ばず実行ログに起動の流れを残すこと" {
	# Arrange
	arrange_parallel off
	write_fake_psql

	# Act
	run_facade JOB001

	# Assert
	[ "$status" -eq 0 ]
	[ ! -e "$FAKE_PSQL_LOG.args" ]
	local log="$LOG_DIR/facade.sh.log"
	grep -q " INFO feature flag loaded blue_mode=foreground green_mode=background rapid_crosscheck_mode=off blue_impl=v1 green_impl=v2 operation_mode=custom$" "$log"
	grep -q " INFO slot started slot=green mode=background pid=[0-9]*$" "$log"
	grep -q " INFO waiting foreground slot=blue pid=[0-9]*$" "$log"
	grep -q " INFO foreground finished slot=blue exit_code=0$" "$log"
	run ! grep -q "parallel_run status changed" "$log"
}

@test "facade_sh_RAPID_CROSSCHECK_MODEがbackgroundでrapid-crosscheck_envが無い場合_終了コード2でどのrunnerも起動しないこと" {
	# Arrange
	arrange_parallel background
	write_fake_psql

	# Act
	run_facade JOB001

	# Assert
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: config file not found path: $CONFIG_DIR/rapid-crosscheck.env" ]
	[ ! -e "$STUB_DIR/blue-runner.sh.invoked" ]
	[ ! -e "$FAKE_PSQL_LOG.args" ]
	[ ! -e "$ARTIFACT_ROOT/facade" ]
}

@test "facade_sh_rapid-crosscheck_envにRAPID_DB_CONN_REFが無い場合_option_requiredで終了コード2であること" {
	# Arrange
	arrange_parallel foreground
	printf '%s\n' "RAPID_LEASE_SEC=600" >"$CONFIG_DIR/rapid-crosscheck.env"

	# Act
	run_facade JOB001

	# Assert
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: option required option=RAPID_DB_CONN_REF path: $CONFIG_DIR/rapid-crosscheck.env" ]
	[ ! -e "$STUB_DIR/blue-runner.sh.invoked" ]
}

@test "facade_sh_RAPID_CROSSCHECK_MODEがbackgroundの場合_参照名をサービス名として渡し起動前INSERTと起動後UPDATEの順でSQLを送ること" {
	# Arrange
	arrange_parallel background
	printf '%s\n' "RAPID_DB_CONN_REF=mgmt-db" "RAPID_LEASE_SEC=600" >"$CONFIG_DIR/rapid-crosscheck.env"
	write_fake_psql

	# Act
	run_facade JOB001 20260830 full

	# Assert(tier-facade.md 起動順序 2〜5)
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	grep -qx "service='mgmt-db'" "$FAKE_PSQL_LOG.args"
	grep -qx -- "-X" "$FAKE_PSQL_LOG.args"
	grep -qxF "parameters=[\"20260830\",\"full\"]" "$FAKE_PSQL_LOG.args"
	# SQL の順(runner の起動記録は runner の中で書くため、起動後の pid の UPDATE との前後は決まらない。SQL だけを並べて見る)
	local -a order
	mapfile -t order < <(grep '^sql ' "$ORDER_LOG")
	[ "${#order[@]}" -eq 6 ]
	[[ "${order[0]}" == "sql INSERT INTO parallel_runs "* ]]
	[[ "${order[1]}" == "sql INSERT INTO slot_executions "* ]]
	[[ "${order[2]}" == "sql UPDATE slot_executions SET pid "* ]]
	[[ "${order[3]}" == "sql INSERT INTO slot_executions "* ]]
	[[ "${order[4]}" == "sql UPDATE slot_executions SET pid "* ]]
	[[ "${order[5]}" == "sql UPDATE parallel_runs SET status = 'RUNNING' "* ]]
	# 起動前 INSERT は runner の起動より前(green の起動記録は 2 つ目の SQL より後)。pid の UPDATE には起動した runner 自身の PID が入る
	local -a all
	mapfile -t all <"$ORDER_LOG"
	[[ "${all[1]}" == "sql INSERT INTO slot_executions "* ]]
	[ "$(grep -n '^launch green-runner.sh$' "$ORDER_LOG" | cut -d: -f1)" -gt 2 ]
	wait_ready "$STUB_DIR/green-runner.sh"
	grep -qx "pid=$(cat "$STUB_DIR/green-runner.sh.self")" "$FAKE_PSQL_LOG.args"
	grep -qx "pid=$(cat "$STUB_DIR/blue-runner.sh.self")" "$FAKE_PSQL_LOG.args"
	grep -qx "RAPID_CROSSCHECK_RUNNER=$STUB_DIR/rapid-crosscheck-runner.sh" "$STUB_DIR/blue-runner.sh.env"
	grep -q " INFO parallel_run status changed from=STARTED to=RUNNING run_id=" "$LOG_DIR/facade.sh.log"
}

@test "facade_sh_管理DBに接続できない場合_connection_failedとconn_refを出し終了コード6でどのrunnerも起動しないこと" {
	# Arrange
	arrange_parallel background
	printf '%s\n' "RAPID_DB_CONN_REF=mgmt-db" >"$CONFIG_DIR/rapid-crosscheck.env"
	write_fake_psql

	# Act
	FAKE_PSQL_EXIT=2 run_facade JOB001

	# Assert
	[ "$status" -eq 6 ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[[ "$stderr" =~ ^error:\ management\ db\ connection\ failed\ run_id=[0-9]{8}T[0-9]{6}-JOB001-[0-9a-f]{8}\ conn_ref=mgmt-db$ ]]
	[ ! -e "$STUB_DIR/blue-runner.sh.invoked" ]
	[ ! -e "$STUB_DIR/green-runner.sh.invoked" ]
}

@test "facade_sh_rapid_runsのINSERTに失敗した場合_insert_failedとtable=rapid_runsを出し終了コード6であること" {
	# Arrange
	arrange_parallel background
	printf '%s\n' "RAPID_DB_CONN_REF=mgmt-db" >"$CONFIG_DIR/rapid-crosscheck.env"
	write_fake_psql

	# Act
	FAKE_PSQL_EXIT=3 run_facade JOB001

	# Assert(スタブは \echo の行をすべて出してから失敗する。最後に始めた文が rapid_runs)
	[ "$status" -eq 6 ]
	[[ "$stderr" =~ ^error:\ management\ db\ insert\ failed\ table=rapid_runs\ run_id=[0-9]{8}T[0-9]{6}-JOB001-[0-9a-f]{8}$ ]]
	[ ! -e "$STUB_DIR/green-runner.sh.invoked" ]
}

@test "runner_process_adapter_launch_実体が実行可能なファイルでない場合_起動せず失敗を返すこと" {
	# Arrange(facade.sh は検証の後、起動の直前にもう一度確かめる。検証の後に実体が消えた場合の経路)
	# shellcheck source=/dev/null
	source "$HOME_DIR/src/gateway/runner_process_adapter.sh"

	# Act
	run runner_process_adapter_launch "$STUB_DIR/missing.sh" RUN JOB001 blue foreground

	# Assert
	[ "$status" -eq 1 ]
	[ -z "$RUNNER_PROCESS_PID" ]
}

# ---- attempt 2: runner の exec 失敗(F-009)----

# background の green の exec が失敗する設定(blue は正常)。第 1 引数は RAPID_CROSSCHECK_MODE
arrange_green_exec_failure() {
	local rapid="$1" blue green
	blue="$(write_runner blue-runner.sh 0)"
	green="$(write_unexecutable_runner green-runner.sh)"
	write_feature_flag "BLUE_MODE=foreground" "GREEN_MODE=background" "RAPID_CROSSCHECK_MODE=$rapid" \
		"BLUE_IMPL=v1" "GREEN_IMPL=v2" "BLUE_RUNNER=$blue" "GREEN_RUNNER=$green" \
		"RAPID_CROSSCHECK_RUNNER=$(write_executable rapid-crosscheck-runner.sh)" \
		"RAPID_CROSSCHECK_WORKER=$(write_executable rapid-crosscheck-worker.sh)"
}

@test "facade_sh_backgroundのrunnerのexecが失敗した場合_起動失敗として終了コード6でforegroundを起動しないこと" {
	# Arrange
	arrange_green_exec_failure off

	# Act
	run_facade JOB001

	# Assert(tier-facade.md 出力契約 6: runner プロセスの起動失敗(exec 不可)。起動に失敗したら後の slot は起動しない)
	[ "$status" -eq 6 ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[[ "$stderr" =~ ^error:\ runner\ failed\ to\ start\ run_id=[0-9]{8}T[0-9]{6}-JOB001-[0-9a-f]{8}\ role=green\ runner=$STUB_DIR/green-runner.sh$ ]]
	[ ! -e "$STUB_DIR/blue-runner.sh.invoked" ]
	grep -q " ERROR runner failed to start run_id=.* role=green runner=$STUB_DIR/green-runner.sh started_pids=-$" "$LOG_DIR/facade.sh.log"
	run ! grep -q "slot started slot=green" "$LOG_DIR/facade.sh.log"
}

@test "facade_sh_setsidを介した起動でrunnerのexecが失敗した場合_起動失敗として終了コード6であること" {
	# Arrange(setsid の exec は成功し、setsid の後の層で runner の exec が失敗する経路。実行環境の Linux と同じ層の重なり)
	arrange_green_exec_failure off
	write_fake_setsid

	# Act
	run_facade JOB001

	# Assert
	[ "$status" -eq 6 ]
	[[ "$stderr" =~ ^error:\ runner\ failed\ to\ start\ run_id=.*\ role=green\ runner=$STUB_DIR/green-runner.sh$ ]]
	[ ! -e "$STUB_DIR/blue-runner.sh.invoked" ]
}

@test "facade_sh_setsidを介した起動でrunnerのexecが成功した場合_PIDはrunner自身のPIDでありforegroundの結果で終わること" {
	# Arrange
	arrange_parallel off
	write_fake_setsid

	# Act
	run_facade JOB001

	# Assert
	[ "$status" -eq 0 ]
	wait_ready "$STUB_DIR/green-runner.sh"
	grep -q " INFO slot started slot=green mode=background pid=$(cat "$STUB_DIR/green-runner.sh.self")$" "$LOG_DIR/facade.sh.log"
	grep -q " INFO slot started slot=blue mode=foreground pid=$(cat "$STUB_DIR/blue-runner.sh.self")$" "$LOG_DIR/facade.sh.log"
}

@test "facade_sh_foregroundのrunnerのexecが失敗した場合_起動済みのbackgroundのPIDを実行ログに残し止めずに終了コード6であること" {
	# Arrange
	local blue green
	blue="$(write_unexecutable_runner blue-runner.sh)"
	green="$(write_runner green-runner.sh 0 sleep)"
	write_feature_flag "BLUE_MODE=foreground" "GREEN_MODE=background" "RAPID_CROSSCHECK_MODE=off" \
		"BLUE_IMPL=v1" "GREEN_IMPL=v2" "BLUE_RUNNER=$blue" "GREEN_RUNNER=$green"

	# Act
	run_facade JOB001

	# Assert(tier-facade.md エラーハンドリング: 起動済みの background runner は継続させ、実行ログに起動済み PID を残す)
	[ "$status" -eq 6 ]
	[[ "$stderr" =~ ^error:\ runner\ failed\ to\ start\ run_id=.*\ role=blue\ runner=$blue$ ]]
	wait_ready "$green"
	kill -0 "$(cat "$green.pid")"
	grep -q " ERROR runner failed to start run_id=.* role=blue runner=$blue started_pids=$(cat "$green.self")$" "$LOG_DIR/facade.sh.log"
}

@test "facade_sh_RAPID_CROSSCHECK_MODEがbackgroundでrunnerのexecが失敗した場合_起動前INSERTの行をFAILEDで閉じpidを更新しないこと" {
	# Arrange
	arrange_green_exec_failure background
	printf '%s\n' "RAPID_DB_CONN_REF=mgmt-db" >"$CONFIG_DIR/rapid-crosscheck.env"
	write_fake_psql

	# Act
	run_facade JOB001

	# Assert(UC ロジックのエラーハンドリング: slot_executions 行を status='FAILED', completed_at で閉じる)
	[ "$status" -eq 6 ]
	local -a order
	mapfile -t order < <(grep '^sql ' "$ORDER_LOG")
	[ "${#order[@]}" -eq 3 ]
	[[ "${order[0]}" == "sql INSERT INTO parallel_runs "* ]]
	[[ "${order[1]}" == "sql INSERT INTO slot_executions "* ]]
	[[ "${order[2]}" == "sql UPDATE slot_executions SET status = 'FAILED', completed_at = "* ]]
	grep -qx "slot=green" "$FAKE_PSQL_LOG.args"
}

# ---- attempt 3: exec を見張る層が始まる前の起動失敗(F-001)----

# 何も起動せずに終わる setsid のスタブ(setsid 自体の失敗。exec を見張る層が始まる前に起動が失敗する経路)
write_failing_setsid() {
	printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$FAKE_BIN/setsid"
	chmod +x "$FAKE_BIN/setsid"
}

@test "facade_sh_setsidがrunnerを起動する前に失敗した場合_起動失敗として終了コード6で後のslotを起動しないこと" {
	# Arrange
	arrange_parallel off
	write_failing_setsid

	# Act
	run_facade JOB001

	# Assert(tier-facade.md 出力契約 6。起動に失敗したら後の slot は起動しない)
	[ "$status" -eq 6 ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[[ "$stderr" =~ ^error:\ runner\ failed\ to\ start\ run_id=.*\ role=green\ runner=$STUB_DIR/green-runner.sh$ ]]
	[ ! -e "$STUB_DIR/green-runner.sh.invoked" ]
	[ ! -e "$STUB_DIR/blue-runner.sh.invoked" ]
	run ! grep -q "slot started" "$LOG_DIR/facade.sh.log"
}

@test "facade_sh_RAPID_CROSSCHECK_MODEがbackgroundでsetsidが起動前に失敗した場合_起動前INSERTの行をFAILEDで閉じRUNNINGへ更新しないこと" {
	# Arrange
	arrange_parallel background
	printf '%s\n' "RAPID_DB_CONN_REF=mgmt-db" >"$CONFIG_DIR/rapid-crosscheck.env"
	write_fake_psql
	write_failing_setsid

	# Act
	run_facade JOB001

	# Assert(UC ロジックのエラーハンドリング: slot_executions 行を status='FAILED', completed_at で閉じる)
	[ "$status" -eq 6 ]
	local -a order
	mapfile -t order < <(grep '^sql ' "$ORDER_LOG")
	[ "${#order[@]}" -eq 3 ]
	[[ "${order[0]}" == "sql INSERT INTO parallel_runs "* ]]
	[[ "${order[1]}" == "sql INSERT INTO slot_executions "* ]]
	[[ "${order[2]}" == "sql UPDATE slot_executions SET status = 'FAILED', completed_at = "* ]]
}

@test "runner_process_adapter_launch_setsidがrunnerを起動する前に失敗した場合_失敗を返しPIDを残さないこと" {
	# Arrange
	local runner
	runner="$(write_runner green-runner.sh 0)"
	write_failing_setsid
	PATH="$FAKE_BIN:$PATH"
	# shellcheck source=/dev/null
	source "$HOME_DIR/src/gateway/runner_process_adapter.sh"

	# Act
	local status=0
	runner_process_adapter_launch "$runner" RUN JOB001 green background || status=$?

	# Assert
	[ "$status" -eq 1 ]
	[ -z "$RUNNER_PROCESS_PID" ]
	[ ! -e "$runner.invoked" ]
}

# ---- attempt 3: runner の起動より前に slot_executions の INSERT が確定していること(F-002)----

@test "facade_sh_RAPID_CROSSCHECK_MODEがbackgroundの場合_runnerが動き出した時点で自slotのslot_executionsのINSERTが既に記録されていること" {
	# Arrange(runner のスタブは動き出した時点の slot_executions の INSERT の数を記録する。
	# psql のスタブは slot_executions の INSERT を記録する前に少し待つ。INSERT が起動の後に移ると、
	# runner が記録する時点ではまだ記録されていないため数が足りなくなる)
	arrange_parallel background
	printf '%s\n' "RAPID_DB_CONN_REF=mgmt-db" >"$CONFIG_DIR/rapid-crosscheck.env"
	write_fake_psql
	export FAKE_PSQL_SLOT_INSERT_DELAY=1

	# Act
	run_facade JOB001

	# Assert(tier-facade.md 起動順序: slot_executions の INSERT は runner の起動の前に確定する)
	[ "$status" -eq 0 ]
	wait_ready "$STUB_DIR/green-runner.sh"
	# green は自 slot の 1 件があればよい(高負荷で動き出しが遅れて blue の分まで数えても正しい順序)
	[ "$(cat "$STUB_DIR/green-runner.sh.inserts")" -ge 1 ]
	[ "$(cat "$STUB_DIR/blue-runner.sh.inserts")" -eq 2 ]
}

# ---- attempt 2: runner の環境(F-019)----

@test "facade_sh_親の環境にRAPID_DB_CONN_REFとfeature-flagのキーがある場合_runnerへ引き継がないこと" {
	# Arrange
	arrange_parallel background
	printf '%s\n' "RAPID_DB_CONN_REF=mgmt-db" >"$CONFIG_DIR/rapid-crosscheck.env"
	write_fake_psql

	# Act
	RAPID_DB_CONN_REF=parent-ref BLUE_MODE=parent BLUE_RUNNER=/parent/runner RAPID_CROSSCHECK_WORKER=/parent/worker \
		run_facade JOB001

	# Assert(tier-facade.md 起動する runner IF: RAPID_DB_CONN_REF は渡さず runner が rapid-crosscheck.env を自分で読む)
	[ "$status" -eq 0 ]
	wait_ready "$STUB_DIR/green-runner.sh"
	local env_file
	for env_file in "$STUB_DIR/blue-runner.sh.env" "$STUB_DIR/green-runner.sh.env"; do
		run ! grep -q "^RAPID_DB_CONN_REF=" "$env_file"
		run ! grep -q "^BLUE_MODE=" "$env_file"
		run ! grep -q "^BLUE_RUNNER=" "$env_file"
		run ! grep -q "^RAPID_CROSSCHECK_WORKER=" "$env_file"
		grep -qx "RAPID_CROSSCHECK_MODE=background" "$env_file"
	done
}

@test "facade_sh_RAPID_CROSSCHECK_MODEがoffで親の環境にRAPID_DB_CONN_REFがある場合_runnerへ引き継がないこと" {
	# Arrange
	arrange_parallel off

	# Act
	RAPID_DB_CONN_REF=parent-ref run_facade JOB001

	# Assert
	[ "$status" -eq 0 ]
	run ! grep -q "^RAPID_DB_CONN_REF=" "$STUB_DIR/blue-runner.sh.env"
}

# ---- attempt 2: 検証エラーの実行ログ(F-023)----

@test "facade_sh_feature-flagの検証エラーの場合_stderrは変えずに同じerror行を実行ログにrun_id未確定のERRORで1回残すこと" {
	# Arrange
	write_feature_flag "BLUE_MODE=invalid" "GREEN_MODE=off" "RAPID_CROSSCHECK_MODE=off"

	# Act
	run_facade JOB001

	# Assert(tier-facade.md エラーハンドリング: usecase で 1 回だけ実行ログに ERROR)
	[ "$status" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: invalid value key=BLUE_MODE value=invalid" ]
	[ "${stderr_lines[1]}" = "hint: use foreground, background or off" ]
	[ "${#stderr_lines[@]}" -eq 2 ]
	[ "$(log_errors_without_run_id)" = "invalid value key=BLUE_MODE value=invalid" ]
}

@test "facade_sh_feature-flag_envが無い場合_config_file_not_foundを実行ログにもERRORで残すこと" {
	# Act
	run_facade JOB001

	# Assert
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: config file not found path: $CONFIG_DIR/feature-flag.env" ]
	[ "$(log_errors_without_run_id)" = "config file not found path: $CONFIG_DIR/feature-flag.env" ]
}

@test "facade_sh_rapid-crosscheck_envの検証エラーの場合_実行ログにERRORで残すこと" {
	# Arrange
	arrange_parallel background

	# Act
	run_facade JOB001

	# Assert
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: config file not found path: $CONFIG_DIR/rapid-crosscheck.env" ]
	[ "$(log_errors_without_run_id)" = "config file not found path: $CONFIG_DIR/rapid-crosscheck.env" ]
}

@test "facade_sh_RAPID_DB_CONN_REFが無い場合_実行ログにERRORで残すこと" {
	# Arrange
	arrange_parallel foreground
	printf '%s\n' "RAPID_LEASE_SEC=600" >"$CONFIG_DIR/rapid-crosscheck.env"

	# Act
	run_facade JOB001

	# Assert
	[ "$status" -eq 2 ]
	[ "$(log_errors_without_run_id)" = "option required option=RAPID_DB_CONN_REF path: $CONFIG_DIR/rapid-crosscheck.env" ]
}

@test "facade_sh_RELAY_GATE_NOWの形式が違う場合_実行ログにERRORで残すこと" {
	# Arrange
	arrange_parallel off

	# Act
	RELAY_GATE_NOW=bad run_facade JOB001

	# Assert
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: invalid value env=RELAY_GATE_NOW value=bad" ]
	[ "$(log_errors_without_run_id)" = "invalid value env=RELAY_GATE_NOW value=bad" ]
}

@test "facade_sh_引数の検証エラーの場合_実行ログにrun_id未確定のERRORで残すこと" {
	# Arrange
	arrange_parallel off

	# Act
	run_facade --foo JOB001

	# Assert(ui-design.md 実行ログファイル: run_id が未確定の段階(引数検証前など)は `-`)
	[ "$status" -eq 2 ]
	[ "$stderr" = "error: unknown option option=--foo" ]
	[ "$(log_errors_without_run_id)" = "unknown option option=--foo" ]
}

@test "facade_sh_helpの場合_実行ログを書かないこと" {
	# Act
	run_facade --help

	# Assert
	[ "$status" -eq 0 ]
	[ ! -s "$LOG_DIR/facade.sh.log" ]
}

# ---- attempt 2: 状態遷移の UPDATE が 0 件(F-022)----

@test "facade_sh_STARTEDからRUNNINGへのUPDATEが0件の場合_遷移したと記録せず実行ログにERRORを残し終了コードは変えないこと" {
	# Arrange
	arrange_parallel background
	printf '%s\n' "RAPID_DB_CONN_REF=mgmt-db" >"$CONFIG_DIR/rapid-crosscheck.env"
	write_fake_psql

	# Act
	FAKE_PSQL_ROWS=0 run_facade JOB001

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	run ! grep -q "parallel_run status changed" "$LOG_DIR/facade.sh.log"
	grep -q " ERROR management db update failed table=parallel_runs run_id=[0-9]\{8\}T[0-9]\{6\}-JOB001-[0-9a-f]\{8\}$" "$LOG_DIR/facade.sh.log"
	grep -q " ERROR management db update failed table=slot_executions run_id=" "$LOG_DIR/facade.sh.log"
}
