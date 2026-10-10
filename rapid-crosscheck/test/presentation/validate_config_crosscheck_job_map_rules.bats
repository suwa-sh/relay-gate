#!/usr/bin/env bats
# UC dcd8234d × tier-rapid-crosscheck: validate-config.sh --crosscheck-job-map の検証ルール・出力契約の単体テスト(S4 tier-impl 追加)。
# facade/bin/validate-config.sh を実プロセスとして起動し、一時ディレクトリの実ファイルで検証する(S2 の bats と同じ方式)。
# 仕様: tier-rapid-crosscheck.md「出力契約」「設定契約」「検証ルール一覧」「ティア完了条件(BDD)」/ spec.md「E2E 完了条件(BDD)」/
#       cli-command-contract.yaml commands[validate-config.sh].stdout / stderr、config_input_rules
# stdout と stderr を分けて判定するテストは、stderr をファイルへ逃がして実行する(bats の版に依存しない)。

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../../facade/bin/validate-config.sh"
	MAP="$BATS_TEST_TMPDIR/crosscheck-job-map.csv"
	CATALOG="$BATS_TEST_TMPDIR/target-catalog.csv"
	COMPARE="$BATS_TEST_TMPDIR/compare.sh"
	ERR="$BATS_TEST_TMPDIR/stderr.txt"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$COMPARE"
	chmod +x "$COMPARE"
	{
		printf '%s\n' 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling'
		printf '%s\n' 'v1,table,SALES_DAILY,key=sales_id,column=business_date'
		printf '%s\n' 'v1,file,/data/out/summary_{business_date}.tsv,-,filename'
	} >"$CATALOG"
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir -p "$TMPDIR"
}

HEADER='job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version'

write_declarations() {
	printf '%s\n' '# exit_code_contract=0:OK,3:NG,6:ERROR'
	printf '%s\n' "# target_catalog_path=$CATALOG"
	printf '%s\n' '# catalog_version=v1'
}

# 宣言 3 行 + ヘッダー + JOB001 / JOB002(tier BDD「妥当なジョブマップを検証する」と同じ構成。物理行 5 / 6)
write_valid_map() {
	{
		write_declarations
		printf '%s\n' "$HEADER"
		printf '%s\n' "JOB001,job,output.csv,$COMPARE,--blue {blue} --green {green},v1"
		printf '%s\n' "JOB002,job,summary.tsv,$COMPARE,--blue {blue} --green {green} --ignore-header,v1"
	} >"$MAP"
}

# stderr をファイルへ分けて実行する(status / output は stdout だけ)
run_split() {
	run env ERR="$ERR" bash -c '"$0" "$@" 2>"$ERR"' "$SCRIPT" "$@"
}

read_stderr_lines() {
	STDERR_LINES=()
	while IFS= read -r line; do
		STDERR_LINES+=("$line")
	done <"$ERR"
}

has_line() {
	local expected="$1" line
	shift
	for line in "$@"; do
		if [ "$line" = "$expected" ]; then return 0; fi
	done
	return 1
}

@test "validate-config_sh_--crosscheck-job-mapで妥当なジョブマップの場合_stderrが空でstdoutが7行であること" {
	# Arrange
	write_valid_map

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 7 ]
	[ "${lines[6]}" = "status=valid" ]
	[ ! -s "$ERR" ]
	[ -z "$(ls -A "$TMPDIR")" ]
}

@test "validate-config_sh_--crosscheck-job-mapでexit_code_contract宣言の値が固定文字列と異なる場合_declaration is invalidで終了コード2であること" {
	# Arrange
	write_valid_map
	sed -i.bak '1s/.*/# exit_code_contract=0:OK,1:NG/' "$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert(stdout は status=invalid / violations=1。exit_code_contract= は宣言の値をそのまま出す)
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: exit_code_contract declaration is invalid value=0:OK,1:NG path: $MAP" ]
	[ "${STDERR_LINES[1]}" = "hint: fix the rows above and rerun validate-config.sh --crosscheck-job-map $MAP" ]
	[ "${lines[5]}" = "exit_code_contract=0:OK,1:NG" ]
	[ "${lines[6]}" = "status=invalid" ]
	[ "${lines[7]}" = "violations=1" ]
}

