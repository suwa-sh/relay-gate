# RDRA フィードバック(Spec 生成時の発見事項)

> 生成: Step4d(トレーサビリティマトリクス + 網羅率是正)。本イベント = `20260908_024000_feedback_slot_status_wording`。対象 RDRA = `docs/rdra/latest/`(event `20260908_011000_feedback_slot_status_wording` 反映後)。
> 網羅率は `traceability-matrix.md` を参照。
> 前々々イベント(`20260830_202851_spec_generation`)の変更要望 #1〜#8 / #10〜#12 は feedback request `20260905_todo_resolution`(CR-c770d8f0-001〜011)で RDRA / USDM に取り込まれ、`20260905_100000_feedback_todo_resolution` で Spec 側の仮採用注記を外した。
> 前イベント(`20260907_024000_feedback_todo_followup`)では todo DIST-022 / DIST-023 / DIST-024 が feedback request `20260907_todo_followup`(CR-c770d8f0-013〜015)で RDRA / USDM / arch に取り込まれ、Spec 側の仮採用注記を外した。
> 前イベント(`20260907_131000_feedback_abort_consistency`)では前々イベントの Step6.5 反証レビュー由来の #13 / #14 / #15 が feedback request `20260907_abort_consistency`(CR-c770d8f0-016〜018。利用者決定 DIST-025 A / DIST-026 A / DIST-027 A)で RDRA(event `20260907_114000`)/ USDM(SPEC-005-02 / 010-01 / 010-02)/ arch(event `20260907_122000`)に取り込まれ、Spec 側の注記(「仮採用: rdra-feedback #13」「rdra-feedback #14」「rdra-feedback #15」)を外して確定規則として記載した。#9(方針資料の図)は利用者が図を修正済みのため解消済みへ移した(下記「解消済み」)。条件「中止済み run の比較依頼作成除外」の対象 slot 限定の判定キーで抜けが無いことを確認した(abort-blue / abort-green が parallel_runs を ABORTED にするため)。
> 本イベントでは前イベントの確認推奨項目 #16(条件「slot 実行の状態導出規則」の管理 DB 側文言)が feedback request `20260908_slot_status_wording`(CR-c770d8f0-019。利用者決定 DIST-029 A)で RDRA(event `20260908_011000`)/ USDM(SPEC-005-02 AC9)に取り込まれ、Spec 側の仮採用注記を除去して条件名参照に統一した(下記「解消済み」)。RDRA への残存変更要望は無い。

## 変更要望一覧(残存)

