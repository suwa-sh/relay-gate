#!/usr/bin/env bash
# domain: SlotLaunchPlan(起動計画。値オブジェクト)と、run_id・parameters・成果物ディレクトリの計算ルール。
# 仕様: docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/spec.md
#       「計算ルール一覧」(run_id 発行 / 起動計画 / 成果物ディレクトリ / parameters(JSON))「分岐条件一覧」(slot 起動可否判定 /
#       slot 起動順序)/ tier-facade.md「UC ロジック」(起動順序: background は blue → green の固定順)
# foreground slot 排他(ちょうど 1 slot)は feature flag の検証表(domain/feature_flag.sh)が先に判定する。この層は検証を通った
# mode の組を受け取り、I/O を行わない。
# 依存: domain/feature_flag.sh(mode の列挙)、domain/job_map.sh(job_id の文字種・JSON の文字列のエスケープ)

# 起動計画の結果(サブシェルを使わずグローバルで返す)
#   SLOT_LAUNCH_PLAN_BACKGROUND … background で起動する slot(起動する順。blue → green)
#   SLOT_LAUNCH_PLAN_FOREGROUND … foreground で起動する slot(0 か 1 つ。無ければ空)
SLOT_LAUNCH_PLAN_BACKGROUND=()
SLOT_LAUNCH_PLAN_FOREGROUND=""
# 起動する slot すべて(起動する順。background すべて → foreground)
SLOT_LAUNCH_PLAN_ORDER=()

# 計算ルール「起動計画」と条件「slot 起動可否判定」「slot 起動順序」:
# background 集合 = {slot : mode=background}、foreground = {slot : mode=foreground}、off は除外。
# 起動の順は background をすべて(blue → green)→ foreground
# 引数: blue_mode green_mode
plan_slot_launch() {
  local -a slots=(blue green) modes=("$1" "$2")
  local index
  SLOT_LAUNCH_PLAN_BACKGROUND=()
  SLOT_LAUNCH_PLAN_FOREGROUND=""
  SLOT_LAUNCH_PLAN_ORDER=()
  for index in 0 1; do
    case "${modes[index]}" in
      "$FEATURE_FLAG_MODE_BACKGROUND") SLOT_LAUNCH_PLAN_BACKGROUND+=("${slots[index]}") ;;
      "$FEATURE_FLAG_MODE_FOREGROUND") SLOT_LAUNCH_PLAN_FOREGROUND="${slots[index]}" ;;
    esac
  done
  SLOT_LAUNCH_PLAN_ORDER=(${SLOT_LAUNCH_PLAN_BACKGROUND[@]+"${SLOT_LAUNCH_PLAN_BACKGROUND[@]}"})
  if [ -n "$SLOT_LAUNCH_PLAN_FOREGROUND" ]; then
    SLOT_LAUNCH_PLAN_ORDER+=("$SLOT_LAUNCH_PLAN_FOREGROUND")
  fi
}

# slot の実行モード(起動計画から)
# 引数: slot
slot_launch_plan_mode_of() {
  if [ "$1" = "$SLOT_LAUNCH_PLAN_FOREGROUND" ]; then
    printf '%s' "$FEATURE_FLAG_MODE_FOREGROUND"
  else
    printf '%s' "$FEATURE_FLAG_MODE_BACKGROUND"
  fi
}

# JOB_ID の文字種(英数字・_・- のみ。run_id の区切りと衝突させないため。tier-facade.md「引数・オプション」)
slot_launch_job_id_is_valid() {
  job_map_is_valid_job_id "$1"
}

# 計算ルール「run_id 発行」: {ローカル yyyymmddThhmmss}-{job_id}-{8 桁 hex 乱数}。結果は SLOT_LAUNCH_RUN_ID
# 引数: local_time(yyyymmddThhmmss) job_id hex8
SLOT_LAUNCH_RUN_ID=""
slot_launch_run_id() {
  # shellcheck disable=SC2034  # 結果のグローバル(呼び出し元が読む)
  SLOT_LAUNCH_RUN_ID="$1-$2-$3"
}

# 8 桁 hex 乱数の形(小文字の 16 進 8 桁)
slot_launch_hex8_is_valid() {
  if [ "${LC_ALL:-}" != C ]; then
    local LC_ALL=C
  fi
  [[ "$1" =~ ^[0-9a-f]{8}$ ]]
}

# 計算ルール「parameters(JSON)」: PARAM... を順序どおり JSON 配列の文字列にする(空なら [])。結果は SLOT_LAUNCH_PARAMETERS_JSON。
# 文字列のエスケープはジョブマップの fixed_params の JSON 表記と同じ関数を使う
# 引数: PARAM...
SLOT_LAUNCH_PARAMETERS_JSON=""
slot_launch_parameters_json() {
  local param json="[" separator=""
  for param in "$@"; do
    job_map_json_escape_string "$param"
    json+="$separator\"$JOB_MAP_JSON_ESCAPED\""
    separator=","
  done
  # shellcheck disable=SC2034  # 結果のグローバル(呼び出し元が読む)
  SLOT_LAUNCH_PARAMETERS_JSON="$json]"
}

# 計算ルール「成果物ディレクトリ」: $RELAY_GATE_ARTIFACT_ROOT/facade/<run_id>/<role>/(run ディレクトリは末尾の role を除いたもの)
# 引数: artifact_root run_id [role]
slot_launch_artifact_dir() {
  if [ $# -ge 3 ]; then
    printf '%s' "$1/facade/$2/$3"
  else
    printf '%s' "$1/facade/$2"
  fi
}
