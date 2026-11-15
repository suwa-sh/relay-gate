#!/usr/bin/env bats
# UC fd678b04 × tier-facade: validate-config.sh --feature-flag の runner / worker の実体パスの解決の単体テスト。
# エントリポイント経由で実プロセスとして起動する(内部の関数の分け方を固定しない)。I/O 境界は実ファイル(一時ディレクトリ)。
# 仕様: CLI 契約 config_files.feature-flag.env.runner_path_resolution(relative_criteria / base_dir / resolved_path / usage / display)、
#       error_messages「実体が無い・実行不可」、error_order.per_key、tier-facade.md「runner / worker の実体パスの解決」
# 2026-11-15 S2 再実行で追加(spec event 20261115_164000_feedback_runner_relative_path。2026-11-15 利用者決定:
#   BLUE_RUNNER / GREEN_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER は相対パスを受け付け、
#   基準はその設定ファイルのあるディレクトリ。4 キーでは `error: path is not absolute` を出さない)。
#   tier BDD(facade/features/configure-feature-flags.feature)が判定しない細部
#   (4 キーの書き方の混在 / 設定ファイルのパスの字面を畳まない / 作業ディレクトリの論理パス / warn 行の runner= / 制御文字の可視表記)を補う。
#   追加時点の実装は 4 キーの相対パスを拒否するため、off の slot のテスト 1 件を除いて fail する(実装は S4 で追従する)。
# 性能(契約 config_input_rules.performance_target)は目標値で合否の検査ではないため、ここに時間の検査は置かない。
bats_require_minimum_version 1.5.0

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../bin/validate-config.sh"
	CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	CONF="$BATS_TEST_TMPDIR/site/conf"
	WORK="$BATS_TEST_TMPDIR/elsewhere/work"
	mkdir -p "$CONFIG_DIR" "$CONF" "$WORK"
	export RELAY_GATE_CONFIG_DIR="$CONFIG_DIR"
	ENV_FILE="$CONF/ff.env"
}

# 起動されるたびに受け取った引数を <スタブ>.invoked へ記録し、--help で runner-if-version=1 を返す runner スタブ
write_recording_runner() {
	mkdir -p "${1%/*}"
	printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >>"$0.invoked"' 'if [ "${1:-}" = "--help" ]; then echo "runner-if-version=1"; exit 0; fi' 'exit 6' >"$1"
	chmod +x "$1"
}

# 単独本番(green だけ)の設定を書く。引数: GREEN_RUNNER の値
write_green_only_env() {
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=%s\n' "$1" >"$ENV_FILE"
	touch "$CONFIG_DIR/green-job-map.csv"
}

# ---- 解決後のパス(resolved_path / usage / display) ----

@test "validate-config_sh_--feature-flagで4キーの相対パスの書き方が混在し実体がある場合_設定ファイルのあるディレクトリ基準の解決後のパスをstdoutに出して終了コード0であること" {
	# Arrange(./ 付き・./ 無し・サブディレクトリ・.. で親をたどる の 4 通り。作業ディレクトリは設定ファイルとは別)
	write_recording_runner "$CONF/blue-runner.sh"
	write_recording_runner "$CONF/runners/green-runner.sh"
	write_recording_runner "$BATS_TEST_TMPDIR/site/bin/rapid-runner.sh"
	write_recording_runner "$CONF/rapid-worker.sh"
	touch "$CONFIG_DIR/blue-job-map.csv" "$CONFIG_DIR/green-job-map.csv"
	printf 'BLUE_MODE=foreground\nGREEN_MODE=background\nRAPID_CROSSCHECK_MODE=background\nBLUE_IMPL=blue-2.3.1\nGREEN_IMPL=green-1.4.0\nBLUE_RUNNER=./blue-runner.sh\nGREEN_RUNNER=runners/green-runner.sh\nRAPID_CROSSCHECK_RUNNER=../bin/rapid-runner.sh\nRAPID_CROSSCHECK_WORKER=rapid-worker.sh\n' >"$ENV_FILE"
	cd "$WORK"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(基準のディレクトリ + / + 値。. と .. を畳まない。問い合わせは解決後のパスを起動する)
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 0 ]
	[ "${#lines[@]}" -eq 15 ]
	[ "${lines[5]}" = "blue_runner: $CONF/./blue-runner.sh" ]
	[ "${lines[6]}" = "green_runner: $CONF/runners/green-runner.sh" ]
	[ "${lines[8]}" = "rapid_crosscheck_runner: $CONF/../bin/rapid-runner.sh" ]
	[ "${lines[9]}" = "rapid_crosscheck_worker: $CONF/rapid-worker.sh" ]
	[ "${lines[13]}" = "blue_runner_if_version=1" ]
	[ "${lines[14]}" = "green_runner_if_version=1" ]
	[ "$(cat "$CONF/blue-runner.sh.invoked")" = "--help" ]
	[ "$(cat "$CONF/runners/green-runner.sh.invoked")" = "--help" ]
	# 速報 runner / worker は検証だけで起動しない
	[ ! -e "$BATS_TEST_TMPDIR/site/bin/rapid-runner.sh.invoked" ]
	[ ! -e "$CONF/rapid-worker.sh.invoked" ]
}

