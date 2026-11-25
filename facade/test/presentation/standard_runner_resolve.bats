#!/usr/bin/env bats
# UC 7c41c7cd × tier-facade: 標準の slot runner(runners/standard-runner.sh)の解決フェーズの単体テスト(入口から見える振る舞い)。
# 仕様: tier-facade.md「出力契約」(成果物・終了コード・エラーメッセージ・実行ログ)と「ジョブマップ(読み取り専用)」。
# 判定するのは、runner を runner IF の引数で起動したときに外から見える結果だけ(成果物ファイル・実行ログ・終了コード)。
# 共通ライブラリ(lib/runner-resolve.sh)の関数の名前と分け方は仕様に無いため、ここでは固定しない(層ごとの単体テストは S4 の TDD で足す)。
# role ディレクトリは facade が作るもの(runner を直接起動するこのテストでは、起動前に用意する)。
# 時間を確かめるテスト、大きな入力を作るテストは書かない。リポジトリの中にファイルを書かない(書くのは BATS_TEST_TMPDIR だけ)。
# 管理 DB は使わない(RAPID_CROSSCHECK_MODE=off)。

bats_require_minimum_version 1.5.0

RUN_ID_JOB001="20260830T113000-JOB001-3f9a1c2e"
RUN_ID_JOB999="20260830T113000-JOB999-a1b2c3d4"
HEADER_9="job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version"
ROW_JOB001_9="JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60,ssh-key-green,map-v3"

setup() {
	HOME_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	RUNNER="$HOME_DIR/runners/standard-runner.sh"
	CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	ARTIFACT_ROOT="$BATS_TEST_TMPDIR/artifacts"
	LOG_DIR="$BATS_TEST_TMPDIR/logs"
	RUNNER_LOG="$LOG_DIR/standard-runner.sh.log"
	mkdir -p "$CONFIG_DIR" "$ARTIFACT_ROOT" "$LOG_DIR"
}

# green のジョブマップを置く(1 行目ヘッダー、2 行目以降は引数の行)
write_job_map() {
	local file="$1"
	shift
	mkdir -p "$(dirname "$file")"
	printf '%s\n' "$@" >"$file"
}

# facade が runner へ渡す環境変数だけで、green の runner を runner IF の引数で起動する。
# 第 1 引数は GREEN_JOB_MAP_CSV の渡し方(unset = 渡さない / それ以外 = その値を渡す)。role ディレクトリは facade の代わりに用意する
run_green_runner() {
	local job_map_env="$1" run_id="$2"
	shift 2
	mkdir -p "$ARTIFACT_ROOT/facade/$run_id/green"
	local -a env_args=(
		PATH="$PATH"
		RELAY_GATE_CONFIG_DIR="$CONFIG_DIR"
		RELAY_GATE_ARTIFACT_ROOT="$ARTIFACT_ROOT"
		RELAY_GATE_LOG_DIR="$LOG_DIR"
		RAPID_CROSSCHECK_MODE=off
		GREEN_IMPL=v2
	)
	if [ "$job_map_env" != unset ]; then
		env_args+=(GREEN_JOB_MAP_CSV="$job_map_env")
	fi
	run --separate-stderr env -i "${env_args[@]}" "$RUNNER" --run-id "$run_id" "$@"
}

# 解決フェーズがまだ無い標準の slot runner は、正しい引数に仮の終了コード 6 を返して何も書かない。その状態を「未実装」として明示する
require_resolve_phase() {
	local role_dir="$1"
	if [ "$status" -eq 6 ] && [ ! -e "$role_dir/exitcode.txt" ] && [ ! -e "$RUNNER_LOG" ]; then
		echo "not implemented: $RUNNER answers the placeholder exit code 6 without resolving the job map"
		return 1
	fi
}

