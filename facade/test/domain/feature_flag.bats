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

# ---- S4 tier-impl(2026-11-13 attempt-5)で追加: 検証表を「キーの分類 → 未知キーの warn 行 → error 行」の 3 つの関数に分けた ----
# 行数に比例する件数の warn 行を usecase が溜めずに出すため(性能目標「5,000 行以内かつ 8 MB 以内を内容によらず 10 秒以内」)。
# validate_feature_flag は 3 つを順に呼ぶだけで、出す行と順は変えていない。

@test "feature_flag_classify_keys_9キーと未知キーとFINAL_で始まるキーが混ざる場合_ファイルに出た順の添字で未知キーと確報の制御キーに分けること" {
	# Arrange(9 キーと同じ長さの未知キー、9 キーの名前で始まる長いキー、小文字の final_ を混ぜる)
	load_domain_or_fail
	FEATURE_FLAG_KEYS=(BLUE_MODE FINAL_X ZZ GREEN_RUNNER FINAL_ final_y BLUE_MODX RAPID_CROSSCHECK_WORKER RAPID_CROSSCHECK_WORKER_2 FINAL)

	# Act
	feature_flag_classify_keys

	# Assert
	[ "${FEATURE_FLAG_UNKNOWN_KEY_INDEXES[*]}" = "2 5 6 8 9" ]
	[ "${FEATURE_FLAG_FORBIDDEN_KEY_INDEXES[*]}" = "1 4" ]
}

@test "feature_flag_classify_keys_キーが0個の場合_どちらの添字も空であること" {
	# Arrange
	load_domain_or_fail
	FEATURE_FLAG_KEYS=()
	FEATURE_FLAG_UNKNOWN_KEY_INDEXES=(9)
	FEATURE_FLAG_FORBIDDEN_KEY_INDEXES=(9)

	# Act
	feature_flag_classify_keys

	# Assert
	[ "${#FEATURE_FLAG_UNKNOWN_KEY_INDEXES[@]}" -eq 0 ]
	[ "${#FEATURE_FLAG_FORBIDDEN_KEY_INDEXES[@]}" -eq 0 ]
}

@test "validate_feature_flag_表示用のキー名の配列を渡した場合_その表記を未知キーのwarnと確報の制御キーのerrorに使うこと" {
	# Arrange(usecase は --verbose の info 行と同じ可視表記を使い回す)
	load_domain_or_fail
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_IMPL=g
	GREEN_RUNNER=/bin/sh
	FEATURE_FLAG_KEYS=(BLUE_MODE $'A\033' $'FINAL_\033')
	FEATURE_FLAG_PATH=ff.env
	# shellcheck disable=SC2034  # 名前で渡す
	local shown=(BLUE_MODE 'shown-A' 'shown-FINAL')

	# Act
	run validate_feature_flag shown

	# Assert
	[ "$status" -eq 1 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "warn: unknown key key=shown-A path: ff.env" ]
	[ "${lines[1]}" = "error: final crosscheck key is not allowed key=shown-FINAL" ]
}

@test "validate_feature_flag_報告行の出し先を配列にした場合_stdoutへ出さず同じ行を同じ順で配列に載せること" {
	# Arrange
	load_domain_or_fail
	BLUE_MODE=sideways
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_IMPL=g
	GREEN_RUNNER=/bin/sh
	FEATURE_FLAG_KEYS=(BLUE_MODE $'A\033' FINAL_Z)
	FEATURE_FLAG_PATH=ff.env
	local status_code=0
	FEATURE_FLAG_REPORT_SINK="$FEATURE_FLAG_REPORT_SINK_ARRAY"
	FEATURE_FLAG_REPORT_LINES=()

	# Act
	validate_feature_flag >"$BATS_TEST_TMPDIR/out.txt" || status_code=$?

	# Assert(列挙外の mode でも slot は off でない扱いのため、BLUE_IMPL と BLUE_RUNNER の必須も報告する。error 行どうしの順は固定しない)
	[ "$status_code" -eq 1 ]
	[ ! -s "$BATS_TEST_TMPDIR/out.txt" ]
	[ "${FEATURE_FLAG_REPORT_LINES[0]}" = 'warn: unknown key key=A\u001b path: ff.env' ]
	[ "${FEATURE_FLAG_REPORT_LINES[1]}" = "error: invalid value key=BLUE_MODE value=sideways" ]
	[ "${FEATURE_FLAG_REPORT_LINES[2]}" = "hint: use foreground, background or off" ]
	[ "${#FEATURE_FLAG_REPORT_LINES[@]}" -eq 6 ]
	[[ " ${FEATURE_FLAG_REPORT_LINES[*]} " == *"error: final crosscheck key is not allowed key=FINAL_Z"* ]]
}

