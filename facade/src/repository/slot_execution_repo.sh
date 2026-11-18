#!/usr/bin/env bash
# repository: SlotExecutionRepository(slot 実行 slot_executions)。
# 仕様: _model-summary.yaml tables.slot_executions(runner 起動前の INSERT(status=RUNNING, pid=NULL)/ 起動後の pid の UPDATE /
#       起動失敗時のベストエフォートの UPDATE(FAILED))/ tier-facade.md「UC ロジック」起動順序 3・4 とエラーハンドリング /
#       契約 management-db(rdb-schema.yaml の slot_executions の列と列挙値)
# 日時はホストで作った値をバインド値で渡す(SQL の now() は使わない。conventions.datetime_generation)。
# 依存: gateway/rdb_client.sh

# runner 起動前に slot 実行を RUNNING(pid=NULL)で作る
# 引数: conn_ref run_id slot mode artifact_dir started_at(ローカル日時)
slot_execution_repo_create() {
  rdb_client_run "$1" "INSERT INTO slot_executions (run_id, slot, mode, pid, artifact_dir, status, exit_code, started_at, completed_at)
VALUES (:'run_id', :'slot', :'mode', NULL, :'artifact_dir', 'RUNNING', NULL, :'started_at', NULL);" \
    "run_id=$2" "slot=$3" "mode=$4" "artifact_dir=$5" "started_at=$6"
}

# runner 起動後に PID を設定する(WHERE run_id=? AND slot=?)。更新した行は RETURNING で受け取り、0 件は設定できなかったとして返す
# 引数: conn_ref run_id slot pid
# 戻り値: rdb_client_run と同じ / RDB_CLIENT_STATUS_NO_ROWS … 0 件
slot_execution_repo_set_pid() {
  rdb_client_run "$1" "UPDATE slot_executions SET pid = CAST(:'pid' AS integer) WHERE run_id = :'run_id' AND slot = :'slot' RETURNING slot;" \
    "run_id=$2" "slot=$3" "pid=$4" || return $?
  rdb_client_require_rows
}

# runner の起動に失敗した slot 実行を FAILED で閉じる(WHERE run_id=? AND slot=? AND status='RUNNING')
# 引数: conn_ref run_id slot completed_at(ローカル日時)
slot_execution_repo_mark_failed() {
  rdb_client_run "$1" "UPDATE slot_executions SET status = 'FAILED', completed_at = :'completed_at'
WHERE run_id = :'run_id' AND slot = :'slot' AND status = 'RUNNING';" \
    "run_id=$2" "slot=$3" "completed_at=$4"
}
