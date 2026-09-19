#!/usr/bin/env bats
# UC fd678b04 × tier-facade: domain 層 CLI 出力フィールド(ui-design.md「出力フォーマット」)の単体テスト。
# 任意文字列の値(echo がオプションとして解釈する `-n` 等・空白を含む値)の境界を検証する。

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/cli_field.sh"
}

@test "cli_field_line_値に空白を含まない場合_key=value形式で出すこと" {
	# Arrange / Act
	run cli_field_line blue_impl blue-2.3.1

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "blue_impl=blue-2.3.1" ]
}

@test "cli_field_line_値に半角空白を含む場合_key: value形式で出すこと" {
	# Arrange / Act
	run cli_field_line green_impl "release 1"

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "green_impl: release 1" ]
}

@test "cli_field_line_値にタブを含む場合_key: value形式で出すこと" {
	# Arrange / Act
	run cli_field_line green_impl $'rel\t1'

	# Assert
	[ "$output" = $'green_impl: rel\t1' ]
}

@test "cli_field_line_値が空の場合_空値表記-で出すこと" {
	# Arrange / Act
	run cli_field_line blue_impl ""

	# Assert
	[ "$output" = "blue_impl=-" ]
}

@test "cli_field_line_値が-nの場合_echoのオプションと解釈せず値を保持すること" {
	# Arrange / Act
	run cli_field_line green_impl -n

	# Assert
	[ "$output" = "green_impl=-n" ]
}

@test "cli_field_line_値が-eの場合_echoのオプションと解釈せず値を保持すること" {
	# Arrange / Act
	run cli_field_line green_impl -e

	# Assert
	[ "$output" = "green_impl=-e" ]
}

@test "cli_field_line_値が-neの場合_echoのオプションと解釈せず値を保持すること" {
	# Arrange / Act
	run cli_field_line green_impl -ne

	# Assert
	[ "$output" = "green_impl=-ne" ]
}

@test "cli_path_field_line_パス値の場合_空白の有無によらずkey: value形式で出すこと" {
	# Arrange / Act
	run cli_path_field_line blue_runner /opt/relay-gate/runners/blue-runner.sh

	# Assert
	[ "$output" = "blue_runner: /opt/relay-gate/runners/blue-runner.sh" ]
}

@test "cli_path_field_line_値が空の場合_key: -で出すこと" {
	# Arrange / Act
	run cli_path_field_line blue_runner ""

	# Assert
	[ "$output" = "blue_runner: -" ]
}

@test "cli_field_display_value_値が-nの場合_そのまま出力すること" {
	# Arrange / Act
	run cli_field_display_value -n

	# Assert
	[ "$output" = "-n" ]
}