@test "validate-config_sh_--crosscheck-job-mapでtarget_catalog_path宣言が無い場合_declaration not foundで参照解決は行わないこと" {
	# Arrange
	write_valid_map
	sed -i.bak '2d' "$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${#STDERR_LINES[@]}" -eq 2 ]
	[ "${STDERR_LINES[0]}" = "error: target_catalog_path declaration not found path: $MAP" ]
	[ "${lines[3]}" = "target_catalog_path: -" ]
	[ "${lines[7]}" = "violations=1" ]
}

@test "validate-config_sh_--crosscheck-job-mapでcatalog_versionがカタログに無い場合_target catalog reference unresolvedで終了コード2であること" {
	# Arrange
	write_valid_map
	sed -i.bak '3s/.*/# catalog_version=v9/' "$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: target catalog reference unresolved path=$CATALOG catalog_version=v9" ]
	[ "${lines[4]}" = "catalog_version=v9" ]
	[ "${lines[6]}" = "status=invalid" ]
}

@test "validate-config_sh_--crosscheck-job-mapでtarget_catalog_pathが存在しない場合_target catalog reference unresolvedであること" {
	# Arrange
	write_valid_map
	sed -i.bak "2s|.*|# target_catalog_path=$BATS_TEST_TMPDIR/missing.csv|" "$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: target catalog reference unresolved path=$BATS_TEST_TMPDIR/missing.csv catalog_version=v1" ]
}

@test "validate-config_sh_--crosscheck-job-mapで同じ宣言が2回ある場合_2回目をdeclaration is invalidにし初出の値を使うこと" {
	# Arrange
	write_valid_map
	printf '%s\n' '# catalog_version=v2' >>"$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: catalog_version declaration is invalid value=v2 path: $MAP" ]
	[ "${lines[4]}" = "catalog_version=v1" ]
}

@test "validate-config_sh_--crosscheck-job-mapでcompare_optionsに{green}が無い場合_line=5のmissing placeholderで終了コード2であること" {
	# Arrange(tier BDD「compare_options にプレースホルダが無い」の Then と同じ値)
	write_valid_map
	sed -i.bak "5s|.*|JOB001,job,output.csv,$COMPARE,--blue {blue},v1|" "$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: compare_options is missing {blue} or {green} line=5 job_id=JOB001 value=--blue {blue}" ]
}

@test "validate-config_sh_--crosscheck-job-mapでcompare_optionsが--fastの場合_value=--fastのmissing placeholderであること" {
	# Arrange(tier BDD の Given の値。Then の value= と一致しない点は issues/20261010_093000_tier-bdd-placeholder-scenario-given-then-mismatch.md)
	write_valid_map
	sed -i.bak "5s|.*|JOB001,job,output.csv,$COMPARE,--fast,v1|" "$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: compare_options is missing {blue} or {green} line=5 job_id=JOB001 value=--fast" ]
}

@test "validate-config_sh_--crosscheck-job-mapでcompare_commandが存在しない場合_not executableで終了コード2であること" {
	# Arrange
	write_valid_map
	sed -i.bak "5s|.*|JOB001,job,output.csv,/opt/compare/missing.sh,--blue {blue} --green {green},v1|" "$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: compare_command is not executable line=5 job_id=JOB001 value=/opt/compare/missing.sh" ]
}