残存する RDRA への変更要望は無い(#16 は本イベントで解消済み)。

## 解消済み(feedback 20260905_todo_resolution / 20260907_todo_followup / 20260907_abort_consistency / 20260908_slot_status_wording で RDRA / USDM / arch に反映済み、または方針資料側で対応済み)

| 旧 # | 対象 | 反映先 | Spec 側の対応 |
|---|---|---|---|
| 16 | 条件「slot 実行の状態導出規則」の管理 DB 側文言(「速報クロスチェック有効時は管理 DB にも同じ状態を保持する」) | feedback 20260908_slot_status_wording CR-019(DIST-029 A): 条件.tsv の管理 DB 側文言を「速報クロスチェック有効時は、管理 DB の slot_executions.status に aborted.txt または exitcode.txt の公開時点の状態を条件付き更新(RUNNING のときだけ)で一度だけ書く。abort-blue / abort-green で ABORTED にした後に実装が走り切って exitcode.txt を公開した場合、管理 DB は ABORTED のまま残し、ファイル正本の導出値(exitcode.txt 優先)へ再同期しない。管理 DB の値は条件「中止済み run の比較依頼作成除外」の判定材料として使う」に改訂。RDRA event 20260908_011000、USDM SPEC-005-02(AC9)、arch E-014 の status 属性説明 / storage_mapping E-014(rdb) | 本イベント: `rdb-schema.yaml` slot_executions.status / 契約 `shared_rules.exitcode_to_status.slot_execution` / `ui-design.md` の管理 DB 側の記述を条件「slot 実行の状態導出規則」の管理 DB 側の規則として参照する形に統一し、仮採用注記と #16 参照を除去。UC-09 に AC9 の BDD シナリオを追加、UC-05 / UC-23 / buc-spec(実装切替ジョブ実行フロー)の文言を追従 |
| 13 | 条件「中止済み run の比較依頼作成除外」の判定キー(parallel_run の ABORTED のみ) | feedback 20260907_abort_consistency CR-016(DIST-025 A): 判定キーを「並行稼働実行が ABORTED、または完了通知の対象 slot の slot 実行が ABORTED(aborted.txt 公開済み)」に拡張。判定材料 = parallel_run.status と slot_executions.status。RDRA event 20260907_114000(条件「中止済み run の比較依頼作成除外」「両系成功判定」、情報「速報実行」、BUC「速報クロスチェックフロー」)、USDM SPEC-005-02(AC5 / AC6)、arch event 20260907_122000(SP-009 / LP-010 / LP-023 / CLP-004 / BC-002 / AG-002 / E-016) | 本イベント: `rapid-crosscheck-runner.sh` の `request_creation_matrix`(3 行 × 3 列)/ idempotency(対象 slot の SELECT)/ execution_log(reason=parallel_run_aborted / slot_execution_aborted)、`rdb-schema.yaml`(completion_status / ロック順)、`asyncapi.yaml`、UC-08 / UC-09 の spec / tier / BDD から「仮採用: rdra-feedback #13」「RDRA 条件は parallel_run の ABORTED のみを判定キーとしている」の注記を外し確定規則として記載 |
| 14 | 状態「クロスチェック依頼」REQUESTED → ABORTED の説明文(両 slot 完了直後の抜けを防ぐ) | feedback 20260907_abort_consistency CR-018(DIST-027 A): 説明を「両系の完了通知で依頼が作成された後に abort-blue / abort-green で slot を中止した場合の競合窓を塞ぐ保険。dispatcher 側の中止済み run 判定と併用」に変更。RDRA event 20260907_114000(状態「クロスチェック依頼」REQUESTED → ABORTED、条件「slot 中止可否判定」)、USDM SPEC-010-01(本文 / AC8)、arch event 20260907_122000(SP-022 / LP-021 / BC-004 / CM-005 / AG-002 / E-017 / E-024) | 本イベント: `abort-blue.sh` / `abort-green.sh` の notes、`shared_rules.state_codes.request_status_transitions`、`rdb-schema.yaml` 冒頭注記、`ui-design.md`、`uc-dependencies.md`、UC-23 / buc-spec(実行中止フロー)/ UC-08 を「競合窓の保険」の表現に統一し「rdra-feedback #14」の参照を外した |
| 15 | 条件「依頼中止可否判定」/ 状態「クロスチェック依頼」RUNNING → ABORTED / USDM SPEC-010-02(abort-rapid-crosscheck は RUNNING 限定) | feedback 20260907_abort_consistency CR-017(DIST-026 A): 速報比較依頼は REQUESTED / CLAIMED / RUNNING のいずれかで中止可能(停止確認 yes + status IN 条件付き UPDATE)、確報比較依頼は RUNNING のみ。状態「クロスチェック依頼」CLAIMED → ABORTED を新設、CLAIMED → RUNNING は条件付き UPDATE(0 件なら比較を開始しない)。RDRA event 20260907_114000、USDM SPEC-010-02(AC2〜AC5)、arch event 20260907_122000(SP-011 / SP-022 / LP-019 / LP-021 / LP-024 / BC-004 / CM-005 / AG-002 / E-017 / E-024) | 本イベント: `abort-rapid-crosscheck.sh`(status IN 条件付き UPDATE、判定表、終端状態のみ 3)/ `abort-final-crosscheck.sh`(RUNNING のみ)/ `rapid-crosscheck-worker.sh`(CLAIMED → RUNNING の条件付き UPDATE と 0 件時の振る舞い)/ `shared_rules.state_codes.request_status_transitions`(CLAIMED → ABORTED 追加)/ `rdb-schema.yaml`、UC-10 / UC-11 / UC-22 / UC-23 / buc-spec を更新し「rdra-feedback #15」「REQUESTED / CLAIMED は worker に処理させてから判断する」「CLAIMED からの遷移は無い」を削除 |
| 9 | 方針資料 C2「Hang Detection」図の `HangDetector -.-> FinalQueue` | 方針資料の図修正(利用者。hang-detector が確報依頼キューを参照する破線を除去) | 変更なし。確報依頼は hang-detector の走査対象外のまま(`cli-command-contract.yaml` hang-detector.sh / `asyncapi.yaml`)。確報依頼のハング監視は final-crosscheck-runner.sh の polling 上限(FINAL_POLL_LIMIT_SEC)で代替 |
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

- #13〜#15 は feedback 20260907_abort_consistency、#16 は feedback 20260908_slot_status_wording で解消済み。#9 は方針資料の図修正(利用者)で解消済み
- 残存は SR-001 / SR-002(スキル側の変更要求)のみ

## 後工程・スキルへの変更要求(RDRA 対象外)

> Step6.5 反証レビュー(前イベント round-1)で挙がったスキーマ拡張要求。RDRA の変更ではなく distillery スキル(dist-spec)のスキーマと後工程(distillery-impl)への要望であるため、本イベントでも修正せずここに記録する。対応先は `dist-spec` のスキーマ更新(次版)。

| # | 由来 | 対象 | 変更要求 | 理由 |
|---|------|------|---------|------|
| SR-001 | 前イベント round-1 F(minor) | dist-spec スキーマ `schema-spec-event.json`(`use_cases[]`)/ `schema-api-summary.json` | `use_cases[]` に `usdm: [{req_id, spec_id, scenarios: [..]}]`(または `_api-summary.yaml` に `usdm_refs`)を追加し、生成時に spec.md「関連 USDM」表と同内容を YAML にも出す。`validateSpecEvent.js` で spec_id の USDM 実在チェックを行う | UC → USDM SPEC ID / acceptance_criteria の対応が各 spec.md の Markdown 表にしか無く、後工程(distillery-impl の ATDD 生成・`usdm-acceptance-matrix.md` の再生成)が Markdown 表を再パースしている。機械可読フィールドが無いため照合の自動検証ができない(本イベントでも `usdm-acceptance-matrix.md` は手集計) |
| SR-002 | 前イベント round-1 F(minor) | dist-spec スキーマ `schema-rdb-schema.json`(`columns[]`) | `columns[]` に任意の `enum: [..]` を追加し、`rdb-schema.yaml` の列挙列(status / completion_status / monitor_status / slot / mode / role / target_type / comparison_type)に機械可読な enum を持たせる。`cli-command-contract.yaml` `shared_rules.state_codes` はそれを参照(または生成)する形にして二重管理を解消する | 列挙値が description の日本語文中にしか無く、bash 定数・SQL DDL(CHECK 制約)の codegen が description を正規表現で拾うか `shared_rules.state_codes` と手で突き合わせるしかない。本イベントでも `shared_rules.state_codes` を正として description の値集合を手動で揃えている |

- スキーマ更新までの暫定: 列挙値の正本は `cli-command-contract.yaml` `shared_rules.state_codes`、USDM 対応の正本は各 spec.md「関連 USDM」表 + `_cross-cutting/usdm-acceptance-matrix.md` とする
