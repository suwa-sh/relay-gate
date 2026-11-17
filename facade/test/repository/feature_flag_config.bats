#!/usr/bin/env bats
# UC fd678b04(feature flag を設定する)× tier-facade: repository 層 FeatureFlagConfig(env 読み込み)の単体テスト。
# I/O 境界(ファイル)は実体(一時ファイル)で検証する(docs/dev-rules/test-strategy.md)。

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/feature_flag.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/repository/feature_flag_config.sh"
	ENV_FILE="$BATS_TEST_TMPDIR/ff.env"
}

@test "feature_flag_config_load_9キーを書いた場合_同名のグローバル変数に値が載ること" {
	# Arrange
	printf 'BLUE_MODE=foreground\nGREEN_MODE=background\nRAPID_CROSSCHECK_MODE=background\nBLUE_IMPL=blue-2.3.1\nGREEN_IMPL=green-1.4.0\nBLUE_RUNNER=/opt/b.sh\nGREEN_RUNNER=/opt/g.sh\nRAPID_CROSSCHECK_RUNNER=/opt/r.sh\nRAPID_CROSSCHECK_WORKER=/opt/w.sh\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_MODE" = "foreground" ]
	[ "$GREEN_MODE" = "background" ]
	[ "$RAPID_CROSSCHECK_MODE" = "background" ]
	[ "$BLUE_IMPL" = "blue-2.3.1" ]
	[ "$GREEN_IMPL" = "green-1.4.0" ]
	[ "$BLUE_RUNNER" = "/opt/b.sh" ]
	[ "$GREEN_RUNNER" = "/opt/g.sh" ]
	[ "$RAPID_CROSSCHECK_RUNNER" = "/opt/r.sh" ]
	[ "$RAPID_CROSSCHECK_WORKER" = "/opt/w.sh" ]
	[ "${#FEATURE_FLAG_KEYS[@]}" -eq 9 ]
	[ "$FEATURE_FLAG_PATH" = "$ENV_FILE" ]
}

@test "feature_flag_config_load_コメント行と空行がある場合_無視されること" {
	# Arrange(コメント行 = 前後の空白(半角空白とタブ)を除いて # で始まる行。空行 = 0 バイトの行。
	#   空白だけの行は invalid line のため、ここには置かない。契約 config_input_rules.env_files)
	printf '# comment\n\nBLUE_MODE=off\n  # indented comment\n\t# BLUE_MODE=background\nGREEN_MODE=foreground\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_MODE" = "off" ]
	[ "$GREEN_MODE" = "foreground" ]
	[ "${#FEATURE_FLAG_KEYS[@]}" -eq 2 ]
}

@test "feature_flag_config_load_値がクォートされている場合_先頭末尾のクォートが除去されること" {
	# Arrange
	printf 'BLUE_IMPL="blue-2.3.1"\nGREEN_IMPL='"'"'green-1.4.0'"'"'\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_IMPL" = "blue-2.3.1" ]
	[ "$GREEN_IMPL" = "green-1.4.0" ]
}

@test "feature_flag_config_load_値にシェル変数展開やコマンド置換がある場合_展開せず文字列のまま載ること" {
	# Arrange
	printf 'BLUE_IMPL=$HOME/x\nGREEN_IMPL=$(echo injected)\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_IMPL" = '$HOME/x' ]
	[ "$GREEN_IMPL" = '$(echo injected)' ]
}

@test "feature_flag_config_load_9キー以外のキーがある場合_キー一覧には載るが変数化されないこと" {
	# Arrange(プロセス環境の PATH 等を env ファイルで上書きさせない)
	local path_before="$PATH"
	printf 'PATH=/evil\nCONFIG_VERSION=cfg-v1\nBLUE_MODE=off\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$PATH" = "$path_before" ]
	[ -z "${CONFIG_VERSION:-}" ]
	[ "${FEATURE_FLAG_KEYS[0]}" = "PATH" ]
	[ "${FEATURE_FLAG_KEYS[1]}" = "CONFIG_VERSION" ]
	[ "${FEATURE_FLAG_KEYS[2]}" = "BLUE_MODE" ]
}

