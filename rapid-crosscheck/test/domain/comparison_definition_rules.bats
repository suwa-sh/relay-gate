#!/usr/bin/env bats
# UC dcd8234d × tier-rapid-crosscheck: domain/comparison_definition_rules.sh の単体テスト(純粋関数)。
# 仕様: tier-rapid-crosscheck.md「設定契約(クロスチェックジョブマップ)」列の検証ルール / 予約 job_id / 検証ルール一覧 #2, #5〜#8, #10
# 報告 sink(job_map_emit)と可視表記(cli_field_safe_text)は tier-facade の domain を読むだけで使う
# (docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md)。

setup() {
	FACADE_SRC="$BATS_TEST_DIRNAME/../../../facade/src"
	# shellcheck source=/dev/null
	source "$FACADE_SRC/domain/cli_field.sh"
	# shellcheck source=/dev/null
	source "$FACADE_SRC/domain/job_map.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/comparison_definition_rules.sh"
	COMPARE="$BATS_TEST_TMPDIR/compare.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$COMPARE"
	chmod +x "$COMPARE"
}

@test "validate_comparison_definition_row_job行が妥当な場合_違反0件で戻り値0であること" {
	# Arrange / Act
	run validate_comparison_definition_row 5 JOB001 job output.csv "$COMPARE" "--blue {blue} --green {green}" v1

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_comparison_definition_row_job行のcompare_optionsに{green}が無い場合_missing placeholderのerror1行であること" {
	# Arrange / Act
	run validate_comparison_definition_row 5 JOB001 job output.csv "$COMPARE" "--blue {blue}" v1

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: compare_options is missing {blue} or {green} line=5 job_id=JOB001 value=--blue {blue}" ]
}

@test "validate_comparison_definition_row_compare_commandが存在しない場合_not executableのerrorであること" {
	# Arrange / Act
	run validate_comparison_definition_row 5 JOB001 job output.csv /opt/compare/missing.sh "--blue {blue} --green {green}" v1

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: compare_command is not executable line=5 job_id=JOB001 value=/opt/compare/missing.sh" ]
}

@test "validate_comparison_definition_row_compare_commandに実行権限が無い場合_not executableのerrorであること" {
	# Arrange
	chmod -x "$COMPARE"

	# Act
	run validate_comparison_definition_row 5 JOB001 job output.csv "$COMPARE" "--blue {blue} --green {green}" v1

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: compare_command is not executable line=5 job_id=JOB001 value=$COMPARE" ]
}

@test "validate_comparison_definition_row_full行が予約job_idで妥当な場合_違反0件であること" {
	# Arrange / Act
	run validate_comparison_definition_row 7 final-crosscheck full catalog "$COMPARE" "--catalog {catalog_path} --catalog-version {catalog_version} --business-date {business_date}" v1

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_comparison_definition_row_full行のjob_idが予約値でない場合_not final-crosscheckのerrorであること" {
	# Arrange / Act
	run validate_comparison_definition_row 7 JOB009 full catalog "$COMPARE" "--catalog-version {catalog_version} --business-date {business_date}" v1

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: job_id is not final-crosscheck for comparison_type=full line=7 job_id=JOB009 value=JOB009" ]
}

@test "validate_comparison_definition_row_full行のcompare_optionsに{business_date}が無い場合_missing placeholderのerrorであること" {
	# Arrange / Act
	run validate_comparison_definition_row 7 final-crosscheck full catalog "$COMPARE" "--catalog-version {catalog_version}" v1

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: compare_options is missing {catalog_version} or {business_date} line=7 job_id=final-crosscheck value=--catalog-version {catalog_version}" ]
}

@test "validate_comparison_definition_row_予約job_idの行がjob種別の場合_not fullのerrorであること" {
	# Arrange / Act
	run validate_comparison_definition_row 7 final-crosscheck job catalog "$COMPARE" "--blue {blue} --green {green}" v1

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: comparison_type is not full for job_id=final-crosscheck line=7 job_id=final-crosscheck value=job" ]
}

