#!/usr/bin/env bats
# UC fd678b04 × tier-facade: slot ジョブマップの場所(domain の関数)の単体テスト。
# 仕様: CLI 契約 config_files.feature-flag.env.job_map_location(location / value_rules / examples)と、値からパスを決める
#       同じ 1 つの規則 runner_path_resolution(relative_criteria / base_dir / resolved_path)、keys、validation_rules(未知キー)
# 実行時の読み手(後続の UC の facade.sh)が同じ関数を再利用するため、関数単位で場所の決め方を固定する。
# エントリポイント経由の判定(所在の検査・表示)は test/usecase/validate_feature_flag_job_map_location.bats。

setup() {
	# shellcheck source=/dev/null
	source "$BATS_TEST_DIRNAME/../../src/domain/feature_flag.sh"
	unset BLUE_MODE GREEN_MODE BLUE_JOB_MAP_CSV GREEN_JOB_MAP_CSV
	FEATURE_FLAG_PATH=/etc/relay-gate/feature-flag.env
}

# ---- 所有するキー(9 キー + 任意の 2 キー) ----

@test "feature_flag_is_defined_key_任意の2キーの場合_所有するキーと判定し名前が似たキーは判定しないこと" {
	# Act / Assert
	local key rejected=0
	feature_flag_is_defined_key BLUE_JOB_MAP_CSV
	feature_flag_is_defined_key GREEN_JOB_MAP_CSV
	for key in BLUE_JOB_MAP GREEN_JOB_MAP_CSV_ JOB_MAP_CSV blue_job_map_csv RAPID_JOB_MAP_CSV; do
		if ! feature_flag_is_defined_key "$key"; then
			rejected=$((rejected + 1))
		fi
	done
	[ "$rejected" -eq 5 ]
}

@test "feature_flag_classify_keys_任意の2キーがある場合_未知キーにも確報の制御キーにも分けないこと" {
	# Arrange
	FEATURE_FLAG_KEYS=(BLUE_MODE BLUE_JOB_MAP_CSV JOB_MAP_CSV GREEN_JOB_MAP_CSV FINAL_JOB_MAP_CSV)

	# Act
	feature_flag_classify_keys

	# Assert
	[ "${FEATURE_FLAG_UNKNOWN_KEY_INDEXES[*]}" = "2" ]
	[ "${FEATURE_FLAG_FORBIDDEN_KEY_INDEXES[*]}" = "4" ]
}

# ---- 場所の決め方 ----

@test "feature_flag_resolve_job_map_locations_2キーが無い場合_置き場の固定の名前を文字列のまま返すこと" {
	# Arrange(置き場が相対パス・末尾がスラッシュでも、絶対パスへの変換も正規化もしない)
	BLUE_MODE=foreground
	GREEN_MODE=background

	# Act
	feature_flag_resolve_job_map_locations /etc/relay-gate /work
	local blue="$FEATURE_FLAG_BLUE_JOB_MAP" green="$FEATURE_FLAG_GREEN_JOB_MAP"
	feature_flag_resolve_job_map_locations ./config/ /work

	# Assert
	[ "$blue" = "/etc/relay-gate/blue-job-map.csv" ]
	[ "$green" = "/etc/relay-gate/green-job-map.csv" ]
	[ "$FEATURE_FLAG_BLUE_JOB_MAP" = "./config//blue-job-map.csv" ]
	[ "$FEATURE_FLAG_GREEN_JOB_MAP" = "./config//green-job-map.csv" ]
}

@test "feature_flag_resolve_job_map_locations_値が空の場合_キーが無いときと同じ固定の名前を返すこと" {
	# Arrange(検証に渡したファイルは置き場と違う場所。既定の場所は置き場の配下)
	FEATURE_FLAG_PATH=/site/conf/ff.env
	BLUE_MODE=foreground
	GREEN_MODE=background
	BLUE_JOB_MAP_CSV=""
	GREEN_JOB_MAP_CSV=""

	# Act
	feature_flag_resolve_job_map_locations /etc/relay-gate /work

	# Assert
	[ "$FEATURE_FLAG_BLUE_JOB_MAP" = "/etc/relay-gate/blue-job-map.csv" ]
	[ "$FEATURE_FLAG_GREEN_JOB_MAP" = "/etc/relay-gate/green-job-map.csv" ]
}

@test "feature_flag_resolve_job_map_locations_絶対パスと相対パスを書いた場合_絶対パスは値のまま相対パスは設定ファイルのあるディレクトリ基準で畳まずに返すこと" {
	# Arrange(契約 job_map_location.examples の 1 つ目)
	BLUE_MODE=foreground
	GREEN_MODE=background
	BLUE_JOB_MAP_CSV=./blue-jobs.csv
	GREEN_JOB_MAP_CSV=/srv/relay-gate/maps/../maps//green-jobs.csv

	# Act
	feature_flag_resolve_job_map_locations /etc/relay-gate /work

	# Assert(2 キーの変数は書き換えない)
	[ "$FEATURE_FLAG_BLUE_JOB_MAP" = "/etc/relay-gate/./blue-jobs.csv" ]
	[ "$FEATURE_FLAG_GREEN_JOB_MAP" = "/srv/relay-gate/maps/../maps//green-jobs.csv" ]
	[ "$BLUE_JOB_MAP_CSV" = "./blue-jobs.csv" ]
	[ "$GREEN_JOB_MAP_CSV" = "/srv/relay-gate/maps/../maps//green-jobs.csv" ]
}

