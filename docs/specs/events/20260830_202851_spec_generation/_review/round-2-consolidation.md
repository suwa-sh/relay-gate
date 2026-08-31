# round-2 consolidation(Step6.5 第 3 ラウンド統合修正。UC ⇔ 横断契約)

- 入力: `round-2-resolution-A.md` / `round-2-resolution-B.md` / `round-2-resolution-cross-cutting.md` の「契約側への要求」「UC 側に追従が必要」「deferred」
- 担当: 1 名(UC ディレクトリと `_cross-cutting/` の両方を編集)。契約(`cli-command-contract.yaml` 等)を正とする
- 区分: fixed = 本ラウンドで修正 / confirmed = 既に対応済みを確認(変更なし)

## 対応表

| # | 項目 | 対応 | 変更ファイル |
|---|---|---|---|
| 1 | F-115 速報 worker: RUNNING 遷移 0 行時の stdout(claim 4 行 + `request_status=<再 SELECT 現在値>` / `result_status=-` / `exit_code=-` / `comparison_result_id=-` / `artifact_dir: -`、実行ログ `WARN request not owned`) | fixed。UC 側の暫定(4 行のみ)を契約に合わせ、tier 出力契約 L24 / 処理フロー手順 1 / tier BDD の Then / _api-summary.stdout を書き換え | 比較ツールでジョブ単位比較を実行して結果を登録する/tier-rapid-crosscheck.md, _api-summary.yaml |
| 2 | F-135 通知 UC tier BDD の 80 桁 Then | fixed。Then を「11 行目 `artifact_dir:` を除く 1〜13 行目に 80 桁を超える行は無い」に。本文仕様(L39)の 80 桁制限記述も同旨に修正 | ハング疑い・実行エラー・比較異常を通知する/tier-ops.md |
| 3 | F-131 通知 tier BDD `error: option required option=ALERT_MAIL_TO path: ...` / 判定 tier の HANG_DB_CONN_REF 欠落の同形文言 | confirmed(通知 BDD L115、判定 tier-ops L41 / _api-summary.stderr とも契約 hang-detector.sh stderr と同文)。通知 BDD の「契約への追記を要求中」注記を「契約と同文」に更新 | ハング疑い・実行エラー・比較異常を通知する/tier-ops.md |
| 4 | F-103 claim UC / 完了通知 UC の exit 2 定型文 2 種 | confirmed。両 UC の設定節・stderr 一覧・BDD・_api-summary と契約 rapid-crosscheck-runner.sh stderr / exit 2 condition が一致(`error: config file not found path: ...` / `error: option required option=RAPID_DB_CONN_REF path: ...`。`management db is not configured mode=off` は worker の 3 専用) | — |
| 5 | F-101 復元起動 UC の処理順序 | confirmed。RS tier-ops(手順 4〜6: INSERT pid=NULL → 起動 → pid UPDATE、起動失敗は FAILED ベストエフォート)= 契約 background-rerun.sh idempotency / stderr `runner failed to start` = rdb slot_executions.used_by(RS と S が `["INSERT", "UPDATE"]`) | — |
| 6 | F-141 検証 / 追跡 UC の _api-summary.stderr に管理 DB 障害 2 文言 | confirmed。両 _api-summary に `error: management db connection failed run_id=... conn_ref=...`(6)/ `error: management db query failed run_id=...`(6)が転記済み | — |
| 7 | F-116 比較実行 UC spec.md の条件名「(spec 追加)」付記 | confirmed(spec.md 分岐条件一覧「comparison_results の登録条件(spec 追加。RDRA 条件.tsv 未登録…)」。rdra-feedback #12 起票済み) | — |
| 8 | F-108 調整 UC current_limit_minutes = judged_at 最大の行 / F-041 調整 UC 分 / F-109 終了コード 6 削除 | confirmed。spec 計算ルール L123 と tier-ops 手順 4 が「judged_at が最大の行」、tier-ops 列説明(started_at / hang_detect_limit_minutes / hang_suspected_at)は rdb-schema と同文、tier-facade / _api-summary に終了コード 6 なし | — |
| 9 | F-123 runner IF exit 6「既存 execution-spec.json の解析失敗」 | confirmed。契約 runner IF exit 6 condition に追記済み。X tier(既存 JSON の解析失敗 = 6)、V UC(`execution-spec is not readable` JSON 不正 = 6)、契約 background-rerun.sh exit 6 condition(JSON 不正・必須キー欠落)が一致。契約の「復元起動での spec 不正は 2」は runner が復元 spec を読んだ場合の runner 側終了コードで、background-rerun.sh の 6 とは別コマンドのため矛盾なし | — |
| 10 | 調整 UC `_model-summary.yaml` の `rdra_info: "管理 DB 接続設定"` | fixed。`rapid-crosscheck.env(RAPID_DB_CONN_REF)` record に `note: "RDRA 未定義(rdra-feedback #6 相当。hang-detector.env / rapid-crosscheck.env の接続設定ファイルは情報.tsv に無い)"` を追加(rdra_info は据え置き) | hang_detect_limit_minutes をジョブごとに調整する/_model-summary.yaml |
| 11 | A 要求 5 / 6: 比較定義 UC の共通形式文言と pid UPDATE 失敗の実行ログを契約に列挙 | fixed。validate-config.sh stderr「行の値不正」の例に `host is empty` / `script_path is not absolute` / `compare_options is missing {blue} or {green}` / `job_id is not final-crosscheck for comparison_type=full` / `<column> is empty`(対象カタログは job_id= 無し `target_type is not in table,file`)を同文で追加。facade.sh execution_log に `ERROR management db update failed table=slot_executions run_id=...`(pid UPDATE 失敗。background-rerun.sh も同文)を追加 | _cross-cutting/api/cli-command-contract.yaml |
| 12 | B 要求 3(final worker `launch failed`)/ 4(rapid-crosscheck-result.sh stderr 2 文言)/ 5(hang-detector.sh config 系文言) | confirmed(契約 final-crosscheck-worker.sh stderr L507、rapid-crosscheck-result.sh stderr L427、hang-detector.sh stderr L538 に反映済み)。確報 worker tier BDD の「契約への明記を要求中」注記を「契約 stderr と同文」に更新 | 比較ツールで日次全量比較を実行して結果を保存する/tier-final-crosscheck.md |
| 13 | 最終 grep | fixed。`management db unavailable` が ui-design.md の「使わない」注記に文字列として残っていたため「『unavailable』系の旧文言は使わない」に言い換え。他パターンは 0 件 | _cross-cutting/ux-ui/ui-design.md |

集計: fixed 6 / confirmed 7。未解決(deferred)なし。

## 最終 grep(`_review/` を除く E 配下)

| パターン | 件数 |
|---|---|
| `management db unavailable` | 0 |
| `NOT_TARGET(正常終了` | 0 |
| `既定 60 分` | 0 |
| `error: --[a-z-]+ required` | 0 |
| `missing option option=` | 0 |
| `RAPID_LEASE_MINUTES` | 0 |
| `finished_at`(履歴記述以外) | 0(rdb-schema.yaml の統一経緯 2 箇所のみ) |
| `要求中` / `契約側へ要求` / `契約担当へ` | 0 |

## 検証結果

| 検証 | 結果 |
|---|---|
| `validateAllYaml.js E` | PASS(error 0) |
| `validateRdbSchema.js rdb-schema.yaml` | PASS(7 tables) |
| `validateApiSummary.js` / `validateModelSummary.js`(全 32 UC dir) | すべて PASS |
| `validateSpecEvent.js E` | PASS |
| `@asyncapi/cli validate asyncapi.yaml` | 0 errors / 0 warnings / 1 info(asyncapi-latest-version。既存) |
| `md-mermaid-lint`(変更 md 4 件: 速報比較実行 tier / 通知 tier / 確報比較実行 tier / ui-design.md) | すべて「All Mermaid diagrams are syntactically correct」 |
