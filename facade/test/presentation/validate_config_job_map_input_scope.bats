#!/usr/bin/env bats
# UC eff24f55 × tier-facade: presentation 層 validate-config.sh --job-map の単体テスト(2026-11-16 の S2 再実行で追加)。
# 前回の完了(2026-10-06)より後に変わった仕様のうち、仕様の BDD が判定していない細部を判定する。
# 仕様: tier-facade.md「コマンド契約」(--job-map は feature-flag.env も BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV も読まない)、
#       「入力の守備範囲」(5,000 行または 8 MB を超えるファイルは受理。バイト・改行の検査の報告の規則)、
#       CLI 契約 config_input_rules.byte_checks / performance_target。
# 性能は目標値で、入力の制限でも合否の検査でもない。ここでは所要時間を判定しない(大きさで結果が変わらないことだけを見る)。
# エントリポイント(bin/validate-config.sh)経由で実プロセスとして起動する。I/O 境界は実ファイル(一時ディレクトリ)。
# stdout と stderr を分けて判定するため `run --separate-stderr`(bats 1.5 以上)を使う。
bats_require_minimum_version 1.5.0

HEADER_5='job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../bin/validate-config.sh"
	MAP="$BATS_TEST_TMPDIR/map.csv"
	CONFIG_DIR="$BATS_TEST_TMPDIR/conf"
	mkdir "$CONFIG_DIR"
}

# 渡すパスのジョブマップ(データ行 1 行)
write_passed_map() {
	{
		printf '%s\n' "$HEADER_5"
		printf '%s\n' 'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",0'
	} >"$MAP"
}

# feature flag に書く場所のジョブマップ(データ行 3 行。渡すパスのジョブマップと行数で区別する)
write_flag_map() {
	{
		printf '%s\n' "$HEADER_5"
		printf '%s\n' 'JOB101,/var/app/work,/opt/app/bin/job101.sh,"[]",0'
		printf '%s\n' 'JOB102,/var/app/work,/opt/app/bin/job102.sh,"[]",0'
		printf '%s\n' 'JOB103,/var/app/work,/opt/app/bin/job103.sh,"[]",0'
	} >"$1"
}

# ---- --job-map は feature-flag.env もジョブマップの場所の 2 キーも読まない ----

@test "validate-config_sh_--job-mapでfeature-flag_envにBLUE_JOB_MAP_CSVとGREEN_JOB_MAP_CSVがある場合_渡したパスのジョブマップを検証してrows=1を出すこと" {
	# Arrange(2 キーは絶対パスと相対パス。どちらの場所にも有効な 3 行のジョブマップがある)
	mkdir "$CONFIG_DIR/maps"
	write_flag_map "$BATS_TEST_TMPDIR/blue-jobs.csv"
	write_flag_map "$CONFIG_DIR/maps/green-jobs.csv"
	{
		printf 'BLUE_JOB_MAP_CSV=%s\n' "$BATS_TEST_TMPDIR/blue-jobs.csv"
		printf '%s\n' 'GREEN_JOB_MAP_CSV=maps/green-jobs.csv'
	} >"$CONFIG_DIR/feature-flag.env"
	write_passed_map

	# Act
	RELAY_GATE_CONFIG_DIR="$CONFIG_DIR" run --separate-stderr "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[0]}" = "map_path: $MAP" ]
	[ "${lines[1]}" = "rows=1" ]
	[ "${lines[2]}" = "map_version=-" ]
	[ -z "$stderr" ]
}

@test "validate-config_sh_--job-mapでfeature-flag_envに書いた場所にジョブマップが無い場合_job map not foundを出さず渡したパスを検証して終了コード0であること" {
	# Arrange(書いた場所にも、固定の名前にもジョブマップが無い)
	{
		printf 'BLUE_JOB_MAP_CSV=%s\n' "$BATS_TEST_TMPDIR/missing/blue-jobs.csv"
		printf '%s\n' 'GREEN_JOB_MAP_CSV=missing/green-jobs.csv'
	} >"$CONFIG_DIR/feature-flag.env"
	write_passed_map

	# Act
	RELAY_GATE_CONFIG_DIR="$CONFIG_DIR" run --separate-stderr "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[1]}" = "rows=1" ]
	[ -z "$stderr" ]
}

