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
CLI_FIELD_C1_TRAIL_FIRST=$'\x80'
CLI_FIELD_C1_TRAIL_LAST=$'\x9f'
# cli_field_escape_text が 1 回に取り込む窓の大きさ(バイト)。結果には影響しない(長い値の処理時間だけに効く)
CLI_FIELD_ESCAPE_WINDOW_BYTES=1024
# 表示のときに置き換えが要る文字の集合(cli_field_safe_text の早期判定用。制御文字と C1 制御文字の先頭バイト)
CLI_FIELD_SAFE_SPECIAL_CHARS="$CLI_FIELD_CONTROL_CHARS$CLI_FIELD_C1_LEAD_BYTE"

# cli_field_escape_text の結果
CLI_FIELD_ESCAPED=""
# cli_field_safe_text の結果
CLI_FIELD_SAFE_TEXT=""

# 制御文字を JSON の文字列と同じエスケープ表記へ置き換える。結果は CLI_FIELD_ESCAPED。
#   - 改行は `\n`、タブは `\t`(2 文字)。それ以外の制御文字(U+0001〜U+001F、U+007F、U+0080〜U+009F)は `\u00XX`(16 進小文字 4 桁)
#   - backslash_escaped_chars に渡した文字は、前にバックスラッシュを付ける(JSON の文字列なら `"` と `\`)
#   - それ以外のバイトは変えない(制御文字を含まない値は 1 バイトも変わらない)
# 引数: text [backslash_escaped_chars] [window_bytes(既定は CLI_FIELD_ESCAPE_WINDOW_BYTES)]
cli_field_escape_text() {
  # bash の文字列操作は文字列全体の長さに比例する時間がかかるため、1 文字ずつ添字で取り出すと
  # 長さの 2 乗の時間がかかる。窓ずつ rest(未処理の窓)へ取り込み、置き換えの要らない連続した文字はまとめて取り込む
  local text="$1" backslash_escaped="${2:-}" window="${3:-$CLI_FIELD_ESCAPE_WINDOW_BYTES}"
  local special rest="" offset=0 total run char next number code
  # バイト単位で処理する(ロケールに依存させない)。UTF-8 の多バイト文字の各バイトは 0x80 以上で、ASCII の制御文字と重ならない
  local LC_ALL=C
  special="$backslash_escaped$CLI_FIELD_CONTROL_CHARS$CLI_FIELD_C1_LEAD_BYTE"
  CLI_FIELD_ESCAPED=""
  # 置き換える文字が無い値(通常の値)はそのまま返す
  if [[ "$text" != *["$special"]* ]]; then
    CLI_FIELD_ESCAPED="$text"
    return 0
  fi
  total="${#text}"
  while [ -n "$rest" ] || [ "$offset" -lt "$total" ]; do
    # C1 制御文字の判定に 2 バイト要るため、窓が 2 バイト未満になったら続きを取り込む
    if [ "${#rest}" -lt 2 ] && [ "$offset" -lt "$total" ]; then
      rest+="${text:offset:window}"
      offset=$((offset + window))
    fi
    run="${rest%%["$special"]*}"
    CLI_FIELD_ESCAPED+="$run"
    rest="${rest:${#run}}"
    # 窓の最後の 1 バイトが 0xC2 のときは、続きを取り込んでから C1 制御文字かどうかを決める
    if [ "$rest" = "$CLI_FIELD_C1_LEAD_BYTE" ] && [ "$offset" -lt "$total" ]; then
      continue
    fi
    char="${rest:0:1}"
    rest="${rest:1}"
    case "$char" in
      "") ;;
      "$CLI_FIELD_C1_LEAD_BYTE")
        next="${rest:0:1}"
        if [[ -n "$next" && ! "$next" < "$CLI_FIELD_C1_TRAIL_FIRST" && ! "$next" > "$CLI_FIELD_C1_TRAIL_LAST" ]]; then
          # C1 制御文字の符号位置は 2 バイト目の値と同じ(符号拡張された値を返す環境に備えて下位 8 ビットだけ使う)
          printf -v number '%d' "'$next"
          printf -v code '%04x' "$((number & 255))"
          CLI_FIELD_ESCAPED+="\\u$code"
          rest="${rest:1}"
        else
          # 0xC2 で始まる通常の 2 バイト文字(U+00A0〜U+00BF)、または UTF-8 として不正な並び。バイトを変えない
          CLI_FIELD_ESCAPED+="$char"
        fi
        ;;
      $'\n') CLI_FIELD_ESCAPED+="\\n" ;;
      $'\t') CLI_FIELD_ESCAPED+="\\t" ;;
      *)
        if [ -n "$backslash_escaped" ] && [[ "$backslash_escaped" == *"$char"* ]]; then
          CLI_FIELD_ESCAPED+="\\$char"
        else
          # 残りは 1 バイトの制御文字(U+0001〜U+001F、U+007F)だけ
          printf -v code '%04x' "'$char"
          CLI_FIELD_ESCAPED+="\\u$code"
        fi
        ;;
    esac
  done
}

# 任意入力の値を表示用の文字列にする(制御文字を可視表記へ置き換える)。結果は CLI_FIELD_SAFE_TEXT。
# バックスラッシュは置き換えない(制御文字を含まない値の表示を変えないため)。
# 引数: text
cli_field_safe_text() {
  # 置き換える文字が無い値(通常の値)はそのまま返す(行数に比例して呼ばれるため、関数呼び出しを重ねない)
  local LC_ALL=C
  if [[ "${1:-}" != *["$CLI_FIELD_SAFE_SPECIAL_CHARS"]* ]]; then
    CLI_FIELD_SAFE_TEXT="${1:-}"
    return 0
  fi
  cli_field_escape_text "${1:-}"
  CLI_FIELD_SAFE_TEXT="$CLI_FIELD_ESCAPED"
}

# 値が空なら空値表記 `-` に置き換える(表示用。制御文字は可視表記にする)
cli_field_display_value() {
  if [ -n "${1:-}" ]; then
    cli_field_safe_text "$1"
    printf '%s\n' "$CLI_FIELD_SAFE_TEXT"
  else
    printf '%s\n' "$CLI_FIELD_EMPTY_VALUE"
  fi
}

# 値に空白(半角空白・タブ等の [[:space:]])を含むか
cli_field_value_has_space() {
  [[ "$1" == *[[:space:]]* ]]
}

# 汎用フィールド 1 行: 空白を含まない値は `key=value`、含む値は `key: value`
# (形式は元の値で決める。表示する値は制御文字を可視表記にしたもの)
# 引数: key value
cli_field_line() {
  local key="$1" value="${2:-}"
  if [ -z "$value" ]; then
    value="$CLI_FIELD_EMPTY_VALUE"
  fi
  cli_field_safe_text "$value"
  if cli_field_value_has_space "$value"; then
    printf '%s: %s\n' "$key" "$CLI_FIELD_SAFE_TEXT"
  else
    printf '%s=%s\n' "$key" "$CLI_FIELD_SAFE_TEXT"
  fi
}

# パス値のフィールド 1 行: 常に `key: value`(空値 `-` でも `key: -`。tier-facade.md 出力契約の例に従う)
# 引数: key value
cli_path_field_line() {
  local key="$1" value="${2:-}"
  if [ -z "$value" ]; then
    value="$CLI_FIELD_EMPTY_VALUE"
  fi
  cli_field_safe_text "$value"
  printf '%s: %s\n' "$key" "$CLI_FIELD_SAFE_TEXT"
}
