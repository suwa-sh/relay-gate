#!/usr/bin/env bats
# UC eff24f55 × tier-facade: presentation 層 validate-config.sh --job-map の単体テスト
# (S2 test-scaffold の red baseline を S4 で green にした。usecase 委譲は validate_config_job_map)。
# エントリポイント(bin/validate-config.sh)経由で実プロセスとして起動する。I/O 境界は実ファイル(一時ディレクトリ)。
# 仕様: tier-facade.md「コマンド契約 / 設定契約 / 出力契約」
# run は原則 stdout と stderr を結合して受ける(既存テストと同じ方式)。stdout が 0 行であることを確かめるテストだけ
# `run --separate-stderr`(bats 1.5 以上)で分けて受ける。
bats_require_minimum_version 1.5.0

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../bin/validate-config.sh"
	MAP="$BATS_TEST_TMPDIR/map.csv"
}

@test "validate-config_sh_--job-mapで有効な9列CSVの場合_終了コード0でmap_pathとrowsとmap_versionの3行だけを出すこと" {
	# Arrange
	{
		printf '%s\n' 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version'
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[""--mode"",""full""]",60,ssh-key-green,map-v3'
		printf '%s\n' 'JOB002,host-green-01,batch,/var/app/work,/opt/app/bin/job002.sh,"[]",0,ssh-key-green,map-v3'
	} >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert(違反・警告が無いので stderr は空。結合出力は stdout の 3 行だけ)
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[0]}" = "map_path: $MAP" ]
	[ "${lines[1]}" = "rows=2" ]
	[ "${lines[2]}" = "map_version=map-v3" ]
}

@test "validate-config_sh_--job-mapで同梱サンプルgreen-job-map_csv_exampleの場合_終了コード0でrows=2とmap_version=map-v3を出すこと" {
	# Arrange(tier-facade.md 設定契約のサンプル。同梱物が検証ルールからずれないことを確認する)
	sample="$BATS_TEST_DIRNAME/../../config/green-job-map.csv.example"

	# Act
	run "$SCRIPT" --job-map "$sample"

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[0]}" = "map_path: $sample" ]
	[ "${lines[1]}" = "rows=2" ]
	[ "${lines[2]}" = "map_version=map-v3" ]
}

@test "validate-config_sh_--job-mapでファイルが無い場合_config file not foundで終了コード2であること" {
	# Arrange / Act
	run "$SCRIPT" --job-map /nonexistent/map.csv

	# Assert
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "error: config file not found path: /nonexistent/map.csv" ]
}

@test "validate-config_sh_--job-mapでfixed_paramsがJSON配列でない場合_行番号付きerrorで終了コード2であること" {
	# Arrange
	{
		printf '%s\n' 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'JOB002,host-green-01,batch,/var/app/work,/opt/app/bin/job002.sh,"[]",60'
		printf '%s\n' 'JOB003,host-green-01,batch,/var/app/work,/opt/app/bin/job003.sh,"p1,p2",60'
	} >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "error: fixed_params is not a json array of strings line=3 job_id=JOB003 value=p1,p2" ]
}

@test "validate-config_sh_--job-mapと--verboseでローカル実行行の場合_host=-とuser=-とexec=localのinfo行を出すこと" {
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'JOB001,/var/app/work,/opt/app/bin/job001.sh,"[]",0'
	} >"$MAP"
	expected='info: resolved job_id=JOB001 host=- user=- exec=local work_dir=/var/app/work script=/opt/app/bin/job001.sh fixed_params=[] hang_detect_limit_minutes=0'

	# Act
	run "$SCRIPT" --job-map "$MAP" --verbose

	# Assert
	[ "$status" -eq 0 ]
	found=false
	for line in "${lines[@]}"; do
		if [ "$line" = "$expected" ]; then found=true; fi
	done
	[ "$found" = true ]
}

