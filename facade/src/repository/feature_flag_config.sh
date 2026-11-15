#!/usr/bin/env bash
# repository: FeatureFlagConfig(feature-flag.env の読み込み)。
# 仕様: tier-facade.md「設定契約(feature flag env)」形式
#       _cross-cutting/api/cli-command-contract.yaml config_input_rules(env_files / rules / snapshot / internal_failure)
#   - 1 行 1 キー `KEY=value`。前後の空白(半角空白とタブ)を除いて `#` で始まる行はコメント、空行(0 バイトの行)は無視
#   - `=` を含まない非空・非コメント行(空白だけの行を含む)と、キーの前後の空白を除いた結果キーが空になる行は
#     形式違反の行(invalid line)として行番号を記録する(文言は usecase)
#   - 同じキーが 2 行以上あれば重複として記録する。invalid line か重複が 1 件でもあれば、そのファイルの値を 1 つも使わない
#   - キーと値の取り出し方は config_input_rules.env_files の (1)〜(4)(最初の `=` で分ける → キーの前後の空白を除く →
#     値の前後の空白を除く → 値の先頭末尾の引用符を 1 文字ずつ外す)。空白は半角空白とタブだけ
#   - シェル変数展開・コマンド置換は行わない(`source` しない)
#   - 入力は最初に 1 回だけ一時ファイルへ複製し、バイト点検(NUL / UTF-8 / BOM / CR)と行の読み取りは複製だけを読む
#     (config_input_rules.snapshot)。複製・バイト点検は slot ジョブマップと同じ関数(repository/job_map_repo.sh)を
#     使う(同じ規則を二重に実装しない)
# 読み込み結果(グローバル):
#   FEATURE_FLAG_KEYS      … env に現れたキー(出現順・重複なし)。--verbose の info / 未知キー warn / 確報制御キー拒否に使う
#   FEATURE_FLAG_PATH      … 読み込んだファイルパス(引数どおり。複製のパスではない。メッセージの `path:` に使う)
#   BLUE_MODE ほか 9 キーと任意の 2 キー(BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV)
#                          … feature flag が所有するキー(domain の FEATURE_FLAG_DEFINED_KEYS)だけを同名のグローバル変数に載せる
#                            (それ以外のキーは変数化しない。invalid line・同じキーの重複があればどのキーも未設定のまま)
# 読み取りの途中の一時的な保持(config_input_rules.env_files): 行の内容(取り込まないキーの値を含む)を置くのは、名前を固定した
#   作業用の領域(feature_flag_config_parse の local 変数と FEATURE_FLAG_CONFIG_SPLIT_LINES、入力の複製、sed / tr の入出力)だけ。
#   キー名から名前を決めた変数へ代入するのは所有するキーだけ。作業用の領域は export せず、補助コマンドへは複製のファイルで読ませる
#   (環境変数で渡さない)。読み終えたとき・失敗したときに作業用の領域を空にし、複製を消す
#   FEATURE_FLAG_CONFIG_INVALID_LINES … invalid line の行番号(昇順)
#   FEATURE_FLAG_CONFIG_DUPLICATE_KEYS / FEATURE_FLAG_CONFIG_DUPLICATE_LINES
#                          … 重複したキーと、その全出現行(カンマ区切り)。初出行の昇順
#   FEATURE_FLAG_CONFIG_FAILED_COMMANDS … 補助コマンドの失敗時に、失敗したコマンド名(カンマ区切り)
#   JOB_MAP_NUL_LINES / JOB_MAP_ENCODING_LINES / JOB_MAP_CR_LINES / JOB_MAP_BOM_LINE / JOB_MAP_MALFORMED_LINES
#                          … バイト点検の結果(job_map_repo_scan_malformed_lines が載せる。違反があれば行の読み取りはしない)
# 依存: domain/feature_flag.sh(FEATURE_FLAG_DEFINED_KEYS / feature_flag_is_defined_key)、
#       repository/job_map_repo.sh(複製・バイト点検。未 source なら自分で source する)
# shellcheck source-path=SCRIPTDIR

