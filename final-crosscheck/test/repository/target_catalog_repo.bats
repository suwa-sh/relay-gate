#!/usr/bin/env bats
# UC dcd8234d × tier-final-crosscheck: repository 層 TargetCatalogRecord の単体テスト。I/O 境界は実ファイル(一時ディレクトリ)。
# 仕様: tier-final-crosscheck.md「設定契約(対象カタログ)」形式(slot ジョブマップと同じ CSV)/ spec.md SPEC-004-04 Then
#       (slot ジョブマップの読み込みと同じ CSV クォート解析関数が使われる)
# 共有の読み込み関数 job_map_repo_load は tier-facade の facade/src/repository/job_map_repo.sh を読むだけで使う
# (docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md)。

setup() {
	source "$BATS_TEST_DIRNAME/../../../facade/src/repository/job_map_repo.sh"
	source "$BATS_TEST_DIRNAME/../../src/repository/target_catalog_repo.sh"
	CATALOG="$BATS_TEST_TMPDIR/target-catalog.csv"
}

@test "target_catalog_repo_loadで引用セルとコメント行を含むCSVの場合_slotジョブマップと同じ解析結果を載せること" {
	# Arrange(カンマを含む引用セル・二重化した引用符・コメント行・空行・最終行の改行なし)
	{
		printf '%s\n' '# comment'
		printf '%s\n' 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling'
		printf '%s\n' ''
		printf '%s\n' 'v1,table,SALES_DAILY,"key=sales_id,branch_id",column=business_date'
		printf '%s' 'v1,file,"/data/out/""summary"".tsv",-,filename'
	} >"$CATALOG"

	# Act
	target_catalog_repo_load "$CATALOG"

	# Assert
	[ "$TARGET_CATALOG_PATH" = "$CATALOG" ]
	[ "$TARGET_CATALOG_HEADER_LINE" -eq 2 ]
	[ "$TARGET_CATALOG_HEADER_STATUS" = "ok" ]
	[ "${#TARGET_CATALOG_HEADER[@]}" -eq 5 ]
	[ "${TARGET_CATALOG_HEADER[0]}" = "catalog_version" ]
	[ "${#TARGET_CATALOG_ROW_LINES[@]}" -eq 2 ]
	[ "${TARGET_CATALOG_ROW_LINES[0]}" -eq 4 ]
	[ "${TARGET_CATALOG_ROW_LINES[1]}" -eq 5 ]
	[ "${TARGET_CATALOG_ROW_CELL_COUNTS[0]}" -eq 5 ]
	[ "${TARGET_CATALOG_ROW_CELL_COUNTS[1]}" -eq 5 ]
	[ "${TARGET_CATALOG_CELLS[3]}" = "key=sales_id,branch_id" ]
	[ "${TARGET_CATALOG_CELLS[$((TARGET_CATALOG_ROW_OFFSETS[1] + 2))]}" = '/data/out/"summary".tsv' ]
	[ "$(target_catalog_repo_row_count)" = "2" ]
}

@test "target_catalog_repo_loadでクォート不正の行がある場合_その行をquote_invalidにすること" {
	# Arrange
	{
		printf '%s\n' 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling'
		printf '%s\n' 'v1,table,"SALES,-,-'
	} >"$CATALOG"

	# Act
	target_catalog_repo_load "$CATALOG"

	# Assert
	[ "${TARGET_CATALOG_ROW_STATUSES[0]}" = "quote_invalid" ]
	[ "${TARGET_CATALOG_ROW_CELL_COUNTS[0]}" -eq 0 ]
}

@test "target_catalog_repo_loadでCRとBOMを含む場合_形式違反の行番号を原因ごとに載せること" {
	# Arrange(先頭 BOM + 2 行目に CR)
	printf '\xef\xbb\xbfcatalog_version,target_type,target_identifier,compare_condition,business_date_handling\nv1,table,X,-,-\r\n' >"$CATALOG"

	# Act
	target_catalog_repo_load "$CATALOG"

	# Assert
	[ "$TARGET_CATALOG_BOM_LINE" -eq 1 ]
	[ "${TARGET_CATALOG_CR_LINES[0]}" -eq 2 ]
	[ "${#TARGET_CATALOG_MALFORMED_LINES[@]}" -eq 2 ]
	[ "$TARGET_CATALOG_HEADER_STATUS" = "malformed" ]
}

@test "target_catalog_repo_loadで共有の読み込み関数が無い場合_内部障害として関数名を返すこと" {
	# Arrange(validate-config.sh 以外から単独で呼ばれた環境を模す)
	unset -f job_map_repo_load
	printf '%s\n' 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling' >"$CATALOG"

	# Act
	run_status=0
	target_catalog_repo_load "$CATALOG" || run_status=$?

	# Assert
	[ "$run_status" -eq 6 ]
	[ "$TARGET_CATALOG_REPO_FAILED_COMMANDS" = "job_map_repo_load" ]
}

@test "target_catalog_repo_loadで読み込み後の一時ファイルが残らないこと" {
	# Arrange(単一スナップショットは TMPDIR に relay-gate-* で作られ、読み込みを終えたら削除される)
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir -p "$TMPDIR"
	printf '%s\n' 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling' 'v1,table,X,-,-' >"$CATALOG"

	# Act
	target_catalog_repo_load "$CATALOG"

	# Assert
	[ "${#TARGET_CATALOG_ROW_LINES[@]}" -eq 1 ]
	[ -z "$(ls -A "$TMPDIR")" ]
}
