#!/usr/bin/env bash
# gateway: FilesystemAdapter(成果物ディレクトリ facade/<run_id>/<role>/ の Runner Result ファイルの読み書き)。
# 仕様: docs/specs/latest/実装切替業務/実装切替ジョブ実行フロー/ジョブマップで JOB_ID から実行先を解決する/
#       tier-facade.md「出力契約」(成果物(未定義・解決失敗時))「データモデル変更 / ファイル(失敗時の出力)」/
#       _cross-cutting/api/cli-command-contract.yaml artifact_layout(publish_rule: 一時ファイル <name>.tmp へ書き、確定名へ mv で公開する。
#       exitcode.txt は 3 ファイル契約の完了マーカーで最後に公開する)
# この層はメッセージを出さない(コマンド自身の stderr も出さない。runner はプロセスの stdout / stderr に出さない)。

FILESYSTEM_ADAPTER_STARTED_AT_FILE="started-at.txt"
FILESYSTEM_ADAPTER_STDOUT_FILE="stdout.log"
FILESYSTEM_ADAPTER_STDERR_FILE="stderr.log"
FILESYSTEM_ADAPTER_EXITCODE_FILE="exitcode.txt"
FILESYSTEM_ADAPTER_ABORTED_FILE="aborted.txt"
FILESYSTEM_ADAPTER_TMP_SUFFIX=".tmp"

# filesystem_adapter_slot_state の結果
FILESYSTEM_ADAPTER_SLOT_OPEN="open"
FILESYSTEM_ADAPTER_SLOT_PUBLISHED="published"
FILESYSTEM_ADAPTER_SLOT_ABORTED="aborted"
FILESYSTEM_ADAPTER_SLOT_STATE=""

# 起動時の二重起動判定に使う slot の状態を FILESYSTEM_ADAPTER_SLOT_STATE に載せる
# (契約 runner IF の idempotency / artifact_layout.files の aborted.txt の readers「slot runner」):
#   published … exitcode.txt がある(この run の結果は公開済み。aborted.txt があっても exitcode.txt が優先)
#   aborted   … exitcode.txt が無く aborted.txt がある(中止済みの slot)
#   open      … どちらも無い(started-at.txt だけがある場合を含む。通常起動では上書きしてよい)
# 引数: role_dir
# shellcheck disable=SC2034  # 結果のグローバル(呼び出し元が読む)
filesystem_adapter_slot_state() {
  if [ -e "$1/$FILESYSTEM_ADAPTER_EXITCODE_FILE" ]; then
    FILESYSTEM_ADAPTER_SLOT_STATE="$FILESYSTEM_ADAPTER_SLOT_PUBLISHED"
  elif [ -e "$1/$FILESYSTEM_ADAPTER_ABORTED_FILE" ]; then
    FILESYSTEM_ADAPTER_SLOT_STATE="$FILESYSTEM_ADAPTER_SLOT_ABORTED"
  else
    FILESYSTEM_ADAPTER_SLOT_STATE="$FILESYSTEM_ADAPTER_SLOT_OPEN"
  fi
}

# filesystem_adapter_read_exit_code の結果(0〜255)
FILESYSTEM_ADAPTER_EXIT_CODE=""

