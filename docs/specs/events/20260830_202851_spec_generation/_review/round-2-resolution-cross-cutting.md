# round-2 反証レビュー 解決記録(横断契約側。Step6.5 第 3 ラウンド)

> 対象 = `_cross-cutting/api/*` / `_cross-cutting/datastore/*` / `_cross-cutting/ux-ui/*` / `_cross-cutting/rdra-feedback.md` / `_cross-cutting/uc-dependencies.md`。
> UC ディレクトリ・traceability-matrix.md / usdm-acceptance-matrix.md は別担当のため未修正(UC 側追従が必要な項目は末尾に列挙)。
> 区分: fixed = 契約側を修正 / no-change = 契約側は正しく UC 側の追従のみ / deferred = 見送り(理由を記載)。

## 検証結果

| 検証 | 結果 |
|---|---|
| `validateAllYaml.js E` | PASS(error 0) |
| `validateRdbSchema.js rdb-schema.yaml` | PASS(7 tables) |
| `@asyncapi/cli validate asyncapi.yaml` | 0 errors / 0 warnings / 1 info(asyncapi-latest-version。既存) |
| `@redocly/cli lint openapi.yaml` | valid(error 0、warning 1 = no-server-example-com。既存スタブ) |
| `md-mermaid-lint ui-design.md / rdra-feedback.md / uc-dependencies.md` | All OK |

## 解決表

略記: contract = `_cross-cutting/api/cli-command-contract.yaml`、rdb = `_cross-cutting/datastore/rdb-schema.yaml`、ui = `_cross-cutting/ux-ui/ui-design.md`、async = `_cross-cutting/api/asyncapi.yaml`、fb = `_cross-cutting/rdra-feedback.md`、dep = `_cross-cutting/uc-dependencies.md`

### 確定した決定

| finding / 項目 | severity | resolution | 変更内容 | 変更ファイル |
|---|---|---|---|---|
| F-110 | minor | fixed | rapid / final worker の exit 0 meaning「warn: を出して 0」を「実行ログに `WARN request already terminal ...` を残して 0(stderr には出さない)」に修正。stderr 欄と一致 | contract |
| F-108 | major | fixed | hang-detect-trend.sh stdout に「current_limit_minutes は job_id × role で集計期間内の `judged_at` 最大の監視記録行の値。started_at では選ばない」を明記(data-visualization.md 2. が正のまま) | contract |
| 暗黙参照 #6〜#12(7 件) | — | fixed | facade.sh(UC-04 / UC-29 / UC-30 / UC-31)、abort-final-crosscheck.sh(UC-15)、run-lineage.sh(UC-27)、rapid-crosscheck-result.sh(UC-01)の `used_by_ucs` に「(テストで起動: …)」/「(書式参照: …)」注記付きで追加。dep の検出結果を「解消済み(契約 used_by_ucs)」表に更新(UC 側 _api-summary への追加は不要) | contract, dep |

### 横断側に向いた major / minor