if ! declare -F job_map_repo_create_snapshot >/dev/null; then
  # shellcheck source=job_map_repo.sh
  source "${BASH_SOURCE[0]%/*}/job_map_repo.sh"
fi

# feature_flag_config_load の戻り値(0 以外)
# 複製完了後の補助コマンドの失敗・想定外の出力(値は conventions.exit_codes の実行エラーと同じ)
FEATURE_FLAG_CONFIG_STATUS_COMMAND_FAILED=6
# 入力の複製の失敗(config_input_rules.internal_failure はコマンド名を問わず「入力の複製の失敗」として区別する)
FEATURE_FLAG_CONFIG_STATUS_SNAPSHOT_FAILED=7
# env の空白は半角空白とタブだけ(config_input_rules.env_files。垂直タブ・改ページは空白として除かない)
FEATURE_FLAG_CONFIG_BLANKS=$' \t'

# feature_flag_config_unquote の結果(サブシェルを使わずグローバルで返す)
FEATURE_FLAG_CONFIG_UNQUOTED=""

# feature_flag_config_split_lines の結果
FEATURE_FLAG_CONFIG_SPLIT_LINES=()

# 改行区切りの文字列を行の配列 FEATURE_FLAG_CONFIG_SPLIT_LINES に分ける(単語分割。空行は無い前提。値のバイトは変えない)。
# IFS とパス名展開の設定は、この関数の中だけで変える
# 引数: text
feature_flag_config_split_lines() {
  local IFS=$'\n'
  local -
  set -f
  # shellcheck disable=SC2206  # 改行での単語分割が目的
  FEATURE_FLAG_CONFIG_SPLIT_LINES=($1)
}