# exitcode.txt の値(0〜255 の数値 1 行)を FILESYSTEM_ADAPTER_EXIT_CODE に載せる
# 引数: role_dir
# 戻り値: 0 … 読めた / 1 … 無い・読めない・数値でない
# shellcheck disable=SC2034  # 結果のグローバル(呼び出し元が読む)
filesystem_adapter_read_exit_code() {
  local file="$1/$FILESYSTEM_ADAPTER_EXITCODE_FILE" value=""
  FILESYSTEM_ADAPTER_EXIT_CODE=""
  # 読めないときのエラーも stderr に出さない(リダイレクトは 2>/dev/null を先に置く)。最終行に改行が無くても読む
  if [ ! -f "$file" ] || ! IFS= read -r value 2>/dev/null <"$file"; then
    if [ -z "$value" ]; then
      return 1
    fi
  fi
  if [ "${LC_ALL:-}" != C ]; then
    local LC_ALL=C
  fi
  if [[ ! "$value" =~ ^[0-9]{1,3}$ ]] || [ $((10#$value)) -gt 255 ]; then
    return 1
  fi
  FILESYSTEM_ADAPTER_EXIT_CODE=$((10#$value))
}

# 公開に使ってよい名前かを確かめる: 何も無いか、リンクでない通常のファイル(前回の途中の成果物。置き換えてよい)であること。
# ディレクトリやディレクトリへのリンクへ mv すると、ファイルはその中へ移って mv は成功を返す。リンク越しの書き込みは別の場所を書き換える
# 引数: path
filesystem_adapter_name_is_publishable() {
  [ ! -L "$1" ] && { [ ! -e "$1" ] || [ -f "$1" ]; }
}

# 1 ファイルを一時ファイル(<name>.tmp)へ書いてから確定名へ mv で公開する(書き込み途中の内容を読ませない)。
# 確定名に通常のファイルでないもの(ディレクトリ・リンクなど)が先にあれば公開の失敗にする(mv の終了 0 だけでは、確定名に
# 通常のファイルを置けたことにならない)。確認と mv の間に置かれた場合に備え、mv の後にも「確定名がリンクでない自分の持つ
# 通常のファイル」であることを確かめる(入力の複製 job_map_repo_create_snapshot と同じ考え方)
# 引数: file line...(行が無ければ空のファイル)
# 戻り値: 0 … 公開した / 1 … 書けない・mv できない・確定名に通常のファイルを置けない
#   (一時ファイルは残さない。確定名に先に置かれていたものには触れない)
filesystem_adapter_publish_file() {
  local file="$1" tmp="$1$FILESYSTEM_ADAPTER_TMP_SUFFIX"
  shift
  # 一時ファイルの名前に他人の持つファイルが残っていれば、それへ書いて確定名へ移すことはしない(移した後では取り消せない)
  if ! filesystem_adapter_name_is_publishable "$tmp" || ! filesystem_adapter_name_is_publishable "$file" \
    || { [ -e "$tmp" ] && [ ! -O "$tmp" ]; }; then
    # 一時ファイルの名前に残ったリンクは、リンクそのものだけを消す(リンク先には触れない。ディレクトリは消えない)
    rm -f -- "$tmp" 2>/dev/null
    return 1
  fi
  if [ "$#" -eq 0 ]; then
    { : >"$tmp"; } 2>/dev/null || return 1
  else
    { printf '%s\n' "$@" >"$tmp"; } 2>/dev/null || {
      rm -f -- "$tmp" 2>/dev/null
      return 1
    }
  fi
  if ! mv -f -- "$tmp" "$file" 2>/dev/null; then
    rm -f -- "$tmp" 2>/dev/null
    return 1
  fi
  if [ -L "$file" ] || [ ! -f "$file" ] || [ ! -O "$file" ]; then
    # 確認の後に置かれたディレクトリの中へ移った一時ファイルは、その中の名前だけで消す
    rm -f -- "$file/${tmp##*/}" "$tmp" 2>/dev/null
    return 1
  fi
}

# 実装を実行せずに終える runner の Runner Result を揃える: started-at.txt(起動時刻)、stdout.log(空)、
# stderr.log(error 行。hint 行が続くことがある)、exitcode.txt の順に公開する。role ディレクトリが無ければ作る
# 引数: role_dir started_at(UTC ISO 8601 秒精度 Z 付き) exit_code stderr_line...
# 戻り値: 0 … 4 ファイルを揃えた / 1 … ディレクトリを作れない・どれかを書けない(exitcode.txt は公開していない)
filesystem_adapter_publish_failure() {
  local role_dir="$1" started_at="$2" exit_code="$3"
  shift 3
  mkdir -p -- "$role_dir" 2>/dev/null || return 1
  filesystem_adapter_publish_file "$role_dir/$FILESYSTEM_ADAPTER_STARTED_AT_FILE" "$started_at" || return 1
  filesystem_adapter_publish_file "$role_dir/$FILESYSTEM_ADAPTER_STDOUT_FILE" || return 1
  filesystem_adapter_publish_file "$role_dir/$FILESYSTEM_ADAPTER_STDERR_FILE" "$@" || return 1
  filesystem_adapter_publish_file "$role_dir/$FILESYSTEM_ADAPTER_EXITCODE_FILE" "$exit_code" || return 1
}