@test "validate-config_sh_--feature-flagで4キーとも相対パスで実体が無い場合_キーごとに解決後のパスのfile not executableを1行ずつ出しpath is not absoluteを出さないこと" {
	# Arrange(作業ディレクトリ側には同じ相対位置に実行可能な実体を置く。作業ディレクトリを基準にしたら検証を通ってしまう)
	write_recording_runner "$WORK/blue-runner.sh"
	write_recording_runner "$WORK/green-runner.sh"
	write_recording_runner "$WORK/rapid-runner.sh"
	write_recording_runner "$WORK/rapid-worker.sh"
	touch "$CONFIG_DIR/blue-job-map.csv" "$CONFIG_DIR/green-job-map.csv"
	printf 'BLUE_MODE=foreground\nGREEN_MODE=background\nRAPID_CROSSCHECK_MODE=background\nBLUE_IMPL=blue-2.3.1\nGREEN_IMPL=green-1.4.0\nBLUE_RUNNER=./blue-runner.sh\nGREEN_RUNNER=green-runner.sh\nRAPID_CROSSCHECK_RUNNER=./rapid-runner.sh\nRAPID_CROSSCHECK_WORKER=rapid-worker.sh\n' >"$ENV_FILE"
	cd "$WORK"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(error_order の順: BLUE_RUNNER → GREEN_RUNNER → RAPID_CROSSCHECK_RUNNER → RAPID_CROSSCHECK_WORKER)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 4 ]
	[ "${stderr_lines[0]}" = "error: file not executable key=BLUE_RUNNER path=$CONF/./blue-runner.sh" ]
	[ "${stderr_lines[1]}" = "error: file not executable key=GREEN_RUNNER path=$CONF/green-runner.sh" ]
	[ "${stderr_lines[2]}" = "error: file not executable key=RAPID_CROSSCHECK_RUNNER path=$CONF/./rapid-runner.sh" ]
	[ "${stderr_lines[3]}" = "error: file not executable key=RAPID_CROSSCHECK_WORKER path=$CONF/rapid-worker.sh" ]
	[[ "$stderr" != *"path is not absolute"* ]]
	# 作業ディレクトリ側の実体は起動されていない
	[ ! -e "$WORK/blue-runner.sh.invoked" ]
	[ ! -e "$WORK/green-runner.sh.invoked" ]
}

@test "validate-config_sh_--feature-flagで相対パスの実体に実行権限が無い場合_解決後のパスのfile not executableで終了コード2であること" {
	# Arrange(実体はあるが実行権限が無い)
	write_recording_runner "$CONF/green-runner.sh"
	chmod -x "$CONF/green-runner.sh"
	write_green_only_env ./green-runner.sh

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(検証を通らない runner へは問い合わせない)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: file not executable key=GREEN_RUNNER path=$CONF/./green-runner.sh" ]
	[ ! -e "$CONF/green-runner.sh.invoked" ]
}

# ---- 基準のディレクトリ(base_dir) ----

@test "validate-config_sh_--feature-flagで設定ファイルのパスに.と連続するスラッシュがある場合_字面を畳まずに基準のディレクトリにすること" {
	# Arrange(基準は渡されたパスの最後の / より前の部分。. と連続する / を畳まない)
	write_recording_runner "$CONF/green-runner.sh"
	write_green_only_env ./green-runner.sh

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$BATS_TEST_TMPDIR/./site/conf//ff.env"

	# Assert(設定ファイルのパス …/./site/conf//ff.env → 基準 …/./site/conf/ → 解決後 …/./site/conf//./green-runner.sh)
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 0 ]
	[ "${lines[6]}" = "green_runner: $BATS_TEST_TMPDIR/./site/conf//./green-runner.sh" ]
	[ "${lines[14]}" = "green_runner_if_version=1" ]
}

