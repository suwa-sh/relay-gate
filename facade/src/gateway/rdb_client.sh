#!/usr/bin/env bash
# gateway: RdbClientAdapter(ジョブキュー兼管理 DB への RDB クライアント CLI 呼び出し)。
# 仕様: spec.md「データフロー」gateway 行(RDB クライアント CLI 呼び出し)/ _cross-cutting/api/cli-command-contract.yaml
#       conventions.credentials(接続情報の値は持たず参照名だけを置く。参照名から接続情報への解決は DB クライアントの接続設定に委ねる。
#       relay-gate は値を保存・出力しない)/ conventions.datetime_generation(日時はホストで作りバインド値で渡す)
# 呼び出し方(仕様に定めが無く、実装で決めた前提。AssumptionRecord):
#   - クライアントは PATH の psql。参照名は接続サービス名として `service=<参照名>` で渡す(接続先は pg_service.conf 等の
#     クライアントの接続設定が決める)。~/.psqlrc は読まない(-X)
#   - SQL は標準入力で渡し、値は psql の変数(-v name=value)で渡して SQL の中では :'name'(文字列のリテラル)で参照する
#     (値を SQL の文字列へ連結しない)。1 回の呼び出しは 1 トランザクション(--single-transaction)で、最初の失敗で止める
#   - psql の stderr は捨てる(接続先のソケット・ホスト・ポートなど、参照名から解決した接続情報が含まれるため)
#   - psql の終了コード: 2 = 接続できない、3 = SQL の失敗(ON_ERROR_STOP)。PATH に無い・起動できないときも接続できないとして扱う

RDB_CLIENT_COMMAND="psql"
# rdb_client_run の戻り値
RDB_CLIENT_STATUS_OK=0
RDB_CLIENT_STATUS_CONNECTION_FAILED=1
RDB_CLIENT_STATUS_SQL_FAILED=2
# rdb_client_require_rows の戻り値(RETURNING で受け取る行が 0 件)
RDB_CLIENT_STATUS_NO_ROWS=3
# psql の終了コード(接続できない)
RDB_CLIENT_PSQL_EXIT_CONNECTION=2

# rdb_client_run の stdout(\echo などの出力。-At で整形なし)
RDB_CLIENT_OUTPUT=""

# 参照名を libpq の接続文字列の値として引用する(`\` と `'` の前に `\` を付けて '...' で囲む)
# 引数: conn_ref
RDB_CLIENT_CONNINFO=""
rdb_client_conninfo() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\'/\\\'}"
  RDB_CLIENT_CONNINFO="service='$value'"
}

# SQL を 1 トランザクションで実行する
# 引数: conn_ref sql [name=value ...](psql の変数。SQL の中では :'name' で参照する)
# 戻り値: RDB_CLIENT_STATUS_OK / RDB_CLIENT_STATUS_CONNECTION_FAILED / RDB_CLIENT_STATUS_SQL_FAILED
rdb_client_run() {
  local conn_ref="$1" sql="$2" status=0 assignment
  local -a variables=()
  shift 2
  for assignment in "$@"; do
    variables+=(-v "$assignment")
  done
  rdb_client_conninfo "$conn_ref"
  # SQL は here-string で渡す(パイプにしない。接続に失敗した psql が標準入力を読まずに終わっても、前段の書き込みエラーを出さない)
  # shellcheck disable=SC2034  # 結果のグローバル(呼び出し元が読む)
  RDB_CLIENT_OUTPUT="$("$RDB_CLIENT_COMMAND" -X -q -A -t -v ON_ERROR_STOP=1 --single-transaction -f - \
    ${variables[@]+"${variables[@]}"} "$RDB_CLIENT_CONNINFO" 2>/dev/null <<<"$sql")" || status=$?
  if [ "$status" -eq 0 ]; then
    return "$RDB_CLIENT_STATUS_OK"
  fi
  if [ "$status" -eq "$RDB_CLIENT_PSQL_EXIT_CONNECTION" ] || [ "$status" -ge 126 ]; then
    return "$RDB_CLIENT_STATUS_CONNECTION_FAILED"
  fi
  return "$RDB_CLIENT_STATUS_SQL_FAILED"
}

# 直前の rdb_client_run の出力(RETURNING の行)が 1 行以上あるかを返す(UPDATE が 0 件だったかの判定)
# 戻り値: RDB_CLIENT_STATUS_OK / RDB_CLIENT_STATUS_NO_ROWS
rdb_client_require_rows() {
  if [ -n "$RDB_CLIENT_OUTPUT" ]; then
    return "$RDB_CLIENT_STATUS_OK"
  fi
  return "$RDB_CLIENT_STATUS_NO_ROWS"
}
