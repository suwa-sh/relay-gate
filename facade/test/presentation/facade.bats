#!/usr/bin/env bats
# UC 09730858 × tier-facade: ジョブを起動するコマンド bin/facade.sh の入口の単体テスト(S2 test-scaffold の最初の failing テスト)。
# 出典: tier-facade.md「コマンド契約」「出力契約」「UC ロジック」。判定するのは入口から見える振る舞いだけで、
# src/ の関数の分け方は固定しない(層ごとの単体テストは S4 の TDD で足す)。
# runner は BATS_TEST_TMPDIR に置く実スクリプトのスタブ(標準の runner は --help 以外は仮の応答のため使わない)。
# RAPID_CROSSCHECK_MODE=off の設定だけを使うため、管理 DB は要らない。
# 時間を確かめるテストは書かない。リポジトリの中にファイルを書かない(書くのは BATS_TEST_TMPDIR だけ)。

bats_require_minimum_version 1.5.0

setup() {
	HOME_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	FACADE="$HOME_DIR/bin/facade.sh"
	CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	ARTIFACT_ROOT="$BATS_TEST_TMPDIR/artifacts"
	LOG_DIR="$BATS_TEST_TMPDIR/logs"
	STUB_DIR="$BATS_TEST_TMPDIR/stubs"
	mkdir -p "$CONFIG_DIR" "$ARTIFACT_ROOT" "$LOG_DIR" "$STUB_DIR"
}

# facade.sh が無い間は「未実装」を理由に落とす(存在しないコマンドの起動エラーを red の理由にしない)
require_facade() {
	[ -f "$FACADE" ] || {
		echo "not implemented: $FACADE does not exist"
		return 1
	}
	[ -x "$FACADE" ]
}

# 起動引数を <スタブ>.invoked に 1 行で記録し、自分の role ディレクトリに Runner Result の 3 ファイル(exitcode.txt は 0)を書くスタブ
write_recording_runner() {
	local file="$STUB_DIR/$1"
	cat >"$file" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$0.invoked"
run_id=""
role=""
while [ "$#" -gt 0 ]; do
	case "$1" in
	--run-id)
		run_id="$2"
		shift 2
		;;
	--role)
		role="$2"
		shift 2
		;;
	--) break ;;
	*) shift ;;
	esac
done
dir="$RELAY_GATE_ARTIFACT_ROOT/facade/$run_id/$role"
mkdir -p "$dir"
: >"$dir/stdout.log"
: >"$dir/stderr.log"
echo 0 >"$dir/exitcode.txt"
STUB
	chmod +x "$file"
	printf '%s\n' "$file"
}

write_feature_flag() {
	printf '%s\n' "$@" >"$CONFIG_DIR/feature-flag.env"
}

run_facade() {
	run --separate-stderr env \
		RELAY_GATE_CONFIG_DIR="$CONFIG_DIR" \
		RELAY_GATE_ARTIFACT_ROOT="$ARTIFACT_ROOT" \
		RELAY_GATE_LOG_DIR="$LOG_DIR" \
		"$FACADE" "$@"
}

@test "facade_sh_JOB_IDが無い場合_JOB_ID requiredとhintをstderrに出して終了コード2であること" {
	# Arrange
	require_facade
	local blue
	blue="$(write_recording_runner blue-runner.sh)"
	write_feature_flag "BLUE_MODE=foreground" "GREEN_MODE=off" "RAPID_CROSSCHECK_MODE=off" "BLUE_IMPL=v1" "BLUE_RUNNER=$blue"

	# Act
	run_facade

	# Assert(tier-facade.md のエラーメッセージ表「JOB_ID なし」)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${stderr_lines[0]}" = "error: JOB_ID required" ]
	[ "${stderr_lines[1]}" = "hint: usage: facade.sh JOB_ID [PARAM...]" ]
	[ ! -e "$blue.invoked" ]
}

@test "facade_sh_両slotがforegroundの場合_どのrunnerも起動せず成果物ディレクトリも作らず終了コード2であること" {
	# Arrange
	require_facade
	local blue green
	blue="$(write_recording_runner blue-runner.sh)"
	green="$(write_recording_runner green-runner.sh)"
	write_feature_flag "BLUE_MODE=foreground" "GREEN_MODE=foreground" "RAPID_CROSSCHECK_MODE=off" \
		"BLUE_IMPL=v1" "GREEN_IMPL=v2" "BLUE_RUNNER=$blue" "GREEN_RUNNER=$green"

	# Act
	run_facade JOB001

	# Assert(条件「foreground slot 排他」。検証 NG なら run_id を発行せず成果物ディレクトリも作らない)
	[ "$status" -eq 2 ]
	[ "${stderr_lines[0]}" = "error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground" ]
	[ ! -e "$blue.invoked" ]
	[ ! -e "$green.invoked" ]
	[ ! -e "$ARTIFACT_ROOT/facade" ]
}

@test "facade_sh_blueだけがforegroundの場合_runner IFの引数でblueのrunnerを起動しexitcode_txtの値で終了すること" {
	# Arrange
	require_facade
	local blue
	blue="$(write_recording_runner blue-runner.sh)"
	write_feature_flag "BLUE_MODE=foreground" "GREEN_MODE=off" "RAPID_CROSSCHECK_MODE=off" "BLUE_IMPL=v1" "BLUE_RUNNER=$blue"

	# Act
	run_facade JOB001 20260830 full

	# Assert(runner IF: <runner> --run-id <run_id> --job-id <JOB_ID> --role blue|green --mode foreground|background -- [PARAM...])
	[ "$status" -eq 0 ]
	[ "$(wc -l <"$blue.invoked")" -eq 1 ]
	local invoked
	invoked="$(cat "$blue.invoked")"
	[[ "$invoked" =~ ^--run-id\ ([0-9]{8}T[0-9]{6}-JOB001-[0-9a-f]{8})\ --job-id\ JOB001\ --role\ blue\ --mode\ foreground\ --\ 20260830\ full$ ]]
	[ -d "$ARTIFACT_ROOT/facade/${BASH_REMATCH[1]}/blue" ]
	[ ! -e "$ARTIFACT_ROOT/facade/${BASH_REMATCH[1]}/green" ]
}
