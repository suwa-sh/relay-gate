#!/usr/bin/env bash
# gateway: 実行ログ($RELAY_GATE_LOG_DIR/{script}.log への追記)。
# 仕様: _cross-cutting/ux-ui/ui-design.md「実行ログファイル」(形式 `{script} {run_id} {ローカル日時} {LEVEL} {message}`。
#       run_id が未確定の段階は `-`)/ _cross-cutting/api/cli-command-contract.yaml conventions.execution_log /
#       conventions.environment_variables の RELAY_GATE_LOG_DIR(書き込み不可は stderr に warn: を出して処理は継続)
# message に埋め込む任意入力(値・パス)の制御文字の可視表記は、呼び出し元が行う(domain/cli_field.sh の cli_field_safe_text)。
# 依存: domain/relay_gate_clock.sh

EXECUTION_LOG_SCRIPT=""
EXECUTION_LOG_FILE=""
EXECUTION_LOG_ENABLED=false
# shellcheck disable=SC2034  # run_id が未確定の段階の表記(呼び出し元が使う)
EXECUTION_LOG_NO_RUN_ID="-"

# 実行ログの出力先を決めて、書き込めるかを確かめる(ディレクトリが無ければ作る)
# 引数: script(スクリプト名) log_dir
# 戻り値: 0 … 書き込める / 1 … 書き込めない(以降の execution_log_write は何もしない)
execution_log_open() {
  EXECUTION_LOG_SCRIPT="$1"
  EXECUTION_LOG_FILE="$2/$1.log"
  EXECUTION_LOG_ENABLED=false
  if mkdir -p -- "$2" 2>/dev/null && { : >>"$EXECUTION_LOG_FILE"; } 2>/dev/null; then
    EXECUTION_LOG_ENABLED=true
    return 0
  fi
  return 1
}

# 実行ログへ 1 行追記する(書き込みの失敗は処理を止めない)
# 引数: run_id(未確定は `-`) level(DEBUG|INFO|WARN|ERROR) message
execution_log_write() {
  if [ "$EXECUTION_LOG_ENABLED" != true ]; then
    return 0
  fi
  relay_gate_clock_now
  relay_gate_clock_format_datetime "$RELAY_GATE_CLOCK_EPOCH"
  { printf '%s %s %s %s %s\n' "$EXECUTION_LOG_SCRIPT" "$1" "$RELAY_GATE_CLOCK_TEXT" "$2" "$3" >>"$EXECUTION_LOG_FILE"; } 2>/dev/null || true
}
