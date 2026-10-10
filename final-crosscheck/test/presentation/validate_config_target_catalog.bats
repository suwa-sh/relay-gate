#!/usr/bin/env bats
# UC dcd8234d × tier-final-crosscheck: validate-config.sh --target-catalog の単体テスト
# (S2 test-scaffold の red baseline を S4 で green にした。usecase 委譲は validate_config_target_catalog)。
# validate-config.sh の本体は tier-facade が所有し(UC「feature flag を設定する」)、本 tier は `--target-catalog` の
# handler(src/presentation/validate_config_target_catalog.sh)と検証ロジック validate_target_catalog を提供する(tier-final-crosscheck.md「変更概要」)。
# facade のエントリポイント(facade/bin/validate-config.sh)経由で実プロセスとして起動する。I/O 境界は実ファイル(一時ディレクトリ)。
# 仕様: tier-final-crosscheck.md「コマンド契約 / 出力契約 / 設定契約 / 検証ルール一覧」/ spec.md E2E(SPEC-004-04)
# run は stdout と stderr を結合して受ける(先行 UC のテストと同じ方式。CI の bats 版に依存しない)。

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../../facade/bin/validate-config.sh"
	CATALOG="$BATS_TEST_TMPDIR/target-catalog.csv"
	HEADER='catalog_version,target_type,target_identifier,compare_condition,business_date_handling'
}

# ヘッダー + table 1 行 + file 1 行の妥当な対象カタログ(tier BDD「妥当な対象カタログを検証する」と同じ構成)
write_valid_catalog() {
	{
		printf '%s\n' 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling'
		printf '%s\n' 'v1,table,SALES_DAILY,key=sales_id,column=business_date'
		printf '%s\n' 'v1,file,/data/out/summary_{business_date}.tsv,-,filename'
	} >"$CATALOG"
}

# 結合出力に期待する行が含まれるか
has_line() {
	local line
	for line in "${lines[@]}"; do
		if [ "$line" = "$1" ]; then return 0; fi
	done
	return 1
}

@test "validate-config_sh_--target-catalogで妥当なカタログの場合_終了コード0で契約の7行を順序どおり出すこと" {
	# Arrange
	write_valid_catalog

	# Act
	run "$SCRIPT" --target-catalog "$CATALOG"

	# Assert(違反が無いので stderr は空。結合出力は stdout の 7 行だけ。順序は出力契約の固定順)
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 7 ]
	[ "${lines[0]}" = "config=target-catalog" ]
	[ "${lines[1]}" = "path: $CATALOG" ]
	[ "${lines[2]}" = "rows=2" ]
	[ "${lines[3]}" = "catalog_versions=v1" ]
	[ "${lines[4]}" = "tables=1" ]
	[ "${lines[5]}" = "files=1" ]
	[ "${lines[6]}" = "status=valid" ]
}

@test "validate-config_sh_--target-catalogでファイルが無い場合_config file not foundで終了コード2であること" {
	# Arrange / Act
	run "$SCRIPT" --target-catalog /nonexistent/target-catalog.csv

	# Assert
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "error: config file not found path: /nonexistent/target-catalog.csv" ]
}

@test "validate-config_sh_--target-catalogでtarget_typeがviewの場合_行番号付きerrorで終了コード2であること" {
	# Arrange(3 行目の file 行を view に変える)
	write_valid_catalog
	sed -i.bak '3s/^v1,file,/v1,view,/' "$CATALOG"

	# Act
	run "$SCRIPT" --target-catalog "$CATALOG"

	# Assert
	[ "$status" -eq 2 ]
	has_line "error: target_type is not in table,file line=3 value=view"
}

@test "validate-config_sh_--target-catalogで同一版内の対象が重複する場合_初出行を含むlines=で終了コード2であること" {
	# Arrange(3 行目を 2 行目の複製にする。物理行は 2 と 3)
	write_valid_catalog
	sed -i.bak '3d' "$CATALOG"
	printf '%s\n' 'v1,table,SALES_DAILY,key=sales_id,column=business_date' >>"$CATALOG"

	# Act
	run "$SCRIPT" --target-catalog "$CATALOG"

	# Assert
	[ "$status" -eq 2 ]
	has_line "error: duplicate target catalog_version=v1 target_type=table target_identifier=SALES_DAILY lines=2,3"
}