| finding | severity | resolution | 変更内容 | 変更ファイル |
|---|---|---|---|---|
| F-101 | major | fixed(契約部分) | background-rerun.sh idempotency に「on 時の slot_executions は facade.sh と同じく起動前 pid=NULL INSERT → 起動後 pid UPDATE、起動失敗は FAILED ベストエフォート UPDATE」を追加。stderr `runner failed to start` に同旨。rdb slot_executions.used_by 復元 UC を ["INSERT", "UPDATE"] に変更。UC 側(spec / tier-ops / _model-summary の処理順序)は UC 担当 | contract, rdb |
| F-103 | major | fixed(契約部分) | rapid-crosscheck-runner.sh stderr に `error: config file not found path: ...`(2)/ `error: option required option=RAPID_DB_CONN_REF path: ...`(2)/ `error: management db connection failed run_id=... conn_ref=...`(6)を追加。exit 2 condition に env 欠落を追加し、`management db is not configured` は worker の mode=off(3)専用と明記。UC 側(claim UC / 完了通知 UC の文言置換)は UC 担当 | contract |
| F-104 | major | fixed(契約部分) | facade.sh execution_log に `INFO parallel_run status changed from=RUNNING to=COMPLETED run_id=...` を追加。UC 側(M tier の `ERROR management db update failed table=parallel_runs ...` への置換)は UC 担当 | contract |
| F-106 | major | fixed(契約部分) | final-crosscheck-worker.sh stderr の `compare tool launch failed` に「依頼は FAILED exit_code=6 error_summary=`launch failed`(速報 worker と同じ値)」を明記。UC 側の文言置換は UC 担当 | contract |
| F-112 | minor | fixed(契約部分) | rapid-crosscheck-result.sh stderr に `error: option required option=--run-id` / `error: invalid value option=--run-id|--limit value=...` / `error: unknown option option=...`(2)を追加。UC 側の tier BDD 置換は UC 担当 | contract |
| F-115 | minor | fixed(契約部分) | rapid-crosscheck-worker.sh stdout に「RUNNING 遷移の条件付き UPDATE が 0 行のときは claim 4 行に続けて request_status=<再 SELECT した現在の status> / result_status=- / exit_code=- / comparison_result_id=- / artifact_dir: - を出して 0(実行ログ `WARN request not owned run_id=... status=...`)」を追加。UC 側(tier 出力契約・BDD L142 の Then)は UC 担当 | contract |
| F-120 | minor | fixed(契約部分) | rdb slot_executions.used_by の S(slot 実行モードを選択して runner を起動する)を ["INSERT", "UPDATE"] に変更。buc-spec CRUD 表は UC 担当 | rdb |
| F-123 | minor | fixed | runner IF exit 6 condition に「既存 execution-spec.json の解析失敗(通常起動で他 slot が書いた JSON が不正。復元起動での spec 不正は 2)」を追加(X 側の 6 を契約に取り込む) | contract |
| F-125 | minor | fixed | final-crosscheck-runner.sh stderr の polling 上限超過を `error: polling limit exceeded final_crosscheck_id=... status=... limit_sec=...` に変更(UC 側 3 箇所に揃える。UC 側変更不要) | contract |
| F-131 | minor | fixed(契約部分) | hang-detector.sh stderr に `error: config file not found path: ...`(2)/ `error: option required option=HANG_DB_CONN_REF|ALERT_MAIL_TO|ALERT_MAIL_CMD path: ...`(2)/ `error: ALERT_MAIL_CMD is not executable value=... path: ...`(2)/ `error: unknown option option=...`(2)を追加。UC 側(通知 tier BDD の `ALERT_MAIL_TO required path=` 置換、判定 tier 出力契約)は UC 担当 | contract |
| F-133 | minor | fixed | hang-detector.sh exit 0 meaning の「ABORTED 済みで監視記録が無い対象は走査しない」を速報比較依頼に限定し、background slot は成果物起点の走査のため監視記録の有無によらず判定 COMPLETED(記録 UC が COMPLETED を UPSERT)と明記。判定 UC の _model-summary(依頼: 未終端の監視記録がある ABORTED のみ / slot: ABORTED → COMPLETED)と tier BDD に一致。UC 側変更不要 | contract |
| F-135 | minor | fixed | async HangAlertMail.recommended_action を「本文 14 行目(1 行。折り返さず 80 桁超可。15 行目以降なし)」に修正、artifact_dir を 80 桁制限の例外と明記。channel description にも同旨。ui「行長」を「1〜13 行目のうち 11 行目 artifact_dir を除く行に適用。BDD の検証も 11 行目を除外」に修正。UC 側(通知 tier BDD L104 の Then を「11 行目を除く 1〜13 行目」に)は UC 担当 | async, ui |
| F-136 | minor | fixed | rdb monitor_records.monitor_status の COMPLETED 説明を「正常終了・中止済み対象の終端」にし、遷移「MONITORING / HANG_SUSPECTED_NOTIFIED → COMPLETED(監視対象が ABORTED になった場合。rdra-feedback.md #11)」を追記 | rdb |
| F-141 | minor | fixed(契約部分) | background-rerun.sh stderr 事前検証節に `error: management db connection failed run_id=... role=... conn_ref=...`(6)/ `error: management db query failed run_id=...`(6)を転記。両 UC の _api-summary.stderr への転記は UC 担当 | contract |
| F-116 | minor | fixed(横断部分) | fb #12 に条件「comparison_results の登録条件」の RDRA 追加候補を起票(RDRA 更新まで Spec 側は条件名に「(spec 追加)」を付す方針)。spec.md 分岐条件一覧への「(spec 追加)」付記は UC 担当 | fb |

### 契約側は正しく UC 側の追従のみ(no-change)

| finding | severity | resolution | 根拠 |
|---|---|---|---|
| F-032 | major | no-change | 契約 validate-config.sh(値必須・共通形式・warn 文言)は round-1 で確定済み。UC 側の引数表・文言の追従のみ |
| F-105 | major | no-change | 契約 runner IF idempotency `ERROR slot_executions update affected 0 rows ...` が正。R tier / _model-summary の追従 |
| F-107 | major | no-change | 契約 `error: invalid value option=--business-date value=...` が共通形式。UC 側の追従 |
| F-109 | major | no-change | 契約 validate-config.sh は 0 / 2 のみ。読み取り不可は `error: config file is not readable path: ...`(2)。調整 UC 側で 6 を削除 |
| F-102 / F-019 / F-031 / F-041 / F-111 / F-113 / F-114 / F-117 / F-118 / F-119 / F-121 / F-122 / F-124 / F-126 / F-127 / F-128 / F-129 / F-130 / F-132 / F-134 / F-137 / F-138 / F-139 / F-140 / F-142 | major / minor | no-change | いずれも契約・ui-design・rdb-schema・data-visualization の記述が正で、UC ディレクトリ側の転記・BDD の修正のみ(round-2.yaml の suggested_fix どおり)。横断側に変更箇所なし |

deferred: なし。

## UC 側に追従が必要な変更(本ラウンドで契約側を先に確定したもの)

| 契約の変更 | 追従先 UC | 内容 |
|---|---|---|
| F-115 rapid-crosscheck-worker.sh stdout(RUNNING 遷移 0 行) | 比較ツールでジョブ単位比較を実行して結果を登録する | tier 出力契約 L47 と BDD L142 の Then に「claim 4 行 + request_status=<現在値> / result_status=- / exit_code=- / comparison_result_id=- / artifact_dir: -」を追加 |
| F-125 polling limit exceeded に `status=` を採用 | 確報比較依頼を登録して終端状態まで待機する / 確報クロスチェック結果を確認する | UC 側の既存文言(status= 付き)のまま。変更不要 |
| F-123 runner IF exit 6 に解析失敗を追加 | execution-spec.json を確定保存する | X tier / _api-summary の 6 は契約と一致。変更不要 |
| F-133 hang-detector.sh 走査規則を依頼 / slot で分離 | background 実行の経過時間と終了状態を判定する | 判定表・BDD(監視記録なしの ABORTED slot → COMPLETED)は契約と一致。変更不要 |
| F-135 artifact_dir 行を 80 桁制限の例外に | ハング疑い・実行エラー・比較異常を通知する | tier BDD L104 の Then を「11 行目 artifact_dir を除く 1〜13 行目に 80 桁を超える行は無い」に変更 |
| F-131 hang-detector.sh 設定エラー定型文 | ハング疑い・実行エラー・比較異常を通知する / background 実行の経過時間と終了状態を判定する | 通知 tier BDD L115 を `error: option required option=ALERT_MAIL_TO path: ...` に、判定 tier 出力契約に HANG_DB_CONN_REF 欠落の同形文言を追加 |
| F-103 rapid-crosscheck-runner.sh env 欠落の定型文 | 速報比較依頼を claim する / 速報クロスチェック runner へ完了通知を送信する | `management db is not configured`(2)を定型文 2 種(config file not found / option required option=RAPID_DB_CONN_REF)に置換 |
| F-101 background-rerun.sh の起動前 INSERT | 元の execution-spec.json から復元して新しい run_id で起動する | 処理順序を「slot_executions INSERT(pid=NULL) → runner 起動 → pid UPDATE」に、起動失敗時は FAILED ベストエフォート UPDATE に変更 |
| F-141 background-rerun.sh の管理 DB 障害文言 | リラン対象を検証する / リラン結果を parent_run_id で追跡する | _api-summary.stderr に 2 文言を転記 |
| F-116 条件名の扱い | 比較ツールでジョブ単位比較を実行して結果を登録する | spec.md 分岐条件一覧の条件名に「(spec 追加)」を付記(rdra-feedback #12 参照) |
