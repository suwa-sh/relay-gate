# 変更の正本(change-brief): event 20260917_050000_feedback_impl_feedback_fd678b04

- feedback request: 20260917_014138_impl_feedback_fd678b04(CR-fd678b04-001 / 002。direct = causal = CR-fd678b04-001#1 / 002#1。実装フェーズ UC fd678b04「feature flag を設定する」からの spec-gap)
- 利用者決定: CR-002 本文に希望値(待機上限 4 秒 / blue → green 逐次 / TERM → 0.2 秒後 KILL / 準備失敗は終了コード 6)が明記。そのまま採用
- trigger_event: rdra:20260908_011000_feedback_slot_status_wording, arch:20260908_015000_feedback_slot_status_wording(前段 head は前イベントと同じ。RDRA / USDM / arch / nfr / infra に変更は無い)
- 性質: BDD Scenario の責務分離と契約への一元化。usdm[] の (UC, REQ, SPEC, Scenario) 集合・状態遷移・値集合は不変

## D1: 運用モード切替 Scenario の検証側 / 実行側への分離(CR-fd678b04-001)

- UC「feature flag を設定する」spec.md: Scenario「ジョブ定義を変えずに feature flag だけで運用モードを切り替える(SPEC-001-03)」を、Given ジョブ定義不変 + 並行稼働の組合せで operation_mode=parallel / When 単独本番の組合せへ変更して validate-config.sh --feature-flag / Then 終了コード 0・operation_mode=green_only・error 行なし・ジョブ定義不変、に書き換え(Scenario 名は不変)。gherkin 直後に実行側 Scenario への参照注記。「関連 USDM」SPEC-001-03 行に「※ 検証側 / 実行側は UC〈slot 実行モードを選択して runner を起動する〉の Scenario「新実装の単独本番モードでは green だけを起動し管理 DB に触れない(SPEC-001-03)」で覆う」
- UC「slot 実行モードを選択して runner を起動する」spec.md: 同 Scenario に Given「ジョブ定義は並行稼働モードのときと同じ facade.sh JOB001 のままで、変更していない」を追記。「関連 USDM」SPEC-001-03 行に「※ 実行側 / 検証側は UC〈feature flag を設定する〉…」
- 同形 Scenario の走査(全 32 UC の spec.md で `When … facade.sh` を grep): 分離したのは UC「slot ごとのジョブマップを定義する」の「hang_detect_limit_minutes の変更は次回以降の run に反映される(SPEC-008-05)」(When を validate-config.sh --job-map --verbose、Then を info: resolved の hang_detect_limit_minutes=90 + 実行中 run の execution-spec.json 不変に。実行側は UC「hang_detect_limit_minutes をジョブごとに調整する」の「調整は実行済み run に影響しない(SPEC-008-05)」とティア完了条件で覆う旨を ※ 注記)。分離対象外: 「切り替えた運用モードで業務ジョブを実行する」(UC 自体が E2E 確認)/「hang_detect_limit_minutes をジョブごとに調整する」(tier-facade が反映タイミングの契約を定義)/「slot runner の実体スクリプトを割り当てる」(runner IF・Runner Result Contract は自 UC の所有)/ 実装切替業務の runner 内部処理 UC(facade.sh は自 BUC の実行経路)。判断は decisions/spec-decision-009.yaml
- cli-command-contract.yaml commands[facade.sh].used_by_ucs から「feature flag を設定する(テストで起動…)」「slot ごとのジョブマップを定義する(テストで起動…)」を削除。uc-dependencies.md の #7 / #9 を「BDD の責務分離で依存なし」に更新
- spec-event.yaml の usdm[] は変更なし(Scenario 名不変)。usdm-acceptance-matrix.md は前提節に本イベントの注記のみ(集計値不変)

## D2: runner --help 問い合わせ規則の契約への一元化(CR-fd678b04-002)

- cli-command-contract.yaml commands[validate-config.sh] に `runner_help_probe` を追加: scope / order(blue → green 逐次)/ timeout_seconds_per_slot: 4 / timeout_action(プロセスグループへ TERM → 0.2 秒後 KILL)/ no_response_criteria(上限到達・非 0 終了・版行なし・版の値が 1 でない)/ version_line_selection(最初の 1 行)/ no_response_result(warn + `<slot>_runner_if_version=-`、終了コード 0)/ response_result / preparation_failure(`error: runner probe failed slot=... reason=...`、終了コード 6、即時終了)/ per_slot_probe_budget_seconds: 4.6 / response_time_budget(2 × 4.6 = 9.2 秒 ≤ 10 秒、残り 0.8 秒)。exit_codes に 6 を追加。stderr 説明と --feature-flag description に参照を追加
- UC「slot runner の実体スクリプトを割り当てる」tier-facade.md: 「5 秒でタイムアウト(仮採用)」を削除し契約参照へ。検証表に準備失敗(6)の行を追加。ティア完了条件に「待機上限で打ち切り両 slot 未応答でも 10 秒以内」「準備失敗は終了コード 6」の 2 Scenario を追加。spec.md のシーケンス図・データフロー表を契約参照に、E2E 異常系に待機上限の Scenario(SPEC ID なし)を追加。_api-summary.yaml に終了コード 6
- UC「feature flag を設定する」tier-facade.md: stdout 注記・終了コード表(6 の行を追加)・UC ロジックを契約参照に。spec.md データフロー図の終了コード注記。_api-summary.yaml に終了コード 6
- docs/todo.md: 5 秒の登録は無かった(更新対象なし)。新規に DIST-030(1 slot あたり予算 4.6 秒のうち回収・起動オーバーヘッド 0.4 秒。実測 9.1 秒からの導出。confidence: low)を登録

## D3: 横断文書・記録

- decisions/spec-decision-009.yaml を追加(Scenario の責務分離の規則と分離対象外の判断、runner_help_probe の値と根拠)
- _inference.md に差分更新履歴を追記。_inputs-digest.md は event_id ヘッダーのみ更新。README.md は最終更新イベントを変更 4 UC(UC-02 / UC-29 / UC-30 / UC-31)だけ本イベントに更新
- 検証: validateAllYaml(78 YAML OK)/ validateSpecProse(変更 4 UC findings 0)/ validateApiSummary・validateModelSummary(変更 4 UC PASS)/ validateSpecEvent PASS / validateRdbSchema PASS / md-mermaid-lint OK。generateSpecEventMd.js で spec-event.md 再生成
- 第三者レビュー(toolbox:review-refute-loop。サブエージェント内発動のためテンプレ C = fresh context の Claude サブエージェント。クロスモデルではない): 観点 5(CR 完了条件 / 方針資料整合 / 二重定義残存 / Scenario 名一致 / NFR 計算可能性)、閾値 medium。round 1: 指摘 1(P5: 8.4 秒予算が実測 9.1 秒と不整合)→ ACCEPTED(per_slot_probe_budget_seconds 4.6 に書き換え)。round 2: 指摘 1(P3: 判定基準の列挙が UC-30 tier md / spec.md に再掲され食い違い)→ ACCEPTED(参照化)。round 3: 指摘 0、全観点 PASS で収束。below-threshold の採用 3 件(注記の字面 / stdout 説明の参照化 / 「10 秒未満」→「10 秒以内」/「逐次実行」→「実行順」)、反証 4 件。記録: _review/round-1.yaml
