#!/usr/bin/env bats
# UC dcd8234d × tier-final-crosscheck: validate-config.sh --target-catalog の単体テスト(S2 test-scaffold の red baseline)。
# validate-config.sh の本体は tier-facade が所有し(UC「feature flag を設定する」)、本 tier は `--target-catalog` の
# サブ検証関数 validate_target_catalog を提供する(tier-final-crosscheck.md「変更概要」)。
# facade のエントリポイント(facade/bin/validate-config.sh)経由で実プロセスとして起動する。I/O 境界は実ファイル(一時ディレクトリ)。
# S2 時点では `--target-catalog` の usecase 委譲(validate_config_target_catalog)が未実装のため、
# "error: validation kind is not implemented option=--target-catalog"(終了コード 6)を理由に fail する。
# 仕様: tier-final-crosscheck.md「コマンド契約 / 出力契約 / 設定契約 / 検証ルール一覧」
# run は stdout と stderr を結合して受ける(先行 UC のテストと同じ方式。CI の bats 版に依存しない)。

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../../facade/bin/validate-config.sh"
	CATALOG="$BATS_TEST_TMPDIR/target-catalog.csv"
}

# ヘッダー + table 1 行 + file 1 行の妥当な対象カタログ(tier BDD「妥当な対象カタログを検証する」と同じ構成)
write_valid_catalog() {
	{
		printf '%s\n' 'catalog_version,target_type,target_identifier,compare_condition,business_date_handling'
		printf '%s\n' 'v1,table,SALES_DAILY,key=sales_id,column=business_date'
		printf '%s\n' 'v1,file,/data/out/summary_{business_date}.tsv,-,filename'
	} >"$CATALOG"
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
	found=false
	for line in "${lines[@]}"; do
		if [ "$line" = "error: target_type is not in table,file line=3 value=view" ]; then found=true; fi
	done
	[ "$found" = true ]
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
	found=false
	for line in "${lines[@]}"; do
		if [ "$line" = "error: duplicate target catalog_version=v1 target_type=table target_identifier=SALES_DAILY lines=2,3" ]; then found=true; fi
	done
	[ "$found" = true ]
}
