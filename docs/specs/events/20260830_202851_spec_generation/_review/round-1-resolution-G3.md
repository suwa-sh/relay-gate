# round-1 resolution(G3: 確報クロスチェックフロー / background 実行監視フロー)

- 所有範囲: `クロスチェック業務/確報クロスチェックフロー/` 全部、`実行監視業務/background 実行監視フロー/` の判定・通知・記録・受信 UC と buc-spec.md
- 契約(`_cross-cutting/`)は別担当。契約側への要求は末尾に列挙する
- 検証: 変更 UC dir 9 件で `validateApiSummary.js` / `validateModelSummary.js` PASS、変更 md 19 件で `md-mermaid-lint` OK

## 所有範囲内の finding

| finding id | severity | resolution | 変更ファイル |
|---|---|---|---|
| F-001 | blocker | fixed。E2E 4 本 + 異常系 2 本、ティア BDD 5 本を Given=REQUESTED / When=`final-crosscheck-worker.sh --once --worker-id final-worker-01` に書き換え、claim → RUNNING → 終端を 1 プロセスで検証する形にした | 比較ツールで日次全量比較を実行して結果を保存する/spec.md, tier-final-crosscheck.md, _api-summary.yaml, _model-summary.yaml |
| F-007 | major | fixed(所有範囲内)。「現在時刻が …」「When <時刻> に …」「5 分後に」を `RELAY_GATE_NOW=<ISO 8601 UTC>` の Given に統一。claim UC は now を SQL バインド値として渡す(`:now`)よう計算ルール / 処理フロー / _model-summary を修正。判定・通知・記録 UC に now の計算ルールを追加。乱数 id は形式パターン検証(登録 UC は既に対応済み) | 確報比較依頼を claim する/spec.md, tier-final-crosscheck.md, _model-summary.yaml / 判定 UC spec.md, tier-ops.md / 通知 UC spec.md, tier-ops.md / 記録 UC spec.md, tier-ops.md |
| F-008 | major | fixed。hang_judgement を 6 値(NOT_TARGET / COMPLETED / MONITORING / HANG_SUSPECTED / EXEC_ERROR / COMPARE_ERROR)にし、判定表・異常判定表・状態遷移・E2E / ティア BDD・_api-summary(stderr)・記録規則・buc-spec のバリエーションを揃えた | 判定 UC spec.md, tier-ops.md, _api-summary.yaml / 通知 UC spec.md / 記録 UC spec.md, tier-ops.md, _model-summary.yaml / buc-spec.md |
| F-009 | major | fixed。execution-spec.json 欠落は既定 60 分で続行せず `warn: execution-spec missing run_id=...` を stderr に出して当該 run を判定対象外(監視記録なし。終了コード 0)。分岐条件・計算ルール・走査手順・ログ一覧・E2E / ティア BDD を修正 | 判定 UC spec.md, tier-ops.md, _api-summary.yaml / 記録 UC tier-ops.md |
| F-010 | major | fixed。依頼走査 where 句に `status='ABORTED' AND 未終端の monitor_records がある` を追加し、異常判定表 ABORTED 行を COMPLETED(中止済み → monitor_status COMPLETED)に変更。E2E に「ハング疑い通知後に中止された速報比較依頼を終端する」を追加 | 判定 UC spec.md, tier-ops.md, _model-summary.yaml |
| F-011 | major | fixed。on 時は `slot_executions.status=ABORTED` を判定 COMPLETED とする行を判定表・_model-summary(slot_executions SELECT)・データフロー・データモデルに追加。off は成果物のみ(abort が拒否されるため ABORTED は発生しない)と明記。受信 UC 異常系の Given に RAPID_CROSSCHECK_MODE=on、Then を「監視記録が COMPLETED で終端し以後同じ run_id / role にメールを送らない」に整合 | 判定 UC spec.md, tier-ops.md, _model-summary.yaml / 受信 UC spec.md, tier-ops.md / buc-spec.md |
| F-012 | major | fixed。80 桁制限は 1〜13 行目のみ、14 行目の recommended_action は折り返さず 1 行(80 桁超可)。通知 UC の出力契約・E2E / ティア BDD、受信 UC の本文表・ティア BDD を修正 | 通知 UC spec.md, tier-ops.md / 受信 UC tier-ops.md |
| F-020 | major | fixed。ティア BDD「--once で 1 件 claim」「lease 失効の回収」と spec Scenario 2 を、停止シグナルまで待機するスタブ compare_command を Given に置き、実行中に worker_id / lease_until / status∈{CLAIMED,RUNNING} を検証する形に統一 | 確報比較依頼を claim する/spec.md, tier-final-crosscheck.md |
| F-021 | major | fixed。中継 UC の E2E 3 本と確認 UC ティア BDD「応答に 3 値だけが含まれる」を「別プロセスが 3 秒後に runner が登録した最新行を終端更新する」Given/When に書き換え | 保存済みの確報結果をジョブスケジューラへ返す/spec.md / 確報クロスチェック結果を確認する/tier-final-crosscheck.md |
| F-023 | major | fixed。`error: option required option=--catalog-version` に修正し、エラーメッセージ一覧・_api-summary にも定型文を追加 | 確報比較依頼を登録して終端状態まで待機する/tier-final-crosscheck.md, _api-summary.yaml |
| F-024 | major | fixed。「claim 直後に abort で ABORTED」を「lease 失効で別 worker に回収され RUNNING 遷移 UPDATE が 0 件」に差し替え。ABORTED 競合は「比較中に ABORTED された依頼の終端 UPDATE は 0 件になる」として spec / tier 双方に定義(F-036 と同時解消) | 比較ツールで日次全量比較を実行して結果を保存する/spec.md, tier-final-crosscheck.md |
| F-028 | minor | fixed(所有範囲内の受信 UC / 通知 UC 分)。受信 UC _api-summary の abort-* / background-rerun.sh / rapid-crosscheck-result.sh synopsis を契約に揃え、通知 UC _api-summary の rapid-crosscheck-result.sh の tier を契約どおり tier-rapid-crosscheck に修正(受信 UC 側の tier-rapid-crosscheck は契約と一致しており正)。他 UC の型 / options / exit_codes は別担当 | 受信 UC _api-summary.yaml / 通知 UC _api-summary.yaml |
| F-034 | minor | fixed(所有範囲内の確認 UC 分)。「終了コード 6 で実行エラーと判断し再実行する」の Scenario タグを SPEC-009-04 にし、関連 USDM に REQ-009 / SPEC-009-04 行を追加。SPEC-012-02 は実行履歴の追跡(Then 追記)として併記 | 確報クロスチェック結果を確認する/spec.md |
| F-036 | minor | fixed。終端 UPDATE 0 件 = 中止済み(成果物 3 ファイルは残し `WARN request already terminal ... status=ABORTED`、終了コード 0)を処理フロー・冪等性・エラー表・BDD に定義。カタログ 0 行は起動失敗と同じ worker 終了コード 6 と明記。polling は status のみ、終端後の 4 列 SELECT は中継 UC が 1 回だけ、に統一(登録 UC の sequence / tier / _model-summary を修正) | 比較ツールで日次全量比較を実行して結果を保存する/spec.md, tier-final-crosscheck.md, _model-summary.yaml, _api-summary.yaml / 確報比較依頼を登録して終端状態まで待機する/spec.md, tier-final-crosscheck.md, _model-summary.yaml |
| F-038 | minor | 一部 fixed。登録 UC tier に終了コード 2 条件の stderr 文言(`config file not found` / `config key required` / `target_catalog_path declaration not found`)を追加。**deferred**: DB 失敗文言の速報 / 確報間の統一(`management db unavailable` vs `connection failed`)と polling ログのキー名(ui-design.md `request_id=`)は契約 / ui-design 側の決定が要るため契約担当へ | 確報比較依頼を登録して終端状態まで待機する/tier-final-crosscheck.md, _api-summary.yaml |
| F-039 | minor | 一部 fixed(所有範囲内)。登録 UC Scenario 1 を FINAL_POLL_INTERVAL_SEC=1 + 終端後の stdout / 終了コード検証に変更(「速報側テーブルを変更しない」も同様)。中継 UC の「中継直前の SELECT に失敗する」は再現不能な競合窓のため E2E から削除し tier の単体テスト対象と明記、ABORTED シナリオの id は `<id>` 形式に統一。判定 UC 異常系に HANG_DB_CONN_REF=relaygate-db、受信 UC に difference_count=12 / report_uri の Given、通知 UC ティア BDD に RELAY_GATE_CONFIG_DIR=/etc/relay-gate を追加。**deferred**: 依頼再作成 UC(実行復旧業務)の artifact_uri 欠落 Given は所有範囲外 | 確報比較依頼を登録して終端状態まで待機する/spec.md / 保存済みの確報結果をジョブスケジューラへ返す/spec.md, tier-final-crosscheck.md / 判定 UC spec.md / 受信 UC spec.md / 通知 UC tier-ops.md |
| F-041 | minor | 一部 fixed(所有範囲内)。記録 UC の hang_suspected_at を「送信成功時刻(判定時刻ではない)」と明記(spec 計算ルール / tier 列説明 / _model-summary)。buc-spec CRUD の通知 UC 列(slot 実行 / 速報比較依頼)を `-` にし「判定 UC 経由」と注記。**deferred**: rdb-schema.yaml の列説明、cli-command-contract.yaml idempotency(alerted_at → monitor_status 遷移有無)、data-visualization.md current_limit_minutes の列説明は契約 / ui 担当へ | 記録 UC spec.md, tier-ops.md, _model-summary.yaml / buc-spec.md |