# 値の先頭・末尾のクォート(`"` / `'`)を 1 文字ずつ除去して FEATURE_FLAG_CONFIG_UNQUOTED に載せる
# (config_input_rules.env_files の取り出し方 (4)。先頭と末尾は別々に判定し、種類の一致や対は求めない)
# 引数: value
feature_flag_config_unquote() {
  # 先頭と末尾の 1 文字だけを取り出して判定する(値の全体をパターンに照合しない。値の長さに上限は無い)
  local value="$1"
  case "${value:0:1}" in
    \" | \') value="${value:1}" ;;
  esac
  case "${value: -1}" in
    \" | \') value="${value:0:${#value}-1}" ;;
  esac
  FEATURE_FLAG_CONFIG_UNQUOTED="$value"
}

# 所有するキー(9 キー + 任意の 2 キー)のグローバル変数を未設定にする(プロセス環境の同名変数を feature flag の値と混同しない)
feature_flag_config_unset_values() {
  local key
  for key in "${FEATURE_FLAG_DEFINED_KEYS[@]}"; do
    unset "$key"
  done
}

# 読み込み結果を初期化する
feature_flag_config_reset() {
  feature_flag_config_unset_values
  FEATURE_FLAG_KEYS=()
  FEATURE_FLAG_PATH=""
  FEATURE_FLAG_CONFIG_INVALID_LINES=()
  FEATURE_FLAG_CONFIG_DUPLICATE_KEYS=()
  FEATURE_FLAG_CONFIG_DUPLICATE_LINES=()
  FEATURE_FLAG_CONFIG_FAILED_COMMANDS=""
  FEATURE_FLAG_CONFIG_PARSED_LINE_COUNT=0
  FEATURE_FLAG_CONFIG_SPLIT_LINES=()
}

# 行の構造を取り出す sed スクリプト(バイト単位。LC_ALL=C で実行する。基本正規表現と生のバイトだけで書く。GNU sed と BSD sed の両方で動く)。
# 入力 1 行を、種類を表す 1 文字で始まる行にして出す(出力は空行を含まない):
#   e … 空行(0 バイトの行) / c … コメント行 / i … 形式違反の行(`=` が無い・キーが空)
#   k<キー> と、その次の行に v<値> … KEY=value の行(キーは前後の空白を除いたもの。値は前後の空白を除いたもの。引用符は外さない)
# 行ごとの文字列操作を bash で行うと、長い行(数 MB のキーや値、長い空白の並び)で行の長さの 2 乗に比例する時間がかかるため、
# 行の長さに比例する時間で済む sed に任せる(性能目標「5,000 行以内かつ 8 MB 以内を内容によらず 10 秒以内」)。
# どの照合も行の長さに比例する時間で終わる形にする(置き換えは行頭に固定した 1 回の照合。行の途中の各位置から長い並びを
# 照合し直して 2 乗の時間になる形(行頭に固定しない `[空白]*$` など)は使わない)
FEATURE_FLAG_CONFIG_NORMALIZE_SED=()
feature_flag_config_build_normalize_script() {
  local blanks="$FEATURE_FLAG_CONFIG_BLANKS" newline=$'\n'
  FEATURE_FLAG_CONFIG_NORMALIZE_SED=(
    # 空行
    -e 's/^$/e/'
    -e 't'
    # コメント行 = 行の前後の空白を除いた結果が `#` で始まる行。`=` での分割より先に判定する
    # (空白だけの行は除くと空になりコメント行ではない。`KEY=#abc` は値 `#abc`)
    -e "/^[$blanks]*#/{"
    -e 's/.*/c/'
    -e 'b'
    -e '}'
    # `=` を含まない行(空白だけの行を含む)は形式違反
    -e '/=/!{'
    -e 's/.*/i/'
    -e 'b'
    -e '}'
    # キーの前の空白を除く。除いた結果キーが空(行が `=` で始まる)なら形式違反
    -e "s/^[$blanks]*//"
    -e '/^=/{'
    -e 's/.*/i/'
    -e 'b'
    -e '}'
    # キーの後ろの空白・値の前の空白・値の後ろの空白を除く(最初の `=` で分ける。キーは `=` を含まない)。
    # 部分式つきの置き換えは照合が遅いため、除く空白がある行だけで行う(前に置いた判定は部分式が無く、速い)
    -e "/^[^=]*[$blanks]=/s/^\\([^=]*[^=$blanks]\\)[$blanks]*=/\\1=/"
    -e "/^[^=]*=[$blanks]/s/^\\([^=]*=\\)[$blanks]*/\\1/"
    -e "/[$blanks]\$/s/^\\(.*[^$blanks]\\)[$blanks]*\$/\\1/"
    # 最初の `=` でキーの行と値の行に分ける
    -e "s/=/\\${newline}v/"
    -e 's/^/k/'
  )
}
feature_flag_config_build_normalize_script

# KEY=value の行を読み取り、キー一覧・invalid line・同じキーの重複・所有するキーの値を載せる(行数に比例する処理)。
# キーと値は数 MB になりうるため、行の全体を展開する回数を増やさない(1 回の展開が行の長さに比例する)
# 引数: file(読む対象。入力の複製)
# 戻り値: 0 … 読み取った / 1 … sed が失敗した・想定外の出力をした(読み込み結果は使わないこと)
# 読み込み結果のグローバルは usecase(validate_feature_flag.sh)と domain の検証表が読む
# shellcheck disable=SC2034
feature_flag_config_parse() {
  local file="$1" normalized line_number=0 index count key_index
  # キーの行(`k` + キー)→ FEATURE_FLAG_KEYS の添字。添字が `k` で始まるため、キーが `@` / `*` でも配列全体の参照と解釈されない
  local -A key_indexes=()
  # FEATURE_FLAG_KEYS と同じ添字で、そのキーの出現行(カンマ区切り)
  local -a key_lines=()
  # バイト単位で読む(事前走査の行番号・行数と対応させ、ロケールに依存させない)。最終行に改行が無くても読む
  local LC_ALL=C
  # sed 自身の stderr は出さない(internal_failure: 内部障害の報告は usecase の error 行 1 つだけ)
  if ! normalized="$(LC_ALL=C sed "${FEATURE_FLAG_CONFIG_NORMALIZE_SED[@]}" <"$file" 2>/dev/null)"; then
    return 1
  fi
  # 改行で行に分ける(単語分割。sed の出力は空行を含まない)。パス名展開はさせない
  feature_flag_config_split_lines "$normalized"
  normalized=""
  count="${#FEATURE_FLAG_CONFIG_SPLIT_LINES[@]}"
  for ((index = 0; index < count; index++)); do
    line_number=$((line_number + 1))
    case "${FEATURE_FLAG_CONFIG_SPLIT_LINES[index]:0:2}" in
      e | c) continue ;;
      i)
        FEATURE_FLAG_CONFIG_INVALID_LINES+=("$line_number")
        continue
        ;;
      k?) ;;
      *) return 1 ;;
    esac
    # キーの行の次は必ず値の行
    index=$((index + 1))
    if [ "${FEATURE_FLAG_CONFIG_SPLIT_LINES[index]:0:1}" != v ]; then
      return 1
    fi
    key_index="${key_indexes["${FEATURE_FLAG_CONFIG_SPLIT_LINES[index - 1]}"]-}"
    if [ -n "$key_index" ]; then
      # 同じキーの 2 行目以降。行番号だけを記録し、値は採らない(先の行・後の行のどちらの値も使わない)
      key_lines[key_index]+=",$line_number"
      continue
    fi
    key_index="${#FEATURE_FLAG_KEYS[@]}"
    key_indexes["${FEATURE_FLAG_CONFIG_SPLIT_LINES[index - 1]}"]="$key_index"
    key_lines[key_index]="$line_number"
    FEATURE_FLAG_KEYS+=("${FEATURE_FLAG_CONFIG_SPLIT_LINES[index - 1]:1}")
    # 所有するキー(9 キー + 任意の 2 キー)だけを変数化する(プロセス環境の PATH 等を env ファイルで上書きさせない)
    if feature_flag_is_defined_key "${FEATURE_FLAG_KEYS[key_index]}"; then
      feature_flag_config_unquote "${FEATURE_FLAG_CONFIG_SPLIT_LINES[index]:1}"
      printf -v "${FEATURE_FLAG_KEYS[key_index]}" '%s' "$FEATURE_FLAG_CONFIG_UNQUOTED"
    fi
  done
  FEATURE_FLAG_CONFIG_SPLIT_LINES=()
  FEATURE_FLAG_CONFIG_PARSED_LINE_COUNT="$line_number"
  # 同じキーの重複: 重複したキーの初出行の昇順(= キーの出現順)に 1 キー 1 件
  # (値が同じ行・値が空の行・未知キーの行も数える。config_input_rules.env_files)
  for key_index in "${!key_lines[@]}"; do
    # 出現行が 2 つ以上(カンマを含む)なら重複
    if [[ "${key_lines[key_index]}" == *,* ]]; then
      FEATURE_FLAG_CONFIG_DUPLICATE_KEYS+=("${FEATURE_FLAG_KEYS[key_index]}")
      FEATURE_FLAG_CONFIG_DUPLICATE_LINES+=("${key_lines[key_index]}")
    fi
  done
  # 行の構造の違反が 1 件でもあれば、そのファイルの値を 1 つも使わない
  if [ "${#FEATURE_FLAG_CONFIG_INVALID_LINES[@]}" -gt 0 ] || [ "${#FEATURE_FLAG_CONFIG_DUPLICATE_KEYS[@]}" -gt 0 ]; then
    feature_flag_config_unset_values
  fi
}

