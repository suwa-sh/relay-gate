#!/usr/bin/env bats
# UC 7c41c7cd × tier-facade: validate-config.sh --feature-flag の対応ジョブマップの所在の検査で、「無い」と「あるが読めない」を
# 分けて報告することの単体テスト(CLI 契約 config_files.feature-flag.env.job_map_location.presence_report。spec-decision-043)。
# 2026-11-24 S2 scoped 再実行で追加。ジョブマップを読む 3 つの読み手(--feature-flag の所在の検査 / --job-map / slot runner)の文言を
# そろえる変更のうち、slot runner と --job-map は既に「読めない」を config file is not readable で報告している。
# --feature-flag の側は 2026-11-24 の S4 再実行で「読めない」を config file is not readable で報告するよう直した。
# 同じ規則の tier BDD は UC「feature flag を設定する」の tier-facade.md にあり、facade/features/configure-feature-flags.feature へ同じ再実行で転写した。
# エントリポイント経由で実プロセスとして起動する。I/O 境界は実ファイル(一時ディレクトリ)。

bats_require_minimum_version 1.5.0

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../bin/validate-config.sh"
	CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	CONF="$BATS_TEST_TMPDIR/conf"
	mkdir -p "$CONFIG_DIR" "$CONF"
	export RELAY_GATE_CONFIG_DIR="$CONFIG_DIR"
	ENV_FILE="$CONF/ff.env"
	BLUE_MAP="$CONFIG_DIR/blue-job-map.csv"
	GREEN_MAP="$CONFIG_DIR/green-job-map.csv"
}

# --help で runner-if-version=1 を返す runner スタブ
write_runner() {
	printf '%s\n' '#!/usr/bin/env bash' 'if [ "${1:-}" = "--help" ]; then echo "runner-if-version=1"; exit 0; fi' 'exit 6' >"$1"
	chmod +x "$1"
}

write_job_map() {
	printf 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\n' >"$1"
}

# 有効な並行稼働設定(9 キー)。ジョブマップは置かない
write_parallel_env() {
	write_runner "$CONF/blue-runner.sh"
	write_runner "$CONF/green-runner.sh"
	write_runner "$CONF/rapid-runner.sh"
	write_runner "$CONF/rapid-worker.sh"
	printf 'BLUE_MODE=foreground\nGREEN_MODE=background\nRAPID_CROSSCHECK_MODE=background\nBLUE_IMPL=blue-2.3.1\nGREEN_IMPL=green-1.4.0\nBLUE_RUNNER=%s\nGREEN_RUNNER=%s\nRAPID_CROSSCHECK_RUNNER=%s\nRAPID_CROSSCHECK_WORKER=%s\n' \
		"$CONF/blue-runner.sh" "$CONF/green-runner.sh" "$CONF/rapid-runner.sh" "$CONF/rapid-worker.sh" >"$ENV_FILE"
}

@test "validate-config_sh_--feature-flagでblueのジョブマップがディレクトリでgreenが読み取り権限の無いファイルの場合_config file is not readableをblue_greenの順に出し終了コード2であること" {
	# Arrange(契約 presence_report の example と同じ組み合わせ。権限を無視して読める利用者(root)では成り立たないため確かめない)
	write_parallel_env
	mkdir "$BLUE_MAP"
	write_job_map "$GREEN_MAP"
	chmod 000 "$GREEN_MAP"
	if [ -r "$GREEN_MAP" ]; then
		skip "the test user can read a file without the read permission"
	fi

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: config file is not readable path: $BLUE_MAP" ]
	[ "${stderr_lines[1]}" = "error: config file is not readable path: $GREEN_MAP" ]
}

@test "validate-config_sh_--feature-flagでジョブマップがシンボリックリンクの場合_リンク先で無いか読めないかを判定し表示はリンクのパスのままであること" {
	# Arrange(blue はリンク先が読める通常のファイル = 違反なし、green はリンク先が無い = 無い)
	write_parallel_env
	write_job_map "$CONF/real-blue.csv"
	ln -s "$CONF/real-blue.csv" "$BLUE_MAP"
	ln -s "$CONF/no-such.csv" "$GREEN_MAP"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: job map not found slot=green map=$GREEN_MAP" ]
}

@test "validate-config_sh_--feature-flagでジョブマップがディレクトリへのリンクの場合_config file is not readableを出すこと" {
	# Arrange
	write_parallel_env
	write_job_map "$BLUE_MAP"
	mkdir "$CONF/a-directory"
	ln -s "$CONF/a-directory" "$GREEN_MAP"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: config file is not readable path: $GREEN_MAP" ]
}

@test "validate-config_sh_--feature-flagで必須キー欠落と読めないジョブマップと無いジョブマップがある場合_error_orderの3から6の順で6の中はblue_greenの順であること" {
	# Arrange(GREEN_IMPL を書かない。blue のジョブマップはディレクトリ、green は無い)
	write_runner "$CONF/blue-runner.sh"
	write_runner "$CONF/green-runner.sh"
	printf 'BLUE_MODE=foreground\nGREEN_MODE=background\nRAPID_CROSSCHECK_MODE=off\nBLUE_IMPL=blue-1.0.0\nBLUE_RUNNER=%s\nGREEN_RUNNER=%s\n' \
		"$CONF/blue-runner.sh" "$CONF/green-runner.sh" >"$ENV_FILE"
	mkdir "$BLUE_MAP"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 3 ]
	[ "${stderr_lines[0]}" = "error: option required option=GREEN_IMPL path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "error: config file is not readable path: $BLUE_MAP" ]
	[ "${stderr_lines[2]}" = "error: job map not found slot=green map=$GREEN_MAP" ]
}
