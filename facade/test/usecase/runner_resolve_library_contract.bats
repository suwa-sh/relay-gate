#!/usr/bin/env bats
# UC 7c41c7cd(ジョブマップで JOB_ID から実行先を解決する)× tier-facade: 共通ライブラリ lib/runner-resolve.sh を
# 自作の runner へ約束する入口(CLI 契約 runner IF の standard_runner.runner_resolve_library。spec-decision-042)の単体テスト。
# 2026-11-24 S2 scoped 再実行で追加。runner_resolve.bats が確かめていない約束だけを置く:
#   - sourcing: source しても set のオプションと trap を変えず、何も出力しない
#   - exit_code_variable: RUNNER_RESOLVE_STATUS_NOT_RESOLVED は source すると値 1 で定義される
#   - resolve_execution_target の on_failure: 二重起動で既存の exitcode.txt が 0 のときの戻り値は RUNNER_RESOLVE_STATUS_NOT_RESOLVED、
#     RUNNER_RESOLVE_EXIT_CODE は 0、成果物を書き換えない
#   - runner_resolve_reject_invocation の returns: run_id が分からず成果物を書かないときも RUNNER_RESOLVE_EXIT_CODE は 2
#   - build_argument_list の on_failure: 前の呼び出しの ARGUMENT_LIST が残っていても、不正な JSON 配列なら空の配列にする
# 自作の runner と同じく、ライブラリを source して関数を直接呼ぶ。I/O 境界は BATS_TEST_TMPDIR の実ファイル。

bats_require_minimum_version 1.5.0

LIB="$BATS_TEST_DIRNAME/../../lib/runner-resolve.sh"
SCRIPT_NAME="my-runner.sh"
HEADER_7="job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes"
ROW_JOB001_7="JOB001,host-green-01,batch,/var/app/work,/opt/app/bin/job001.sh,[],60"

setup() {
	export RELAY_GATE_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	export RELAY_GATE_ARTIFACT_ROOT="$BATS_TEST_TMPDIR/artifacts"
	export RELAY_GATE_LOG_DIR="$BATS_TEST_TMPDIR/logs"
	unset BLUE_JOB_MAP_CSV GREEN_JOB_MAP_CSV RELAY_GATE_NOW
	mkdir -p "$RELAY_GATE_CONFIG_DIR"
}

# ---- sourcing ----

@test "lib_runner-resolve_shをsourceする場合_setのオプションとEXITのtrapを変えず何も出力しないこと" {
	# Arrange(自作の runner と同じく、trap と set を設定してから source する別プロセス)
	# shellcheck disable=SC2016
	local caller='
		set -u
		set -o pipefail
		trap "echo caller-exit" EXIT
		before_opts="$(set +o)"
		before_shopt="$-"
		before_trap="$(trap -p EXIT)"
		source "$1" >"$2" 2>"$3"
		[ "$(set +o)" = "$before_opts" ] || { echo "set options changed" >&2; exit 11; }
		[ "$-" = "$before_shopt" ] || { echo "shell flags changed: $before_shopt -> $-" >&2; exit 12; }
		[ "$(trap -p EXIT)" = "$before_trap" ] || { echo "EXIT trap changed" >&2; exit 13; }
		trap - EXIT
	'
	local out="$BATS_TEST_TMPDIR/source.out" err="$BATS_TEST_TMPDIR/source.err"

	# Act
	run --separate-stderr bash -c "$caller" _ "$LIB" "$out" "$err"

	# Assert
	[ "$status" -eq 0 ] || {
		echo "stderr: $stderr"
		return 1
	}
	[ ! -s "$out" ]
	[ ! -s "$err" ]
}

@test "lib_runner-resolve_shをsourceした場合_RUNNER_RESOLVE_STATUS_NOT_RESOLVEDが1で定義されること" {
	# Act
	run --separate-stderr bash -c 'source "$1"; printf "%s\n" "${RUNNER_RESOLVE_STATUS_NOT_RESOLVED-unset}"' _ "$LIB"

	# Assert
	[ "$status" -eq 0 ]
	[ "$output" = "1" ]
}

# ---- resolve_execution_target: 二重起動 ----

