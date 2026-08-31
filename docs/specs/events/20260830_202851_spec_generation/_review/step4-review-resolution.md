# Step4 Review Resolution(横断契約側)

- 対象: `_review/step4-review-api.md` / `step4-review-datastore.md` / `step4-review-uxui.md` と、`step3-round-2-G1〜G4.md` のうち横断契約(`_cross-cutting/api/*` / `datastore/*` / `ux-ui/*` / `rdra-feedback.md`)に向いた指摘
- 対応区分: fixed = 横断契約側で修正済み / deferred = 横断契約側では対応しない(UC 側の修正、または確定済み決定の範囲外)
- UC ディレクトリ・traceability-matrix.md / uc-dependencies.md / usdm-acceptance-matrix.md は本対応で変更していない(別担当・後で再生成)

## 検証結果

| 検証 | 結果 |
|---|---|
| `validateRdbSchema.js _cross-cutting/datastore/rdb-schema.yaml` | PASS(7 tables。slot_executions は indexes 0、parallel_runs は indexes 1) |
| `validateAllYaml.js E` | PASS(68 YAML) |
| `@asyncapi/cli validate asyncapi.yaml` | 0 errors / 0 warnings / 1 info(バージョン推奨のみ) |
| `@redocly/cli lint openapi.yaml` | valid。warning 1(placeholder サーバー URL。スタブとして既知) |
| `md-mermaid-lint`(ux-design / ui-design / data-visualization / rdra-feedback) | All OK |

## 対応表

