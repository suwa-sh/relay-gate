#!/usr/bin/env bats
# UC 09730858(slot 実行モードを選択して runner を起動する)× tier-facade: domain/slot_launch_plan.sh の単体テスト。
# 対象: spec.md「計算ルール一覧」(起動計画 / run_id 発行 / parameters(JSON)/ 成果物ディレクトリ)と
#       「分岐条件一覧」(slot 起動可否判定 / slot 起動順序)。

setup() {
	local src="$BATS_TEST_DIRNAME/../../src/domain"
	# shellcheck source=/dev/null
	source "$src/feature_flag.sh"
	# shellcheck source=/dev/null
	source "$src/job_map.sh"
	# shellcheck source=/dev/null
	source "$src/slot_launch_plan.sh"
}

@test "plan_slot_launch_blueがforegroundでgreenがbackgroundの場合_greenを先にblueを後に起動する計画であること" {
	# Act
	plan_slot_launch foreground background

	# Assert
	[ "${SLOT_LAUNCH_PLAN_BACKGROUND[*]}" = "green" ]
	[ "$SLOT_LAUNCH_PLAN_FOREGROUND" = "blue" ]
	[ "${SLOT_LAUNCH_PLAN_ORDER[*]}" = "green blue" ]
}

@test "plan_slot_launch_blueがbackgroundでgreenがforegroundの場合_blueを先にgreenを後に起動する計画であること" {
	# Act
	plan_slot_launch background foreground

	# Assert
	[ "${SLOT_LAUNCH_PLAN_ORDER[*]}" = "blue green" ]
	[ "$SLOT_LAUNCH_PLAN_FOREGROUND" = "green" ]
	[ "$(slot_launch_plan_mode_of blue)" = "background" ]
	[ "$(slot_launch_plan_mode_of green)" = "foreground" ]
}

@test "plan_slot_launch_offのslotがある場合_offのslotを計画に含めないこと" {
	# Act
	plan_slot_launch off foreground

	# Assert
	[ "${#SLOT_LAUNCH_PLAN_BACKGROUND[@]}" -eq 0 ]
	[ "${SLOT_LAUNCH_PLAN_ORDER[*]}" = "green" ]
}

@test "slot_launch_run_id_時刻部とjob_idとhexの場合_ハイフンでつないだrun_idであること" {
	# Act
	slot_launch_run_id 20260830T113000 JOB001 3f9a1c2e

	# Assert
	[ "$SLOT_LAUNCH_RUN_ID" = "20260830T113000-JOB001-3f9a1c2e" ]
}

@test "slot_launch_hex8_is_valid_小文字の16進8桁だけの場合_通すこと" {
	# Act / Assert
	slot_launch_hex8_is_valid 3f9a1c2e
	run slot_launch_hex8_is_valid 3F9A1C2E
	[ "$status" -ne 0 ]
	run slot_launch_hex8_is_valid 3f9a1c2
	[ "$status" -ne 0 ]
}

@test "slot_launch_job_id_is_valid_英数字とアンダースコアとハイフン以外を含む場合_通さないこと" {
	# Act / Assert
	slot_launch_job_id_is_valid JOB_001-a
	run slot_launch_job_id_is_valid "JOB 001"
	[ "$status" -ne 0 ]
	run slot_launch_job_id_is_valid "JOB.001"
	[ "$status" -ne 0 ]
}

@test "slot_launch_parameters_json_引数がある場合_順序どおりのJSON配列の文字列であること" {
	# Act
	slot_launch_parameters_json 20260830 full

	# Assert
	[ "$SLOT_LAUNCH_PARAMETERS_JSON" = '["20260830","full"]' ]
}

@test "slot_launch_parameters_json_引数が無い場合_空の配列であること" {
	# Act
	slot_launch_parameters_json

	# Assert
	[ "$SLOT_LAUNCH_PARAMETERS_JSON" = '[]' ]
}

@test "slot_launch_parameters_json_引用符とバックスラッシュと改行を含む場合_JSONの文字列にエスケープすること" {
	# Act
	slot_launch_parameters_json 'a"b' 'c\d' $'e\nf' '--opt'

	# Assert
	[ "$SLOT_LAUNCH_PARAMETERS_JSON" = '["a\"b","c\\d","e\nf","--opt"]' ]
}

@test "slot_launch_artifact_dir_roleを渡した場合_ARTIFACT_ROOTのfacade配下のrun_idとroleのパスであること" {
	# Act / Assert
	[ "$(slot_launch_artifact_dir /var/rg 20260830T113000-JOB001-3f9a1c2e green)" = "/var/rg/facade/20260830T113000-JOB001-3f9a1c2e/green" ]
	[ "$(slot_launch_artifact_dir /var/rg 20260830T113000-JOB001-3f9a1c2e)" = "/var/rg/facade/20260830T113000-JOB001-3f9a1c2e" ]
}
