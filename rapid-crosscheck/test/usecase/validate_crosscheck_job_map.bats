#!/usr/bin/env bats
# UC dcd8234d × tier-rapid-crosscheck: usecase/validate_crosscheck_job_map.sh の単体テスト(関数を直接呼ぶ。I/O は一時ディレクトリの実ファイル)。
# 仕様: tier-rapid-crosscheck.md「出力契約」「UC ロジック」(全件収集・読み取り専用)/ cli-command-contract.yaml config_input_rules
# tier-facade の domain / repository を読むだけで使う(docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md)。

setup() {
	FACADE_SRC="$BATS_TEST_DIRNAME/../../../facade/src"
	# shellcheck source=/dev/null
	source "$FACADE_SRC/domain/cli_field.sh"
	# shellcheck source=/dev/null
	source "$FACADE_SRC/domain/job_map.sh"
	# shellcheck source=/dev/null
	source "$FACADE_SRC/repository/job_map_repo.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/presentation/validate_config_crosscheck_job_map.sh"
	MAP="$BATS_TEST_TMPDIR/crosscheck-job-map.csv"
	CATALOG="$BATS_TEST_TMPDIR/target-catalog.csv"
	COMPARE="$BATS_TEST_TMPDIR/compare.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$COMPARE"
	chmod +x "$COMPARE"
	printf '%s\n' 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling' 'v1,table,SALES_DAILY,key=sales_id,column=business_date' >"$CATALOG"
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir -p "$TMPDIR"
}

write_valid_map() {
	{
		printf '%s\n' '# exit_code_contract=0:OK,3:NG,6:ERROR'
		printf '%s\n' "# target_catalog_path=$CATALOG"
		printf '%s\n' '# catalog_version=v1'
		printf '%s\n' 'job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version'
		printf '%s\n' "JOB001,job,output.csv,$COMPARE,--blue {blue} --green {green},v1"
	} >"$MAP"
}

@test "validate_crosscheck_job_map_妥当なジョブマップの場合_戻り値0で報告sinkを元に戻すこと" {
	# Arrange
	write_valid_map
	JOB_MAP_REPORT_SINK=""

	# Act
	validate_crosscheck_job_map "$MAP" false >/dev/null

	# Assert
	[ -z "$JOB_MAP_REPORT_SINK" ]
	[ "${#JOB_MAP_REPORT_LINES[@]}" -eq 0 ]
}

@test "validate_crosscheck_job_map_妥当なジョブマップの場合_入力ファイルを変更しないこと" {
	# Arrange(UC ロジック: 参照のみ)
	write_valid_map
	before="$(cat "$MAP")"

	# Act
	run validate_crosscheck_job_map "$MAP" false

	# Assert
	[ "$status" -eq 0 ]
	[ "$(cat "$MAP")" = "$before" ]
}

@test "validate_crosscheck_job_map_読み取り権限が無い場合_not readableで戻り値2であること" {
	# Arrange
	write_valid_map
	chmod 000 "$MAP"
	if [ -r "$MAP" ]; then
		skip "root など読み取り権限を無視できるユーザーでは再現しない"
	fi

	# Act
	run validate_crosscheck_job_map "$MAP" false

	# Assert
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "error: config file is not readable path: $MAP" ]
}

@test "validate_crosscheck_job_map_宣言の違反と行の違反とカタログ未解決がある場合_violationsが合算されること" {
	# Arrange(exit_code_contract 不正 1 + compare_command 実行不可 1 + 参照未解決 1)
	write_valid_map
	sed -i.bak '1s/.*/# exit_code_contract=bad/' "$MAP"
	sed -i.bak '3s/.*/# catalog_version=v9/' "$MAP"
	sed -i.bak "5s|.*|JOB001,job,output.csv,$BATS_TEST_TMPDIR/none.sh,--blue {blue} --green {green},v1|" "$MAP"

	# Act
	run validate_crosscheck_job_map "$MAP" false

	# Assert(順序: 宣言 → 行 → 参照 → hint → stdout)
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "error: exit_code_contract declaration is invalid value=bad path: $MAP" ]
	[ "${lines[1]}" = "error: compare_command is not executable line=5 job_id=JOB001 value=$BATS_TEST_TMPDIR/none.sh" ]
	[ "${lines[2]}" = "error: target catalog reference unresolved path=$CATALOG catalog_version=v9" ]
	[ "${lines[3]}" = "hint: fix the rows above and rerun validate-config.sh --crosscheck-job-map $MAP" ]
	[ "${lines[11]}" = "violations=3" ]
}

@test "crosscheck_target_catalog_report_row_errors_クォート不正と列数不一致の行がある場合_物理行順に共通文言で出し件数を返すこと" {
	# Arrange(config_input_rules: 空白だけの行は 1 セルのデータ行。expected はカタログのヘッダーの列数)
	{
		printf '%s\n' 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling'
		printf '%s\n' 'v1,table,SALES_DAILY,key=sales_id,column=business_date'
		printf '%s\n' '"broken,table,X,-,filename'
		printf '%s\n' ' '
	} >"$CATALOG"
	crosscheck_target_catalog_repo_load "$CATALOG"
	JOB_MAP_REPORT_SINK=""

	# Act
	run crosscheck_target_catalog_report_row_errors "$CATALOG"

	# Assert
	[ "$status" -eq 1 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "error: csv quote is invalid line=3 path: $CATALOG" ]
	[ "${lines[1]}" = "error: column count mismatch line=4 expected=5 actual=1" ]
}

@test "crosscheck_target_catalog_report_row_errors_全行が妥当な場合_何も出さず戻り値0であること" {
	# Arrange
	crosscheck_target_catalog_repo_load "$CATALOG"
	JOB_MAP_REPORT_SINK=""

	# Act
	run crosscheck_target_catalog_report_row_errors "$CATALOG"

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}