@test "feature_flag_config_load_プロセス環境に同名変数がある場合_envファイルに無いキーは未設定に戻ること" {
	# Arrange
	export BLUE_IMPL="from-process-env"
	printf 'BLUE_MODE=off\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ -z "${BLUE_IMPL:-}" ]
	[ "$BLUE_MODE" = "off" ]
}

@test "feature_flag_config_load_値に=を含む場合_最初の=で分割されること" {
	# Arrange
	printf 'BLUE_IMPL=a=b=c\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_IMPL" = "a=b=c" ]
}

@test "feature_flag_config_load_最終行に改行が無い場合_最終行も読めること" {
	# Arrange(契約 config_input_rules.rules「最終行の改行なし」は受理)
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_MODE" = "off" ]
	[ "$GREEN_MODE" = "foreground" ]
}

# ---- S2 test-scaffold 再実行(2026-11-13)で追加・整理: 契約 config_input_rules.env_files のキーと値の取り出し方 ----
# 削除した場面(仕様から消えたため): 同じキーの重複は後の行が勝つ / CRLF の CR を落として読む /
#   `=` の無い行をキーだけの行として読む(いずれも現在は拒否。拒否の文言・順・終了コードは
#   test/usecase/validate_feature_flag_env_rules.bats がエントリポイント経由で検証する)

@test "feature_flag_config_load_キーと値の前後に空白がある場合_半角空白とタブを除いて載ること" {
	# Arrange(取り出し方 (2)(3)。例: ` KEY = 'a b' ` → キー KEY・値 `a b`)
	printf " BLUE_IMPL = 'a b' \n\tGREEN_IMPL\t=\tgreen-1.4.0\t\n" >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_IMPL" = "a b" ]
	[ "$GREEN_IMPL" = "green-1.4.0" ]
	[ "${FEATURE_FLAG_KEYS[0]}" = "BLUE_IMPL" ]
	[ "${FEATURE_FLAG_KEYS[1]}" = "GREEN_IMPL" ]
}

@test "feature_flag_config_load_引用符の内側に空白がある場合_内側の空白は残ること" {
	# Arrange(取り出し方 (4)。例: `KEY="  a  "` → 値 `  a  `)
	printf 'BLUE_IMPL="  a  "\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_IMPL" = "  a  " ]
}

@test "feature_flag_config_load_引用符が片側だけや種類違いの場合_先頭と末尾を別々に1文字ずつ外すこと" {
	# Arrange(取り出し方 (4)。例: `"abc` → abc、`abc'` → abc、`"abc'` → abc。対や種類の一致は求めない)
	printf 'BLUE_IMPL="abc\nGREEN_IMPL=abc'"'"'\nBLUE_RUNNER="abc'"'"'\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_IMPL" = "abc" ]
	[ "$GREEN_IMPL" = "abc" ]
	[ "$BLUE_RUNNER" = "abc" ]
}

@test "feature_flag_config_load_値の先頭が#の場合_コメントにせず値に残ること" {
	# Arrange(`KEY=#abc` はコメント行ではなく値 `#abc`。行の途中の # を行末コメントにする規則は無い)
	printf 'BLUE_IMPL=#v1\nGREEN_IMPL=g # not a comment\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_IMPL" = "#v1" ]
	[ "$GREEN_IMPL" = "g # not a comment" ]
}

@test "feature_flag_config_load_値の前後に改ページや垂直タブがある場合_空白として除かず値に残ること" {
	# Arrange(env の空白は半角空白 0x20 とタブ 0x09 だけ。契約 config_input_rules.env_files)
	printf 'BLUE_IMPL=\fabc\v\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$BLUE_IMPL" = $'\fabc\v' ]
}

# ---- S4 tier-impl(2026-11-13 attempt-5)で追加: 行の構造の取り出しを sed 1 回で行う(長い行でも行の長さに比例する時間) ----
# 性能目標は「5,000 行以内かつ 8 MB 以内のファイルを、内容によらず 10 秒以内」(目標値。入力を制限する仕様ではない)。

