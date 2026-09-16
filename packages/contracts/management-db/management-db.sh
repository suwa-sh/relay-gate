#!/usr/bin/env bash
# shellcheck disable=SC2034  # 定数は source 先で参照する(このファイル内では未使用)
# contract-codegen: from rdb-schema.yaml scope={parallel_runs, slot_executions, rapid_runs, rapid_crosscheck_requests, comparison_results, final_crosscheck_requests, monitor_records}
# 生成物。直接編集禁止(再生成は bootstrap P4 / S3 のみ)。source: docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml
# provider: tier-ops / consumers: tier-facade, tier-rapid-crosscheck, tier-final-crosscheck
# 使い方: source "$(dirname "${BASH_SOURCE[0]}")/management-db.sh" してテーブル名・列名・列挙値の定数を参照する。
# 型は抽象型(string / integer / text / datetime / date / boolean)。DDL / migration は datastore_owner(tier-ops)の資産が正本。

# ---- parallel_runs: 並行稼働実行(parallel_run)
readonly RG_TABLE_PARALLEL_RUNS="parallel_runs"
readonly RG_PK_PARALLEL_RUNS="run_id"
readonly RG_COLUMNS_PARALLEL_RUNS="run_id parent_run_id job_id parameters execution_spec_uri status requested_at completed_at"
# run_id: string
readonly RG_COL_PARALLEL_RUNS_RUN_ID="run_id"
# parent_run_id: string nullable
readonly RG_COL_PARALLEL_RUNS_PARENT_RUN_ID="parent_run_id"
# job_id: string
readonly RG_COL_PARALLEL_RUNS_JOB_ID="job_id"
# parameters: text
readonly RG_COL_PARALLEL_RUNS_PARAMETERS="parameters"
# execution_spec_uri: string
readonly RG_COL_PARALLEL_RUNS_EXECUTION_SPEC_URI="execution_spec_uri"
# status: string
readonly RG_COL_PARALLEL_RUNS_STATUS="status"
readonly RG_ENUM_PARALLEL_RUNS_STATUS="STARTED RUNNING COMPLETED ABORTED"
readonly RG_PARALLEL_RUNS_STATUS_STARTED="STARTED"
readonly RG_PARALLEL_RUNS_STATUS_RUNNING="RUNNING"
readonly RG_PARALLEL_RUNS_STATUS_COMPLETED="COMPLETED"
readonly RG_PARALLEL_RUNS_STATUS_ABORTED="ABORTED"
# requested_at: datetime
readonly RG_COL_PARALLEL_RUNS_REQUESTED_AT="requested_at"
# completed_at: datetime nullable
readonly RG_COL_PARALLEL_RUNS_COMPLETED_AT="completed_at"

# ---- slot_executions: slot 実行
readonly RG_TABLE_SLOT_EXECUTIONS="slot_executions"
readonly RG_PK_SLOT_EXECUTIONS="run_id slot"
readonly RG_COLUMNS_SLOT_EXECUTIONS="run_id slot mode pid artifact_dir status exit_code started_at completed_at"
# run_id: string
readonly RG_COL_SLOT_EXECUTIONS_RUN_ID="run_id"
# slot: string
readonly RG_COL_SLOT_EXECUTIONS_SLOT="slot"
readonly RG_ENUM_SLOT_EXECUTIONS_SLOT="blue green"
readonly RG_SLOT_EXECUTIONS_SLOT_BLUE="blue"
readonly RG_SLOT_EXECUTIONS_SLOT_GREEN="green"
# mode: string
readonly RG_COL_SLOT_EXECUTIONS_MODE="mode"
readonly RG_ENUM_SLOT_EXECUTIONS_MODE="foreground background"
readonly RG_SLOT_EXECUTIONS_MODE_FOREGROUND="foreground"
readonly RG_SLOT_EXECUTIONS_MODE_BACKGROUND="background"
# pid: integer nullable
readonly RG_COL_SLOT_EXECUTIONS_PID="pid"
# artifact_dir: string
readonly RG_COL_SLOT_EXECUTIONS_ARTIFACT_DIR="artifact_dir"
# status: string
readonly RG_COL_SLOT_EXECUTIONS_STATUS="status"
readonly RG_ENUM_SLOT_EXECUTIONS_STATUS="RUNNING SUCCEEDED FAILED ABORTED"
readonly RG_SLOT_EXECUTIONS_STATUS_RUNNING="RUNNING"
readonly RG_SLOT_EXECUTIONS_STATUS_SUCCEEDED="SUCCEEDED"
readonly RG_SLOT_EXECUTIONS_STATUS_FAILED="FAILED"
readonly RG_SLOT_EXECUTIONS_STATUS_ABORTED="ABORTED"
# exit_code: integer nullable
readonly RG_COL_SLOT_EXECUTIONS_EXIT_CODE="exit_code"
# started_at: datetime
readonly RG_COL_SLOT_EXECUTIONS_STARTED_AT="started_at"
# completed_at: datetime nullable
readonly RG_COL_SLOT_EXECUTIONS_COMPLETED_AT="completed_at"

