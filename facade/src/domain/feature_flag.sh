#!/usr/bin/env bash
# domain: FeatureFlag(値オブジェクト)/ SlotRunnerAssignment の検証表と運用モード名の導出。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/tier-facade.md
#       「設定契約(feature flag env)」「組合せ検証」「運用モード表」
# 文言の正本: _cross-cutting/api/cli-command-contract.yaml config_files.feature-flag.env.error_messages
# この層は I/O(env ファイル読み込み・runner --help の起動)を行わない。実体パスの存在・実行可否だけは
# 仕様が domain の責務としているため `test` で判定する。
# 違反行は stdout に `error:` / `hint:` / `warn:` 1 行ずつ出し(全件収集。1 件目で止めない)、
# 呼び出し元(usecase)が stderr へ振り分ける。戻り値は「error 行が 1 件以上あれば 1、無ければ 0」。
# 値は任意文字列(実装版 `-n` 等)を含むため、出力は echo ではなく printf の固定フォーマットで行う。

# 設定所有区分: feature flag が所有する 9 キー(元の方針資料の設定契約と同じ。設定版は持たない)
FEATURE_FLAG_DEFINED_KEYS=(
  BLUE_MODE
  GREEN_MODE
  RAPID_CROSSCHECK_MODE
  BLUE_IMPL
  GREEN_IMPL
  BLUE_RUNNER
  GREEN_RUNNER
  RAPID_CROSSCHECK_RUNNER
  RAPID_CROSSCHECK_WORKER
)

# slot 実行モード / 速報クロスチェックモードの列挙(3 値)
FEATURE_FLAG_MODE_FOREGROUND="foreground"
FEATURE_FLAG_MODE_BACKGROUND="background"
FEATURE_FLAG_MODE_OFF="off"
FEATURE_FLAG_MODE_HINT="hint: use foreground, background or off"

# 確報クロスチェック非起動: キー名が `FINAL_` で始まる全キーは feature flag に置けない
# (接頭辞判定・大文字小文字を区別。キー名の列挙ではない。未知キー warn より先に判定し、同じキーに warn は出さない)。
# 範囲の正本: cli-command-contract.yaml config_files.feature-flag.env.validation_rules
FEATURE_FLAG_FORBIDDEN_KEY_PREFIX="FINAL_"

# 運用モード名(英字コード。RDRA バリエーション「運用モード」)
OPERATION_MODE_PARALLEL="parallel"
OPERATION_MODE_GREEN_ONLY="green_only"
OPERATION_MODE_NEXT_GEN_PARALLEL="next_gen_parallel"
OPERATION_MODE_CUSTOM="custom"

# 空値の表記(ui-design.md 出力フォーマット「空値」)
FEATURE_FLAG_EMPTY_VALUE="-"

# 9 キーに含まれるか
feature_flag_is_defined_key() {
  local key="$1" defined
  for defined in "${FEATURE_FLAG_DEFINED_KEYS[@]}"; do
    if [ "$key" = "$defined" ]; then
      return 0
    fi
  done
  return 1
}

# mode 値が列挙(foreground / background / off)に含まれるか
feature_flag_is_valid_mode() {
  case "$1" in
    "$FEATURE_FLAG_MODE_FOREGROUND" | "$FEATURE_FLAG_MODE_BACKGROUND" | "$FEATURE_FLAG_MODE_OFF") return 0 ;;
    *) return 1 ;;
  esac
}

# 速報クロスチェック有効判定 / slot の検証対象判定: 「off か off 以外か」で判定する
feature_flag_mode_is_active() {
  [ "$1" != "$FEATURE_FLAG_MODE_OFF" ]
}

