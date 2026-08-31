# round-1 反証レビュー 解決記録(横断契約側)

> Step6.5 修正担当(横断契約)。対象 = `_cross-cutting/api/*` / `_cross-cutting/datastore/*` / `_cross-cutting/ux-ui/*` / `_cross-cutting/rdra-feedback.md`。
> UC ディレクトリ・traceability-matrix.md / uc-dependencies.md / usdm-acceptance-matrix.md は別担当のため未修正(UC 側追従が必要な項目は末尾に列挙)。

## 検証結果

| 検証 | 結果 |
|---|---|
| `validateAllYaml.js E` | PASS(73 ファイル、error 0) |
| `validateRdbSchema.js rdb-schema.yaml` | PASS(7 tables) |
| `@asyncapi/cli validate asyncapi.yaml` | valid(error 0、info 1 = asyncapi-latest-version。既存) |
| `@redocly/cli lint openapi.yaml` | valid(error 0、warning 1 = no-server-example-com。既存スタブ) |
| `md-mermaid-lint ui-design.md / data-visualization.md / rdra-feedback.md` | OK |

## 解決表

略記: contract = `_cross-cutting/api/cli-command-contract.yaml`、rdb = `_cross-cutting/datastore/rdb-schema.yaml`、ui = `_cross-cutting/ux-ui/ui-design.md`、dv = `_cross-cutting/ux-ui/data-visualization.md`、async = `_cross-cutting/api/asyncapi.yaml`、fb = `_cross-cutting/rdra-feedback.md`