# ---- rapid_runs: 速報実行(rapid_run)
readonly RG_TABLE_RAPID_RUNS="rapid_runs"
readonly RG_PK_RAPID_RUNS="run_id"
readonly RG_COLUMNS_RAPID_RUNS="run_id blue_status green_status blue_artifact_uri green_artifact_uri blue_completed_at green_completed_at completion_status"
# run_id: string
readonly RG_COL_RAPID_RUNS_RUN_ID="run_id"
# blue_status: string nullable
readonly RG_COL_RAPID_RUNS_BLUE_STATUS="blue_status"
readonly RG_ENUM_RAPID_RUNS_BLUE_STATUS="SUCCEEDED FAILED"
readonly RG_RAPID_RUNS_BLUE_STATUS_SUCCEEDED="SUCCEEDED"
readonly RG_RAPID_RUNS_BLUE_STATUS_FAILED="FAILED"
# green_status: string nullable
readonly RG_COL_RAPID_RUNS_GREEN_STATUS="green_status"
readonly RG_ENUM_RAPID_RUNS_GREEN_STATUS="SUCCEEDED FAILED"
readonly RG_RAPID_RUNS_GREEN_STATUS_SUCCEEDED="SUCCEEDED"
readonly RG_RAPID_RUNS_GREEN_STATUS_FAILED="FAILED"
# blue_artifact_uri: string nullable
readonly RG_COL_RAPID_RUNS_BLUE_ARTIFACT_URI="blue_artifact_uri"
# green_artifact_uri: string nullable
readonly RG_COL_RAPID_RUNS_GREEN_ARTIFACT_URI="green_artifact_uri"
# blue_completed_at: datetime nullable
readonly RG_COL_RAPID_RUNS_BLUE_COMPLETED_AT="blue_completed_at"
# green_completed_at: datetime nullable
readonly RG_COL_RAPID_RUNS_GREEN_COMPLETED_AT="green_completed_at"
# completion_status: string
readonly RG_COL_RAPID_RUNS_COMPLETION_STATUS="completion_status"
readonly RG_ENUM_RAPID_RUNS_COMPLETION_STATUS="PENDING ONE_COMPLETED BOTH_SUCCEEDED ANY_FAILED REQUEST_CREATED"
readonly RG_RAPID_RUNS_COMPLETION_STATUS_PENDING="PENDING"
readonly RG_RAPID_RUNS_COMPLETION_STATUS_ONE_COMPLETED="ONE_COMPLETED"
readonly RG_RAPID_RUNS_COMPLETION_STATUS_BOTH_SUCCEEDED="BOTH_SUCCEEDED"
readonly RG_RAPID_RUNS_COMPLETION_STATUS_ANY_FAILED="ANY_FAILED"
readonly RG_RAPID_RUNS_COMPLETION_STATUS_REQUEST_CREATED="REQUEST_CREATED"

