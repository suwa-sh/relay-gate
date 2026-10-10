#!/usr/bin/env bats
# UC dcd8234d × tier-final-crosscheck: usecase 層 validate_target_catalog の単体テスト。I/O 境界は実ファイル(一時ディレクトリ)。
# 仕様: tier-final-crosscheck.md「出力契約」「検証ルール一覧」「UC ロジック」/ 契約 config_input_rules(rules / snapshot / internal_failure)
# 依存する tier-facade の関数(cli_field_* / job_map_repo_load)は facade/src を読むだけで使う
# (docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md)。
# usecase の関数をサブシェルで直接呼び、stdout と stderr を分けて受ける。
bats_require_minimum_version 1.5.0

setup() {
	source "$BATS_TEST_DIRNAME/../../../facade/src/domain/cli_field.sh"
	source "$BATS_TEST_DIRNAME/../../../facade/src/repository/job_map_repo.sh"
	source "$BATS_TEST_DIRNAME/../../src/domain/target_catalog.sh"
	source "$BATS_TEST_DIRNAME/../../src/repository/target_catalog_repo.sh"
	source "$BATS_TEST_DIRNAME/../../src/usecase/validate_target_catalog.sh"
	CATALOG="$BATS_TEST_TMPDIR/target-catalog.csv"
	HEADER='catalog_version,target_type,target_identifier,compare_condition,business_date_handling'
}

@test "validate_target_catalogで違反が複数ある場合_行順のerror_重複_hintの順でstderrに出しstdoutはinvalidとviolationsで締めること" {
	# Arrange(2 行目 view、3 行目と 4 行目が重複、5 行目が列数不一致)
	printf '%s\n' "$HEADER" 'v1,view,A,-,-' 'v1,table,B,-,-' 'v1,table,B,-,-' 'a,b' >"$CATALOG"

	# Act
	run --separate-stderr validate_target_catalog "$CATALOG" false

	# Assert
	[ "$status" -eq 2 ]
	[ "${#stderr_lines[@]}" -eq 4 ]
	[ "${stderr_lines[0]}" = "error: target_type is not in table,file line=2 value=view" ]
	[ "${stderr_lines[1]}" = "error: column count mismatch line=5 expected=5 actual=2" ]
	[ "${stderr_lines[2]}" = "error: duplicate target catalog_version=v1 target_type=table target_identifier=B lines=3,4" ]
	[ "${stderr_lines[3]}" = "hint: fix the rows above and rerun validate-config.sh --target-catalog $CATALOG" ]
	[ "${#lines[@]}" -eq 8 ]
	[ "${lines[0]}" = "config=target-catalog" ]
	[ "${lines[1]}" = "path: $CATALOG" ]
	[ "${lines[2]}" = "rows=4" ]
	[ "${lines[3]}" = "catalog_versions=v1" ]
	[ "${lines[4]}" = "tables=2" ]
	[ "${lines[5]}" = "files=0" ]
	[ "${lines[6]}" = "status=invalid" ]
	[ "${lines[7]}" = "violations=3" ]
}

@test "validate_target_catalogでverboseの場合_通過した行だけinfo_checkedをstderrに出すこと" {
	# Arrange
	printf '%s\n' "$HEADER" 'v1,table,A,-,-' 'v1,view,B,-,-' >"$CATALOG"

	# Act
	run --separate-stderr validate_target_catalog "$CATALOG" true

	# Assert(違反行は info を出さない。終了コードには影響しない)
	[ "$status" -eq 2 ]
	[ "${stderr_lines[0]}" = "info: checked target_identifier=A catalog_version=v1 target_type=table line=2" ]
	[ "${stderr_lines[1]}" = "error: target_type is not in table,file line=3 value=view" ]
}

@test "validate_target_catalogでヘッダーだけの場合_rows=0とcatalog_versions=-で検証OKであること" {
	# Arrange(config_input_rules: データ行 0 件は受理)
	printf '%s\n' "$HEADER" '# comment' >"$CATALOG"

	# Act
	run --separate-stderr validate_target_catalog "$CATALOG" false

	# Assert
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 0 ]
	[ "${lines[2]}" = "rows=0" ]
	[ "${lines[3]}" = "catalog_versions=-" ]
	[ "${lines[4]}" = "tables=0" ]
	[ "${lines[5]}" = "files=0" ]
	[ "${lines[6]}" = "status=valid" ]
}

@test "validate_target_catalogで空のファイルの場合_actualが空のheader_mismatchでstdoutを出さないこと" {
	# Arrange
	: >"$CATALOG"

	# Act
	run --separate-stderr validate_target_catalog "$CATALOG" false

	# Assert
	[ "$status" -eq 2 ]
	[ "${#lines[@]}" -eq 0 ]
	[ "${stderr_lines[0]}" = "error: header mismatch expected=$HEADER actual= path: $CATALOG" ]
	[ "${stderr_lines[1]}" = "hint: fix the rows above and rerun validate-config.sh --target-catalog $CATALOG" ]
}

