#!/usr/bin/env bats
# UC fd678b04 × tier-facade: presentation 層 validate-config.sh の引数解析・終了コードの単体テスト。
# エントリポイント(bin/validate-config.sh)経由で実プロセスとして起動する。

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../bin/validate-config.sh"
	CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	mkdir -p "$CONFIG_DIR"
	export RELAY_GATE_CONFIG_DIR="$CONFIG_DIR"
}

@test "validate-config_sh_--helpの場合_usageをstdoutに出して終了コード0であること" {
	# Arrange / Act
	run "$SCRIPT" --help

	# Assert
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "usage: validate-config.sh "* ]]
}

@test "validate-config_sh_検証種別オプションが無い場合_option requiredで終了コード2であること" {
	# Arrange / Act
	run "$SCRIPT"

	# Assert
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "error: option required option=--feature-flag|--job-map|--crosscheck-job-map|--target-catalog" ]
}

@test "validate-config_sh_検証種別オプションを2つ指定した場合_排他違反で終了コード2であること" {
	# Arrange / Act
	run "$SCRIPT" --feature-flag a.env --job-map b.csv

	# Assert
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "error: options are exclusive options=--feature-flag,--job-map" ]
}

@test "validate-config_sh_--feature-flagの値が無い場合_option requiredで終了コード2であること" {
	# Arrange / Act
	run "$SCRIPT" --feature-flag

	# Assert
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "error: option required option=--feature-flag" ]
}

@test "validate-config_sh_未知オプションの場合_unknown optionで終了コード2であること" {
	# Arrange / Act
	run "$SCRIPT" --feature-flag a.env --foo

	# Assert
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "error: unknown option option=--foo" ]
}

@test "validate-config_sh_--key=value形式の場合_unknown optionで終了コード2であること" {
	# Arrange / Act
	run "$SCRIPT" --feature-flag=a.env

	# Assert
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "error: unknown option option=--feature-flag=a.env" ]
}

@test "validate-config_sh_--feature-flagでファイルが無い場合_config file not foundで終了コード2であること" {
	# Arrange / Act
	run "$SCRIPT" --feature-flag /nonexistent.env

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: config file not found path: /nonexistent.env" ]
}

@test "validate-config_sh_FINAL_で始まるキーが2つある場合_該当キーごとにerrorを出し終了コード2でwarnは出ないこと" {
	# Arrange(tier-facade.md ティア完了条件 Scenario「FINAL_ で始まるキーを未知キーではなく終了コード 2 で拒否する」。S2 cycle2 追加)
	runner="$BATS_TEST_TMPDIR/runner.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'if [ "${1:-}" = "--help" ]; then echo "runner-if-version=1"; exit 0; fi' 'exit 6' >"$runner"
	chmod +x "$runner"
	env_file="$BATS_TEST_TMPDIR/ff.env"
	printf '%s\n' "BLUE_MODE=foreground" "GREEN_MODE=background" "RAPID_CROSSCHECK_MODE=background" "BLUE_IMPL=blue-2.3.1" "GREEN_IMPL=green-1.4.0" "BLUE_RUNNER=$runner" "GREEN_RUNNER=$runner" "RAPID_CROSSCHECK_RUNNER=$runner" "RAPID_CROSSCHECK_WORKER=$runner" "FINAL_DB_CONN_REF=final-db" "FINAL_CROSSCHECK_MODE=background" >"$env_file"
	touch "$CONFIG_DIR/blue-job-map.csv" "$CONFIG_DIR/green-job-map.csv"

	# Act
	run "$SCRIPT" --feature-flag "$env_file"

	# Assert
	[ "$status" -eq 2 ]
	[[ "$output" == *"error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF"* ]]
	[[ "$output" == *"error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE"* ]]
	[[ "$output" != *"warn: unknown key"* ]]
}

@test "validate-config_sh_未実装の検証種別を指定した場合_終了コード6であること" {
	# Arrange / Act
	run "$SCRIPT" --target-catalog "$CONFIG_DIR/x.csv"

	# Assert
	[ "$status" -eq 6 ]
	[ "${lines[0]}" = "error: validation kind is not implemented option=--target-catalog" ]
}

@test "validate-config_sh_runnerが終了しない場合_待機上限で戻りwarnと版-で終了コード0であること" {
	# Arrange(--help に応答せず終了しない runner。CLI が NFR の 10 秒以内に戻ることを検証する)
	local runner="$BATS_TEST_TMPDIR/hang-runner.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'exec sleep 60' >"$runner"
	chmod +x "$runner"
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=g\nGREEN_RUNNER=%s\n' "$runner" >"$BATS_TEST_TMPDIR/ff.env"
	touch "$CONFIG_DIR/green-job-map.csv"
	local started
	started="$(date +%s)"

	# Act
	run "$SCRIPT" --feature-flag "$BATS_TEST_TMPDIR/ff.env"

	# Assert
	[ "$status" -eq 0 ]
	[ $(($(date +%s) - started)) -lt 10 ]
	[[ "$output" == *"warn: runner does not respond to --help slot=green runner=$runner"* ]]
	[[ "$output" == *"green_runner_if_version=-"* ]]
}

@test "validate-config_sh_RELAY_GATE_CONFIG_DIR未設定の場合_RELAY_GATE_HOME配下のconfigをジョブマップの既定に使うこと" {
	# Arrange
	unset RELAY_GATE_CONFIG_DIR
	export RELAY_GATE_HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$RELAY_GATE_HOME"
	local runner="$BATS_TEST_TMPDIR/runner.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'echo "runner-if-version=1"' >"$runner"
	chmod +x "$runner"
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=g\nGREEN_RUNNER=%s\n' "$runner" >"$BATS_TEST_TMPDIR/ff.env"

	# Act
	run "$SCRIPT" --feature-flag "$BATS_TEST_TMPDIR/ff.env"

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: job map not found slot=green map=$RELAY_GATE_HOME/config/green-job-map.csv" ]
}

# ---- S2 test-scaffold 再実行(spec event 20260917_050000)で追加: 契約 cli-command-contract.yaml validate-config.sh runner_help_probe ----

@test "validate-config_sh_runner問い合わせの準備に失敗した場合_runner probe failedで終了コード6でstdoutは空であること" {
	# Arrange(契約 runner_help_probe.preparation_failure: 応答を受ける一時ファイルの作成に失敗 → 終了コード 6。
	# 一時ファイルの置き場を存在しないディレクトリにして mktemp を失敗させる。runner 自体は正常に応答する)
	local runner="$BATS_TEST_TMPDIR/green-runner.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'if [ "${1:-}" = "--help" ]; then echo "runner-if-version=1"; exit 0; fi' 'exit 6' >"$runner"
	chmod +x "$runner"
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=g\nGREEN_RUNNER=%s\n' "$runner" >"$BATS_TEST_TMPDIR/ff.env"
	touch "$CONFIG_DIR/green-job-map.csv"
	local stdout_file="$BATS_TEST_TMPDIR/out.txt" stderr_file="$BATS_TEST_TMPDIR/err.txt"

	# Act
	set +e
	TMPDIR="$BATS_TEST_TMPDIR/nonexistent-tmp" "$SCRIPT" --feature-flag "$BATS_TEST_TMPDIR/ff.env" >"$stdout_file" 2>"$stderr_file"
	local exit_status=$?
	set -e

	# Assert
	[ "$exit_status" -eq 6 ]
	grep -q '^error: runner probe failed slot=green reason=' "$stderr_file"
	[ ! -s "$stdout_file" ]
}
