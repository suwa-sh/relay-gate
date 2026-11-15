#!/usr/bin/env bats
# UC fd678b04 × tier-facade: runner / worker の実体パスの解決(domain の関数)の単体テスト。
# 仕様: CLI 契約 config_files.feature-flag.env.runner_path_resolution(relative_criteria / base_dir / resolved_path / examples)
# 実行時の読み手(後続の UC)が同じ関数を再利用するため、関数単位で字面の規則を固定する。
# エントリポイント経由の判定(実体の検査・問い合わせ・表示)は test/usecase/validate_feature_flag_runner_path.bats。

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/feature_flag.sh"
}

# ---- 基準のディレクトリ(base_dir) ----

@test "feature_flag_resolve_runner_base_dir_設定ファイルが絶対パスの場合_最後のスラッシュより前を基準にし作業ディレクトリを使わないこと" {
	# Act
	feature_flag_resolve_runner_base_dir /etc/relay-gate/feature-flag.env /work

	# Assert
	[ "$FEATURE_FLAG_RUNNER_BASE_DIR" = "/etc/relay-gate" ]
}

@test "feature_flag_resolve_runner_base_dir_設定ファイルが相対パスの場合_作業ディレクトリと連結してから基準を決めること" {
	# Act
	feature_flag_resolve_runner_base_dir conf/ff.env /work

	# Assert
	[ "$FEATURE_FLAG_RUNNER_BASE_DIR" = "/work/conf" ]
}

@test "feature_flag_resolve_runner_base_dir_設定ファイルがファイル名だけの場合_作業ディレクトリを基準にすること" {
	# Act
	feature_flag_resolve_runner_base_dir ff.env /work

	# Assert
	[ "$FEATURE_FLAG_RUNNER_BASE_DIR" = "/work" ]
}

@test "feature_flag_resolve_runner_base_dir_作業ディレクトリがルートの場合_スラッシュを重ねずに連結すること" {
	# Act(契約 examples (c): 作業ディレクトリ / で conf/ff.env → /conf/ff.env → 基準 /conf)
	feature_flag_resolve_runner_base_dir conf/ff.env /

	# Assert
	[ "$FEATURE_FLAG_RUNNER_BASE_DIR" = "/conf" ]
}

@test "feature_flag_resolve_runner_base_dir_最後のスラッシュが先頭の1文字の場合_基準はルートであること" {
	# Act
	feature_flag_resolve_runner_base_dir /ff.env /work

	# Assert
	[ "$FEATURE_FLAG_RUNNER_BASE_DIR" = "/" ]
}

@test "feature_flag_resolve_runner_base_dir_作業ディレクトリがルートでファイル名だけの場合_基準はルートであること" {
	# Act
	feature_flag_resolve_runner_base_dir ff.env /

	# Assert
	[ "$FEATURE_FLAG_RUNNER_BASE_DIR" = "/" ]
}

@test "feature_flag_resolve_runner_base_dir_パスにドットと連続するスラッシュがある場合_字面を畳まないこと" {
	# Act(契約 examples (a)(b))
	feature_flag_resolve_runner_base_dir ./config/feature-flag.env /opt/relay-gate
	local relative_base="$FEATURE_FLAG_RUNNER_BASE_DIR"
	feature_flag_resolve_runner_base_dir /etc/relay-gate//feature-flag.env /work
	local doubled_base="$FEATURE_FLAG_RUNNER_BASE_DIR"
	feature_flag_resolve_runner_base_dir /etc/../etc/relay-gate/./feature-flag.env /work

	# Assert
	[ "$relative_base" = "/opt/relay-gate/./config" ]
	[ "$doubled_base" = "/etc/relay-gate/" ]
	[ "$FEATURE_FLAG_RUNNER_BASE_DIR" = "/etc/../etc/relay-gate/." ]
}

@test "feature_flag_resolve_runner_base_dir_作業ディレクトリを省略した場合_シェルのPWDを使うこと" {
	# Arrange
	cd "$BATS_TEST_TMPDIR"

	# Act
	feature_flag_resolve_runner_base_dir conf/ff.env

	# Assert
	[ "$FEATURE_FLAG_RUNNER_BASE_DIR" = "$PWD/conf" ]
}

# ---- 解決後のパス(resolved_path) ----

