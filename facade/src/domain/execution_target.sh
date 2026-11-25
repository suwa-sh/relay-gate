#!/usr/bin/env bash
# domain: ExecutionTarget(実行先。値オブジェクト)と ArgumentList(固定引数 + PARAM。値オブジェクト)の純粋関数。
# 仕様: docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/ジョブマップで JOB_ID から実行先を解決する/
#       spec.md「分岐条件一覧」(ジョブマップ解決条件 / 引数連結規則)「計算ルール一覧」(引数連結)/
#       tier-facade.md「UC ロジック」バリデーション (6)〜(9) /
#       _cross-cutting/api/cli-command-contract.yaml shared_rules.argument_concatenation
# 行の値の判定と error 行の文言は、検証コマンドと同じ関数(domain/job_map.sh)を使う(同じ判定を二重に持たない)。
# この層は I/O を持たない。
# 依存: domain/cli_field.sh, domain/job_map.sh(呼び出し元が先に source する)

# execution_target_from_row の結果(1 件分の ExecutionTarget)。
# host / user / credential_ref / map_version は、列が無い・値が空のとき空文字(仕様の null。契約 output_format.empty_value は null と空文字を区別しない)
EXECUTION_TARGET_HOST=""
EXECUTION_TARGET_USER=""
EXECUTION_TARGET_SCRIPT=""
EXECUTION_TARGET_WORK_DIR=""
EXECUTION_TARGET_FIXED_PARAMS=()
EXECUTION_TARGET_HANG_DETECT_LIMIT_MINUTES=""
EXECUTION_TARGET_CREDENTIAL_REF=""
EXECUTION_TARGET_MAP_VERSION=""
# 実行方式(local | ssh。host / user が両方無い・両方空なら local)
EXECUTION_TARGET_EXEC=""
# build_argument_list の結果(実装へ渡す引数。固定引数の後ろに PARAM を順序どおり)
ARGUMENT_LIST=()

execution_target_reset() {
  EXECUTION_TARGET_HOST=""
  EXECUTION_TARGET_USER=""
  EXECUTION_TARGET_SCRIPT=""
  EXECUTION_TARGET_WORK_DIR=""
  EXECUTION_TARGET_FIXED_PARAMS=()
  EXECUTION_TARGET_HANG_DETECT_LIMIT_MINUTES=""
  EXECUTION_TARGET_CREDENTIAL_REF=""
  EXECUTION_TARGET_MAP_VERSION=""
  EXECUTION_TARGET_EXEC=""
  ARGUMENT_LIST=()
}