@test "validate-config_sh_--feature-flagで設定ファイルのパスが.で始まる相対パスの場合_作業ディレクトリと連結した字面のまま基準のディレクトリにすること" {
	# Arrange(作業ディレクトリ <tmp>/site から ./conf/ff.env を渡す。作業ディレクトリ直下には別の実体を置く)
	write_recording_runner "$CONF/green-runner.sh"
	write_recording_runner "$BATS_TEST_TMPDIR/site/green-runner.sh"
	write_green_only_env green-runner.sh
	cd "$BATS_TEST_TMPDIR/site"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag ./conf/ff.env

	# Assert(作業ディレクトリ + / + パス → 基準 <tmp>/site/./conf。作業ディレクトリ直下の実体は使わない)
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 0 ]
	[ "${lines[0]}" = "config_path: ./conf/ff.env" ]
	[ "${lines[6]}" = "green_runner: $BATS_TEST_TMPDIR/site/./conf/green-runner.sh" ]
	[ "$(cat "$CONF/green-runner.sh.invoked")" = "--help" ]
	[ ! -e "$BATS_TEST_TMPDIR/site/green-runner.sh.invoked" ]
}

@test "validate-config_sh_--feature-flagで作業ディレクトリがシンボリックリンク経由の場合_物理パスではなく論理パスを基準のディレクトリにすること" {
	# Arrange(<tmp>/linked は <tmp>/site/conf へのシンボリックリンク。リンク経由の作業ディレクトリから相対パスで設定ファイルを渡す)
	write_recording_runner "$CONF/green-runner.sh"
	write_green_only_env ./green-runner.sh
	ln -s "$CONF" "$BATS_TEST_TMPDIR/linked"
	cd "$BATS_TEST_TMPDIR/linked"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag ff.env

	# Assert(基準はシェルの $PWD の論理パス <tmp>/linked。リンクを辿った <tmp>/site/conf にしない)
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 0 ]
	[ "${lines[6]}" = "green_runner: $BATS_TEST_TMPDIR/linked/./green-runner.sh" ]
}

# ---- 表示(display) ----

@test "validate-config_sh_--feature-flagで相対パスのrunnerが--helpに応答しない場合_warn行のrunner=に解決後のパスを出して終了コード0であること" {
	# Arrange(実行可能だが --help に版の行を返さない runner)
	printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$CONF/silent-runner.sh"
	chmod +x "$CONF/silent-runner.sh"
	write_green_only_env ./silent-runner.sh
	cd "$WORK"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "warn: runner does not respond to --help slot=green runner=$CONF/./silent-runner.sh" ]
	[ "${lines[6]}" = "green_runner: $CONF/./silent-runner.sh" ]
	[ "${lines[14]}" = "green_runner_if_version=-" ]
}

@test "validate-config_sh_--feature-flagで相対パスの値にタブがあり実体が無い場合_解決後のパスを可視表記で出すこと" {
	# Arrange(値の途中のタブは値の一部。出力規約「制御文字の表記」でタブは \t)
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=green\trunner.sh\n' >"$ENV_FILE"
	touch "$CONFIG_DIR/green-job-map.csv"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(生のタブを出さない)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: file not executable key=GREEN_RUNNER path=$CONF/green\\trunner.sh" ]
}

# ---- 検査しないキー ----

@test "validate-config_sh_--feature-flagでoffのslotと速報offの相対パスに実体が無い場合_解決も検査もせず-を出して終了コード0であること" {
	# Arrange(BLUE_MODE=off と RAPID_CROSSCHECK_MODE=off。3 キーの相対パスの実体は無い)
	write_recording_runner "$CONF/green-runner.sh"
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nBLUE_RUNNER=./missing-blue.sh\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=%s\nRAPID_CROSSCHECK_RUNNER=./missing-rapid.sh\nRAPID_CROSSCHECK_WORKER=missing-worker.sh\n' "$CONF/green-runner.sh" >"$ENV_FILE"
	touch "$CONFIG_DIR/green-job-map.csv"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(検査しないキーは従来どおり -。絶対パスの値はそのまま)
	[ "$status" -eq 0 ]
	[ "${#stderr_lines[@]}" -eq 0 ]
	[ "${lines[5]}" = "blue_runner: -" ]
	[ "${lines[6]}" = "green_runner: $CONF/green-runner.sh" ]
	[ "${lines[8]}" = "rapid_crosscheck_runner: -" ]
	[ "${lines[9]}" = "rapid_crosscheck_worker: -" ]
}
