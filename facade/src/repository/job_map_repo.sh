#!/usr/bin/env bash
# repository: JobMapRepository(slot ジョブマップ CSV の読み込みと CSV セルのクォート解析)。
# 仕様: docs/specs/latest/適用構成業務/適用構成定義フロー/slot ごとのジョブマップを定義する/tier-facade.md
#       「設定契約(slot ジョブマップ CSV)」形式 / CSV セルのクォート解析規則 / 入力の守備範囲
#       _cross-cutting/api/cli-command-contract.yaml config_files[<slot>-job-map.csv].csv_rules
#       _cross-cutting/api/cli-command-contract.yaml config_input_rules(rules / snapshot / internal_failure)
#   - 1 行目はヘッダー行。行頭 `#` の行と空行(0 バイトの行)は無視。改行コードは LF。セル内に改行は置けない
#   - セルはカンマ区切り。二重引用符で囲める。囲んだセル内の二重引用符は `""` と二重化する
#   - bash 単独(外部 CSV パーサ非依存)で 1 文字ずつ状態機械で解析する(ネスト・複数行セル不可)
#   - 形式から外れた入力(NUL バイト・UTF-8 として不正なバイト列・BOM・CR)は原因ごとに行番号を記録する
#     (コメント行も含む。文言と終了コードは usecase が付ける)
# UC「ジョブマップで JOB_ID から実行先を解決する」の runner 解決関数と共有する(同じ解析を二重に実装しない)。
# この層は検証しない(列の意味・必須・値域は domain/job_map.sh の検証表)。メッセージも出さない。
# 読み込み結果(グローバル):
#   JOB_MAP_PATH              … 読み込んだファイルパス(引数どおり。メッセージの `path:` に使う)
#   JOB_MAP_HEADER_LINE       … ヘッダー行の行番号(ヘッダー行が無ければ 0)
#   JOB_MAP_HEADER_STATUS     … ヘッダー行の解析結果(ok | quote_invalid | malformed | missing)
#   JOB_MAP_HEADER            … ヘッダー行のセル(列名)
#   JOB_MAP_ROW_LINES         … データ行ごとの行番号(ファイル先頭を 1 とする物理行番号)
#   JOB_MAP_ROW_STATUSES      … データ行ごとの解析結果(ok | quote_invalid | malformed)
#   JOB_MAP_ROW_OFFSETS       … データ行ごとの JOB_MAP_CELLS 内の開始位置
#   JOB_MAP_ROW_CELL_COUNTS   … データ行ごとのセル数(quote_invalid / malformed の行は 0)
#   JOB_MAP_CELLS             … 全データ行のセルを行順に連結した配列(bash は 2 次元配列を持たないため)
#   JOB_MAP_NUL_LINES         … NUL バイト(0x00)を含む行の行番号(昇順。コメント行を含む)
#   JOB_MAP_ENCODING_LINES    … UTF-8 として不正なバイト列を含む行の行番号(昇順。コメント行を含む)
#   JOB_MAP_CR_LINES          … CR(0x0d)を含む行の行番号(昇順。CRLF 改行・行末 CR・セル内 CR)
#   JOB_MAP_BOM_LINE          … 先頭に BOM(EF BB BF)があれば 1、無ければ 0
#   JOB_MAP_MALFORMED_LINES   … 上記 4 種のいずれかに当たる行の行番号(昇順・重複なし)。解析せず malformed として記録する
#   JOB_MAP_SCANNED_LINE_COUNT … 事前走査が数えた総行数(読み込んだ行数と照合する。空のファイルは 0)
#   JOB_MAP_REPO_FAILED_COMMANDS … 補助コマンドの失敗時に、失敗したコマンド名(カンマ区切り)
# 最終行の改行なしは受理する。セル前後の空白の除去はしない(バイト列を変えずにセルへ分解する)。行の長さに上限は無い。
# 戻り値: job_map_repo_load は 0(読み込み完了)/ JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED(入力の複製の失敗)/
#         JOB_MAP_REPO_STATUS_COMMAND_FAILED(複製完了後の補助コマンド tr / sed / rm の失敗・想定外の出力)
# 補助コマンド自身の stderr はどれも出さない(内部障害の報告は usecase の error 行 1 つだけ)