@test "resolve_execution_target_既存のexitcode_txtが0の二重起動で解決できない場合_RUNNER_RESOLVE_STATUS_NOT_RESOLVEDを返しRUNNER_RESOLVE_EXIT_CODEが0で成果物を変えないこと" {
	# Arrange
	# shellcheck source=/dev/null
	source "$LIB"
	local run_id="20260830T113000-JOB999-a1b2c3d4"
	local role_dir="$RELAY_GATE_ARTIFACT_ROOT/facade/$run_id/green"
	printf '%s\n' "$HEADER_7" "$ROW_JOB001_7" >"$RELAY_GATE_CONFIG_DIR/green-job-map.csv"
	mkdir -p "$role_dir"
	printf '0\n' >"$role_dir/exitcode.txt"
	local before
	before="$(ls -A "$role_dir")"

	# Act
	local resolve_status=0
	resolve_execution_target "$SCRIPT_NAME" "$run_id" JOB999 green || resolve_status=$?

	# Assert
	[ "$resolve_status" -eq "$RUNNER_RESOLVE_STATUS_NOT_RESOLVED" ]
	[ "$resolve_status" -eq 1 ]
	[ "$RUNNER_RESOLVE_EXIT_CODE" = "0" ]
	[ "$(cat "$role_dir/exitcode.txt")" = "0" ]
	[ "$(ls -A "$role_dir")" = "$before" ]
}

# ---- runner_resolve_reject_invocation ----

@test "runner_resolve_reject_invocation_run_idが分からない場合_成果物を書かずRUNNER_RESOLVE_EXIT_CODEが2であること" {
	# Arrange
	# shellcheck source=/dev/null
	source "$LIB"
	RUNNER_RESOLVE_EXIT_CODE=""

	# Act
	local reject_status=0
	runner_resolve_reject_invocation "$SCRIPT_NAME" "" green "option required option=--run-id" || reject_status=$?

	# Assert
	[ "$reject_status" -ne 0 ]
	[ "$RUNNER_RESOLVE_EXIT_CODE" = "2" ]
	grep -qE "^my-runner\.sh - [0-9T:-]+ ERROR option required option=--run-id\$" "$RELAY_GATE_LOG_DIR/$SCRIPT_NAME.log"
	[ -z "$(find "$RELAY_GATE_ARTIFACT_ROOT" -type f 2>/dev/null)" ]
}

# ---- build_argument_list ----

@test "build_argument_list_前の呼び出しの結果が残っていて固定引数がJSON配列でない場合_1を返してARGUMENT_LISTが空であること" {
	# Arrange
	# shellcheck source=/dev/null
	source "$LIB"
	build_argument_list '["p1"]' x

	# Act
	local build_status=0
	build_argument_list '["p1",' y || build_status=$?

	# Assert
	[ "$build_status" -eq 1 ]
	[ "${#ARGUMENT_LIST[@]}" -eq 0 ]
}

# ---- 入力の複製の最終名(config_input_rules.snapshot.work_name。issues/20261124_001000_snapshot-final-name-directory-swap.md) ----

@test "resolve_execution_target_入力の複製の最終名に先にディレクトリがある場合_config snapshot failedをstderr_logに書いて6であること" {
	# Arrange(X を置き換えない mktemp(BSD 系の動き)で作業名と最終名を予測できる状態を、関数の差し替えで作る)
	# shellcheck source=/dev/null
	source "$LIB"
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir -p "$TMPDIR"
	mktemp() {
		(
			set -C
			: >"$1"
		) 2>/dev/null || return 1
		chmod 600 "$1"
		printf '%s\n' "$1"
	}
	local run_id="20260830T113000-JOB001-3f9a1c2e"
	local role_dir="$RELAY_GATE_ARTIFACT_ROOT/facade/$run_id/green"
	local map="$RELAY_GATE_CONFIG_DIR/green-job-map.csv"
	printf '%s\n' "$HEADER_7" "$ROW_JOB001_7" >"$map"
	local final="$TMPDIR/relay-gate-$BASHPID-XXXXXX"
	mkdir "$final"

	# Act
	local resolve_status=0
	resolve_execution_target "$SCRIPT_NAME" "$run_id" JOB001 green || resolve_status=$?

	# Assert(影響は複製の失敗まで。runner は exitcode.txt=6)
	[ "$resolve_status" -eq 6 ]
	[ "$RUNNER_RESOLVE_EXIT_CODE" = "6" ]
	[ "$(sed -n 1p "$role_dir/stderr.log")" = "error: config snapshot failed path: $map" ] || {
		echo "stderr.log: $(cat "$role_dir/stderr.log")"
		return 1
	}
	[ "$(cat "$role_dir/exitcode.txt")" = "6" ]
	[ -z "$(ls -A "$final")" ]
}