@test "validate_feature_flag_制御文字だらけの長いキーが多数ある場合_まとめて作った可視表記でもキーごとの可視表記と同じ行を出すこと" {
	# Arrange(キーの合計が大きいと、可視表記を外部コマンドでまとめて作る。少数のときの表記と同じであること)
	load_domain_or_fail
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_IMPL=g
	GREEN_RUNNER=/bin/sh
	local body="" shown_body="" index
	for ((index = 0; index < 150; index++)); do
		body+=$'\001\033\177\xc2\x9b\t'
		shown_body+='\u0001\u001b\u007f\u009b\t'
	done
	FEATURE_FLAG_KEYS=(BLUE_MODE)
	for ((index = 0; index < 20; index++)); do
		FEATURE_FLAG_KEYS+=("U$index$body" "FINAL_$index$body")
	done
	FEATURE_FLAG_PATH=$'dir\033/ff.env'

	# Act
	run validate_feature_flag

	# Assert(未知キーの warn 20 行 → 確報の制御キーの error 20 行。どちらもファイルに出た順)
	[ "$status" -eq 1 ]
	[ "${#lines[@]}" -eq 40 ]
	[ "${lines[0]}" = "warn: unknown key key=U0$shown_body path: dir\\u001b/ff.env" ]
	[ "${lines[19]}" = "warn: unknown key key=U19$shown_body path: dir\\u001b/ff.env" ]
	[ "${lines[20]}" = "error: final crosscheck key is not allowed key=FINAL_0$shown_body" ]
	[ "${lines[39]}" = "error: final crosscheck key is not allowed key=FINAL_19$shown_body" ]
}

@test "feature_flag_is_defined_key_9キーより長いキーや9キーの名前で始まるキーの場合_9キーではないと判定すること" {
	# Arrange
	load_domain_or_fail

	# Act / Assert
	local key rejected=0
	feature_flag_is_defined_key RAPID_CROSSCHECK_WORKER
	feature_flag_is_defined_key BLUE_MODE
	for key in RAPID_CROSSCHECK_WORKERS BLUE_MODE_ "" blue_mode; do
		if ! feature_flag_is_defined_key "$key"; then
			rejected=$((rejected + 1))
		fi
	done
	[ "$rejected" -eq 4 ]
}

@test "validate_feature_flag_長いキーが多数あり可視表記をまとめて作るsedが失敗する場合_キーごとの置き換えで同じ行を出し検証表の結果を返すこと" {
	# Arrange(domain は終了コードを決めない。補助コマンドの失敗として止めるのは usecase。ここでは同じ行を返す)
	load_domain_or_fail
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_IMPL=g
	GREEN_RUNNER=/bin/sh
	local body="" shown_body="" index
	for ((index = 0; index < 150; index++)); do
		body+=$'\001\033'
		shown_body+='\u0001\u001b'
	done
	FEATURE_FLAG_KEYS=(BLUE_MODE)
	for ((index = 0; index < 20; index++)); do
		FEATURE_FLAG_KEYS+=("U$index$body")
	done
	FEATURE_FLAG_PATH=ff.env
	local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
	mkdir -p "$fake_bin"
	printf '%s\n' '#!/bin/sh' 'exit 1' >"$fake_bin/sed"
	chmod +x "$fake_bin/sed"
	PATH="$fake_bin:$PATH"

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 20 ]
	[ "${lines[0]}" = "warn: unknown key key=U0$shown_body path: ff.env" ]
	[ "${lines[19]}" = "warn: unknown key key=U19$shown_body path: ff.env" ]
}

