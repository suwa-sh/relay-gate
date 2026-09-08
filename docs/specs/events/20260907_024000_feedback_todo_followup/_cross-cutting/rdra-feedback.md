# RDRA フィードバック(Spec 生成時の発見事項)

> 生成: Step4d(トレーサビリティマトリクス + 網羅率是正)。本イベント = `20260907_024000_feedback_todo_followup`。対象 RDRA = `docs/rdra/latest/`(event `20260907_011000_feedback_todo_followup` 反映後)。
> 網羅率は `traceability-matrix.md` を参照。
> 前々イベント(`20260830_202851_spec_generation`)の変更要望 #1〜#8 / #10〜#12 は feedback request `20260905_todo_resolution`(CR-c770d8f0-001〜011)で RDRA / USDM に取り込まれ、前イベント(`20260905_100000_feedback_todo_resolution`)で Spec 側の仮採用注記を外した。
> 本イベントでは todo DIST-022 / DIST-023 / DIST-024 が feedback request `20260907_todo_followup`(CR-c770d8f0-013〜015)で RDRA / USDM / arch に取り込まれ、Spec 側の仮採用注記(`config_files[rapid-crosscheck.env]` / `lease_and_poll` の「_inference.md #6」、実行ログ日時の「UTC」注記)を外した(下記「解消済み」)。

## 変更要望一覧(残存)

| # | 種別 | 対象RDRA要素 | 変更内容 | 理由 |
|---|------|-------------|---------|------|
| 9 | 確認 | 方針資料 C2「Hang Detection」図の `HangDetector -.-> FinalQueue` | 図の破線を削除するか、本文(監視対象は background slot と速報比較依頼)を改める | 方針資料の C2 図は hang-detector が確報依頼キューを参照するように読めるが、本文と Spec(`cli-command-contract.yaml` hang-detector.sh / `asyncapi.yaml`)では確報依頼は走査対象外。Spec は本文を正とし、確報依頼のハング監視は final-crosscheck-runner.sh の polling 上限(FINAL_POLL_LIMIT_SEC、既定 8 時間)で代替する仮採用のまま(前イベント Step3 Round 2 G3 #13。今回の CR には含まれていない) |
| 13 | 変更 | 条件「中止済み run の比較依頼作成除外」(条件.tsv) | 判定キーを「並行稼働実行(parallel_run)が ABORTED」から「parallel_run が ABORTED **または** 同 run のいずれかの slot 実行が ABORTED(aborted.txt 公開済み)」に拡張する | 典型的な中止経路(foreground slot 完了で parallel_run が COMPLETED になった後に background slot を abort-blue / abort-green で中止)では parallel_run は COMPLETED のまま(中止の条件付き UPDATE は COMPLETED を更新しない)で、現行の判定キーでは除外が一度も効かず依頼が作られる。Spec 側は `rapid-crosscheck-runner.sh` の `request_creation_matrix` / notes と UC「両系成功時に速報比較依頼を作成する」で拡張後の判定キーを仮採用(注記「仮採用: rdra-feedback #13」)。判断主体は dispatcher のままで条件「完了通知の系統独立」と矛盾しない(Step6.5 反証レビュー R-001) |
| 14 | 変更 | 状態「クロスチェック依頼」REQUESTED → ABORTED(状態.tsv 行 7)の説明文 | 説明文「両 slot 完了直後に中止した場合に依頼だけが残って比較が走る抜けを防ぐ」を「dispatcher の依頼作成と abort-blue / abort-green の成果物再確認が同時刻に起きた競合窓の保険」に改める | REQUESTED の依頼は両 slot の exitcode.txt 公開後にしか存在せず、その時点で abort-blue / abort-green は「exitcode.txt あり = 終端済み」で 3 を返すため、「両 slot 完了直後」には到達しない。両 slot 完了直後の依頼を止める本来の経路は #13(dispatcher の判定)。Spec 側は `abort-blue.sh` notes / UC「実行を ABORTED へ遷移させる」/ buc-spec(実行中止フロー)に競合窓の保険である旨を注記(Step6.5 反証レビュー R-002) |
| 15 | 変更 | 条件「依頼中止可否判定」/ 状態.tsv 行 16(クロスチェック依頼 RUNNING → ABORTED)/ USDM SPEC-010-02 | abort-rapid-crosscheck の対象に REQUESTED / CLAIMED を加える(RUNNING 限定をやめる) | abort-blue / abort-green は CLAIMED の依頼を変更せず、abort-rapid-crosscheck は RUNNING 限定のため、中止済み run の CLAIMED 依頼は worker の lease 失効で REQUESTED に戻り別 worker に再 claim されて比較が走る。戻ってきた REQUESTED を中止する経路が無い。Spec 側は claim の振る舞いを変えず(RDRA に無い判断を発明しない)、`abort-blue.sh` notes / UC「実行を ABORTED へ遷移させる」に「CLAIMED のまま中止した依頼は lease 失効で再 claim されうる」と注記(Step6.5 反証レビュー R-004。確認推奨) |

## 解消済み(feedback 20260905_todo_resolution / 20260907_todo_followup で RDRA / USDM / arch に反映済み)

| 旧 # | 対象 | 反映先 | Spec 側の対応 |
|---|---|---|---|
| DIST-023 | 速報クロスチェック設定(rapid-crosscheck.env)が RDRA 情報.tsv に無い(`_inference.md #6` 仮採用) | feedback 20260907_todo_followup CR-013: 情報「速報クロスチェック設定」(属性: 管理 DB 接続参照名 / lease 期間(秒)/ worker の poll 間隔(秒)。所有者: 基盤適用設計者)を新設。バリエーション「設定所有区分」に追加。USDM SPEC-005-06 新設。arch E-027 | 本イベント: `config_files[rapid-crosscheck.env]` の owner / defined_in_uc(4 UC)/ keys の RDRA 属性名を確定し「仮採用: _inference.md #6」「final-crosscheck.env と対称」を除去。`shared_rules.lease_and_poll.rapid` に出所(速報クロスチェック設定)を明記(既定値 600 / 30 秒は仮採用のまま)。4 UC の `_model-summary.yaml` に `rdra_info` を付与 |
| DIST-024 | 中止済み run の速報比較依頼(ABORTED run で両系成功したときの依頼作成可否、未着手依頼の中止) | feedback 20260907_todo_followup CR-014: 条件「中止済み run の比較依頼作成除外」新設、条件「両系成功判定」「完了通知の系統独立」「slot 中止可否判定」追記、状態「クロスチェック依頼」REQUESTED → ABORTED(abort-blue / abort-green。速報のみ)追加。USDM SPEC-005-02 に AC 3 件 / SPEC-010-01 に AC 2 件 / SPEC-005-01 に AC 1 件。arch LP-010 / LP-021 / LP-023 / SP-009 / SP-022 | 本イベント: 契約 `rapid-crosscheck-runner.sh`(判定表・WARN・stdout `request_status=-`)、`abort-blue.sh` / `abort-green.sh`(rapid_crosscheck_requests の条件付き UPDATE)、`shared_rules.state_codes.request_status_transitions`、`rdb-schema.yaml`(status / completion_status の遷移注記)、UC-08 / UC-09 / UC-23 の BDD |
| DIST-022 | 実行ログ・出力・管理 DB の日時のタイムゾーン(UTC 統一の仮採用) | feedback 20260907_todo_followup CR-015(利用者決定 A): ホストのローカルタイムゾーン(ISO 8601 秒精度、指示子なし。run_id の時刻部と同じ時刻軸)。arch CLP-002 / CTP-003 / CLP-004 / E-025 / E-015 | 本イベント: `conventions.datetime` / `execution_log.datetime` / `shared_rules.run_id.timezone` / `time_precision`、`ui-design.md`「出力フォーマット」/ 通知メール規約、`data-visualization.md` の日時列型と `--since`、`rdb-schema.yaml` `_review_notes`、`asyncapi.yaml` / `ux-design.md` / `uc-dependencies.md` の日時説明を差し替え。started-at.txt / aborted.txt の中身は UTC Z 付きのまま(Runner Result Contract) |
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
- #13 / #14 / #15 は本イベントの Step6.5 反証レビュー(`_review/round-1.yaml` R-001 / R-002 / R-004)由来。Spec 側は #13 を仮採用(判定キーの拡張。注記「仮採用: rdra-feedback #13」)、#14 / #15 を注記(競合窓の保険 / CLAIMED 依頼の再 claim)で実装可能な形にしてあり、RDRA 反映後に注記を外す。#15 は確認推奨(RDRA を変えない判断なら中止済み run の CLAIMED 依頼が再 claim されうる抜けが残る)

## 後工程・スキルへの変更要求(RDRA 対象外)

> Step6.5 反証レビュー(前イベント round-1)で挙がったスキーマ拡張要求。RDRA の変更ではなく distillery スキル(dist-spec)のスキーマと後工程(distillery-impl)への要望であるため、本イベントでも修正せずここに記録する。対応先は `dist-spec` のスキーマ更新(次版)。

| # | 由来 | 対象 | 変更要求 | 理由 |
|---|------|------|---------|------|
| SR-001 | 前イベント round-1 F(minor) | dist-spec スキーマ `schema-spec-event.json`(`use_cases[]`)/ `schema-api-summary.json` | `use_cases[]` に `usdm: [{req_id, spec_id, scenarios: [..]}]`(または `_api-summary.yaml` に `usdm_refs`)を追加し、生成時に spec.md「関連 USDM」表と同内容を YAML にも出す。`validateSpecEvent.js` で spec_id の USDM 実在チェックを行う | UC → USDM SPEC ID / acceptance_criteria の対応が各 spec.md の Markdown 表にしか無く、後工程(distillery-impl の ATDD 生成・`usdm-acceptance-matrix.md` の再生成)が Markdown 表を再パースしている。機械可読フィールドが無いため照合の自動検証ができない(本イベントでも `usdm-acceptance-matrix.md` は手集計) |
| SR-002 | 前イベント round-1 F(minor) | dist-spec スキーマ `schema-rdb-schema.json`(`columns[]`) | `columns[]` に任意の `enum: [..]` を追加し、`rdb-schema.yaml` の列挙列(status / completion_status / monitor_status / slot / mode / role / target_type / comparison_type)に機械可読な enum を持たせる。`cli-command-contract.yaml` `shared_rules.state_codes` はそれを参照(または生成)する形にして二重管理を解消する | 列挙値が description の日本語文中にしか無く、bash 定数・SQL DDL(CHECK 制約)の codegen が description を正規表現で拾うか `shared_rules.state_codes` と手で突き合わせるしかない。本イベントでも `shared_rules.state_codes` を正として description の値集合を手動で揃えている |

- スキーマ更新までの暫定: 列挙値の正本は `cli-command-contract.yaml` `shared_rules.state_codes`、USDM 対応の正本は各 spec.md「関連 USDM」表 + `_cross-cutting/usdm-acceptance-matrix.md` とする
