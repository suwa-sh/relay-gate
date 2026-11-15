#!/usr/bin/env bats
# UC fd678b04 × tier-facade: validate-config.sh --feature-flag の slot ジョブマップの場所(任意の 2 キー)の単体テスト。
# エントリポイント経由で実プロセスとして起動する(内部の関数の分け方を固定しない)。I/O 境界は実ファイル(一時ディレクトリ)。
# 仕様: CLI 契約 config_files.feature-flag.env.job_map_location(BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV は任意。無い・空なら
#       $RELAY_GATE_CONFIG_DIR/<slot>-job-map.csv。値からパスを決める規則は runner_path_resolution と同じ。off の slot のキーは
#       解決も検査もしない。2 キーは未知キーではない)、tier-facade.md「slot ジョブマップの場所」、spec-decision-036 / 038
# 2026-11-16 S2 再実行で追加(利用者決定 2026-11-16)。tier BDD(facade/features/configure-feature-flags.feature)が判定しない細部
#   (blue と green で別の場所 / 絶対パスと相対パスの混在 / 両方の値が空 / off の slot の相対パス / mode が列挙外の slot /
#    --verbose の info 行 / map= の制御文字の可視表記)を補う。
#   追加時点の実装は 2 キーを未知キーとして warn し、固定の名前だけを見るため、2 キーを書くテストは fail する(実装は S4 で追従する)。
#   2 キーを書かないテスト 1 件は現行実装でも通る(9 キーだけの設定がそのまま通ることの回帰の検査)。
# 性能(契約 config_input_rules.performance_target)は目標値で合否の検査ではないため、ここに時間の検査は置かない。
bats_require_minimum_version 1.5.0

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../bin/validate-config.sh"
	CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	CONF="$BATS_TEST_TMPDIR/site/conf"
	MAPS="$BATS_TEST_TMPDIR/shared/maps"
	WORK="$BATS_TEST_TMPDIR/elsewhere/work"
	mkdir -p "$CONFIG_DIR" "$CONF" "$MAPS" "$WORK"
	export RELAY_GATE_CONFIG_DIR="$CONFIG_DIR"
	ENV_FILE="$CONF/ff.env"
}

# --help で runner-if-version=1 を返す runner スタブ
write_runner() {
	mkdir -p "${1%/*}"
	printf '%s\n' '#!/usr/bin/env bash' 'if [ "${1:-}" = "--help" ]; then echo "runner-if-version=1"; exit 0; fi' 'exit 6' >"$1"
	chmod +x "$1"
}

write_job_map() {
	mkdir -p "${1%/*}"
	printf 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\n' >"$1"
}

# 有効な並行稼働設定(9 キー。runner の実体は絶対パス)を書く。ジョブマップは置かない。追加の行は呼び出し側が追記する
write_parallel_env() {
	write_runner "$CONF/blue-runner.sh"
	write_runner "$CONF/green-runner.sh"
	write_runner "$CONF/rapid-runner.sh"
	write_runner "$CONF/rapid-worker.sh"
	printf 'BLUE_MODE=foreground\nGREEN_MODE=background\nRAPID_CROSSCHECK_MODE=background\nBLUE_IMPL=blue-2.3.1\nGREEN_IMPL=green-1.4.0\nBLUE_RUNNER=%s\nGREEN_RUNNER=%s\nRAPID_CROSSCHECK_RUNNER=%s\nRAPID_CROSSCHECK_WORKER=%s\n' \
		"$CONF/blue-runner.sh" "$CONF/green-runner.sh" "$CONF/rapid-runner.sh" "$CONF/rapid-worker.sh" >"$ENV_FILE"
}

# 単独本番(green だけ)の設定を書く。ジョブマップは置かない
write_green_only_env() {
	write_runner "$CONF/green-runner.sh"
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=%s\n' "$CONF/green-runner.sh" >"$ENV_FILE"
}

# ---- 2 キーを書かない(既定の場所) ----

@test "validate-config_sh_--feature-flagで2キーを書かない9キーだけの設定の場合_RELAY_GATE_CONFIG_DIR配下の固定の名前をstdoutに出しstderrは0行であること" {
	# Arrange(設定ファイルのあるディレクトリにも同じ名前のファイルを置く。そちらは使わない)
	write_parallel_env
	write_job_map "$CONFIG_DIR/blue-job-map.csv"
	write_job_map "$CONFIG_DIR/green-job-map.csv"
	write_job_map "$CONF/blue-job-map.csv"
	write_job_map "$CONF/green-job-map.csv"
	cd "$WORK"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 0 ]
	[ "${#lines[@]}" -eq 15 ]
	[ "${lines[11]}" = "blue_job_map: $CONFIG_DIR/blue-job-map.csv" ]
	[ "${lines[12]}" = "green_job_map: $CONFIG_DIR/green-job-map.csv" ]
}

# ---- 2 キーに場所を書く ----