@test "標準のslot runner_JOB_IDの行がジョブマップに無い場合_3ファイルとstarted-at_txtを揃えて終了コード2であること" {
	# Arrange
	write_job_map "$CONFIG_DIR/green-job-map.csv" "$HEADER_9" "$ROW_JOB001_9"
	local role_dir="$ARTIFACT_ROOT/facade/$RUN_ID_JOB999/green"

	# Act
	run_green_runner unset "$RUN_ID_JOB999" --job-id JOB999 --role green --mode background

	# Assert(runner はプロセスの stdout / stderr に出さない。exitcode.txt は runner の終了コードと一致する)
	require_resolve_phase "$role_dir"
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ -f "$role_dir/started-at.txt" ]
	[ -f "$role_dir/stdout.log" ]
	[ ! -s "$role_dir/stdout.log" ]
	[ "$(cat "$role_dir/exitcode.txt")" = "2" ]
	[ "$(wc -l <"$role_dir/exitcode.txt" | tr -d ' ')" = "1" ]
	grep -qxF "error: job_id=JOB999 not found in job map slot=green map=$CONFIG_DIR/green-job-map.csv" "$role_dir/stderr.log"
	[ -z "$(find "$role_dir" -name '*.tmp')" ]
}

@test "標準のslot runner_ジョブマップのファイルが無い場合_stderr_logにjob map not foundを書いて終了コード2であること" {
	# Arrange(設定ファイル置き場に green-job-map.csv を置かない)
	local role_dir="$ARTIFACT_ROOT/facade/$RUN_ID_JOB001/green"

	# Act
	run_green_runner unset "$RUN_ID_JOB001" --job-id JOB001 --role green --mode background

	# Assert
	require_resolve_phase "$role_dir"
	[ "$status" -eq 2 ]
	[ "$(cat "$role_dir/exitcode.txt")" = "2" ]
	grep -qxF "error: job map not found slot=green map=$CONFIG_DIR/green-job-map.csv" "$role_dir/stderr.log"
}

@test "標準のslot runner_環境変数GREEN_JOB_MAP_CSVでジョブマップの場所を受け取った場合_既定の場所ではなくその場所をmap=に出すこと" {
	# Arrange(既定の場所には JOB999 の行があり、環境変数で渡す場所のジョブマップには無い)
	local maps="$BATS_TEST_TMPDIR/maps"
	write_job_map "$CONFIG_DIR/green-job-map.csv" "$HEADER_9" "JOB999,host-default-99,other,/var/default,/opt/default/job999.sh,[],60,,"
	write_job_map "$maps/green-jobs.csv" "$HEADER_9" "$ROW_JOB001_9"
	local role_dir="$ARTIFACT_ROOT/facade/$RUN_ID_JOB999/green"

	# Act
	run_green_runner "$maps/green-jobs.csv" "$RUN_ID_JOB999" --job-id JOB999 --role green --mode background

	# Assert
	require_resolve_phase "$role_dir"
	[ "$status" -eq 2 ]
	[ "$(cat "$role_dir/exitcode.txt")" = "2" ]
	grep -qxF "error: job_id=JOB999 not found in job map slot=green map=$maps/green-jobs.csv" "$role_dir/stderr.log"
}

@test "標準のslot runner_JOB_IDの行がジョブマップにある場合_実行ログにjob map resolvedの行を出すこと" {
	# Arrange
	write_job_map "$CONFIG_DIR/green-job-map.csv" "$HEADER_9" "$ROW_JOB001_9"
	local role_dir="$ARTIFACT_ROOT/facade/$RUN_ID_JOB001/green"

	# Act(解決の後の段(execution-spec の保存・実装の実行)は後続の機能の担当。ここでは終了コードを判定しない)
	run_green_runner unset "$RUN_ID_JOB001" --job-id JOB001 --role green --mode background -- 20260830

	# Assert(実行ログの行形式: {script} {run_id} {ローカル日時} {LEVEL} {message})
	require_resolve_phase "$role_dir"
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ -f "$RUNNER_LOG" ]
	grep -qE "^standard-runner\.sh $RUN_ID_JOB001 [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} INFO job map resolved job_id=JOB001 slot=green host=host-green-01 map_version=map-v3\$" "$RUNNER_LOG"
}

