#!/usr/bin/env bats
# UC fd678b04 × tier-facade: usecase 層 ValidateFeatureFlagQuery の単体テスト。
# 一時ディレクトリに env / runner スタブ / ジョブマップを実体で置いて検証する。

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/feature_flag.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/cli_field.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/repository/feature_flag_config.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/gateway/runner_probe.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/usecase/validate_feature_flag.sh"
	CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	mkdir -p "$CONFIG_DIR"
	ENV_FILE="$CONFIG_DIR/feature-flag.env"
	RUNNER="$BATS_TEST_TMPDIR/runner.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'if [ "${1:-}" = "--help" ]; then echo "runner-if-version=1"; exit 0; fi' 'exit 6' >"$RUNNER"
	chmod +x "$RUNNER"
	SILENT_RUNNER="$BATS_TEST_TMPDIR/silent.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$SILENT_RUNNER"
	chmod +x "$SILENT_RUNNER"
}

write_parallel_env() {
	cat >"$ENV_FILE" <<EOF
BLUE_MODE=foreground
GREEN_MODE=background
RAPID_CROSSCHECK_MODE=background
BLUE_IMPL=blue-2.3.1
GREEN_IMPL=green-1.4.0
BLUE_RUNNER=$RUNNER
GREEN_RUNNER=$RUNNER
RAPID_CROSSCHECK_RUNNER=$RUNNER
RAPID_CROSSCHECK_WORKER=$RUNNER
EOF
	touch "$CONFIG_DIR/blue-job-map.csv" "$CONFIG_DIR/green-job-map.csv"
}

# stdout と stderr を分けて取る(bats の run は両方を混ぜるため)
run_query() {
	STDOUT_FILE="$BATS_TEST_TMPDIR/out.txt"
	STDERR_FILE="$BATS_TEST_TMPDIR/err.txt"
	set +e
	validate_feature_flag_query "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
	QUERY_STATUS=$?
	set -e
}

@test "validate_feature_flag_query_有効な並行稼働設定の場合_終了コード0で15キー固定順のstdoutを出すこと" {
	# Arrange
	write_parallel_env

	# Act
	run_query "$ENV_FILE" "$CONFIG_DIR" false

	# Assert
	[ "$QUERY_STATUS" -eq 0 ]
	[ "$(wc -l <"$STDOUT_FILE" | tr -d ' ')" -eq 15 ]
	[ "$(sed -n 1p "$STDOUT_FILE")" = "config_path: $ENV_FILE" ]
	[ "$(sed -n 2p "$STDOUT_FILE")" = "blue_mode=foreground" ]
	[ "$(sed -n 3p "$STDOUT_FILE")" = "green_mode=background" ]
	[ "$(sed -n 4p "$STDOUT_FILE")" = "blue_impl=blue-2.3.1" ]
	[ "$(sed -n 5p "$STDOUT_FILE")" = "green_impl=green-1.4.0" ]
	[ "$(sed -n 6p "$STDOUT_FILE")" = "blue_runner: $RUNNER" ]
	[ "$(sed -n 7p "$STDOUT_FILE")" = "green_runner: $RUNNER" ]
	[ "$(sed -n 8p "$STDOUT_FILE")" = "rapid_crosscheck_mode=background" ]
	[ "$(sed -n 9p "$STDOUT_FILE")" = "rapid_crosscheck_runner: $RUNNER" ]
	[ "$(sed -n 10p "$STDOUT_FILE")" = "rapid_crosscheck_worker: $RUNNER" ]
	[ "$(sed -n 11p "$STDOUT_FILE")" = "operation_mode=parallel" ]
	[ "$(sed -n 12p "$STDOUT_FILE")" = "blue_job_map: $CONFIG_DIR/blue-job-map.csv" ]
	[ "$(sed -n 13p "$STDOUT_FILE")" = "green_job_map: $CONFIG_DIR/green-job-map.csv" ]
	[ "$(sed -n 14p "$STDOUT_FILE")" = "blue_runner_if_version=1" ]
	[ "$(sed -n 15p "$STDOUT_FILE")" = "green_runner_if_version=1" ]
	[ ! -s "$STDERR_FILE" ]
}