# ---- rapid_crosscheck_requests: 速報比較依頼(rapid_crosscheck_request)
readonly RG_TABLE_RAPID_CROSSCHECK_REQUESTS="rapid_crosscheck_requests"
readonly RG_PK_RAPID_CROSSCHECK_REQUESTS="run_id"
readonly RG_COLUMNS_RAPID_CROSSCHECK_REQUESTS="run_id job_id status worker_id lease_until requested_at started_at completed_at exit_code stdout stderr error_summary"
# run_id: string
readonly RG_COL_RAPID_CROSSCHECK_REQUESTS_RUN_ID="run_id"
# job_id: string
readonly RG_COL_RAPID_CROSSCHECK_REQUESTS_JOB_ID="job_id"
# status: string
readonly RG_COL_RAPID_CROSSCHECK_REQUESTS_STATUS="status"
readonly RG_ENUM_RAPID_CROSSCHECK_REQUESTS_STATUS="REQUESTED CLAIMED RUNNING SUCCEEDED FAILED ABORTED"
readonly RG_RAPID_CROSSCHECK_REQUESTS_STATUS_REQUESTED="REQUESTED"
readonly RG_RAPID_CROSSCHECK_REQUESTS_STATUS_CLAIMED="CLAIMED"
readonly RG_RAPID_CROSSCHECK_REQUESTS_STATUS_RUNNING="RUNNING"
readonly RG_RAPID_CROSSCHECK_REQUESTS_STATUS_SUCCEEDED="SUCCEEDED"
readonly RG_RAPID_CROSSCHECK_REQUESTS_STATUS_FAILED="FAILED"
readonly RG_RAPID_CROSSCHECK_REQUESTS_STATUS_ABORTED="ABORTED"
# worker_id: string nullable
readonly RG_COL_RAPID_CROSSCHECK_REQUESTS_WORKER_ID="worker_id"
# lease_until: datetime nullable
readonly RG_COL_RAPID_CROSSCHECK_REQUESTS_LEASE_UNTIL="lease_until"
# requested_at: datetime
readonly RG_COL_RAPID_CROSSCHECK_REQUESTS_REQUESTED_AT="requested_at"
# started_at: datetime nullable
readonly RG_COL_RAPID_CROSSCHECK_REQUESTS_STARTED_AT="started_at"
# completed_at: datetime nullable
readonly RG_COL_RAPID_CROSSCHECK_REQUESTS_COMPLETED_AT="completed_at"
# exit_code: integer nullable
readonly RG_COL_RAPID_CROSSCHECK_REQUESTS_EXIT_CODE="exit_code"
# stdout: text nullable
readonly RG_COL_RAPID_CROSSCHECK_REQUESTS_STDOUT="stdout"
# stderr: text nullable
readonly RG_COL_RAPID_CROSSCHECK_REQUESTS_STDERR="stderr"
# error_summary: string nullable
readonly RG_COL_RAPID_CROSSCHECK_REQUESTS_ERROR_SUMMARY="error_summary"

# ---- comparison_results: 比較結果(comparison_result)
readonly RG_TABLE_COMPARISON_RESULTS="comparison_results"
readonly RG_PK_COMPARISON_RESULTS="comparison_result_id"
readonly RG_COLUMNS_COMPARISON_RESULTS="comparison_result_id run_id comparison_type status difference_count report_uri compared_at"
# comparison_result_id: string
readonly RG_COL_COMPARISON_RESULTS_COMPARISON_RESULT_ID="comparison_result_id"
# run_id: string
readonly RG_COL_COMPARISON_RESULTS_RUN_ID="run_id"
# comparison_type: string
readonly RG_COL_COMPARISON_RESULTS_COMPARISON_TYPE="comparison_type"
readonly RG_ENUM_COMPARISON_RESULTS_COMPARISON_TYPE="job full"
readonly RG_COMPARISON_RESULTS_COMPARISON_TYPE_JOB="job"
readonly RG_COMPARISON_RESULTS_COMPARISON_TYPE_FULL="full"
# status: string
readonly RG_COL_COMPARISON_RESULTS_STATUS="status"
readonly RG_ENUM_COMPARISON_RESULTS_STATUS="OK NG FAILED"
readonly RG_COMPARISON_RESULTS_STATUS_OK="OK"
readonly RG_COMPARISON_RESULTS_STATUS_NG="NG"
readonly RG_COMPARISON_RESULTS_STATUS_FAILED="FAILED"
# difference_count: integer nullable
readonly RG_COL_COMPARISON_RESULTS_DIFFERENCE_COUNT="difference_count"
# report_uri: string nullable
readonly RG_COL_COMPARISON_RESULTS_REPORT_URI="report_uri"
# compared_at: datetime
readonly RG_COL_COMPARISON_RESULTS_COMPARED_AT="compared_at"

