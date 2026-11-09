#!/usr/bin/env bash
# domain: LaunchCommandRules(値オブジェクト。速報の比較ツール起動コマンド 1 行の検証表。純粋関数)。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-facade.md
#       「検証ルール(domain: launch_command_rules)」
#       _cross-cutting/api/cli-command-contract.yaml shared_rules.compare_command_argv(split / command_part / placeholder_substitution)
# 検査はコマンド部分(先頭の引数)と `{job_id}` の有無・`{params}` の位置だけ。ほかの引数部分の内容は検査しない
# (記号・空白を含む値は拒否しない。引数として文字のまま届くため)。
# この層は I/O を持たない(実行可能かの判定はファイルの属性を見るだけで、起動はしない)。
# 違反行は `error:` を 1 行ずつ LAUNCH_COMMAND_REPORT_LINES に溜め、呼び出し元(usecase)が stderr へ出す
# (結果をグローバルで返すため、コマンド置換のサブシェルで呼ばない)。
# 依存: domain/cli_field.sh(呼び出し元が先に source する。表示用に制御文字を可視表記にする)

LAUNCH_COMMAND_KEY="RAPID_COMPARE_COMMAND"
LAUNCH_COMMAND_JOB_ID_PLACEHOLDER="{job_id}"
LAUNCH_COMMAND_PARAMS_PLACEHOLDER="{params}"
# shared_rules.compare_command_argv.split: 区切りはスペースまたはタブの 1 個以上の連続
LAUNCH_COMMAND_SEPARATORS=$' \t'

# launch_command_split の結果(引数の並び)
LAUNCH_COMMAND_ARGV=()
# launch_command_rules の結果
LAUNCH_COMMAND_PATH=""
LAUNCH_COMMAND_HAS_JOB_ID=false
LAUNCH_COMMAND_VIOLATIONS=0
LAUNCH_COMMAND_REPORT_LINES=()

# 計算ルール「コマンド部分の抽出」の前段: 値を空白区切りで引数の並びに分けて LAUNCH_COMMAND_ARGV に載せる
# (shared_rules.compare_command_argv.split。引用符・エスケープ・`$`・バッククォート・`;` などのシェルの記法は解釈せず、
# 空白の連続は 1 つの区切りとして扱い、空の引数は作らない)。
# IFS を空白文字(スペース・タブ)だけにした単語分割は、連続を 1 つの区切りにまとめ先頭末尾の空白を落とす。
# パス名展開は関数内だけ止める(`local -` で戻る時にシェルオプションを元へ戻す)。引用符・バックスラッシュは単語分割では解釈されない。
# ヒアストリングやサブプロセスを使わない(一時ファイルの失敗で値を黙って失わないため)
# 引数: value(1 行。改行を含まない。repository が行単位で読む)
launch_command_split() {
  local value="$1"
  local -
  set -f
  local IFS="$LAUNCH_COMMAND_SEPARATORS"
  # shellcheck disable=SC2206
  LAUNCH_COMMAND_ARGV=($value)
}

# 計算ルール「{params} 位置の検査」: `{params}` を含む引数は、その引数全体がちょうど `{params}` であること
# 戻り値: 0 … 適合(`{params}` を使わない場合を含む)/ 1 … 引数の一部に `{params}` を含む引数がある
# 入力: LAUNCH_COMMAND_ARGV
launch_command_params_is_whole_argument() {
  local argument
  for argument in ${LAUNCH_COMMAND_ARGV[@]+"${LAUNCH_COMMAND_ARGV[@]}"}; do
    if [[ "$argument" == *"$LAUNCH_COMMAND_PARAMS_PLACEHOLDER"* ]] && [ "$argument" != "$LAUNCH_COMMAND_PARAMS_PLACEHOLDER" ]; then
      return 1
    fi
  done
  return 0
}

