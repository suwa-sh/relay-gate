#!/usr/bin/env bats
# UC 65b09d93 × tier-facade: 標準の slot runner(runners/standard-runner.sh)の入口と共通ライブラリ lib/runner-*.sh の配置の単体テスト。
# 配置ディレクトリ(RELAY_GATE_HOME)は tier dir(facade/)。契約 standard_runner.home: runners/ の 1 つ上。
# この UC の範囲は入口(--help で runner-if-version=1)と 4 ファイルの配置まで。
# UC 7c41c7cd(ジョブマップで JOB_ID から実行先を解決する)で、runner IF の引数の違反の報告(実行ログと Runner Result)を足した。
# 解決フェーズそのものは standard_runner_resolve.bats、実行・結果の出力・通知の中身は後続の機能の担当で、ここでは判定しない。
# 時間を確かめるテストは書かない。リポジトリの中にファイルを書かない(書くのは BATS_TEST_TMPDIR だけ)。
# 標準の slot runner は、置き場を環境変数で受け取らないと配置ディレクトリ(facade/)の config / var / log を使うため、
# --help 以外の起動には一時ディレクトリの置き場を環境変数で渡す(teardown でリポジトリに書いていないことも確かめる)。

bats_require_minimum_version 1.5.0

setup() {
	HOME_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	RUNNER="$HOME_DIR/runners/standard-runner.sh"
	LIB_DIR="$HOME_DIR/lib"
	export RELAY_GATE_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	export RELAY_GATE_ARTIFACT_ROOT="$BATS_TEST_TMPDIR/artifacts"
	export RELAY_GATE_LOG_DIR="$BATS_TEST_TMPDIR/logs"
	RUNNER_LOG="$RELAY_GATE_LOG_DIR/standard-runner.sh.log"
	mkdir -p "$RELAY_GATE_CONFIG_DIR"
}

teardown() {
	[ ! -e "$HOME_DIR/var" ]
	[ ! -e "$HOME_DIR/log" ]
}

@test "standard-runner_sh_--helpの場合_usage行とrunner-if-version=1をstdoutに出して終了コード0であること" {
	# Arrange
	[ -f "$RUNNER" ] || {
		echo "not implemented: $RUNNER does not exist"
		return 1
	}
	[ -x "$RUNNER" ]

	# Act(環境変数を引き継がない起動。--help は設定も環境変数も要らない)
	run --separate-stderr env -i PATH="$PATH" "$RUNNER" --help

	# Assert
	# tier BDD: "usage: " で始まる行と runner-if-version=1 が出る。版の行は契約 runner_help_probe.version_line_selection
	# (runner-if-version= で始まる最初の 1 行の = より右、前後の空白を除いた値)で読む
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	printf '%s\n' "${lines[@]}" | grep -q '^usage: '
	local version
	version="$(printf '%s\n' "${lines[@]}" | grep -m1 '^runner-if-version=' | sed -e 's/^runner-if-version=//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
	[ "$version" = "1" ]
}

@test "standard-runner_sh_ほかのオプションの後に--helpを付けた場合_使い方を出して終了コード0であること" {
	# Arrange(--help は `--` より前のどこにあってもよい)
	[ -x "$RUNNER" ]

	# Act
	run --separate-stderr "$RUNNER" --role blue --help

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	printf '%s\n' "${lines[@]}" | grep -qx 'runner-if-version=1'
}

@test "standard-runner_sh_--helpが--より後のPARAMにある場合_使い方を出さず何も出力しないこと" {
	# Arrange(作業ディレクトリを空の一時ディレクトリにし、何も書かないことも確かめる)
	local work="$BATS_TEST_TMPDIR/work"
	mkdir -p "$work"

	# Act(--help 以外の起動。`--` より後の --help は PARAM で、解決フェーズへ進む。ここではジョブマップを置いていない)
	run --separate-stderr bash -c 'cd "$1" && "$2" --run-id r1 --job-id JOB001 --role green --mode foreground -- --help' _ "$work" "$RUNNER"

	# Assert(runner は stdout / stderr に出さない。Runner Result の不変条件 (3)。作業ディレクトリにも書かない)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ -z "$(ls -A "$work")" ]
	grep -qF "ERROR job map not found slot=green map=$RELAY_GATE_CONFIG_DIR/green-job-map.csv" "$RUNNER_LOG"
}

