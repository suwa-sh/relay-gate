#!/usr/bin/env bash
# repository: CrosscheckJobMapRecord(クロスチェックジョブマップ CSV の読み込みと、対象カタログ参照の解決)。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-rapid-crosscheck.md
#       「設定契約(クロスチェックジョブマップ)」宣言(コメント行)/ spec.md「計算ルール一覧」対象カタログ参照の解決
#       _cross-cutting/api/cli-command-contract.yaml config_input_rules(snapshot / internal_failure)
# CSV の解析(単一スナップショット・バイト点検・ヘッダーとデータ行のクォート解析)は slot ジョブマップの読み込みと
# 同じ関数(facade/src/repository/job_map_repo.sh の job_map_repo_*)を使う(spec.md SPEC-004-04 Then「同じ CSV クォート解析関数」)。
# 契約未宣言の tier 間依存であり、validate-config.sh 経由の実行時は tier-facade が先に source 済み。
# 根拠: docs/impl/latest/dcd8234d/issues/20261010_084142_facade-dispatch-and-csv-parser-outside-tiers.md
# 本ファイルが加えるのは、同じスナップショットからの宣言(コメント行 `# name=value`)の取り出しと、対象カタログの版の有無の解決。
# この層は検証しない(宣言の必須・値は domain / usecase)。メッセージも出さない。
# 読み込み結果(グローバル。CSV 部分は job_map_repo の JOB_MAP_* をそのまま読む):
#   CROSSCHECK_JOB_MAP_DECL_NAMES   … 宣言の名前(ファイル内の出現順。同じ名前が複数回あれば複数回)
#   CROSSCHECK_JOB_MAP_DECL_VALUES  … 宣言の値(`=` より右。前後の空白は除かない)
#   CROSSCHECK_JOB_MAP_DECL_LINES   … 宣言の物理行番号
# 戻り値: crosscheck_job_map_repo_load は job_map_repo_load と同じ(0 / JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED / JOB_MAP_REPO_STATUS_COMMAND_FAILED)

CROSSCHECK_JOB_MAP_DECL_NAMES=()
CROSSCHECK_JOB_MAP_DECL_VALUES=()
CROSSCHECK_JOB_MAP_DECL_LINES=()

# crosscheck_job_map_repo_declaration の結果: 出現回数 / 初出の値 / 初出の行番号
CROSSCHECK_JOB_MAP_DECL_FOUND=0
CROSSCHECK_JOB_MAP_DECL_VALUE=""
CROSSCHECK_JOB_MAP_DECL_LINE=0

crosscheck_job_map_repo_reset() {
  CROSSCHECK_JOB_MAP_DECL_NAMES=()
  CROSSCHECK_JOB_MAP_DECL_VALUES=()
  CROSSCHECK_JOB_MAP_DECL_LINES=()
}

# クロスチェックジョブマップ CSV を読み込む(job_map_repo_load と同じ手順に宣言の取り出しを加えたもの)。
# 入力は 1 回だけ一時ファイルへ複製し、バイト点検・CSV 解析・宣言の取り出しはすべて複製だけを読む
# (config_input_rules.snapshot: 1 時点の内容だけに基づく)。複製は正常終了・失敗・シグナルのいずれでも削除する。
# 引数: path(存在・可読性の確認は usecase の責務)
# shellcheck disable=SC2034
crosscheck_job_map_repo_load() {
  local path="$1" saved_traps status=0 failed_commands
  job_map_repo_reset
  crosscheck_job_map_repo_reset
  JOB_MAP_PATH="$path"
  saved_traps="$(trap -p "${JOB_MAP_REPO_TRAP_SIGNALS[@]}")"
  trap 'job_map_repo_remove_snapshot; exit 129' HUP
  trap 'job_map_repo_remove_snapshot; exit 130' INT
  trap 'job_map_repo_remove_snapshot; exit 143' TERM
  if job_map_repo_create_snapshot "$path"; then
    job_map_repo_load_snapshot "$path" "$JOB_MAP_REPO_SNAPSHOT" || status=$?
    if [ "$status" -eq 0 ]; then
      crosscheck_job_map_repo_read_declarations "$JOB_MAP_REPO_SNAPSHOT"
    fi
  else
    status="$JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED"
  fi
  if ! job_map_repo_remove_snapshot && [ "$status" -ne "$JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED" ]; then
    failed_commands="$JOB_MAP_REPO_FAILED_COMMANDS"
    job_map_repo_reset
    crosscheck_job_map_repo_reset
    JOB_MAP_PATH="$path"
    JOB_MAP_REPO_FAILED_COMMANDS="${failed_commands:+$failed_commands,}rm"
    status="$JOB_MAP_REPO_STATUS_COMMAND_FAILED"
  fi
  trap - "${JOB_MAP_REPO_TRAP_SIGNALS[@]}"
  eval "$saved_traps"
  return "$status"
}