@test "validate-config_sh_--job-mapでfixed_paramsが20万文字の行の場合_10秒以内に終了コード0であること" {
	# Arrange(行の長さに上限は無い。nfr-grade B.2.1.1 の CLI 応答 10 秒目標。行の長さの 2 乗の時間をかけない)
	long_value="$(head -c 200000 /dev/zero | tr '\000' 'a')"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J1,/w,/s,"[""%s""]",60\n' "$long_value"
	} >"$MAP"
	SECONDS=0

	# Act
	run "$SCRIPT" --job-map "$MAP" --verbose

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[0]}" -gt 200000 ]
	[ "${lines[2]}" = "rows=1" ]
	[ "$SECONDS" -lt 10 ]
}

@test "validate-config_sh_--job-mapで二重化引用符とエスケープが密な4万文字の行の場合_10秒以内に終了コード0であること" {
	# Arrange(区切りが密な長い行。5000 要素の空文字列と、\n が 1 万個の要素)
	empty_elements="$(head -c 4999 /dev/zero | tr '\000' 'q' | sed 's/q/"""",/g')"
	escapes="$(head -c 10000 /dev/zero | tr '\000' 'q' | sed 's/q/\\n/g')"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J1,/w,/s,"[%s""""]",60\n' "$empty_elements"
		printf 'J2,/w,/s,"[""%s""]",60\n' "$escapes"
	} >"$MAP"
	SECONDS=0

	# Act
	run "$SCRIPT" --job-map "$MAP" --verbose

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[0]}" -gt 15000 ]
	[ "${#lines[1]}" -gt 20000 ]
	[ "${lines[3]}" = "rows=2" ]
	[ "$SECONDS" -lt 10 ]
}

# --- attempt 3 の独立検証 F-001 / F-002 / F-025 の再現(実プロセス。Verifier と同じ入力・同じ障害注入) ---

# 制御文字の生バイトを含むか(行末の改行は lines に含まれない)
has_control_byte() {
	local LC_ALL=C
	[[ "$1" == *[$'\001'-$'\037'$'\177']* ]]
}

@test "validate-config_sh_--job-mapでmap_versionにANSIエスケープがある場合_終了コード0でstdoutに生のESCを出さないこと" {
	# Arrange(F-001 の再現入力)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,map_version'
		printf 'J1,/w,/s,[],60,\033[31mred\033[0m\n'
	} >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[2]}" = 'map_version=\u001b[31mred\u001b[0m' ]
	! has_control_byte "${lines[0]}${lines[1]}${lines[2]}"
}

@test "validate-config_sh_--job-mapでファイル名に改行がある場合_stdoutが3行のままであること" {
	# Arrange(F-001 の再現入力)
	map="$BATS_TEST_TMPDIR"/$'ma\np.csv'
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$map"

	# Act
	run "$SCRIPT" --job-map "$map"

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[0]}" = "map_path: $BATS_TEST_TMPDIR"'/ma\np.csv' ]
	[ "${lines[1]}" = "rows=1" ]
	[ "${lines[2]}" = "map_version=-" ]
}

@test "validate-config_sh_未知のオプションに制御文字がある場合_unknown optionを1行で可視表記にして出すこと" {
	# Arrange / Act
	run "$SCRIPT" $'--bad\033[31m\nopt'

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = 'error: unknown option option=--bad\u001b[31m\nopt' ]
}

@test "validate-config_sh_余分な引数に制御文字がある場合_unexpected argumentを1行で可視表記にして出すこと" {
	# Arrange / Act
	run "$SCRIPT" $'extra\033\narg'

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = 'error: unexpected argument value=extra\u001b\narg' ]
}

@test "validate-config_sh_--job-mapでfixed_paramsに不正なUTF-8バイト列がある場合_encoding is not utf-8で終了コード2であること" {
	# Arrange(F-025 の再現入力。実バイト 0xff。spec reflux 20260921_100000: 入力の守備範囲は原因ごとの文言で拒否する)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,map_version'
		printf 'J1,/w,/s,"[""a\377b""]",60,v1\n'
	} >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP" --verbose

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: encoding is not utf-8 line=2 path: $MAP" ]
}