# ---- final_crosscheck_requests: 確報比較依頼(final_crosscheck_request)
readonly RG_TABLE_FINAL_CROSSCHECK_REQUESTS="final_crosscheck_requests"
readonly RG_PK_FINAL_CROSSCHECK_REQUESTS="final_crosscheck_id"
readonly RG_COLUMNS_FINAL_CROSSCHECK_REQUESTS="final_crosscheck_id business_date catalog_version status worker_id lease_until requested_at started_at completed_at exit_code stdout stderr error_summary"
# final_crosscheck_id: string
readonly RG_COL_FINAL_CROSSCHECK_REQUESTS_FINAL_CROSSCHECK_ID="final_crosscheck_id"
# business_date: date
readonly RG_COL_FINAL_CROSSCHECK_REQUESTS_BUSINESS_DATE="business_date"
# catalog_version: string
readonly RG_COL_FINAL_CROSSCHECK_REQUESTS_CATALOG_VERSION="catalog_version"
# status: string
readonly RG_COL_FINAL_CROSSCHECK_REQUESTS_STATUS="status"
readonly RG_ENUM_FINAL_CROSSCHECK_REQUESTS_STATUS="REQUESTED CLAIMED RUNNING SUCCEEDED FAILED ABORTED"
readonly RG_FINAL_CROSSCHECK_REQUESTS_STATUS_REQUESTED="REQUESTED"
readonly RG_FINAL_CROSSCHECK_REQUESTS_STATUS_CLAIMED="CLAIMED"
readonly RG_FINAL_CROSSCHECK_REQUESTS_STATUS_RUNNING="RUNNING"
readonly RG_FINAL_CROSSCHECK_REQUESTS_STATUS_SUCCEEDED="SUCCEEDED"
readonly RG_FINAL_CROSSCHECK_REQUESTS_STATUS_FAILED="FAILED"
readonly RG_FINAL_CROSSCHECK_REQUESTS_STATUS_ABORTED="ABORTED"
# worker_id: string nullable
readonly RG_COL_FINAL_CROSSCHECK_REQUESTS_WORKER_ID="worker_id"
# lease_until: datetime nullable
readonly RG_COL_FINAL_CROSSCHECK_REQUESTS_LEASE_UNTIL="lease_until"
# requested_at: datetime
readonly RG_COL_FINAL_CROSSCHECK_REQUESTS_REQUESTED_AT="requested_at"
# started_at: datetime nullable
readonly RG_COL_FINAL_CROSSCHECK_REQUESTS_STARTED_AT="started_at"
# completed_at: datetime nullable
readonly RG_COL_FINAL_CROSSCHECK_REQUESTS_COMPLETED_AT="completed_at"
# exit_code: integer nullable
readonly RG_COL_FINAL_CROSSCHECK_REQUESTS_EXIT_CODE="exit_code"
# stdout: text nullable
readonly RG_COL_FINAL_CROSSCHECK_REQUESTS_STDOUT="stdout"
# stderr: text nullable
readonly RG_COL_FINAL_CROSSCHECK_REQUESTS_STDERR="stderr"
# error_summary: string nullable
readonly RG_COL_FINAL_CROSSCHECK_REQUESTS_ERROR_SUMMARY="error_summary"