@test "validate-config_sh_--crosscheck-job-mapで実行不可と列数不一致が1件ずつある場合_error2行とviolations=2で全件出すこと" {
	# Arrange(tier BDD「複数の違反を全件出力する」: JOB001 の compare_command が存在せず、JOB002 の列数が 5)
	write_valid_map
	sed -i.bak "5s|.*|JOB001,job,output.csv,/opt/compare/missing.sh,--blue {blue} --green {green},v1|" "$MAP"
	sed -i.bak "6s|.*|JOB002,job,summary.tsv,$COMPARE,--blue {blue} --green {green}|" "$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert(hint は最後の 1 行。stdout は 8 行)
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${#STDERR_LINES[@]}" -eq 3 ]
	[ "${STDERR_LINES[0]}" = "error: compare_command is not executable line=5 job_id=JOB001 value=/opt/compare/missing.sh" ]
	[ "${STDERR_LINES[1]}" = "error: column count mismatch line=6 expected=6 actual=5" ]
	[ "${STDERR_LINES[2]}" = "hint: fix the rows above and rerun validate-config.sh --crosscheck-job-map $MAP" ]
	[ "${#lines[@]}" -eq 8 ]
	[ "${lines[2]}" = "rows=2" ]
	[ "${lines[6]}" = "status=invalid" ]
	[ "${lines[7]}" = "violations=2" ]
}

@test "validate-config_sh_--crosscheck-job-mapでヘッダーにhost列が混入する場合_header mismatchでstdoutを出さないこと" {
	# Arrange(spec.md「ヘッダー列が契約と異なる」)
	write_valid_map
	sed -i.bak '4s/.*/job_id,host,comparison_type,compare_targets,compare_command,compare_options,definition_version/' "$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: header mismatch expected=job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version actual=job_id,host,comparison_type,compare_targets,compare_command,compare_options,definition_version path: $MAP" ]
	[ "${STDERR_LINES[1]}" = "hint: fix the rows above and rerun validate-config.sh --crosscheck-job-map $MAP" ]
	[ "${#lines[@]}" -eq 0 ]
}

@test "validate-config_sh_--crosscheck-job-mapでタブ区切りのファイルの場合_header mismatchで拒否されること" {
	# Arrange(spec.md SPEC-004-04 Then 後半)
	{
		write_declarations
		printf 'job_id\tcomparison_type\tcompare_targets\tcompare_command\tcompare_options\tdefinition_version\n'
		printf 'JOB001\tjob\toutput.csv\t%s\t--blue {blue} --green {green}\tv1\n' "$COMPARE"
	} >"$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert(タブは可視表記 \t で出る)
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = 'error: header mismatch expected=job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version actual=job_id\tcomparison_type\tcompare_targets\tcompare_command\tcompare_options\tdefinition_version path: '"$MAP" ]
}

@test "validate-config_sh_--crosscheck-job-mapでcompare_targetsがカンマを含む引用セルの場合_1セルとして解析し終了コード0であること" {
	# Arrange(spec.md SPEC-004-04)
	write_valid_map
	sed -i.bak "6s|.*|JOB002,job,\"output.csv,summary.csv\",$COMPARE,--blue {blue} --green {green},v1|" "$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[2]}" = "rows=2" ]
	[ "${lines[6]}" = "status=valid" ]
}

@test "validate-config_sh_--crosscheck-job-mapで閉じ引用符の無いセルがある場合_csv quote is invalidで終了コード2であること" {
	# Arrange
	write_valid_map
	sed -i.bak "6s|.*|JOB002,job,\"output.csv,$COMPARE,--blue {blue} --green {green},v1|" "$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: csv quote is invalid line=6 path: $MAP" ]
}

@test "validate-config_sh_--crosscheck-job-mapで予約job_idのfull行がある場合_終了コード0でrows=3であること" {
	# Arrange
	write_valid_map
	printf '%s\n' "final-crosscheck,full,catalog,$COMPARE,--catalog {catalog_path} --catalog-version {catalog_version} --business-date {business_date},v1" >>"$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[2]}" = "rows=3" ]
	[ "${lines[6]}" = "status=valid" ]
}

