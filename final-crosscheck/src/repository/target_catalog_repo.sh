#!/usr/bin/env bash
# repository: TargetCatalogRecord(対象カタログ CSV の読み込み)。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-final-crosscheck.md
#       「設定契約(対象カタログ)」形式(slot ジョブマップと同じ CSV。1 行目ヘッダー、`#` コメント、セルのクォート規則)
#       spec.md E2E「同じ CSV 形式である(SPEC-004-04)」Then: slot ジョブマップの読み込みと同じ CSV クォート解析関数が使われる
#       _cross-cutting/api/cli-command-contract.yaml config_input_rules(rules / snapshot / internal_failure)
# CSV の解析(入力の複製・バイト点検・クォート解析)は自前で持たず、slot ジョブマップの読み込み関数 job_map_repo_load
# (tier-facade の facade/src/repository/job_map_repo.sh。validate-config.sh のエントリポイントが先に source する)をそのまま使う。
# この関数共有は契約 contracts[] に無い tier 間依存であり、扱いは
# docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md に従う(暫定の依存。
# 契約として宣言されるまで本ファイル以外から facade の読み込み関数を参照しない)。
# この層は検証しない(列の意味・必須・値域は domain/target_catalog.sh の検証表)。メッセージも出さない。
# 読み込み結果(グローバル。job_map_repo_load の結果を対象カタログの名前に写す):
#   TARGET_CATALOG_PATH              … 読み込んだファイルパス(引数どおり)
#   TARGET_CATALOG_HEADER_LINE       … ヘッダー行の行番号(ヘッダー行が無ければ 0)
#   TARGET_CATALOG_HEADER_STATUS     … ヘッダー行の解析結果(ok | quote_invalid | malformed | missing)
#   TARGET_CATALOG_HEADER            … ヘッダー行のセル(列名)
#   TARGET_CATALOG_ROW_LINES         … データ行ごとの物理行番号
#   TARGET_CATALOG_ROW_STATUSES      … データ行ごとの解析結果(ok | quote_invalid | malformed)
#   TARGET_CATALOG_ROW_OFFSETS       … データ行ごとの TARGET_CATALOG_CELLS 内の開始位置
#   TARGET_CATALOG_ROW_CELL_COUNTS   … データ行ごとのセル数(quote_invalid / malformed の行は 0)
#   TARGET_CATALOG_CELLS             … 全データ行のセルを行順に連結した配列
#   TARGET_CATALOG_NUL_LINES / TARGET_CATALOG_ENCODING_LINES / TARGET_CATALOG_CR_LINES / TARGET_CATALOG_BOM_LINE /
#   TARGET_CATALOG_MALFORMED_LINES   … 入力の守備範囲の違反(原因ごとの行番号。job_map_repo_load と同じ意味)
#   TARGET_CATALOG_REPO_FAILED_COMMANDS … 補助コマンドの失敗時に、失敗したコマンド名(カンマ区切り)
# 戻り値: target_catalog_repo_load は 0(読み込み完了)/ TARGET_CATALOG_REPO_STATUS_SNAPSHOT_FAILED(入力の複製の失敗)/
#         TARGET_CATALOG_REPO_STATUS_COMMAND_FAILED(複製完了後の補助コマンドの失敗・想定外の出力。
#         共有の読み込み関数が無い環境もここに含める)

# 解析結果の値(usecase が読む。このファイル内では参照しない)
# shellcheck disable=SC2034
TARGET_CATALOG_PARSE_OK="ok"
# shellcheck disable=SC2034
TARGET_CATALOG_PARSE_QUOTE_INVALID="quote_invalid"
# shellcheck disable=SC2034
TARGET_CATALOG_PARSE_MALFORMED="malformed"
TARGET_CATALOG_HEADER_MISSING="missing"
# 値は conventions.exit_codes の実行エラーと同じ(job_map_repo_load の戻り値と同じ区分。usecase が読む)
TARGET_CATALOG_REPO_STATUS_COMMAND_FAILED=6
# shellcheck disable=SC2034
TARGET_CATALOG_REPO_STATUS_SNAPSHOT_FAILED=7
# 共有の読み込み関数(slot ジョブマップの読み込み)の名前
TARGET_CATALOG_REPO_SHARED_LOADER="job_map_repo_load"

