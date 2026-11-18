#!/usr/bin/env bats
# UC 09730858(slot 実行モードを選択して runner を起動する)× tier-facade: domain/relay_gate_clock.sh の単体テスト。
# 対象: RELAY_GATE_NOW(UTC Z 付き)の解析とローカルタイムゾーンの表記(契約 conventions.datetime / shared_rules.run_id.timezone)。

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/relay_gate_clock.sh"
}

@test "relay_gate_clock_parse_utc_UTCのZ付きの日時の場合_epoch秒を返すこと" {
	# Arrange
	local value="2026-08-30T11:30:00Z"

	# Act
	relay_gate_clock_parse_utc "$value"

	# Assert(2026-08-30T11:30:00Z = 1788089400)
	[ "$RELAY_GATE_CLOCK_EPOCH" -eq 1788089400 ]
}

@test "relay_gate_clock_parse_utc_epochの起点とうるう日の場合_暦どおりのepoch秒を返すこと" {
	# Arrange / Act / Assert
	relay_gate_clock_parse_utc "1970-01-01T00:00:00Z"
	[ "$RELAY_GATE_CLOCK_EPOCH" -eq 0 ]
	relay_gate_clock_parse_utc "2024-02-29T23:59:59Z"
	[ "$RELAY_GATE_CLOCK_EPOCH" -eq 1709251199 ]
	relay_gate_clock_parse_utc "2000-03-01T00:00:00Z"
	[ "$RELAY_GATE_CLOCK_EPOCH" -eq 951868800 ]
}

@test "relay_gate_clock_parse_utc_形式が違うか暦に無い日時の場合_失敗すること" {
	# Arrange
	local value
	for value in "2026-08-30T11:30:00" "2026-08-30 11:30:00Z" "2026-08-30T11:30:00+09:00" "2026-02-29T00:00:00Z" \
		"2026-13-01T00:00:00Z" "2026-04-31T00:00:00Z" "2026-08-30T24:00:00Z" "2026-08-30T11:60:00Z" "x"; do
		# Act
		run relay_gate_clock_parse_utc "$value"

		# Assert
		[ "$status" -ne 0 ]
	done
}

@test "relay_gate_clock_format_run_id_time_TZがUTCの場合_指示子の無いyyyymmddThhmmssを返すこと" {
	# Arrange
	export TZ=UTC
	relay_gate_clock_parse_utc "2026-08-30T11:30:00Z"

	# Act
	relay_gate_clock_format_run_id_time "$RELAY_GATE_CLOCK_EPOCH"

	# Assert
	[ "$RELAY_GATE_CLOCK_TEXT" = "20260830T113000" ]
}

@test "relay_gate_clock_format_datetime_TZがAsia_Tokyoの場合_ローカル時刻の指示子の無い日時を返すこと" {
	# Arrange(TZ を変えたときの表記は、プロセスを起動し直して確かめる)
	local clock="$BATS_TEST_DIRNAME/../../src/domain/relay_gate_clock.sh"

	# Act
	run env TZ=Asia/Tokyo bash -c 'source "$1"; relay_gate_clock_parse_utc 2026-08-30T11:30:00Z; relay_gate_clock_format_datetime "$RELAY_GATE_CLOCK_EPOCH"; printf "%s\n" "$RELAY_GATE_CLOCK_TEXT"' _ "$clock"

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "2026-08-30T20:30:00" ]
}

@test "relay_gate_clock_now_RELAY_GATE_NOWが設定されている場合_その値を現在時刻にすること" {
	# Arrange
	export RELAY_GATE_NOW="2026-08-30T11:30:00Z"

	# Act
	relay_gate_clock_now

	# Assert
	[ "$RELAY_GATE_CLOCK_EPOCH" -eq 1788089400 ]
}

@test "relay_gate_clock_injection_is_valid_未設定と正しい値と不正な値の場合_未設定と正しい値だけを通すこと" {
	# Arrange / Act / Assert
	unset RELAY_GATE_NOW
	relay_gate_clock_injection_is_valid
	RELAY_GATE_NOW="2026-08-30T11:30:00Z"
	relay_gate_clock_injection_is_valid
	RELAY_GATE_NOW="2026-08-30T11:30:00"
	run relay_gate_clock_injection_is_valid
	[ "$status" -ne 0 ]
}
