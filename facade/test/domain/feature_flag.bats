#!/usr/bin/env bats
# S2 test-scaffold: UC fd678b04(feature flag を設定する)× tier-facade の最初の failing 単体テスト。
# 対象: domain 層の純粋関数(spec.md「計算ルール一覧」運用モード名 / foreground 数)。
# red baseline 規約: 実装ファイルの不在を module resolution error で fail させず、
# 「未実装」を理由とする明示的な fail にする(docs/dev-rules/test-strategy.md)。
# 実装先(S4 で作る): facade/src/domain/feature_flag.sh(source して関数を使う形式)

DOMAIN_SH="$BATS_TEST_DIRNAME/../../src/domain/feature_flag.sh"

# 実装ファイルが無ければ「未実装」を理由に fail する(S2 red baseline)
load_domain_or_fail() {
	if [ ! -f "$DOMAIN_SH" ]; then
		echo "not implemented (S2 test-scaffold): $DOMAIN_SH" >&2
		return 1
	fi
	# shellcheck source=/dev/null
	source "$DOMAIN_SH"
}

@test "derive_operation_mode_foreground-background-backgroundの場合_parallelを返すこと" {
	# Arrange
	load_domain_or_fail

	# Act
	run derive_operation_mode foreground background background

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "parallel" ]
}

@test "derive_operation_mode_off-foreground-offの場合_green_onlyを返すこと" {
	# Arrange
	load_domain_or_fail

	# Act
	run derive_operation_mode off foreground off

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "green_only" ]
}

@test "derive_operation_mode_background-foreground-backgroundの場合_next_gen_parallelを返すこと" {
	# Arrange
	load_domain_or_fail

	# Act
	run derive_operation_mode background foreground background

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "next_gen_parallel" ]
}

@test "derive_operation_mode_表に無い有効な組合せの場合_customを返すこと" {
	# Arrange
	load_domain_or_fail

	# Act
	run derive_operation_mode foreground off off

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "custom" ]
}

@test "feature_flag_display_value_値が-nの場合_echoのオプションと解釈せず値を保持すること" {
	# Arrange
	load_domain_or_fail

	# Act
	run feature_flag_display_value -n

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "-n" ]
}

@test "validate_feature_flag_modeの値が-eの場合_invalid valueの文言に値を保持すること" {
	# Arrange
	load_domain_or_fail
	BLUE_MODE=-e
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -ne 0 ]
	[ "${lines[0]}" = "error: invalid value key=BLUE_MODE value=-e" ]
}

@test "validate_feature_flag_両slotがforegroundの場合_foreground排他の違反行を出すこと" {
	# Arrange(条件: foreground slot 排他。違反は全件収集するため終了コードでなく出力行で判定)
	load_domain_or_fail
	BLUE_MODE=foreground
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	export BLUE_MODE GREEN_MODE RAPID_CROSSCHECK_MODE

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -ne 0 ]
	[[ "$output" == *"error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground"* ]]
}

@test "validate_feature_flag_foregroundが0個の場合_foreground排他の違反行を出すこと" {
	# Arrange
	load_domain_or_fail
	BLUE_MODE=background
	GREEN_MODE=off
	RAPID_CROSSCHECK_MODE=off
	BLUE_IMPL=b
	BLUE_RUNNER=/bin/sh

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -ne 0 ]
	[[ "$output" == *"error: foreground slot must be exactly one blue_mode=background green_mode=off"* ]]
}

@test "validate_feature_flag_modeが列挙外の場合_invalid valueとhintを続けて出すこと" {
	# Arrange
	load_domain_or_fail
	BLUE_MODE=parallel
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=maybe
	FEATURE_FLAG_PATH=ff.env

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -ne 0 ]
	[ "${lines[0]}" = "error: invalid value key=BLUE_MODE value=parallel" ]
	[ "${lines[1]}" = "hint: use foreground, background or off" ]
	[[ "$output" == *"error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe"* ]]
}

@test "validate_feature_flag_offでないslotの実装版が無い場合_option requiredを出すこと" {
	# Arrange
	load_domain_or_fail
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_RUNNER=/bin/sh
	FEATURE_FLAG_PATH=ff.env

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -ne 0 ]
	[ "$output" = "error: option required option=GREEN_IMPL path: ff.env" ]
}

@test "validate_feature_flag_runnerが相対パスの場合_path is not absoluteを出すこと" {
	# Arrange
	load_domain_or_fail
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_IMPL=g
	GREEN_RUNNER=bin/green.sh

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -ne 0 ]
	[ "$output" = "error: path is not absolute key=GREEN_RUNNER path=bin/green.sh" ]
}

@test "validate_feature_flag_runnerが存在しない場合_file not executableを出すこと" {
	# Arrange
	load_domain_or_fail
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_IMPL=g
	GREEN_RUNNER=/nonexistent/green.sh

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -ne 0 ]
	[ "$output" = "error: file not executable key=GREEN_RUNNER path=/nonexistent/green.sh" ]
}