JOB_MAP_PARSE_OK="ok"
JOB_MAP_PARSE_QUOTE_INVALID="quote_invalid"
# 形式違反(NUL / 不正な UTF-8 / BOM / CR)の行。bash 単独で解析できる範囲の外なので解析しない
JOB_MAP_PARSE_MALFORMED="malformed"
JOB_MAP_HEADER_MISSING="missing"
# 複製完了後の補助コマンド(tr / sed)が失敗した・想定外の出力をしたときの戻り値
# (値は conventions.exit_codes の実行エラーと同じ)
JOB_MAP_REPO_STATUS_COMMAND_FAILED=6
# 入力の複製(一時ファイルの作成・複製先への書き込み・最終名への rename)が失敗したときの戻り値
# (config_input_rules.internal_failure はコマンド名を問わず「入力の複製の失敗」として区別する)
JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED=7

# 入力の複製(単一スナップショット)の名前(config_input_rules.snapshot.validate_config):
# `${TMPDIR:-/tmp}/relay-gate-XXXXXX.part` を mktemp で作り(作業名)、書き終えたら `.part` を外した最終名へ rename する
JOB_MAP_SNAPSHOT_PREFIX="relay-gate-"
JOB_MAP_SNAPSHOT_WORK_SUFFIX=".part"

# 事前走査の sed スクリプト(バイト単位。LC_ALL=C で実行する)。tr が NUL を `N`(元からある `N` は `x`)に置き換えた入力を読む。
# 出力は「原因の文字 + 改行 + 行番号 + 改行」の繰り返しと、最終行で出す証跡(`E` + 改行 + 総行数):
#   n … NUL バイトを含む行 / r … CR を含む行 / b … 先頭に BOM がある(1 行目だけ) / u … UTF-8 として不正なバイト列を含む行
# 1 行に複数の原因があれば原因ごとに出す。行番号だけを取り出し、値は取り込まない。
# 妥当な UTF-8 の多バイト文字(RFC 3629 の範囲。過長形式・サロゲート・U+10FFFF 超を含まない)を 4 バイト → 3 バイト →
# 2 バイトの順に ASCII の `x` へ置き換え、置き換え後に 0x80 以上のバイトが残った行を不正とする(BOM の判定はこの置き換えの前に行う)。
# 拡張正規表現や \xHH の拡張に頼らず、基本正規表現と生のバイトだけで書く(GNU sed と BSD sed の両方で動く)
JOB_MAP_SCAN_UTF8_CONTINUATION=$'[\x80-\xbf]'
# 走査が最終行まで進んだ証跡の文字(この後に sed が数えた総行数が続く)。
# 出力が無いことが「異常な行が無い」を意味すると、補助コマンドが何も出さずに終了状態 0 で終わる障害と区別できない
JOB_MAP_SCAN_END_MARKER="E"
JOB_MAP_SCAN_MARK_NUL="n"
JOB_MAP_SCAN_MARK_CR="r"
JOB_MAP_SCAN_MARK_BOM="b"
JOB_MAP_SCAN_MARK_ENCODING="u"
JOB_MAP_SCAN_MARKS="$JOB_MAP_SCAN_MARK_NUL$JOB_MAP_SCAN_MARK_CR$JOB_MAP_SCAN_MARK_BOM$JOB_MAP_SCAN_MARK_ENCODING$JOB_MAP_SCAN_END_MARKER"
# 走査のパイプラインが失敗したとき、失敗したコマンド名を伝える最終行の先頭文字(job_map_repo_scan_output)
JOB_MAP_SCAN_FAILED_MARKER="!"
# 書き込み先のパイプが先に閉じたコマンドの終了状態(128 + SIGPIPE 13)
JOB_MAP_SCAN_SIGPIPE_STATUS=141
JOB_MAP_SCAN_SED_SCRIPT=(
  # 最終行で、証跡の文字と総行数を先に出す(ホールドスペースと入れ替えて証跡の文字に置き換えて出し、元に戻す)
  -e $'${\nx\ns/.*/E/\np\nx\n=\n}'
  # 原因ごとの判定は元の行に対して行う(判定のたびにホールドスペースから戻す)
  -e 'h'
  -e $'/N/{\ns/.*/n/p\n=\ng\n}'
  -e $'/\r/{\ns/.*/r/p\n=\ng\n}'
  -e $'1{\n/^\xef\xbb\xbf/{\ns/.*/b/p\n=\ng\n}\n}'
  -e $'s/\xf0[\x90-\xbf]'"$JOB_MAP_SCAN_UTF8_CONTINUATION$JOB_MAP_SCAN_UTF8_CONTINUATION/x/g"
  -e $'s/[\xf1-\xf3]'"$JOB_MAP_SCAN_UTF8_CONTINUATION$JOB_MAP_SCAN_UTF8_CONTINUATION$JOB_MAP_SCAN_UTF8_CONTINUATION/x/g"
  -e $'s/\xf4[\x80-\x8f]'"$JOB_MAP_SCAN_UTF8_CONTINUATION$JOB_MAP_SCAN_UTF8_CONTINUATION/x/g"
  -e $'s/\xe0[\xa0-\xbf]'"$JOB_MAP_SCAN_UTF8_CONTINUATION/x/g"
  -e $'s/[\xe1-\xec\xee\xef]'"$JOB_MAP_SCAN_UTF8_CONTINUATION$JOB_MAP_SCAN_UTF8_CONTINUATION/x/g"
  -e $'s/\xed[\x80-\x9f]'"$JOB_MAP_SCAN_UTF8_CONTINUATION/x/g"
  -e $'s/[\xc2-\xdf]'"$JOB_MAP_SCAN_UTF8_CONTINUATION/x/g"
  # UTF-8 として不正な行(コメント行でも報告する。文字コード UTF-8 はファイル全体の形式)
  -e $'/[\x80-\xff]/{\ns/.*/u/p\n=\n}'
)