@test "feature_flag_resolve_job_map_locations_設定ファイルが相対パスの場合_作業ディレクトリで絶対化したディレクトリを基準にすること" {
	# Arrange
	FEATURE_FLAG_PATH=conf/ff.env
	BLUE_MODE=off
	GREEN_MODE=foreground
	GREEN_JOB_MAP_CSV=../maps/green-jobs.csv

	# Act
	feature_flag_resolve_job_map_locations /etc/relay-gate /work

	# Assert
	[ "$FEATURE_FLAG_GREEN_JOB_MAP" = "/work/conf/../maps/green-jobs.csv" ]
}

@test "feature_flag_resolve_job_map_locations_runnerのキーと同じ値を書いた場合_runnerのキーと同じ解決後のパスになること" {
	# Arrange(6 キーに同じ 1 つの規則を適用し、キーの種類で結果を変えない)
	FEATURE_FLAG_PATH=./config/feature-flag.env
	BLUE_MODE=foreground
	GREEN_MODE=background
	RAPID_CROSSCHECK_MODE=off
	local value
	local -a values=(a.csv ./a.csv ../a.csv '~/a.csv' '$HOME/a.csv' /abs/./a.csv 'dir with space/a.csv')

	for value in "${values[@]}"; do
		BLUE_RUNNER="$value"
		BLUE_JOB_MAP_CSV="$value"

		# Act
		feature_flag_resolve_runner_paths /opt/relay-gate
		feature_flag_resolve_job_map_locations /etc/relay-gate /opt/relay-gate

		# Assert
		[ "$FEATURE_FLAG_BLUE_JOB_MAP" = "$BLUE_RUNNER" ]
	done
}

@test "feature_flag_resolve_job_map_locations_offのslotの場合_場所を決めず空を返すこと" {
	# Arrange(前の呼び出しの結果を残さない)
	FEATURE_FLAG_BLUE_JOB_MAP=/stale/blue.csv
	FEATURE_FLAG_GREEN_JOB_MAP=/stale/green.csv
	BLUE_MODE=off
	GREEN_MODE=off
	BLUE_JOB_MAP_CSV=./blue-jobs.csv

	# Act
	feature_flag_resolve_job_map_locations /etc/relay-gate /work

	# Assert
	[ -z "$FEATURE_FLAG_BLUE_JOB_MAP" ]
	[ -z "$FEATURE_FLAG_GREEN_JOB_MAP" ]
}

@test "feature_flag_resolve_job_map_locations_modeが列挙外と欠落の場合_offでないとして場所を決めること" {
	# Arrange(off として扱うのは値が off と完全一致するときだけ)
	BLUE_MODE=parallel
	unset GREEN_MODE
	BLUE_JOB_MAP_CSV=maps/blue-jobs.csv

	# Act
	feature_flag_resolve_job_map_locations /etc/relay-gate /work

	# Assert
	[ "$FEATURE_FLAG_BLUE_JOB_MAP" = "/etc/relay-gate/maps/blue-jobs.csv" ]
	[ "$FEATURE_FLAG_GREEN_JOB_MAP" = "/etc/relay-gate/green-job-map.csv" ]
}

@test "feature_flag_resolve_job_map_locations_2回呼んだ場合_結果が変わらないこと" {
	# Arrange(既定の場所が相対パスでも、2 回目に基準のディレクトリを付け足さない)
	BLUE_MODE=foreground
	GREEN_MODE=background
	GREEN_JOB_MAP_CSV=green-jobs.csv

	# Act
	feature_flag_resolve_job_map_locations config /work
	feature_flag_resolve_job_map_locations config /work

	# Assert
	[ "$FEATURE_FLAG_BLUE_JOB_MAP" = "config/blue-job-map.csv" ]
	[ "$FEATURE_FLAG_GREEN_JOB_MAP" = "/etc/relay-gate/green-jobs.csv" ]
}

@test "feature_flag_resolve_job_map_locations_blueとgreenに同じ場所を書いた場合_同じ場所を返すこと" {
	# Arrange
	BLUE_MODE=foreground
	GREEN_MODE=background
	BLUE_JOB_MAP_CSV=/srv/maps/jobs.csv
	GREEN_JOB_MAP_CSV=/srv/maps/jobs.csv

	# Act
	feature_flag_resolve_job_map_locations /etc/relay-gate /work

	# Assert
	[ "$FEATURE_FLAG_BLUE_JOB_MAP" = "/srv/maps/jobs.csv" ]
	[ "$FEATURE_FLAG_GREEN_JOB_MAP" = "/srv/maps/jobs.csv" ]
}
