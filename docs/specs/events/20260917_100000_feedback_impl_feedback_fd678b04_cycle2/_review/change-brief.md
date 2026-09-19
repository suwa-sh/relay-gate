# 変更の正本(change-brief): event 20260917_100000_feedback_impl_feedback_fd678b04_cycle2

- feedback request: 2026-09-17 の実装フィードバック cycle 2(CR-fd678b04-001。direct = causal = CR-fd678b04-001#1。実装フェーズ UC fd678b04「feature flag を設定する」からの spec-gap。ID / SHA は spec-event.yaml の feedback_request と source.txt)
- 利用者決定: CR 本文に「現行実装の値としては FINAL_ 接頭辞を希望する」が明記され、2026-09-17 のレビューで承認済み。そのまま採用
- trigger_event: rdra:20260908_011000_feedback_slot_status_wording, arch:20260908_015000_feedback_slot_status_wording(前段 head は前イベントと同じ。RDRA / USDM / arch / nfr / infra に変更は無い)
- 性質: 「確報の制御キー」の範囲の一意化(接頭辞 `FINAL_`)と境界を判定する BDD Scenario の追加。UC ツリー・ティア構成・状態遷移・値集合は不変。usdm[] は UC「feature flag を設定する」の SPEC-001-01 に Scenario 1 件追加

## D1: 範囲の正本を CLI 契約に置く(CR-fd678b04-001)

- `_cross-cutting/api/cli-command-contract.yaml` config_files.feature-flag.env.validation_rules: 「確報の制御キーは置かない」を「範囲は『キー名が `FINAL_` で始まるすべてのキー』(接頭辞判定。列挙ではない。大文字小文字を区別)。制御キーも final-crosscheck.env のキー(FINAL_DB_CONN_REF / FINAL_POLL_INTERVAL_SEC / FINAL_POLL_LIMIT_SEC / FINAL_LEASE_MINUTES / FINAL_WORKER_POLL_INTERVAL_SEC)の誤配置も同じ違反(終了コード 2)。`FINAL_` で始まるキーは未知キー(warn)として扱わない。範囲の正本は本項」に具体化。未知キー規則に「`FINAL_` で始まるキーは未知キーではない」を追記
- 同 error_messages: 「確報制御キーあり(キー名が `FINAL_` で始まる): `error: final crosscheck key is not allowed key=<KEY>`(2。該当キーごとに 1 行。同じキーに warn は出さない)」
- commands[validate-config.sh] の stderr 説明・終了コード 2 の条件、commands[facade.sh] の終了コード 2 の条件(同じ検証を共有。tier-facade.md「facade.sh との共有」と契約「facade.sh の起動時検証も同文」の帰結)に同じ範囲を明記

## D2: UC「feature flag を設定する」を同じ表記に揃え、境界 Scenario を追加

- spec.md 概要: 範囲(`FINAL_` で始まるキー)と正本の所在を 1 文追記
- spec.md 処理フロー(シーケンス図): 「FINAL_* キーがある」→「キー名が FINAL_ で始まるキーがある(接頭辞判定。未知キー warn より先に判定)」。未知キー warn の分岐(9 キー以外で FINAL_ で始まらないキー)を追加
- spec.md 分岐条件一覧「確報クロスチェック非起動」: 「`FINAL_CROSSCHECK_MODE` 等の確報制御キー」→ 接頭辞 `FINAL_` の判定ルール(該当キーごとに error、warn にしない、正本は CLI 契約)。「設定所有区分」行の未知キー warn に「`FINAL_` で始まるキーは除く」を追記
- spec.md 関連 USDM SPEC-001-01 行: 新 Scenario を追加し、AC「確報クロスチェックの制御設定は feature flag に含まれない」の定義側 / 実行側の注記
- spec.md E2E 異常系: Scenario「FINAL_ で始まる確報設定のキーは未知キーではなく拒否される(SPEC-001-01)」を追加(有効な並行稼働の状態に FINAL_DB_CONN_REF=final-db を加える → 終了コード 2、`error: final crosscheck key is not allowed key=FINAL_DB_CONN_REF`、error 行はその 1 行だけ、warn: unknown key は出ない)。既存 Scenario「確報の制御キーは拒否される(SPEC-001-01)」は不変
- tier-facade.md 組合せ検証: 「`FINAL_CROSSCHECK_*` キー」→「キー名が `FINAL_` で始まるキー(接頭辞判定 …)」+ 判定順序 + 正本参照。未知キー行を「9 キー以外で `FINAL_` で始まらないキー」に。ビジネスルールに範囲を追記。ティア完了条件に Scenario「validate-config_sh_feature-flag は FINAL_ で始まるキーを未知キーではなく終了コード 2 で拒否する」(FINAL_DB_CONN_REF と FINAL_CROSSCHECK_MODE の 2 キーで該当キーごとに 1 行)を追加
- `_api-summary.yaml`: stderr / 終了コード 2 の説明に範囲を追記
- `spec-event.yaml` use_cases[feature flag を設定する].usdm SPEC-001-01 scenarios に新 Scenario を追加(Scenario 参照 210 → 211 件)。usdm-acceptance-matrix.md(前提節の注記と UC-29 の対応 Scenario 列)、traceability-matrix.md(条件「確報クロスチェック非起動」行)を追従

## D3: 横断文書・記録

- decisions/spec-decision-010.yaml を追加(範囲・判定方法・判定順序・正本の所在・facade.sh との共有・境界 Scenario・却下した代替案)
- _inference.md に差分更新履歴を追記。_inputs-digest.md は event_id ヘッダーのみ更新。README.md は最新イベントと UC-29 の最終更新イベントを本イベントに更新。docs/todo.md: 新規の仮採用は無い(登録なし)
- 検証: validateAllYaml(79 YAML OK)/ validateSpecEvent PASS / validateApiSummary・validateModelSummary(UC-29 PASS)/ validateSpecProse(UC-29 findings 0)/ validateRdbSchema PASS / md-mermaid-lint OK。generateSpecEventMd.js で spec-event.md 再生成
- 第三者レビュー(toolbox:review-refute-loop。サブエージェント内発動のためテンプレ C = fresh context の Claude サブエージェント。クロスモデルではない): 観点 5(CR 完了条件 / 方針資料・USDM・RDRA 整合 / 二重定義 / Scenario 名一致 / 実装・テスト可能性)、閾値 medium。round 1: 指摘 1(P5 minor R-001: 新 Scenario の Given の前提範囲が名前参照で不明確)→ ACCEPTED(前提を明示、error 行の単独性を Then に追加)。round 2(検証パス): 指摘 0、全観点 PASS で収束。記録: _review/round-1.yaml