# ---- monitor_records: 監視記録
readonly RG_TABLE_MONITOR_RECORDS="monitor_records"
readonly RG_PK_MONITOR_RECORDS="run_id role"
readonly RG_COLUMNS_MONITOR_RECORDS="run_id role target_type job_id monitor_status started_at elapsed_minutes hang_detect_limit_minutes hang_suspected_at alerted_at elapsed_minutes_at_alert judged_at"
# run_id: string
readonly RG_COL_MONITOR_RECORDS_RUN_ID="run_id"
# role: string
readonly RG_COL_MONITOR_RECORDS_ROLE="role"
readonly RG_ENUM_MONITOR_RECORDS_ROLE="blue green rapid-crosscheck"
readonly RG_MONITOR_RECORDS_ROLE_BLUE="blue"
readonly RG_MONITOR_RECORDS_ROLE_GREEN="green"
readonly RG_MONITOR_RECORDS_ROLE_RAPID_CROSSCHECK="rapid-crosscheck"
# target_type: string
readonly RG_COL_MONITOR_RECORDS_TARGET_TYPE="target_type"
readonly RG_ENUM_MONITOR_RECORDS_TARGET_TYPE="background_slot rapid_request"
readonly RG_MONITOR_RECORDS_TARGET_TYPE_BACKGROUND_SLOT="background_slot"
readonly RG_MONITOR_RECORDS_TARGET_TYPE_RAPID_REQUEST="rapid_request"
# job_id: string
readonly RG_COL_MONITOR_RECORDS_JOB_ID="job_id"
# monitor_status: string
readonly RG_COL_MONITOR_RECORDS_MONITOR_STATUS="monitor_status"
readonly RG_ENUM_MONITOR_RECORDS_MONITOR_STATUS="NOT_MONITORED MONITORING HANG_SUSPECTED_NOTIFIED EXEC_ERROR_NOTIFIED COMPARE_ERROR_NOTIFIED COMPLETED"
readonly RG_MONITOR_RECORDS_MONITOR_STATUS_NOT_MONITORED="NOT_MONITORED"
readonly RG_MONITOR_RECORDS_MONITOR_STATUS_MONITORING="MONITORING"
readonly RG_MONITOR_RECORDS_MONITOR_STATUS_HANG_SUSPECTED_NOTIFIED="HANG_SUSPECTED_NOTIFIED"
readonly RG_MONITOR_RECORDS_MONITOR_STATUS_EXEC_ERROR_NOTIFIED="EXEC_ERROR_NOTIFIED"
readonly RG_MONITOR_RECORDS_MONITOR_STATUS_COMPARE_ERROR_NOTIFIED="COMPARE_ERROR_NOTIFIED"
readonly RG_MONITOR_RECORDS_MONITOR_STATUS_COMPLETED="COMPLETED"
# started_at: datetime
readonly RG_COL_MONITOR_RECORDS_STARTED_AT="started_at"
# elapsed_minutes: integer
readonly RG_COL_MONITOR_RECORDS_ELAPSED_MINUTES="elapsed_minutes"
# hang_detect_limit_minutes: integer
readonly RG_COL_MONITOR_RECORDS_HANG_DETECT_LIMIT_MINUTES="hang_detect_limit_minutes"
# hang_suspected_at: datetime nullable
readonly RG_COL_MONITOR_RECORDS_HANG_SUSPECTED_AT="hang_suspected_at"
# alerted_at: datetime nullable
readonly RG_COL_MONITOR_RECORDS_ALERTED_AT="alerted_at"
# elapsed_minutes_at_alert: integer nullable
readonly RG_COL_MONITOR_RECORDS_ELAPSED_MINUTES_AT_ALERT="elapsed_minutes_at_alert"
# judged_at: datetime
readonly RG_COL_MONITOR_RECORDS_JUDGED_AT="judged_at"
