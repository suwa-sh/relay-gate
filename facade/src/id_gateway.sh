#!/usr/bin/env bash
# gateway 層: run_id / attempt_id / event_id の発番と、イベント時刻の取得。
# 既定は uuidgen。RELAYGATE_ID_GENERATOR に実行ファイルを指定すると `<generator> <kind> [<qualifier>]` で発番を委譲する
# (tier BDD「run_id発番が ... を返すよう固定されている」の seam。本番運用では未設定のまま使う)。
# 時刻は rdb-schema.yaml datetime_rules に従い UTC・マイクロ秒 6 桁固定の ISO 8601 で、イベントごとに取得し記録順に単調増加させる。
# shellcheck shell=bash
# 層間で共有する CLI 実行コンテキスト(run_id 等のグローバル)は bin/relaygate と他層のファイルで定義・参照するため、
# 単一ファイル検査での未定義・未使用警告は対象外
# shellcheck disable=SC2034,SC2154

# generate_id は kind(run_id / attempt_id / event_id)と qualifier(slot 等)を渡して識別子を 1 件発番する。
generate_id() {
  local kind="$1" qualifier="${2:-}" value
  if [[ -n ${RELAYGATE_ID_GENERATOR:-} ]]; then
    value="$(deadline_run "$RELAYGATE_ID_GENERATOR" "$kind" "$qualifier")" || return 1
  else
    value="$(deadline_run uuidgen)" || return 1
    value="${value,,}"
  fi
  # SQL・SSH 環境変数へそのまま渡すため、識別子は英数字と . _ : - に限定する
  [[ $value =~ ^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$ ]] || return 1
  printf '%s' "$value"
}

# id_error は識別子発番の失敗を業務エラーで終了する。
id_error() {
  business_error "Identifier generation failed (boundary=id$1). Next action: check uuidgen or RELAYGATE_ID_GENERATOR, then rerun the job."
}

# clock_now_utc は現在時刻を UTC の ISO 8601(マイクロ秒 6 桁固定、datetime_rules.representation)で返す(perl Time::HiRes はコアモジュール)。
clock_now_utc() {
  clock_times_utc 1
}

# clock_times_utc は N 件の時刻を 1 件ずつ取得し、改行区切りで返す。同一 transaction の複数イベントの分をまとめて取得する場合も
# イベントごとに時計を読み、直前の値と同値なら後の値が得られるまで取り直す(datetime_rules.ordering_guarantee)。
clock_times_utc() {
  # shellcheck disable=SC2016
  deadline_run perl -MTime::HiRes=time -MPOSIX=strftime -e '
    my $last = "";
    for (1 .. $ARGV[0]) {
      my $now;
      do { my $t = time(); my $s = int($t); $now = sprintf("%s.%06dZ", strftime("%Y-%m-%dT%H:%M:%S", gmtime($s)), int(($t - $s) * 1_000_000)); } until ($now gt $last);
      $last = $now;
      print "$now\n";
    }' "$1"
}

# next_event_time は 1 イベント分の時刻を取得し、直前に取得した時刻より必ず後になるよう保証する
# (datetime_rules.ordering_guarantee: 同一 transaction 内の複数イベントも記録順に単調増加、同値を許さない)。
# 時計の解像度で同値になった場合は、後の時刻が得られるまで取り直す。結果はグローバル event_time に置く
# (サブシェルで呼ぶと直前時刻の記憶が失われるため、標準出力ではなく変数で返す)。
next_event_time() {
  local now
  now="$(clock_now_utc)" || return 1
  while [[ -n ${last_event_time:-} && ! $now > $last_event_time ]]; do
    now="$(clock_now_utc)" || return 1
  done
  last_event_time="$now"
  event_time="$now"
}

# next_event_times は N イベント分の時刻をまとめて取得し、配列 event_times に置く(単調増加。以降の next_event_time とも連続する)。
next_event_times() {
  local count="$1"
  event_times=()
  mapfile -t event_times < <(clock_times_utc "$count")
  [[ ${#event_times[@]} -eq $count ]] || return 1
  while [[ -n ${last_event_time:-} && ! ${event_times[0]} > $last_event_time ]]; do
    mapfile -t event_times < <(clock_times_utc "$count")
    [[ ${#event_times[@]} -eq $count ]] || return 1
  done
  last_event_time="${event_times[$((count - 1))]}"
}

# clock_error は時刻取得の失敗を業務エラーで終了する。
clock_error() {
  business_error "Clock read failed (boundary=clock). Next action: check the system clock, then rerun the job."
}

# issue_run_identity は run_id・選択 slot ごとの attempt_id と起動受付時刻(attempt_started)・履歴/監査イベント id と時刻を一度だけ確定する。
# 時刻は記録順(slot ごとの attempt_started → slot_launch_accepted → slot ごとの slot_launch_attempted)に取得する。
issue_run_identity() {
  local slot index selected_count
  run_id="$(generate_id run_id)" || id_error ""
  selected_count=${#selected_slots[@]}
  # 起動前 transaction のイベント数 = attempt_started × slot 数 + slot_launch_accepted 1 件 + slot_launch_attempted × slot 数
  next_event_times $((selected_count * 2 + 1)) || clock_error
  runner_event_ids=()
  runner_occurred_ats=()
  for index in "${!selected_slots[@]}"; do
    slot="${selected_slots[$index]}"
    slot_attempt_id["$slot"]="$(generate_id attempt_id "$slot")" || id_error ", run_id=$run_id, slot=$slot"
    runner_event_ids+=("$(generate_id event_id "runner_result_events:$slot")") || id_error ", run_id=$run_id, slot=$slot"
    runner_occurred_ats+=("${event_times[$index]}")
  done
  audit_event_ids=()
  audit_occurred_ats=()
  for ((index = 0; index <= selected_count; index++)); do
    audit_event_ids+=("$(generate_id event_id "audit_logs:$index")") || id_error ", run_id=$run_id"
    audit_occurred_ats+=("${event_times[$((selected_count + index))]}")
  done
}
