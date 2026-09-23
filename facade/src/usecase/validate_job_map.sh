#!/usr/bin/env bash
# usecase: ValidateJobMapQuery。
# 入力の複製(単一スナップショット)→ バイト点検(NUL / UTF-8 / BOM / CR)→ ヘッダー検証(必須列・host / user の対・列名の重複)
# → 行ごとの列検証 → job_id 重複検査 → 集計出力。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/slot ごとのジョブマップを定義する/tier-facade.md
#       「出力契約」「UC ロジック」(全行を検査してから全件報告。読み取り専用・副作用なし)
#       _cross-cutting/api/cli-command-contract.yaml config_input_rules(rules / snapshot / internal_failure)
#       stdout の固定順(map_path, rows, map_version)は cli-command-contract.yaml commands[validate-config.sh].stdout が正。
#       行の形式(`key=value` / `key: value` / 空値 `-`)は domain/cli_field.sh(ui-design.md 出力フォーマット)に従う。
# 任意入力(パス・セルの値)を出す行は、制御文字を可視表記にする(cli_field_safe_text。ANSI を出さず 1 行 1 事実を保つ)。
# 報告行(error / warn / info / hint)は domain の job_map_emit で JOB_MAP_REPORT_LINES に溜め、検証を終えてから stderr へ出す。
# 内部障害(終了コード 6)のときは溜めた行を捨て、error 行 1 つ(+ hint)だけを出す(他の error / warn 行も stdout も出さない)。
# 依存: domain/job_map.sh, domain/cli_field.sh, repository/job_map_repo.sh
# 戻り値: 0(検証 OK)/ 2(ファイルなし・読めない・入力の守備範囲の違反・ヘッダー不一致・列名の重複・クォート不正・
#         列数不一致・列検証違反・job_id 重複)/
#         6(入力の複製の失敗、または補助コマンド tr / sed / sort / rm(複製の削除)の失敗。conventions.exit_codes の実行エラー。
#           検証が未完了のまま検証 OK にも検証違反にもしない。stdout は出さない。補助コマンド自身の stderr も出さない)

JOB_MAP_EXIT_OK=0
JOB_MAP_EXIT_VALIDATION_ERROR=2
JOB_MAP_EXIT_EXECUTION_ERROR=6

# 溜めた報告行を stderr へ出す(1 回の printf で出す)
validate_job_map_flush_report() {
  if [ "${#JOB_MAP_REPORT_LINES[@]}" -gt 0 ]; then
    printf '%s\n' "${JOB_MAP_REPORT_LINES[@]}" >&2
  fi
  JOB_MAP_REPORT_LINES=()
}

# クォート不正の行を全件報告する(ヘッダーが使えず列検証に進めないときも、クォート不正は行番号付きで全部出す)
# 引数: shown_path(表示用に置き換え済みのパス)
validate_job_map_report_quote_errors() {
  local shown_path="$1" row_index=0 row_count="${#JOB_MAP_ROW_LINES[@]}"
  while [ "$row_index" -lt "$row_count" ]; do
    if [ "${JOB_MAP_ROW_STATUSES[$row_index]}" = "$JOB_MAP_PARSE_QUOTE_INVALID" ]; then
      job_map_emit "error: csv quote is invalid line=${JOB_MAP_ROW_LINES[$row_index]} path: $shown_path"
    fi
    row_index=$((row_index + 1))
  done
}

# 入力の守備範囲の違反(config_input_rules.rules)を原因ごとの文言で行番号順に全件報告する。
# 1 行に複数の原因があれば BOM → NUL → 文字コード → CR の順に出す。`hint: use LF line endings` は最後の CR の error 行の次に 1 回。
# 戻り値: 0 … 違反なし / 1 … 違反あり(報告済み)
# 引数: shown_path
validate_job_map_report_byte_errors() {
  local shown_path="$1" line number last_cr=0 reported=0
  # 行番号を添字にした疎な配列で原因を持つ(行番号は事前走査の出力なので数字だけ)
  local nul_lines=() encoding_lines=() cr_lines=()
  for number in ${JOB_MAP_NUL_LINES[@]+"${JOB_MAP_NUL_LINES[@]}"}; do
    nul_lines[number]=1
  done
  for number in ${JOB_MAP_ENCODING_LINES[@]+"${JOB_MAP_ENCODING_LINES[@]}"}; do
    encoding_lines[number]=1
  done
  for number in ${JOB_MAP_CR_LINES[@]+"${JOB_MAP_CR_LINES[@]}"}; do
    cr_lines[number]=1
    last_cr="$number"
  done
  for line in ${JOB_MAP_MALFORMED_LINES[@]+"${JOB_MAP_MALFORMED_LINES[@]}"}; do
    if [ "$JOB_MAP_BOM_LINE" -eq "$line" ]; then
      job_map_emit "error: byte order mark is not allowed line=$line path: $shown_path"
      reported=$((reported + 1))
    fi
    if [ -n "${nul_lines[line]+x}" ]; then
      job_map_emit "error: nul byte is not allowed line=$line path: $shown_path"
      reported=$((reported + 1))
    fi
    if [ -n "${encoding_lines[line]+x}" ]; then
      job_map_emit "error: encoding is not utf-8 line=$line path: $shown_path"
      reported=$((reported + 1))
    fi
    if [ -n "${cr_lines[line]+x}" ]; then
      job_map_emit "error: carriage return is not allowed line=$line path: $shown_path"
      reported=$((reported + 1))
      if [ "$line" -eq "$last_cr" ]; then
        job_map_emit "hint: use LF line endings"
      fi
    fi
  done
  [ "$reported" -eq 0 ]
}