@test "standard-runner_sh_runner IFの引数が不正な場合_何も出力せず終了コード2であること" {
	# Arrange(契約 exit_codes の 2: runner IF 引数不正)
	local work="$BATS_TEST_TMPDIR/work"
	mkdir -p "$work"
	local -a cases=(
		""
		"--job-id JOB001 --role green --mode foreground"
		"--run-id r1 --role green --mode foreground"
		"--run-id r1 --job-id JOB001 --mode foreground"
		"--run-id r1 --job-id JOB001 --role green"
		"--run-id r1 --job-id JOB001 --role red --mode foreground"
		"--run-id r1 --job-id JOB001 --role green --mode later"
		"--run-id r1 --job-id JOB001 --role green --mode foreground --unknown x"
		"--run-id r1 --job-id JOB001 --role green --mode"
		"--run-id r1 --job-id JOB001 --role green --mode foreground --execution-spec spec.json -- x"
	)
	local args

	for args in "${cases[@]}"; do
		# 前の組が揃えた成果物を残さない(同じ run_id と role の exitcode.txt があると二重起動の扱いになる)
		rm -rf "$RELAY_GATE_ARTIFACT_ROOT"

		# Act(引数は空白で分ける。どの値も空白を含まない)
		# shellcheck disable=SC2086
		run --separate-stderr bash -c 'cd "$1" && shift && "$@"' _ "$work" "$RUNNER" $args

		# Assert
		[ "$status" -eq 2 ] || {
			echo "args=[$args] status=$status"
			return 1
		}
		[ -z "$output" ]
		[ -z "$stderr" ]
	done
	[ -z "$(ls -A "$work")" ]
}

@test "standard-runner_sh_値を取るオプションに空の値を渡した場合_何も出力せず終了コード2であること" {
	# Arrange(契約 exit_codes の 2: 引数不足 / spec なし。値を取る 5 オプションのそれぞれに空文字の引数を 1 つ渡す。
	# ほかの引数は正しい。空の値の --execution-spec は「spec なし」で 2 であり、仮置きの 6 にしない)
	local work="$BATS_TEST_TMPDIR/work"
	mkdir -p "$work"
	local option
	local -a args

	for option in --run-id --job-id --role --mode --execution-spec; do
		rm -rf "$RELAY_GATE_ARTIFACT_ROOT"
		args=(--run-id r1 --job-id JOB001 --role green --mode foreground)
		case "$option" in
		--run-id) args[1]="" ;;
		--job-id) args[3]="" ;;
		--role) args[5]="" ;;
		--mode) args[7]="" ;;
		--execution-spec) args+=(--execution-spec "") ;;
		esac

		# Act(`--` の有無の両方で確かめる)
		run --separate-stderr bash -c 'cd "$1" && shift && "$@"' _ "$work" "$RUNNER" "${args[@]}"
		local status_without_separator="$status" output_without_separator="$output" stderr_without_separator="$stderr"
		run --separate-stderr bash -c 'cd "$1" && shift && "$@"' _ "$work" "$RUNNER" "${args[@]}" --

		# Assert
		[ "$status_without_separator" -eq 2 ] && [ "$status" -eq 2 ] || {
			echo "option=$option status=$status_without_separator/$status"
			return 1
		}
		[ -z "$output_without_separator" ] && [ -z "$stderr_without_separator" ]
		[ -z "$output" ] && [ -z "$stderr" ]
	done
	[ -z "$(ls -A "$work")" ]
}

@test "standard-runner_sh_シンボリックリンクを含むパスで起動した場合_起動されたパスの字面から配置ディレクトリを決めること" {
	# Arrange(一時ディレクトリの home/runners を facade/runners へのリンクにし、home/src は置かない。
	# 字面の 1 つ上(home)を配置ディレクトリにすれば本体が見つからず、リンク先をたどれば facade/src が見つかる)
	local home="$BATS_TEST_TMPDIR/home"
	mkdir -p "$home"
	ln -s "$HOME_DIR/runners" "$home/runners"

	# Act
	run --separate-stderr "$home/runners/standard-runner.sh" --help

	# Assert(standard_runner.home: シンボリックリンクは辿らない)
	[ "$status" -ne 0 ]
	[[ "$stderr" == *"$home/src/presentation/standard_runner.sh"* ]]
}

@test "配置ディレクトリのrunners_標準のslot runnerを配置した場合_standard-runner_shは実行可能な通常ファイルでssh-runner_shは無いこと" {
	# Arrange / Act
	[ -e "$RUNNER" ] || {
		echo "not implemented: $RUNNER does not exist"
		return 1
	}

	# Assert
	[ -f "$RUNNER" ]
	[ ! -L "$RUNNER" ]
	[ -x "$RUNNER" ]
	[ ! -e "$HOME_DIR/runners/ssh-runner.sh" ]
}

@test "共通ライブラリ_lib_runner-*_shをsourceした場合_4ファイルとも出力も終了もせずに読み込めること" {
	# Arrange
	local name
	for name in runner-resolve.sh runner-spec.sh runner-result.sh runner-notify.sh; do
		[ -f "$LIB_DIR/$name" ] || {
			echo "not implemented: $LIB_DIR/$name does not exist"
			return 1
		}
	done

	# Act(4 ファイルを順に source し、最後まで到達したら印を出す)
	run --separate-stderr bash -c 'set -u; for f in "$1"/runner-resolve.sh "$1"/runner-spec.sh "$1"/runner-result.sh "$1"/runner-notify.sh; do . "$f"; done; echo sourced-all' _ "$LIB_DIR"

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "sourced-all" ]
	[ -z "$stderr" ]
}