# ---- S4 tier-impl(2026-11-13 attempt-5)で追加: 値を埋め込む報告行(大きな値は、出すときに可視表記を付ける) ----

@test "feature_flag_emit_value_line_出し先がstdoutの場合_値の表示を埋め込んだ1行を出し空の値は-にすること" {
	# Arrange
	load_domain_or_fail

	# Act
	run feature_flag_emit_value_line "error: invalid value key=BLUE_MODE value=" $'side\033ways'
	local one_value="$output"
	run feature_flag_emit_value_line "error: foreground slot must be exactly one blue_mode=" "" " green_mode=" $'o\tff'

	# Assert
	[ "$one_value" = 'error: invalid value key=BLUE_MODE value=side\u001bways' ]
	[ "$output" = 'error: foreground slot must be exactly one blue_mode=- green_mode=o\tff' ]
}

@test "feature_flag_emit_value_line_出し先が配列で値が小さい場合と大きい場合_溜めた行を出すとstdoutへ直接出した場合と同じバイト列になること" {
	# Arrange(大きな値(合計が FEATURE_FLAG_REPORT_DEFERRED_MIN_BYTES 以上)は元の値のまま控え、出すときに可視表記を付ける)
	load_domain_or_fail
	local big="" index
	for ((index = 0; index < 1200; index++)); do
		big+=$'v\033\xc2\x85 '
	done
	local direct="$BATS_TEST_TMPDIR/direct.txt" flushed="$BATS_TEST_TMPDIR/flushed.txt"
	emit_all() {
		feature_flag_emit "warn: first"
		feature_flag_emit_value_line "error: invalid value key=BLUE_MODE value=" "small"$'\033'
		feature_flag_emit_value_line "error: invalid value key=GREEN_MODE value=" "$big"
		feature_flag_emit "hint: use foreground, background or off"
		feature_flag_emit_value_line "error: foreground slot must be exactly one blue_mode=" "$big" " green_mode=" ""
		feature_flag_emit_value_line "error: foreground slot must be exactly one blue_mode=" "x" " green_mode=" "$big"
		feature_flag_emit "warn: last"
	}

	# Act
	emit_all >"$direct"
	FEATURE_FLAG_REPORT_SINK="$FEATURE_FLAG_REPORT_SINK_ARRAY"
	feature_flag_reset_report_lines
	emit_all >"$BATS_TEST_TMPDIR/none.txt"
	local line_count="${#FEATURE_FLAG_REPORT_LINES[@]}" deferred_count="${#FEATURE_FLAG_REPORT_VALUE_1[@]}"
	FEATURE_FLAG_REPORT_SINK="$FEATURE_FLAG_REPORT_SINK_STDOUT"
	feature_flag_flush_report_lines >"$flushed"

	# Assert(配列に溜めている間は何も出さない。7 行のうち大きな値を含む 3 行が後回し。出した後は配列が空)
	[ ! -s "$BATS_TEST_TMPDIR/none.txt" ]
	[ "$line_count" -eq 7 ]
	[ "$deferred_count" -eq 3 ]
	cmp "$direct" "$flushed"
	[ "$(wc -l <"$flushed" | tr -d ' ')" -eq 7 ]
	[ "$(sed -n '2p' "$flushed")" = 'error: invalid value key=BLUE_MODE value=small\u001b' ]
	local fifth expected_head='error: foreground slot must be exactly one blue_mode=v\u001b\u0085 v'
	fifth="$(sed -n '5p' "$flushed")"
	[ "${fifth:0:${#expected_head}}" = "$expected_head" ]
	[ "${fifth: -14}" = '  green_mode=-' ]
	[ "${#FEATURE_FLAG_REPORT_LINES[@]}" -eq 0 ]
	[ "${#FEATURE_FLAG_REPORT_VALUE_1[@]}" -eq 0 ]
}
