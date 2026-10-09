#!/usr/bin/env bats
# UC dcd8234d × tier-rapid-crosscheck: validate-config.sh --crosscheck-job-map の単体テスト(S2 test-scaffold の red baseline)。
# validate-config.sh の本体は tier-facade が所有し(UC「feature flag を設定する」)、本 tier は `--crosscheck-job-map` の
# サブ検証関数 validate_crosscheck_job_map を提供する(tier-rapid-crosscheck.md「変更概要」。bash の source で直接依存)。
# facade のエントリポイント(facade/bin/validate-config.sh)経由で実プロセスとして起動する。I/O 境界は実ファイル(一時ディレクトリ)。
# S2 時点では `--crosscheck-job-map` の usecase 委譲(validate_config_crosscheck_job_map)が未実装のため、
# "error: validation kind is not implemented option=--crosscheck-job-map"(終了コード 6)を理由に fail する。
# 仕様: tier-rapid-crosscheck.md「コマンド契約 / 出力契約 / 設定契約 / 検証ルール一覧」
# run は stdout と stderr を結合して受ける(先行 UC のテストと同じ方式。CI の bats 版に依存しない)。

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../../facade/bin/validate-config.sh"
	MAP="$BATS_TEST_TMPDIR/crosscheck-job-map.csv"
	CATALOG="$BATS_TEST_TMPDIR/target-catalog.csv"
	COMPARE="$BATS_TEST_TMPDIR/compare.sh"
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$COMPARE"
	chmod +x "$COMPARE"
	{
		printf '%s\n' 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling'
		printf '%s\n' 'v1,table,SALES_DAILY,key=sales_id,column=business_date'
	} >"$CATALOG"
}

# 宣言 3 行 + ヘッダー + JOB001 / JOB002 の妥当なジョブマップ(tier BDD「妥当なジョブマップを検証する」と同じ構成)
write_valid_map() {
	{
		printf '%s\n' '# exit_code_contract=0:OK,3:NG,6:ERROR'
		printf '%s\n' "# target_catalog_path=$CATALOG"
		printf '%s\n' '# catalog_version=v1'
		printf '%s\n' 'job_id,comparison_type,compare_targets,compare_command,compare_options,definition_version'
		printf '%s\n' "JOB001,job,output.csv,$COMPARE,--blue {blue} --green {green},v1"
		printf '%s\n' "JOB002,job,summary.tsv,$COMPARE,--blue {blue} --green {green} --ignore-header,v1"
	} >"$MAP"
}

@test "validate-config_sh_--crosscheck-job-mapで妥当なジョブマップの場合_終了コード0で契約の7行を順序どおり出すこと" {
	# Arrange
	write_valid_map

	# Act
	run "$SCRIPT" --crosscheck-job-map "$MAP"

	# Assert(違反が無いので stderr は空。結合出力は stdout の 7 行だけ。順序は出力契約の固定順)
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 7 ]
	[ "${lines[0]}" = "config=crosscheck-job-map" ]
	[ "${lines[1]}" = "path: $MAP" ]
	[ "${lines[2]}" = "rows=2" ]
	[ "${lines[3]}" = "target_catalog_path: $CATALOG" ]
	[ "${lines[4]}" = "catalog_version=v1" ]
	[ "${lines[5]}" = "exit_code_contract=0:OK,3:NG,6:ERROR" ]
	[ "${lines[6]}" = "status=valid" ]
}

@test "validate-config_sh_--crosscheck-job-mapでファイルが無い場合_config file not foundで終了コード2であること" {
	# Arrange / Act
	run "$SCRIPT" --crosscheck-job-map /nonexistent/crosscheck-job-map.csv

	# Assert
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "error: config file not found path: /nonexistent/crosscheck-job-map.csv" ]
}

@test "validate-config_sh_--crosscheck-job-mapでexit_code_contract宣言が無い場合_declaration not foundで終了コード2であること" {
	# Arrange(宣言 1 行目を落とす。ヘッダーは 3 行目になる)
	write_valid_map
	sed -i.bak '1d' "$MAP"

	# Act
	run "$SCRIPT" --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	found=false
	for line in "${lines[@]}"; do
		if [ "$line" = "error: exit_code_contract declaration not found path: $MAP" ]; then found=true; fi
	done
	[ "$found" = true ]
}

@test "validate-config_sh_--crosscheck-job-mapでjob_idが重複する場合_初出行を含むlines=で終了コード2であること" {
	# Arrange(6 行目を JOB001 行の複製にする。物理行は 5 と 6)
	write_valid_map
	sed -i.bak '6d' "$MAP"
	printf '%s\n' "JOB001,job,output.csv,$COMPARE,--blue {blue} --green {green},v1" >>"$MAP"

	# Act
	run "$SCRIPT" --crosscheck-job-map "$MAP"

	# Assert
	[ "$status" -eq 2 ]
	found=false
	for line in "${lines[@]}"; do
		if [ "$line" = "error: duplicate job_id job_id=JOB001 lines=5,6" ]; then found=true; fi
	done
	[ "$found" = true ]
}