@test "validate-config_sh_--job-mapでsortが失敗しjob_idが重複する場合_成功サマリーを出さず終了コード6であること" {
	# Arrange(F-002 と同じ障害注入: 失敗する関数を export -f して実 CLI を起動する)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"
	sort() { return 1; }
	export -f sort

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert(config_input_rules.internal_failure: error 行 1 つだけ。path: に利用者のパス)
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=sort path: $MAP" ]
}

@test "validate-config_sh_--job-mapでtrが失敗しNULを含む行がある場合_成功サマリーを出さず終了コード6であること" {
	# Arrange(F-002 と同じ障害注入。commands= には実際に失敗したコマンド名だけを書く)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J\0001,/w,/s,[],60\n'
	} >"$MAP"
	tr() { return 1; }
	export -f tr

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=tr path: $MAP" ]
}

@test "validate-config_sh_--job-mapでsedが失敗し不正なUTF-8の行がある場合_成功サマリーを出さず終了コード6であること" {
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J1,/w\377,/s,[],60\n'
	} >"$MAP"
	sed() { return 1; }
	export -f sed

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=sed path: $MAP" ]
}

@test "validate-config_sh_--job-mapで2回目のsortだけが失敗する場合_duplicate job_idの行も成功サマリーも出さず終了コード6であること" {
	# Arrange(重複の報告順を決める 2 回目の sort。1 回目は本物の sort に委譲する)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"
	export SORT_CALLS_FILE="$BATS_TEST_TMPDIR/sort-calls"
	: >"$SORT_CALLS_FILE"
	sort() {
		printf 'x' >>"$SORT_CALLS_FILE"
		if [ "$(wc -c <"$SORT_CALLS_FILE")" -ge 2 ]; then
			return 1
		fi
		command sort "$@"
	}
	export -f sort

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=sort path: $MAP" ]
}

@test "validate-config_sh_--job-mapでsedが終了コード0のまま何も出力しない場合_NULを含む行を検証OKにせず終了コード6であること" {
	# Arrange(走査結果が空でも、走査完了の証跡が無ければ検証 OK にしない。想定外の出力も「補助コマンドの失敗」)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J\0001,/w,/s,[],60\n'
	} >"$MAP"
	sed() { command cat >/dev/null; }
	export -f sed

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=sed path: $MAP" ]
}

@test "validate-config_sh_--job-mapでsortが並べ替えずに入力を返す場合_離れた行の重複を検証OKにせず終了コード6であること" {
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J2,/w,/s,[],60'
		printf '%s\n' 'J1,/w,/s,[],60'
		printf '%s\n' 'J2,/w,/s,[],60'
	} >"$MAP"
	sort() { command cat; }
	export -f sort

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=sort path: $MAP" ]
}

@test "validate-config_sh_--job-mapで複製の削除rmが失敗する場合_成功サマリーを出さず終了コード6でerror行1つだけを出すこと" {
	# Arrange(attempt 5 F-002: 有効な CSV でも、複製が残ったまま検証 OK を返さない。rm は stderr に診断を出して失敗する)
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"
	rm() {
		printf '%s\n' 'rm: simulated I/O failure' >&2
		return 1
	}
	export -f rm

	# Act
	run "$SCRIPT" --job-map "$MAP"
	unset -f rm

	# Assert(stdout の map_path / rows / map_version も rm の診断も出ない)
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=rm path: $MAP" ]
	command rm -f -- "$TMPDIR"/relay-gate-*
}

@test "validate-config_sh_--job-mapでsortがstderrに診断を出して失敗する場合_契約のerror行1つだけを出すこと" {
	# Arrange(attempt 5 F-001: 補助コマンド自身の stderr を漏らさない)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"
	sort() {
		printf '%s\n' 'sort: simulated I/O failure' >&2
		return 1
	}
	export -f sort

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=sort path: $MAP" ]
}

