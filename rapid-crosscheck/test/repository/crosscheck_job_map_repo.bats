#!/usr/bin/env bats
# UC dcd8234d × tier-rapid-crosscheck: repository/crosscheck_job_map_repo.sh の単体テスト(一時ディレクトリの実ファイル)。
# 仕様: tier-rapid-crosscheck.md「設定契約(クロスチェックジョブマップ)」宣言(コメント行)/ spec.md「計算ルール一覧」対象カタログ参照の解決
#       cli-command-contract.yaml config_input_rules.snapshot(読み込みを終えたら複製を削除する)
# CSV の解析は tier-facade の job_map_repo.sh を読むだけで使う
# (docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md)。

setup() {
	FACADE_SRC="$BATS_TEST_DIRNAME/../../../facade/src"
	# shellcheck source=/dev/null
	source "$FACADE_SRC/domain/cli_field.sh"
	# shellcheck source=/dev/null
	source "$FACADE_SRC/domain/job_map.sh"
	# shellcheck source=/dev/null
	source "$FACADE_SRC/repository/job_map_repo.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/comparison_definition_rules.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/repository/crosscheck_job_map_repo.sh"
	MAP="$BATS_TEST_TMPDIR/crosscheck-job-map.csv"
	CATALOG="$BATS_TEST_TMPDIR/target-catalog.csv"
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir -p "$TMPDIR"
}

@test "crosscheck_job_map_repo_load_宣言3行とヘッダーと2行の場合_宣言を出現順に行番号付きで取り出しデータ行は2行であること" {
	# Arrange
	{
		printf '%s\n' '# exit_code_contract=0:OK,3:NG,6:ERROR'
		printf '%s\n' '#target_catalog_path=/etc/relay-gate/target-catalog.csv'
		printf '%s\n' '#   catalog_version=v1'
		printf '%s\n' '# this is a free comment'
		printf '%s\n' 'job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version'
		printf '%s\n' 'JOB001,job,output.csv,/opt/compare/compare.sh,--blue {blue} --green {green},v1'
		printf '%s\n' '# map_version=m1'
		printf '%s\n' 'JOB002,job,"a,b",/opt/compare/compare.sh,--blue {blue} --green {green},v1'
	} >"$MAP"

	# Act
	crosscheck_job_map_repo_load "$MAP"

	# Assert
	[ "${#CROSSCHECK_JOB_MAP_DECL_NAMES[@]}" -eq 4 ]
	[ "${CROSSCHECK_JOB_MAP_DECL_NAMES[0]}" = "exit_code_contract" ]
	[ "${CROSSCHECK_JOB_MAP_DECL_VALUES[0]}" = "0:OK,3:NG,6:ERROR" ]
	[ "${CROSSCHECK_JOB_MAP_DECL_LINES[0]}" -eq 1 ]
	[ "${CROSSCHECK_JOB_MAP_DECL_NAMES[1]}" = "target_catalog_path" ]
	[ "${CROSSCHECK_JOB_MAP_DECL_VALUES[1]}" = "/etc/relay-gate/target-catalog.csv" ]
	[ "${CROSSCHECK_JOB_MAP_DECL_NAMES[2]}" = "catalog_version" ]
	[ "${CROSSCHECK_JOB_MAP_DECL_VALUES[2]}" = "v1" ]
	[ "${CROSSCHECK_JOB_MAP_DECL_NAMES[3]}" = "map_version" ]
	[ "${CROSSCHECK_JOB_MAP_DECL_LINES[3]}" -eq 7 ]
	[ "$JOB_MAP_HEADER_LINE" -eq 5 ]
	[ "${#JOB_MAP_ROW_LINES[@]}" -eq 2 ]
	[ "${JOB_MAP_ROW_LINES[1]}" -eq 8 ]
	# 同じクォート解析関数: カンマを含む引用セルは 1 セル
	[ "${JOB_MAP_ROW_CELL_COUNTS[1]}" -eq 6 ]
	job_map_repo_row 1
	[ "${JOB_MAP_ROW[2]}" = "a,b" ]
}

@test "crosscheck_job_map_repo_load_読み込みを終えた場合_TMPDIRに複製が残らないこと" {
	# Arrange
	printf '%s\n' '# exit_code_contract=0:OK,3:NG,6:ERROR' 'job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version' >"$MAP"

	# Act
	crosscheck_job_map_repo_load "$MAP"

	# Assert
	[ -z "$(ls -A "$TMPDIR")" ]
}

