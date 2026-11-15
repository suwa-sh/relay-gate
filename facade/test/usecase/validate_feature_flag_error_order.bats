#!/usr/bin/env bats
# UC fd678b04 × tier-facade: validate-config.sh --feature-flag のキーごとの検査の細部の単体テスト。
# エントリポイント経由で実プロセスとして起動する。I/O 境界は実ファイル(一時ディレクトリ)。
# 仕様: CLI 契約 config_files.feature-flag.env の error_order(sequence / per_key / example)・
#       validation_rules(mode の値が列挙外・欠落・空のときの扱い)・error_messages(blue_mode= / green_mode= の `-`)、
#       config_input_rules.env_files「feature-flag.env から値を取り込むキーの範囲」、tier-facade.md「設定契約」
# 2026-11-15 S2 再実行で追加(spec event 20261115_142000_feedback_impl_feedback_fd678b04_cycle3)。
#   この仕様更新は現行実装の挙動を仕様に書いたもの(spec-decision-034)のため、現行実装(facade/src/)で green になる。
#   tier BDD(facade/features/configure-feature-flags.feature)が判定しない場合
#   (1 つのキーの error 行は 1 行だけ / 検証を通らない runner へ問い合わせない / 値を子プロセスへ渡さない)を補う。
# 2026-11-15 S2 再実行で更新(spec event 20261115_164000_feedback_runner_relative_path。2026-11-15 利用者決定):
#   runner / worker の 4 キーは相対パスを受け付け、設定ファイルのあるディレクトリを基準に解決する(契約 runner_path_resolution)。
#   `error: path is not absolute` を期待していた 2 件を、解決後のパスの `error: file not executable` の期待へ直した
#   (error_order.example の 5 行目 / per_key の検査の順「欠落・空 → 実体が無い・実行不可」)。実装は S4 で追従する。
# 性能(契約 config_input_rules.performance_target)は目標値で合否の検査ではないため、ここに時間の検査は置かない。
bats_require_minimum_version 1.5.0

setup() {
	SCRIPT="$BATS_TEST_DIRNAME/../../bin/validate-config.sh"
	CONFIG_DIR="$BATS_TEST_TMPDIR/config"
	mkdir -p "$CONFIG_DIR"
	export RELAY_GATE_CONFIG_DIR="$CONFIG_DIR"
	ENV_FILE="$BATS_TEST_TMPDIR/ff.env"
	BLUE_STUB="$BATS_TEST_TMPDIR/blue-runner.sh"
	GREEN_STUB="$BATS_TEST_TMPDIR/green-runner.sh"
	write_recording_runner "$BLUE_STUB"
	write_recording_runner "$GREEN_STUB"
}

# 起動されるたびに、受け取った引数を <スタブ>.invoked へ、受け取った環境変数を <スタブ>.env へ記録する runner スタブ
write_recording_runner() {
	printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >>"$0.invoked"' 'env >"$0.env"' 'if [ "${1:-}" = "--help" ]; then echo "runner-if-version=1"; exit 0; fi' 'exit 6' >"$1"
	chmod +x "$1"
}

# ---- error 行どうしの順(error_order.sequence / example) ----