# ---- UC 7c41c7cd: runner IF の引数の違反の報告(tier-facade.md エラーメッセージ表「必須オプション欠落」)----

@test "standard-runner_sh_--job-idが無くrun_idとroleが分かる場合_実行ログにERRORを残し3ファイルとstarted-at_txtを揃えて終了コード2であること" {
	# Arrange
	local role_dir="$RELAY_GATE_ARTIFACT_ROOT/facade/r1/green"

	# Act
	run --separate-stderr "$RUNNER" --run-id r1 --role green --mode background

	# Assert(実行ログの行形式: {script} {run_id} {ローカル日時} {LEVEL} {message})
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	grep -qE '^standard-runner\.sh r1 [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ERROR option required option=--job-id$' "$RUNNER_LOG"
	[ "$(grep -c ' ERROR ' "$RUNNER_LOG")" = "1" ]
	[ -f "$role_dir/started-at.txt" ]
	[ -f "$role_dir/stdout.log" ]
	[ ! -s "$role_dir/stdout.log" ]
	[ "$(cat "$role_dir/stderr.log")" = "error: option required option=--job-id" ]
	[ "$(cat "$role_dir/exitcode.txt")" = "2" ]
}

@test "standard-runner_sh_--run-idが無い場合_実行ログのrun_id欄を-にしてERRORを残し成果物を書かないこと" {
	# Act
	run --separate-stderr "$RUNNER" --job-id JOB001 --role green --mode background

	# Assert(run_id が分からなければ成果物は書けないため、実行ログにだけ残す)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	grep -qE '^standard-runner\.sh - [0-9T:-]+ ERROR option required option=--run-id$' "$RUNNER_LOG"
	[ ! -e "$RELAY_GATE_ARTIFACT_ROOT" ]
}

@test "standard-runner_sh_--roleが列挙外の場合_実行ログにinvalid valueを残し成果物を書かないこと" {
	# Act
	run --separate-stderr "$RUNNER" --run-id r1 --job-id JOB001 --role red --mode background

	# Assert(role が分からなければ成果物ディレクトリが決まらない)
	[ "$status" -eq 2 ]
	grep -qF ' r1 ' "$RUNNER_LOG"
	grep -qE ' ERROR invalid value option=--role value=red$' "$RUNNER_LOG"
	[ ! -e "$RELAY_GATE_ARTIFACT_ROOT" ]
}

@test "standard-runner_sh_未知のオプションがある場合_実行ログにunknown optionを残して終了コード2であること" {
	# Act
	run --separate-stderr "$RUNNER" --run-id r1 --job-id JOB001 --role green --mode background --unknown x

	# Assert(契約 conventions.option_style の定型文)
	[ "$status" -eq 2 ]
	grep -qE ' ERROR unknown option option=--unknown$' "$RUNNER_LOG"
	[ "$(cat "$RELAY_GATE_ARTIFACT_ROOT/facade/r1/green/exitcode.txt")" = "2" ]
}

@test "standard-runner_sh_--execution-specを付けた正しい引数の場合_ジョブマップを読まず何も書かずに仮の終了コードであること" {
	# Arrange(復元起動は後続の機能の担当。ジョブマップを置いても読まない)
	printf '%s\n' "job_id,work_dir,script,fixed_params,hang_detect_limit_minutes" "JOB001,/w,/s.sh,[],0" >"$RELAY_GATE_CONFIG_DIR/green-job-map.csv"

	# Act
	run --separate-stderr "$RUNNER" --run-id r1 --job-id JOB001 --role green --mode background --execution-spec "$BATS_TEST_TMPDIR/spec.json"

	# Assert
	[ "$status" -eq 6 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ ! -e "$RUNNER_LOG" ]
	[ ! -e "$RELAY_GATE_ARTIFACT_ROOT" ]
}

@test "standard-runner_sh_置き場を環境変数で受け取らない場合_配置ディレクトリのconfigとvarとlogを既定にすること" {
	# Arrange(配置ディレクトリ全体を一時ディレクトリへ複製する。リポジトリの facade/ には書かない。契約 standard_runner.home)
	local home="$BATS_TEST_TMPDIR/home"
	mkdir -p "$home"
	cp -R "$HOME_DIR/runners" "$HOME_DIR/lib" "$HOME_DIR/src" "$home/"

	# Act(環境変数 RELAY_GATE_HOME が別の場所を指していても使わない)
	run --separate-stderr env -i PATH="$PATH" RELAY_GATE_HOME="$BATS_TEST_TMPDIR/elsewhere" \
		"$home/runners/standard-runner.sh" --run-id r1 --job-id JOB001 --role blue --mode foreground

	# Assert
	[ "$status" -eq 2 ]
	[ "$(cat "$home/var/facade/r1/blue/stderr.log")" = "error: job map not found slot=blue map=$home/config/blue-job-map.csv" ]
	[ -f "$home/log/standard-runner.sh.log" ]
	[ ! -e "$BATS_TEST_TMPDIR/elsewhere" ]
}