# ---- S4 tier-impl で追加 ----

@test "validate-config_sh_--target-catalogで値を省略した場合_option_requiredで終了コード2であること" {
	# Arrange / Act(値必須。既定パスによる補完はしない。判定はエントリポイント側)
	run "$SCRIPT" --target-catalog

	# Assert
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "error: option required option=--target-catalog" ]
}

@test "validate-config_sh_--target-catalogに--verboseを付けた場合_行ごとのinfo_checkedを出すこと" {
	# Arrange
	write_valid_catalog

	# Act
	run "$SCRIPT" --target-catalog "$CATALOG" --verbose

	# Assert
	[ "$status" -eq 0 ]
	has_line "info: checked target_identifier=SALES_DAILY catalog_version=v1 target_type=table line=2"
	has_line "info: checked target_identifier=/data/out/summary_{business_date}.tsv catalog_version=v1 target_type=file line=3"
	has_line "status=valid"
}

@test "validate-config_sh_--target-catalogで版を追加した場合_catalog_versionsが初出順のカンマ区切りであること" {
	# Arrange(版を追加する運用: v1 を残して v2 を追加)
	write_valid_catalog
	printf '%s\n' 'v2,table,SALES_DAILY,key=sales_id,column=business_date' >>"$CATALOG"

	# Act
	run "$SCRIPT" --target-catalog "$CATALOG"

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[2]}" = "rows=3" ]
	[ "${lines[3]}" = "catalog_versions=v1,v2" ]
	[ "${lines[4]}" = "tables=2" ]
	[ "${lines[5]}" = "files=1" ]
}

@test "validate-config_sh_--target-catalogでカンマを含む引用セルの場合_1セルとして解析し検証OKであること" {
	# Arrange(SPEC-004-04: 囲んだセルはカンマを含む 1 セル)
	{
		printf '%s\n' "$HEADER"
		printf '%s\n' 'v1,table,SALES_DAILY,"key=sales_id,branch_id",column=business_date'
	} >"$CATALOG"

	# Act
	run "$SCRIPT" --target-catalog "$CATALOG"

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[2]}" = "rows=1" ]
	[ "${lines[6]}" = "status=valid" ]
}

@test "validate-config_sh_--target-catalogでタブ区切りのファイルの場合_header_mismatchで拒否すること" {
	# Arrange(SPEC-004-04: タブ区切りは 1 セルの列名として header mismatch)
	printf 'catalog_version\ttarget_type\ttarget_identifier\tcompare_condition\tbusiness_date_handling\nv1\ttable\tX\t-\t-\n' >"$CATALOG"

	# Act
	run "$SCRIPT" --target-catalog "$CATALOG"

	# Assert
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = 'error: header mismatch expected=catalog_version,target_type,target_identifier,compare_condition,business_date_handling actual=catalog_version\ttarget_type\ttarget_identifier\tcompare_condition\tbusiness_date_handling path: '"$CATALOG" ]
	[ "${lines[1]}" = "hint: fix the rows above and rerun validate-config.sh --target-catalog $CATALOG" ]
}

@test "validate-config_sh_--target-catalogでヘッダー行全体が引用された1セルの場合_header_mismatchで終了コード2であること" {
	# Arrange(S5 F-001 の回帰: 1 行目を二重引用符で囲むと解析後は 1 セル。5 列の定義と一致しない)
	printf '%s\n' "\"$HEADER\"" 'v1,table,A,-,-' >"$CATALOG"

	# Act
	run "$SCRIPT" --target-catalog "$CATALOG"

	# Assert(stdout の集計は出ず、結合出力は error + hint の 2 行)
	[ "$status" -eq 2 ]
	[ "${#lines[@]}" -eq 2 ]
	[ "${lines[0]}" = "error: header mismatch expected=$HEADER actual=\"$HEADER\" path: $CATALOG" ]
	[ "${lines[1]}" = "hint: fix the rows above and rerun validate-config.sh --target-catalog $CATALOG" ]
}