@test "validate-config_sh_--job-mapでtrがstderrに診断を出して失敗する場合_契約のerror行1つだけを出すこと" {
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"
	tr() {
		printf '%s\n' 'tr: simulated I/O failure' >&2
		return 1
	}
	export -f tr

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=tr path: $MAP" ]
}

@test "validate-config_sh_--job-mapでsedがstderrに診断を出して失敗する場合_契約のerror行1つだけを出すこと" {
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"
	sed() {
		printf '%s\n' 'sed: simulated I/O failure' >&2
		return 1
	}
	export -f sed

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=sed path: $MAP" ]
}

@test "validate-config_sh_--job-mapで事前走査の直後に同じ行数のNULを含むファイルへmvで差し替えた場合_差し替え前の内容だけで検証すること" {
	# Arrange(attempt 4 F-001 の再現。通常の tr の直後に一時ファイルから mv で差し替える。tr の出力は改変しない)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/old,/s,[],60'
	} >"$MAP"
	export SWAP_NEXT="$BATS_TEST_TMPDIR/next.csv" SWAP_MAP="$MAP"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J\0002,/new,/s,[],60\n'
	} >"$SWAP_NEXT"
	tr() {
		command tr "$@"
		command mv "$SWAP_NEXT" "$SWAP_MAP"
	}
	export -f tr

	# Act
	run "$SCRIPT" --job-map "$MAP" --verbose

	# Assert(差し替えは起きている。検証結果は差し替え前の 1 行だけから作られ、両ファイルに無い J2 + /new の行を作らない)
	[ ! -e "$SWAP_NEXT" ]
	[ "$status" -eq 0 ]
	[[ "$output" == *"job_id=J1 "* ]]
	[[ "$output" == *"work_dir=/old "* ]]
	[[ "$output" != *"J2"* ]]
	[[ "$output" != *"/new"* ]]
	[[ "$output" == *"map_path: $MAP"* ]]
	[[ "$output" == *"rows=1"* ]]
}

@test "validate-config_sh_--job-mapで差し替え前のファイルにNULを含む行がある場合_事前走査の直後に正常なファイルへ差し替えてもnul byte is not allowedで終了コード2であること" {
	# Arrange(逆向きの差し替え。点検した内容と解析する内容が同じなら、差し替え前の NUL の行を拒否する)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J\0001,/old,/s,[],60\n'
	} >"$MAP"
	export SWAP_NEXT="$BATS_TEST_TMPDIR/next.csv" SWAP_MAP="$MAP"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J2,/new,/s,[],60'
	} >"$SWAP_NEXT"
	tr() {
		command tr "$@"
		command mv "$SWAP_NEXT" "$SWAP_MAP"
	}
	export -f tr

	# Act
	run "$SCRIPT" --job-map "$MAP" --verbose

	# Assert
	[ ! -e "$SWAP_NEXT" ]
	[ "$status" -eq 2 ]
	[ "$output" = "error: nul byte is not allowed line=2 path: $MAP" ]
}

@test "validate-config_sh_--job-mapで正常に検証を終えた場合_一時ファイルを残さず出力に一時ファイルのパスを出さないこと" {
	# Arrange(一時ディレクトリをテスト専用にして、残ったファイルを数える)
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP" --verbose

	# Assert
	[ "$status" -eq 0 ]
	[[ "$output" != *"$TMPDIR"* ]]
	[ -z "$(ls -A "$TMPDIR")" ]
}

@test "validate-config_sh_--job-mapで検証違反の場合_一時ファイルを残さないこと" {
	# Arrange
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J\0001,/w,/s,[],60\n'
	} >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: nul byte is not allowed line=2 path: $MAP" ]
	[ -z "$(ls -A "$TMPDIR")" ]
}

@test "validate-config_sh_--job-mapでtrが失敗した場合_一時ファイルを残さず終了コード6であること" {
	# Arrange
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes' >"$MAP"
	tr() { return 1; }
	export -f tr

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	[ "$output" = "error: internal command failed commands=tr path: $MAP" ]
	[ -z "$(ls -A "$TMPDIR")" ]
}