# 複製から宣言(行頭 `#` + 空白 0 個以上 + `name=value`。name は `[A-Za-z0-9_]+`)を出現順に取り出す。
# 宣言はファイル先頭のコメント行(ヘッダー行より前)だけから読む(設定契約「先頭のコメント行にファイル全体の宣言を置く」)。
# ヘッダー行以降のコメント行は宣言として扱わない(自由なコメント)。宣言の形に合わないコメント行は無視する。
# 形式違反の行(JOB_MAP_MALFORMED_LINES)は読まない。
# 行の読み込みはバイト単位(LC_ALL=C。事前走査の行番号と対応させる)。行数に比例する時間で処理する。
# 引数: snapshot(JOB_MAP_HEADER_LINE は job_map_repo_load_snapshot が先に確定させる)
crosscheck_job_map_repo_read_declarations() {
  local snapshot="$1" line line_number=0 malformed_index=0 body name
  # `#` の直後に許す空白は半角空白とタブ(ASCII。Unicode 空白は空白として扱わない)
  local blank=$' \t'
  local LC_ALL=C
  while IFS= read -r line || [ -n "$line" ]; do
    line_number=$((line_number + 1))
    if [ "$JOB_MAP_HEADER_LINE" -gt 0 ] && [ "$line_number" -ge "$JOB_MAP_HEADER_LINE" ]; then
      break
    fi
    if [ "$malformed_index" -lt "${#JOB_MAP_MALFORMED_LINES[@]}" ] && [ "${JOB_MAP_MALFORMED_LINES[malformed_index]}" -eq "$line_number" ]; then
      malformed_index=$((malformed_index + 1))
      continue
    fi
    case "$line" in
      \#*) ;;
      *) continue ;;
    esac
    body="${line#\#}"
    body="${body#"${body%%[!"$blank"]*}"}"
    name="${body%%=*}"
    if [ "$name" = "$body" ] || [[ ! "$name" =~ ^[A-Za-z0-9_]+$ ]]; then
      continue
    fi
    CROSSCHECK_JOB_MAP_DECL_NAMES+=("$name")
    CROSSCHECK_JOB_MAP_DECL_VALUES+=("${body#*=}")
    CROSSCHECK_JOB_MAP_DECL_LINES+=("$line_number")
  done <"$snapshot"
}

# 名前の宣言を引く。結果は CROSSCHECK_JOB_MAP_DECL_FOUND(出現回数)/ CROSSCHECK_JOB_MAP_DECL_VALUE / CROSSCHECK_JOB_MAP_DECL_LINE(初出)
# 引数: name
# shellcheck disable=SC2034
crosscheck_job_map_repo_declaration() {
  local name="$1" index=0 count="${#CROSSCHECK_JOB_MAP_DECL_NAMES[@]}"
  CROSSCHECK_JOB_MAP_DECL_FOUND=0
  CROSSCHECK_JOB_MAP_DECL_VALUE=""
  CROSSCHECK_JOB_MAP_DECL_LINE=0
  while [ "$index" -lt "$count" ]; do
    if [ "${CROSSCHECK_JOB_MAP_DECL_NAMES[$index]}" = "$name" ]; then
      if [ "$CROSSCHECK_JOB_MAP_DECL_FOUND" -eq 0 ]; then
        CROSSCHECK_JOB_MAP_DECL_VALUE="${CROSSCHECK_JOB_MAP_DECL_VALUES[$index]}"
        CROSSCHECK_JOB_MAP_DECL_LINE="${CROSSCHECK_JOB_MAP_DECL_LINES[$index]}"
      fi
      CROSSCHECK_JOB_MAP_DECL_FOUND=$((CROSSCHECK_JOB_MAP_DECL_FOUND + 1))
    fi
    index=$((index + 1))
  done
}