@test "feature_flag_config_load_種類を表す文字と同じ内容の行やキーがある場合_行の種類を取り違えないこと" {
	# Arrange(sed は 1 行を e / c / i / k<キー> + v<値> に直して渡す。同じ文字で始まる入力と混同しない)
	printf 'e\nc\ni\nk=1\nv=2\ne=3\nkBLUE_MODE=4\nv\n=5\nBLUE_MODE=off\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert(`=` の無い e / c / i / v と、キーが空の `=5` は形式違反の行。k / v / e / kBLUE_MODE は未知キー)
	[ "${FEATURE_FLAG_CONFIG_INVALID_LINES[*]}" = "1 2 3 8 9" ]
	[ "${FEATURE_FLAG_KEYS[*]}" = "k v e kBLUE_MODE BLUE_MODE" ]
	[ "${#FEATURE_FLAG_CONFIG_DUPLICATE_KEYS[@]}" -eq 0 ]
	[ -z "${BLUE_MODE+x}" ]
}

@test "feature_flag_config_load_キーの後ろと値の前後に空白があり値に=と空白を含む場合_最初の=で分け外側の空白だけを除くこと" {
	# Arrange(半角空白とタブだけを除く。値の内側の空白と 2 つ目以降の = は残す)
	printf '  BLUE_IMPL \t =\t a = b  c \t\nGREEN_IMPL==\nBLUE_RUNNER=\t \nGREEN_RUNNER = "  /opt/g.sh  " \n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "${FEATURE_FLAG_KEYS[*]}" = "BLUE_IMPL GREEN_IMPL BLUE_RUNNER GREEN_RUNNER" ]
	[ "$BLUE_IMPL" = "a = b  c" ]
	[ "$GREEN_IMPL" = "=" ]
	[ "${BLUE_RUNNER-unset}" = "" ]
	[ "$GREEN_RUNNER" = "  /opt/g.sh  " ]
}

@test "feature_flag_config_load_同じキーが3行と別のキーが2行ある場合_初出行の昇順に全出現行を載せること" {
	# Arrange
	printf 'B=1\nA=1\nB=2\n# c\nA=2\n\nB=3\nC=1\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "${FEATURE_FLAG_KEYS[*]}" = "B A C" ]
	[ "${FEATURE_FLAG_CONFIG_DUPLICATE_KEYS[*]}" = "B A" ]
	[ "${FEATURE_FLAG_CONFIG_DUPLICATE_LINES[0]}" = "1,3,7" ]
	[ "${FEATURE_FLAG_CONFIG_DUPLICATE_LINES[1]}" = "2,5" ]
}

@test "feature_flag_config_load_キーが配列の添字として特別な文字やパス名展開の文字の場合_キーごとに別のキーとして載せること" {
	# Arrange(キーの重複の判定に連想配列を使う。@ / * / 式に見えるキー、パス名展開の文字を取り違えない)
	cd "$BATS_TEST_TMPDIR"
	touch a1 a2
	printf '@=1\n*=2\na[$(echo x)]=3\n1+1=4\na*=5\n@=6\n' >"$ENV_FILE"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "${#FEATURE_FLAG_KEYS[@]}" -eq 5 ]
	[ "${FEATURE_FLAG_KEYS[0]}" = "@" ]
	[ "${FEATURE_FLAG_KEYS[1]}" = "*" ]
	[ "${FEATURE_FLAG_KEYS[2]}" = 'a[$(echo x)]' ]
	[ "${FEATURE_FLAG_KEYS[3]}" = "1+1" ]
	[ "${FEATURE_FLAG_KEYS[4]}" = "a*" ]
	[ "${FEATURE_FLAG_CONFIG_DUPLICATE_KEYS[*]}" = "@" ]
	[ "${FEATURE_FLAG_CONFIG_DUPLICATE_LINES[0]}" = "1,6" ]
}