@test "validate-config_sh_--target-catalogでヘッダーの先頭2列が引用で結合された4セルの場合_header_mismatchで終了コード2であること" {
	# Arrange(S5 F-001 の回帰: `"catalog_version,target_type",...` は 4 セル)
	printf '%s\n' '"catalog_version,target_type",target_identifier,compare_condition,business_date_handling' 'v1,table,A,-,-' >"$CATALOG"

	# Act
	run "$SCRIPT" --target-catalog "$CATALOG"

	# Assert
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "error: header mismatch expected=$HEADER actual=\"catalog_version,target_type\",target_identifier,compare_condition,business_date_handling path: $CATALOG" ]
}

@test "validate-config_sh_--target-catalogでslotジョブマップのヘッダーの場合_header_mismatchで拒否すること" {
	# Arrange(設定所有区分: slot ジョブマップの列が混入)
	printf '%s\n' 'job_id,work_dir,script,fixed_params,hang_detect_limit_minutes' >"$CATALOG"

	# Act
	run "$SCRIPT" --target-catalog "$CATALOG"

	# Assert
	[ "$status" -eq 2 ]
	[ "${lines[0]}" = "error: header mismatch expected=$HEADER actual=job_id,work_dir,script,fixed_params,hang_detect_limit_minutes path: $CATALOG" ]
}

@test "validate-config_sh_--target-catalogで違反がある場合_stdoutをstatus=invalidとviolations=Nで締めること" {
	# Arrange
	write_valid_catalog
	sed -i.bak '3s/^v1,file,/v1,view,/' "$CATALOG"

	# Act
	run "$SCRIPT" --target-catalog "$CATALOG"

	# Assert(結合出力: stderr の error + hint の後に stdout の 8 行)
	[ "$status" -eq 2 ]
	has_line "status=invalid"
	has_line "violations=1"
	has_line "hint: fix the rows above and rerun validate-config.sh --target-catalog $CATALOG"
}

@test "validate-config_sh_--target-catalogでNFR共通前提の最悪条件5000行の場合_10秒以内に終了コード0であること" {
	# Arrange(nfr-grade B.1.1.2 の共通前提: ヘッダーを除いて 5,000 行、全列に値があり、対象が全行一意、版が全行異なる。
	#         B.2.1.1: 内容によらず 10 秒以内。行数に比例する時間で処理できること(重複検査・版の集計を全組合せ比較にしない))
	{
		printf '%s\n' "$HEADER"
		index=1
		while [ "$index" -le 5000 ]; do
			printf 'v%d,table,TABLE_%05d,"key=id,branch_id",column=business_date\n' "$index" "$index"
			index=$((index + 1))
		done
	} >"$CATALOG"
	SECONDS=0

	# Act
	run "$SCRIPT" --target-catalog "$CATALOG"

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[2]}" = "rows=5000" ]
	[[ "${lines[3]}" == "catalog_versions=v1,v2,"* ]]
	[ "${lines[4]}" = "tables=5000" ]
	[ "$SECONDS" -lt 10 ]
}

@test "validate-config_sh_--target-catalogでNFR共通前提の最悪条件5000行にverboseを付けた場合_10秒以内に終了コード0であること" {
	# Arrange(--verbose は 1 行 1 対象の info を出す。出力量が行数に比例しても 10 秒以内)
	{
		printf '%s\n' "$HEADER"
		index=1
		while [ "$index" -le 5000 ]; do
			printf 'v1,file,/data/out/file_%05d.tsv,-,filename\n' "$index"
			index=$((index + 1))
		done
	} >"$CATALOG"
	SECONDS=0

	# Act
	run "$SCRIPT" --target-catalog "$CATALOG" --verbose

	# Assert
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "${lines[@]}" | grep -c '^info: checked target_identifier=')" -eq 5000 ]
	[ "$SECONDS" -lt 10 ]
}