@test "feature_flag_resolve_runner_path_値が絶対パスの場合_値をそのまま返すこと" {
	# Act
	feature_flag_resolve_runner_path /etc/relay-gate /opt/relay-gate/runners/../runners//blue-runner.sh

	# Assert
	[ "$FEATURE_FLAG_RESOLVED_RUNNER_PATH" = "/opt/relay-gate/runners/../runners//blue-runner.sh" ]
}

@test "feature_flag_resolve_runner_path_値が相対パスの場合_基準とスラッシュと値を畳まずに連結すること" {
	# Act(契約 resolved_path の例)
	feature_flag_resolve_runner_path /etc/relay-gate ./blue-runner.sh
	local dotted="$FEATURE_FLAG_RESOLVED_RUNNER_PATH"
	feature_flag_resolve_runner_path /etc/relay-gate green-runner.sh
	local bare="$FEATURE_FLAG_RESOLVED_RUNNER_PATH"
	feature_flag_resolve_runner_path /etc/relay-gate ../bin/rapid-crosscheck-runner.sh
	local parent="$FEATURE_FLAG_RESOLVED_RUNNER_PATH"
	feature_flag_resolve_runner_path /etc/relay-gate/ ./blue-runner.sh

	# Assert
	[ "$dotted" = "/etc/relay-gate/./blue-runner.sh" ]
	[ "$bare" = "/etc/relay-gate/green-runner.sh" ]
	[ "$parent" = "/etc/relay-gate/../bin/rapid-crosscheck-runner.sh" ]
	[ "$FEATURE_FLAG_RESOLVED_RUNNER_PATH" = "/etc/relay-gate//./blue-runner.sh" ]
}

@test "feature_flag_resolve_runner_path_基準がルートの場合_スラッシュと値を連結すること" {
	# Act
	feature_flag_resolve_runner_path / blue-runner.sh

	# Assert
	[ "$FEATURE_FLAG_RESOLVED_RUNNER_PATH" = "/blue-runner.sh" ]
}

@test "feature_flag_resolve_runner_path_値にチルダと環境変数とコマンド置換がある場合_展開せず文字のまま相対パスとして連結すること" {
	# Arrange
	local marker="$BATS_TEST_TMPDIR/expanded"

	# Act
	feature_flag_resolve_runner_path /conf '~/runner.sh'
	local tilde="$FEATURE_FLAG_RESOLVED_RUNNER_PATH"
	# shellcheck disable=SC2016  # 展開されないことを確かめる
	feature_flag_resolve_runner_path /conf '$HOME/runner.sh'
	local variable="$FEATURE_FLAG_RESOLVED_RUNNER_PATH"
	feature_flag_resolve_runner_path /conf "\$(touch $marker)/runner.sh"

	# Assert
	[ "$tilde" = "/conf/~/runner.sh" ]
	# shellcheck disable=SC2016
	[ "$variable" = '/conf/$HOME/runner.sh' ]
	[ "$FEATURE_FLAG_RESOLVED_RUNNER_PATH" = "/conf/\$(touch $marker)/runner.sh" ]
	[ ! -e "$marker" ]
}

@test "feature_flag_resolve_runner_path_値が空の場合_解決せず空を返すこと" {
	# Act
	feature_flag_resolve_runner_path /etc/relay-gate ""

	# Assert(空は必須キーの欠落・空として扱う)
	[ -z "$FEATURE_FLAG_RESOLVED_RUNNER_PATH" ]
}

# ---- 4 キーの置き換え ----

@test "feature_flag_resolve_runner_paths_4キーが相対パスの場合_設定ファイルのあるディレクトリ基準の解決後のパスに置き換えること" {
	# Arrange
	FEATURE_FLAG_PATH=/etc/relay-gate/feature-flag.env
	BLUE_MODE=foreground
	GREEN_MODE=background
	RAPID_CROSSCHECK_MODE=background
	BLUE_RUNNER=./blue-runner.sh
	GREEN_RUNNER=/opt/relay-gate/runners/green-runner.sh
	RAPID_CROSSCHECK_RUNNER=../bin/rapid-runner.sh
	RAPID_CROSSCHECK_WORKER=rapid-worker.sh

	# Act
	feature_flag_resolve_runner_paths /work

	# Assert
	[ "$BLUE_RUNNER" = "/etc/relay-gate/./blue-runner.sh" ]
	[ "$GREEN_RUNNER" = "/opt/relay-gate/runners/green-runner.sh" ]
	[ "$RAPID_CROSSCHECK_RUNNER" = "/etc/relay-gate/../bin/rapid-runner.sh" ]
	[ "$RAPID_CROSSCHECK_WORKER" = "/etc/relay-gate/rapid-worker.sh" ]
}

