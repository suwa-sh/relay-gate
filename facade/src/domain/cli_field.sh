#!/usr/bin/env bash
# domain: CLI 出力フィールド(stdout の「1 行 1 事実」の表現)。
# 仕様: _cross-cutting/ux-ui/ui-design.md「出力フォーマット」/ cli-command-contract.yaml conventions.output_format.stdout
#   - `key=value`(値に空白を含まない)/ `key: value`(値に空白・パスを含む。`:` の後に半角空白 1 つ)
#   - 空値は `key=` ではなく `key=-`
#   - ANSI エスケープを出さない(conventions.output_format.color)。1 行 1 事実
# 任意文字列の値(実装版など)を扱うため、出力は必ず printf の固定フォーマットで行う
# (echo は `-n` / `-e` などの値をオプションとして解釈してしまう)。
# 任意入力(設定ファイルの値・引数のパス)に含まれる制御文字は、生のまま出さず可視表記へ置き換える
# (cli_field_safe_text。ESC は ANSI エスケープになり、改行は 1 行 1 事実を崩すため)。
# この層は I/O を持たない(標準出力へ書くだけ。呼び出し元が振り分ける)。

# 空値の表記(ui-design.md 出力フォーマット「空値」)
CLI_FIELD_EMPTY_VALUE="-"

# 表示のときに置き換える 1 バイトの制御文字: U+0001〜U+001F と U+007F(8 進表記)。
# U+0000 は bash の文字列に入らない。
CLI_FIELD_CONTROL_CHARS=$'\001\002\003\004\005\006\007\010\011\012\013\014\015\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037\177'
# C1 制御文字 U+0080〜U+009F の UTF-8 表現は 0xC2 + 0x80〜0x9F の 2 バイト(U+009B は端末が CSI として解釈する)。
# 0xC2 は UTF-8 の先頭バイトにしか現れないため、この 2 バイトの並びは常に C1 制御文字を表す
CLI_FIELD_C1_LEAD_BYTE=$'\xc2'
CLI_FIELD_C1_TRAIL_BYTES=$'\x80\x81\x82\x83\x84\x85\x86\x87\x88\x89\x8a\x8b\x8c\x8d\x8e\x8f\x90\x91\x92\x93\x94\x95\x96\x97\x98\x99\x9a\x9b\x9c\x9d\x9e\x9f'
# cli_field_escape_chunk が窓を断片へ分けるときの区切り(U+001F。置き換える文字の 1 つなので、区切った後の断片には残らない)。
# bash が内部で使う U+0001 / U+007F と、単語分割で連続を 1 つにまとめられる空白類(タブ・改行・CR など)は使えない
CLI_FIELD_ESCAPE_SEPARATOR=$'\037'
# cli_field_escape_text が 1 回に取り込む窓の大きさ(バイト)。結果には影響しない(長い値の処理時間だけに効く)
CLI_FIELD_ESCAPE_WINDOW_BYTES=1024
# 表示のときに置き換えが要る文字の集合(cli_field_safe_text の早期判定用。制御文字と C1 制御文字の先頭バイト)
CLI_FIELD_SAFE_SPECIAL_CHARS="$CLI_FIELD_CONTROL_CHARS$CLI_FIELD_C1_LEAD_BYTE"

# cli_field_escape_text の結果
CLI_FIELD_ESCAPED=""
# cli_field_safe_text の結果
CLI_FIELD_SAFE_TEXT=""

