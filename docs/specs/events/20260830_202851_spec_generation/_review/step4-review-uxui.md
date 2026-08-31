# Step4 Review: UX/UI 系(design 無しモード・cli)

- 対象: `_cross-cutting/ux-ui/ux-design.md` / `ui-design.md`(出力規約)/ `data-visualization.md`
- 前提: `design_available: false`、`interface_kind: cli`。`common-components.md` 非生成は正しい(指摘対象外)
- 突き合わせ先: `_inference.md` 採用値 #2 / #9 / #10 / #11、`_cross-cutting/api/cli-command-contract.yaml`、対象 UC の tier md、`docs/rdra/latest/状態.tsv`

## 判定サマリー

| severity | 件数 |
|---|---|
| blocker | 0 |
| major | 3 |
| minor | 4 |

## 指摘一覧

| # | severity | ファイル | 行 / 節 | 指摘内容 | 修正案 |
|---|---|---|---|---|---|
| 1 | major | `_cross-cutting/ux-ui/data-visualization.md` | L19-34「1. 速報比較結果参照 要約部」 | 要約部を **12 行**(`parent_run_id` / `completion` / `error_summary` を含む)と定義しているが、正本側は **9 行**で一致している: `cli-command-contract.yaml` L394(`固定順 9 行: run_id / job_id / request_status / blue_status / green_status / exit_code / worker_id / requested_at / completed_at`)、tier md `速報比較結果を参照する/tier-rapid-crosscheck.md` L28-37、`ui-design.md` L76-87 の出力例。実装時にどちらを採るか迷う | data-visualization.md の要約部を契約・tier md と同じ 9 行に揃える。`completion` / `parent_run_id` / `error_summary` を残したいなら、契約(`cli-command-contract.yaml` L394)と tier md L28-37・ui-design.md L76-87 の出力例を同時に 12 行へ更新する(どちらか一方に統一) |
| 2 | major | `_cross-cutting/api/cli-command-contract.yaml`(ux-ui との突き合わせで検出) | L556 `hang-detect-trend.sh` の `stdout` | TSV 列名が `max_elapsed_at_alert_minutes` / `last_elapsed_at_alert_minutes` となっており、列定義の正本 `data-visualization.md` L63-64(`max_elapsed_minutes_at_alert` / `last_elapsed_minutes_at_alert`)および tier md `hang_detect_limit_minutes をジョブごとに調整する/tier-ops.md` L31・L48・L109 と不一致。契約は「列定義は data-visualization.md を正とする」(L29)と宣言しているため、契約側の転記ミス | 契約 L556 の列名を `max_elapsed_minutes_at_alert` / `last_elapsed_minutes_at_alert` に修正する |
| 3 | major | `_cross-cutting/ux-ui/data-visualization.md` | L50「対象 run_id が存在しない / off 時のエラー文言」 | `rapid-crosscheck-result.sh` のエラー文言を `error: run not found run_id=...` / `error: management db is not configured (RAPID_CROSSCHECK_MODE=off)` と書いているが、契約 L395 と tier md L54 は `error: rapid crosscheck request not found run_id=...` / `error: rapid crosscheck is off; no management db to query mode=off`。同じ条件で 2 通りの文言が正本間に存在する(終了コード 3 は一致) | data-visualization.md L50 の文言を契約・tier md の文言に揃える(L50 は「終了コード 3」の記述だけ残し、文言は契約を参照する形でもよい)。なお `run-lineage.sh` / `hang-detect-trend.sh` は `management db is not configured (RAPID_CROSSCHECK_MODE=off)` で契約・tier md・data-viz が一致しており、コマンド間で off 時の文言が 2 系統ある点も横断規約(ui-design.md メッセージ表現規約)で統一を検討する |
| 4 | minor | `_cross-cutting/ux-ui/ux-design.md` | L143(IA「コマンド体系」の補足) | 「`hang-detector.sh --trend` に統合してもよい(コマンド名は Step3 の tier md で確定する)」と未確定の書きぶりが残っている。Step3 の tier md と契約では `hang-detect-trend.sh` として確定済み(契約 L518、tier-ops.md L5) | 補足を「`hang-detect-trend.sh` として確定(契約 / tier-ops md 参照)」に書き換え、統合案の記述を削除する |
| 5 | minor | `_cross-cutting/ux-ui/ux-design.md` | L182「段階的開示」 | `--show-output` の適用場面を `rapid-crosscheck-result.sh / run-lineage.sh / hang-detect-trend.sh` の 3 コマンドとしているが、契約(common_options L68-70、run-lineage L785、hang-detect-trend L520)と ui-design.md L205 では `rapid-crosscheck-result.sh` 専用。run-lineage / hang-detect-trend の段階的開示は `--verbose` / `--all` | 適用場面を「`rapid-crosscheck-result.sh`(`--show-output`)、`hang-detect-trend.sh`(`--all`)、`run-lineage.sh`(`--verbose`)」に書き分ける |
| 6 | minor | `_cross-cutting/ux-ui/ux-design.md` | L176「意図的な壁」 | 現在状態の表示項目を「run_id / job_id / role / mode / status / 開始時刻」と列挙しているが、契約 L641(abort-blue/green は 8 行: + `pid` / `artifact_dir`)、L725(abort-rapid/final は `worker_id` / `lease_until` を含む 7 行)と項目が異なる。原則説明としては許容範囲だが、tier md / ui-design.md L92-99 と読み合わせると欠落に見える | 「現在状態(契約 `stdout` の固定行。abort-blue/green は 8 行、abort-rapid/final は 7 行)」のように項目列挙を契約参照へ置き換える |
| 7 | minor | `_cross-cutting/ux-ui/ui-design.md` / `data-visualization.md` | ui-design L192「日次メールサマリー」/ data-viz L114「全体サマリー」 | 日次サマリー(arch CTP-010)を両ファイルが「範囲外・未確定(todo)」としながら、data-visualization.md 側だけが本文キー(`runs=` / `background_failed=` / … / `final_status=`)を仮採用として具体化している。ui-design.md は「警告傾向 TSV をそのまま貼る形を推奨」と別案を書いており、未確定項目の記述が 2 ファイルで分岐している | どちらか 1 箇所(通知メール規約を持つ ui-design.md)に寄せ、data-visualization.md は「ui-design.md の日次サマリー(todo)を参照」に留める。仮採用値は `docs/todo.md` 相当の todo 一覧へ 1 件として記録する |