# ---- S4(tier 実装)で足したテスト ----

@test "標準のslot runner_解決に成功した場合_後続の段が無い間は成果物を書かず仮の終了コード6であること" {
	# Arrange(execution-spec の保存と実装の実行は後続の機能の担当。それまでの終わり方は実装で決めた前提)
	write_job_map "$CONFIG_DIR/green-job-map.csv" "$HEADER_9" "$ROW_JOB001_9"
	local role_dir="$ARTIFACT_ROOT/facade/$RUN_ID_JOB001/green"

	# Act
	run_green_runner unset "$RUN_ID_JOB001" --job-id JOB001 --role green --mode background

	# Assert(解決フェーズは副作用を持たない。ファイル書き込みは失敗時のみ)
	[ "$status" -eq 6 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ -z "$(ls -A "$role_dir")" ]
	[ "$(grep -c ' ERROR ' "$RUNNER_LOG")" = "0" ]
}

@test "標準のslot runner_roleディレクトリが無いまま直接起動して解決に失敗した場合_ディレクトリを作って3ファイルを揃えること" {
	# Arrange(facade を介さない起動。role ディレクトリを用意しない)
	local role_dir="$ARTIFACT_ROOT/facade/$RUN_ID_JOB001/blue"
	local -a env_args=(PATH="$PATH" RELAY_GATE_CONFIG_DIR="$CONFIG_DIR" RELAY_GATE_ARTIFACT_ROOT="$ARTIFACT_ROOT" RELAY_GATE_LOG_DIR="$LOG_DIR")

	# Act
	run --separate-stderr env -i "${env_args[@]}" "$RUNNER" --run-id "$RUN_ID_JOB001" --job-id JOB001 --role blue --mode foreground

	# Assert
	[ "$status" -eq 2 ]
	[ "$(cat "$role_dir/exitcode.txt")" = "2" ]
	grep -qxF "error: job map not found slot=blue map=$CONFIG_DIR/blue-job-map.csv" "$role_dir/stderr.log"
}

@test "標準のslot runner_blueのジョブマップの行のhostとuserが両方空の場合_実行ログのhostが-であること" {
	# Arrange
	write_job_map "$CONFIG_DIR/blue-job-map.csv" "job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes" "JOB001,,,/var/app/work,/opt/app/bin/job001.sh,[],0"
	local -a env_args=(PATH="$PATH" RELAY_GATE_CONFIG_DIR="$CONFIG_DIR" RELAY_GATE_ARTIFACT_ROOT="$ARTIFACT_ROOT" RELAY_GATE_LOG_DIR="$LOG_DIR")

	# Act
	run --separate-stderr env -i "${env_args[@]}" "$RUNNER" --run-id "$RUN_ID_JOB001" --job-id JOB001 --role blue --mode foreground

	# Assert
	[ "$status" -eq 6 ]
	grep -qE " INFO job map resolved job_id=JOB001 slot=blue host=- map_version=-\$" "$RUNNER_LOG"
}

# ---- 独立検証の指摘を受けて足したテスト(attempt 2) ----