# 内部障害を報告する(実行エラー。利用者が設定の問題と検証器の障害を区別できるようにする)。
# 溜めた報告行は出さない(検証 OK も違反も返さない。config_input_rules.internal_failure)
# 引数: commands(カンマ区切りの失敗したコマンド名) shown_path
validate_job_map_report_command_failure() {
  local commands="$1" shown_path="$2"
  JOB_MAP_REPORT_LINES=()
  printf '%s\n' "error: internal command failed commands=$commands path: $shown_path" >&2
}

# 入力の複製の失敗を報告する(コマンド名を問わず「入力の複製の失敗」。config_input_rules.internal_failure)
# 引数: shown_path
validate_job_map_report_snapshot_failure() {
  local shown_path="$1"
  JOB_MAP_REPORT_LINES=()
  printf '%s\n' "error: config snapshot failed path: $shown_path" >&2
  printf '%s\n' "hint: check TMPDIR is writable" >&2
}

# 引数: path verbose(true|false)
validate_job_map_query() {
  local path="$1" verbose="${2:-false}" shown_path
  cli_field_safe_text "$path"
  shown_path="$CLI_FIELD_SAFE_TEXT"

  if [ ! -e "$path" ]; then
    printf '%s\n' "error: config file not found path: $shown_path" >&2
    return "$JOB_MAP_EXIT_VALIDATION_ERROR"
  fi
  if [ ! -f "$path" ] || [ ! -r "$path" ]; then
    printf '%s\n' "error: config file is not readable path: $shown_path" >&2
    return "$JOB_MAP_EXIT_VALIDATION_ERROR"
  fi

  # 報告行は検証を終えるまで溜める(内部障害のときに他の行を出さないため)。戻るときに出力先を元に戻す
  local saved_sink="$JOB_MAP_REPORT_SINK" status
  JOB_MAP_REPORT_SINK="$JOB_MAP_REPORT_SINK_ARRAY"
  JOB_MAP_REPORT_LINES=()
  validate_job_map_run "$path" "$verbose" "$shown_path" || status=$?
  JOB_MAP_REPORT_SINK="$saved_sink"
  return "${status:-0}"
}