## 観点別の確認結果(指摘なし)

| 観点 | 結果 |
|---|---|
| 1. 出力規約の具体性 / 終了コード | stdout・stderr・終了コード・実行ログ形式・メール件名/本文の行順・環境変数が具体値で記述されている。終了コード 0 / 2 / 3 / 6・中継系そのまま・`1` 不使用・worker の扱いは `_inference.md` 採用値 #2(L291)および契約 `conventions.exit_codes` / `exit_code_notes`(L10-26)と一致。各コマンドの `exit_codes` / `stdout` / `stderr`(facade / runner / rapid-* / final-* / hang-* / abort-* / run-lineage / validate-config)と矛盾なし(指摘 #1〜#3 を除く)。design-event / Storybook / コンポーネント名 / デザイントークンへの参照なし |
| 2. ux-design.md | 4 本のユーザーフローはすべてコマンド / ジョブ / メールをノードとし画面遷移なし。IA はコマンド体系(15 コマンド + runner IF)で、名称は契約の `commands[].name` と一致。UX 心理学原則は意図的な壁 / 認知負荷 / 視覚的階層 / 段階的開示など CLI に妥当で、動機づけ系を除外している。アクセシビリティ方針(非 TTY 主経路・`--yes`・ANSI なし・色非依存・TSV 8 列以内)は tier md(abort の `[ ! -t 0 ]` 判定・終了コード 2、rerun の非 TTY 主経路)と矛盾なし |
| 3. data-visualization.md | `hang-detect-trend.sh`(8 列・ソート・`--all` 既定絞り込み・off 時 3)と `run-lineage.sh`(8 列・depth 降順・自分自身を含む・off 時 3)は tier-ops md と一致。`rapid-crosscheck-result.sh` の comparison_result TSV(6 列・compared_at 昇順)は契約・tier md と一致。「チャートは対象なし」を L4 / L9 / L94 で明記 |
| 4. tier md への画面仕様混入 | `grep -rn "screens:\|storybook\|Storybook\|デザイントークン\|コンポーネント設計\|design-event\|画面仕様" E`(_review 除外)のヒットは `_inference.md` L85(「生成しない」という方針文)と `_inputs-digest.md` L28(design-event を読まない旨)の 2 件のみ。tier md にヒットなし |
| 5. 中立表現 | ux-ui 3 ファイルに製品名・サーバ名・業務名の固有名詞なし(ジョブスケジューラ / 比較ツール / 管理 DB の中立表現) |
| 6. mermaid | `ux-design.md` の 5 ブロックは `npx md-mermaid-lint` で「All Mermaid diagrams are syntactically correct」。`ui-design.md` / `data-visualization.md` に mermaid ブロックなし |

## 補足(対応不要)

- `ui-design.md` L147 の監視状態の英字コード 6 値は `docs/rdra/latest/状態.tsv` L45-56 の「監視対象外 / 監視中 / ハング疑い通知済み / 実行エラー通知済み / 比較異常通知済み / 正常終了」と 1 対 1 で対応している(採用値 #11 準拠。バリエーションとの不一致は rdra-feedback 対象として明記済み)
- 3 ファイル間の正本分担(ui-design = 横断規約 / contract = 機械可読転記 / data-visualization = TSV 列定義)は各ファイル冒頭で相互参照されており、指摘 #1〜#3 を直せば整合する
