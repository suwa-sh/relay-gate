# RDRA フィードバック(Spec 生成時の発見事項)

> 生成: Step4d(トレーサビリティマトリクス + 網羅率是正)。対象 RDRA = `docs/rdra/latest/`(event `20260905_083000_feedback_todo_resolution` 反映後)。
> 網羅率は `traceability-matrix.md` を参照(合計 100.0%。未カバー 0 件)。
> 前イベント(`20260830_202851_spec_generation`)の変更要望 #1〜#8 / #10〜#12 は feedback request `20260905_todo_resolution`(CR-c770d8f0-001〜011)で RDRA / USDM に取り込まれ、本イベントで Spec 側の仮採用注記を外した(下記「解消済み」)。

## 変更要望一覧(残存)

| # | 種別 | 対象RDRA要素 | 変更内容 | 理由 |
|---|------|-------------|---------|------|
| 9 | 確認 | 方針資料 C2「Hang Detection」図の `HangDetector -.-> FinalQueue` | 図の破線を削除するか、本文(監視対象は background slot と速報比較依頼)を改める | 方針資料の C2 図は hang-detector が確報依頼キューを参照するように読めるが、本文と Spec(`cli-command-contract.yaml` hang-detector.sh / `asyncapi.yaml`)では確報依頼は走査対象外。Spec は本文を正とし、確報依頼のハング監視は final-crosscheck-runner.sh の polling 上限(FINAL_POLL_LIMIT_SEC、既定 8 時間)で代替する仮採用のまま(前イベント Step3 Round 2 G3 #13。今回の CR には含まれていない) |

## 解消済み(feedback 20260905_todo_resolution で RDRA / USDM に反映済み)

| 旧 # | 対象 | 反映先 | Spec 側の対応(本イベント) |
|---|---|---|---|
| 1 | 情報「ハング検知上限設定」の属性「調整日時」「調整根拠」 | CR-007: 属性を削除し、情報「適用構成文書」の属性「運用者の調整記録」へ移動 | UC「hang_detect_limit_minutes をジョブごとに調整する」のトレーサビリティ行を付け替え |
| 2 | 情報「ジョブスケジューラ応答」の属性「応答日時」 | CR-007: 属性を削除 | UC「foreground slot の結果をジョブスケジューラへ中継する」の該当行を削除 |
| 3 | バリエーション「監視状態」の値集合 | CR-008: 状態モデルと同じ 6 値に統一(「通知後正常終了」は遷移の別名) | `monitor_status` 6 値の注記を「RDRA 準拠」に変更 |
| 4 | 状態「並行稼働実行」STARTED → ABORTED | CR-009: 遷移を追加(遷移 UC「実行を ABORTED へ遷移させる」) | 仮採用注記を除去 |
| 5 | 状態「並行稼働実行」RUNNING → COMPLETED(リラン由来 run) | CR-009: 遷移 UC「比較ツールでジョブ単位比較を実行して結果を登録する」「実装スクリプトを実行して Runner Result を出力する」を追加 | 判定規則と条件付き UPDATE を契約・UC に記載 |
| 6 | 情報「ハング検知定期ジョブ設定」(hang-detector.env) | CR-010: 情報を新設(所有者 = 基盤適用設計者。設定所有区分に追加) | `config_files[hang-detector.env]` の owner を確定、`ALERT_SUBJECT_PREFIX` を追加 |
| 7 | 状態「監視状態」ハング疑い通知済み → 比較異常通知済み / 実行エラー通知済み / 正常終了 | CR-008: 遷移を追加 | 仮採用注記を除去 |
| 8 | 完了通知失敗の検知の要否 | CR-005: 条件「完了通知失敗の扱い」を新設(自動検知しない。運用者が同一引数で再実行) | 「(spec 追加 / スコープ外)」注記を条件名参照へ置換 |
| 10 | USDM SPEC-001-01 の feature flag キー | CR-001: 契約側を元資料の 9 キーへ戻す(USDM 本文が正) | `config_files[feature-flag.env]` を 9 キーに変更、`CONFIG_VERSION` 削除 |
| 11 | 状態「監視状態」の中止済み終端 / バリエーション「ハング検知判定結果」の値集合 | CR-004 / CR-008: 条件「ハング検知判定」に aborted.txt の終端を追記、判定結果を 6 値に統一 | `hang_judgement` 6 値の注記を「RDRA 準拠」に変更 |
| 12 | 条件「comparison_results の登録条件」 | CR-011: 条件「比較結果の登録条件」を新設 | 条件名を改名し「(spec 追加)」注記を除去 |

## 対応方針

- 残存する #9 は方針資料(図)側の確認事項であり、RDRA モデルの網羅率には影響しない(`traceability-matrix.md` の分母に該当要素は無い)
- Spec 側は #9 を仮採用(確報依頼は hang-detector の走査対象外)として実装の正本にする。方針資料の図を改めるか本文を改めるかは利用者判断

## 後工程・スキルへの変更要求(RDRA 対象外)

> Step6.5 反証レビュー(前イベント round-1)で挙がったスキーマ拡張要求。RDRA の変更ではなく distillery スキル(dist-spec)のスキーマと後工程(distillery-impl)への要望であるため、本イベントでも修正せずここに記録する。対応先は `dist-spec` のスキーマ更新(次版)。

| # | 由来 | 対象 | 変更要求 | 理由 |
|---|------|------|---------|------|
| SR-001 | 前イベント round-1 F(minor) | dist-spec スキーマ `schema-spec-event.json`(`use_cases[]`)/ `schema-api-summary.json` | `use_cases[]` に `usdm: [{req_id, spec_id, scenarios: [..]}]`(または `_api-summary.yaml` に `usdm_refs`)を追加し、生成時に spec.md「関連 USDM」表と同内容を YAML にも出す。`validateSpecEvent.js` で spec_id の USDM 実在チェックを行う | UC → USDM SPEC ID / acceptance_criteria の対応が各 spec.md の Markdown 表にしか無く、後工程(distillery-impl の ATDD 生成・`usdm-acceptance-matrix.md` の再生成)が Markdown 表を再パースしている。機械可読フィールドが無いため照合の自動検証ができない(本イベントでも `usdm-acceptance-matrix.md` は手集計) |
| SR-002 | 前イベント round-1 F(minor) | dist-spec スキーマ `schema-rdb-schema.json`(`columns[]`) | `columns[]` に任意の `enum: [..]` を追加し、`rdb-schema.yaml` の列挙列(status / completion_status / monitor_status / slot / mode / role / target_type / comparison_type)に機械可読な enum を持たせる。`cli-command-contract.yaml` `shared_rules.state_codes` はそれを参照(または生成)する形にして二重管理を解消する | 列挙値が description の日本語文中にしか無く、bash 定数・SQL DDL(CHECK 制約)の codegen が description を正規表現で拾うか `shared_rules.state_codes` と手で突き合わせるしかない。本イベントでも `shared_rules.state_codes` を正として description の値集合を手動で揃えている |

- スキーマ更新までの暫定: 列挙値の正本は `cli-command-contract.yaml` `shared_rules.state_codes`、USDM 対応の正本は各 spec.md「関連 USDM」表 + `_cross-cutting/usdm-acceptance-matrix.md` とする
