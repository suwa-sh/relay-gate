# 変更の正本(change-brief): event 20260908_062000_feedback_spec_machine_readable

- feedback request: 20260908_spec_machine_readable(CR-c770d8f0-020 / 021 / 022。direct = causal = CR-c770d8f0-020#1 / 021#1 / 022#1)
- 利用者決定: 2026-09-08 D1 = A(state_codes は値の複製 + derived_from)/ D2 = A(comparison_type の enum は [job, full])。CR 本文に明記。そのまま採用
- trigger_event: rdra:20260908_011000_feedback_slot_status_wording, arch:20260908_015000_feedback_slot_status_wording(前段 head は前イベントと同じ)
- 性質: 記述の機械可読化と正本の一本化のみ。実装挙動・状態遷移・値集合は不変

## D1: spec-event.yaml `use_cases[].usdm` の投入(CR-c770d8f0-020)

- 32 UC すべてに `usdm: [{req_id, spec_id, scenarios[]}]` を追加(133 行 / Scenario 参照 210 件)。内容は各 spec.md「関連 USDM」表と同内容
- Step6.5 round-1 の R-001 / R-002 で、usdm-acceptance-matrix.md に前イベント以前から記録されていた表の記載誤り・記載漏れ 4 行を表と usdm[] の両方で解消した: UC-30 SPEC-002-03 行(「facade は設定された runner を runner IF で起動するだけである(SPEC-002-03)」を先頭に併記)、UC-29 SPEC-001-03 行(「ジョブ定義を変えずに feature flag だけで運用モードを切り替える(SPEC-001-03)」)、UC-18 SPEC-008-01 行(「上限内は継続監視と判定する(SPEC-008-01)」)/ SPEC-008-02 行(「ハング疑い通知後の速報比較依頼も再判定する(SPEC-008-02)」)。Scenario 参照は 206 → 210 件。SPEC ID を接尾辞に持つ Scenario で usdm[] から参照されないものは 0 件
- `scenarios[]` は当該 spec.md の BDD `Scenario:` 名(接尾の `(SPEC-xxx-yy)` を含む完全名)と完全一致。Scenario を持たない対応は無かった(`scenarios: []` は 0 件)
- 各 spec.md「関連 USDM」表の「対応 BDD Scenario」列を整えた: 実 Scenario の完全名を「 / 」で区切って列挙し、Scenario 名以外の補足(「受け入れ条件 8 件:」「(AC1 / AC5)」「…の実行側は UC〈…〉で覆う」等)は「※」以降へ移した。表の直後に「機械可読の正本は spec-event.yaml の use_cases[].usdm」の注記行を追加。表の (REQ, SPEC) 行集合と行数(133)は不変
- 表側で Scenario 名の接尾辞を省いていた UC(実装切替業務 / 適用構成業務の 11 UC 等)は完全名に揃えた。複数 SPEC を持つ Scenario(例: `(SPEC-010-01 / SPEC-010-03)`)は括弧内の「 / 」で機械分割すると壊れるため、実名との照合で分解した(事前検出 19 箇所)
- `validateSpecEvent.js`: usdm warning 32 → 0、エラー 0

## D2: rdb-schema.yaml 列挙列 14 列の `enum[]`(CR-c770d8f0-021)

| テーブル.列 | enum | 出所 |
|---|---|---|
| parallel_runs.status | STARTED / RUNNING / COMPLETED / ABORTED | 状態「並行稼働実行」 |
| slot_executions.slot | blue / green | バリエーション「実装スロット」 |
| slot_executions.mode | foreground / background | バリエーション「slot 実行モード」(off はレコードを作らないため含めない) |
| slot_executions.status | RUNNING / SUCCEEDED / FAILED / ABORTED | 状態「slot 実行」 |
| rapid_runs.blue_status / green_status | SUCCEEDED / FAILED | 完了結果(nullable。未受信は NULL) |
| rapid_runs.completion_status | PENDING / ONE_COMPLETED / BOTH_SUCCEEDED / ANY_FAILED / REQUEST_CREATED | 状態「速報実行の完了状況」5 値の英字コード |
| rapid_crosscheck_requests.status / final_crosscheck_requests.status | REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED | 状態「クロスチェック依頼」 |
| comparison_results.comparison_type | job / full | バリエーション「比較種別」(D2 = A。速報側に現れるのは job のみと description に残す) |
| comparison_results.status | OK / NG / FAILED | バリエーション「比較結果ステータス」の英字コード |
| monitor_records.role | blue / green / rapid-crosscheck | バリエーション「リラン対象 role」(final-crosscheck は監視対象外) |
| monitor_records.target_type | background_slot / rapid_request | 情報「監視記録」属性「監視対象種別」 |
| monitor_records.monitor_status | NOT_MONITORED / MONITORING / HANG_SUSPECTED_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED / COMPLETED | 状態「監視状態」6 値の英字コード |

- description は「値: A(…), B(…)」の列挙を除去し、各値の意味・遷移・条件の説明だけを残した(「取りうる値は enum」と明記)。enum と食い違う値は無い
- ファイル冒頭コメントに「列挙列の値集合は columns[].enum を正本とし、cli-command-contract.yaml の state_codes は複製」を追記
- `datastore-schema.md` は `generateDatastoreMd.js` で再生成後、enum を type 列(`string (enum: …)`)に追記した(生成スクリプト 1.15.1 は enum を出力しないための後処理。14 列)
- `validateRdbSchema.js`: enum warning 14 → 0、エラー 0、PASS

## D3: cli-command-contract.yaml `shared_rules.state_codes` の derived_from 化(CR-c770d8f0-022)

- DB 対応 6 項目(parallel_run_status / slot_execution_status / request_status / rapid_run_completion / monitor_status / comparison_result_status)を `{derived_from: {table, column}, values: [...]}` に変更(D1 = A)。values は rdb-schema.yaml の enum と完全一致(複製)
- request_status の derived_from は `rapid_crosscheck_requests.status` と `final_crosscheck_requests.status` の 2 要素配列
- DB 非対応 5 項目(slot_mode / role / hang_judgement / alert_level / alert_kind)は `{source, values}`。source は RDRA バリエーション名(「slot 実行モード」「run role(成果物ディレクトリ区分)」「ハング検知判定結果」「通知レベル」)。alert_kind は RDRA に同名バリエーションが無いため通知メール規約(ui-design.md)を出所として記した
- 冒頭 `note` に「values は rdb-schema.yaml の enum の複製。不一致は rdb-schema を正とし、実装フェーズのドリフトテストで一致を検証する」を明記
- 遷移説明(*_transitions / *_labels / *_derivation / hang_judgement_to_monitor_status)は不変。state_codes を参照する本文(commands[].notes / idempotency、ui-design.md、各 UC の tier-*.md、usdm-acceptance-matrix.md、uc-dependencies.md)は参照名を変えないため追従しない
- 既存バリデータへの影響: `validateAllYaml.js`(76 YAML すべて parse OK)/ `validateApiSummary.js` / `validateModelSummary.js`(32 UC 全件 PASS)/ `validateSpecEvent.js`(PASS)。`compileContracts.js` / `compileRdbSchema.js` は catalog 方式(contracts.json / 分割 RDB)専用で、本プロジェクト(legacy 形式)では前イベントでも実行対象外(contracts.json 不在 / `yaml` モジュール不在で終了)

## D4: 横断文書の再集計と解消記録

- `usdm-acceptance-matrix.md`: 集計元を `spec-event.yaml` の usdm[] に切り替えて再集計。受け入れ条件 122 / SPEC 50 / 振る舞い SPEC の対応率 49 / 49 = 100% / 未対応 SPEC-011-05 の 1 件で既存値と一致。対応表の「対応 UC」集合と usdm[] 由来の集合の差分 0(スクリプトで照合)。前提節の「契約 shared_rules.state_codes で照合」を「rdb-schema.yaml の enum(正本)と契約(複製)で照合」に改めた
- `rdra-feedback.md`: SR-001 / SR-002 を「distillery 1.15.1 で対応済み。本イベントで投入」として解消済みへ移し、「スキーマ更新までの暫定」注記(列挙値の正本は state_codes、USDM 対応の正本は Markdown 表)を削除。残存する RDRA 変更要望 / スキル変更要求は 0 件。「列挙値の正本は shared_rules.state_codes」の記述は docs/specs 内に残っていない
- `traceability-matrix.md` / `uc-dependencies.md` / `asyncapi.yaml` / `openapi.yaml` / `ux-ui/*`: 変更なし(RDRA 要素・依存・API は不変)
- `decisions/spec-decision-008.yaml` を追加(列挙値の正本の一本化と usdm[] の機械照合)
- `_inference.md` に本イベントの差分更新履歴を追記。`_inputs-digest.md` は arch 20260908_015000 / nfr 20260907_120000 から再生成(event_id ヘッダーのみ差分)。`README.md` は最終更新イベントを本イベントに更新(全 32 UC の spec.md を整えたため)

## D5: 既存バリデータ適合のための文言修正(挙動不変)

- `validateSpecProse.js` の `editorial-direction` ルール(「本文…複写しない」)に、前イベントから残っていた 2 箇所の仕様文が誤検知していた。UC「保存済みの確報結果をジョブスケジューラへ返す」tier-final-crosscheck.md「stdout / stderr の本文はログに複写しない」→「stdout / stderr の中身はログに含めない」、UC「ハング疑い・実行エラー・比較異常を通知する」tier-ops.md「本文は複写しない」→「メール本文はログに含めない」。意味は同じ(ログにペイロードを含めない)。32 UC すべて PASS