@test "標準のslot runner_既存のexitcode_txtが0で解決に失敗した場合_成果物を変えず既存の値0で終了すること" {
	# Arrange(同じ run_id / role の成果物が既にある = 二重起動。契約 runner IF の idempotency。ジョブマップは JOB999 を持たない)
	write_job_map "$CONFIG_DIR/green-job-map.csv" "$HEADER_9" "$ROW_JOB001_9"
	local role_dir="$ARTIFACT_ROOT/facade/$RUN_ID_JOB999/green"
	mkdir -p "$role_dir"
	printf '0\n' >"$role_dir/exitcode.txt"
	printf 'previous\n' >"$role_dir/stderr.log"

	# Act
	run_green_runner unset "$RUN_ID_JOB999" --job-id JOB999 --role green --mode background

	# Assert(プロセスの終了コードは exitcode.txt と一致する)
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ "$(cat "$role_dir/exitcode.txt")" = "0" ]
	[ "$(cat "$role_dir/stderr.log")" = "previous" ]
	[ ! -e "$role_dir/started-at.txt" ]
	grep -qE " WARN runner result already published run_id=$RUN_ID_JOB999 role=green\$" "$RUNNER_LOG"
}

@test "標準のslot runner_既存のexitcode_txtが0で引数が不正な場合_成果物を変えず既存の値0で終了すること" {
	# Arrange
	local role_dir="$ARTIFACT_ROOT/facade/$RUN_ID_JOB001/green"
	mkdir -p "$role_dir"
	printf '0\n' >"$role_dir/exitcode.txt"

	# Act(--job-id が無い)
	run_green_runner unset "$RUN_ID_JOB001" --role green --mode background

	# Assert
	[ "$status" -eq 0 ]
	[ "$(cat "$role_dir/exitcode.txt")" = "0" ]
	[ ! -e "$role_dir/stderr.log" ]
}

@test "標準のslot runner_採用した行のcredential_refがパスらしい値の場合_実行ログに値を出さないWARNを残すこと" {
	# Arrange
	write_job_map "$CONFIG_DIR/green-job-map.csv" "$HEADER_9" "JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60,/etc/keys/green.pem,map-v3"

	# Act
	run_green_runner unset "$RUN_ID_JOB001" --job-id JOB001 --role green --mode background

	# Assert
	[ -z "$output" ]
	[ -z "$stderr" ]
	grep -qE " WARN credential_ref looks like a secret or path line=2 job_id=JOB001\$" "$RUNNER_LOG"
	grep -qE " INFO job map resolved job_id=JOB001 " "$RUNNER_LOG"
	! grep -q 'green.pem' "$RUNNER_LOG"
}

# ---- 独立検証の指摘を受けて足したテスト(attempt 3。契約 runner IF の exit_codes 6 / idempotency の中止済み slot) ----

# 中止済みの slot を用意する(exitcode.txt が無く aborted.txt がある)
arrange_aborted_slot() {
	local role_dir="$1"
	mkdir -p "$role_dir"
	printf '2026-08-30T11:30:05Z\n' >"$role_dir/started-at.txt"
	printf 'partial out\n' >"$role_dir/stdout.log"
	printf 'partial err\n' >"$role_dir/stderr.log"
	printf '2026-08-30T11:40:00Z\n' >"$role_dir/aborted.txt"
}

assert_aborted_slot_untouched() {
	local role_dir="$1"
	[ ! -e "$role_dir/exitcode.txt" ]
	[ "$(cat "$role_dir/started-at.txt")" = "2026-08-30T11:30:05Z" ]
	[ "$(cat "$role_dir/stdout.log")" = "partial out" ]
	[ "$(cat "$role_dir/stderr.log")" = "partial err" ]
	[ "$(cat "$role_dir/aborted.txt")" = "2026-08-30T11:40:00Z" ]
	[ "$(find "$role_dir" -type f | wc -l | tr -d ' ')" = "4" ]
}