@test "validate-config_sh_--job-mapで検証中にTERMシグナルを受けた場合_一時ファイルを残さず成功サマリーを出さないこと" {
	# Arrange(tr の中から検証中のプロセス自身へ TERM を送る。$$ はパイプラインのサブシェルでも元のプロセス)
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"
	tr() {
		kill -TERM $$
		command tr "$@"
	}
	export -f tr

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert(TERM による終了は 128 + 15)
	[ "$status" -eq 143 ]
	[[ "$output" != *"rows="* ]]
	[ -z "$(ls -A "$TMPDIR")" ]
}

@test "validate-config_sh_--job-mapで入力の複製に失敗した場合_検証せずconfig snapshot failedとhintの2行と終了コード6で終えること" {
	# Arrange(複製に使う cat が失敗する。NUL を含む行を未点検のまま検証 OK にしない。
	#         config_input_rules.internal_failure: 複製の工程の失敗はコマンド名を問わず「入力の複製の失敗」)
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf 'J\0001,/w,/s,[],60\n'
	} >"$MAP"
	cat() { return 1; }
	export -f cat

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "error: config snapshot failed path: $MAP" ]
	[ "${lines[1]}" = "hint: check TMPDIR is writable" ]
	[ -z "$(ls -A "$TMPDIR")" ]
}

@test "validate-config_sh_--job-mapで一時ファイルを作れない場合_検証せずconfig snapshot failedとhintの2行と終了コード6で終えること" {
	# Arrange(mktemp が失敗する = 複製の工程「一時ファイルの作成」の失敗)
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"
	mktemp() { return 1; }
	export -f mktemp

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "error: config snapshot failed path: $MAP" ]
	[ "${lines[1]}" = "hint: check TMPDIR is writable" ]
}

# --- spec reflux 20260921_100000(config_input_rules / runtime_prerequisites / 制御文字の表記 / NFR 共通前提)で追加した red baseline ---
# S2 test-scaffold 再生成(scoped)。実装は S4 の再実行で追従する。

@test "validate-config_sh_--job-mapでTMPDIRが書き込めないディレクトリの場合_stdoutを出さずconfig snapshot failedとhintで終了コード6であること" {
	# Arrange(spec.md Scenario「検証器の内部障害は検証結果にならない」。存在しないディレクトリは書き込めない)
	export TMPDIR="$BATS_TEST_TMPDIR/no-such-dir"
	[ ! -e "$TMPDIR" ]
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"

	# Act(stdout を output に、stderr を stderr_lines に分けて受ける。bats の run は `2>file` を内側の 2>&1 で上書きするため
	#     --separate-stderr を使う。bats 1.5 以上)
	run --separate-stderr "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: config snapshot failed path: $MAP" ]
	[ "${stderr_lines[1]}" = "hint: check TMPDIR is writable" ]
}

@test "validate-config_sh_--job-mapで補助コマンドが失敗した場合_stdoutを出さずerror行は1行だけであること" {
	# Assert 対象: 終了コード 6 のとき検証 OK も違反も返さず、他の error / warn 行も出さない(違反行と未知列を含む入力で確認)
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,impl_version'
		printf '%s\n' 'J1,/w,/s,[],60m,x'
		printf '%s\n' 'J1,/w,/s,[],60,x'
	} >"$MAP"
	sort() { return 1; }
	export -f sort

	# Act(stdout を output に、stderr を stderr_lines に分けて受ける。bats 1.5 以上の --separate-stderr)
	run --separate-stderr "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: internal command failed commands=sort path: $MAP" ]
}

@test "validate-config_sh_--job-mapで先頭にBOMがある場合_byte order mark is not allowedで終了コード2でありheader mismatchを出さないこと" {
	# Arrange(実バイト EF BB BF)
	printf '\357\273\277job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\nJ1,/w,/s,"[]",60\n' >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: byte order mark is not allowed line=1 path: $MAP" ]
}