集計: fixed 12 / 一部 fixed(残りは契約側に deferred)4(F-028, F-038, F-039, F-041)/ deferred 単独 0

## 所有範囲外(参照のみ。本担当は未変更)

F-002〜F-006, F-013〜F-019, F-022, F-025〜F-027, F-029〜F-033, F-035, F-037, F-040, F-042〜F-046, SR-001, SR-002

## 契約(`_cross-cutting/`)側への要求

| # | 対象 | 要求 | 由来 |
|---|---|---|---|
| 1 | cli-command-contract.yaml `environment_variables` | テスト専用 `RELAY_GATE_NOW`(ISO 8601 UTC。本番未設定。設定時は now() の代わりに使う)を宣言する。final-crosscheck-worker.sh / hang-detector.sh が参照 | F-007 |
| 2 | cli-command-contract.yaml `shared_rules.state_codes.hang_judgement` / ui-design.md L152 | 6 値 `["NOT_TARGET", "COMPLETED", "MONITORING", "HANG_SUSPECTED", "EXEC_ERROR", "COMPARE_ERROR"]` にする(NOT_TARGET=監視対象外 → NOT_MONITORED、COMPLETED=正常終了・中止済み → COMPLETED) | F-008 |
| 3 | cli-command-contract.yaml `hang-detector.sh` stderr / idempotency | `warn: execution-spec missing run_id=...`(当該 run は判定対象外。監視記録なし。終了コード 0)を追記。artifact_layout の execution-spec.json readers に hang-detector.sh の「欠落時は skip」を反映 | F-009 |
| 4 | cli-command-contract.yaml `hang-detector.sh` / rdb-schema.yaml `slot_executions` | on 時に hang-detector.sh が `slot_executions.status`(ABORTED 判定)と、未終端の監視記録がある `rapid_crosscheck_requests.status='ABORTED'` を SELECT することを readers / used_by に反映 | F-010, F-011 |
| 5 | ui-design.md 通知メール規約 / asyncapi.yaml HangAlertMail | 「80 桁制限は 1〜13 行目のみ。14 行目の recommended_action は折り返さず 1 行(80 桁超可)。15 行目以降なし」に改定 | F-012 |
| 6 | cli-command-contract.yaml `final-crosscheck-worker.sh` exit_codes / stderr | 「RUNNING 遷移 UPDATE 0 件(lease 失効で回収済み)・終端 UPDATE 0 件(比較中に ABORTED)は `WARN ...` で終了コード 0」「カタログ 0 行は 6」を追記 | F-024, F-036 |
| 7 | cli-command-contract.yaml `final-crosscheck-runner.sh` stderr | `error: option required option=--business-date|--catalog-version` / `error: config file not found path=...` / `error: config key required key=FINAL_DB_CONN_REF path=...` / `error: target_catalog_path declaration not found path=...` を転記。polling ログのキー名は `final_crosscheck_id=` に統一(ui-design.md L433 の `request_id=` を修正) | F-023, F-038 |
| 8 | cli-command-contract.yaml 速報 / 確報 worker stderr | DB 失敗文言(`management db unavailable` / `management db connection failed`)をどちらかに統一して両 tier md に転記(確報側は現状 `management db unavailable` で統一済み) | F-038 |
| 9 | rdb-schema.yaml `monitor_records.hang_suspected_at` / cli-command-contract.yaml `hang-detector.sh` idempotency / data-visualization.md 列 8 | hang_suspected_at の説明を「ハング疑い通知の送信成功日時」に、冪等判定の根拠を「monitor_status の遷移有無」に、current_limit_minutes の説明に「速報比較依頼は hang-detector.env の RAPID_HANG_DETECT_LIMIT_MINUTES」を追記 | F-041 |
| 10 | rdra-feedback.md | 監視状態の追加遷移(中止済み ABORTED → COMPLETED、HANG_SUSPECTED_NOTIFIED → COMPLETED(中止))、hang_judgement 6 値(バリエーション「ハング検知判定結果」に監視対象外を追加)を rdra-feedback 対象として記録 | F-008, F-010, F-011 |