@test "validate-config_sh_--crosscheck-job-mapでfull行が2行ある場合_duplicate job_idのlines=7,8で終了コード2であること" {
	# Arrange(予約 job_id は最大 1 行。重複検査で違反になる)
	write_valid_map
	printf '%s\n' "final-crosscheck,full,catalog,$COMPARE,--catalog-version {catalog_version} --business-date {business_date},v1" >>"$MAP"
	printf '%s\n' "final-crosscheck,full,catalog,$COMPARE,--catalog-version {catalog_version} --business-date {business_date},v2" >>"$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: duplicate job_id job_id=final-crosscheck lines=7,8" ]
}

@test "validate-config_sh_--crosscheck-job-mapでfull行のjob_idが予約値でない場合_not final-crosscheckで終了コード2であること" {
	# Arrange
	write_valid_map
	sed -i.bak "6s|.*|JOB002,full,catalog,$COMPARE,--catalog-version {catalog_version} --business-date {business_date},v1|" "$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: job_id is not final-crosscheck for comparison_type=full line=6 job_id=JOB002 value=JOB002" ]
}

@test "validate-config_sh_--crosscheck-job-mapでcomparison_typeが列挙外の場合_not in job,fullで終了コード2であること" {
	# Arrange
	write_valid_map
	sed -i.bak "6s|.*|JOB002,table,summary.tsv,$COMPARE,--blue {blue} --green {green},v1|" "$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: comparison_type is not in job,full line=6 job_id=JOB002 value=table" ]
}

@test "validate-config_sh_--crosscheck-job-mapでdefinition_versionが空の場合_is emptyで終了コード2であること" {
	# Arrange
	write_valid_map
	sed -i.bak "6s|.*|JOB002,job,summary.tsv,$COMPARE,--blue {blue} --green {green},|" "$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: definition_version is empty line=6 job_id=JOB002 value=" ]
}

@test "validate-config_sh_--crosscheck-job-mapでverboseを付けた場合_行ごとにinfo checkedがstderrに出て終了コード0であること" {
	# Arrange
	write_valid_map

	# Act
	run_split --crosscheck-job-map "$MAP" --verbose

	# Assert
	[ "$status" -eq 0 ]
	read_stderr_lines
	[ "${#STDERR_LINES[@]}" -eq 2 ]
	[ "${STDERR_LINES[0]}" = "info: checked job_id=JOB001" ]
	[ "${STDERR_LINES[1]}" = "info: checked job_id=JOB002" ]
}

@test "validate-config_sh_--crosscheck-job-mapでデータ行が0件の場合_rows=0で終了コード0であること" {
	# Arrange(config_input_rules: 導入直後の空のマップは正当)
	{
		write_declarations
		printf '%s\n' "$HEADER"
	} >"$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[2]}" = "rows=0" ]
	[ "${lines[6]}" = "status=valid" ]
}

@test "validate-config_sh_--crosscheck-job-mapでコメントだけのファイルの場合_actualが空のheader mismatchで終了コード2であること" {
	# Arrange
	write_declarations >"$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: header mismatch expected=job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version actual= path: $MAP" ]
}

@test "validate-config_sh_--crosscheck-job-mapでCRLF改行の場合_carriage returnのerrorとLFのhintで終了コード2であること" {
	# Arrange(config_input_rules: CR は拒否。行ごとに 1 行 + hint 1 回。ヘッダー検証には進まない)
	{
		printf '# exit_code_contract=0:OK,3:NG,6:ERROR\r\n'
		printf '%s\r\n' "$HEADER"
	} >"$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: carriage return is not allowed line=1 path: $MAP" ]
	[ "${STDERR_LINES[1]}" = "error: carriage return is not allowed line=2 path: $MAP" ]
	[ "${STDERR_LINES[2]}" = "hint: use LF line endings" ]
	[ "${STDERR_LINES[3]}" = "hint: fix the rows above and rerun validate-config.sh --crosscheck-job-map $MAP" ]
	[ "${#lines[@]}" -eq 0 ]
}

@test "validate-config_sh_--crosscheck-job-mapで先頭にBOMがある場合_byte order markのerrorで終了コード2であること" {
	# Arrange
	{
		printf '\xef\xbb\xbf# exit_code_contract=0:OK,3:NG,6:ERROR\n'
		printf '%s\n' "$HEADER"
	} >"$MAP"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: byte order mark is not allowed line=1 path: $MAP" ]
}