| finding | severity | resolution | 変更内容 | 変更ファイル |
|---|---|---|---|---|
| F-001 | blocker | deferred(UC 側) | 確報 worker の BDD Given 修正は UC 側。契約の final-crosscheck-worker.sh idempotency は「CLAIMED 再開規則なし」のまま(Given を REQUESTED に直す方針) | — |
| F-002 | major | fixed | background-rerun.sh: exit 3 condition を role 別に分け、rapid-crosscheck は execution-spec.json を必須にしない・数珠つなぎ可を idempotency / notes に明記。stderr `execution-spec not found` を blue/green 限定。artifact_layout execution-spec.json readers も同期 | contract |
| F-003 | major | fixed | rapid-crosscheck-runner.sh notes[0] を「実行ログ WARN のみ。stderr.log 追記なし」に変更。slot runner stderr / artifact_layout stderr.log を「exitcode.txt 公開後は変更しない」に統一 | contract |
| F-004 | major | fixed | facade.sh idempotency に「起動前 pid=NULL INSERT → 起動後 pid UPDATE」、slot runner idempotency に「終端 UPDATE 0 件は実行ログ ERROR、終了コード不変」。rdb slot_executions.pid / started_at description と _review_notes に反映 | contract, rdb |
| F-005 | major | fixed | facade.sh exit 6 condition を runner 起動前の INSERT / STARTED→RUNNING UPDATE 失敗等に限定し、中継後 COMPLETED UPDATE 失敗は終了コードに反映しない(実行ログ ERROR)を明記 | contract |
| F-006 | major | fixed | facade.sh notes と slot runner `environment` に引き継ぎ環境変数 4 つ(RELAY_GATE_CONFIG_DIR / RELAY_GATE_ARTIFACT_ROOT / RELAY_GATE_LOG_DIR / RAPID_CROSSCHECK_MODE)と on 時 rapid-crosscheck.env 読み込み・不在 2 を宣言。facade / runner / worker の exit 2 condition と config_files.rapid-crosscheck.env.on_missing を整合 | contract |
| F-007 | major | fixed | environment_variables に `RELAY_GATE_NOW`(テスト専用、ISO 8601 UTC、未設定なら now()、読む側を列挙)を追加。shared_rules.run_id.test_verification に乱数部は形式パターンで照合する旨を追加。ui 環境変数表にも同行を追加 | contract, ui |
| F-008 | major | fixed | shared_rules.state_codes.hang_judgement を 6 値 `[NOT_TARGET, COMPLETED, MONITORING, HANG_SUSPECTED, EXEC_ERROR, COMPARE_ERROR]` に変更し、monitor_status への対応表 `hang_judgement_to_monitor_status` を追加。ui「ハング検知判定結果」行を 6 値に更新。asyncapi に該当箇所なし | contract, ui |
| F-009 | major | fixed | hang-detector.sh stderr に `warn: execution-spec missing run_id=... path: ...`(判定対象外・0)を追加、exit 0 meaning に「既定値で判定しない」を明記。artifact_layout execution-spec.json readers も同期 | contract |
| F-010 | major | fixed | hang-detector.sh exit 0 meaning に「ABORTED(依頼)で未終端の監視記録があるものは判定 COMPLETED で終端、メール送らない」を追加 | contract |
| F-011 | major | fixed | 同上(slot_executions.status=ABORTED も対象)。idempotency に「on 時は slot_executions / rapid_crosscheck_requests の ABORTED を読む」。rdb slot_executions.used_by に判定 UC の SELECT を追加、_review_notes のインデックス不採用根拠を更新 | contract, rdb |
| F-012 | major | fixed | ui 通知メール規約に「80 桁制限は 1〜13 行目のみ。14 行目の recommended_action は折り返さず 1 行」を追加(行順表も 14 行目・1 行に変更) | ui |
| F-013 | major | deferred(UC 側) | feature flag spec の Given 修正は UC 側 | — |
| F-014 | major | deferred(UC 側) | _api-summary の転記修正は UC 側(契約は 12 キー・required false のまま) | — |
| F-015 | major | fixed | config_files.feature-flag.env.derived を「validate-config.sh の stdout と facade.sh 実行ログ `feature flag loaded ... operation_mode=`」に修正。facade.sh に `execution_log` 節を追加し当該行を宣言 | contract |
| F-016 | major | deferred(UC 側) | slot runner 割当 spec の Given 修正は UC 側 | — |
| F-017 | major | deferred(UC 側) | 契約はすでに「起動失敗では INSERT しない」。UC 側転記待ち | — |
| F-018 | major | fixed | rapid-crosscheck-worker.sh に exit 3(`error: management db is not configured mode=off`、DB 未接続)を追加。feature-flag.env readers に worker を追加。on_missing と exit 2 condition を整合 | contract |
| F-019 | major | fixed | rapid-crosscheck-worker.sh stdout に `result_status=-` / `comparison_result_id=-`(comparison_results なし)と `request_status=ABORTED`(終端 UPDATE 0 件)を追記。stderr に `warn: request already terminal` | contract |
| F-020〜F-024 | major | deferred(UC 側) | BDD Given/When の修正。F-022 / F-023 は契約側がすでに正(抜き出し catalog / `option required option=`)、UC 転記待ち | — |
| F-025 | major | fixed | abort-final-crosscheck.sh exit 3 condition / stderr を「final-crosscheck.env / FINAL_DB_CONN_REF の有無だけで判定。RAPID_CROSSCHECK_MODE は参照しない」に修正。feature-flag.env readers から abort-final を除外 | contract |
| F-026 | major | fixed | execution_spec_rules に「slots.{role} 節が無い slot は mode=off とみなす(リラン検証の判定元)」を注記。background-rerun.sh notes / exit 3 condition にも反映 | contract |
| F-027〜F-029 | minor | deferred(UC 側) | _model-summary / _api-summary / BDD の修正 | — |
| F-030 | minor | fixed | facade.sh に `option_placement`(オプションは JOB_ID より前のみ。以降はすべて PARAM)を追加、PARAM description も更新 | contract |
| F-031 | minor | deferred(UC 側) | 契約(external_interfaces SSH 形式 / error 行形式)が正。UC 転記待ち | — |
| F-032 | minor | fixed | validate-config.sh stderr に検証種別共通のメッセージ形式(file not found / header mismatch / column count mismatch / duplicate / 値不正 / 宣言不正)を定義。runner-if-version 未応答は `-`。--crosscheck-job-map / --target-catalog を値必須(default 削除、synopsis `<path>`) | contract |
| F-033 / F-034 | minor | deferred(UC 側) | BDD / USDM 対応表の修正 | — |
| F-035 | minor | fixed | ui 出力例を request_status=FAILED に修正。dv: difference_count の説明を stdout 転記規則に、ソートに SQL 併記、--show-output 構造を正本と明記(仮採用注記の根拠を解消)。contract rapid-crosscheck-result.sh stdout をタイブレーク・空行・区切り行を含む形に更新 | ui, dv, contract |
| F-036 | minor | fixed(契約側) | final-crosscheck-worker.sh: 終端 UPDATE 0 件 = 中止済み(warn、0)、カタログ 0 行は 6(依頼 FAILED)、runner polling は status のみ・終端時 4 列 SELECT を idempotency に明記。rdb _review_notes に依頼終端 UPDATE 0 件の扱いを追加。UC 側 BDD 追加は別担当 | contract, rdb |
| F-037 | minor | fixed | rdb _review_notes(部分ユニーク不採用の根拠 (3))を「二重起動抑止はジョブスケジューラの責務。runner は事前 SELECT しない」に修正 | rdb |
| F-038 | minor | fixed | final-crosscheck-runner.sh / worker の stderr 文言を列挙(config file not found / target_catalog_path declaration not found / management db connection failed 等)。ui に管理 DB 障害・設定不在の定型文を追加、polling ログを `final_crosscheck_id=` に修正 | contract, ui |
| F-039 | minor | deferred(UC 側) | BDD の具体値・待機時間 | — |
| F-040 | minor | fixed | async HangAlertMail 例を elapsed_minutes 74 に。contract --exit-code を 0〜255、--job-id 照合先を parallel_runs.job_id に修正 | async, contract |
| F-041 | minor | fixed | rdb hang_suspected_at を「通知送信成功日時」、alerted_at を記録用に。contract hang-detector.sh idempotency を「monitor_status の遷移有無で判定」に。dv current_limit_minutes / rdb hang_detect_limit_minutes に rapid-crosscheck の出所(RAPID_HANG_DETECT_LIMIT_MINUTES)を追記。ui 冪等性も同期。buc-spec CRUD は UC 側 | rdb, contract, dv, ui |
| F-042 | minor | fixed(契約側) | artifact_layout started-at.txt readers から background-rerun を削除(exitcode.txt のみで導出)。path: 表記は契約既存どおり。tier-ops 終了コード表(循環検出 6)は UC 側 | contract |
| F-043 | minor | deferred | buc-spec の状態遷移図(rdra-feedback #4 の採否待ち)。契約側変更なし | — |
| F-044 / F-045 | minor | deferred(UC 側) | tier md の根拠文・setsid 前提 | — |
| F-046 | minor | fixed | validate-config.sh tier を `tier-facade` 単一値に(検証ロジックの所有は options[].owner_tier、`tier_note` で説明)。defined_in_uc を「feature flag を設定する」単一値にし、他 2 UC を used_by_ucs へ移動 | contract |
| SR-001 | minor | deferred(記録) | fb 末尾に「後工程・スキルへの変更要求」節を新設し記録 | fb |
| SR-002 | minor | deferred(記録) | 同上 | fb |
| uc-dependencies 残件 | — | fixed | abort-blue / abort-green / abort-rapid-crosscheck の used_by_ucs に「リラン対象を検証する」を追加。rapid-crosscheck-runner.sh の defined_in_uc を「速報クロスチェック runner へ完了通知を送信する」、used_by_ucs を「両系成功時に速報比較依頼を作成する」に戻した | contract |

集計: fixed 27(F-002〜F-012, F-015, F-018, F-019, F-025, F-026, F-030, F-032, F-035〜F-038, F-040〜F-042, F-046, uc-deps 残件)/ deferred 21(UC 側 18: F-001, F-013, F-014, F-016, F-017, F-020〜F-024, F-027〜F-029, F-031, F-033, F-034, F-039, F-044, F-045 / rdra 待ち 1: F-043 / スキル要求 2: SR-001, SR-002)

## UC 側に追従が必要な契約変更

| 契約変更 | 追従先 |
|---|---|
| hang_judgement 6 値化(NOT_TARGET / COMPLETED 分離) | 判定 UC tier-ops 判定表(「あり・0」→ COMPLETED、対象外 → NOT_TARGET)、記録 UC 記録規則、通知 UC |
| hang-detector: execution-spec 欠落は warn で対象外(既定 60 分で続行しない) | 判定 UC ティア完了条件・計算ルール |
| hang-detector: ABORTED(slot_executions / 依頼)で未終端監視記録は COMPLETED 終端。on 時は slot_executions を読む | 判定 UC _model-summary(slot_executions SELECT 追加、依頼 where に ABORTED)、判定表 ABORTED 行、受信 UC Then |
| 冪等判定を monitor_status の遷移有無に統一、hang_suspected_at = 送信成功日時 | 記録 UC / 通知 UC(spec 側はすでに同旨) |
| slot_executions: 起動前 INSERT(pid=NULL)→ 起動後 pid UPDATE。終端 UPDATE 0 件は ERROR ログ | slot 選択 UC sequence(INSERT 位置)、Runner Result UC(0 件の扱い)、復元起動 UC |
| facade exit 6 の範囲限定、実行ログ `feature flag loaded ... operation_mode=` 行 | slot 選択 UC tier-facade 実行ログ一覧、運用モード UC |
| runner へ引き継ぐ env 4 つ + on 時 rapid-crosscheck.env 読み込み(不在 2) | slot 選択 UC / Runner Result UC / 完了通知 UC の設定契約・終了コード表 |
| 完了通知失敗は実行ログ WARN のみ(stderr.log 追記廃止) | 完了通知 UC tier-facade L28・L44、spec.md、_api-summary |
| RELAY_GATE_NOW / run_id 形式照合 | 監視・確報 claim・復元・abort 各 UC の BDD(絶対時刻は Given に `RELAY_GATE_NOW=...` を置く、run_id 末尾はパターン照合) |
| rapid-crosscheck-worker.sh: off は exit 3、stdout の `-` / ABORTED、終端 UPDATE 0 件は warn で 0 | claim UC / 比較実行 UC tier-rapid-crosscheck 終了コード表・出力契約・BDD Then |
| final-crosscheck-worker.sh: 終端 UPDATE 0 件 = 中止済み(warn、0)、カタログ 0 行 = 6、polling は status のみ | 確報 比較実行 UC / 登録 UC tier・_model-summary |
| abort-final-crosscheck.sh は RAPID_CROSSCHECK_MODE を参照しない | 停止確認 UC tier-ops「RAPID_CROSSCHECK_MODE=off」節 |
| background-rerun --role rapid-crosscheck は execution-spec.json 不要、slots 節なし = off | 検証 UC spec sequence / 事前検証表 / 計算ルール / tier-ops Given |
| validate-config.sh の共通 stderr 形式、runner_if_version 未応答 `-`、--crosscheck-job-map / --target-catalog 値必須、tier=tier-facade、defined_in_uc 単一化 | feature flag / ジョブマップ / クロスチェック定義 各 UC の tier md・_api-summary、uc-dependencies.md(再生成) |
| facade.sh オプションは JOB_ID より前のみ | slot 選択 UC 引数表 |
| rapid-crosscheck-result.sh --show-output 構造・ソートのタイブレーク | 速報結果参照 UC spec L178 注記削除・_model-summary ORDER BY |
| ui 管理 DB 障害・設定不在の定型文(`management db unavailable` 廃止) | 確報 claim UC / 登録 UC のエラーメッセージ一覧 |
