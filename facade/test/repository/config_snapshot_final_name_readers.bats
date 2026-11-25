#!/usr/bin/env bats
# UC 7c41c7cd × tier-facade: 入力の複製を作るほかの読み手(feature flag の env / 速報クロスチェックの env)も、
# 複製の最終名に先にディレクトリが置かれていれば複製の失敗にし、置かれたディレクトリの中へ複製を移さないことの単体テスト。
# 2026-11-24 の S4 再実行で追加(docs/impl/latest/7c41c7cd/issues/20261124_001000_snapshot-final-name-directory-swap.md の
# 「同じ複製の定めを使うほかの読み手にも同じ形があれば同じく直す」)。どの読み手も複製は repository/job_map_repo.sh の
# job_map_repo_create_snapshot で作るため、読み手ごとに 1 件ずつ確かめる。
# 仕様: CLI 契約 config_input_rules.snapshot.work_name の predictability(影響は複製の失敗まで。すり替えられない)。
# 最終名を予測できる状況は、X を置き換えない mktemp(BSD 系)を関数で差し替えて作る(job_map_repo_snapshot_final_name.bats と同じ)。

bats_require_minimum_version 1.5.0

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/feature_flag.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/repository/feature_flag_config.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/repository/rapid_crosscheck_env.sh"
	export TMPDIR="$BATS_TEST_TMPDIR/tmp"
	mkdir -p "$TMPDIR"
	ENV_FILE="$BATS_TEST_TMPDIR/input.env"
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

@test "feature_flag_config_load_複製の最終名に先にディレクトリがある場合_複製失敗の状態を返しディレクトリの中へ複製を移さないこと" {
	# Arrange
	printf 'BLUE_MODE=foreground\nGREEN_MODE=background\n' >"$ENV_FILE"
	local final="$TMPDIR/relay-gate-$BASHPID-XXXXXX"
	mkdir "$final"

	# Act
	local status=0
	feature_flag_config_load "$ENV_FILE" || status=$?

	# Assert
	[ "$status" -eq "$FEATURE_FLAG_CONFIG_STATUS_SNAPSHOT_FAILED" ]
	[ -z "$(ls -A "$final")" ]
	[ ! -e "$final.part" ]
}

@test "rapid_crosscheck_env_read_複製の最終名に先にディレクトリがある場合_複製失敗の状態を返しディレクトリの中へ複製を移さないこと" {
	# Arrange
	printf 'RAPID_COMPARE_COMMAND=/opt/compare.sh\n' >"$ENV_FILE"
	local final="$TMPDIR/relay-gate-$BASHPID-XXXXXX"
	mkdir "$final"

	# Act
	local status=0
	rapid_crosscheck_env_read "$ENV_FILE" || status=$?

	# Assert
	[ "$status" -eq "$RAPID_CROSSCHECK_ENV_STATUS_SNAPSHOT_FAILED" ]
	[ -z "$(ls -A "$final")" ]
	[ ! -e "$final.part" ]
}