@test "validate-config_sh_--job-mapで全行がCRLFの場合_行ごとのcarriage return is not allowedとhintで終了コード2であること" {
	# Arrange
	printf 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes\r\nJ1,/w,/s,"[]",60\r\n' >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert(同種の違反は行ごとに 1 行。hint は 1 行。header mismatch へ流さない)
	[ "$status" -eq 2 ]
	[ "$(printf '%s\n' "${lines[@]}" | grep -c '^error: carriage return is not allowed line=1 path: ')" -eq 1 ]
	[ "$(printf '%s\n' "${lines[@]}" | grep -c '^error: carriage return is not allowed line=2 path: ')" -eq 1 ]
	[ "$(printf '%s\n' "${lines[@]}" | grep -c '^hint: use LF line endings$')" -eq 1 ]
	[[ "$output" != *"job map header mismatch"* ]]
}

@test "validate-config_sh_--job-mapでヘッダーにjob_id列が2つある場合_duplicate columnで終了コード2であること" {
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,job_id'
		printf '%s\n' 'J1,/w,/s,"[]",60,J1'
	} >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	[ "$output" = "error: duplicate column column=job_id path: $MAP" ]
}

@test "validate-config_sh_--job-mapで方針資料のWindows形式パスと非ASCIIのホスト名の行の場合_終了コード0で表示を1バイトも変えないこと" {
	# Arrange(方針資料のジョブマップ例。work_dir / script の形式は検査しない。バックスラッシュは置き換えない)
	{
		printf '%s\n' 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'TOMM0410010100,督促AP,saiken,G:\scripts,G:\scripts\xxx.bat,"[""param1"",""param2"",""param3""]",60'
	} >"$MAP"
	expected='info: resolved job_id=TOMM0410010100 host=督促AP user=saiken exec=ssh work_dir=G:\scripts script=G:\scripts\xxx.bat fixed_params=["param1","param2","param3"] hang_detect_limit_minutes=60'

	# Act
	run "$SCRIPT" --job-map "$MAP" --verbose

	# Assert
	[ "$status" -eq 0 ]
	found=false
	for line in "${lines[@]}"; do
		if [ "$line" = "$expected" ]; then found=true; fi
	done
	[ "$found" = true ]
	[[ "$output" != *"error:"* ]]
	[[ "$output" == *"rows=1"* ]]
}

@test "validate-config_sh_--job-mapで方針資料の相対パスの行の場合_終了コード0でrows=1であること" {
	# Arrange
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'TOMM0410010100,./beam-batches,./beam-batches/TOMM0410010100.sh,"[""param1"",""param2"",""param3""]",60'
	} >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 3 ]
	[ "${lines[1]}" = "rows=1" ]
}