@test "validate_feature_flag_query_単独本番設定の場合_offのslotと速報の値が-になりgreen_onlyを返すこと" {
	# Arrange
	cat >"$ENV_FILE" <<EOF
BLUE_MODE=off
GREEN_MODE=foreground
RAPID_CROSSCHECK_MODE=off
GREEN_IMPL=green-1.4.0
GREEN_RUNNER=$RUNNER
EOF
	touch "$CONFIG_DIR/green-job-map.csv"

	# Act
	run_query "$ENV_FILE" "$CONFIG_DIR" false

	# Assert
	[ "$QUERY_STATUS" -eq 0 ]
	grep -qx 'blue_impl=-' "$STDOUT_FILE"
	grep -qx 'blue_runner: -' "$STDOUT_FILE"
	grep -qx 'rapid_crosscheck_runner: -' "$STDOUT_FILE"
	grep -qx 'rapid_crosscheck_worker: -' "$STDOUT_FILE"
	grep -qx 'blue_job_map: -' "$STDOUT_FILE"
	grep -qx 'blue_runner_if_version=-' "$STDOUT_FILE"
	grep -qx 'green_runner_if_version=1' "$STDOUT_FILE"
	grep -qx 'operation_mode=green_only' "$STDOUT_FILE"
}

@test "validate_feature_flag_query_実装版が-nの場合_echoのオプションと解釈せずgreen_impl=-nを出すこと" {
	# Arrange(BLUE_IMPL / GREEN_IMPL は任意の非空文字列)
	cat >"$ENV_FILE" <<EOF
BLUE_MODE=off
GREEN_MODE=foreground
RAPID_CROSSCHECK_MODE=off
GREEN_IMPL=-n
GREEN_RUNNER=$RUNNER
EOF
	touch "$CONFIG_DIR/green-job-map.csv"

	# Act
	run_query "$ENV_FILE" "$CONFIG_DIR" false

	# Assert
	[ "$QUERY_STATUS" -eq 0 ]
	[ "$(sed -n 5p "$STDOUT_FILE")" = "green_impl=-n" ]
	[ ! -s "$STDERR_FILE" ]
}

@test "validate_feature_flag_query_実装版が空白を含む場合_key: value形式で出すこと" {
	# Arrange(ui-design.md 出力フォーマット: 空白を含む値は `key: value`)
	cat >"$ENV_FILE" <<EOF
BLUE_MODE=off
GREEN_MODE=foreground
RAPID_CROSSCHECK_MODE=off
GREEN_IMPL=release 1
GREEN_RUNNER=$RUNNER
EOF
	touch "$CONFIG_DIR/green-job-map.csv"

	# Act
	run_query "$ENV_FILE" "$CONFIG_DIR" false

	# Assert
	[ "$QUERY_STATUS" -eq 0 ]
	[ "$(wc -l <"$STDOUT_FILE" | tr -d ' ')" -eq 15 ]
	[ "$(sed -n 5p "$STDOUT_FILE")" = "green_impl: release 1" ]
	[ "$(sed -n 4p "$STDOUT_FILE")" = "blue_impl=-" ]
}

@test "validate_feature_flag_query_ファイルが無い場合_終了コード2でconfig file not foundを出すこと" {
	# Arrange
	local missing="$BATS_TEST_TMPDIR/nonexistent.env"

	# Act
	run_query "$missing" "$CONFIG_DIR" false

	# Assert
	[ "$QUERY_STATUS" -eq 2 ]
	[ "$(cat "$STDERR_FILE")" = "error: config file not found path: $missing" ]
	[ ! -s "$STDOUT_FILE" ]
}

@test "validate_feature_flag_query_検証違反がある場合_終了コード2で違反を全件stderrに出しstdoutは空であること" {
	# Arrange(条件: 違反は全件まとめて報告される)
	printf 'BLUE_MODE=parallel\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=maybe\n' >"$ENV_FILE"

	# Act
	run_query "$ENV_FILE" "$CONFIG_DIR" false

	# Assert
	[ "$QUERY_STATUS" -eq 2 ]
	grep -qx 'error: invalid value key=BLUE_MODE value=parallel' "$STDERR_FILE"
	grep -qx 'error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe' "$STDERR_FILE"
	[ "$(grep -cx 'hint: use foreground, background or off' "$STDERR_FILE")" -eq 2 ]
	[ ! -s "$STDOUT_FILE" ]
}

@test "validate_feature_flag_query_offでないslotのジョブマップが無い場合_終了コード2でjob map not foundを出すこと" {
	# Arrange
	write_parallel_env
	rm "$CONFIG_DIR/green-job-map.csv"

	# Act
	run_query "$ENV_FILE" "$CONFIG_DIR" false

	# Assert
	[ "$QUERY_STATUS" -eq 2 ]
	grep -qx "error: job map not found slot=green map=$CONFIG_DIR/green-job-map.csv" "$STDERR_FILE"
}