@test "標準のslot runner_中止済みのslotで解決に失敗した場合_成果物を変えずWARNを残して終了コード6であること" {
	# Arrange(ヘッダーだけのジョブマップ = JOB001 は未定義)
	write_job_map "$CONFIG_DIR/green-job-map.csv" "$HEADER_9"
	local role_dir="$ARTIFACT_ROOT/facade/$RUN_ID_JOB001/green"
	arrange_aborted_slot "$role_dir"

	# Act
	run_green_runner unset "$RUN_ID_JOB001" --job-id JOB001 --role green --mode background

	# Assert(exitcode.txt を書かない。中止済みの slot の再実行は background-rerun.sh が新しい run_id で行う)
	[ "$status" -eq 6 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	assert_aborted_slot_untouched "$role_dir"
	grep -qE "^standard-runner\.sh $RUN_ID_JOB001 [0-9T:-]+ WARN slot already aborted run_id=$RUN_ID_JOB001 role=green\$" "$RUNNER_LOG"
}

@test "標準のslot runner_中止済みのslotで引数が不正な場合_成果物を変えずWARNを残して終了コード6であること" {
	# Arrange
	local role_dir="$ARTIFACT_ROOT/facade/$RUN_ID_JOB001/green"
	arrange_aborted_slot "$role_dir"

	# Act(--job-id が無い)
	run_green_runner unset "$RUN_ID_JOB001" --role green --mode background

	# Assert
	[ "$status" -eq 6 ]
	assert_aborted_slot_untouched "$role_dir"
	grep -qE " ERROR option required option=--job-id\$" "$RUNNER_LOG"
	grep -qE " WARN slot already aborted run_id=$RUN_ID_JOB001 role=green\$" "$RUNNER_LOG"
}

@test "標準のslot runner_中止済みのslotで解決に成功した場合_成果物を変えずWARNを残して終了コード6であること" {
	# Arrange
	write_job_map "$CONFIG_DIR/green-job-map.csv" "$HEADER_9" "$ROW_JOB001_9"
	local role_dir="$ARTIFACT_ROOT/facade/$RUN_ID_JOB001/green"
	arrange_aborted_slot "$role_dir"

	# Act
	run_green_runner unset "$RUN_ID_JOB001" --job-id JOB001 --role green --mode background

	# Assert
	[ "$status" -eq 6 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	assert_aborted_slot_untouched "$role_dir"
	grep -qE " WARN slot already aborted run_id=$RUN_ID_JOB001 role=green\$" "$RUNNER_LOG"
	[ "$(grep -c ' ERROR ' "$RUNNER_LOG")" = "0" ]
}

@test "標準のslot runner_既存のexitcode_txtが0で解決に成功した場合_成果物を変えずWARNを残して既存の値0で終了すること" {
	# Arrange(同じ run_id / role の成果物が既にある = 二重起動)
	write_job_map "$CONFIG_DIR/green-job-map.csv" "$HEADER_9" "$ROW_JOB001_9"
	local role_dir="$ARTIFACT_ROOT/facade/$RUN_ID_JOB001/green"
	mkdir -p "$role_dir"
	printf '0\n' >"$role_dir/exitcode.txt"

	# Act
	run_green_runner unset "$RUN_ID_JOB001" --job-id JOB001 --role green --mode background

	# Assert(プロセスの終了コードは exitcode.txt と一致する)
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ "$(cat "$role_dir/exitcode.txt")" = "0" ]
	[ "$(find "$role_dir" -type f | wc -l | tr -d ' ')" = "1" ]
	grep -qE " WARN runner result already published run_id=$RUN_ID_JOB001 role=green\$" "$RUNNER_LOG"
}

@test "標準のslot runner_ジョブマップがあるが読めない場合_stderr_logにconfig file is not readableを書いて終了コード2であること" {
	# Arrange(存在するが通常ファイルではない)
	mkdir -p "$CONFIG_DIR/green-job-map.csv"
	local role_dir="$ARTIFACT_ROOT/facade/$RUN_ID_JOB001/green"

	# Act
	run_green_runner unset "$RUN_ID_JOB001" --job-id JOB001 --role green --mode background

	# Assert
	[ "$status" -eq 2 ]
	[ "$(cat "$role_dir/exitcode.txt")" = "2" ]
	grep -qxF "error: config file is not readable path: $CONFIG_DIR/green-job-map.csv" "$role_dir/stderr.log"
}