@test "validate-config_sh_--feature-flagで6種類の違反が重なる場合_契約のerror_orderの順に12行だけを出して終了コード2であること" {
	# Arrange(契約 error_order.example と同じ 7 行。両ジョブマップは無く、設定ファイルのあるディレクトリに relative/blue-runner.sh も無い)
	printf 'BLUE_MODE=foreground\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=maybe\nGREEN_IMPL=green-1.4.0\nBLUE_RUNNER=relative/blue-runner.sh\nFINAL_POLL_LIMIT_SEC=60\nFINAL_CROSSCHECK_MODE=background\n' >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(mode → foreground の個数 → slot の実装版と runner → 速報の実体 → FINAL_ で始まるキー → 対応ジョブマップ)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 12 ]
	[ "${stderr_lines[0]}" = "error: invalid value key=RAPID_CROSSCHECK_MODE value=maybe" ]
	[ "${stderr_lines[1]}" = "hint: use foreground, background or off" ]
	[ "${stderr_lines[2]}" = "error: foreground slot must be exactly one blue_mode=foreground green_mode=foreground" ]
	[ "${stderr_lines[3]}" = "error: option required option=BLUE_IMPL path: $ENV_FILE" ]
	# 相対パスの BLUE_RUNNER は設定ファイルのあるディレクトリ基準の解決後のパスで報告する(path is not absolute は出さない)
	[ "${stderr_lines[4]}" = "error: file not executable key=BLUE_RUNNER path=$BATS_TEST_TMPDIR/relative/blue-runner.sh" ]
	[ "${stderr_lines[5]}" = "error: option required option=GREEN_RUNNER path: $ENV_FILE" ]
	[ "${stderr_lines[6]}" = "error: option required option=RAPID_CROSSCHECK_RUNNER path: $ENV_FILE" ]
	[ "${stderr_lines[7]}" = "error: option required option=RAPID_CROSSCHECK_WORKER path: $ENV_FILE" ]
	[ "${stderr_lines[8]}" = "error: final crosscheck key is not allowed key=FINAL_POLL_LIMIT_SEC" ]
	[ "${stderr_lines[9]}" = "error: final crosscheck key is not allowed key=FINAL_CROSSCHECK_MODE" ]
	[ "${stderr_lines[10]}" = "error: job map not found slot=blue map=$CONFIG_DIR/blue-job-map.csv" ]
	[ "${stderr_lines[11]}" = "error: job map not found slot=green map=$CONFIG_DIR/green-job-map.csv" ]
}

# ---- 1 つのキーの error 行は 1 行だけ(error_order.per_key) ----

@test "validate-config_sh_--feature-flagでrunnerが相対パスで実体なしと絶対パスで実体なしと空の場合_キーごとに最初に当たった違反を1行だけ出し相対パスは解決後のパスで報告すること" {
	# Arrange(GREEN_RUNNER は相対パスで実体も無い。RAPID_CROSSCHECK_RUNNER は絶対パスで実体が無い。RAPID_CROSSCHECK_WORKER は値が空)
	touch "$CONFIG_DIR/green-job-map.csv"
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=background\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=relative/missing.sh\nRAPID_CROSSCHECK_RUNNER=/nonexistent/rapid-runner.sh\nRAPID_CROSSCHECK_WORKER=\n' >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(欠落・空 → 実体が無い・実行不可 の順に検査し、1 つのキーに 1 行だけ。相対パスの runner は解決後のパスで file not executable)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 3 ]
	[ "${stderr_lines[0]}" = "error: file not executable key=GREEN_RUNNER path=$BATS_TEST_TMPDIR/relative/missing.sh" ]
	[ "${stderr_lines[1]}" = "error: file not executable key=RAPID_CROSSCHECK_RUNNER path=/nonexistent/rapid-runner.sh" ]
	[ "${stderr_lines[2]}" = "error: option required option=RAPID_CROSSCHECK_WORKER path: $ENV_FILE" ]
}

# ---- mode の値が列挙外・欠落・空のときの扱い(validation_rules / error_messages) ----

@test "validate-config_sh_--feature-flagでBLUE_MODEが列挙外でGREEN_MODEの値が空の場合_foregroundの個数のerror行にblue_mode=parallelとgreen_mode=-を出すこと" {
	# Arrange(契約 error_messages の例。従属キーとジョブマップは両 slot とも有効にして、mode と foreground の個数の行だけにする)
	touch "$CONFIG_DIR/blue-job-map.csv" "$CONFIG_DIR/green-job-map.csv"
	printf 'BLUE_MODE=parallel\nGREEN_MODE=\nRAPID_CROSSCHECK_MODE=off\nBLUE_IMPL=blue-2.3.1\nBLUE_RUNNER=%s\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=%s\n' "$BLUE_STUB" "$GREEN_STUB" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(列挙外の値はそのまま、値が空のキーは -。列挙外・空の mode は foreground に数えない)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 4 ]
	[ "${stderr_lines[0]}" = "error: invalid value key=BLUE_MODE value=parallel" ]
	[ "${stderr_lines[1]}" = "hint: use foreground, background or off" ]
	[ "${stderr_lines[2]}" = "error: option required option=GREEN_MODE path: $ENV_FILE" ]
	[ "${stderr_lines[3]}" = "error: foreground slot must be exactly one blue_mode=parallel green_mode=-" ]
}