# 検証の本体(validate_job_map_query から呼ぶ。JOB_MAP_REPORT_SINK は配列)
# 引数: path verbose shown_path
validate_job_map_run() {
  local path="$1" verbose="$2" shown_path="$3" load_status=0

  # (1) 入力の複製 → (2) バイト点検。複製の失敗と、複製完了後の補助コマンドの失敗は検証結果にせず終了コード 6
  job_map_repo_load "$path" || load_status=$?
  if [ "$load_status" -eq "$JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED" ]; then
    validate_job_map_report_snapshot_failure "$shown_path"
    return "$JOB_MAP_EXIT_EXECUTION_ERROR"
  fi
  if [ "$load_status" -ne 0 ]; then
    validate_job_map_report_command_failure "$JOB_MAP_REPO_FAILED_COMMANDS" "$shown_path"
    return "$JOB_MAP_EXIT_EXECUTION_ERROR"
  fi

  # 形式(UTF-8 / LF / BOM なし / NUL なし)から外れた入力は原因ごとの文言で拒否する。形式違反の行は解析できないため、
  # ヘッダー・行・重複の検証には進まない(利用者が error 行だけで原因を区別できるようにする)
  if ! validate_job_map_report_byte_errors "$shown_path"; then
    validate_job_map_flush_report
    return "$JOB_MAP_EXIT_VALIDATION_ERROR"
  fi

  # (3) ヘッダー行: クォート不正なら列を対応付けられないため、クォート不正だけを全件報告して終える
  if [ "$JOB_MAP_HEADER_STATUS" = "$JOB_MAP_PARSE_QUOTE_INVALID" ]; then
    job_map_emit "error: csv quote is invalid line=$JOB_MAP_HEADER_LINE path: $shown_path"
    validate_job_map_report_quote_errors "$shown_path"
    validate_job_map_flush_report
    return "$JOB_MAP_EXIT_VALIDATION_ERROR"
  fi
  # ヘッダー不一致(必須列の欠落・host / user の片方だけ)と列名の重複は、列を対応付けられないため列検証に進まない
  if ! validate_job_map_header "$path" ${JOB_MAP_HEADER[@]+"${JOB_MAP_HEADER[@]}"}; then
    validate_job_map_report_quote_errors "$shown_path"
    validate_job_map_flush_report
    return "$JOB_MAP_EXIT_VALIDATION_ERROR"
  fi
  job_map_header_bind "${JOB_MAP_HEADER[@]}"

  # (4) 行ごとの検証(全件)
  local errors=0 row_index=0 row_count="${#JOB_MAP_ROW_LINES[@]}" line expected="${#JOB_MAP_HEADER[@]}" actual
  local job_id_pairs=() map_versions=()
  while [ "$row_index" -lt "$row_count" ]; do
    line="${JOB_MAP_ROW_LINES[$row_index]}"
    actual="${JOB_MAP_ROW_CELL_COUNTS[$row_index]}"
    if [ "${JOB_MAP_ROW_STATUSES[$row_index]}" = "$JOB_MAP_PARSE_QUOTE_INVALID" ]; then
      job_map_emit "error: csv quote is invalid line=$line path: $shown_path"
      errors=$((errors + 1))
    elif [ "$actual" -ne "$expected" ]; then
      # 列数不一致の行(空白だけの行を含む)は列を対応付けられないため、列検証・重複検査の対象にしない
      job_map_emit "error: column count mismatch line=$line expected=$expected actual=$actual"
      errors=$((errors + 1))
    else
      job_map_row_bind_at JOB_MAP_CELLS "${JOB_MAP_ROW_OFFSETS[$row_index]}"
      if validate_job_map_row "$line"; then
        # 検証を通過した行の解決結果は必ず作れる。作れなければ検証器の障害として扱う(黙って行を落とさない)
        if [ "$verbose" = "true" ] && ! job_map_row_resolved_line; then
          validate_job_map_report_command_failure "job_map_row_resolved_line" "$shown_path"
          return "$JOB_MAP_EXIT_EXECUTION_ERROR"
        fi
      else
        errors=$((errors + 1))
      fi
      job_id_pairs+=("$line" "$JOB_MAP_ROW_JOB_ID")
      map_versions+=("$JOB_MAP_ROW_MAP_VERSION")
    fi
    row_index=$((row_index + 1))
  done

  # (5) job_id の重複検査(0 … 重複なし / 1 … 重複あり / それ以外 … sort の失敗。重複検査が未実施のまま検証 OK にしない)
  local unique_status=0
  validate_job_map_unique_job_ids ${job_id_pairs[@]+"${job_id_pairs[@]}"} || unique_status=$?
  if [ "$unique_status" -eq "$JOB_MAP_STATUS_COMMAND_FAILED" ]; then
    validate_job_map_report_command_failure "sort" "$shown_path"
    return "$JOB_MAP_EXIT_EXECUTION_ERROR"
  fi
  if [ "$unique_status" -ne 0 ]; then
    errors=$((errors + 1))
  fi

  # (6) 版の集計(集計値は JOB_MAP_VERSION_SUMMARY、版の混在は warn。warn は拒否しない)
  if ! job_map_version_summary ${map_versions[@]+"${map_versions[@]}"} || [ -z "$JOB_MAP_VERSION_SUMMARY" ]; then
    validate_job_map_report_command_failure "job_map_version_summary" "$shown_path"
    return "$JOB_MAP_EXIT_EXECUTION_ERROR"
  fi

  validate_job_map_flush_report
  if [ "$errors" -ne 0 ]; then
    return "$JOB_MAP_EXIT_VALIDATION_ERROR"
  fi

  cli_path_field_line map_path "$path"
  cli_field_line rows "$row_count"
  cli_field_line map_version "$JOB_MAP_VERSION_SUMMARY"
  return "$JOB_MAP_EXIT_OK"
}