@test "validate-config_sh_--job-mapでfeature-flag_envが形式から外れている場合_feature-flag_envの違反を出さず渡したパスを検証して終了コード0であること" {
	# Arrange(NUL バイト・KEY=VALUE でない行・同じキーの重複。--feature-flag なら終了コード 2 になる内容)
	{
		printf 'BLUE_JOB_MAP_CSV=/x\000y\n'
		printf '%s\n' 'broken line'
		printf '%s\n' 'GREEN_JOB_MAP_CSV=a.csv'
		printf '%s\n' 'GREEN_JOB_MAP_CSV=b.csv'
	} >"$CONFIG_DIR/feature-flag.env"
	write_passed_map

	# Act
	RELAY_GATE_CONFIG_DIR="$CONFIG_DIR" run --separate-stderr "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "map_path: $MAP" ]
	[ "${lines[1]}" = "rows=1" ]
	[ -z "$stderr" ]
}

@test "validate-config_sh_--job-mapで渡したパスに違反がありfeature-flag_envに書いた場所が有効な場合_渡したパスの違反で終了コード2であること" {
	# Arrange(feature flag に書いた場所は有効。渡すパスは hang_detect_limit_minutes が不正)
	write_flag_map "$BATS_TEST_TMPDIR/blue-jobs.csv"
	printf 'BLUE_JOB_MAP_CSV=%s\n' "$BATS_TEST_TMPDIR/blue-jobs.csv" >"$CONFIG_DIR/feature-flag.env"
	{
		printf '%s\n' "$HEADER_5"
		printf '%s\n' 'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",60m'
	} >"$MAP"

	# Act
	RELAY_GATE_CONFIG_DIR="$CONFIG_DIR" run --separate-stderr "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=60m" ]
}

# ---- バイト・改行の検査の報告の規則(config_input_rules.byte_checks) ----

@test "validate-config_sh_--job-mapで契約の例と同じ4行のバイト違反の場合_8行を行番号の昇順と表の順で出しhintを最後のCRの次に出すこと" {
	# Arrange(byte_checks.example と同じ並び: 1 行目 BOM + CRLF / 2 行目 NUL + 不正な UTF-8 + 行末 CR / 3 行目 行末 CR / 4 行目 NUL)
	{
		printf '\357\273\277%s\r\n' "$HEADER_5"
		printf 'J\0001,/w\377,/s,"[]",60\r\n'
		printf 'J3,/w,/s,"[]",60\r\n'
		printf 'J\0004,/w,/s,"[]",60\n'
	} >"$MAP"

	# Act
	run --separate-stderr "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 8 ]
	[ "${stderr_lines[0]}" = "error: byte order mark is not allowed line=1 path: $MAP" ]
	[ "${stderr_lines[1]}" = "error: carriage return is not allowed line=1 path: $MAP" ]
	[ "${stderr_lines[2]}" = "error: nul byte is not allowed line=2 path: $MAP" ]
	[ "${stderr_lines[3]}" = "error: encoding is not utf-8 line=2 path: $MAP" ]
	[ "${stderr_lines[4]}" = "error: carriage return is not allowed line=2 path: $MAP" ]
	[ "${stderr_lines[5]}" = "error: carriage return is not allowed line=3 path: $MAP" ]
	[ "${stderr_lines[6]}" = "hint: use LF line endings" ]
	[ "${stderr_lines[7]}" = "error: nul byte is not allowed line=4 path: $MAP" ]
}

@test "validate-config_sh_--job-mapで同じ行にCRが2個とNULが2個ある場合_種類ごとに1行だけ出すこと" {
	# Arrange(2 行目: セル内の CR と行末の CR、NUL が 2 個。byte_checks.order: 同じ行の同じ種類は 1 行)
	{
		printf '%s\n' "$HEADER_5"
		printf 'J\0001\000,/w\r,/s,"[]",60\r\n'
	} >"$MAP"

	# Act
	run --separate-stderr "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 3 ]
	[ "${stderr_lines[0]}" = "error: nul byte is not allowed line=2 path: $MAP" ]
	[ "${stderr_lines[1]}" = "error: carriage return is not allowed line=2 path: $MAP" ]
	[ "${stderr_lines[2]}" = "hint: use LF line endings" ]
}