# CSV 1 行の解析状態(状態機械)
CSV_STATE_CELL_START="cell_start"
CSV_STATE_UNQUOTED="unquoted"
CSV_STATE_QUOTED="quoted"
CSV_STATE_QUOTE_CLOSED="quote_closed"
# csv_parse が 1 回に取り込む窓の大きさ(バイト)。解析結果には影響しない(長い行の処理時間だけに効く)
CSV_PARSE_WINDOW_BYTES=1024

# csv_parse の結果(1 行分のセル)
CSV_CELLS=()
# job_map_repo_row が取り出した 1 行分のセル
JOB_MAP_ROW=()

# CSV 1 行をセルに分解して CSV_CELLS に載せる。
# 戻り値: 0 … 解析 OK / 1 … クォート不正(閉じ引用符が無い・囲み外に二重引用符がある・閉じ引用符の直後がカンマでも行末でもない)
# 引数: line(改行を含まない 1 行)
csv_parse() {
  # バイト単位で処理する(ロケールに依存させない)。UTF-8 の多バイト文字の各バイトは 0x80 以上で、
  # 区切りの ASCII 文字と重ならない(UTF-8 として不正な行は job_map_repo_load が解析前に除く。この関数はバイト列を変えない)
  local LC_ALL=C
  # 窓に収まる長さの行(通常のジョブマップの行)は、窓の取り込みを省いた同じ文法の解析で済ませる(行数に比例して呼ばれるため)
  if [ "${#1}" -le "$CSV_PARSE_WINDOW_BYTES" ]; then
    csv_parse_short "$1"
    return
  fi
  # bash の文字列操作は文字列全体の長さに比例する時間がかかるため、行を 1 文字ずつ添字で取り出すと
  # 行の長さの 2 乗の時間がかかる。行を CSV_PARSE_WINDOW_BYTES ずつ rest(未解析の窓)へ取り込み、
  # 区切り(カンマ・二重引用符)以外の連続した文字はまとめて取り込む。状態遷移は 1 文字ずつの解析と同じ
  local line="$1" state="$CSV_STATE_CELL_START" cell="" run rest="" offset=0 total
  total="${#line}"
  CSV_CELLS=()
  while [ -n "$rest" ] || [ "$offset" -lt "$total" ]; do
    # `""` の判定に 2 文字要るため、窓が 2 文字未満になったら続きを取り込む
    if [ "${#rest}" -lt 2 ] && [ "$offset" -lt "$total" ]; then
      rest+="${line:offset:CSV_PARSE_WINDOW_BYTES}"
      offset=$((offset + CSV_PARSE_WINDOW_BYTES))
    fi
    case "$state" in
      "$CSV_STATE_CELL_START")
        case "$rest" in
          '"'*)
            state="$CSV_STATE_QUOTED"
            rest="${rest:1}"
            ;;
          ,*)
            CSV_CELLS+=("")
            rest="${rest:1}"
            ;;
          # 囲まないセルの 1 文字目(消費は次の状態で行う)
          *) state="$CSV_STATE_UNQUOTED" ;;
        esac
        ;;
      "$CSV_STATE_UNQUOTED")
        run="${rest%%[\",]*}"
        cell+="$run"
        rest="${rest:${#run}}"
        case "$rest" in
          # 囲まないセルは二重引用符を含められない
          '"'*) return 1 ;;
          ,*)
            CSV_CELLS+=("$cell")
            cell=""
            state="$CSV_STATE_CELL_START"
            rest="${rest:1}"
            ;;
        esac
        ;;
      "$CSV_STATE_QUOTED")
        run="${rest%%\"*}"
        cell+="$run"
        rest="${rest:${#run}}"
        # 窓の最後の 1 文字が二重引用符のときは、続きを取り込んでから `""` か閉じ引用符かを決める
        if [ "$rest" = '"' ] && [ "$offset" -lt "$total" ]; then
          continue
        fi
        case "$rest" in
          '""'*)
            # 囲んだセル内の `""` は二重引用符 1 文字
            cell+='"'
            rest="${rest:2}"
            ;;
          '"'*)
            state="$CSV_STATE_QUOTE_CLOSED"
            rest="${rest:1}"
            ;;
        esac
        ;;
      "$CSV_STATE_QUOTE_CLOSED")
        case "$rest" in
          ,*)
            CSV_CELLS+=("$cell")
            cell=""
            state="$CSV_STATE_CELL_START"
            rest="${rest:1}"
            ;;
          # 閉じ引用符の直後がカンマでも行末でもない
          *) return 1 ;;
        esac
        ;;
    esac
  done
  # 閉じ引用符が無いまま行末に達した
  if [ "$state" = "$CSV_STATE_QUOTED" ]; then
    return 1
  fi
  CSV_CELLS+=("$cell")
  return 0
}

