#!/usr/bin/env bash
# repository: RapidCrosscheckEnvRecord(速報クロスチェック設定 rapid-crosscheck.env の読み取り。RDB には触れない)。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md
#       「データフロー」repository 行(KEY=VALUE。入力の守備範囲は CLI 契約 config_input_rules)
#       _cross-cutting/api/cli-command-contract.yaml config_input_rules(env_files / rules / snapshot / internal_failure)
#   - 1 行 1 キー `KEY=VALUE`。行頭 `#` の行はコメント、空行(0 バイトの行)は無視
#   - `=` を含まない非空・非コメント行(空白だけの行を含む)は形式違反の行として行番号を記録する(文言は usecase)
#   - 値の先頭末尾のクォート除去は UC「feature flag を設定する」の設定契約に従う(repository/feature_flag_config.sh と同じ規則)
#   - `source` しない(シェル変数展開・コマンド置換は行わない)
#   - 入力は最初に 1 回だけ一時ファイルへ複製し、バイト点検(NUL / UTF-8 / BOM / CR)と行の読み取りは複製だけを読む。
#     複製・バイト点検は slot ジョブマップと同じ関数(repository/job_map_repo.sh)を使う(同じ規則を二重に実装しない)
# 読み込み結果(グローバル):
#   RAPID_CROSSCHECK_ENV_KEYS             … env に現れたキー(出現順・重複なし。--verbose の info に使う)
#   RAPID_CROSSCHECK_ENV_HAS_COMPARE_COMMAND … RAPID_COMPARE_COMMAND が現れたか(true|false)
#   RAPID_CROSSCHECK_ENV_COMPARE_COMMAND  … RAPID_COMPARE_COMMAND の値(env 解析後。同じキーが重複したら後の行が勝つ)
#   RAPID_CROSSCHECK_ENV_INVALID_LINES    … `=` を含まない・キーが空の行の行番号(昇順)
#   JOB_MAP_NUL_LINES / JOB_MAP_ENCODING_LINES / JOB_MAP_CR_LINES / JOB_MAP_BOM_LINE / JOB_MAP_MALFORMED_LINES
#                                         … バイト点検の結果(job_map_repo_scan_malformed_lines が載せる)
#   RAPID_CROSSCHECK_ENV_FAILED_COMMANDS  … 補助コマンドの失敗時に、失敗したコマンド名(カンマ区切り)
# 戻り値: 0(読み込み完了)/ RAPID_CROSSCHECK_ENV_STATUS_SNAPSHOT_FAILED(入力の複製の失敗)/
#         RAPID_CROSSCHECK_ENV_STATUS_COMMAND_FAILED(複製完了後の補助コマンドの失敗・想定外の出力)
# 依存: repository/job_map_repo.sh(複製・バイト点検)

RAPID_CROSSCHECK_ENV_COMPARE_COMMAND_KEY="RAPID_COMPARE_COMMAND"
RAPID_CROSSCHECK_ENV_STATUS_COMMAND_FAILED=6
RAPID_CROSSCHECK_ENV_STATUS_SNAPSHOT_FAILED=7

rapid_crosscheck_env_reset() {
  RAPID_CROSSCHECK_ENV_KEYS=()
  RAPID_CROSSCHECK_ENV_HAS_COMPARE_COMMAND=false
  RAPID_CROSSCHECK_ENV_COMPARE_COMMAND=""
  RAPID_CROSSCHECK_ENV_INVALID_LINES=()
  RAPID_CROSSCHECK_ENV_FAILED_COMMANDS=""
  RAPID_CROSSCHECK_ENV_TRIMMED=""
  RAPID_CROSSCHECK_ENV_UNQUOTED=""
}

# env を読み込む(複製 → バイト点検 → 行の読み取り → 複製の削除)。
# 複製は正常終了・失敗・シグナル(HUP / INT / TERM は複製を削除して 129 / 130 / 143)のいずれでも削除し、
# 呼び出し元の trap は読み込みの後に元へ戻す(job_map_repo_load と同じ扱い)。
# 引数: path(存在・可読性の確認は呼び出し元 usecase の責務)
rapid_crosscheck_env_read() {
  local path="$1" saved_traps status=0
  rapid_crosscheck_env_reset
  saved_traps="$(trap -p "${JOB_MAP_REPO_TRAP_SIGNALS[@]}")"
  trap 'job_map_repo_remove_snapshot; exit 129' HUP
  trap 'job_map_repo_remove_snapshot; exit 130' INT
  trap 'job_map_repo_remove_snapshot; exit 143' TERM
  if job_map_repo_create_snapshot "$path"; then
    rapid_crosscheck_env_read_snapshot "$JOB_MAP_REPO_SNAPSHOT" || status=$?
  else
    status="$RAPID_CROSSCHECK_ENV_STATUS_SNAPSHOT_FAILED"
  fi
  # 複製の削除の失敗は補助コマンドの失敗として扱い、読み込み結果を検証結果として使わない
  # (複製の工程が失敗していたときは「入力の複製の失敗」の報告を優先する)
  if ! job_map_repo_remove_snapshot && [ "$status" -ne "$RAPID_CROSSCHECK_ENV_STATUS_SNAPSHOT_FAILED" ]; then
    local failed_commands="$RAPID_CROSSCHECK_ENV_FAILED_COMMANDS"
    rapid_crosscheck_env_reset
    RAPID_CROSSCHECK_ENV_FAILED_COMMANDS="${failed_commands:+$failed_commands,}rm"
    status="$RAPID_CROSSCHECK_ENV_STATUS_COMMAND_FAILED"
  fi
  trap - "${JOB_MAP_REPO_TRAP_SIGNALS[@]}"
  eval "$saved_traps"
  return "$status"
}