# 計算ルール「foreground 数」: BLUE_MODE / GREEN_MODE のうち foreground の個数
count_foreground() {
  local count=0 mode
  for mode in "$@"; do
    if [ "$mode" = "$FEATURE_FLAG_MODE_FOREGROUND" ]; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

# 計算ルール「運用モード名」: (BLUE_MODE, GREEN_MODE, RAPID_CROSSCHECK_MODE) → operation_mode
derive_operation_mode() {
  local blue="$1" green="$2" rapid="$3"
  case "$blue/$green/$rapid" in
    "$FEATURE_FLAG_MODE_FOREGROUND/$FEATURE_FLAG_MODE_BACKGROUND/$FEATURE_FLAG_MODE_BACKGROUND")
      printf '%s\n' "$OPERATION_MODE_PARALLEL"
      ;;
    "$FEATURE_FLAG_MODE_OFF/$FEATURE_FLAG_MODE_FOREGROUND/$FEATURE_FLAG_MODE_OFF")
      printf '%s\n' "$OPERATION_MODE_GREEN_ONLY"
      ;;
    "$FEATURE_FLAG_MODE_BACKGROUND/$FEATURE_FLAG_MODE_FOREGROUND/$FEATURE_FLAG_MODE_BACKGROUND")
      printf '%s\n' "$OPERATION_MODE_NEXT_GEN_PARALLEL"
      ;;
    *)
      printf '%s\n' "$OPERATION_MODE_CUSTOM"
      ;;
  esac
}

# 値が空なら空値表記 `-` に置き換える
feature_flag_display_value() {
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$FEATURE_FLAG_EMPTY_VALUE"
  fi
}

# mode キー 1 つの検証: 必須(欠落・空)→ 列挙
# 引数: key path value
validate_feature_flag_mode_key() {
  local key="$1" path="$2" value="$3"
  if [ -z "$value" ]; then
    printf '%s\n' "error: option required option=$key path: $path"
    return 1
  fi
  if ! feature_flag_is_valid_mode "$value"; then
    printf '%s\n' "error: invalid value key=$key value=$value"
    printf '%s\n' "$FEATURE_FLAG_MODE_HINT"
    return 1
  fi
  return 0
}

# 非空文字列キー(<SLOT>_IMPL)の検証: 欠落・空は option required
# 引数: key path value
validate_feature_flag_required_value() {
  local key="$1" path="$2" value="$3"
  if [ -z "$value" ]; then
    printf '%s\n' "error: option required option=$key path: $path"
    return 1
  fi
  return 0
}