@test "validate_feature_flag_速報がoffでなく速報runnerとworkerが不正な場合_両方の違反を出すこと" {
	# Arrange
	load_domain_or_fail
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=background
	GREEN_IMPL=g
	GREEN_RUNNER=/bin/sh
	RAPID_CROSSCHECK_WORKER=/opt/relay-gate/bin/missing-worker.sh
	FEATURE_FLAG_PATH=/etc/relay-gate/feature-flag.env

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -ne 0 ]
	[ "${lines[0]}" = "error: option required option=RAPID_CROSSCHECK_RUNNER path: /etc/relay-gate/feature-flag.env" ]
	[ "${lines[1]}" = "error: file not executable key=RAPID_CROSSCHECK_WORKER path=/opt/relay-gate/bin/missing-worker.sh" ]
}

@test "validate_feature_flag_速報がoffの場合_速報runnerとworkerを検証しないこと" {
	# Arrange
	load_domain_or_fail
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_IMPL=g
	GREEN_RUNNER=/bin/sh

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_feature_flag_確報制御キーがある場合_final crosscheck key is not allowedを出すこと" {
	# Arrange
	load_domain_or_fail
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_IMPL=g
	GREEN_RUNNER=/bin/sh
	FEATURE_FLAG_KEYS=(BLUE_MODE GREEN_MODE RAPID_CROSSCHECK_MODE GREEN_IMPL GREEN_RUNNER FINAL_CROSSCHECK_MODE)

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -ne 0 ]
	[ "$output" = "error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE" ]
}

@test "validate_feature_flag_9キー以外のキーがある場合_warnを出して違反にしないこと" {
	# Arrange
	load_domain_or_fail
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_IMPL=g
	GREEN_RUNNER=/bin/sh
	FEATURE_FLAG_KEYS=(BLUE_MODE CONFIG_VERSION)
	FEATURE_FLAG_PATH=ff.env

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "warn: unknown key key=CONFIG_VERSION path: ff.env" ]
}

# ---- S2 test-scaffold 再実行(spec event 20260917_100000 cycle2)で追加: 契約 config_files.feature-flag.env.validation_rules ----
# 拒否範囲 = キー名が FINAL_ で始まる全キー(接頭辞判定・大文字小文字を区別)。未知キー warn より先に判定し、同じキーに warn を出さない

@test "validate_feature_flag_FINAL_CROSSCHECK_で始まらないFINAL_キーがある場合_未知キーではなくfinal crosscheck key is not allowedを出すこと" {
	# Arrange
	load_domain_or_fail
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_IMPL=g
	GREEN_RUNNER=/bin/sh
	FEATURE_FLAG_KEYS=(BLUE_MODE GREEN_MODE RAPID_CROSSCHECK_MODE GREEN_IMPL GREEN_RUNNER FINAL_DB_CONN_REF)
	FEATURE_FLAG_PATH=ff.env

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -ne 0 ]
	[ "$output" = "error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF" ]
}

@test "validate_feature_flag_FINAL_で始まるキーが複数ある場合_該当キーごとに1行ずつerrorを出しwarnは出さないこと" {
	# Arrange
	load_domain_or_fail
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_IMPL=g
	GREEN_RUNNER=/bin/sh
	FEATURE_FLAG_KEYS=(BLUE_MODE GREEN_MODE RAPID_CROSSCHECK_MODE GREEN_IMPL GREEN_RUNNER FINAL_DB_CONN_REF FINAL_CROSSCHECK_MODE FINAL_POLL_LIMIT_SEC)
	FEATURE_FLAG_PATH=ff.env

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -ne 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[0]}" = "error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF" ]
	[ "${lines[1]}" = "error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE" ]
	[ "${lines[2]}" = "error: final crosscheck key is not allowed key=FINAL_POLL_LIMIT_SEC" ]
	[[ "$output" != *"warn: unknown key"* ]]
}

@test "validate_feature_flag_小文字のfinal_で始まるキーがある場合_接頭辞判定は大文字小文字を区別し未知キーwarnにすること" {
	# Arrange
	load_domain_or_fail
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_IMPL=g
	GREEN_RUNNER=/bin/sh
	FEATURE_FLAG_KEYS=(BLUE_MODE GREEN_MODE RAPID_CROSSCHECK_MODE GREEN_IMPL GREEN_RUNNER final_db_conn_ref)
	FEATURE_FLAG_PATH=ff.env

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "warn: unknown key key=final_db_conn_ref path: ff.env" ]
}

@test "validate_slot_runner_assignment_offでないslotのジョブマップが無い場合_job map not foundを出すこと" {
	# Arrange
	load_domain_or_fail

	# Act
	run validate_slot_runner_assignment green foreground /nonexistent/green-job-map.csv

	# Assert
	[ "$status" -ne 0 ]
	[ "$output" = "error: job map not found slot=green map=/nonexistent/green-job-map.csv" ]
}

@test "validate_slot_runner_assignment_offのslotの場合_ジョブマップを検証しないこと" {
	# Arrange
	load_domain_or_fail

	# Act
	run validate_slot_runner_assignment blue off /nonexistent/blue-job-map.csv

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}
