#!/usr/bin/env bash
# gateway: RunnerProcessAdapter(slot runner のプロセス起動と PID の取得)。
# 仕様: tier-facade.md「起動する runner IF(呼び出し側の契約)」(`<runner> --run-id <run_id> --job-id <JOB_ID> --role blue|green
#       --mode foreground|background -- [PARAM...]`。background も foreground も `&` で起動して PID を記録する。runner へ渡す環境変数)/
#       「出力契約」終了コード 6(runner プロセスの起動失敗(exec 不可))/
#       「クラッシュ耐性」(runner は親を失っても継続する。setsid で起動。仮採用)/
#       _cross-cutting/api/cli-command-contract.yaml commands の facade.sh の notes(引き継ぐ環境変数。RELAY_GATE_HOME は渡さない)
# 実装で決めた前提(AssumptionRecord):
#   - runner の標準入力は /dev/null、標準出力と標準エラーは /dev/null へつなぐ(runner は stdout / stderr に出さない契約。
#     facade の stdout / stderr を runner に継承させると、facade の終了後も background の runner が出力先を開いたままになる)
#   - setsid が PATH にあれば setsid を介して起動し、無い環境(macOS など)ではそのまま起動する
#   - exec の成否は、起動ごとに作る名前付きパイプ(TMPDIR の下の一時ディレクトリ)で子から親へ知らせる。
#     runner を exec する層(setsid の後の bash)は、見張りの coproc を始めた後に最初に開始の合図の行を書く。
#     この層は close-on-exec の coproc のパイプを持ち、exec に成功するとそのパイプが閉じる。
#     exec に失敗したときだけ、coproc が名前付きパイプへ失敗を書く。親は 1 行目に開始の合図を待ち、
#     合図の後の EOF を成功、合図の後の失敗の行を失敗とする。合図の無い EOF(setsid などの見張る層より前の失敗)も失敗
#     (runner の終了は待たない。PID は runner 自身の PID のまま)

# 起動した runner の PID(runner_process_adapter_launch の結果)
RUNNER_PROCESS_PID=""
# runner へ渡す環境変数(NAME=value の並び。呼び出し元が組み立てる)と、親から引き継がせない環境変数の名前
RUNNER_PROCESS_ENV=()
RUNNER_PROCESS_UNSET=()
# exec の失敗を知らせる行と、exec を見張る層が始まったことを知らせる行
RUNNER_PROCESS_EXEC_FAILED="exec-failed"
RUNNER_PROCESS_WATCH_STARTED="watch-started"
# runner を exec する層(bash -c で動かす)。引数: 名前付きパイプの書き込み側の fd 番号 runner [引数...]
# 見張りの coproc を始めたら、最初に開始の合図の行を書く(この行が無い EOF は、この層が始まる前の失敗)。
# coproc のパイプは close-on-exec のため、exec に成功すると coproc が EOF を読んで何も書かずに終わる。
# exec に失敗したとき(execfail で続行する)だけ、coproc へ失敗を渡し、coproc が名前付きパイプへ失敗の行を書く
# shellcheck disable=SC2016  # 子の bash で展開する
RUNNER_PROCESS_EXEC_SCRIPT='status_fd="$1"
shift
coproc RELAY_GATE_EXEC_WATCH { IFS= read -r line || line=""; if [ "$line" = failed ]; then printf "%s\n" "exec-failed" >&"$status_fd"; fi; }
if [ -z "${RELAY_GATE_EXEC_WATCH_PID:-}" ]; then
  printf "%s\n" "exec-failed" >&"$status_fd"
  exit 126
fi
printf "%s\n" "watch-started" >&"$status_fd"
exec {status_fd}>&-
shopt -s execfail
exec "$@"
printf "%s\n" failed >&"${RELAY_GATE_EXEC_WATCH[1]}"
exit 126'

# runner を runner IF で起動する(待たない)
# 引数: runner(解決後のパス) run_id job_id role mode [PARAM...]
# 戻り値: 0 … 起動した(RUNNER_PROCESS_PID に PID)/ 1 … 起動できなかった(実体が実行可能なファイルでない・exec の失敗・
#         名前付きパイプを作れない・exec を見張る層が始まる前に終わった)
runner_process_adapter_launch() {
  local runner="$1" run_id="$2" job_id="$3" role="$4" mode="$5" launcher=() work_dir status_pipe status_fd first="" line=""
  shift 5
  RUNNER_PROCESS_PID=""
  if [ ! -f "$runner" ] || [ ! -x "$runner" ]; then
    return 1
  fi
  if ! work_dir="$(mktemp -d "${TMPDIR:-/tmp}/relay-gate-launch.XXXXXX" 2>/dev/null)" || [ -z "$work_dir" ]; then
    return 1
  fi
  status_pipe="$work_dir/exec-status"
  if ! mkfifo -m 600 "$status_pipe" 2>/dev/null; then
    rm -rf -- "$work_dir"
    return 1
  fi
  if command -v setsid >/dev/null 2>&1; then
    launcher=(setsid)
  fi
  (
    # 最初に名前付きパイプの書き込み側を開く(親の読み込み側の open はこれを待つ)
    exec {status_fd}>"$status_pipe"
    local name assignment
    for name in ${RUNNER_PROCESS_UNSET[@]+"${RUNNER_PROCESS_UNSET[@]}"}; do
      unset "$name"
    done
    for assignment in ${RUNNER_PROCESS_ENV[@]+"${RUNNER_PROCESS_ENV[@]}"}; do
      export "${assignment?}"
    done
    shopt -s execfail
    exec ${launcher[@]+"${launcher[@]}"} "$BASH" -c "$RUNNER_PROCESS_EXEC_SCRIPT" relay-gate-runner-exec "$status_fd" \
      "$runner" --run-id "$run_id" --job-id "$job_id" --role "$role" --mode "$mode" -- "$@"
    printf '%s\n' "$RUNNER_PROCESS_EXEC_FAILED" >&"$status_fd"
    exit 126
  ) </dev/null >/dev/null 2>&1 &
  RUNNER_PROCESS_PID="$!"
  exec {status_fd}<"$status_pipe"
  # 1 行目は開始の合図(無ければ見張る層が始まる前の失敗)。合図の後は EOF(exec の成功)か失敗の行
  IFS= read -r -u "$status_fd" first || first=""
  if [ "$first" = "$RUNNER_PROCESS_WATCH_STARTED" ]; then
    IFS= read -r -u "$status_fd" line || line=""
  else
    line="$RUNNER_PROCESS_EXEC_FAILED"
  fi
  exec {status_fd}<&-
  rm -rf -- "$work_dir"
  if [ -n "$line" ]; then
    # 起動に失敗した子はすぐに終わる(回収して PID を残さない)
    wait "$RUNNER_PROCESS_PID" 2>/dev/null || true
    RUNNER_PROCESS_PID=""
    return 1
  fi
  [ -n "$RUNNER_PROCESS_PID" ]
}

# runner の終了を待つ(foreground の PID だけを待つ)
# 引数: pid
runner_process_adapter_wait() {
  local status=0
  wait "$1" || status=$?
  return "$status"
}

# background の runner を facade のジョブ表から外す(待たない。facade が終わっても runner は続く)
# 引数: pid
runner_process_adapter_detach() {
  disown "$1" 2>/dev/null || true
}