@test "validate-config_sh_--job-mapで値にタブと列名にESCがある場合_可視表記で1行1事実のまま終了コード2であること" {
	# Arrange(spec.md Scenario「出力する値の制御文字は可視表記になる」。生の ESC・タブは出さない)
	{
		printf 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes,note\033[31m\n'
		printf 'JOB001,/w,/s,"[]",6\t0,x\n'
	} >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	[ "${#lines[@]}" -eq 2 ]
	! has_control_byte "$output"
	found_warn=false
	found_error=false
	for line in "${lines[@]}"; do
		[ "$line" = 'warn: unknown column column=note\u001b[31m path: '"$MAP" ] && found_warn=true
		[ "$line" = 'error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=6\t0' ] && found_error=true
	done
	[ "$found_warn" = true ]
	[ "$found_error" = true ]
}

@test "validate-config_sh_--job-mapで複製完了時点の一時ファイルの場合_relay-gate-で始まり_partで終わらず権限0600であること" {
	# Arrange(config_input_rules.snapshot: 作業名 .part へ書き終えてから最終名へ rename、0600。バイト点検の tr が動く時点で複製は完了している)
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	export SNAPSHOT_LIST="$BATS_TEST_TMPDIR/snapshot-list.txt"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"
	tr() {
		if [ ! -s "$SNAPSHOT_LIST" ]; then
			# 最初の tr 呼び出し時点の TMPDIR の一覧(ls -l の 1 列目 = 権限、最終列 = 名前。GNU / BSD 共通)
			command ls -l "$TMPDIR" | command grep -v '^total' >"$SNAPSHOT_LIST"
		fi
		command tr "$@"
	}
	export -f tr

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert(一時ファイルはちょうど 1 つ。名前と権限)
	[ "$status" -eq 0 ]
	[ "$(wc -l <"$SNAPSHOT_LIST" | tr -d ' ')" -eq 1 ]
	snapshot_perm="$(awk '{print substr($1, 1, 10)}' "$SNAPSHOT_LIST")"
	snapshot_name="$(awk '{print $NF}' "$SNAPSHOT_LIST")"
	[ "$snapshot_perm" = "-rw-------" ]
	[[ "$snapshot_name" == relay-gate-* ]]
	[[ "$snapshot_name" != *.part ]]
	[ -z "$(ls -A "$TMPDIR")" ]
}

@test "validate-config_sh_--job-mapで検証中にHUPシグナルを受けた場合_一時ファイルを残さず終了コード129であること" {
	# Arrange(tr の中から検証中のプロセス自身へ HUP を送る)
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"
	tr() {
		kill -HUP $$
		command tr "$@"
	}
	export -f tr

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert(HUP による終了は 128 + 1)
	[ "$status" -eq 129 ]
	[[ "$output" != *"rows="* ]]
	[ -z "$(ls -A "$TMPDIR")" ]
}

@test "validate-config_sh_--job-mapで検証中にINTシグナルを受けた場合_一時ファイルを残さず終了コード130であること" {
	# Arrange
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir "$TMPDIR"
	{
		printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'J1,/w,/s,[],60'
	} >"$MAP"
	tr() {
		kill -INT $$
		command tr "$@"
	}
	export -f tr

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert(INT による終了は 128 + 2)
	[ "$status" -eq 130 ]
	[[ "$output" != *"rows="* ]]
	[ -z "$(ls -A "$TMPDIR")" ]
}

@test "validate-config_sh_--job-mapでNFR共通前提の最悪条件5000行の場合_10秒以内に終了コード0であること" {
	# Arrange(nfr-grade B.1.1.2 の共通前提: ヘッダーを除いて 5,000 行、全列に値があり、job_id が全行一意、map_version が全行異なる。
	#         B.2.1.1: 内容によらず 10 秒以内。行数に比例する時間で処理できること(重複検査・版の集計を全組合せ比較にしない))
	{
		printf '%s\n' 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version'
		index=1
		while [ "$index" -le 5000 ]; do
			printf 'JOB%05d,host-green-%02d,batch,/var/app/work,/opt/app/bin/job%05d.sh,"[""--mode"",""full"",""--id"",""%d""]",60,ssh-key-green,map-v%d\n' "$index" "$((index % 100))" "$index" "$index" "$index"
			index=$((index + 1))
		done
	} >"$MAP"
	SECONDS=0

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert(版の混在は warn。違反は無いので終了コード 0)
	[ "$status" -eq 0 ]
	[[ "$output" == *"rows=5000"* ]]
	[[ "$output" == *"warn: mixed map_version values="* ]]
	[ "$SECONDS" -lt 10 ]
}

@test "validate-config_sh_--job-mapでNFR共通前提の最悪条件5000行にverboseを付けた場合_10秒以内に終了コード0であること" {
	# Arrange(--verbose は 1 行 1 job_id の info を出す。出力量が行数に比例しても 10 秒以内)
	{
		printf '%s\n' 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version'
		index=1
		while [ "$index" -le 5000 ]; do
			printf 'JOB%05d,host-green-%02d,batch,/var/app/work,/opt/app/bin/job%05d.sh,"[""--mode"",""full"",""--id"",""%d""]",60,ssh-key-green,map-v%d\n' "$index" "$((index % 100))" "$index" "$index" "$index"
			index=$((index + 1))
		done
	} >"$MAP"
	SECONDS=0

	# Act
	run "$SCRIPT" --job-map "$MAP" --verbose

	# Assert
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "${lines[@]}" | grep -c '^info: resolved job_id=')" -eq 5000 ]
	[ "$SECONDS" -lt 10 ]
}

