#!/usr/bin/env bash
# domain: CLI 出力フィールド(stdout の「1 行 1 事実」の表現)。
# 仕様: _cross-cutting/ux-ui/ui-design.md「出力フォーマット」/ cli-command-contract.yaml conventions.output_format.stdout
#   - `key=value`(値に空白を含まない)/ `key: value`(値に空白・パスを含む。`:` の後に半角空白 1 つ)
#   - 空値は `key=` ではなく `key=-`
# 任意文字列の値(実装版など)を扱うため、出力は必ず printf の固定フォーマットで行う
# (echo は `-n` / `-e` などの値をオプションとして解釈してしまう)。
# この層は I/O を持たない(標準出力へ書くだけ。呼び出し元が振り分ける)。

# 空値の表記(ui-design.md 出力フォーマット「空値」)
CLI_FIELD_EMPTY_VALUE="-"

# 値が空なら空値表記 `-` に置き換える
cli_field_display_value() {
  if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$CLI_FIELD_EMPTY_VALUE"
  fi
}

# 値に空白(半角空白・タブ等の [[:space:]])を含むか
cli_field_value_has_space() {
  [[ "$1" == *[[:space:]]* ]]
}

# 汎用フィールド 1 行: 空白を含まない値は `key=value`、含む値は `key: value`
# 引数: key value
cli_field_line() {
  local key="$1" value="${2:-}"
  if [ -z "$value" ]; then
    value="$CLI_FIELD_EMPTY_VALUE"
  fi
  if cli_field_value_has_space "$value"; then
    printf '%s: %s\n' "$key" "$value"
  else
    printf '%s=%s\n' "$key" "$value"
  fi
}

# パス値のフィールド 1 行: 常に `key: value`(空値 `-` でも `key: -`。tier-facade.md 出力契約の例に従う)
# 引数: key value
cli_path_field_line() {
  local key="$1" value="${2:-}"
  if [ -z "$value" ]; then
    value="$CLI_FIELD_EMPTY_VALUE"
  fi
  printf '%s: %s\n' "$key" "$value"
}