@test "validate_feature_flag_query_runnerがhelpに応答しない場合_warnを出してif_versionは-で終了コード0であること" {
	# Arrange
	write_parallel_env
	sed -i.bak "s|^GREEN_RUNNER=.*|GREEN_RUNNER=$SILENT_RUNNER|" "$ENV_FILE"

	# Act
	run_query "$ENV_FILE" "$CONFIG_DIR" false

	# Assert
	[ "$QUERY_STATUS" -eq 0 ]
	grep -qx "warn: runner does not respond to --help slot=green runner=$SILENT_RUNNER" "$STDERR_FILE"
	grep -qx 'green_runner_if_version=-' "$STDOUT_FILE"
	grep -qx 'blue_runner_if_version=1' "$STDOUT_FILE"
}

@test "validate_feature_flag_query_未知キーがある場合_warnを出して終了コード0であること" {
	# Arrange
	write_parallel_env
	echo 'CONFIG_VERSION=cfg-v1' >>"$ENV_FILE"

	# Act
	run_query "$ENV_FILE" "$CONFIG_DIR" false

	# Assert
	[ "$QUERY_STATUS" -eq 0 ]
	[ "$(cat "$STDERR_FILE")" = "warn: unknown key key=CONFIG_VERSION path: $ENV_FILE" ]
}

# ---- S2 test-scaffold 再実行(spec event 20260917_100000 cycle2)で追加: 契約 config_files.feature-flag.env.validation_rules(FINAL_ 接頭辞) ----

@test "validate_feature_flag_query_有効な設定にFINAL_DB_CONN_REFを加えた場合_error1行だけで終了コード2相当のNGになりwarnは出ないこと" {
	# Arrange(spec.md E2E Scenario「FINAL_ で始まる確報設定のキーは未知キーではなく拒否される」)
	write_parallel_env
	echo 'FINAL_DB_CONN_REF=final-db' >>"$ENV_FILE"

	# Act
	run_query "$ENV_FILE" "$CONFIG_DIR" false

	# Assert
	[ "$QUERY_STATUS" -ne 0 ]
	grep -qx 'error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF' "$STDERR_FILE"
	[ "$(grep -c '^error:' "$STDERR_FILE")" -eq 1 ]
	! grep -q '^warn: unknown key key=FINAL_DB_CONN_REF' "$STDERR_FILE"
}

@test "validate_feature_flag_query_有効な設定に=の無いFINAL_DB_CONN_REF行を加えた場合_未知キーwarnではなくerror1行で拒否されること" {
	# Arrange(= の無い行はキーだけとして扱い、FINAL_ 接頭辞の拒否が未知キー warn より先に判定される)
	write_parallel_env
	echo 'FINAL_DB_CONN_REF' >>"$ENV_FILE"

	# Act
	run_query "$ENV_FILE" "$CONFIG_DIR" false

	# Assert
	[ "$QUERY_STATUS" -ne 0 ]
	[ "$(cat "$STDERR_FILE")" = "error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF" ]
	[ ! -s "$STDOUT_FILE" ]
}

@test "validate_feature_flag_query_verbose指定の場合_読み込んだキーをinfoでstderrに出すこと" {
	# Arrange
	write_parallel_env

	# Act
	run_query "$ENV_FILE" "$CONFIG_DIR" true

	# Assert
	[ "$QUERY_STATUS" -eq 0 ]
	grep -qx "info: key loaded key=BLUE_MODE path: $ENV_FILE" "$STDERR_FILE"
	[ "$(grep -c '^info: key loaded' "$STDERR_FILE")" -eq 9 ]
}

# ---- S2 test-scaffold 再実行(spec event 20260917_050000)で追加: 契約 cli-command-contract.yaml validate-config.sh runner_help_probe ----

@test "validate_feature_flag_query_runnerの版が1でない場合_応答しないとしてwarnを出しif_versionは-であること" {
	# Arrange(契約 runner_help_probe.no_response_criteria: 採用した runner-if-version= 行の値が 1 でない)
	local old_runner="$BATS_TEST_TMPDIR/old-runner.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'if [ "${1:-}" = "--help" ]; then echo "runner-if-version=2"; exit 0; fi' 'exit 6' >"$old_runner"
	chmod +x "$old_runner"
	write_parallel_env
	sed -i.bak "s|^GREEN_RUNNER=.*|GREEN_RUNNER=$old_runner|" "$ENV_FILE"

	# Act
	run_query "$ENV_FILE" "$CONFIG_DIR" false

	# Assert
	[ "$QUERY_STATUS" -eq 0 ]
	grep -qx "warn: runner does not respond to --help slot=green runner=$old_runner" "$STDERR_FILE"
	grep -qx 'green_runner_if_version=-' "$STDOUT_FILE"
	grep -qx 'blue_runner_if_version=1' "$STDOUT_FILE"
}