@test "validate-config_sh_--feature-flagでmodeが列挙外のslotのrunnerが実行不可の場合_そのrunnerへは問い合わせず検証を通ったrunnerだけに--helpを1回送ること" {
	# Arrange(blue は mode が列挙外で runner が実行不可。green は有効。runner への問い合わせは絶対パス・実行可能の検証を通ったときだけ)
	touch "$CONFIG_DIR/blue-job-map.csv" "$CONFIG_DIR/green-job-map.csv"
	chmod -x "$BLUE_STUB"
	printf 'BLUE_MODE=parallel\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nBLUE_IMPL=blue-2.3.1\nBLUE_RUNNER=%s\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=%s\n' "$BLUE_STUB" "$GREEN_STUB" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 3 ]
	[ "${stderr_lines[0]}" = "error: invalid value key=BLUE_MODE value=parallel" ]
	[ "${stderr_lines[1]}" = "hint: use foreground, background or off" ]
	[ "${stderr_lines[2]}" = "error: file not executable key=BLUE_RUNNER path=$BLUE_STUB" ]
	[ ! -e "$BLUE_STUB.invoked" ]
	[ "$(cat "$GREEN_STUB.invoked")" = "--help" ]
}

# ---- 9 キー以外のキーの値を取り込まない(config_input_rules.env_files) ----

@test "validate-config_sh_--feature-flagで未知キーにPATHと独自の名前がある場合_値をrunnerの環境変数へ渡さずwarnだけを出して終了コード0であること" {
	# Arrange(有効な単独本番設定 + 未知キー 2 つ。runner スタブは受け取った環境変数を記録する)
	touch "$CONFIG_DIR/green-job-map.csv"
	printf 'PATH=/nonexistent\nBLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=%s\nRELAY_GATE_TEST_UNKNOWN_KEY=leaked-value\n' "$GREEN_STUB" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(キー名を warn の表示に使うだけ。読み手のプロセスの PATH は変わらず、子プロセスにも渡らない)
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 15 ]
	[ "${lines[14]}" = "green_runner_if_version=1" ]
	[ "${#stderr_lines[@]}" -eq 2 ]
	[ "${stderr_lines[0]}" = "warn: unknown key key=PATH path: $ENV_FILE" ]
	[ "${stderr_lines[1]}" = "warn: unknown key key=RELAY_GATE_TEST_UNKNOWN_KEY path: $ENV_FILE" ]
	[ -f "$GREEN_STUB.env" ]
	run ! grep -q '^RELAY_GATE_TEST_UNKNOWN_KEY=' "$GREEN_STUB.env"
	run ! grep -qx 'PATH=/nonexistent' "$GREEN_STUB.env"
}

@test "validate-config_sh_--feature-flagでFINAL_で始まるキーがある場合_値をrunnerの環境変数へ渡さずerrorだけを出して終了コード2であること" {
	# Arrange(有効な単独本番設定 + FINAL_ で始まるキー 1 つ。FINAL_ で始まるキーも 9 キー以外のキー)
	touch "$CONFIG_DIR/green-job-map.csv"
	printf 'BLUE_MODE=off\nGREEN_MODE=foreground\nRAPID_CROSSCHECK_MODE=off\nGREEN_IMPL=green-1.4.0\nGREEN_RUNNER=%s\nFINAL_TEST_KEY=leaked-value\n' "$GREEN_STUB" >"$ENV_FILE"

	# Act
	run --separate-stderr "$SCRIPT" --feature-flag "$ENV_FILE"

	# Assert(runner は検証を通っているため問い合わせる。その環境変数に FINAL_ で始まるキーの値は無い)
	[ "$status" -eq 2 ]
	[ -z "$output" ]
	[ "${#stderr_lines[@]}" -eq 1 ]
	[ "${stderr_lines[0]}" = "error: final crosscheck key is not allowed key=FINAL_TEST_KEY" ]
	[ -f "$GREEN_STUB.env" ]
	run ! grep -q '^FINAL_TEST_KEY=' "$GREEN_STUB.env"
}
