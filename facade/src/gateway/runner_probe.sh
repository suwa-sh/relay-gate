#!/usr/bin/env bash
# gateway: slot runner 実体への `--help` 問い合わせ(runner IF 版の取得)。
# 仕様の正本: _cross-cutting/api/cli-command-contract.yaml commands[validate-config.sh].runner_help_probe
#   - timeout_seconds_per_slot: 4(1 slot あたりの待機上限)
#   - timeout_action: 上限到達で runner のプロセスグループへ TERM、0.2 秒後に KILL(runner は独立したプロセスグループで起動し、
#     runner が起動した子プロセスも同じグループとして回収する)。停止後は「応答しない」
#   - no_response_criteria: 上限到達 / 終了コード非 0 / `runner-if-version=` 行が無い / 採用行の値が 1(現在の runner IF 版)でない
#   - version_line_selection: `runner-if-version=` で始まる最初の 1 行を採用し、`=` より右の前後空白を除いた文字列を版の値とする
#   - preparation_failure: 一時ファイルの作成・プロセスグループでの起動に失敗したら未応答と区別する(呼び出し元が終了コード 6 にする)
# 実行順(blue → green の逐次)と問い合わせ対象の選別(mode=off / 実体検証違反の slot は問い合わせない)は usecase の責務。
# 外部プロセスの起動はこの層に閉じる。stdin は /dev/null、stderr は捨てる。

RUNNER_IF_VERSION_KEY="runner-if-version"
# 現在の runner IF 版(契約 runner_help_probe.response_result: `<slot>_runner_if_version=1`)
RUNNER_IF_VERSION_CURRENT="1"
# 待機上限(秒)。契約 runner_help_probe.timeout_seconds_per_slot
RUNNER_PROBE_TIMEOUT_SEC=4
# 生存確認の間隔(秒)。契約には無い実装上の粒度(上限到達の検出は最大この時間だけ遅れる)
RUNNER_PROBE_POLL_INTERVAL_SEC=0.1
# TERM 後に KILL するまでの猶予(秒)。契約 runner_help_probe.timeout_action
RUNNER_PROBE_KILL_GRACE_SEC=0.2

# runner_probe_if_version の戻り値
RUNNER_PROBE_STATUS_RESPONDED=0
RUNNER_PROBE_STATUS_NO_RESPONSE=1
RUNNER_PROBE_STATUS_PREPARATION_FAILED=2
# runner_probe_run_with_limit: 待機上限到達の戻り値(timeout(1) と同じ 124)
RUNNER_PROBE_RUN_TIMED_OUT=124
# runner_probe_run_with_limit がプロセスグループでの起動に失敗したときに 1 を立てる(runner の終了コードと区別するためのフラグ)
RUNNER_PROBE_START_FAILED=0

# runner を独自プロセスグループで起動し、待機上限内に終了すれば runner の終了コード、
# 上限到達(強制終了)なら 124 を返す。プロセスグループでの起動に失敗したら RUNNER_PROBE_START_FAILED=1 を立てて非 0 を返す。
# 引数: runner output_file timeout_sec
runner_probe_run_with_limit() {
  local runner="$1" output_file="$2" timeout_sec="$3"
  local pid="" status waited_ms limit_ms
  RUNNER_PROBE_START_FAILED=0
  # job control を一時的に有効にし、background job を独自プロセスグループ(pgid = pid)にする
  if ! set -m 2>/dev/null; then
    RUNNER_PROBE_START_FAILED=1
    return 1
  fi
  "$runner" --help </dev/null >"$output_file" 2>/dev/null &
  pid=$!
  set +m 2>/dev/null || true
  if [ -z "$pid" ]; then
    RUNNER_PROBE_START_FAILED=1
    return 1
  fi
  waited_ms=0
  limit_ms=$((timeout_sec * 1000))
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited_ms" -ge "$limit_ms" ]; then
      kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
      sleep "$RUNNER_PROBE_KILL_GRACE_SEC"
      kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return "$RUNNER_PROBE_RUN_TIMED_OUT"
    fi
    sleep "$RUNNER_PROBE_POLL_INTERVAL_SEC"
    waited_ms=$((waited_ms + 100))
  done
  wait "$pid"
  status=$?
  return "$status"
}

# 先頭末尾の空白を落とす(版の値の正規化。契約 runner_help_probe.version_line_selection)
runner_probe_trim() {
  local text="$1"
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  printf '%s' "$text"
}

# 版の値が現在の runner IF 版(1)か。契約 runner_help_probe.no_response_criteria の最後の項目
runner_probe_version_is_current() {
  [ "$1" = "$RUNNER_IF_VERSION_CURRENT" ]
}

# 引数: runner(絶対パス・実行可能であることは呼び出し元が確認済み) [timeout_sec(既定 RUNNER_PROBE_TIMEOUT_SEC)]
# 戻り値と stdout:
#   0 … 応答した。stdout に採用した `runner-if-version=` 行の値(前後空白除去済み。現在版かの判定は呼び出し元)
#   1 … 応答しない(非 0 終了・待機上限到達・版行なし)。stdout なし
#   2 … 準備失敗(一時ファイルの作成・プロセスグループでの起動)。stdout に理由(`reason=` の値。空白を含まない)
runner_probe_if_version() {
  local runner="$1" timeout_sec="${2:-$RUNNER_PROBE_TIMEOUT_SEC}"
  local output_file="" line found="$RUNNER_PROBE_STATUS_NO_RESPONSE" run_status
  if ! output_file="$(mktemp "${TMPDIR:-/tmp}/relay-gate-runner-probe.XXXXXX" 2>/dev/null)" || [ -z "$output_file" ]; then
    printf '%s\n' "temp-file-create-failed tmpdir=${TMPDIR:-/tmp}"
    return "$RUNNER_PROBE_STATUS_PREPARATION_FAILED"
  fi
  runner_probe_run_with_limit "$runner" "$output_file" "$timeout_sec"
  run_status=$?
  if [ "$RUNNER_PROBE_START_FAILED" -ne 0 ]; then
    rm -f "$output_file"
    printf '%s\n' "process-group-start-failed runner=$runner"
    return "$RUNNER_PROBE_STATUS_PREPARATION_FAILED"
  fi
  if [ "$run_status" -ne 0 ]; then
    rm -f "$output_file"
    return "$RUNNER_PROBE_STATUS_NO_RESPONSE"
  fi
  # 版行の採用規則: 最初の 1 行だけを採用し、2 行目以降は無視する
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$RUNNER_IF_VERSION_KEY="*)
        printf '%s\n' "$(runner_probe_trim "${line#*=}")"
        found="$RUNNER_PROBE_STATUS_RESPONDED"
        break
        ;;
    esac
  done <"$output_file"
  rm -f "$output_file"
  return "$found"
}
