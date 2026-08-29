# 変更サマリ

- event_id: 20260829_220117_spec_stories
- trigger_event: spec:20260829_210828_spec_generation, design:20260829_210210_design_system_feedback_disposition
- 種別: feedback 差分反映（reconciliation。direct owner なし）

```yaml
feedback_request:
  feedback_request_id: "20260822_085257_impl_feedback_6078c4ed"
  input_sha256: "8129956bff632d9c271356ef56e3256319c7613b030adfd5477fe9f60d748bf5"
  request_ids: ["CR-6078c4ed-011","CR-6078c4ed-012","CR-6078c4ed-013","CR-6078c4ed-014","CR-6078c4ed-015","CR-6078c4ed-016","CR-6078c4ed-017","CR-6078c4ed-018"]
  work_unit_ids: ["CR-6078c4ed-011#1","CR-6078c4ed-012#1","CR-6078c4ed-013#1","CR-6078c4ed-014#1","CR-6078c4ed-015#1","CR-6078c4ed-016#1","CR-6078c4ed-017#1","CR-6078c4ed-018#1"]
```

## 追加

- screens: 起動slot選択画面 に variant `JobMapFieldMissingDashboard`（slot別ジョブマップの必須フィールド欠落、終了コード2）
- screens: 起動slot選択画面 に variant `LaunchEventFailedDashboard`（起動イベント送出失敗のFAILED補償記録、終了コード1）
- screens: 起動slot選択画面 に variant `LaunchEventTimeoutDashboard`（起動イベント送出timeoutのUNKNOWN補償記録、終了コード124）
- screens: 実行結果応答管理画面 に variant `LaunchFailedDashboard`（status=FAILEDかつexit_code=NULLの補償記録、退避コード125。非0 exit_codeの通常FAILEDと区別）

## 変更

- components.domain: ExecutionSpecCard の description — マップ版(job_map_version)の記載を run共通からslot別実行設定へ移動（CR-6078c4ed-018でjob_map_versionがslot_execution_specsへ移動したことに追随）
- components.domain: RunnerResultPanel の description — 退避終了コード125の対象に「起動イベント送出失敗の補償記録であるFAILEDかつexit_code=NULL」を明記（CR-6078c4ed-012）
- src/components/domain/ExecutionSpecCard.tsx: 「map版」行を run共通セクションから slot別実行設定セクションへ移動
- screens: 起動slot選択画面 の JobMapUnresolvedDashboard のバナー文言を「slot_type=green のジョブマップ（ファイルパス）に JOB_ID が存在しません」へ具体化（ジョブマップがslot別独立ファイルであることを明示）

## 削除

- なし

## reconciliation（causal work unit の判定）

| work_unit_id | status | 理由 |
|---|---|---|
| CR-6078c4ed-011#1 | not_impacted | 監査event_hashの正規化形式はRDB内部の算出規則であり、CLI出力・Storybook表示に現れない |
| CR-6078c4ed-012#1 | changed | 起動イベント送出失敗/timeoutのFAILED/UNKNOWN補償記録を起動slot選択画面に、exit_code=NULLの125応答を実行結果応答管理画面に追加 |
| CR-6078c4ed-013#1 | not_impacted | E2E Scenarioの責務先変更（起動UC→UC横断統合シナリオ）であり、表示済みのSTARTING出力・終了コード0という文言自体に変更はない |
| CR-6078c4ed-014#1 | not_impacted | additional_args/fixed_argsの保存形式（JSON配列）はRDB保存規則であり、ExecutionSpecCard等の表示Propsに引数一覧は含まれない |
| CR-6078c4ed-015#1 | not_impacted | 物理型対応表・datetime精度・uuid形式はRDB/migration生成規則でありCLI表示文言に影響しない |
| CR-6078c4ed-016#1 | not_impacted | USDM SPEC-009-03の文言整理（要求仕様の記述改訂）であり、design/latestは20260829_210210の判定どおり既に整合済みで新規表示文言は生じない |
| CR-6078c4ed-017#1 | not_impacted | credential_refは既存表示（参照名のみ）のままであり、解決規則・環境変数名の追加はCLI表示要素に現れない |
| CR-6078c4ed-018#1 | changed | job_map_versionのslot_execution_specsへの移動をExecutionSpecCard表示位置へ反映し、per-slotジョブマップの必須フィールド欠落エラーバリエーションを追加 |