# 検証表(ルール 1〜5)を評価し、違反を全件 LAUNCH_COMMAND_REPORT_LINES に溜める。
#   1 RAPID_COMPARE_COMMAND が存在し非空(分けた引数が 0 個なら空とみなす)
#   2 コマンド部分(先頭の引数)が絶対パス
#   3 コマンド部分が存在し実行可能(2 に違反したら評価しない。相対パスの存在判定は cwd に依存するため)
#   4 `{job_id}` を含む
#   5 `{params}` は引数 1 つ全体のときだけ
# 結果: LAUNCH_COMMAND_REPORT_LINES(error 行)/ LAUNCH_COMMAND_PATH(コマンド部分。空なら無し)/ LAUNCH_COMMAND_HAS_JOB_ID(true|false)/ LAUNCH_COMMAND_VIOLATIONS(件数)
# 戻り値: 0 … 違反なし / 1 … 違反あり
# 引数: present(true|false。キーが env に現れたか) value(env 解析後の値) shown_path(表示用に置き換え済みの env のパス)
# shellcheck disable=SC2034
launch_command_rules() {
  local present="$1" value="$2" shown_path="$3" shown
  LAUNCH_COMMAND_PATH=""
  LAUNCH_COMMAND_HAS_JOB_ID=false
  LAUNCH_COMMAND_VIOLATIONS=0
  LAUNCH_COMMAND_REPORT_LINES=()
  launch_command_split "$value"

  # ルール 1(欠落・空。ほかのルールは評価しない)
  if [ "$present" != true ] || [ "${#LAUNCH_COMMAND_ARGV[@]}" -eq 0 ]; then
    LAUNCH_COMMAND_REPORT_LINES+=("error: option required option=$LAUNCH_COMMAND_KEY path: $shown_path")
    LAUNCH_COMMAND_VIOLATIONS=1
    return 1
  fi

  LAUNCH_COMMAND_PATH="${LAUNCH_COMMAND_ARGV[0]}"
  cli_field_safe_text "$LAUNCH_COMMAND_PATH"
  shown="$CLI_FIELD_SAFE_TEXT"
  # ルール 2 / 3
  case "$LAUNCH_COMMAND_PATH" in
    /*)
      if [ ! -f "$LAUNCH_COMMAND_PATH" ] || [ ! -x "$LAUNCH_COMMAND_PATH" ]; then
        LAUNCH_COMMAND_REPORT_LINES+=("error: file not executable key=$LAUNCH_COMMAND_KEY path=$shown")
        LAUNCH_COMMAND_VIOLATIONS=$((LAUNCH_COMMAND_VIOLATIONS + 1))
      fi
      ;;
    *)
      LAUNCH_COMMAND_REPORT_LINES+=("error: path is not absolute key=$LAUNCH_COMMAND_KEY path=$shown")
      LAUNCH_COMMAND_VIOLATIONS=$((LAUNCH_COMMAND_VIOLATIONS + 1))
      ;;
  esac

  cli_field_safe_text "$value"
  shown="$CLI_FIELD_SAFE_TEXT"
  # ルール 4(計算ルール「{job_id} プレースホルダの検査」: 文字列に含まれるか)
  if [[ "$value" == *"$LAUNCH_COMMAND_JOB_ID_PLACEHOLDER"* ]]; then
    LAUNCH_COMMAND_HAS_JOB_ID=true
  else
    LAUNCH_COMMAND_REPORT_LINES+=("error: placeholder $LAUNCH_COMMAND_JOB_ID_PLACEHOLDER is missing key=$LAUNCH_COMMAND_KEY value=$shown")
    LAUNCH_COMMAND_VIOLATIONS=$((LAUNCH_COMMAND_VIOLATIONS + 1))
  fi
  # ルール 5
  if ! launch_command_params_is_whole_argument; then
    LAUNCH_COMMAND_REPORT_LINES+=("error: placeholder $LAUNCH_COMMAND_PARAMS_PLACEHOLDER must be a whole argument key=$LAUNCH_COMMAND_KEY value=$shown")
    LAUNCH_COMMAND_VIOLATIONS=$((LAUNCH_COMMAND_VIOLATIONS + 1))
  fi

  [ "$LAUNCH_COMMAND_VIOLATIONS" -eq 0 ]
}