@test "validate-config_sh_--feature-flagでblueに絶対パスgreenにサブディレクトリの相対パスを書き実体がある場合_それぞれの決めた場所をstdoutに出し未知キーのwarnを出さないこと" {
	# Arrange(固定の名前のファイルは置かない。作業ディレクトリは設定ファイルとは別で、同じ相対位置にファイルは無い)
	write_parallel_env
	write_job_map "$MAPS/blue-jobs.csv"
	write_job_map "$CONF/maps/green-jobs.csv"
	printf 'BLUE_JOB_MAP_CSV=%s\nGREEN_JOB_MAP_CSV=maps/green-jobs.csv\n' "$MAPS/blue-jobs.csv" >>"$ENV_FILE"
	cd "$WORK"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(絶対パスは値のまま。相対パスは 設定ファイルのあるディレクトリ + / + 値)
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 0 ]
	[ "${#lines[@]}" -eq 15 ]
	[ "${lines[11]}" = "blue_job_map: $MAPS/blue-jobs.csv" ]
	[ "${lines[12]}" = "green_job_map: $CONF/maps/green-jobs.csv" ]
}

@test "validate-config_sh_--feature-flagで2キーとも値が空の場合_固定の名前を使いerrorもwarnも出さないこと" {
	# Arrange
	write_parallel_env
	write_job_map "$CONFIG_DIR/blue-job-map.csv"
	write_job_map "$CONFIG_DIR/green-job-map.csv"
	printf 'BLUE_JOB_MAP_CSV=\nGREEN_JOB_MAP_CSV=\n' >>"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(値が空は、キーが無いときと同じ)
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 0 ]
	[ "${lines[11]}" = "blue_job_map: $CONFIG_DIR/blue-job-map.csv" ]
	[ "${lines[12]}" = "green_job_map: $CONFIG_DIR/green-job-map.csv" ]
}

@test "validate-config_sh_--feature-flagでoffのslotに実体の無い相対パスの場所を書いた場合_解決も検査もせずblue_job_mapにハイフンを出して終了コード0であること" {
	# Arrange
	write_green_only_env
	write_job_map "$CONFIG_DIR/green-job-map.csv"
	printf 'BLUE_JOB_MAP_CSV=./no-such/blue-jobs.csv\n' >>"$ENV_FILE"
	cd "$WORK"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(off の slot のキーは job map not found にも warn にもしない。解決後のパスも出さない)
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 0 ]
	[ "${lines[11]}" = "blue_job_map: -" ]
	[ "${lines[12]}" = "green_job_map: $CONFIG_DIR/green-job-map.csv" ]
}

# ---- 決めた場所に無い ----

@test "validate-config_sh_--feature-flagでmodeが列挙外のslotに書いた相対パスの場所に実体が無い場合_解決後のパスのjob map not foundを出すこと" {
	# Arrange(mode が列挙外の slot は off でないとして場所を決めて所在を検査する。固定の名前のファイルはあっても使わない)
	write_runner "$CONF/blue-runner.sh"
	write_runner "$CONF/green-runner.sh"
	write_job_map "$CONFIG_DIR/blue-job-map.csv"
	write_job_map "$CONFIG_DIR/green-job-map.csv"
	printf 'BLUE_MODE=parallel\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nBLUE_IMPL=blue-2.3.1\nGREEN_IMPL=green-1.4.0\nBLUE_RUNNER=%s\nGREEN_RUNNER=%s\nBLUE_JOB_MAP_CSV=../maps/blue-jobs.csv\n' \
		"$CONF/blue-runner.sh" "$CONF/green-runner.sh" >"$ENV_FILE"
	cd "$WORK"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(mode の違反 → 対応ジョブマップの順。.. を畳まない)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 3 ]
	[ "${stderr_lines[0]}" = "error: invalid value key=BLUE_MODE value=parallel" ]
	[ "${stderr_lines[1]}" = "hint: use foreground, background or off" ]
	[ "${stderr_lines[2]}" = "error: job map not found slot=blue map=$CONF/../maps/blue-jobs.csv" ]
}

@test "validate-config_sh_--feature-flagで場所の値にタブを含み実体が無い場合_map=に可視表記の解決後のパスを出すこと" {
	# Arrange(値の途中のタブは値の一部。出力規約「制御文字の表記」でタブは \t)
	write_green_only_env
	write_job_map "$CONFIG_DIR/green-job-map.csv"
	printf 'GREEN_JOB_MAP_CSV=./green\tjobs.csv\n' >>"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(生のタブをそのまま出さない)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: job map not found slot=green map=$CONF/./green\\tjobs.csv" ]
}

# ---- --verbose ----

@test "validate-config_sh_--feature-flag_--verboseで2キーを書いた有効な設定の場合_2キーのinfo行を出し未知キーのwarnを出さないこと" {
	# Arrange
	write_green_only_env
	write_job_map "$MAPS/green-jobs.csv"
	printf 'BLUE_JOB_MAP_CSV=\nGREEN_JOB_MAP_CSV=%s\n' "$MAPS/green-jobs.csv" >>"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE" --verbose

	# Assert(info 行はキーがファイルに初めて出た順。値が空のキーも含む。値は出さない)
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 7 ]
	[ "${stderr_lines[5]}" = "info: key loaded key=BLUE_JOB_MAP_CSV path: $ENV_FILE" ]
	[ "${stderr_lines[6]}" = "info: key loaded key=GREEN_JOB_MAP_CSV path: $ENV_FILE" ]
	[ "${lines[11]}" = "blue_job_map: -" ]
	[ "${lines[12]}" = "green_job_map: $MAPS/green-jobs.csv" ]
}
