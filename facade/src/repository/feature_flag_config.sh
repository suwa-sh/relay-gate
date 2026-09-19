#!/usr/bin/env bash
# repository: FeatureFlagConfig(feature-flag.env の読み込み)。
# 仕様: tier-facade.md「設定契約(feature flag env)」形式
#   - 1 行 1 キー `KEY=value`。`#` 始まりはコメント、空行は無視
#   - 値の先頭末尾の `"` / `'` は除去する
#   - シェル変数展開・コマンド置換は行わない(`source` しない)
# 読み込み結果(グローバル):
#   FEATURE_FLAG_KEYS      … env に現れたキー(出現順・重複なし)。未知キー warn / 確報制御キー拒否に使う
#   FEATURE_FLAG_PATH      … 読み込んだファイルパス(引数どおり。メッセージの `path:` に使う)
#   BLUE_MODE ほか 9 キー   … 9 キーだけを同名のグローバル変数に載せる(9 キー以外は変数化しない)
# 依存: domain/feature_flag.sh(FEATURE_FLAG_DEFINED_KEYS / feature_flag_is_defined_key)

# 先頭末尾の空白を落とす
feature_flag_config_trim() {
  local text="$1"
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  printf '%s' "$text"
}

# 値の先頭・末尾のクォート(`"` / `'`)を 1 文字ずつ除去する(クォートは値の一部とみなさない)
feature_flag_config_unquote() {
  local value="$1"
  case "$value" in
    \"* | \'*) value="${value:1}" ;;
  esac
  case "$value" in
    *\" | *\') value="${value:0:${#value}-1}" ;;
  esac
  printf '%s' "$value"
}

# 9 キーのグローバル変数を初期化する(プロセス環境の同名変数を feature flag の値と混同しない)
feature_flag_config_reset() {
  local key
  for key in "${FEATURE_FLAG_DEFINED_KEYS[@]}"; do
    unset "$key"
  done
  FEATURE_FLAG_KEYS=()
  FEATURE_FLAG_PATH=""
}

# env ファイルを読み込み、9 キーをグローバル変数に載せる。
# 引数: path(存在・可読性の確認は呼び出し元 usecase の責務)
feature_flag_config_load() {
  local path="$1"
  local line key value seen
  feature_flag_config_reset
  # domain/feature_flag.sh の validate_feature_flag がメッセージの `path:` に使う
  # shellcheck disable=SC2034
  FEATURE_FLAG_PATH="$path"
  # 最終行に改行が無くても読む。CRLF の `\r` は落とす
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="$(feature_flag_config_trim "$line")"
    case "$line" in
      "" | \#*) continue ;;
    esac
    if [[ "$line" == *=* ]]; then
      key="$(feature_flag_config_trim "${line%%=*}")"
      value="$(feature_flag_config_unquote "$(feature_flag_config_trim "${line#*=}")")"
    else
      # `=` の無い行はキーだけ・値は空として扱う。評価は domain の validate_feature_flag が行う:
      #   FINAL_ で始まるキー → error(拒否。未知キー warn より先に判定)
      #   9 キー            → 値が空なので、そのキーが検証対象(mode 3 キー・off でない slot / 速報の必須キー)なら option required
      #   それ以外          → warn: unknown key
      key="$line"
      value=""
    fi
    if [ -z "$key" ]; then
      continue
    fi
    seen=0
    local existing
    for existing in ${FEATURE_FLAG_KEYS[@]+"${FEATURE_FLAG_KEYS[@]}"}; do
      if [ "$existing" = "$key" ]; then
        seen=1
        break
      fi
    done
    if [ "$seen" -eq 0 ]; then
      FEATURE_FLAG_KEYS+=("$key")
    fi
    # 9 キーだけを変数化する(同名キーが重複したら後の行が勝つ)
    if feature_flag_is_defined_key "$key"; then
      printf -v "$key" '%s' "$value"
    fi
  done <"$path"
}