# env を読み込み、所有するキーをグローバル変数に載せる(複製 → バイト点検 → 行の読み取り → 複製の削除)。
# 複製は正常終了・失敗・シグナル(HUP / INT / TERM は複製を削除して 129 / 130 / 143)のいずれでも削除し、
# 呼び出し元の trap は読み込みの後に元へ戻す(job_map_repo_load と同じ扱い)。
# 引数: path(存在・可読性の確認は呼び出し元 usecase の責務)
# 戻り値: 0(読み込み完了)/ FEATURE_FLAG_CONFIG_STATUS_SNAPSHOT_FAILED(入力の複製の失敗)/
#         FEATURE_FLAG_CONFIG_STATUS_COMMAND_FAILED(複製完了後の補助コマンドの失敗・想定外の出力)
feature_flag_config_load() {
  local path="$1" saved_traps status=0
  feature_flag_config_reset
  # domain/feature_flag.sh の validate_feature_flag がメッセージの `path:` に使う
  # shellcheck disable=SC2034
  FEATURE_FLAG_PATH="$path"
  saved_traps="$(trap -p "${JOB_MAP_REPO_TRAP_SIGNALS[@]}")"
  # 一時ファイルを作る前に削除の trap を登録する(作成直後のシグナルで残さない)
  trap 'job_map_repo_remove_snapshot; exit 129' HUP
  trap 'job_map_repo_remove_snapshot; exit 130' INT
  trap 'job_map_repo_remove_snapshot; exit 143' TERM
  if job_map_repo_create_snapshot "$path"; then
    feature_flag_config_load_snapshot "$JOB_MAP_REPO_SNAPSHOT" || status=$?
  else
    status="$FEATURE_FLAG_CONFIG_STATUS_SNAPSHOT_FAILED"
  fi
  # 複製の削除の失敗は補助コマンドの失敗として扱い、読み込み結果を検証結果として使わない
  # (複製の工程が失敗していたときは「入力の複製の失敗」の報告を優先する)
  if ! job_map_repo_remove_snapshot && [ "$status" -ne "$FEATURE_FLAG_CONFIG_STATUS_SNAPSHOT_FAILED" ]; then
    local failed_commands="$FEATURE_FLAG_CONFIG_FAILED_COMMANDS"
    feature_flag_config_reset
    FEATURE_FLAG_PATH="$path"
    FEATURE_FLAG_CONFIG_FAILED_COMMANDS="${failed_commands:+$failed_commands,}rm"
    status="$FEATURE_FLAG_CONFIG_STATUS_COMMAND_FAILED"
  fi
  trap - "${JOB_MAP_REPO_TRAP_SIGNALS[@]}"
  eval "$saved_traps"
  return "$status"
}

