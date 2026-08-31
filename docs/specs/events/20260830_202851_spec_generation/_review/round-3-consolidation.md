# Round 3 Consolidation(UC ⇔ 横断契約の統合修正)

- 対象: `_review/step4-review-resolution.md` と `step3-round-2-G1〜G4-resolution.md` に残った「契約側への要求」「UC 側に追従が必要」「deferred」
- 担当: 1 名(UC ディレクトリと `_cross-cutting/` の両方を編集)
- 区分: fixed = 本ラウンドで修正 / confirmed = 既に対応済みを確認 / skipped = 意図的に見送り(理由を記載)

## 1. 確定した決定 1〜12 の対応

| # | 項目 | 対応 | 変更ファイル |
|---|---|---|---|
| 1 | 必須オプション欠落の定型文を `error: option required option=--xxx` に統一 | fixed。`missing option` は契約 1 箇所 + UC「速報クロスチェック runner へ完了通知を送信する」3 ファイルに残っていたので置換。ui-design.md「メッセージ表現規約」に定型文を 1 行追加 | cli-command-contract.yaml(rapid-crosscheck-runner.sh stderr)、ui-design.md、完了通知 UC の tier-rapid-crosscheck.md / _api-summary.yaml |
| 2 | worker_id 既定値 `{hostname}-{pid}` のホスト名 `.` → `-` 置換 | fixed。契約 `worker_id_default` に明記(速報・確報共通)。rdb-schema の worker_id 2 列、速報 claim UC の tier md / spec.md に追記。確報 claim UC は G3 で記載済み(confirmed) | cli-command-contract.yaml、rdb-schema.yaml、速報比較依頼を claim する/tier-rapid-crosscheck.md・spec.md |
| 3 | `execution_spec_example` に `restored_at`(リラン時のみ) | fixed。`execution_spec_rules` に「リラン時のみ `"restored_at": "2026-08-30T12:00:00Z"` を持つ。通常起動の例(execution_spec_example)は節を持たない」を追加(通常起動の例 JSON 自体は変更しない) | cli-command-contract.yaml |
| 4 | `exitcode.txt` content に「6 = runner 起動失敗(background-rerun の gateway が書く)」 | fixed(未追加だった)。UC「復元起動」tier-ops.md 手順 4 の記述と同文 | cli-command-contract.yaml `artifact_layout.files[exitcode.txt]` |
| 5 | `validate-config.sh --job-map` の stderr 例を `error: hang_detect_limit_minutes is not a non-negative integer line=N job_id=... value=...` に統一 | fixed。契約に例を追記。UC「slot ごとのジョブマップを定義する」「hang_detect_limit_minutes をジョブごとに調整する」は既に同文(confirmed)。UC「ジョブマップで JOB_ID から実行先を解決する」の runner 側メッセージ(`job_id=... slot=... value=...`、line 無し)は validate-config ではなく runner 起動時の解決エラーのため対象外として維持 | cli-command-contract.yaml `validate-config.sh.stderr` |
| 6 | `--role final-crosscheck` は enum 外 → 終了コード 2 | fixed。UC「リラン対象を検証する」の tier-ops.md(引数表 / 出力契約表の `role is not supported` 行削除 / 終了コード 2 条件 / 事前検証表の `unsupported_role` 行)、spec.md(トレーサビリティ 2 行 + BDD シナリオを終了コード 2 `error: invalid value option=--role value=final-crosscheck` に変更)、_api-summary.yaml(option description / stderr / exit 2・3 meaning)を契約に追従 | リラン対象を検証する/tier-ops.md・spec.md・_api-summary.yaml |
| 7 | `RAPID_LEASE_SEC` / `RAPID_POLL_INTERVAL_SEC` / `RAPID_DB_CONN_REF` / `rapid-crosscheck.env` に統一 | confirmed。`RAPID_LEASE_MINUTES` / `RAPID_POLL_INTERVAL_SECONDS` / 「datastore 側で定義」は `_review/` 以外に 0 件 | — |
| 8 | 完了通知失敗時の stderr.log 文言を `warn: completion notice failed run_id=... role=... exit_code=N` に統一 | fixed。UC「完了通知を送信する」の tier-facade.md(出力契約 / 実行ログ / 復旧手順 / BDD)、spec.md(トレーサビリティ / BDD)、_api-summary.yaml を追従。実行ログ行は同内容を `WARN completion notice failed ...`(ログ行形式の LEVEL 表記)とした。UC「実装スクリプトを実行して Runner Result を出力する」は通知失敗文言を持たない(完了通知 UC を参照)ため変更なし | 完了通知 UC の tier-facade.md / spec.md / _api-summary.yaml |
| 9 | UC「速報比較依頼だけを新規作成する」の payload 記述 | confirmed。tier-rapid-crosscheck.md L52 は「依頼レコードの列 + 参照先(rapid_runs / parallel_runs.parent_run_id は JOIN した派生値で依頼テーブルの列ではない)」に修正済み | — |
| 10 | UC「実行を ABORTED へ遷移させる」の COMPLETED 不更新 | confirmed。tier-ops.md 併更新行 / 状態遷移一覧 / BDD(`COMPLETED の parallel_runs を変更しない`)、spec.md 状態遷移一覧(L132)・BDD に明記済み | — |
| 11 | HANG_SUSPECTED_NOTIFIED → COMPARE_ERROR_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPLETED の整合 | fixed(補強)。asyncapi HangAlertMail は kind / level / request_status のみで監視状態の遷移を記述せず矛盾なし。ui-design.md「ハング検知判定結果」は判定 5 値(COMPARE_ERROR 含む)で矛盾なし。rdb-schema.yaml `monitor_records.monitor_status` の description は値の列挙だけだったので遷移(MONITORING → 4 状態、HANG_SUSPECTED_NOTIFIED → 3 状態。rdra-feedback #7)を追記 | rdb-schema.yaml |
| 12 | `comparison_results.comparison_type` description | confirmed。`job(速報)/ full(確報)` + 比較定義なしは INSERT しない旨あり | — |

## 2. resolution.md の要求・deferred の確認

### step4-review-resolution.md「UC 側に追従が必要になった変更」

| 契約の変更 | 状態 |
|---|---|
| `rapid-crosscheck.env` / `RAPID_*_SEC` | confirmed(#7) |
| `background-rerun.sh --role` enum から final-crosscheck 削除 | fixed(#6) |
| off 時の `--role rapid-crosscheck` は `management db is not configured (RAPID_CROSSCHECK_MODE=off) ...`(3) | confirmed。tier-ops.md 出力契約表・事前検証表・「元状態の解決」・BDD に反映済み |
| abort-* の parallel_runs 併更新(COMPLETED 不更新) | confirmed(#10) |
| 比較定義なしは INSERT せず FAILED / error_summary | confirmed。UC「比較ツールでジョブ単位比較を実行して結果を登録する」spec.md / tier-rapid-crosscheck.md に `comparison definition not found` あり |
| 完了通知失敗時の runner 挙動 | fixed(#8) |
| asyncapi `RapidCrosscheckRequest` の 3 プロパティ削除 | confirmed(#9) |
| `hang-detect-trend.sh` TSV 列名 | 追従不要(記載どおり) |

### step4-review-resolution.md の deferred(15 件)

| 出典 | 状態 |
|---|---|
| datastore #1 `finished_at` | confirmed。UC 側に 0 件(rdb-schema `_review_notes` / completed_at の description の履歴記述のみ) |
| datastore #7 / G3 #6 monitor_records インデックス列 | confirmed。UC「監視記録を保存する」tier-ops.md / _model-summary.yaml は `(job_id, role, judged_at)` |
| G1 #11 runner IF exit 6 | confirmed。G1 resolution C-3 で UC 側を契約の 2 / 6 区分に合わせ済み。契約変更不要 |
| G2 #1 / #2 UC 側(クラッシュ耐性・BDD Then) | fixed(#8)/ confirmed(#比較定義なし) |
| G2 #3 UC 側表記 | confirmed(#7) |
| G2 #8 BDD Given の具体化 | confirmed。完了通知 UC spec.md BDD は「rapid_runs の UPDATE が SQL エラー(権限なし)」→ `management db update failed`(6)で契約の 2 種区分と整合 |
| G3 #1 遷移 | fixed(#11) |
| G3 #3 exitcode.txt 解釈 | confirmed。UC「経過時間と終了状態を判定する」spec.md / tier-ops.md は `exit_code=-` + `WARN invalid exitcode` |
| G3 #5 worker_id 文字種 | fixed(#2) |
| G3 #7 `judged` ログ行 | confirmed。UC 側は job_id なし(契約 `--verbose` 説明と同形式) |
| G3 #12 `FINAL_POLL_LIMIT_SEC` | confirmed。tier-final-crosscheck.md は `integer(>=1)` |
| G4 #5 option required | fixed(#1) |
| G4 #11 restored_at | fixed(#3) |
| G4 #13 exitcode.txt=6 | fixed(#4) |
| G4 #14 off 時の `--role rapid-crosscheck` | confirmed(上表) |
| G4 #17 runner IF idempotency 両経路 | confirmed。UC「実装スクリプトを実行して Runner Result を出力する」tier-facade.md「冪等性」に通常起動 / 復元起動の両経路を記載済み |

### G1〜G4 resolution「契約側への要求」

| 要求 | 状態 |
|---|---|
| G1 C-1 used_by_ucs 追加、C-2 comparison_type、C-3 変更不要 | confirmed(step4 契約側で対応済み) |
| G2 C1〜C4, C6〜C8 | confirmed(step4 契約側で対応済み) |
| G2 C5 通知失敗文言 | fixed(#8。契約の `warn: completion notice failed` を正とし UC 側を変更) |
| G3 1〜3 | confirmed(step4 契約側で対応済み) |
| G3 4 worker_id `.` 置換 | fixed(#2) |
| G4 1〜3, 5, 6, 9 | confirmed(step4 契約側で対応済み) |
| G4 4 option required | fixed(#1) |
| G4 7 restored_at | fixed(#3) |
| G4 8 exitcode.txt=6 | fixed(#4) |
| G4 10 validate-config stderr | fixed(#5) |

skipped: なし。

## 3. 横断的な最終 grep チェック(`_review/` を除く E 配下)

| # | パターン | 結果 |
|---|---|---|
| 1 | `finished_at` | 0 件(rdb-schema の `_review_notes` と completed_at description の「混在していたため統一」の履歴記述のみ) |
| 2 | `alerted_at` を monitor_records のインデックス列として使用 | 0 件(列 `alerted_at` 自体は情報.tsv 由来の正規列として存続。インデックスは `(job_id, role, judged_at)`) |
| 3 | `-FINAL-`(大文字) | 0 件 |
| 4 | `hang-detector.sh --trend` | 0 件 |
| 5 | `YYYYMMDD` | 0 件 |
| 6 | `screens:` / `Storybook` / `デザイントークン` in `tier-*.md` | 0 件 |
| 7 | 固有名(製品名・サーバ名・ドメイン) | 0 件(`openapi.yaml` の `relay-gate.example.com` はバリデータ互換スタブのプレースホルダ) |
| 追加 | `missing option` / `role is not supported` / `unsupported_role` / `rapid crosscheck notify failed` / `RAPID_LEASE_MINUTES` / `RAPID_POLL_INTERVAL_SECONDS` / `datastore 側で定義` | 0 件 |

## 4. 検証結果

| 検証 | 結果 |
|---|---|
| `validateAllYaml.js E` | PASS(error 0) |
| `validateRdbSchema.js rdb-schema.yaml` | PASS(7 tables) |
| `validateApiSummary.js` / `validateModelSummary.js`(`_api-summary.yaml` を持つ 32 ディレクトリ) | すべて PASS(fail 0) |
| `@asyncapi/cli validate asyncapi.yaml` | 0 errors / 0 warnings / 1 info(バージョン推奨のみ) |
| `md-mermaid-lint`(変更した md 8 ファイル) | All OK |

## 5. 変更ファイル一覧

- `_cross-cutting/api/cli-command-contract.yaml`
- `_cross-cutting/datastore/rdb-schema.yaml`
- `_cross-cutting/ux-ui/ui-design.md`
- `クロスチェック業務/速報クロスチェックフロー/速報クロスチェック runner へ完了通知を送信する/{tier-facade.md, tier-rapid-crosscheck.md, spec.md, _api-summary.yaml}`
- `クロスチェック業務/速報クロスチェックフロー/速報比較依頼を claim する/{tier-rapid-crosscheck.md, spec.md}`
- `実行復旧業務/background 側リランフロー/リラン対象を検証する/{tier-ops.md, spec.md, _api-summary.yaml}`

## 6. 残課題(次工程)

- traceability-matrix.md / uc-dependencies.md / usdm-acceptance-matrix.md は本ラウンドで未変更(別担当で再生成)。UC「リラン対象を検証する」の BDD シナリオ名変更(「未対応の role(final-crosscheck)は事前検証 NG」→「enum 外の role(final-crosscheck)は引数エラー」)は再生成時に追従される