@test "validate-config_sh_--job-mapと--verboseでバイト違反とヘッダー以降の違反が両方ある場合_バイト違反の行だけを出して以降の検査をしないこと" {
	# Arrange(必須列 script が無いヘッダー・未知列・クォート不正・列数不一致・job_id の重複があり、5 行目に行末 CR が 1 個ある。
	#         byte_checks.stop: 第 1 段の error 行と hint だけを出して止める)
	{
		printf '%s\n' 'job_id,work_dir,fixed_params,hang_detect_limit_minutes,impl_version'
		printf '%s\n' 'J1,/w,"[""a""],60,x'
		printf '%s\n' 'J2,/w'
		printf '%s\n' 'J3,/w,"[]",60,x'
		printf 'J3,/w,"[]",60,x\r\n'
	} >"$MAP"

	# Act
	run --separate-stderr "$SCRIPT" --job-map "$MAP" --verbose

	# Assert(warn: unknown column も info: resolved も出ない)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: carriage return is not allowed line=5 path: $MAP" ]
	[ "${stderr_lines[1]}" = "hint: use LF line endings" ]
}

# ---- 5,000 行または 8 MB を超えるファイルは受理する(大きさを理由に拒否・警告しない) ----

# bats test_tags=heavy
@test "validate-config_sh_--job-mapでデータ行が5001行の場合_大きさについての行を出さず終了コード0でrows=5001を出すこと" {
	# Arrange(性能の目標値の条件(5,000 行以内)を 1 行超える。所要時間は判定しない)
	{
		printf '%s\n' "$HEADER_5"
		index=1
		while [ "$index" -le 5001 ]; do
			printf 'JOB%05d,/w,/s,"[]",60\n' "$index"
			index=$((index + 1))
		done
	} >"$MAP"

	# Act
	run --separate-stderr "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[0]}" = "map_path: $MAP" ]
	[ "${lines[1]}" = "rows=5001" ]
	[ "${lines[2]}" = "map_version=-" ]
	[ -z "$stderr" ]
}

# bats test_tags=heavy
@test "validate-config_sh_--job-mapで5000行を超えた先の行に違反がある場合_5000行以内と同じ規則でその行のerrorを出して終了コード2であること" {
	# Arrange(5,001 件目のデータ行 = 物理 5002 行目の hang_detect_limit_minutes が不正。大きさで検証の結果を変えない)
	{
		printf '%s\n' "$HEADER_5"
		index=1
		while [ "$index" -le 5000 ]; do
			printf 'JOB%05d,/w,/s,"[]",60\n' "$index"
			index=$((index + 1))
		done
		printf '%s\n' 'JOB05001,/w,/s,"[]",60m'
	} >"$MAP"

	# Act
	run --separate-stderr "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: hang_detect_limit_minutes is not a non-negative integer line=5002 job_id=JOB05001 value=60m" ]
}

# bats test_tags=heavy
@test "validate-config_sh_--job-mapでファイルが8MBを超える場合_大きさについての行を出さず終了コード0でrows=1を出すこと" {
	# Arrange(1 MiB のコメント行 9 行 + データ行 1 行。性能の目標値の条件(8 MB 以内)を超える。所要時間は判定しない)
	{
		printf '%s\n' "$HEADER_5"
		index=1
		while [ "$index" -le 9 ]; do
			printf '# '
			head -c 1048576 /dev/zero | tr '\0' 'x'
			printf '\n'
			index=$((index + 1))
		done
		printf '%s\n' 'J1,/w,/s,"[]",60'
	} >"$MAP"
	size="$(wc -c <"$MAP")"
	[ "$size" -gt 8388608 ]

	# Act
	run --separate-stderr "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[0]}" = "map_path: $MAP" ]
	[ "${lines[1]}" = "rows=1" ]
	[ "${lines[2]}" = "map_version=-" ]
	[ -z "$stderr" ]
}