# 条件「ジョブマップ解決条件」: JobMapRow(JOB_MAP_ROW_*。job_map_row_bind 済み)を ExecutionTarget にする。
# tier-facade.md のバリデーションの順((6) host / user の空は両方同時のみ → (7) fixed_params が JSON 配列 →
# (8) hang_detect_limit_minutes が非負整数 → (9) script / work_dir が非空)で検査し、最初の違反の error 行を
# job_map_emit で 1 行だけ出して 1 を返す(runner の stderr.log は error 1 行)。値は変換しない(ハング検知上限の意味は監視側が解釈する)。
# credential_ref が秘密やパスらしい値なら、値の検査より先に warn 行を 1 行出す(受理する。値は出さない。
# 契約 columns.credential_ref.on_format_violation。検証コマンドと同じ判定・同じ文)
# 引数: line(行番号)
# 戻り値: 0 … EXECUTION_TARGET_* に載せた / 1 … 違反(error 行を 1 行出した)
# shellcheck disable=SC2034  # 結果のグローバル(共通ライブラリを使う runner が読む)
execution_target_from_row() {
  local line="$1" job_id="$JOB_MAP_ROW_JOB_ID"
  execution_target_reset
  job_map_warn_credential_ref "$line" "$job_id"
  if [ -z "$JOB_MAP_ROW_HOST" ] && [ -n "$JOB_MAP_ROW_USER" ]; then
    job_map_empty_cell_error host "$line" "$job_id"
    return 1
  fi
  if [ -n "$JOB_MAP_ROW_HOST" ] && [ -z "$JOB_MAP_ROW_USER" ]; then
    job_map_empty_cell_error user "$line" "$job_id"
    return 1
  fi
  if [ -z "$JOB_MAP_ROW_FIXED_PARAMS" ]; then
    job_map_empty_cell_error fixed_params "$line" "$job_id"
    return 1
  fi
  if ! job_map_fixed_params_parse "$JOB_MAP_ROW_FIXED_PARAMS"; then
    job_map_value_error "fixed_params is not a json array of strings" "$line" "$job_id" "$JOB_MAP_ROW_FIXED_PARAMS"
    return 1
  fi
  if [ -z "$JOB_MAP_ROW_HANG_DETECT_LIMIT_MINUTES" ]; then
    job_map_empty_cell_error hang_detect_limit_minutes "$line" "$job_id"
    return 1
  fi
  if ! job_map_is_valid_hang_detect_limit "$JOB_MAP_ROW_HANG_DETECT_LIMIT_MINUTES"; then
    job_map_value_error "hang_detect_limit_minutes is not a non-negative integer" "$line" "$job_id" "$JOB_MAP_ROW_HANG_DETECT_LIMIT_MINUTES"
    return 1
  fi
  if [ -z "$JOB_MAP_ROW_SCRIPT" ]; then
    job_map_empty_cell_error script "$line" "$job_id"
    return 1
  fi
  if [ -z "$JOB_MAP_ROW_WORK_DIR" ]; then
    job_map_empty_cell_error work_dir "$line" "$job_id"
    return 1
  fi

  EXECUTION_TARGET_HOST="$JOB_MAP_ROW_HOST"
  EXECUTION_TARGET_USER="$JOB_MAP_ROW_USER"
  EXECUTION_TARGET_SCRIPT="$JOB_MAP_ROW_SCRIPT"
  EXECUTION_TARGET_WORK_DIR="$JOB_MAP_ROW_WORK_DIR"
  EXECUTION_TARGET_FIXED_PARAMS=(${JOB_MAP_FIXED_PARAMS[@]+"${JOB_MAP_FIXED_PARAMS[@]}"})
  EXECUTION_TARGET_HANG_DETECT_LIMIT_MINUTES="$JOB_MAP_ROW_HANG_DETECT_LIMIT_MINUTES"
  EXECUTION_TARGET_CREDENTIAL_REF="$JOB_MAP_ROW_CREDENTIAL_REF"
  EXECUTION_TARGET_MAP_VERSION="$JOB_MAP_ROW_MAP_VERSION"
  if job_map_row_is_local "$JOB_MAP_ROW_HOST" "$JOB_MAP_ROW_USER"; then
    EXECUTION_TARGET_EXEC="$JOB_MAP_EXEC_LOCAL"
  else
    EXECUTION_TARGET_EXEC="$JOB_MAP_EXEC_SSH"
  fi
  return 0
}

# 条件「引数連結規則」/ 計算ルール「引数連結」: args = parse_json_array(fixed_params) ++ PARAM...
# fixed_params(JSON 配列の文字列)を要素ごとに 1 引数へ展開し、その後ろに PARAM を順序どおり足す。
# 要素の中の空白・カンマは 1 引数のまま。`[]` なら PARAM だけ。結果は ARGUMENT_LIST(bash の配列)
# 引数: fixed_params(JSON 配列の文字列) [PARAM...]
# 戻り値: 0 … ARGUMENT_LIST に載せた / 1 … fixed_params が文字列の JSON 配列でない(ARGUMENT_LIST は空)
# shellcheck disable=SC2034  # 結果のグローバル(共通ライブラリを使う runner が読む)
build_argument_list() {
  local fixed_params="$1"
  shift
  ARGUMENT_LIST=()
  if ! job_map_fixed_params_parse "$fixed_params"; then
    return 1
  fi
  ARGUMENT_LIST=(${JOB_MAP_FIXED_PARAMS[@]+"${JOB_MAP_FIXED_PARAMS[@]}"} "$@")
  return 0
}
