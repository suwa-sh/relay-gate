#!/usr/bin/env bats
# UC dcd8234d × tier-final-crosscheck: domain 層 TargetCatalogRules の単体テスト(純粋関数。I/O なし)。
# 仕様: tier-final-crosscheck.md「設定契約(対象カタログ)」列の検証表 / 「検証ルール一覧」/ spec.md「計算ルール一覧」
# 依存の cli_field_safe_text は tier-facade の facade/src/domain/cli_field.sh を読むだけで使う
# (docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md)。

setup() {
	source "$BATS_TEST_DIRNAME/../../../facade/src/domain/cli_field.sh"
	source "$BATS_TEST_DIRNAME/../../src/domain/target_catalog.sh"
	target_catalog_rules_reset
}

# 行の値を TARGET_CATALOG_ROW_* に載せる(列順固定の 5 列)
bind_row() {
	local cells=("$@")
	target_catalog_row_bind_at cells 0
}

@test "validate_target_catalog_headerで契約の5列と完全一致する場合_違反なしで報告行が0件であること" {
	# Arrange / Act
	run_status=0
	validate_target_catalog_header /etc/relay-gate/target-catalog.csv catalog_version target_type target_identifier compare_condition business_date_handling || run_status=$?

	# Assert
	[ "$run_status" -eq 0 ]
	[ "${#TARGET_CATALOG_REPORT_LINES[@]}" -eq 0 ]
}

@test "validate_target_catalog_headerで列順が異なる場合_header_mismatchでexpectedとactualとpathを出すこと" {
	# Arrange / Act
	run_status=0
	validate_target_catalog_header /etc/x.csv target_type catalog_version target_identifier compare_condition business_date_handling || run_status=$?

	# Assert(列順固定。順序違いも不一致)
	[ "$run_status" -eq 1 ]
	[ "${#TARGET_CATALOG_REPORT_LINES[@]}" -eq 1 ]
	[ "${TARGET_CATALOG_REPORT_LINES[0]}" = "error: header mismatch expected=catalog_version,target_type,target_identifier,compare_condition,business_date_handling actual=target_type,catalog_version,target_identifier,compare_condition,business_date_handling path: /etc/x.csv" ]
	[ "$TARGET_CATALOG_ERROR_COUNT" -eq 1 ]
}

@test "validate_target_catalog_headerでヘッダー行が無い場合_actualが空のheader_mismatchであること" {
	# Arrange / Act(空のファイル・コメントだけのファイルはヘッダーのセルが 0 個)
	run_status=0
	validate_target_catalog_header /etc/x.csv || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${TARGET_CATALOG_REPORT_LINES[0]}" = "error: header mismatch expected=catalog_version,target_type,target_identifier,compare_condition,business_date_handling actual= path: /etc/x.csv" ]
}

@test "validate_target_catalog_headerで列名が重複する場合_duplicate_columnの後にheader_mismatchを出すこと" {
	# Arrange / Act
	run_status=0
	validate_target_catalog_header /etc/x.csv catalog_version target_type target_type compare_condition business_date_handling || run_status=$?

	# Assert(重複した列名ごとに 1 行 → 不一致)
	[ "$run_status" -eq 1 ]
	[ "${#TARGET_CATALOG_REPORT_LINES[@]}" -eq 2 ]
	[ "${TARGET_CATALOG_REPORT_LINES[0]}" = "error: duplicate column column=target_type path: /etc/x.csv" ]
	[[ "${TARGET_CATALOG_REPORT_LINES[1]}" == "error: header mismatch expected="* ]]
}

@test "validate_target_catalog_headerで列名に制御文字を含む場合_actualを可視表記で出すこと" {
	# Arrange / Act(タブ区切りのファイルは 1 セルの列名になる)
	run_status=0
	validate_target_catalog_header /etc/x.csv $'catalog_version\ttarget_type' || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${TARGET_CATALOG_REPORT_LINES[0]}" = 'error: header mismatch expected=catalog_version,target_type,target_identifier,compare_condition,business_date_handling actual=catalog_version\ttarget_type path: /etc/x.csv' ]
}

@test "validate_target_catalog_headerで引用により5列名が1セルに結合された場合_header_mismatchでactualを引用付きで出すこと" {
	# Arrange / Act(`"catalog_version,target_type,...,business_date_handling"` の 1 行は解析後 1 セル。
	#              カンマで再連結すると契約の 5 列と同じ文字列になるため、セル数と位置で判定する。S5 F-001 の回帰)
	run_status=0
	validate_target_catalog_header /etc/x.csv 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling' || run_status=$?

	# Assert(actual= はカンマを含む列名を引用し、1 セルだと分かる表記にする)
	[ "$run_status" -eq 1 ]
	[ "${#TARGET_CATALOG_REPORT_LINES[@]}" -eq 1 ]
	[ "${TARGET_CATALOG_REPORT_LINES[0]}" = 'error: header mismatch expected=catalog_version,target_type,target_identifier,compare_condition,business_date_handling actual="catalog_version,target_type,target_identifier,compare_condition,business_date_handling" path: /etc/x.csv' ]
}