@test "validate_target_catalogでヘッダーの列名が重複する場合_duplicate_columnとheader_mismatchを出すこと" {
	# Arrange
	printf '%s\n' 'catalog_version,catalog_version,target_identifier,compare_condition,business_date_handling' 'v1,table,X,-,-' >"$CATALOG"

	# Act
	run --separate-stderr validate_target_catalog "$CATALOG" false

	# Assert
	[ "$status" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: duplicate column column=catalog_version path: $CATALOG" ]
	[[ "${stderr_lines[1]}" == "error: header mismatch expected=$HEADER actual=catalog_version,catalog_version,"* ]]
}

@test "validate_target_catalogでヘッダー行のクォートが不正な場合_ヘッダーと行のクォート不正を全件出すこと" {
	# Arrange
	printf '%s\n' '"catalog_version,target_type,target_identifier,compare_condition,business_date_handling' 'v1,table,"X,-,-' >"$CATALOG"

	# Act
	run --separate-stderr validate_target_catalog "$CATALOG" false

	# Assert
	[ "$status" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: csv quote is invalid line=1 path: $CATALOG" ]
	[ "${stderr_lines[1]}" = "error: csv quote is invalid line=2 path: $CATALOG" ]
	[ "${#lines[@]}" -eq 0 ]
}

@test "validate_target_catalogでCRLF改行の場合_行ごとのcarriage_returnとhint_use_LFで拒否すること" {
	# Arrange
	printf '%s\r\n' "$HEADER" 'v1,table,X,-,-' >"$CATALOG"

	# Act
	run --separate-stderr validate_target_catalog "$CATALOG" false

	# Assert(形式違反の行があればヘッダー・行の検証には進まず stdout も出さない)
	[ "$status" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: carriage return is not allowed line=1 path: $CATALOG" ]
	[ "${stderr_lines[1]}" = "error: carriage return is not allowed line=2 path: $CATALOG" ]
	[ "${stderr_lines[2]}" = "hint: use LF line endings" ]
	[ "${stderr_lines[3]}" = "hint: fix the rows above and rerun validate-config.sh --target-catalog $CATALOG" ]
	[ "${#lines[@]}" -eq 0 ]
}

@test "validate_target_catalogでBOMとNULと不正なUTF-8を含む場合_原因ごとの文言で行番号を出すこと" {
	# Arrange(1 行目 BOM、2 行目 NUL、3 行目 不正な UTF-8)
	printf '\xef\xbb\xbf%s\nv1,table,A\x00B,-,-\nv1,file,\xe3\x81,-,-\n' "$HEADER" >"$CATALOG"

	# Act
	run --separate-stderr validate_target_catalog "$CATALOG" false

	# Assert
	[ "$status" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: byte order mark is not allowed line=1 path: $CATALOG" ]
	[ "${stderr_lines[1]}" = "error: nul byte is not allowed line=2 path: $CATALOG" ]
	[ "${stderr_lines[2]}" = "error: encoding is not utf-8 line=3 path: $CATALOG" ]
}

@test "validate_target_catalogでファイルが読めない場合_not_readableで終了コード2であること" {
	# Arrange(ディレクトリは通常ファイルではない)
	mkdir -p "$BATS_TEST_TMPDIR/dir.csv"

	# Act
	run --separate-stderr validate_target_catalog "$BATS_TEST_TMPDIR/dir.csv" false

	# Assert
	[ "$status" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: config file is not readable path: $BATS_TEST_TMPDIR/dir.csv" ]
}

@test "validate_target_catalogでパスに制御文字を含む場合_path表示を可視表記にすること" {
	# Arrange
	local weird="$BATS_TEST_TMPDIR/"$'a\tb.csv'
	printf '%s\n' "$HEADER" 'v1,table,X,-,-' >"$weird"

	# Act
	run --separate-stderr validate_target_catalog "$weird" false

	# Assert
	[ "$status" -eq 0 ]
	[ "${lines[1]}" = "path: $BATS_TEST_TMPDIR/a\\tb.csv" ]
}

@test "validate_target_catalogでTMPDIRに書けない場合_config_snapshot_failedで終了コード6でstdoutを出さないこと" {
	# Arrange(入力の複製の失敗。config_input_rules.internal_failure)
	printf '%s\n' "$HEADER" 'v1,table,X,-,-' >"$CATALOG"
	export TMPDIR="$BATS_TEST_TMPDIR/nonexistent-tmp"

	# Act
	run --separate-stderr validate_target_catalog "$CATALOG" false

	# Assert
	[ "$status" -eq 6 ]
	[ "${#lines[@]}" -eq 0 ]
	[ "${stderr_lines[0]}" = "error: config snapshot failed path: $CATALOG" ]
	[ "${stderr_lines[1]}" = "hint: check TMPDIR is writable" ]
}

@test "validate_target_catalogで補助コマンドsedが失敗する場合_internal_command_failedで終了コード6であること" {
	# Arrange(PATH の先頭に失敗する sed を置く。契約 snapshot.out_of_scope が認める確認方法)
	printf '%s\n' "$HEADER" 'v1,table,X,-,-' >"$CATALOG"
	mkdir -p "$BATS_TEST_TMPDIR/bin"
	printf '#!/usr/bin/env bash\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/sed"
	chmod +x "$BATS_TEST_TMPDIR/bin/sed"
	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

	# Act
	run --separate-stderr validate_target_catalog "$CATALOG" false

	# Assert
	[ "$status" -eq 6 ]
	[ "${#lines[@]}" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: internal command failed commands=sed path: $CATALOG" ]
}