# 複製をバイト点検し、形式違反の行が無ければ KEY=VALUE を読み取る(rapid_crosscheck_env_read の本体)。
# 形式違反の行(NUL / 不正な UTF-8 / BOM / CR)があれば行の読み取りはしない(usecase が原因ごとの文言で拒否する)。
# 引数: snapshot
# 読み込み結果のグローバルは usecase(validate_rapid_crosscheck.sh)が読む
# shellcheck disable=SC2034
rapid_crosscheck_env_read_snapshot() {
  local snapshot="$1" line line_number=0 key
  local -A seen_keys=()
  if ! job_map_repo_scan_malformed_lines "$snapshot"; then
    RAPID_CROSSCHECK_ENV_FAILED_COMMANDS="$JOB_MAP_REPO_FAILED_COMMANDS"
    return "$RAPID_CROSSCHECK_ENV_STATUS_COMMAND_FAILED"
  fi
  if [ "${#JOB_MAP_MALFORMED_LINES[@]}" -gt 0 ]; then
    return 0
  fi
  # バイト単位で読む(事前走査の行番号・行数と対応させる)。最終行に改行が無くても読む
  local LC_ALL=C
  while IFS= read -r line || [ -n "$line" ]; do
    line_number=$((line_number + 1))
    case "$line" in
      "" | \#*) continue ;;
    esac
    if [[ "$line" != *=* ]]; then
      RAPID_CROSSCHECK_ENV_INVALID_LINES+=("$line_number")
      continue
    fi
    rapid_crosscheck_env_trim "${line%%=*}"
    key="$RAPID_CROSSCHECK_ENV_TRIMMED"
    if [ -z "$key" ]; then
      RAPID_CROSSCHECK_ENV_INVALID_LINES+=("$line_number")
      continue
    fi
    # 添字に接頭辞を付ける(キーが `@` / `*` のとき配列全体の参照と解釈させない)
    if [ -z "${seen_keys["k:$key"]+x}" ]; then
      seen_keys["k:$key"]=1
      RAPID_CROSSCHECK_ENV_KEYS+=("$key")
    fi
    if [ "$key" = "$RAPID_CROSSCHECK_ENV_COMPARE_COMMAND_KEY" ]; then
      rapid_crosscheck_env_trim "${line#*=}"
      rapid_crosscheck_env_unquote "$RAPID_CROSSCHECK_ENV_TRIMMED"
      RAPID_CROSSCHECK_ENV_HAS_COMPARE_COMMAND=true
      RAPID_CROSSCHECK_ENV_COMPARE_COMMAND="$RAPID_CROSSCHECK_ENV_UNQUOTED"
    fi
  done <"$snapshot"
  # 事前走査が数えた総行数と読み込んだ行数が合わなければ、走査していない行がある(検証結果として使わない)
  if [ "$line_number" -ne "$JOB_MAP_SCANNED_LINE_COUNT" ]; then
    rapid_crosscheck_env_reset
    RAPID_CROSSCHECK_ENV_FAILED_COMMANDS="tr,sed"
    return "$RAPID_CROSSCHECK_ENV_STATUS_COMMAND_FAILED"
  fi
  return 0
}

# 先頭末尾の空白を落として RAPID_CROSSCHECK_ENV_TRIMMED に載せる(feature_flag_config_trim と同じ規則。
# 行数に比例して呼ばれるため、コマンド置換のサブシェルを使わずグローバルで返す)
# 引数: text
rapid_crosscheck_env_trim() {
  local text="$1"
  text="${text#"${text%%[![:space:]]*}"}"
  RAPID_CROSSCHECK_ENV_TRIMMED="${text%"${text##*[![:space:]]}"}"
}

# 値の先頭・末尾のクォート(`"` / `'`)を 1 文字ずつ除去して RAPID_CROSSCHECK_ENV_UNQUOTED に載せる
# (UC「feature flag を設定する」の設定契約。feature_flag_config_unquote と同じ規則をサブシェルなしで行う)
# 引数: value
rapid_crosscheck_env_unquote() {
  local value="$1"
  case "$value" in
    \"* | \'*) value="${value:1}" ;;
  esac
  case "$value" in
    *\" | *\') value="${value:0:${#value}-1}" ;;
  esac
  RAPID_CROSSCHECK_ENV_UNQUOTED="$value"
}