# csv_parse の窓なし版(窓に収まる長さの行だけに使う。受理する文法と結果は窓ありの状態機械と同じ)。
# セルごとに、囲みセルなら閉じ引用符(`""` は二重引用符 1 文字)まで、囲まないセルならカンマか二重引用符の手前までをまとめて取り込む。
# 戻り値: csv_parse と同じ
# 引数: line
csv_parse_short() {
  local rest="$1" cell run
  local LC_ALL=C
  CSV_CELLS=()
  while :; do
    if [[ "$rest" == \"* ]]; then
      rest="${rest:1}"
      cell=""
      while :; do
        run="${rest%%\"*}"
        # 閉じ引用符が無いまま行末に達した
        if [ "${#run}" -eq "${#rest}" ]; then
          return 1
        fi
        cell+="$run"
        rest="${rest:${#run}+1}"
        if [[ "$rest" == \"* ]]; then
          # 囲んだセル内の `""` は二重引用符 1 文字
          cell+='"'
          rest="${rest:1}"
        else
          break
        fi
      done
      if [ -z "$rest" ]; then
        CSV_CELLS+=("$cell")
        return 0
      fi
      # 閉じ引用符の直後がカンマでも行末でもない
      if [[ "$rest" != ,* ]]; then
        return 1
      fi
    else
      cell="${rest%%[\",]*}"
      rest="${rest:${#cell}}"
      if [ -z "$rest" ]; then
        CSV_CELLS+=("$cell")
        return 0
      fi
      # 囲まないセルは二重引用符を含められない
      if [[ "$rest" == \"* ]]; then
        return 1
      fi
    fi
    CSV_CELLS+=("$cell")
    rest="${rest:1}"
  done
}

job_map_repo_reset() {
  JOB_MAP_PATH=""
  JOB_MAP_HEADER_LINE=0
  JOB_MAP_HEADER_STATUS="$JOB_MAP_HEADER_MISSING"
  JOB_MAP_HEADER=()
  JOB_MAP_ROW_LINES=()
  JOB_MAP_ROW_STATUSES=()
  JOB_MAP_ROW_OFFSETS=()
  JOB_MAP_ROW_CELL_COUNTS=()
  JOB_MAP_CELLS=()
  JOB_MAP_NUL_LINES=()
  JOB_MAP_ENCODING_LINES=()
  JOB_MAP_CR_LINES=()
  JOB_MAP_BOM_LINE=0
  JOB_MAP_MALFORMED_LINES=()
  JOB_MAP_SCANNED_LINE_COUNT=0
  JOB_MAP_REPO_FAILED_COMMANDS=""
}

# 読み込み中の入力の複製(一時ファイル)の最終名。読み込み中以外は空。
# 作業名(最終名 + .part)と最終名のどちらが存在していても job_map_repo_remove_snapshot が両方を削除する
# (rename の前後で削除対象が途切れないようにする)
JOB_MAP_REPO_SNAPSHOT=""
# 読み込み中だけ差し替える trap の対象(切断・割り込み・終了要求)。
# EXIT は差し替えない: この関数の中の失敗はすべて条件文の中で戻り値として受けるため exit に至らず、
# 戻る経路では必ず複製を削除する。また bash はサブシェル(コマンド置換を含む)の中で、実際には効いていない
# 親の trap を trap -p に表示することがあり、EXIT を表示どおりに戻すとサブシェルの終了時に親の EXIT 処理が動いてしまう
JOB_MAP_REPO_TRAP_SIGNALS=(HUP INT TERM)

# ジョブマップ CSV を読み込み、ヘッダーとデータ行をグローバルに載せる。
# コメント行(行頭 `#`)と空行を除いた最初の行をヘッダー行として扱う。
# 入力は最初に 1 回だけ一時ファイルへ複製し、事前走査(NUL・不正な UTF-8・BOM・CR)と CSV の解析はどちらも複製だけを読む
# (config_input_rules.snapshot: 検証結果は 1 時点の内容だけに基づく。差し替えは検知も報告もしない)。
# 複製は正常終了・失敗・シグナルのいずれでも削除し、呼び出し元の trap は読み込みの後に元へ戻す。
# 引数: path(存在・可読性の確認は呼び出し元 usecase の責務。JOB_MAP_PATH には複製ではなくこのパスを記録する)
# 読み込み結果のグローバルは usecase(validate_job_map.sh)と runner の解決関数が読む(このファイル内では参照しない)
job_map_repo_load() {
  local path="$1" saved_traps status=0 failed_commands
  job_map_repo_reset
  JOB_MAP_PATH="$path"
  saved_traps="$(trap -p "${JOB_MAP_REPO_TRAP_SIGNALS[@]}")"
  # 一時ファイルを作る前に削除の trap を登録する(作成直後のシグナルで残さない。終了コードは 128 + シグナル番号)
  trap 'job_map_repo_remove_snapshot; exit 129' HUP
  trap 'job_map_repo_remove_snapshot; exit 130' INT
  trap 'job_map_repo_remove_snapshot; exit 143' TERM
  if job_map_repo_create_snapshot "$path"; then
    job_map_repo_load_snapshot "$path" "$JOB_MAP_REPO_SNAPSHOT" || status=$?
  else
    status="$JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED"
  fi
  # 複製の削除(rm)の失敗は補助コマンドの失敗として扱い、読み込み結果を検証結果として使わない
  # (config_input_rules.snapshot.validate_config: 読み込みを終えたら削除する。残ったまま検証 OK を返さない)。
  # 複製の工程が失敗していたときは「入力の複製の失敗」の報告を優先する(置き場所の問題が原因で、hint も同じ)
  if ! job_map_repo_remove_snapshot && [ "$status" -ne "$JOB_MAP_REPO_STATUS_SNAPSHOT_FAILED" ]; then
    failed_commands="$JOB_MAP_REPO_FAILED_COMMANDS"
    job_map_repo_reset
    JOB_MAP_PATH="$path"
    # 補助コマンドの失敗と重なったときは失敗した順に並べる(例: sed,rm)
    JOB_MAP_REPO_FAILED_COMMANDS="${failed_commands:+$failed_commands,}rm"
    status="$JOB_MAP_REPO_STATUS_COMMAND_FAILED"
  fi
  trap - "${JOB_MAP_REPO_TRAP_SIGNALS[@]}"
  eval "$saved_traps"
  return "$status"
}

# 入力を一時ファイルへ複製し、最終名を JOB_MAP_REPO_SNAPSHOT に載せる(config_input_rules.snapshot.validate_config)。
#   - mktemp で作業名(`relay-gate-XXXXXX.part`。権限は mktemp の既定 0600)を作る
#   - 作業名へ書き終えてから最終名(`.part` を外した名前)へ同一ディレクトリ内で rename する。最終名は rename まで存在させない
# 戻り値: 0 … 複製完了 / 1 … 一時ファイルを作れない・複製先へ書けない・rename できない(走査していない入力を読み込まない)
# 引数: path
job_map_repo_create_snapshot() {
  local path="$1" dir="${TMPDIR:-/tmp}" work final
  if ! work="$(mktemp "$dir/${JOB_MAP_SNAPSHOT_PREFIX}XXXXXX${JOB_MAP_SNAPSHOT_WORK_SUFFIX}" 2>/dev/null)" || [ -z "$work" ]; then
    return 1
  fi
  JOB_MAP_REPO_SNAPSHOT="${work%"$JOB_MAP_SNAPSHOT_WORK_SUFFIX"}"
  # 末尾以外の X を置き換えない mktemp(BSD 系。実行環境の Linux ではない開発機向け)では、テンプレートのままの名前で
  # 作られる。プロセス固有の作業名へ移してから使う(最終名の規則は変えない)
  if [[ "${work##*/}" == *XXXXXX* ]]; then
    final="$dir/${JOB_MAP_SNAPSHOT_PREFIX}$$-$RANDOM$RANDOM"
    JOB_MAP_REPO_SNAPSHOT="$final"
    mv -- "$work" "$final$JOB_MAP_SNAPSHOT_WORK_SUFFIX" 2>/dev/null || return 1
    work="$final$JOB_MAP_SNAPSHOT_WORK_SUFFIX"
  fi
  # オプションと解釈されるパスでも読めるよう、入力はリダイレクトで渡す
  cat <"$path" >"$work" 2>/dev/null || return 1
  mv -- "$work" "$JOB_MAP_REPO_SNAPSHOT" 2>/dev/null || return 1
}

# 入力の複製を削除する(trap からも呼ぶ。未作成・削除済みなら何もしない。作業名と最終名の両方を対象にする)。
# rm 自身の stderr は出さない(internal_failure: 内部障害の報告は usecase の error 行 1 つだけ)。
# 戻り値: 0 … 削除した・対象なし / 1 … rm が失敗した(複製が残り得る。呼び出し元が内部障害として扱う)
job_map_repo_remove_snapshot() {
  local status=0
  if [ -n "$JOB_MAP_REPO_SNAPSHOT" ]; then
    rm -f -- "$JOB_MAP_REPO_SNAPSHOT" "$JOB_MAP_REPO_SNAPSHOT$JOB_MAP_SNAPSHOT_WORK_SUFFIX" 2>/dev/null || status=1
    JOB_MAP_REPO_SNAPSHOT=""
  fi
  return "$status"
}

# 入力の複製を走査・解析する(job_map_repo_load の本体)。
# 引数: path(記録用の元のパス) snapshot(読む対象の複製)
# shellcheck disable=SC2034
job_map_repo_load_snapshot() {
  local path="$1" snapshot="$2"
  local line line_number=0 malformed malformed_index=0
  # 事前走査が失敗したら 1 行も読み込まない(走査していない行を ok として扱わない)
  if ! job_map_repo_scan_malformed_lines "$snapshot"; then
    return "$JOB_MAP_REPO_STATUS_COMMAND_FAILED"
  fi
  # 最終行に改行が無くても読む
  while IFS= read -r line || [ -n "$line" ]; do
    line_number=$((line_number + 1))
    malformed=false
    if [ "$malformed_index" -lt "${#JOB_MAP_MALFORMED_LINES[@]}" ] && [ "${JOB_MAP_MALFORMED_LINES[malformed_index]}" -eq "$line_number" ]; then
      malformed=true
      malformed_index=$((malformed_index + 1))
    fi
    # 形式違反の行の $line は NUL が落ちた別の文字列や不正なバイト列なので、コメント行・空行の判定にも使わない
    if [ "$malformed" = false ]; then
      case "$line" in
        "" | \#*) continue ;;
      esac
    fi
    job_map_repo_record_line "$line_number" "$line" "$malformed"
  done <"$snapshot"
  # 改行の無い最終行が NUL だけのとき、read は 1 文字も返さずに終端へ達する(上のループに現れない)
  while [ "$malformed_index" -lt "${#JOB_MAP_MALFORMED_LINES[@]}" ]; do
    line_number="${JOB_MAP_MALFORMED_LINES[malformed_index]}"
    job_map_repo_record_line "$line_number" "" true
    malformed_index=$((malformed_index + 1))
  done
  # 事前走査が数えた総行数と、読み込んだ行数が合わなければ、走査していない行がある
  # (補助コマンドの出力の欠落。tr と sed のどちらで欠けたかは判別できない)。検証結果として使わない
  if [ "$line_number" -ne "$JOB_MAP_SCANNED_LINE_COUNT" ]; then
    job_map_repo_reset
    JOB_MAP_PATH="$path"
    JOB_MAP_REPO_FAILED_COMMANDS="tr,sed"
    return "$JOB_MAP_REPO_STATUS_COMMAND_FAILED"
  fi
  return 0
}

# 形式違反の行の物理行番号を原因ごとに JOB_MAP_NUL_LINES / JOB_MAP_ENCODING_LINES / JOB_MAP_CR_LINES / JOB_MAP_BOM_LINE に載せ、
# いずれかに当たる行を昇順・重複なしで JOB_MAP_MALFORMED_LINES に載せる(config_input_rules.rules)。
#   - NUL バイト(0x00)を含む行(コメント行を含む)。bash の文字列は NUL を保持できず、read は NUL を黙って落とす
#     (`a<NUL>b` が `ab` になる)。落ちた後の文字列を検証すると不正な値を受理する
#   - UTF-8 として不正なバイト列を含む行(コメント行を含む)/ 先頭の BOM / CR を含む行
# bash へ取り込む前にバイト列のまま検出する。NUL を `N` に、元からある `N` を別の文字に置き換えてから、
# 原因の文字と行番号だけを取り出す(値は取り込まない)。tr と sed だけを使い、ロケールに依存させない(LC_ALL=C)。
# 戻り値: 0 … 走査完了 / JOB_MAP_REPO_STATUS_COMMAND_FAILED … tr か sed が失敗した・想定外の出力をした・
#         最終行まで走査した証跡(JOB_MAP_SCAN_END_MARKER と総行数)を出さなかった(JOB_MAP_REPO_FAILED_COMMANDS に名前)
# 引数: path
# shellcheck disable=SC2034
job_map_repo_scan_malformed_lines() {
  local path="$1" output
  JOB_MAP_NUL_LINES=()
  JOB_MAP_ENCODING_LINES=()
  JOB_MAP_CR_LINES=()
  JOB_MAP_BOM_LINE=0
  JOB_MAP_MALFORMED_LINES=()
  JOB_MAP_SCANNED_LINE_COUNT=0
  # コマンド置換で受けて終了状態を確認する(プロセス置換は補助コマンドの終了状態を親へ伝えない)。
  # 失敗したときは出力の最終行(`!` + コマンド名)から失敗したコマンド名を受け取る(サブシェルの変数は親に戻らない)
  if ! output="$(job_map_repo_scan_output "$path")"; then
    JOB_MAP_REPO_FAILED_COMMANDS="${output##*$'\n'"$JOB_MAP_SCAN_FAILED_MARKER"}"
    if [ -z "$JOB_MAP_REPO_FAILED_COMMANDS" ] || [ "$JOB_MAP_REPO_FAILED_COMMANDS" = "$output" ]; then
      JOB_MAP_REPO_FAILED_COMMANDS="tr,sed"
    fi
    return "$JOB_MAP_REPO_STATUS_COMMAND_FAILED"
  fi
  # 出力は原因の文字と行番号(数字)と改行だけのはず。それ以外が混ざっていたら走査結果として使わない
  local LC_ALL=C
  if [[ "$output" == *[!0-9"$JOB_MAP_SCAN_MARKS"$'\n']* ]]; then
    JOB_MAP_REPO_FAILED_COMMANDS="sed"
    return "$JOB_MAP_REPO_STATUS_COMMAND_FAILED"
  fi
  # 最終行に改行が無いファイルでは、sed が原因の文字にも改行を付けず行番号が同じ行に続くことがある。
  # 改行を取り除いてから原因の文字ごとに区切り直す(原因の文字 + 数字 の組になる)
  local compact="${output//$'\n'/}" mark
  local marks="$JOB_MAP_SCAN_MARKS"
  while [ -n "$marks" ]; do
    mark="${marks:0:1}"
    marks="${marks:1}"
    compact="${compact//"$mark"/$'\n'$mark}"
  done
  # 数字と原因の文字と改行だけなので、単語分割で配列にしてもパス名展開は起きない
  # (ヒアストリングやプロセス置換を使わない。一時ファイルやサブプロセスの失敗で行番号を黙って失わないため)
  local IFS=$'\n' entries entry number markers=0 last_malformed=0
  # shellcheck disable=SC2206
  entries=($compact)
  for entry in ${entries[@]+"${entries[@]}"}; do
    mark="${entry:0:1}"
    number="${entry:1}"
    if [[ ! "$number" =~ ^[0-9]+$ ]]; then
      JOB_MAP_REPO_FAILED_COMMANDS="sed"
      return "$JOB_MAP_REPO_STATUS_COMMAND_FAILED"
    fi
    case "$mark" in
      "$JOB_MAP_SCAN_END_MARKER")
        markers=$((markers + 1))
        JOB_MAP_SCANNED_LINE_COUNT="$number"
        continue
        ;;
      "$JOB_MAP_SCAN_MARK_NUL") JOB_MAP_NUL_LINES+=("$number") ;;
      "$JOB_MAP_SCAN_MARK_CR") JOB_MAP_CR_LINES+=("$number") ;;
      "$JOB_MAP_SCAN_MARK_BOM") JOB_MAP_BOM_LINE="$number" ;;
      "$JOB_MAP_SCAN_MARK_ENCODING") JOB_MAP_ENCODING_LINES+=("$number") ;;
    esac
    # 原因は行順に出るため、直前と同じ行番号を重ねなければ昇順・重複なしになる
    if [ "$number" -ne "$last_malformed" ]; then
      JOB_MAP_MALFORMED_LINES+=("$number")
      last_malformed="$number"
    fi
  done
  # 空のファイルは最終行が無いため証跡も出ない。それ以外で証跡がちょうど 1 つ無ければ、走査は完了していない
  if [ ! -s "$path" ]; then
    if [ "${#entries[@]}" -ne 0 ]; then
      JOB_MAP_REPO_FAILED_COMMANDS="sed"
      return "$JOB_MAP_REPO_STATUS_COMMAND_FAILED"
    fi
    return 0
  fi
  if [ "$markers" -ne 1 ]; then
    JOB_MAP_REPO_FAILED_COMMANDS="sed"
    return "$JOB_MAP_REPO_STATUS_COMMAND_FAILED"
  fi
  return 0
}

# 事前走査のパイプライン。原因の文字と行番号を stdout に出し、tr と sed の両方が成功したときだけ 0 を返す
# (パイプラインの終了状態は最後のコマンドのものだけなので、PIPESTATUS で全段を確認する)。
# 失敗したときは、失敗したコマンド名を `!` に続けて最終行に出して 1 を返す(呼び出し元はコマンド置換で受けるため、
# 変数では伝えられない)。tr / sed 自身の stderr は出さない(internal_failure: 内部障害の報告は usecase の error 行 1 つだけ。
# 補助コマンドの生の診断を混ぜない)。
# 引数: path
job_map_repo_scan_output() {
  local path="$1" statuses failed=""
  LC_ALL=C tr '\000N' 'Nx' <"$path" 2>/dev/null | LC_ALL=C sed -n "${JOB_MAP_SCAN_SED_SCRIPT[@]}" 2>/dev/null
  statuses=("${PIPESTATUS[@]}")
  if [ "${statuses[1]}" -ne 0 ]; then
    failed="sed"
  fi
  # sed が読み切らずに終わると tr は SIGPIPE(128 + 13)で終わる。これは sed の失敗の結果なので tr を失敗に数えない
  if [ "${statuses[0]}" -ne 0 ] && { [ -z "$failed" ] || [ "${statuses[0]}" -ne "$JOB_MAP_SCAN_SIGPIPE_STATUS" ]; }; then
    failed="tr${failed:+,$failed}"
  fi
  if [ -n "$failed" ]; then
    printf '\n%s%s\n' "$JOB_MAP_SCAN_FAILED_MARKER" "$failed"
    return 1
  fi
  return 0
}

# コメント行・空行を除いた 1 行を、ヘッダー行(最初の 1 行)またはデータ行として記録する。
# 形式違反の行(NUL・不正な UTF-8・BOM・CR)は bash 単独で 1 文字ずつ解析できる範囲の外なので、解析せず malformed にする
# (usecase が config_input_rules の原因ごとの文言で報告する)。
# 引数: line_number line malformed(true|false)
# shellcheck disable=SC2034
job_map_repo_record_line() {
  local line_number="$1" line="$2" malformed="$3" status="$JOB_MAP_PARSE_QUOTE_INVALID"
  CSV_CELLS=()
  if [ "$malformed" = true ]; then
    status="$JOB_MAP_PARSE_MALFORMED"
  elif csv_parse "$line"; then
    status="$JOB_MAP_PARSE_OK"
  fi
  if [ "$JOB_MAP_HEADER_LINE" -eq 0 ]; then
    JOB_MAP_HEADER_LINE="$line_number"
    JOB_MAP_HEADER_STATUS="$status"
    if [ "$status" = "$JOB_MAP_PARSE_OK" ]; then
      JOB_MAP_HEADER=("${CSV_CELLS[@]}")
    fi
    return 0
  fi
  JOB_MAP_ROW_LINES+=("$line_number")
  JOB_MAP_ROW_OFFSETS+=("${#JOB_MAP_CELLS[@]}")
  JOB_MAP_ROW_STATUSES+=("$status")
  if [ "$status" = "$JOB_MAP_PARSE_OK" ]; then
    JOB_MAP_ROW_CELL_COUNTS+=("${#CSV_CELLS[@]}")
    JOB_MAP_CELLS+=("${CSV_CELLS[@]}")
  else
    JOB_MAP_ROW_CELL_COUNTS+=(0)
  fi
}

# データ行数(コメント・空行・ヘッダー行を除く。計算ルール「行数集計」)
job_map_repo_row_count() {
  printf '%s\n' "${#JOB_MAP_ROW_LINES[@]}"
}

# row_index(0 始まり)のデータ行のセルを JOB_MAP_ROW に取り出す(JOB_MAP_ROW は呼び出し元が読む)
# shellcheck disable=SC2034
job_map_repo_row() {
  local row_index="$1"
  local offset="${JOB_MAP_ROW_OFFSETS[$row_index]}" count="${JOB_MAP_ROW_CELL_COUNTS[$row_index]}"
  local cell_index=0
  JOB_MAP_ROW=()
  # 配列スライス(${array[@]:offset:count})は先頭から offset まで走査するため、行数の 2 乗の時間がかかる。添字で取り出す
  while [ "$cell_index" -lt "$count" ]; do
    JOB_MAP_ROW+=("${JOB_MAP_CELLS[offset + cell_index]}")
    cell_index=$((cell_index + 1))
  done
}