@test "validate_target_catalog_headerで引用により先頭2列が1セルに結合された4セルの場合_header_mismatchであること" {
	# Arrange / Act(`"catalog_version,target_type",target_identifier,...` は解析後 4 セル。S5 F-001 の回帰)
	run_status=0
	validate_target_catalog_header /etc/x.csv 'catalog_version,target_type' target_identifier compare_condition business_date_handling || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${TARGET_CATALOG_REPORT_LINES[0]}" = 'error: header mismatch expected=catalog_version,target_type,target_identifier,compare_condition,business_date_handling actual="catalog_version,target_type",target_identifier,compare_condition,business_date_handling path: /etc/x.csv' ]
}

@test "validate_target_catalog_headerで6セル目に空の列名がある場合_header_mismatchであること" {
	# Arrange / Act(末尾のカンマで 6 セル。セル数の不一致)
	run_status=0
	validate_target_catalog_header /etc/x.csv catalog_version target_type target_identifier compare_condition business_date_handling "" || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${TARGET_CATALOG_REPORT_LINES[0]}" = 'error: header mismatch expected=catalog_version,target_type,target_identifier,compare_condition,business_date_handling actual=catalog_version,target_type,target_identifier,compare_condition,business_date_handling, path: /etc/x.csv' ]
}

@test "validate_target_catalog_headerで列名に二重引用符を含む場合_actualで二重化して引用すること" {
	# Arrange / Act(列名 `a"b` は入力のクォート規則どおり `"a""b"` と表記する)
	run_status=0
	validate_target_catalog_header /etc/x.csv 'a"b' target_type target_identifier compare_condition business_date_handling || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${TARGET_CATALOG_REPORT_LINES[0]}" = 'error: header mismatch expected=catalog_version,target_type,target_identifier,compare_condition,business_date_handling actual="a""b",target_type,target_identifier,compare_condition,business_date_handling path: /etc/x.csv' ]
}

@test "target_catalog_is_valid_catalog_versionで英数字とドットとアンダースコアとハイフンの場合_受理すること" {
	target_catalog_is_valid_catalog_version "v1.2_rc-3"
}

@test "target_catalog_is_valid_catalog_versionで空白や全角数字を含む場合_拒否すること" {
	! target_catalog_is_valid_catalog_version "v 1"
	! target_catalog_is_valid_catalog_version "v１"
	! target_catalog_is_valid_catalog_version ""
}

@test "validate_target_catalog_rowで妥当なtable行の場合_違反なしであること" {
	# Arrange
	bind_row v1 table SALES_DAILY key=sales_id column=business_date

	# Act / Assert
	validate_target_catalog_row 2
	[ "${#TARGET_CATALOG_REPORT_LINES[@]}" -eq 0 ]
}

@test "validate_target_catalog_rowで任意列が空の場合_受理すること" {
	# Arrange(compare_condition / business_date_handling は任意列。空セルも受理する)
	bind_row v1 file /data/out/x.tsv "" ""

	# Act / Assert
	validate_target_catalog_row 2
	[ "${#TARGET_CATALOG_REPORT_LINES[@]}" -eq 0 ]
}

@test "validate_target_catalog_rowでtarget_typeがviewの場合_job_id無しのtarget_type違反を出すこと" {
	# Arrange
	bind_row v1 view SALES_DAILY - -

	# Act
	run_status=0
	validate_target_catalog_row 3 || run_status=$?

	# Assert(対象カタログは job_id 列を持たないため job_id= を付けない)
	[ "$run_status" -eq 1 ]
	[ "${TARGET_CATALOG_REPORT_LINES[0]}" = "error: target_type is not in table,file line=3 value=view" ]
}

