#!/usr/bin/env bats
# UC 7c41c7cd × tier-facade: 入力の複製の最終名に、先にディレクトリやディレクトリへのリンクが置かれている場合の単体テスト。
# 2026-11-24 S2 scoped 再実行で追加(docs/impl/latest/7c41c7cd/issues/20261124_001000_snapshot-final-name-directory-swap.md の再現テスト)。
# 仕様: CLI 契約 config_input_rules.snapshot.work_name(spec-decision-041)。predictability「X を置き換えない mktemp では作業名を
#       予測できる。…影響は複製の失敗まで(終了コード 6)で、複製の内容を読まれたり、すり替えられたりはしない」、rename
#       「書き終えたら .part を外した最終名へ同一ディレクトリ内で rename する」。
# 最終名を予測できる状況は、X を置き換えない mktemp(BSD 系)を関数で差し替えて作る(X を乱数にする GNU mktemp の環境でも
# 同じ条件で確かめるため)。2026-11-24 の S4 再実行で、最終名に先に何か(ディレクトリ・リンク・通常のファイル)があれば複製の失敗にするよう
# 実装を直し、通常のファイルの場合のテストを足した。

bats_require_minimum_version 1.5.0

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/repository/job_map_repo.sh"
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir -p "$TMPDIR"
	MAP="$BATS_TEST_TMPDIR/map.csv"
	printf '%s\n' 'job_id,work_dir' 'JOB001,/w' >"$MAP"
	PLANTED="$BATS_TEST_TMPDIR/planted"
	mkdir -p "$PLANTED"
}

# X を置き換えない mktemp(BSD 系の動き): テンプレートのままの名前で作り、既にあれば作らずに失敗する。権限は 0600
mktemp() {
	local name="$1"
	(
		set -C
		: >"$name"
	) 2>/dev/null || return 1
	chmod 600 "$name"
	printf '%s\n' "$name"
}

@test "job_map_repo_create_snapshot_最終名に先にディレクトリがある場合_複製の失敗にしてディレクトリの中へ複製を移さないこと" {
	# Arrange
	# job_map_repo_create_snapshot が使う最終名(このシェルのプロセス番号で決まる。コマンド置換の中では取らない)
	local final="$TMPDIR/relay-gate-$BASHPID-XXXXXX"
	mkdir "$final"

	# Act
	local status=0
	job_map_repo_create_snapshot "$MAP" || status=$?

	# Assert
	[ "$status" -ne 0 ]
	[ -z "$(ls -A "$final")" ]
	[ ! -e "$final.part" ]
}

@test "job_map_repo_create_snapshot_最終名に先にディレクトリへのリンクがある場合_複製の失敗にしてリンク先へ複製を移さないこと" {
	# Arrange
	# job_map_repo_create_snapshot が使う最終名(このシェルのプロセス番号で決まる。コマンド置換の中では取らない)
	local final="$TMPDIR/relay-gate-$BASHPID-XXXXXX"
	ln -s "$PLANTED" "$final"

	# Act
	local status=0
	job_map_repo_create_snapshot "$MAP" || status=$?

	# Assert
	[ "$status" -ne 0 ]
	[ -z "$(ls -A "$PLANTED")" ]
	[ ! -e "$final.part" ]
}

@test "job_map_repo_load_最終名に先にディレクトリがある場合_複製失敗の状態を返し置かれた中身を読まないこと" {
	# Arrange(置いた側が、読み手が開く前に最終名の中身を自分のファイルへ差し替えられる状態。読み手は最終名を開かずに失敗する)
	# job_map_repo_create_snapshot が使う最終名(このシェルのプロセス番号で決まる。コマンド置換の中では取らない)
	local final="$TMPDIR/relay-gate-$BASHPID-XXXXXX"
	mkdir "$final"

	# Act
	local status=0
	job_map_repo_load "$MAP" || status=$?

	# Assert(config_input_rules.internal_failure の「入力の複製の失敗」= 呼び出し元は config snapshot failed / 終了コード 6)
	[ "$status" -eq "$JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED" ]
	[ -z "$(ls -A "$final")" ]
}

@test "job_map_repo_load_最終名に先に通常のファイルがある場合_複製失敗の状態を返し置かれたファイルを読まず残すこと" {
	# Arrange(置いた側の通常のファイル。読み手がこの中身を読むと、すり替えが成り立つ)
	local final="$TMPDIR/relay-gate-$BASHPID-XXXXXX"
	printf '%s\n' 'job_id,work_dir' 'PLANTED,/planted' >"$final"

	# Act
	local status=0
	job_map_repo_load "$MAP" || status=$?

	# Assert(複製の失敗。置かれたファイルは消さず書き換えず、作業名も残さない)
	[ "$status" -eq "$JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED" ]
	[ "$(sed -n 2p "$final")" = "PLANTED,/planted" ]
	[ ! -e "$final.part" ]
	[ "${#JOB_MAP_CELLS[@]}" -eq 0 ]
}
