#!/usr/bin/env bats
# UC 65b09d93 × tier-facade: 標準の slot runner(runners/standard-runner.sh)の入口と共通ライブラリ lib/runner-*.sh の配置の単体テスト。
# 配置ディレクトリ(RELAY_GATE_HOME)は tier dir(facade/)。契約 standard_runner.home: runners/ の 1 つ上。
# この UC の範囲は入口(--help で runner-if-version=1)と 4 ファイルの配置まで。
# 解決・実行・結果の出力・通知の中身は後続の 4 機能の担当で、ここでは判定しない。
# 時間を確かめるテストは書かない。リポジトリの中にファイルを書かない(書くのは BATS_TEST_TMPDIR だけ)。

bats_require_minimum_version 1.5.0

setup() {
	HOME_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	RUNNER="$HOME_DIR/runners/standard-runner.sh"
	LIB_DIR="$HOME_DIR/lib"
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
	# Arrange(--help は `--` より前のどこにあってもよい。前提 A-003)
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

	# Act(--help 以外の起動。runner IF の処理は後続 UC が実装するまで仮置きの終了コードで終える。前提 A-004)
	run --separate-stderr bash -c 'cd "$1" && "$2" --run-id r1 --job-id JOB001 --role green --mode foreground -- --help' _ "$work" "$RUNNER"

	# Assert(runner は stdout / stderr に出さない。Runner Result の不変条件 (3))
	[ "$status" -ne 0 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ -z "$(ls -A "$work")" ]
}

@test "standard-runner_sh_runner IFの引数が不正な場合_何も出力せず終了コード2であること" {
	# Arrange(契約 exit_codes の 2: runner IF 引数不正。exitcode.txt の公開は後続 UC。前提 A-004)
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