| 出典 | # | severity | 対応 | 変更ファイル | 理由 |
|---|---|---|---|---|---|
| step4-review-api | 1 | major | fixed | cli-command-contract.yaml(`config_files[rapid-crosscheck.env]` 新設、`RELAY_GATE_CONFIG_DIR.purpose`、`credentials`、`shared_rules.lease_and_poll.rapid`)、asyncapi.yaml(channel description / lease_until)、rdb-schema.yaml(lease_until description)、ui-design.md(環境変数表・範囲外注記) | `rapid-crosscheck.env` に `RAPID_DB_CONN_REF` / `RAPID_LEASE_SEC`(600)/ `RAPID_POLL_INTERVAL_SEC`(30)を定義。readers に runner / worker / result / abort-blue・green・rapid / run-lineage / hang-detect-trend / background-rerun / facade・slot runner(on 時)を列挙。abort-final-crosscheck は final-crosscheck.env の readers に追加。「datastore 側で定義」の逃げ文言を削除 |
| step4-review-api | 2 | minor | fixed | rdb-schema.yaml `_review_notes` | business_date の表記を `YYYY-MM-DD` に統一 |
| step4-review-api | 3 | minor | fixed | rdb-schema.yaml `comparison_results.comparison_type.description` | enum `[job, full]` に合わせ、比較定義なしは INSERT しない旨も追記 |
| step4-review-api | 4 | minor | fixed | cli-command-contract.yaml `background-rerun.sh.options[--role]` | enum を `[blue, green, rapid-crosscheck]` に縮め synopsis と一致。final-crosscheck は UC「復元起動」「依頼再作成」の tier-ops.md が定義しないため削除し、列挙外として終了コード 2 |
| step4-review-api | 5 | minor | fixed | ux-design.md L143 | `hang-detect-trend.sh` として確定済みに書き換え |
| step4-review-datastore | 1 | major | deferred | (UC 側: 実装切替ジョブ実行フロー 4 ファイルの `finished_at` → `completed_at`) | schema 側は `completed_at` で確定済み。UC 側の未追従は別担当が修正 |
| step4-review-datastore | 2 | minor | fixed | rdb-schema.yaml(`idx_slot_executions_status_mode` 削除、`_review_notes` に不採用理由) | 利用者不在(走査は成果物ファイル、abort は主キー、runner 起動 UC は INSERT のみ) |
| step4-review-datastore | 3 | minor | fixed | rdb-schema.yaml(`idx_parallel_runs_job_id_requested_at` 削除、`_review_notes`) | UC 由来の検索が無い。運用調査は run_id の時刻プレフィックスで代替 |
| step4-review-datastore | 4 | minor | fixed | rdb-schema.yaml `idx_rapid_crosscheck_requests_status_requested_at.used_by` | INSERT のみの UC「速報比較依頼だけを新規作成する」を外した。同方針で `idx_parallel_runs_parent_run_id`(リラン 2 UC)、`idx_comparison_results_run_id_compared_at`(登録 UC)、`idx_monitor_records_*`(保存 UC)からも INSERT / UPSERT のみの UC を外し、`_review_notes` に運用規則を記録 |
| step4-review-datastore | 5 | minor | fixed | rdb-schema.yaml `_review_notes`、`idx_final_crosscheck_requests_status_requested_at.reason` | 未終端部分ユニークは不採用。根拠(ジョブスケジューラの二重起動抑止 / DDL 方言依存 / runner が同一キーの未終端依頼を SELECT して再利用・拒否する運用)を記録 |
| step4-review-datastore | 6 | minor | fixed | rdb-schema.yaml `monitor_records.target_type.description` | role からの導出可能性と非正規化の根拠(情報.tsv 属性の転記、可読性)を追記 |
| step4-review-datastore | 7 | minor | deferred | (UC 側: 監視記録を保存する/tier-ops.md・_model-summary.yaml のインデックス列) | schema 側は `(job_id, role, judged_at)` で確定済み。UC 側の未追従は別担当が修正 |
| step4-review-uxui | 1 | major | fixed | data-visualization.md 1.(要約部)/「認知負荷への配慮」 | 契約・tier md と同じ 9 行に統一。parent_run_id / error_summary の参照先を注記 |
| step4-review-uxui | 2 | major | fixed | cli-command-contract.yaml `hang-detect-trend.sh.stdout` | 列名を `max_elapsed_minutes_at_alert` / `last_elapsed_minutes_at_alert` に修正 |
| step4-review-uxui | 3 | major | fixed | data-visualization.md 1. | not-found / off 時の文言を契約(`rapid crosscheck request not found` / `rapid crosscheck is off; no management db to query mode=off`)に揃え、run-lineage / hang-detect-trend の off 時文言とは別系統である旨を明記 |
| step4-review-uxui | 4 | minor | fixed | ux-design.md L143 | api #5 と同一 |
| step4-review-uxui | 5 | minor | fixed | ux-design.md「段階的開示」 | `--show-output` は rapid-crosscheck-result 専用、hang-detect-trend は `--all`、run-lineage は `--verbose` に書き分け |
| step4-review-uxui | 6 | minor | fixed | ux-design.md「意図的な壁」 | 現在状態の項目を契約の固定行(slot 系 8 行 / 依頼系 7 行)に置換 |
| step4-review-uxui | 7 | minor | fixed | ui-design.md「日次メールサマリー」、data-visualization.md「全体サマリー」 | 仮採用内容(件名 + 警告傾向 TSV を貼る)を同文にし、data-visualization 側の本文キー案を削除 |
| step3-round-2-G1 | 11 | minor | deferred | (cli-command-contract.yaml runner IF exit 6 の条件追記 / UC 側 tier-facade.md) | 通常起動での既存 execution-spec.json 解析失敗を 2 / 6 のどちらに寄せるかは UC「execution-spec.json を確定保存する」担当の判断待ち。確定済み決定に含まれないため契約は未変更 |
| step3-round-2-G1 | 15 | minor | fixed | rdb-schema.yaml `comparison_results.comparison_type` | api #3 と同一 |
| step3-round-2-G2 | 1 | major | fixed(契約側) / deferred(UC 側) | cli-command-contract.yaml `rapid-crosscheck-runner.sh.notes`、rdra-feedback.md #8 | 完了通知失敗時は slot runner が stderr.log に `warn:` を残し終了コードは実装 exitcode のまま。復旧は運用者が同一引数で再実行(冪等・先勝ち)。自動検知は RDRA に要件が無くスコープ外として rdra-feedback に起票。UC 側のクラッシュ耐性節の書き直しは別担当 |
| step3-round-2-G2 | 2 | major | fixed(契約側) / deferred(UC 側) | cli-command-contract.yaml `rapid-crosscheck-worker.sh`(exit 0 meaning / idempotency)、`external_interfaces[比較ツール(速報)].result_registration`、rdb-schema.yaml、asyncapi.yaml(`error_summary`) | 比較定義が無い job_id は comparison_results を INSERT せず依頼を FAILED(error_summary=`comparison definition not found job_id=...`)で終端。UC 側 spec.md / tier md / _model-summary の BDD Then 修正は別担当 |
| step3-round-2-G2 | 3 | major | fixed | api #1 と同一 | 同上。UC 側 tier-rapid-crosscheck.md L23 の「datastore 側で定義」と `RAPID_LEASE_MINUTES` / `RAPID_POLL_INTERVAL_SECONDS` の表記は UC 側で `RAPID_LEASE_SEC` / `RAPID_POLL_INTERVAL_SEC` / `rapid-crosscheck.env` に追従が必要 |
| step3-round-2-G2 | 6 | minor | fixed | cli-command-contract.yaml `rapid-crosscheck-runner.sh.idempotency` | 先勝ち(先に登録済みの値は変えない)を明記 |
| step3-round-2-G2 | 8 | minor | deferred | (UC 側 BDD の Given / Then) | 契約の stderr は `management db update failed`(UPDATE 失敗)と `management db transaction failed`(接続・トランザクション失敗)の 2 種を既に区別しており、契約側の変更は不要。UC 側の Given 具体化は別担当 |
| step3-round-2-G2 | 11 | minor | fixed | asyncapi.yaml `RapidCrosscheckRequest` | blue_artifact_uri / green_artifact_uri / parent_run_id を削除し、description で rapid_runs / parallel_runs 参照を明記。代わりに rdb-schema にある `error_summary` を追加 |
| step3-round-2-G2 | 15 | minor | fixed | api #3 と同一 | |
| step3-round-2-G3 | 1 | major | fixed(rdra-feedback) / deferred(UC 側) | rdra-feedback.md #7 | HANG_SUSPECTED_NOTIFIED → COMPARE_ERROR_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPLETED を状態.tsv への追加要望として起票。走査 SQL・遷移表の修正は UC 側 |
| step3-round-2-G3 | 3 | major | deferred | (UC 側 spec.md「exitcode.txt の解釈」) | asyncapi `HangAlertMail.exit_code`(`^([0-9]{1,3}|-)$`)と ui-design.md「整数または `-`」を正とし、UC 側を `exit_code=-` + `WARN invalid exitcode` に寄せる。契約側は変更しない |
| step3-round-2-G3 | 5 | minor | deferred | (UC 側 tier-final-crosscheck.md の worker_id 文字種) | 契約 `--worker-id`(英数字・_・-)を正とし UC 側を合わせる。`{hostname}-{pid}` 既定値でホスト名に `.` が入る運用値は todo(feedback request)で見直す |
| step3-round-2-G3 | 6 | minor | deferred | datastore #7 と同一 | |
| step3-round-2-G3 | 7 | minor | deferred | (UC 側 spec / tier md の `judged` ログ行形式) | 契約 `hang-detector.sh --verbose` の説明は job_id なし。UC 側を契約に合わせる(契約側は変更しない) |
| step3-round-2-G3 | 12 | minor | deferred | (UC 側 `FINAL_POLL_LIMIT_SEC` 検証ルール / _api-summary stderr) | 契約 `integer(>=1)` を正とする。UC 側の追従は別担当 |
| step3-round-2-G3 | 13 | minor | fixed(rdra-feedback) | rdra-feedback.md #9 | 方針資料 C2 図 `HangDetector -.-> FinalQueue` と本文の食い違いを起票。Spec は本文(確報依頼は走査対象外)を正とし、polling 上限で代替する仮採用を記録 |
| step3-round-2-G3 | 14 | minor | fixed | ui-design.md「ハング検知判定結果」 | `COMPARE_ERROR` を追加(契約 `hang_judgement` 5 値と一致) |
| step3-round-2-G4 | 2 | major | fixed | cli-command-contract.yaml abort-blue / abort-green / abort-rapid-crosscheck の exit 0 meaning | parallel_runs の併更新を `WHERE status IN ('STARTED','RUNNING')` の条件付き UPDATE(COMPLETED は更新しない。0 件で可)に修正し、通常 run(0 件)と rerun-rapid 由来 run(ABORTED)の違いを明記。rerun-rapid の parallel_runs 終端は rdra-feedback #5 で起票済み |
| step3-round-2-G4 | 3 | major | fixed | cli-command-contract.yaml `background-rerun.sh.stderr` / `exit_codes`、`run-lineage.sh.stderr`、`hang-detect-trend.sh.stderr` / exit 2 condition | 各 UC の tier-ops.md 出力契約表を全行転記(hint 行を含む)。off 時の `--role rapid-crosscheck` は abort 系と同じ `management db is not configured (RAPID_CROSSCHECK_MODE=off)` 文言・終了コード 3。run-lineage に `lineage cycle detected`(6)/ `info: artifact_dir:`、hang-detect-trend の exit 2 に job_id 形式不正を追加 |
| step3-round-2-G4 | 5 | minor | deferred | (ui-design.md「メッセージ表現規約」の定型文 / 契約 rapid-crosscheck-runner.sh L309 / UC 側) | 必須オプション欠落の語彙統一(`option required` vs `missing option`)は確定済み決定に含まれず、G2 UC 側の文言と同時に変える必要があるため今回は保留。background-rerun / run-lineage の契約転記では UC tier-ops.md どおり `error: option required option=...` を採用した |
| step3-round-2-G4 | 7 | minor | fixed | cli-command-contract.yaml `artifact_layout.files[started-at.txt].readers` | abort-* を readers から外し、「on 時は slot_executions.started_at、off 時は管理 DB 未設定で 3」に修正 |
| step3-round-2-G4 | 8 | minor | fixed | G2 #11 と同一 | |
| step3-round-2-G4 | 11 | minor | deferred | (契約 `execution_spec_example` への `restored_at` 追加 / UC 側 buc-spec) | 契約 `execution_spec_rules` は既に run_id / parent_run_id / restored_at の 3 キー書き換えを記述済み。例への `restored_at: null` 追加は確定済み決定に含まれないため保留 |
| step3-round-2-G4 | 13 | minor | deferred | (契約 `artifact_layout.files[exitcode.txt].content` / UC 側 tier-ops.md 手順 4) | runner 起動不能時に background-rerun の gateway が 3 ファイルを書くか(値 6)は UC 側の決定待ち。契約側は決定後に転記する |
| step3-round-2-G4 | 14 | minor | fixed | G4 #3 と同一(off 時の `--role rapid-crosscheck` 文言) | UC 側 tier-ops.md「元状態の解決」の `request_not_found` 記述は契約に合わせて追従が必要 |
| step3-round-2-G4 | 17 | minor | deferred | (UC 側 G1 tier-facade.md L44) | 契約 runner IF idempotency は両経路を区別済み。UC 側の追記は別担当 |
| 確定済み決定(レビュー # なし) | — | — | fixed | cli-command-contract.yaml | `rapid-crosscheck-runner.sh` の defines を UC「両系成功時に速報比較依頼を作成する」、uses を「速報クロスチェック runner へ完了通知を送信する」に入替。`facade.sh` と `artifact_layout.files[execution-spec.json].readers` に UC「hang_detect_limit_minutes をジョブごとに調整する」、`validate-config.sh` / `hang-detector.sh` に UC「切り替えた運用モードで業務ジョブを実行する」、abort-blue / green / rapid・background-rerun・rapid-crosscheck-result に UC「ハング疑い・実行エラー・比較異常を通知する」を used_by_ucs に追加。`exitcode.txt` / `started-at.txt` の readers に background-rerun.sh(off 時の元状態導出)を追加。runner IF の `--execution-spec` と PARAM 併用は「受け付けない(2)」を維持 |
| 確定済み決定(レビュー # なし) | — | — | fixed | rdra-feedback.md #10 | USDM SPEC-001-01 本文の `BLUE_IMPL / GREEN_IMPL / RAPID_CROSSCHECK_RUNNER / RAPID_CROSSCHECK_WORKER` が feature flag 契約に無いキーである旨を起票 |

## 集計

| 区分 | 件数 |
|---|---|
| fixed(横断契約側で修正) | 32 |
| deferred(UC 側の修正・決定待ち) | 15 |

## UC 側に追従が必要になった変更(横断契約の変更に起因)

| 契約の変更 | 追従が必要な UC ファイル |
|---|---|
| `rapid-crosscheck.env` 新設、キー名 `RAPID_LEASE_SEC` / `RAPID_POLL_INTERVAL_SEC` / `RAPID_DB_CONN_REF` | クロスチェック業務/速報クロスチェックフロー/速報比較依頼を claim する/tier-rapid-crosscheck.md L23、spec.md L60・L102・L104、_model-summary.yaml L49(`RAPID_LEASE_MINUTES` / `RAPID_POLL_INTERVAL_SECONDS` / 「datastore 側で定義」) |
| `background-rerun.sh --role` の enum から final-crosscheck を削除(列挙外 = 終了コード 2) | 実行復旧業務/background 側リランフロー/リラン対象を検証する/tier-ops.md(引数表・出力契約表 `role is not supported by background-rerun` 行・事前検証表 `unsupported_role` 行・終了コード 3 の条件)、同 spec.md / _api-summary.yaml |
| off 時の `--role rapid-crosscheck` は `management db is not configured (RAPID_CROSSCHECK_MODE=off) run_id=... role=rapid-crosscheck`(3) | 同上 tier-ops.md「元状態の解決」(`request_not_found` → 管理 DB 未設定)、出力契約表・事前検証表への行追加 |
| abort-* の parallel_runs 併更新は COMPLETED を更新しない(0 件で可) | 実行復旧業務/実行中止フロー/実行を ABORTED へ遷移させる/tier-ops.md 併更新行、spec.md 状態遷移一覧(事前条件に明記) |
| 比較定義なしは comparison_results を INSERT せず FAILED / error_summary で終端 | クロスチェック業務/速報クロスチェックフロー/比較ツールでジョブ単位比較を実行して結果を登録する/spec.md(処理フロー・BDD Then)、tier-rapid-crosscheck.md、_model-summary.yaml |
| 完了通知失敗時の runner 挙動(stderr.log に `warn: completion notice failed ...`、終了コードは実装 exitcode のまま)と復旧手順 | クロスチェック業務/速報クロスチェックフロー/速報クロスチェック runner へ完了通知を送信する/tier-facade.md L42「クラッシュ耐性」 |
| asyncapi `RapidCrosscheckRequest` から 3 プロパティ削除 | 実行復旧業務/background 側リランフロー/速報比較依頼だけを新規作成する/tier-rapid-crosscheck.md L52「payload は依頼レコードそのもの」(依頼列 + rapid_runs 参照に修正) |
| `hang-detect-trend.sh` の TSV 列名(契約側を tier md に合わせた) | 追従不要(tier-ops.md / data-visualization.md が正) |
