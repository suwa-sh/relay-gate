#!/usr/bin/env bats
# UC fd678b04(feature flag を設定する)× tier-facade: repository 層 FeatureFlagConfig(env 読み込み)の単体テスト。
# I/O 境界(ファイル)は実体(一時ファイル)で検証する(docs/dev-rules/test-strategy.md)。

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/feature_flag.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/repository/feature_flag_config.sh"
	ENV_FILE="$BATS_TEST_TMPDIR/ff.env"
}

@test "feature_flag_config_load_9キーを書いた場合_同名のグローバル変数に値が載ること" {
	# Arrange
	printf 'BLUE_MODE=foreground\nGREEN_MODE=background\nRAPID_CROSSCHECK_MODE=background\nBLUE_IMPL=blue-2.3.1\nGREEN_IMPL=green-1.4.0\nBLUE_RUNNER=/opt/b.sh\nGREEN_RUNNER=/opt/g.sh\nRAPID_CROSSCHECK_RUNNER=/opt/r.sh\nRAPID_CROSSCHECK_WORKER=/opt/w.sh\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_MODE" = "foreground" ]
	[ "$GREEN_MODE" = "background" ]
	[ "$RAPID_CROSSCHECK_MODE" = "background" ]
	[ "$BLUE_IMPL" = "blue-2.3.1" ]
	[ "$GREEN_IMPL" = "green-1.4.0" ]
	[ "$BLUE_RUNNER" = "/opt/b.sh" ]
	[ "$GREEN_RUNNER" = "/opt/g.sh" ]
	[ "$RAPID_CROSSCHECK_RUNNER" = "/opt/r.sh" ]
	[ "$RAPID_CROSSCHECK_WORKER" = "/opt/w.sh" ]
	[ "${#FEATURE_FLAG_KEYS[@]}" -eq 9 ]
	[ "$FEATURE_FLAG_PATH" = "$ENV_FILE" ]
}

@test "feature_flag_config_load_コメント行と空行がある場合_無視されること" {
	# Arrange
	printf '# comment\n\n   \nBLUE_MODE=off\n  # indented comment\nGREEN_MODE=foreground\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_MODE" = "off" ]
	[ "$GREEN_MODE" = "foreground" ]
	[ "${#FEATURE_FLAG_KEYS[@]}" -eq 2 ]
}

@test "feature_flag_config_load_値がクォートされている場合_先頭末尾のクォートが除去されること" {
	# Arrange
	printf 'BLUE_IMPL="blue-2.3.1"\nGREEN_IMPL='"'"'green-1.4.0'"'"'\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_IMPL" = "blue-2.3.1" ]
	[ "$GREEN_IMPL" = "green-1.4.0" ]
}

@test "feature_flag_config_load_値にシェル変数展開やコマンド置換がある場合_展開せず文字列のまま載ること" {
	# Arrange
	printf 'BLUE_IMPL=$HOME/x\nGREEN_IMPL=$(echo injected)\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_IMPL" = '$HOME/x' ]
	[ "$GREEN_IMPL" = '$(echo injected)' ]
}

@test "feature_flag_config_load_9キー以外のキーがある場合_キー一覧には載るが変数化されないこと" {
	# Arrange(プロセス環境の PATH 等を env ファイルで上書きさせない)
	local path_before="$PATH"
	printf 'PATH=/evil\nCONFIG_VERSION=cfg-v1\nBLUE_MODE=off\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$PATH" = "$path_before" ]
	[ -z "${CONFIG_VERSION:-}" ]
	[ "${FEATURE_FLAG_KEYS[0]}" = "PATH" ]
	[ "${FEATURE_FLAG_KEYS[1]}" = "CONFIG_VERSION" ]
	[ "${FEATURE_FLAG_KEYS[2]}" = "BLUE_MODE" ]
}

@test "feature_flag_config_load_プロセス環境に同名変数がある場合_envファイルに無いキーは未設定に戻ること" {
	# Arrange
	export BLUE_IMPL="from-process-env"
	printf 'BLUE_MODE=off\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ -z "${BLUE_IMPL:-}" ]
	[ "$BLUE_MODE" = "off" ]
}

@test "feature_flag_config_load_同じキーが重複する場合_後の行の値が勝ちキー一覧には1回だけ載ること" {
	# Arrange
	printf 'BLUE_MODE=off\nBLUE_MODE=foreground\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_MODE" = "foreground" ]
	[ "${#FEATURE_FLAG_KEYS[@]}" -eq 1 ]
}

@test "feature_flag_config_load_値に=を含む場合_最初の=で分割されること" {
	# Arrange
	printf 'BLUE_IMPL=a=b=c\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_IMPL" = "a=b=c" ]
}

@test "feature_flag_config_load_CRLF改行と末尾改行なしの場合_値に制御文字が混ざらず最終行も読めること" {
	# Arrange
	printf 'BLUE_MODE=off\r\nGREEN_MODE=foreground' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_MODE" = "off" ]
	[ "$GREEN_MODE" = "foreground" ]
}

@test "feature_flag_config_load_キーだけで=が無い行の場合_値は空としてキー一覧に載ること" {
	# Arrange
	printf 'BLUE_MODE\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "${FEATURE_FLAG_KEYS[0]}" = "BLUE_MODE" ]
	[ -z "$BLUE_MODE" ]
}

@test "feature_flag_config_load_=が無いFINAL_で始まる行の場合_キー一覧に載り変数化されないこと" {
	# Arrange(拒否判定は domain の validate_feature_flag が FEATURE_FLAG_KEYS を見て行う)
	printf 'BLUE_MODE=off\nFINAL_DB_CONN_REF\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "${FEATURE_FLAG_KEYS[1]}" = "FINAL_DB_CONN_REF" ]
	[ -z "${FINAL_DB_CONN_REF:-}" ]
}