@test "feature_flag_config_load_読み込みの前後_呼び出し元のIFSとパス名展開の設定を変えないこと" {
	# Arrange(sed の出力は単語分割で行に分ける。関数の外の設定に影響させない)
	printf 'BLUE_MODE=off\nX=*\n' >"$ENV_FILE"
	local ifs_before="$IFS" options_before="$-"

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$IFS" = "$ifs_before" ]
	[ "$-" = "$options_before" ]
	[ "$BLUE_MODE" = "off" ]
}

@test "feature_flag_config_load_行の構造を取り出すsedが失敗する場合_補助コマンドの失敗としてsedを報告し値を載せないこと" {
	# Arrange(バイト点検の sed は本物へ通し、行の構造を取り出す sed(スクリプトに s/^$/e/ を含む)だけを失敗させる)
	local fake_bin="$BATS_TEST_TMPDIR/fake-bin" real_sed
	real_sed="$(command -v sed)"
	mkdir -p "$fake_bin"
	printf '%s\n' '#!/bin/sh' 'for arg in "$@"; do' '  case "$arg" in' "    's/^\$/e/') echo 'fake failure' >&2; exit 1 ;;" '  esac' 'done' "exec \"$real_sed\" \"\$@\"" >"$fake_bin/sed"
	chmod +x "$fake_bin/sed"
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\n' >"$ENV_FILE"
	local status_code=0

	# Act
	PATH="$fake_bin:$PATH" feature_flag_config_load "$ENV_FILE" 2>"$BATS_TEST_TMPDIR/err.txt" || status_code=$?

	# Assert
	[ "$status_code" -eq "$FEATURE_FLAG_CONFIG_STATUS_COMMAND_FAILED" ]
	[ "$FEATURE_FLAG_CONFIG_FAILED_COMMANDS" = "sed" ]
	[ "${#FEATURE_FLAG_KEYS[@]}" -eq 0 ]
	[ -z "${BLUE_MODE+x}" ]
	[ "$FEATURE_FLAG_PATH" = "$ENV_FILE" ]
	[ ! -s "$BATS_TEST_TMPDIR/err.txt" ]
}

# bats test_tags=heavy
@test "feature_flag_config_load_1行が8MBでキーの前後と値の前後に数MBの空白がある場合_10秒以内に空白を除いて載せること" {
	# Arrange(行の長さに上限は無い。空白の並びが長くても、行の長さに比例する時間で読む)
	local blanks=" " tabs=$'\t' index
	for ((index = 0; index < 21; index++)); do
		blanks+="$blanks"
		tabs+="$tabs"
	done
	printf '%sGREEN_IMPL%s=%s"a  b"%s\n' "${blanks:0:2000000}" "${tabs:0:2000000}" "${blanks:0:2000000}" "${tabs:0:2000000}" >"$ENV_FILE"
	SECONDS=0

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$SECONDS" -lt 10 ]
	[ "${FEATURE_FLAG_KEYS[*]}" = "GREEN_IMPL" ]
	[ "$GREEN_IMPL" = "a  b" ]
}

# bats test_tags=heavy
@test "feature_flag_config_load_4MBのキーの行と4MBの空白だけの行が2行ある場合_10秒以内にキーと形式違反の行を載せること" {
	# Arrange(= までが 4 MB のキー、空白だけ 4 MB の行(形式違反))
	local chunk="abcdefgh" blanks=" " index
	for ((index = 0; index < 19; index++)); do
		chunk+="$chunk"
		blanks+="$blanks"
	done
	printf '%s=x\n%s\n' "$chunk" "$blanks" >"$ENV_FILE"
	printf '%s\t\n' "$blanks" >>"$ENV_FILE"
	SECONDS=0

	# Act
	feature_flag_config_load "$ENV_FILE"

	# Assert
	[ "$SECONDS" -lt 10 ]
	[ "${#FEATURE_FLAG_KEYS[@]}" -eq 1 ]
	[ "${#FEATURE_FLAG_KEYS[0]}" -eq 4194304 ]
	[ "${FEATURE_FLAG_CONFIG_INVALID_LINES[*]}" = "2 3" ]
}