# 実体パスキー(<SLOT>_RUNNER / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER)の検証:
# 欠落 → 絶対パス → 存在かつ実行可能
# 引数: key path value
validate_feature_flag_executable_path() {
  local key="$1" path="$2" value="$3"
  if [ -z "$value" ]; then
    printf '%s\n' "error: option required option=$key path: $path"
    return 1
  fi
  case "$value" in
    /*) ;;
    *)
      printf '%s\n' "error: path is not absolute key=$key path=$value"
      return 1
      ;;
  esac
  if [ ! -f "$value" ] || [ ! -x "$value" ]; then
    printf '%s\n' "error: file not executable key=$key path=$value"
    return 1
  fi
  return 0
}

# 実体パスが検証を通過済み(絶対パス・存在・実行可能)か。runner --help 問い合わせの前提判定に使う
feature_flag_path_is_executable() {
  local value="$1"
  case "$value" in
    /*) [ -f "$value" ] && [ -x "$value" ] ;;
    *) return 1 ;;
  esac
}

# 検証表の全項目を評価する(違反は全件収集)。
# 入力(グローバル。repository が env から構築する):
#   BLUE_MODE GREEN_MODE RAPID_CROSSCHECK_MODE BLUE_IMPL GREEN_IMPL BLUE_RUNNER GREEN_RUNNER
#   RAPID_CROSSCHECK_RUNNER RAPID_CROSSCHECK_WORKER(未設定可)
#   FEATURE_FLAG_PATH(メッセージの `path:` に使う。未設定なら `-`)
#   FEATURE_FLAG_KEYS(env に現れたキー一覧。未知キー warn / 確報制御キー拒否に使う。未設定なら評価しない)
validate_feature_flag() {
  local path="${FEATURE_FLAG_PATH:-$FEATURE_FLAG_EMPTY_VALUE}"
  local errors=0
  local blue_mode="${BLUE_MODE:-}" green_mode="${GREEN_MODE:-}" rapid_mode="${RAPID_CROSSCHECK_MODE:-}"

  # 列挙・必須(BLUE_MODE / GREEN_MODE / RAPID_CROSSCHECK_MODE)
  validate_feature_flag_mode_key BLUE_MODE "$path" "$blue_mode" || errors=$((errors + 1))
  validate_feature_flag_mode_key GREEN_MODE "$path" "$green_mode" || errors=$((errors + 1))
  validate_feature_flag_mode_key RAPID_CROSSCHECK_MODE "$path" "$rapid_mode" || errors=$((errors + 1))

  # 条件「foreground slot 排他」: foreground はちょうど 1 slot(2 個・0 個は同じ文言で NG)
  if [ "$(count_foreground "$blue_mode" "$green_mode")" -ne 1 ]; then
    printf '%s\n' "error: foreground slot must be exactly one blue_mode=$(feature_flag_display_value "$blue_mode") green_mode=$(feature_flag_display_value "$green_mode")"
    errors=$((errors + 1))
  fi

  # slot 実行モード: off 以外の slot は <SLOT>_IMPL(非空)と <SLOT>_RUNNER(実体)が必須。off は検証をスキップ
  if feature_flag_mode_is_active "$blue_mode"; then
    validate_feature_flag_required_value BLUE_IMPL "$path" "${BLUE_IMPL:-}" || errors=$((errors + 1))
    validate_feature_flag_executable_path BLUE_RUNNER "$path" "${BLUE_RUNNER:-}" || errors=$((errors + 1))
  fi
  if feature_flag_mode_is_active "$green_mode"; then
    validate_feature_flag_required_value GREEN_IMPL "$path" "${GREEN_IMPL:-}" || errors=$((errors + 1))
    validate_feature_flag_executable_path GREEN_RUNNER "$path" "${GREEN_RUNNER:-}" || errors=$((errors + 1))
  fi

  # 条件「速報クロスチェック有効判定」: off 以外は速報 runner / worker の実体が必須
  if feature_flag_mode_is_active "$rapid_mode"; then
    validate_feature_flag_executable_path RAPID_CROSSCHECK_RUNNER "$path" "${RAPID_CROSSCHECK_RUNNER:-}" || errors=$((errors + 1))
    validate_feature_flag_executable_path RAPID_CROSSCHECK_WORKER "$path" "${RAPID_CROSSCHECK_WORKER:-}" || errors=$((errors + 1))
  fi

  # 条件「確報クロスチェック非起動」/「設定所有区分」: env に現れたキーの検査
  # (FINAL_ 接頭辞の拒否を先に判定し、それ以外の 9 キー外キーだけを未知キー warn にする)
  local key
  for key in ${FEATURE_FLAG_KEYS[@]+"${FEATURE_FLAG_KEYS[@]}"}; do
    case "$key" in
      "$FEATURE_FLAG_FORBIDDEN_KEY_PREFIX"*)
        printf '%s\n' "error: final crosscheck key is not allowed key=$key"
        errors=$((errors + 1))
        ;;
      *)
        if ! feature_flag_is_defined_key "$key"; then
          printf '%s\n' "warn: unknown key key=$key path: $path"
        fi
        ;;
    esac
  done

  [ "$errors" -eq 0 ]
}

# SlotRunnerAssignment: off でない slot の対応ジョブマップ `<slot>-job-map.csv` が存在し読めること
# (UC「slot runner の実体スクリプトを割り当てる」が validate-config.sh --feature-flag に追加する検証項目)
# 引数: slot(blue|green) mode job_map_path
validate_slot_runner_assignment() {
  local slot="$1" mode="$2" job_map="$3"
  if ! feature_flag_mode_is_active "$mode"; then
    return 0
  fi
  if [ ! -f "$job_map" ] || [ ! -r "$job_map" ]; then
    printf '%s\n' "error: job map not found slot=$slot map=$job_map"
    return 1
  fi
  return 0
}