@test "validate-config_sh_--crosscheck-job-mapでsortが失敗する場合_internal command failedだけを出し終了コード6であること" {
	# Arrange(config_input_rules.internal_failure: PATH の先頭に失敗する sort を置く。stdout も他の error も出さない)
	write_valid_map
	mkdir -p "$BATS_TEST_TMPDIR/bin"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$BATS_TEST_TMPDIR/bin/sort"
	chmod +x "$BATS_TEST_TMPDIR/bin/sort"

	# Act
	PATH="$BATS_TEST_TMPDIR/bin:$PATH" run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	read_stderr_lines
	[ "${#STDERR_LINES[@]}" -eq 1 ]
	[ "${STDERR_LINES[0]}" = "error: internal command failed commands=sort path: $MAP" ]
	[ "${#lines[@]}" -eq 0 ]
}

@test "validate-config_sh_--crosscheck-job-mapでTMPDIRに書けない場合_config snapshot failedで終了コード6であること" {
	# Arrange
	write_valid_map
	export TMPDIR="$BATS_TEST_TMPDIR/nonexistent-tmp"

	# Act
	run_split --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 6 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: config snapshot failed path: $MAP" ]
	[ "${STDERR_LINES[1]}" = "hint: check TMPDIR is writable" ]
	[ "${#lines[@]}" -eq 0 ]
}

@test "validate-config_sh_--crosscheck-job-mapでNFR共通前提の最悪条件5000行の場合_10秒以内に終了コード0であること" {
	# Arrange(nfr-grade B.1.1.2 / B.2.1.1: ジョブマップ 5,000 行 + 参照先カタログ 5,000 行(該当版は最終行)。行数に比例する時間で処理する。
	#         実測: 検証だけで macOS 2〜3 秒 / Ubuntu 24.04 arm64 2 秒 / amd64(エミュレーション)4 秒。fixture の生成は計測に含めない)
	{
		printf '%s\n' 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling'
		awk 'BEGIN { for (i = 1; i <= 4999; i++) printf "v0,table,TABLE%05d,\"key=id,branch_id\",column=business_date\n", i }'
		printf '%s\n' 'v1,table,SALES_DAILY,key=sales_id,column=business_date'
	} >"$CATALOG"
	{
		write_declarations
		printf '%s\n' "$HEADER"
		awk -v compare="$COMPARE" 'BEGIN { for (i = 1; i <= 5000; i++) printf "JOB%05d,job,\"output_%05d.csv,summary.tsv\",%s,--blue {blue} --green {green} --id %d,v%d\n", i, i, compare, i, i }'
	} >"$MAP"
	SECONDS=0

	# Act
	run_split --crosscheck-job-map "$MAP" --verbose

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[2]}" = "rows=5000" ]
	[ "${lines[6]}" = "status=valid" ]
	[ "$(grep -c '^info: checked job_id=' "$ERR")" -eq 5000 ]
	[ "$SECONDS" -lt 10 ]
}

@test "validate-config_sh_--crosscheck-job-mapでパスに改行がある場合_stdoutが7行のままで可視表記になること" {
	# Arrange
	map="$BATS_TEST_TMPDIR"/$'ma\np.csv'
	write_valid_map
	mv "$MAP" "$map"

	# Act
	run_split --crosscheck-job-map "$map"

	# Assert
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 7 ]
	[ "${lines[1]}" = 'path: '"$BATS_TEST_TMPDIR"'/ma\np.csv' ]
}

@test "validate-config_sh_--crosscheck-job-mapで値が無い場合_option requiredで終了コード2であること" {
	# Arrange / Act(エントリポイント(tier-facade)の契約。値必須)
	run_split --crosscheck-job-map

	# Assert
	[ "$status" -eq 2 ]
	read_stderr_lines
	[ "${STDERR_LINES[0]}" = "error: option required option=--crosscheck-job-map" ]
}