# 対象カタログの読み込み(計算ルール「対象カタログ参照の解決」の前段)。カタログも同じ CSV 解析関数(job_map_repo_load。
# 入力の複製(単一スナップショット)・バイト点検・クォート解析を含む)で読む(JOB_MAP_* を上書きするため、ジョブマップ側の
# 行を読み終えてから呼ぶ)。入力の守備範囲(config_input_rules)は全設定ファイル共通なので、カタログの形式違反は
# 「参照未解決」に丸めない: 解析できない段階の違反(NUL / 不正な UTF-8 / BOM / CR の行、ヘッダー行のクォート不正)は
# CROSSCHECK_TARGET_CATALOG_FORMAT_INVALID で返し、データ行の違反(クォート不正・列数不一致)は読み込み結果
# (JOB_MAP_ROW_STATUSES / JOB_MAP_ROW_CELL_COUNTS)に残す。どちらも usecase が共通の文言で報告する。
# カタログの列の検証(列名・必須・値域)は tier-final-crosscheck に委ね、ここでは参照解決に必要な読み込みだけを行う。
# 戻り値: CROSSCHECK_TARGET_CATALOG_LOADED … 解析できた(ヘッダーは JOB_MAP_HEADER。データ行の形式違反は含み得る)/
#         CROSSCHECK_TARGET_CATALOG_MISSING … ファイル不在・読めない /
#         CROSSCHECK_TARGET_CATALOG_FORMAT_INVALID … 形式違反(NUL / 不正な UTF-8 / BOM / CR の行がある、ヘッダー行のクォート不正)/
#         JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED / JOB_MAP_REPO_STATUS_COMMAND_FAILED … 内部障害(usecase が終了コード 6 にする)
# 引数: catalog_path
CROSSCHECK_TARGET_CATALOG_LOADED=0
CROSSCHECK_TARGET_CATALOG_MISSING=1
CROSSCHECK_TARGET_CATALOG_FORMAT_INVALID=2
crosscheck_target_catalog_repo_load() {
  local catalog_path="$1" status=0
  if [ ! -f "$catalog_path" ] || [ ! -r "$catalog_path" ]; then
    return "$CROSSCHECK_TARGET_CATALOG_MISSING"
  fi
  job_map_repo_load "$catalog_path" || status=$?
  if [ "$status" -ne 0 ]; then
    return "$status"
  fi
  if [ "${#JOB_MAP_MALFORMED_LINES[@]}" -ne 0 ] || [ "$JOB_MAP_HEADER_STATUS" = "$JOB_MAP_PARSE_QUOTE_INVALID" ]; then
    return "$CROSSCHECK_TARGET_CATALOG_FORMAT_INVALID"
  fi
  return "$CROSSCHECK_TARGET_CATALOG_LOADED"
}

# 対象カタログ参照の解決(計算ルール「対象カタログ参照の解決」): 読み込み済みのカタログ(JOB_MAP_*)に catalog_version 列があり、
# 値が version に一致する行が 1 件以上あるか。照合に使うのは、クォート解析でき列数がヘッダーの列数と一致する行だけ
# (クォート不正・列数不一致の行は列を対応付けられない。報告は usecase の crosscheck_target_catalog_report_row_errors)。
# ヘッダー行が無い・catalog_version 列が無いときは解決できない。
# 列名の重複(どの列を使うか決められない)は呼び出し元が report_duplicate_columns で先に拒否する。
# 戻り値: 0 … 解決できた / 1 … 解決できない(ヘッダー行が無い・catalog_version 列が無い・該当行なし)
# 引数: version
crosscheck_target_catalog_repo_has_version() {
  local version="$1" column_index=0 found=false
  local row_index=0 row_count offset column_count
  if [ "$JOB_MAP_HEADER_STATUS" != "$JOB_MAP_PARSE_OK" ]; then
    return 1
  fi
  column_count="${#JOB_MAP_HEADER[@]}"
  for column_index in "${!JOB_MAP_HEADER[@]}"; do
    if [ "${JOB_MAP_HEADER[$column_index]}" = "$CROSSCHECK_DECL_CATALOG_VERSION" ]; then
      found=true
      break
    fi
  done
  if [ "$found" = false ]; then
    return 1
  fi
  row_count="${#JOB_MAP_ROW_LINES[@]}"
  while [ "$row_index" -lt "$row_count" ]; do
    if [ "${JOB_MAP_ROW_STATUSES[$row_index]}" = "$JOB_MAP_PARSE_OK" ] && [ "${JOB_MAP_ROW_CELL_COUNTS[$row_index]}" -eq "$column_count" ]; then
      offset="${JOB_MAP_ROW_OFFSETS[$row_index]}"
      if [ "${JOB_MAP_CELLS[offset + column_index]}" = "$version" ]; then
        return 0
      fi
    fi
    row_index=$((row_index + 1))
  done
  return 1
}