# ---- S2 test-scaffold scoped 再生成(spec event 20260923_112000_feedback_impl_feedback_eff24f55_cycle2)----
# 変更点 1: 重複 job_id の error 行は job_id ごとに 1 行。lines= は初出行を含む出現順の全行番号。
# 変更点 2: credential_ref が参照名の形式に合わない値は理由を問わず同じ warn で受理し、値を診断に出さない。

@test "validate-config_sh_--job-mapで2行目と5行目のjob_idが重複する場合_初出行を含むlines=2,5の1行だけで終了コード2であること" {
	# Arrange
	{
		printf '%s\n' 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60'
		printf '%s\n' 'JOB002,host-green-01,batch,/var/app/work,/opt/app/bin/job002.sh,"[]",60'
		printf '%s\n' 'JOB003,host-green-01,batch,/var/app/work,/opt/app/bin/job003.sh,"[]",60'
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60'
	} >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	[ "$(printf '%s\n' "${lines[@]}" | grep -c 'duplicate job_id')" -eq 1 ]
	[ "$(printf '%s\n' "${lines[@]}" | grep -c -x 'error: duplicate job_id job_id=JOB001 lines=2,5')" -eq 1 ]
}

@test "validate-config_sh_--job-mapで2行目と3行目と4行目のjob_idが重複する場合_lines=2,3,4の1行だけで終了コード2であること" {
	# Arrange
	{
		printf '%s\n' 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes'
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60'
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60'
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60'
	} >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	[ "$(printf '%s\n' "${lines[@]}" | grep -c 'duplicate job_id')" -eq 1 ]
	[ "$(printf '%s\n' "${lines[@]}" | grep -c -x 'error: duplicate job_id job_id=JOB001 lines=2,3,4')" -eq 1 ]
}

@test "validate-config_sh_--job-mapと--verboseでcredential_refが空白を含む場合_同じwarnを1行出して受理し値を出さないこと" {
	# Arrange("/" も "BEGIN" も含まない。空白だけで参照名の形式に合わない)
	{
		printf '%s\n' 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version'
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60,ssh key green,map-v3'
	} >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP" --verbose

	# Assert
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "${lines[@]}" | grep -c -x 'warn: credential_ref looks like a secret or path line=2 job_id=JOB001')" -eq 1 ]
	[ "$(printf '%s\n' "${lines[@]}" | grep -c '^error:')" -eq 0 ]
	[[ "$output" == *"rows=1"* ]]
	[[ "$output" != *"ssh key green"* ]]
}

@test "validate-config_sh_--job-mapと--verboseでcredential_refがパス形式の場合_warnを出して受理しstdoutとstderrに値を出さないこと" {
	# Arrange
	{
		printf '%s\n' 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version'
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60,/home/batch/.ssh/id_green,map-v3'
	} >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP" --verbose

	# Assert
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "${lines[@]}" | grep -c -x 'warn: credential_ref looks like a secret or path line=2 job_id=JOB001')" -eq 1 ]
	[[ "$output" != *"/home/batch/.ssh/id_green"* ]]
}

@test "validate-config_sh_--job-mapでcredential_refが参照名の形式でBEGINを含む場合_同じwarnを1行出して受理し値を出さないこと" {
	# Arrange
	{
		printf '%s\n' 'job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,credential_ref,map_version'
		printf '%s\n' 'JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,"[]",60,BEGIN_KEY,map-v3'
	} >"$MAP"

	# Act
	run "$SCRIPT" --job-map "$MAP"

	# Assert
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "${lines[@]}" | grep -c -x 'warn: credential_ref looks like a secret or path line=2 job_id=JOB001')" -eq 1 ]
	[[ "$output" != *"BEGIN_KEY"* ]]
}