# 可視表記の表(添字は `k` + 元の 1 バイト。`@` / `*` を配列全体の参照と解釈させないために接頭辞を付ける)。
#   CLI_FIELD_ESCAPE_TABLE … 1 バイトの制御文字 → `\n` / `\t` / `\u00XX`
# C1 制御文字は 32 種類を同じ添字の 2 つの配列に並べる:
#   CLI_FIELD_C1_SEQUENCES … C1 制御文字の 2 バイト(0xC2 + 0x80〜0x9F)
#   CLI_FIELD_C1_ESCAPES   … その可視表記 `\u00XX`
# 関数の中から source されてもグローバルに置く(declare -g)
declare -gA CLI_FIELD_ESCAPE_TABLE=()
declare -ga CLI_FIELD_C1_SEQUENCES=() CLI_FIELD_C1_ESCAPES=()
cli_field_build_escape_tables() {
  local index char number code
  local LC_ALL=C
  for ((index = 0; index < ${#CLI_FIELD_CONTROL_CHARS}; index++)); do
    char="${CLI_FIELD_CONTROL_CHARS:index:1}"
    printf -v code '%04x' "'$char"
    CLI_FIELD_ESCAPE_TABLE["k$char"]="\\u$code"
  done
  CLI_FIELD_ESCAPE_TABLE["k"$'\n']="\\n"
  CLI_FIELD_ESCAPE_TABLE["k"$'\t']="\\t"
  for ((index = 0; index < ${#CLI_FIELD_C1_TRAIL_BYTES}; index++)); do
    char="${CLI_FIELD_C1_TRAIL_BYTES:index:1}"
    # C1 制御文字の符号位置は 2 バイト目の値と同じ(符号拡張された値を返す環境に備えて下位 8 ビットだけ使う)
    printf -v number '%d' "'$char"
    printf -v code '%04x' "$((number & 255))"
    CLI_FIELD_C1_SEQUENCES+=("$CLI_FIELD_C1_LEAD_BYTE$char")
    CLI_FIELD_C1_ESCAPES+=("\\u$code")
  done
}
cli_field_build_escape_tables

# ---- まとめて変換する経路(外部コマンド sed / tr を、値の個数によらず一定回数だけ起動する) ----
# 性能目標「5,000 行以内かつ 8 MB 以内のファイルを、内容によらず 10 秒以内」(目標値。入力を制限する仕様ではない)。
# bash の文字列操作による置き換え(cli_field_escape_chunk)は、制御文字の種類が多い値で 1 バイトあたり数マイクロ秒かかり、
# 数 MB の入力では 10 秒を超える。行数に比例する個数の値や大きな値を表示する呼び出し元は、表示の前に
# cli_field_safe_text_list / cli_field_safe_text_prepare を呼び、1 行 1 値にして sed へ渡す。
# 結果のバイト列は bash の経路と同じ(test/domain/cli_field_batch.bats が bash の経路・参照実装と比べる)。
# 外部コマンドを使うのは、この 2 つの関数を呼んだときだけ(cli_field_safe_text などの値ごとの関数は外部コマンドを起動しない)。
# 外部コマンドの失敗・想定外の出力は戻り値で伝え、失敗したコマンド名を CLI_FIELD_BATCH_FAILED_COMMANDS に載せる
# (CLI 契約 config_input_rules.internal_failure「補助コマンドの失敗」として報告するかどうかは呼び出し元が決める)

# 値の合計がこの大きさ(バイト)以上なら sed で置き換える。未満は bash で置き換える(プロセスの起動のほうが高くつく)。
# 結果には影響しない
CLI_FIELD_ESCAPE_EXTERNAL_MIN_BYTES=4096
# sed の出力で 1 つの値の終わりを表す目印(U+001F)。1 段目の sed が 1 バイトの制御文字をすべて可視表記にした後に付けるため、
# 値の中の文字と混ざらない。bash が内部で使う U+0001 / U+007F は使わない
CLI_FIELD_BATCH_RECORD_END=$'\037'
# パイプラインの終了状態(sed 2 つと tr 1 つ。使わなかったコマンドは 0)を、最後の値の後ろへ付ける証跡の接頭辞と、
# 全コマンドが成功したときの証跡
CLI_FIELD_BATCH_TRAILER_PREFIX="ok:"
CLI_FIELD_BATCH_OK_TRAILER="ok:0 0 0"
# cli_field_escape_batch が失敗したときの、失敗した外部コマンド名(カンマ区切り。パイプラインの順)。成功したときは空
CLI_FIELD_BATCH_FAILED_COMMANDS=""

# sed のスクリプト(バイト単位。LC_ALL=C で実行する)。拡張正規表現や \xHH の拡張に頼らず、基本正規表現と生のバイトだけで書く
# (GNU sed と BSD sed の両方で動く)。置き換えの回数は値の個数にも制御文字の種類の数にもよらない:
#   1 バイトの制御文字(CLI_FIELD_BATCH_SED_CONTROLS):
#     - タブ → `\t`
#     - U+0001〜U+000F → `\u000` + 元の 1 バイト、U+0010〜U+001F → `\u001` + 元の 1 バイト、U+007F → `\u007f`
#     - 残った元の 1 バイトを y で 16 進 1 桁へ写す(この時点で、行に残る 1 バイトの制御文字は可視表記の最後の 1 桁の位置だけ)
#   C1 制御文字(0xC2 + 0x80〜0x9F)。値に 0xC2 があるときだけ使う 2 段:
#     - 1 段目(CLI_FIELD_BATCH_SED_ESCAPE = 上の置き換え + 次の 2 つ): C1 制御文字の前後で行を分け(C1 制御文字 1 つだけの行にする)、
#       値の終わりに目印を付ける
#     - 2 段目(CLI_FIELD_BATCH_SED_C1): C1 制御文字 1 つだけの行を `\u008X` / `\u009X` にする
#       (y は行全体に効くため、0x80〜0x9F のバイトを含みうる他の部分と行を分けてから使う。
#        0xC2 で始まる通常の 2 バイト文字(U+00A0〜U+00BF)と、UTF-8 として不正な並びの 0xC2 は行が分かれず、変わらない)
#     - その後 tr で改行をすべて消すと、値は目印で区切られた 1 本の並びになる
declare -ga CLI_FIELD_BATCH_SED_CONTROLS=() CLI_FIELD_BATCH_SED_ESCAPE=() CLI_FIELD_BATCH_SED_C1=()
cli_field_build_batch_scripts() {
  local tab=$'\t' newline=$'\n' delete=$'\177' lead="$CLI_FIELD_C1_LEAD_BYTE"
  local low=$'\001\002\003\004\005\006\007\010\013\014\015\016\017'
  local high=$'\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037'
  local trail_8="${CLI_FIELD_C1_TRAIL_BYTES:0:16}" trail_9="${CLI_FIELD_C1_TRAIL_BYTES:16:16}"
  local hex="0123456789abcdef"
  CLI_FIELD_BATCH_SED_CONTROLS=(
    -e "s/$tab/\\\\t/g"
    -e "s/[$low]/\\\\u000&/g"
    -e "s/[$high]/\\\\u001&/g"
    -e "s/$delete/\\\\u007f/g"
    -e "y/$low$high/12345678bcdef$hex/"
  )
  CLI_FIELD_BATCH_SED_ESCAPE=(
    "${CLI_FIELD_BATCH_SED_CONTROLS[@]}"
    -e "s/${lead}[$trail_8$trail_9]/\\$newline&\\$newline/g"
    -e "s/\$/$CLI_FIELD_BATCH_RECORD_END/"
  )
  CLI_FIELD_BATCH_SED_C1=(
    -e "/^${lead}[$trail_8]\$/{"
    -e "y/$trail_8/$hex/"
    -e "s/^$lead/\\\\u008/"
    -e "}"
    -e "/^${lead}[$trail_9]\$/{"
    -e "y/$trail_9/$hex/"
    -e "s/^$lead/\\\\u009/"
    -e "}"
  )
}
cli_field_build_batch_scripts

# 値をまとめて可視表記にし、呼び出し元の配列に同じ並びで載せる(規則は cli_field_escape_text と同じ。
# 前にバックスラッシュを付ける文字の指定は無い)。外部コマンドの起動回数は値の個数によらない:
#   - どの値にも 0xC2 が無く、空の値も無いとき: sed 1 回(1 行 1 値のまま返る)
#   - それ以外: sed 2 回と tr 1 回(C1 制御文字の置き換えのため。1 つの値が数 MB のときは 3 つが順に動くため、上の 2〜3 倍かかる)
# 置き換える文字を含まない値も渡してよい(1 バイトも変わらない)。
# 結果は呼び出し元の配列へ直接載せる(数十 MB の結果を配列から配列へ写すと、写すたびに 0.5 秒前後かかる)。
# 引数: target_name(結果を載せる配列の名前。この関数の中の変数名(cli_field_batch_target / batch_ で始まる名前)以外) text...
# 戻り値: 0 … 置き換えた / 1 … 外部コマンドが失敗した・想定外の出力をした(結果は空。失敗したコマンド名は
#         CLI_FIELD_BATCH_FAILED_COMMANDS。sed か tr のどちらか。どの終了状態も 0 なのに出力の件数が合わないときは、
#         使ったコマンドすべて(sed、または sed,tr))
cli_field_escape_batch() {
  local -n cli_field_batch_target="$1"
  shift
  local batch_count="$#" batch_text batch_output batch_trailer
  local batch_has_newline=false batch_needs_c1=false
  local -a batch_lines=()
  cli_field_batch_target=()
  CLI_FIELD_BATCH_FAILED_COMMANDS=""
  if [ "$batch_count" -eq 0 ]; then
    return 0
  fi
  if [ "${LC_ALL:-}" != C ]; then
    local LC_ALL=C
  fi
  # 値の中の改行・0xC2・空の値の有無を調べる(1 バイトの有無だけを見る。置き換える文字の種類ごとには調べない)
  for batch_text in "$@"; do
    if [ -z "$batch_text" ] || [[ "$batch_text" == *"$CLI_FIELD_C1_LEAD_BYTE"* ]]; then
      batch_needs_c1=true
    fi
    if [[ "$batch_text" == *$'\n'* ]]; then
      batch_has_newline=true
    fi
  done
  # 1 行 1 値で渡す。値の中の改行は、先に可視表記 `\n`(2 文字)にしておく(バックスラッシュは置き換えの対象ではないため、sed は変えない)
  if [ "$batch_has_newline" = true ]; then
    for batch_text in "$@"; do
      batch_lines+=("${batch_text//$'\n'/"\\n"}")
    done
    set -- "${batch_lines[@]}"
  fi
  # sed / tr 自身の stderr は出さない(失敗は戻り値で伝える。sed が読み切らずに終わったときの printf の書き込みエラーも出さない)。
  # sed 2 つと tr の終了状態(使わなかったコマンドは 0)を、最後の値の後ろに証跡として付ける。
  # 結果は変数で受ける(パイプから 1 件ずつ読むと 1 バイトごとの読み取りになり、数十 MB で数秒かかる)。
  # 値に分けるのは単語分割(パス名展開はさせない。IFS と set -f はこの関数の中だけ)
  local IFS
  local -
  set -f
  if [ "$batch_needs_c1" = true ]; then
    batch_output="$(
      printf '%s\n' "$@" 2>/dev/null \
        | LC_ALL=C sed "${CLI_FIELD_BATCH_SED_ESCAPE[@]}" 2>/dev/null \
        | LC_ALL=C sed "${CLI_FIELD_BATCH_SED_C1[@]}" 2>/dev/null \
        | LC_ALL=C tr -d '\n' 2>/dev/null
      printf '%s%s %s %s' "$CLI_FIELD_BATCH_TRAILER_PREFIX" "${PIPESTATUS[@]:1}"
    )"
    # 目印で値に分ける(目印は空白類ではないため、空の値も 1 件として残る)
    IFS="$CLI_FIELD_BATCH_RECORD_END"
  else
    batch_output="$(
      printf '%s\n' "$@" 2>/dev/null | LC_ALL=C sed "${CLI_FIELD_BATCH_SED_CONTROLS[@]}" 2>/dev/null
      printf '%s%s 0 0' "$CLI_FIELD_BATCH_TRAILER_PREFIX" "${PIPESTATUS[1]}"
    )"
    # 改行で値に分ける(空の値は無い。sed の出力の最後の改行の後ろに証跡が続く)
    IFS=$'\n'
  fi
  # shellcheck disable=SC2206  # 目印・改行での単語分割が目的
  cli_field_batch_target=($batch_output)
  # 値の個数 + 証跡の 1 件がそろい、全コマンドが成功したときだけ結果を使う
  if [ "${#cli_field_batch_target[@]}" -eq $((batch_count + 1)) ] \
    && [ "${cli_field_batch_target[batch_count]}" = "$CLI_FIELD_BATCH_OK_TRAILER" ]; then
    unset 'cli_field_batch_target[batch_count]'
    return 0
  fi
  # 失敗したコマンド名を、証跡の終了状態から決める(証跡は必ず出力の末尾にある。数十 MB の出力の全体は調べず、末尾だけを見る)
  cli_field_batch_target=()
  batch_trailer="$batch_output"
  if [ "${#batch_output}" -gt 32 ]; then
    batch_trailer="${batch_output: -32}"
  fi
  if [[ "$batch_trailer" =~ ${CLI_FIELD_BATCH_TRAILER_PREFIX}([0-9]+)\ ([0-9]+)\ ([0-9]+)$ ]]; then
    # 後ろのコマンドが読み切らずに終わると、書き込み先を失った前のコマンドも SIGPIPE や書き込みエラーで終わる
    # (前のコマンド自身の失敗と区別できない)。最も後ろで失敗したコマンドだけを、失敗したコマンドとして載せる
    if [ "${BASH_REMATCH[3]}" != 0 ]; then
      CLI_FIELD_BATCH_FAILED_COMMANDS="tr"
    elif [ "${BASH_REMATCH[1]}" != 0 ] || [ "${BASH_REMATCH[2]}" != 0 ]; then
      CLI_FIELD_BATCH_FAILED_COMMANDS="sed"
    fi
  fi
  if [ -z "$CLI_FIELD_BATCH_FAILED_COMMANDS" ]; then
    # 終了状態はどれも 0 なのに出力の件数が合わない・証跡が無い(どのコマンドで欠けたかは判別できない)
    if [ "$batch_needs_c1" = true ]; then
      CLI_FIELD_BATCH_FAILED_COMMANDS="sed,tr"
    else
      CLI_FIELD_BATCH_FAILED_COMMANDS="sed"
    fi
  fi
  return 1
}

# 制御文字を JSON の文字列と同じエスケープ表記へ置き換える。結果は CLI_FIELD_ESCAPED。
#   - 改行は `\n`、タブは `\t`(2 文字)。それ以外の制御文字(U+0001〜U+001F、U+007F、U+0080〜U+009F)は `\u00XX`(16 進小文字 4 桁)
#   - backslash_escaped_chars に渡した文字は、前にバックスラッシュを付ける(JSON の文字列なら `"` と `\`)
#   - それ以外のバイトは変えない(制御文字を含まない値は 1 バイトも変わらない)
# 引数: text [backslash_escaped_chars] [window_bytes(既定は CLI_FIELD_ESCAPE_WINDOW_BYTES)]
cli_field_escape_text() {
  # bash だけで置き換える(外部コマンドを起動しない)。処理時間を値の内容によらずバイト数に比例させる
  # (ただし制御文字の種類が多い値は 1 バイトあたり数マイクロ秒かかる。数 MB を表示する呼び出し元は cli_field_safe_text_list /
  # cli_field_safe_text_prepare でまとめて置き換える)。
  # 置き換える文字 1 つごとに未処理の残りを切り詰め直すと 1 文字あたり 20 マイクロ秒前後かかり、制御文字 128 個のキー 5,000 行で
  # 20 秒を超える。置き換えは窓ごとに cli_field_escape_chunk で行う(同じ文字の一括置き換えと、断片の連結)。
  # bash の文字列操作は文字列全体の長さに比例する時間がかかるため、長い値は窓ずつ処理する
  local text="$1" backslash_escaped="${2:-}" window="${3:-$CLI_FIELD_ESCAPE_WINDOW_BYTES}"
  local special controls="$CLI_FIELD_CONTROL_CHARS" escaped_chars="" index char chunk offset=0 total
  # バイト単位で処理する(ロケールに依存させない)。UTF-8 の多バイト文字の各バイトは 0x80 以上で、ASCII の制御文字と重ならない
  local LC_ALL=C
  special="$CLI_FIELD_CONTROL_CHARS$CLI_FIELD_C1_LEAD_BYTE$backslash_escaped"
  CLI_FIELD_ESCAPED=""
  # 置き換える文字が無い値(通常の値)はそのまま返す
  if [[ "$text" != *["$special"]* ]]; then
    CLI_FIELD_ESCAPED="$text"
    return 0
  fi
  # 断片への分割(cli_field_escape_chunk)は単語分割で行う。パス名展開はさせない(この関数と、ここから呼ぶ関数の中だけ)
  local -
  set -f
  # 前にバックスラッシュを付ける文字の並び。バックスラッシュ自身を最初に処理する(後から付けたバックスラッシュを二重にしない)。
  # 改行・タブ・0xC2 は可視表記の規則を優先する。それ以外の制御文字が指定されていれば、バックスラッシュを付ける側を優先する
  if [[ "$backslash_escaped" == *\\* ]]; then
    escaped_chars="\\"
  fi
  for ((index = 0; index < ${#backslash_escaped}; index++)); do
    char="${backslash_escaped:index:1}"
    case "$char" in
      \\ | $'\n' | $'\t' | "$CLI_FIELD_C1_LEAD_BYTE") ;;
      *)
        # 同じ文字が 2 回指定されていても、バックスラッシュは 1 つだけ付ける
        if [[ "$escaped_chars" != *"$char"* ]]; then
          escaped_chars+="$char"
          controls="${controls//"$char"/}"
        fi
        ;;
    esac
  done
  total="${#text}"
  while [ "$offset" -lt "$total" ]; do
    chunk="${text:offset:window}"
    offset=$((offset + window))
    # 窓の最後の 1 バイトが 0xC2 のときは、次の 1 バイトも取り込んでから C1 制御文字かどうかを決める
    # (取り込んだ 1 バイトがまた 0xC2 なら、その次も取り込む)
    while [ "${chunk: -1}" = "$CLI_FIELD_C1_LEAD_BYTE" ] && [ "$offset" -lt "$total" ]; do
      chunk+="${text:offset:1}"
      offset=$((offset + 1))
    done
    if [[ "$chunk" == *["$special"]* ]]; then
      cli_field_escape_chunk "$chunk" "$escaped_chars" "$controls"
      CLI_FIELD_ESCAPED+="$CLI_FIELD_ESCAPED_CHUNK"
    else
      CLI_FIELD_ESCAPED+="$chunk"
    fi
  done
}

# cli_field_escape_chunk の結果
CLI_FIELD_ESCAPED_CHUNK=""
# 同じ制御文字が 1 窓にこの個数以上あれば、その文字を一括で置き換える(未満なら断片の連結で置き換える)。
# 結果には影響しない(処理時間だけに効く。一括の置き換えは窓の長さに比例する 1 回の処理、連結は 1 個ごとの処理)
CLI_FIELD_ESCAPE_BULK_MIN_COUNT=4
# 1 窓の 1 バイトの制御文字の合計がこの個数以上のときだけ、種類ごとの個数を数える(未満ならすべて断片の連結で置き換える)。
# 結果には影響しない(数える処理は種類の数に比例するため、少ない窓では連結だけのほうが速い)
CLI_FIELD_ESCAPE_COUNT_MIN_TOTAL=64

# cli_field_escape_text の 1 窓分の置き換え。結果は CLI_FIELD_ESCAPED_CHUNK。
# 呼び出し元が LC_ALL=C と set -f にしておくこと。
# どの入力でも、シェルの処理の回数が「窓のバイト数に比例する回数」を超えないようにする:
#   - 同じ文字が多い場合(ESC が 100 個など): その文字を 1 回の処理で一括して置き換える(個数によらない)
#   - それ以外: 窓を「置き換える文字で区切った断片」と「置き換える文字の並び」に分け、断片と表引きの結果を順に連結する
#     (1 個につき連結 1 回。未処理の残りを切り詰め直したり、種類ごとに窓全体を処理し直したりしない)
# 置き換え後の文字列(`\n` / `\t` / `\u00XX` / `\<文字>`)には置き換え対象の文字が現れないため、置き換えた結果を再び置き換えることはない
# (バックスラッシュだけは例外のため、最初に処理する)。
# 置き換え後の文字列は引用符で囲んで渡す(bash 5.2 以降は、囲まない置き換え文字列の `&` を一致部分として展開する)
# 引数: chunk escaped_chars(前にバックスラッシュを付ける文字。バックスラッシュが先頭) controls(可視表記にする 1 バイトの制御文字)
cli_field_escape_chunk() {
  local chunk="$1" escaped_chars="$2" controls="$3"
  local index char rest delims="" joined_chars="" marked joined count
  local bulk_min_count="$CLI_FIELD_ESCAPE_BULK_MIN_COUNT" count_min_total="$CLI_FIELD_ESCAPE_COUNT_MIN_TOTAL"
  local -a parts=()
  # 区切りの文字そのものが「前にバックスラッシュを付ける文字」に指定されていると、生のまま窓に残り断片へ分けられない。
  # その場合は断片の連結を使わず、すべて一括で置き換える(JSON の文字列の `"` と `\` では起きない)
  if [[ "$escaped_chars" == *"$CLI_FIELD_ESCAPE_SEPARATOR"* ]]; then
    bulk_min_count=1
    count_min_total=0
  fi
  for ((index = 0; index < ${#escaped_chars}; index++)); do
    char="${escaped_chars:index:1}"
    if [[ "$chunk" == *"$char"* ]]; then
      chunk=${chunk//"$char"/"\\$char"}
    fi
  done
  # C1 制御文字(0xC2 + 0x80〜0x9F): 窓に 1 つでもあれば、32 種類を順に一括で置き換える(個数にも種類の数にもよらず 32 回。
  # 窓が短いうちに、1 バイトの制御文字より先に処理する)。
  # 0xC2 で始まる通常の 2 バイト文字(U+00A0〜U+00BF)と、UTF-8 として不正な並びの 0xC2 はバイトを変えない
  if [[ "$chunk" == *"$CLI_FIELD_C1_LEAD_BYTE"["$CLI_FIELD_C1_TRAIL_BYTES"]* ]]; then
    for index in "${!CLI_FIELD_C1_SEQUENCES[@]}"; do
      chunk=${chunk//"${CLI_FIELD_C1_SEQUENCES[index]}"/"${CLI_FIELD_C1_ESCAPES[index]}"}
    done
  fi
  # 1 バイトの制御文字(U+0001〜U+001F、U+007F)。窓に現れた制御文字の並び(現れた順)を取り出す
  if [ -n "$controls" ]; then
    delims=${chunk//[!"$controls"]/}
  fi
  if [ "${#delims}" -lt "$count_min_total" ]; then
    # 制御文字が少ない窓は、数えずにすべて断片の連結で置き換える(数える処理のほうが高くつく)
    joined_chars="$delims"
  else
    # 種類ごとの個数を数え、多い種類を一括で置き換える
    while [ -n "$delims" ]; do
      char="${delims:0:1}"
      rest=${delims//"$char"/}
      if [ $((${#delims} - ${#rest})) -ge "$bulk_min_count" ]; then
        chunk=${chunk//"$char"/"${CLI_FIELD_ESCAPE_TABLE["k$char"]}"}
      else
        joined_chars+="$char"
      fi
      delims="$rest"
    done
  fi
  if [ -n "$joined_chars" ]; then
    # 断片の連結。置き換える文字をすべて区切りに変えてから、区切りで断片に分ける(区切りは U+001F。置き換える文字の 1 つで、
    # ここまでに一括で置き換え済みか、ここで区切りに変わるかのどちらかなので、元の値の U+001F と混ざらない)。
    # parts[i] は i 番目の置き換える文字の直前の断片(末尾の空の断片は配列に入らないため、未設定を空として扱う)
    local IFS="$CLI_FIELD_ESCAPE_SEPARATOR"
    delims=${chunk//[!"$joined_chars"]/}
    marked=${chunk//["$joined_chars"]/"$CLI_FIELD_ESCAPE_SEPARATOR"}
    # shellcheck disable=SC2206  # 区切りでの単語分割が目的(パス名展開は呼び出し元が set -f で止めている)
    parts=($marked)
    count="${#delims}"
    joined=""
    for ((index = 0; index < count; index++)); do
      joined+=${parts[index]-}${CLI_FIELD_ESCAPE_TABLE["k${delims:index:1}"]}
    done
    chunk="$joined${parts[count]-}"
  fi
  CLI_FIELD_ESCAPED_CHUNK="$chunk"
}

# 可視表記の結果の控え(添字は `k` + 元の値)。同じ値を 2 回以上表示するとき、置き換えを繰り返さない
# (列挙外の mode の値は error 行 2 つに出る。slot ジョブマップの job_id は行ごとの複数の error 行に出る)。
# 載せるのは次の 2 通り:
#   - cli_field_safe_text が置き換えた、CLI_FIELD_SAFE_CACHE_MAX_BYTES 以下の値(長い値は繰り返し表示しない前提で、メモリを使わない)
#   - cli_field_safe_text_prepare がまとめて置き換えた値(大きさによらない。置き換える文字の無い値も、要否の判定を繰り返さないために載せる)
# 控えの合計(元の値と可視表記のバイト数の和)が CLI_FIELD_SAFE_CACHE_MAX_TOTAL_BYTES を超える分は載せない
# (入力の大きさに上限は無いため、メモリの使用量を入力の大きさに比例させない。載せなかった値は表示のたびに置き換える)。
# 合計の上限は、性能目標の上限の大きさ(8 MB)の値 1 つとその可視表記(最大 6 倍)が収まる大きさ
declare -gA CLI_FIELD_SAFE_CACHE=()
CLI_FIELD_SAFE_CACHE_MAX_BYTES=1024
CLI_FIELD_SAFE_CACHE_MAX_TOTAL_BYTES=$((64 * 1024 * 1024))
CLI_FIELD_SAFE_CACHE_TOTAL_BYTES=0

# 値と可視表記を控えに載せる(合計の上限を超える分は載せない)。呼び出し元が LC_ALL=C にしておくこと(バイト数で数える)
# 引数: text shown
cli_field_safe_cache_store() {
  local total=$((CLI_FIELD_SAFE_CACHE_TOTAL_BYTES + ${#1} + ${#2}))
  if [ "$total" -le "$CLI_FIELD_SAFE_CACHE_MAX_TOTAL_BYTES" ]; then
    CLI_FIELD_SAFE_CACHE["k$1"]="$2"
    CLI_FIELD_SAFE_CACHE_TOTAL_BYTES="$total"
  fi
}

# 任意入力の値を表示用の文字列にする(制御文字を可視表記へ置き換える)。結果は CLI_FIELD_SAFE_TEXT。
# バックスラッシュは置き換えない(制御文字を含まない値の表示を変えないため)。外部コマンドは起動しない。
# 値は数 MB になりうるため、変数へ写さずに引数のまま使う(1 回写すたびに値の長さに比例する時間がかかる)
# 引数: text
cli_field_safe_text() {
  # バイト単位で判定する。LC_ALL の設定は setlocale を伴い関数呼び出しより重いため、呼び出し元が C にしていれば設定しない
  if [ "${LC_ALL:-}" != C ]; then
    local LC_ALL=C
  fi
  if [ $# -eq 0 ]; then
    set -- ""
  fi
  # 控えにある値(まとめて置き換えた値を含む)はそれを返す。控えが空のうちは調べない(行数に比例して呼ばれるため)
  if [ "${#CLI_FIELD_SAFE_CACHE[@]}" -gt 0 ] && [ -n "${CLI_FIELD_SAFE_CACHE["k$1"]+x}" ]; then
    CLI_FIELD_SAFE_TEXT="${CLI_FIELD_SAFE_CACHE["k$1"]}"
    return 0
  fi
  # 置き換える文字が無い値(通常の値)はそのまま返す
  if [[ "$1" != *["$CLI_FIELD_SAFE_SPECIAL_CHARS"]* ]]; then
    CLI_FIELD_SAFE_TEXT="$1"
    return 0
  fi
  cli_field_escape_text "$1"
  CLI_FIELD_SAFE_TEXT="$CLI_FIELD_ESCAPED"
  if [ "${#1}" -le "$CLI_FIELD_SAFE_CACHE_MAX_BYTES" ]; then
    cli_field_safe_cache_store "$1" "$CLI_FIELD_ESCAPED"
  fi
}

# この後に cli_field_safe_text で表示する値を、まとめて可視表記にして控えに載せる(大きな値の置き換えを bash で行わないため)。
# 控えにある値は除く。残りの合計が CLI_FIELD_ESCAPE_EXTERNAL_MIN_BYTES 未満なら何もしない(表示のときに bash で置き換える)。
# サブシェルの中で載せた控えは親へ戻らないため、サブシェルで表示する値も、親で先に呼んでおく。
# 引数: text...
# 戻り値: 0 … 載せた・何もしなかった / 1 … 外部コマンドが失敗した(控えは変えていない。CLI_FIELD_BATCH_FAILED_COMMANDS に名前)
cli_field_safe_text_prepare() {
  local prepare_text prepare_total=0 prepare_index
  local -a prepare_values=() prepare_shown=()
  # 引数に同じ値が 2 回以上あっても 1 回だけ置き換える(添字は控えと同じく `k` + 値)
  local -A prepare_seen=()
  if [ "${LC_ALL:-}" != C ]; then
    local LC_ALL=C
  fi
  for prepare_text in "$@"; do
    if [ -z "$prepare_text" ] || [ -n "${CLI_FIELD_SAFE_CACHE["k$prepare_text"]+x}" ] \
      || [ -n "${prepare_seen["k$prepare_text"]+x}" ]; then
      continue
    fi
    prepare_seen["k$prepare_text"]=1
    prepare_values+=("$prepare_text")
    prepare_total=$((prepare_total + ${#prepare_text}))
  done
  if [ "$prepare_total" -lt "$CLI_FIELD_ESCAPE_EXTERNAL_MIN_BYTES" ]; then
    return 0
  fi
  if ! cli_field_escape_batch prepare_shown "${prepare_values[@]}"; then
    return 1
  fi
  # 控えへ直接載せる(cli_field_safe_cache_store と同じ規則。関数の引数に渡すと、数十 MB の可視表記をもう 1 回写すことになる)
  for prepare_index in "${!prepare_values[@]}"; do
    prepare_total=$((CLI_FIELD_SAFE_CACHE_TOTAL_BYTES + ${#prepare_values[prepare_index]} + ${#prepare_shown[prepare_index]}))
    if [ "$prepare_total" -le "$CLI_FIELD_SAFE_CACHE_MAX_TOTAL_BYTES" ]; then
      CLI_FIELD_SAFE_CACHE["k${prepare_values[prepare_index]}"]="${prepare_shown[prepare_index]}"
      CLI_FIELD_SAFE_CACHE_TOTAL_BYTES="$prepare_total"
    fi
  done
  return 0
}

# 多数の値をまとめて表示用の文字列にし、呼び出し元の配列に同じ並びで載せる(値ごとの結果は cli_field_safe_text と同じ)。
# 行数に比例する個数の値(キー名など)を表示する呼び出し元が使う: 値の合計が CLI_FIELD_ESCAPE_EXTERNAL_MIN_BYTES 以上なら、
# 値の個数によらず一定回数の外部コマンドで置き換える。合計が小さいときは、値ごとに bash で置き換える(外部コマンドを起動しない)。
# 引数: target_name(結果を載せる配列の名前。cli_field_ / batch_ / list_ で始まる名前以外) text...
# 戻り値: 0 … 載せた / 1 … 外部コマンドが失敗した(結果は空。CLI_FIELD_BATCH_FAILED_COMMANDS に名前。
#         呼び出し元は補助コマンドの失敗として扱うか、値ごとの cli_field_safe_text で置き換え直す)
cli_field_safe_text_list() {
  local cli_field_list_target_name="$1" list_text list_total=0
  local -n cli_field_list_target="$1"
  shift
  if [ "${LC_ALL:-}" != C ]; then
    local LC_ALL=C
  fi
  for list_text in "$@"; do
    list_total=$((list_total + ${#list_text}))
    if [ "$list_total" -ge "$CLI_FIELD_ESCAPE_EXTERNAL_MIN_BYTES" ]; then
      break
    fi
  done
  if [ "$list_total" -ge "$CLI_FIELD_ESCAPE_EXTERNAL_MIN_BYTES" ]; then
    cli_field_escape_batch "$cli_field_list_target_name" "$@"
    return
  fi
  cli_field_list_target=()
  for list_text in "$@"; do
    cli_field_safe_text "$list_text"
    cli_field_list_target+=("$CLI_FIELD_SAFE_TEXT")
  done
}

# 値の可視表記を、改行を付けずに stdout へ出す(cli_field_safe_text の結果と同じバイト列)。
# 控えにある値は、控えから直接出す(数十 MB になりうる可視表記を変数へ写さない。1 回写すたびに長さに比例する時間がかかる)
# 引数: text
cli_field_print_safe_text() {
  if [ "${LC_ALL:-}" != C ]; then
    local LC_ALL=C
  fi
  if [ $# -eq 0 ]; then
    set -- ""
  fi
  if [ "${#CLI_FIELD_SAFE_CACHE[@]}" -gt 0 ] && [ -n "${CLI_FIELD_SAFE_CACHE["k$1"]+x}" ]; then
    printf '%s' "${CLI_FIELD_SAFE_CACHE["k$1"]}"
    return 0
  fi
  cli_field_safe_text "$1"
  printf '%s' "$CLI_FIELD_SAFE_TEXT"
}

# 値が空なら空値表記 `-` に置き換える(表示用。制御文字は可視表記にする)
cli_field_display_value() {
  if [ -n "${1:-}" ]; then
    cli_field_print_safe_text "$1"
    printf '\n'
  else
    printf '%s\n' "$CLI_FIELD_EMPTY_VALUE"
  fi
}

# `key=value` / `key: value` の選択に使う「空白」: ASCII の空白文字(半角空白・タブ・LF・VT・FF・CR。C ロケールの [[:space:]] と同じ集合)。
# 契約は空白を定義しないが、他の箇所では「半角空白」「空白だけの行(半角空白・タブだけ)」「空白区切り」と ASCII の意味で使い、
# 制御文字の規則もバイト単位で定める。Unicode の空白(U+2003 等)は空白として扱わない: `[[:space:]]` に任せると UTF-8 ロケールでだけ
# 一致して出力形式が環境で変わり、Unicode 空白の集合自体も libc(glibc / macOS)で異なるため、ロケールに関係なく同じ結果にできない
CLI_FIELD_SPACE_CHARS=$' \t\n\v\f\r'

# 値に空白(CLI_FIELD_SPACE_CHARS)を含むか。バイト単位で判定する(ロケールに依存させない)
cli_field_value_has_space() {
  if [ "${LC_ALL:-}" != C ]; then
    local LC_ALL=C
  fi
  [[ "$1" == *["$CLI_FIELD_SPACE_CHARS"]* ]]
}

# 汎用フィールド 1 行: 空白を含まない値は `key=value`、含む値は `key: value`
# (形式は元の値で決める。表示する値は制御文字を可視表記にしたもの)。
# 値は数 MB になりうるため、変数へ写さずに引数のまま使い、キー・値・改行を順に出す
# 引数: key value
cli_field_line() {
  if [ -z "${2:-}" ]; then
    printf '%s=%s\n' "$1" "$CLI_FIELD_EMPTY_VALUE"
    return 0
  fi
  if cli_field_value_has_space "$2"; then
    printf '%s: ' "$1"
  else
    printf '%s=' "$1"
  fi
  cli_field_print_safe_text "$2"
  printf '\n'
}

# パス値のフィールド 1 行: 常に `key: value`(空値 `-` でも `key: -`。tier-facade.md 出力契約の例に従う)
# 引数: key value
cli_path_field_line() {
  if [ -z "${2:-}" ]; then
    printf '%s: %s\n' "$1" "$CLI_FIELD_EMPTY_VALUE"
    return 0
  fi
  printf '%s: ' "$1"
  cli_field_print_safe_text "$2"
  printf '\n'
}