@test "feature_flag_resolve_runner_paths_2回呼んだ場合_結果が変わらないこと" {
	# Arrange
	FEATURE_FLAG_PATH=conf/ff.env
	BLUE_MODE=foreground
	GREEN_MODE=off
	RAPID_CROSSCHECK_MODE=off
	BLUE_RUNNER=blue-runner.sh

	# Act
	feature_flag_resolve_runner_paths /work
	feature_flag_resolve_runner_paths /elsewhere

	# Assert
	[ "$BLUE_RUNNER" = "/work/conf/blue-runner.sh" ]
}

@test "feature_flag_resolve_runner_paths_offのslotと速報offと空と未設定の場合_値を変えないこと" {
	# Arrange(検査しないキーは解決しない。空・未設定は必須キーの欠落・空のまま)
	FEATURE_FLAG_PATH=/etc/relay-gate/feature-flag.env
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	BLUE_RUNNER=./blue-runner.sh
	GREEN_RUNNER=""
	RAPID_CROSSCHECK_RUNNER=./rapid-runner.sh
	unset RAPID_CROSSCHECK_WORKER

	# Act
	feature_flag_resolve_runner_paths /work

	# Assert
	[ "$BLUE_RUNNER" = "./blue-runner.sh" ]
	[ -z "$GREEN_RUNNER" ]
	[ "$RAPID_CROSSCHECK_RUNNER" = "./rapid-runner.sh" ]
	[ -z "${RAPID_CROSSCHECK_WORKER+x}" ]
}

@test "feature_flag_resolve_runner_paths_modeが列挙外と欠落の場合_offでないとして解決すること" {
	# Arrange(off として扱うのは値が off と完全一致するときだけ)
	FEATURE_FLAG_PATH=/etc/relay-gate/feature-flag.env
	BLUE_MODE=parallel
	unset GREEN_MODE
	RAPID_CROSSCHECK_MODE=""
	BLUE_RUNNER=b.sh
	GREEN_RUNNER=g.sh
	RAPID_CROSSCHECK_RUNNER=r.sh
	RAPID_CROSSCHECK_WORKER=w.sh

	# Act
	feature_flag_resolve_runner_paths /work

	# Assert
	[ "$BLUE_RUNNER" = "/etc/relay-gate/b.sh" ]
	[ "$GREEN_RUNNER" = "/etc/relay-gate/g.sh" ]
	[ "$RAPID_CROSSCHECK_RUNNER" = "/etc/relay-gate/r.sh" ]
	[ "$RAPID_CROSSCHECK_WORKER" = "/etc/relay-gate/w.sh" ]
}

@test "validate_feature_flag_runnerが相対パスで実体が無い場合_解決後のパスのfile not executableを出すこと" {
	# Arrange
	FEATURE_FLAG_PATH="$BATS_TEST_TMPDIR/conf/ff.env"
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_IMPL=g
	GREEN_RUNNER=bin/green.sh

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -eq 1 ]
	[ "$output" = "error: file not executable key=GREEN_RUNNER path=$BATS_TEST_TMPDIR/conf/bin/green.sh" ]
}

@test "validate_feature_flag_runnerが相対パスで実体が設定ファイルのあるディレクトリにある場合_違反なしであること" {
	# Arrange(作業ディレクトリは別の場所)
	mkdir -p "$BATS_TEST_TMPDIR/conf/bin" "$BATS_TEST_TMPDIR/work"
	printf '#!/usr/bin/env bash\n' >"$BATS_TEST_TMPDIR/conf/bin/green.sh"
	chmod +x "$BATS_TEST_TMPDIR/conf/bin/green.sh"
	cd "$BATS_TEST_TMPDIR/work"
	FEATURE_FLAG_PATH="$BATS_TEST_TMPDIR/conf/ff.env"
	BLUE_MODE=off
	GREEN_MODE=foreground
	RAPID_CROSSCHECK_MODE=off
	GREEN_IMPL=g
	GREEN_RUNNER=./bin/green.sh

	# Act
	run validate_feature_flag

	# Assert
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}
