# 変更サマリ

- event_id: 20260829_210828_spec_generation
- trigger_event: rdra:20260829_205305_spec_009_03_execution_spec_split_wording, arch:20260829_205903_feedback_disposition, design:20260829_210210_design_system_feedback_disposition
- 種別: feedback 差分反映（direct owner stage）

```yaml
feedback_request:
  feedback_request_id: "20260822_085257_impl_feedback_6078c4ed"
  input_sha256: "8129956bff632d9c271356ef56e3256319c7613b030adfd5477fe9f60d748bf5"
  request_ids: ["CR-6078c4ed-011","CR-6078c4ed-012","CR-6078c4ed-013","CR-6078c4ed-014","CR-6078c4ed-015","CR-6078c4ed-016","CR-6078c4ed-017","CR-6078c4ed-018"]
  work_unit_ids: ["CR-6078c4ed-011#1","CR-6078c4ed-012#1","CR-6078c4ed-013#1","CR-6078c4ed-014#1","CR-6078c4ed-015#1","CR-6078c4ed-016#1","CR-6078c4ed-017#1","CR-6078c4ed-018#1"]
```

- direct_work_unit_ids: CR-6078c4ed-011#1, CR-6078c4ed-012#1, CR-6078c4ed-013#1, CR-6078c4ed-014#1, CR-6078c4ed-015#1, CR-6078c4ed-017#1, CR-6078c4ed-018#1
- causal_work_unit_ids: 上記 + CR-6078c4ed-016#1（USDM SPEC-009-03 文言整合の reconciliation）
- packet_path: docs/pipeline/feedback-runs/20260822_085257_impl_feedback_6078c4ed/stage-packets/spec.md

## 追加 UC

- なし

## 変更 UC

- 並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する（CR-012/013/014/017/018: slot 別ジョブマップ、job_map_version の slot 別保存、hang_detect_limit_minutes の出所、引数の JSON 配列、credential_ref 解決、起動イベント送出失敗/timeout の FAILED/UNKNOWN 補償記録、CLI 応答対象の起動受付限定、E2E Scenario 改訂・追加）
- 並行稼働実行業務/並行稼働実行フロー/background roleを起動する（CR-014/017: credential_resolution・argument_serialization への追随、job_map_version の slot 側移動）
- 並行稼働実行業務/並行稼働実行フロー/foreground roleの標準出力・標準エラー・終了コードを応答する（CR-012/013: wait_contract（待機上限 hang_detect_limit_minutes）、FAILED かつ exit_code=NULL の 125 応答）
- 並行稼働実行業務/並行稼働実行フロー/並行稼働実行結果を確認する（CR-018: Given の job_map_version 位置）
- 実行監視業務/ハング監視フロー/background実行の未完了・非0終了・速報比較異常を定期検知する（CR-012/016/018: hang_detect_limit_minutes の run 共通文言、STARTING 走査の注記）
- 実行制御業務/background側リランフロー/execution-spec.jsonの実行設定を保ったまま再実行する（CR-014/017/018: job_map_version の slot 側複製、引数復元、credential 解決）
- 実行制御業務/background側リランフロー/再実行対象のbackground実行・速報比較依頼を選択する（CR-018: Given）
- 実行制御業務/blue中止フロー/blue background実行の中止を依頼する、対話確認のうえblue background実行をABORTEDへ遷移させる（CR-017/018: 環境変数表、Given）
- 実行制御業務/green中止フロー/green background実行の中止を依頼する、対話確認のうえgreen background実行をABORTEDへ遷移させる（CR-017/018: 環境変数表、Given）
- 実行制御業務/確報比較中止フロー/RUNNING中の確報比較依頼の中止を依頼する（CR-018: Given）
- クロスチェック業務/確報クロスチェックフロー/全テーブル・全ファイルを対象に確報クロスチェックを実行する、確報クロスチェック結果を確認する、確報クロスチェック結果をstdout/stderr/exitcodeで応答する（CR-018: Given）

## 削除 UC

- なし

## 影響 BUC

- 並行稼働実行業務/並行稼働実行フロー（UC01 の STARTING→FAILED/UNKNOWN 補償記録、UC03 の待機責務を buc-spec.md へ反映）

## cross-cutting 再生成

- api/cli-command-contract.yaml: `job_map_contract`（slot 別ジョブマップ）・`credential_resolution`（認証情報ディレクトリ方式）を追加。select-slot / worker start-background-execution / abort 4 コマンド / rerun run / respond-foreground の env・exit_codes・wait_contract を更新
- api/audit-event-contract.yaml: `hash_chain.canonical_form`（event_hash 正規化形式）を追加。slot_launch_failed / slot_launch_timeout の emitted_by に起動 UC を追加。補償記録の transaction_rules を追加
- datastore/rdb-schema.yaml: `physical_type_mapping` / `datetime_rules` / `uuid_rules` / `argument_serialization` を追加。job_map_version を execution_specs から slot_execution_specs へ移動。runner_results の used_by に起動 UC の UPDATE を追加
- datastore/datastore-schema.md: 再生成
- uc-dependencies.md: #2/#3/#13/#14/#28 更新、#31/#32 追加、「UC 横断統合シナリオ」節を新設（CR-013 で起動 UC から移した統合 Then）
- usdm-acceptance-matrix.md: SPEC-009-03 を 2 criteria へ分割（総数 57）、SPEC-002-02 / 003-04 #3 / 009-01 / 009-02 / 009-05 #2 の対応 Scenario 更新
- traceability-matrix.md: 「マップ版」の対応先を slot_execution_specs.job_map_version へ、hang_detect_limit_minutes の説明を run 共通 1 値へ（網羅率 100% 維持）
- rdra-feedback.md: #2（execution-spec.json 属性「マップ版」の slot別実行設定への移動。未解消）を追加
- decisions/spec-decision-008〜010 を追加

## 確認推奨項目

- docs/todo.md DIST-025: RDRA 情報.tsv の「マップ版」属性配置（requirements 側で反映）
- docs/todo.md DIST-026: foreground 試行の実行状態確定（STARTING→RUNNING→SUCCEEDED/FAILED）の担い手が未定義（既存ギャップ。待機契約により顕在化）
