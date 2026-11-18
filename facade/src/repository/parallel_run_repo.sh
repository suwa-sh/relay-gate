#!/usr/bin/env bash
# repository: ParallelRunRepository / RapidRunRepository(並行稼働実行 parallel_runs と速報実行 rapid_runs)。
# 仕様: _model-summary.yaml tables(parallel_runs の INSERT(STARTED)と条件付き UPDATE(RUNNING)、rapid_runs の INSERT(PENDING))/
#       tier-facade.md「UC ロジック」起動順序 2・5(parallel_runs と rapid_runs の INSERT は同一トランザクション。canonical C3)/
#       契約 management-db(rdb-schema.yaml の parallel_runs / rapid_runs の列と列挙値)
# 日時はホストで作った値をバインド値で渡す(SQL の now() は使わない。conventions.datetime_generation)。
# 依存: gateway/rdb_client.sh

# 失敗した INSERT の表の名前(SQL の失敗のとき。どの文で止まったかを、文の前に出す \echo の最後の行で知る)
PARALLEL_RUN_REPO_FAILED_TABLE=""
# 文の前に出す印(\echo)の接頭辞
PARALLEL_RUN_REPO_STEP_PREFIX="table="

# 実行した SQL の出力(\echo の行)から、最後に始めた文の表の名前を PARALLEL_RUN_REPO_FAILED_TABLE に載せる
# 引数: output default_table(印が無いときの表の名前)
parallel_run_repo_last_step_table() {
  local line table="$2"
  while IFS= read -r line; do
    case "$line" in
      "$PARALLEL_RUN_REPO_STEP_PREFIX"*) table="${line#"$PARALLEL_RUN_REPO_STEP_PREFIX"}" ;;
    esac
  done <<<"$1"
  PARALLEL_RUN_REPO_FAILED_TABLE="$table"
}

# parallel_runs を STARTED で、rapid_runs を completion_status=PENDING で、同一トランザクションで作る
# 引数: conn_ref run_id job_id parameters(JSON 配列の文字列) execution_spec_uri requested_at(ローカル日時)
# 戻り値: rdb_client_run と同じ(SQL の失敗のときは PARALLEL_RUN_REPO_FAILED_TABLE に表の名前)
parallel_run_repo_create_with_rapid_run() {
  local status=0 sql
  sql="\\echo ${PARALLEL_RUN_REPO_STEP_PREFIX}parallel_runs
INSERT INTO parallel_runs (run_id, parent_run_id, job_id, parameters, execution_spec_uri, status, requested_at, completed_at)
VALUES (:'run_id', NULL, :'job_id', :'parameters', :'execution_spec_uri', 'STARTED', :'requested_at', NULL);
\\echo ${PARALLEL_RUN_REPO_STEP_PREFIX}rapid_runs
INSERT INTO rapid_runs (run_id, blue_status, green_status, blue_completed_at, green_completed_at, completion_status)
VALUES (:'run_id', NULL, NULL, NULL, NULL, 'PENDING');"
  # shellcheck disable=SC2034  # 結果のグローバル(呼び出し元が読む)
  PARALLEL_RUN_REPO_FAILED_TABLE=""
  rdb_client_run "$1" "$sql" "run_id=$2" "job_id=$3" "parameters=$4" "execution_spec_uri=$5" "requested_at=$6" || status=$?
  if [ "$status" -eq "$RDB_CLIENT_STATUS_SQL_FAILED" ]; then
    parallel_run_repo_last_step_table "$RDB_CLIENT_OUTPUT" parallel_runs
  fi
  return "$status"
}

# 並行稼働実行の状態遷移 STARTED → RUNNING(条件付き UPDATE。WHERE run_id=? AND status='STARTED')。
# 更新した行は RETURNING で受け取り、条件に合う行が無く 0 件だったときは遷移していないとして返す(0 件を成功にしない)
# 引数: conn_ref run_id
# 戻り値: rdb_client_run と同じ / RDB_CLIENT_STATUS_NO_ROWS … 0 件
parallel_run_repo_mark_running() {
  rdb_client_run "$1" "UPDATE parallel_runs SET status = 'RUNNING' WHERE run_id = :'run_id' AND status = 'STARTED' RETURNING run_id;" \
    "run_id=$2" || return $?
  rdb_client_require_rows
}