target_catalog_repo_reset() {
  TARGET_CATALOG_PATH=""
  TARGET_CATALOG_HEADER_LINE=0
  TARGET_CATALOG_HEADER_STATUS="$TARGET_CATALOG_HEADER_MISSING"
  TARGET_CATALOG_HEADER=()
  TARGET_CATALOG_ROW_LINES=()
  TARGET_CATALOG_ROW_STATUSES=()
  TARGET_CATALOG_ROW_OFFSETS=()
  TARGET_CATALOG_ROW_CELL_COUNTS=()
  TARGET_CATALOG_CELLS=()
  TARGET_CATALOG_NUL_LINES=()
  TARGET_CATALOG_ENCODING_LINES=()
  TARGET_CATALOG_CR_LINES=()
  TARGET_CATALOG_BOM_LINE=0
  TARGET_CATALOG_MALFORMED_LINES=()
  TARGET_CATALOG_REPO_FAILED_COMMANDS=""
}

# 対象カタログ CSV を読み込み、ヘッダーとデータ行をグローバルに載せる。
# 引数: path(存在・可読性の確認は呼び出し元 usecase の責務)
# shellcheck disable=SC2034
target_catalog_repo_load() {
  local path="$1" status=0
  target_catalog_repo_reset
  TARGET_CATALOG_PATH="$path"
  # 共有の読み込み関数が source されていない(validate-config.sh 以外から単独で呼ばれた)環境は、検証を続けず内部障害として返す
  if ! declare -F "$TARGET_CATALOG_REPO_SHARED_LOADER" >/dev/null; then
    TARGET_CATALOG_REPO_FAILED_COMMANDS="$TARGET_CATALOG_REPO_SHARED_LOADER"
    return "$TARGET_CATALOG_REPO_STATUS_COMMAND_FAILED"
  fi
  "$TARGET_CATALOG_REPO_SHARED_LOADER" "$path" || status=$?
  TARGET_CATALOG_REPO_FAILED_COMMANDS="$JOB_MAP_REPO_FAILED_COMMANDS"
  if [ "$status" -ne 0 ]; then
    return "$status"
  fi
  # 読み込み結果を対象カタログの名前に写す(配列の複製は行数に比例する時間)
  TARGET_CATALOG_HEADER_LINE="$JOB_MAP_HEADER_LINE"
  TARGET_CATALOG_HEADER_STATUS="$JOB_MAP_HEADER_STATUS"
  TARGET_CATALOG_HEADER=(${JOB_MAP_HEADER[@]+"${JOB_MAP_HEADER[@]}"})
  TARGET_CATALOG_ROW_LINES=(${JOB_MAP_ROW_LINES[@]+"${JOB_MAP_ROW_LINES[@]}"})
  TARGET_CATALOG_ROW_STATUSES=(${JOB_MAP_ROW_STATUSES[@]+"${JOB_MAP_ROW_STATUSES[@]}"})
  TARGET_CATALOG_ROW_OFFSETS=(${JOB_MAP_ROW_OFFSETS[@]+"${JOB_MAP_ROW_OFFSETS[@]}"})
  TARGET_CATALOG_ROW_CELL_COUNTS=(${JOB_MAP_ROW_CELL_COUNTS[@]+"${JOB_MAP_ROW_CELL_COUNTS[@]}"})
  TARGET_CATALOG_CELLS=(${JOB_MAP_CELLS[@]+"${JOB_MAP_CELLS[@]}"})
  TARGET_CATALOG_NUL_LINES=(${JOB_MAP_NUL_LINES[@]+"${JOB_MAP_NUL_LINES[@]}"})
  TARGET_CATALOG_ENCODING_LINES=(${JOB_MAP_ENCODING_LINES[@]+"${JOB_MAP_ENCODING_LINES[@]}"})
  TARGET_CATALOG_CR_LINES=(${JOB_MAP_CR_LINES[@]+"${JOB_MAP_CR_LINES[@]}"})
  TARGET_CATALOG_BOM_LINE="$JOB_MAP_BOM_LINE"
  TARGET_CATALOG_MALFORMED_LINES=(${JOB_MAP_MALFORMED_LINES[@]+"${JOB_MAP_MALFORMED_LINES[@]}"})
  return 0
}

# データ行数(コメント・空行・ヘッダー行を除く。計算ルール「行数集計」)
target_catalog_repo_row_count() {
  printf '%s\n' "${#TARGET_CATALOG_ROW_LINES[@]}"
}