@test "validate_target_catalog_rowで必須3列が空の場合_列ごとにis_emptyを契約の列順で出すこと" {
	# Arrange
	bind_row "" "" "" - -

	# Act
	run_status=0
	validate_target_catalog_row 4 || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${#TARGET_CATALOG_REPORT_LINES[@]}" -eq 3 ]
	[ "${TARGET_CATALOG_REPORT_LINES[0]}" = "error: catalog_version is empty line=4 value=" ]
	[ "${TARGET_CATALOG_REPORT_LINES[1]}" = "error: target_type is empty line=4 value=" ]
	[ "${TARGET_CATALOG_REPORT_LINES[2]}" = "error: target_identifier is empty line=4 value=" ]
}

@test "validate_target_catalog_rowでcatalog_versionに制御文字を含む場合_is_invalidでvalueを可視表記にすること" {
	# Arrange
	bind_row $'v1\e' table X - -

	# Act
	run_status=0
	validate_target_catalog_row 2 || run_status=$?

	# Assert
	[ "$run_status" -eq 1 ]
	[ "${TARGET_CATALOG_REPORT_LINES[0]}" = 'error: catalog_version is invalid line=2 value=v1\u001b' ]
}

@test "target_catalog_report_duplicatesで同一版内の同じ対象が3行にある場合_初出行を含む全行番号を出現順に出すこと" {
	# Arrange
	bind_row v1 table SALES_DAILY - -
	target_catalog_register_key 2
	bind_row v1 file SALES_DAILY - -
	target_catalog_register_key 3
	bind_row v1 table SALES_DAILY - -
	target_catalog_register_key 5
	bind_row v1 table SALES_DAILY - -
	target_catalog_register_key 7

	# Act
	run_status=0
	target_catalog_report_duplicates || run_status=$?

	# Assert(target_type が違えば別の対象。重複したキー 1 つにつき 1 行)
	[ "$run_status" -eq 1 ]
	[ "${#TARGET_CATALOG_REPORT_LINES[@]}" -eq 1 ]
	[ "${TARGET_CATALOG_REPORT_LINES[0]}" = "error: duplicate target catalog_version=v1 target_type=table target_identifier=SALES_DAILY lines=2,5,7" ]
}

@test "target_catalog_report_duplicatesで版が違う同じ対象の場合_重複にしないこと" {
	# Arrange(版を追加する運用: v1 の行を残して v2 に同じ対象を置く)
	bind_row v1 table SALES_DAILY - -
	target_catalog_register_key 2
	bind_row v2 table SALES_DAILY - -
	target_catalog_register_key 3

	# Act / Assert
	target_catalog_report_duplicates
	[ "${#TARGET_CATALOG_REPORT_LINES[@]}" -eq 0 ]
}

@test "target_catalog_report_duplicatesで複数のキーが重複する場合_初出行の昇順に並べること" {
	# Arrange
	bind_row v1 table B - -
	target_catalog_register_key 2
	bind_row v1 table A - -
	target_catalog_register_key 3
	bind_row v1 table A - -
	target_catalog_register_key 4
	bind_row v1 table B - -
	target_catalog_register_key 5

	# Act
	target_catalog_report_duplicates || true

	# Assert
	[ "${#TARGET_CATALOG_REPORT_LINES[@]}" -eq 2 ]
	[ "${TARGET_CATALOG_REPORT_LINES[0]}" = "error: duplicate target catalog_version=v1 target_type=table target_identifier=B lines=2,5" ]
	[ "${TARGET_CATALOG_REPORT_LINES[1]}" = "error: duplicate target catalog_version=v1 target_type=table target_identifier=A lines=3,4" ]
}

@test "target_catalog_register_keyでキーの列が空の行の場合_重複検査の対象にしないこと" {
	# Arrange
	bind_row "" table X - -
	target_catalog_register_key 2
	bind_row "" table X - -
	target_catalog_register_key 3

	# Act / Assert
	target_catalog_report_duplicates
	[ "${#TARGET_CATALOG_REPORT_LINES[@]}" -eq 0 ]
}

@test "target_catalog_versions_summaryで版が初出順にv2とv1の場合_初出順のカンマ区切りであること" {
	# Arrange
	bind_row v2 table A - -
	target_catalog_register_aggregates
	bind_row v1 file B - -
	target_catalog_register_aggregates
	bind_row v2 file C - -
	target_catalog_register_aggregates

	# Act
	target_catalog_versions_summary

	# Assert(集計も初出順。tables / files は target_type ごとの行数)
	[ "$TARGET_CATALOG_VERSIONS_SUMMARY" = "v2,v1" ]
	[ "$TARGET_CATALOG_TABLE_COUNT" -eq 1 ]
	[ "$TARGET_CATALOG_FILE_COUNT" -eq 2 ]
}

@test "target_catalog_versions_summaryで行が無い場合_空値表記であること" {
	# Arrange / Act
	target_catalog_versions_summary

	# Assert
	[ "$TARGET_CATALOG_VERSIONS_SUMMARY" = "-" ]
}

@test "target_catalog_register_aggregatesでtarget_typeが列挙外の場合_tablesにもfilesにも数えないこと" {
	# Arrange
	bind_row v1 view A - -

	# Act
	target_catalog_register_aggregates

	# Assert
	[ "$TARGET_CATALOG_TABLE_COUNT" -eq 0 ]
	[ "$TARGET_CATALOG_FILE_COUNT" -eq 0 ]
}

@test "target_catalog_row_checked_lineで識別子に制御文字を含む場合_info行を可視表記で出すこと" {
	# Arrange
	bind_row v1 file $'/data/out/x\ty.tsv' - -

	# Act
	target_catalog_row_checked_line 3

	# Assert
	[ "${TARGET_CATALOG_REPORT_LINES[0]}" = 'info: checked target_identifier=/data/out/x\ty.tsv catalog_version=v1 target_type=file line=3' ]
	[ "$TARGET_CATALOG_ERROR_COUNT" -eq 0 ]
}
