#!/usr/bin/env bash
# domain: 現在時刻と、ローカルタイムゾーンの表記(run_id の時刻部・実行ログと管理 DB の日時)。
# 仕様: _cross-cutting/api/cli-command-contract.yaml conventions.datetime(ローカルタイムゾーン・秒精度・指示子なし。
#       UTC → ローカルの変換は 1 箇所の共通関数に置く)/ conventions.environment_variables の RELAY_GATE_NOW
#       (UTC ISO 8601 秒精度 Z 付き。形式不正は `error: invalid value env=RELAY_GATE_NOW value=...` で終了コード 2)/
#       shared_rules.run_id.timezone
# 外部コマンド(date)を使わない(GNU と BSD で引数が違うため)。UTC の暦日から epoch 秒への変換は bash の整数演算で行い、
# epoch 秒からローカルの表記への変換は bash の printf の %(...)T(プロセスの TZ に従う)で行う。

# shellcheck disable=SC2034  # 呼び出し元がエラー行の env= に使う
RELAY_GATE_CLOCK_ENV="RELAY_GATE_NOW"
# RELAY_GATE_NOW の形式(UTC ISO 8601 秒精度、Z 付き)
RELAY_GATE_CLOCK_UTC_PATTERN='^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z$'

# relay_gate_clock_* の結果(サブシェルを使わずグローバルで返す)
RELAY_GATE_CLOCK_EPOCH=""
RELAY_GATE_CLOCK_TEXT=""

# 暦日(UTC)から 1970-01-01 からの日数を求める(proleptic グレゴリオ暦。days_from_civil)。結果は RELAY_GATE_CLOCK_EPOCH(日数)
# 引数: year month day(10 進の整数。先頭の 0 は呼び出し元が外す)
relay_gate_clock_days_from_civil() {
  local year="$1" month="$2" day="$3" era yoe doy doe
  if [ "$month" -le 2 ]; then
    year=$((year - 1))
  fi
  if [ "$year" -ge 0 ]; then
    era=$((year / 400))
  else
    era=$(((year - 399) / 400))
  fi
  yoe=$((year - era * 400))
  if [ "$month" -gt 2 ]; then
    doy=$(((153 * (month - 3) + 2) / 5 + day - 1))
  else
    doy=$(((153 * (month + 9) + 2) / 5 + day - 1))
  fi
  doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
  RELAY_GATE_CLOCK_EPOCH=$((era * 146097 + doe - 719468))
}

# 月の日数(UTC の暦。うるう年を含む)
# 引数: year month
relay_gate_clock_days_in_month() {
  case "$2" in
    1 | 3 | 5 | 7 | 8 | 10 | 12) printf '%s' 31 ;;
    4 | 6 | 9 | 11) printf '%s' 30 ;;
    *)
      if { [ $(($1 % 4)) -eq 0 ] && [ $(($1 % 100)) -ne 0 ]; } || [ $(($1 % 400)) -eq 0 ]; then
        printf '%s' 29
      else
        printf '%s' 28
      fi
      ;;
  esac
}

# RELAY_GATE_NOW の値(UTC)を epoch 秒にする。結果は RELAY_GATE_CLOCK_EPOCH
# 引数: value
# 戻り値: 0 … 変換した / 1 … 形式が違う・暦に無い日時
relay_gate_clock_parse_utc() {
  local year month day hour minute second
  if [ "${LC_ALL:-}" != C ]; then
    local LC_ALL=C
  fi
  if [[ ! "$1" =~ $RELAY_GATE_CLOCK_UTC_PATTERN ]]; then
    return 1
  fi
  # 先頭の 0 を 8 進数と解釈させない
  year=$((10#${BASH_REMATCH[1]}))
  month=$((10#${BASH_REMATCH[2]}))
  day=$((10#${BASH_REMATCH[3]}))
  hour=$((10#${BASH_REMATCH[4]}))
  minute=$((10#${BASH_REMATCH[5]}))
  second=$((10#${BASH_REMATCH[6]}))
  if [ "$month" -lt 1 ] || [ "$month" -gt 12 ] || [ "$day" -lt 1 ] \
    || [ "$day" -gt "$(relay_gate_clock_days_in_month "$year" "$month")" ] \
    || [ "$hour" -gt 23 ] || [ "$minute" -gt 59 ] || [ "$second" -gt 59 ]; then
    return 1
  fi
  relay_gate_clock_days_from_civil "$year" "$month" "$day"
  RELAY_GATE_CLOCK_EPOCH=$((RELAY_GATE_CLOCK_EPOCH * 86400 + hour * 3600 + minute * 60 + second))
  return 0
}

# RELAY_GATE_NOW の値が正しい形式か(未設定・空は「設定されていない」として正しい扱い)
relay_gate_clock_injection_is_valid() {
  local value="${RELAY_GATE_NOW:-}"
  [ -z "$value" ] || relay_gate_clock_parse_utc "$value"
}

# 現在時刻(epoch 秒)を RELAY_GATE_CLOCK_EPOCH に載せる。RELAY_GATE_NOW が設定されていればその値(呼び出し元が形式を検査済み)
relay_gate_clock_now() {
  if [ -n "${RELAY_GATE_NOW:-}" ] && relay_gate_clock_parse_utc "$RELAY_GATE_NOW"; then
    return 0
  fi
  RELAY_GATE_CLOCK_EPOCH="$EPOCHSECONDS"
}

# epoch 秒をローカルタイムゾーンの run_id の時刻部(yyyymmddThhmmss。指示子なし)にする。結果は RELAY_GATE_CLOCK_TEXT
# 引数: epoch
relay_gate_clock_format_run_id_time() {
  printf -v RELAY_GATE_CLOCK_TEXT '%(%Y%m%dT%H%M%S)T' "$1"
}

# epoch 秒をローカルタイムゾーンの日時(ISO 8601 秒精度、指示子なし。例 2026-08-30T11:30:00)にする。結果は RELAY_GATE_CLOCK_TEXT
# 引数: epoch
relay_gate_clock_format_datetime() {
  # shellcheck disable=SC2034  # 結果のグローバル(呼び出し元が読む)
  printf -v RELAY_GATE_CLOCK_TEXT '%(%Y-%m-%dT%H:%M:%S)T' "$1"
}