# 複製をバイト点検し、形式違反の行が無ければ KEY=value を読み取る(feature_flag_config_load の本体)。
# 形式違反の行(NUL / 不正な UTF-8 / BOM / CR)があれば行の読み取りはしない(usecase が原因ごとの文言で拒否する)。
# 引数: snapshot
feature_flag_config_load_snapshot() {
  local snapshot="$1" path="$FEATURE_FLAG_PATH"
  if ! job_map_repo_scan_malformed_lines "$snapshot"; then
    FEATURE_FLAG_CONFIG_FAILED_COMMANDS="$JOB_MAP_REPO_FAILED_COMMANDS"
    return "$FEATURE_FLAG_CONFIG_STATUS_COMMAND_FAILED"
  fi
  if [ "${#JOB_MAP_MALFORMED_LINES[@]}" -gt 0 ]; then
    return 0
  fi
  # 行の構造の取り出しに使う sed の失敗・想定外の出力は、補助コマンドの失敗として扱う
  if ! feature_flag_config_parse "$snapshot"; then
    feature_flag_config_reset
    FEATURE_FLAG_PATH="$path"
    FEATURE_FLAG_CONFIG_FAILED_COMMANDS="sed"
    return "$FEATURE_FLAG_CONFIG_STATUS_COMMAND_FAILED"
  fi
  # 事前走査が数えた総行数と読み込んだ行数が合わなければ、走査していない行がある(検証結果として使わない)
  if [ "$FEATURE_FLAG_CONFIG_PARSED_LINE_COUNT" -ne "$JOB_MAP_SCANNED_LINE_COUNT" ]; then
    feature_flag_config_reset
    FEATURE_FLAG_PATH="$path"
    FEATURE_FLAG_CONFIG_FAILED_COMMANDS="tr,sed"
    return "$FEATURE_FLAG_CONFIG_STATUS_COMMAND_FAILED"
  fi
  return 0
}