@test "validate_comparison_definition_row_comparison_typeが列挙外の場合_not in job,fullのerrorでプレースホルダは判定しないこと" {
	# Arrange / Act
	run validate_comparison_definition_row 5 JOB001 table output.csv "$COMPARE" "--fast" v1

	# Assert
	[ "$status" -eq 1 ]
	[ "${#lines[@]}" -eq 1 ]
	[ "${lines[0]}" = "error: comparison_type is not in job,full line=5 job_id=JOB001 value=table" ]
}

@test "validate_comparison_definition_row_job_idが形式外の場合_job_id is invalidのerrorであること" {
	# Arrange / Act
	run validate_comparison_definition_row 5 "JOB 001" job output.csv "$COMPARE" "--blue {blue} --green {green}" v1

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: job_id is invalid line=5 job_id=JOB 001 value=JOB 001" ]
}

@test "validate_comparison_definition_row_全列が空の場合_列ごとにis emptyのerrorが6行出ること" {
	# Arrange / Act
	run validate_comparison_definition_row 5 "" "" "" "" "" ""

	# Assert(列順: job_id, comparison_type, compare_targets, compare_command, compare_options, definition_version)
	[ "$status" -eq 1 ]
	[ "${#lines[@]}" -eq 6 ]
	[ "${lines[0]}" = "error: job_id is empty line=5 job_id= value=" ]
	[ "${lines[1]}" = "error: comparison_type is empty line=5 job_id= value=" ]
	[ "${lines[2]}" = "error: compare_targets is empty line=5 job_id= value=" ]
	[ "${lines[3]}" = "error: compare_command is empty line=5 job_id= value=" ]
	[ "${lines[4]}" = "error: compare_options is empty line=5 job_id= value=" ]
	[ "${lines[5]}" = "error: definition_version is empty line=5 job_id= value=" ]
	[ "$COMPARISON_DEFINITION_ROW_ERRORS" -eq 0 ] # run はサブシェルなので親の件数は変わらない
}

@test "validate_comparison_definition_row_値に制御文字がある場合_可視表記で出すこと" {
	# Arrange / Act
	run validate_comparison_definition_row 5 JOB001 job output.csv "$COMPARE" $'--fast\033[31m' v1

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = 'error: compare_options is missing {blue} or {green} line=5 job_id=JOB001 value=--fast\u001b[31m' ]
}

@test "validate_crosscheck_job_map_header_列定義と完全一致する場合_戻り値0であること" {
	# Arrange / Act
	run validate_crosscheck_job_map_header map.csv job_id comparison_type compare_targets compare_command compare_options definition_version

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_crosscheck_job_map_header_host列が混入する場合_header mismatchのerrorであること" {
	# Arrange / Act
	run validate_crosscheck_job_map_header map.csv job_id host comparison_type compare_targets compare_command compare_options definition_version

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: header mismatch expected=job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version actual=job_id,host,comparison_type,compare_targets,compare_command,compare_options,definition_version path: map.csv" ]
}

@test "validate_crosscheck_job_map_header_ヘッダー行が無い場合_actualが空のheader mismatchであること" {
	# Arrange / Act
	run validate_crosscheck_job_map_header map.csv

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: header mismatch expected=job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version actual= path: map.csv" ]
}

@test "validate_exit_code_contract_declaration_固定文字列と一致する場合_戻り値0であること" {
	# Arrange / Act
	run validate_exit_code_contract_declaration map.csv 1 "0:OK,3:NG,6:ERROR"

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "validate_exit_code_contract_declaration_宣言が無い場合_declaration not foundであること" {
	# Arrange / Act
	run validate_exit_code_contract_declaration map.csv 0 ""

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: exit_code_contract declaration not found path: map.csv" ]
}

@test "validate_exit_code_contract_declaration_値が固定文字列と異なる場合_declaration is invalidであること" {
	# Arrange / Act
	run validate_exit_code_contract_declaration map.csv 1 "0:OK,1:NG"

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: exit_code_contract declaration is invalid value=0:OK,1:NG path: map.csv" ]
}

@test "validate_required_declaration_値が空の場合_declaration is invalidであること" {
	# Arrange / Act
	run validate_required_declaration map.csv catalog_version 1 ""

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: catalog_version declaration is invalid value= path: map.csv" ]
}
