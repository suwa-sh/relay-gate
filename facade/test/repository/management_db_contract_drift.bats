#!/usr/bin/env bats
# UC 09730858(slot 実行モードを選択して runner を起動する)× tier-facade: 管理 DB の SQL と契約の生成物の一致(ドリフトテスト)。
# facade の repository は表名・列名・列挙値を SQL に直接書く(facade の配置の外にある packages/ を実行時に読まないため)。
# その複製が契約 management-db の生成物(packages/contracts/management-db/management-db.sh の定数)とずれていないことを、
# repository の関数が送る SQL を記録して確かめる。生成物が見つからない複製先(facade だけを複製した環境など)では fail にする。

bats_require_minimum_version 1.5.0

CONTRACT_FILE="$BATS_TEST_DIRNAME/../../../packages/contracts/management-db/management-db.sh"

setup() {
	[ -f "$CONTRACT_FILE" ] || {
		echo "contract constants not found: $CONTRACT_FILE" >&2
		return 1
	}
	# shellcheck source=/dev/null
	source "$CONTRACT_FILE"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/gateway/rdb_client.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/repository/parallel_run_repo.sh"
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/repository/slot_execution_repo.sh"
	SQL_LOG=()
	# psql を呼ばずに SQL だけを記録する(RETURNING の行は 1 行返す)
	rdb_client_run() {
		SQL_LOG+=("$2")
		RDB_CLIENT_OUTPUT="row"
		return 0
	}
}

# INSERT 文の列の並び(空白区切り)を INSERT_COLUMNS に載せる
# 引数: sql table
insert_columns_of() {
	local sql="${1//$'\n'/ }" table="$2" rest
	rest="${sql#*INSERT INTO "$table" (}"
	[ "$rest" != "$sql" ] || return 1
	rest="${rest%%)*}"
	INSERT_COLUMNS="${rest//, / }"
}

# 単語が空白区切りの一覧に含まれるか
# 引数: word list
in_list() {
	case " $2 " in
	*" $1 "*) return 0 ;;
	esac
	return 1
}

@test "parallel_run_repo_create_with_rapid_run_INSERTの表と列の並びと列挙値が契約の生成物と同じであること" {
	# Act
	parallel_run_repo_create_with_rapid_run ref run job "[]" uri at

	# Assert
	insert_columns_of "${SQL_LOG[0]}" "$RG_TABLE_PARALLEL_RUNS"
	[ "$INSERT_COLUMNS" = "$RG_COLUMNS_PARALLEL_RUNS" ]
	[[ "${SQL_LOG[0]}" == *"'$RG_PARALLEL_RUNS_STATUS_STARTED'"* ]]
	insert_columns_of "${SQL_LOG[0]}" "$RG_TABLE_RAPID_RUNS"
	[ "$INSERT_COLUMNS" = "$RG_COLUMNS_RAPID_RUNS" ]
	[[ "${SQL_LOG[0]}" == *"'$RG_RAPID_RUNS_COMPLETION_STATUS_PENDING'"* ]]
}

@test "slot_execution_repo_create_INSERTの表と列の並びと列挙値が契約の生成物と同じであること" {
	# Act
	slot_execution_repo_create ref run green background dir at

	# Assert
	insert_columns_of "${SQL_LOG[0]}" "$RG_TABLE_SLOT_EXECUTIONS"
	[ "$INSERT_COLUMNS" = "$RG_COLUMNS_SLOT_EXECUTIONS" ]
	[[ "${SQL_LOG[0]}" == *"'$RG_SLOT_EXECUTIONS_STATUS_RUNNING'"* ]]
}

@test "状態とpidのUPDATE_表と更新する列と条件の列挙値が契約の生成物にあること" {
	# Act
	parallel_run_repo_mark_running ref run
	slot_execution_repo_set_pid ref run green 1
	slot_execution_repo_mark_failed ref run green at

	# Assert
	[[ "${SQL_LOG[0]}" == "UPDATE $RG_TABLE_PARALLEL_RUNS SET $RG_COL_PARALLEL_RUNS_STATUS = '$RG_PARALLEL_RUNS_STATUS_RUNNING' WHERE $RG_COL_PARALLEL_RUNS_RUN_ID = :'run_id' AND $RG_COL_PARALLEL_RUNS_STATUS = '$RG_PARALLEL_RUNS_STATUS_STARTED' "* ]]
	[[ "${SQL_LOG[1]}" == "UPDATE $RG_TABLE_SLOT_EXECUTIONS SET $RG_COL_SLOT_EXECUTIONS_PID = "* ]]
	[[ "${SQL_LOG[1]}" == *"WHERE $RG_COL_SLOT_EXECUTIONS_RUN_ID = :'run_id' AND $RG_COL_SLOT_EXECUTIONS_SLOT = :'slot' "* ]]
	[[ "${SQL_LOG[2]}" == "UPDATE $RG_TABLE_SLOT_EXECUTIONS SET $RG_COL_SLOT_EXECUTIONS_STATUS = '$RG_SLOT_EXECUTIONS_STATUS_FAILED', $RG_COL_SLOT_EXECUTIONS_COMPLETED_AT = "* ]]
	[[ "${SQL_LOG[2]}" == *"AND $RG_COL_SLOT_EXECUTIONS_STATUS = '$RG_SLOT_EXECUTIONS_STATUS_RUNNING';" ]]
	in_list "$RG_PARALLEL_RUNS_STATUS_RUNNING" "$RG_ENUM_PARALLEL_RUNS_STATUS"
	in_list "$RG_SLOT_EXECUTIONS_STATUS_FAILED" "$RG_ENUM_SLOT_EXECUTIONS_STATUS"
}