@test "crosscheck_job_map_repo_load_形式違反の行がある場合_その行の宣言は取り込まないこと" {
	# Arrange(2 行目に CR を含む宣言)
	printf '# exit_code_contract=0:OK,3:NG,6:ERROR\n# catalog_version=v1\r\njob_id,comparison_type,compare_targets,compare_command,compare_options,definition_version\n' >"$MAP"

	# Act
	crosscheck_job_map_repo_load "$MAP"

	# Assert
	[ "${#CROSSCHECK_JOB_MAP_DECL_NAMES[@]}" -eq 1 ]
	[ "${JOB_MAP_CR_LINES[0]}" -eq 2 ]
}

@test "crosscheck_job_map_repo_declaration_同名の宣言が2回ある場合_初出の値と出現回数2を返すこと" {
	# Arrange
	CROSSCHECK_JOB_MAP_DECL_NAMES=(catalog_version exit_code_contract catalog_version)
	CROSSCHECK_JOB_MAP_DECL_VALUES=(v1 "0:OK,3:NG,6:ERROR" v2)
	CROSSCHECK_JOB_MAP_DECL_LINES=(1 2 3)

	# Act
	crosscheck_job_map_repo_declaration catalog_version

	# Assert
	[ "$CROSSCHECK_JOB_MAP_DECL_FOUND" -eq 2 ]
	[ "$CROSSCHECK_JOB_MAP_DECL_VALUE" = "v1" ]
	[ "$CROSSCHECK_JOB_MAP_DECL_LINE" -eq 1 ]
}

@test "crosscheck_job_map_repo_declaration_宣言が無い場合_出現回数0で値が空であること" {
	# Arrange
	CROSSCHECK_JOB_MAP_DECL_NAMES=(exit_code_contract)
	CROSSCHECK_JOB_MAP_DECL_VALUES=("0:OK,3:NG,6:ERROR")
	CROSSCHECK_JOB_MAP_DECL_LINES=(1)

	# Act
	crosscheck_job_map_repo_declaration target_catalog_path

	# Assert
	[ "$CROSSCHECK_JOB_MAP_DECL_FOUND" -eq 0 ]
	[ -z "$CROSSCHECK_JOB_MAP_DECL_VALUE" ]
}

@test "target_catalog_repo_has_version_該当版の行がある場合_戻り値0であること" {
	# Arrange(catalog_version 列が先頭でなくても列名で引く)
	{
		printf '%s\n' 'target_type,catalog_version,target_identifier,compare_condition,business_date_handling'
		printf '%s\n' 'table,v1,SALES_DAILY,"key=sales_id,branch_id",column=business_date'
		printf '%s\n' 'file,v2,/data/out/summary.tsv,-,filename'
	} >"$CATALOG"

	# Act
	run target_catalog_repo_has_version "$CATALOG" v2

	# Assert
	[ "$status" -eq 0 ]
}

@test "target_catalog_repo_has_version_該当版の行が無い場合_戻り値1であること" {
	# Arrange
	printf '%s\n' 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling' 'v1,table,SALES_DAILY,key=sales_id,column=business_date' >"$CATALOG"

	# Act
	run target_catalog_repo_has_version "$CATALOG" v9

	# Assert
	[ "$status" -eq 1 ]
}

@test "target_catalog_repo_has_version_catalog_version列が無い場合_戻り値1であること" {
	# Arrange
	printf '%s\n' 'version,target_type' 'v1,table' >"$CATALOG"

	# Act
	run target_catalog_repo_has_version "$CATALOG" v1

	# Assert
	[ "$status" -eq 1 ]
}

@test "target_catalog_repo_has_version_カタログが存在しない場合_戻り値1であること" {
	# Arrange / Act
	run target_catalog_repo_has_version "$BATS_TEST_TMPDIR/missing.csv" v1

	# Assert
	[ "$status" -eq 1 ]
}

@test "target_catalog_repo_has_version_カタログにCRがある場合_形式違反として解決できず戻り値1であること" {
	# Arrange
	printf 'catalog_version,target_type\r\nv1,table\r\n' >"$CATALOG"

	# Act
	run target_catalog_repo_has_version "$CATALOG" v1

	# Assert
	[ "$status" -eq 1 ]
}
