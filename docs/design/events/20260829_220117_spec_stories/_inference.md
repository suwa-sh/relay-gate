# 推論メモ

## 入力

- feedback request: 20260822_085257_impl_feedback_6078c4ed
- stage packet: docs/pipeline/feedback-runs/20260822_085257_impl_feedback_6078c4ed/stage-packets/spec_stories.md
- causal_work_unit_ids: CR-6078c4ed-011#1〜018#1（direct_work_unit_ids は空。本stageは reconciliation のみを担う）
- 直前の spec 差分反映イベント: spec:20260829_210828_spec_generation
  （並行稼働実行フローの4 UC・実行監視業務・実行制御業務・クロスチェック業務の各tier/spec.mdを更新）

## 判定プロセス

1. 8件のCRそれぞれについて、work-unit descriptor の `reason` と、対応する spec イベントの `_changes.md` / tier-*.md 本文を突き合わせ、
   「CLIの標準出力・標準エラー・終了コード、またはStorybook Storyの表示要素・Props・バリアントに変化を生むか」を判定基準とした。
2. CR-012（launch-event-failure-compensation）: tier-facade.md（feature flag設定に基づきslotを選択して起動する）に
   「送出失敗はFAILED・timeoutはUNKNOWNへ補償記録」「標準エラーに `slot_type={blue|green} attempt_id={attempt_id} を {FAILED|UNKNOWN} として記録しました` を含める」との明記があり、
   起動slot選択画面のBanner/RunnerResultPanel表示に新規シナリオが必要と判定（changed）。
   さらに respond-foreground の tier-facade.md に「起動イベント送出失敗の補償記録であるFAILEDかつexit_code=NULL」が退避コード125の対象として明記され、
   既存のFailedDashboard（非0 exit_codeの業務エラー）と区別が必要なため実行結果応答管理画面も changed とした。
3. CR-018（per-slot-job-map-contract）: rdb-schema.yaml で job_map_version が execution_specs から slot_execution_specs（PK=run_id,slot_type）へ移動したことを確認。
   design-event.yaml の ExecutionSpecCard 記述・実装（ExecutionSpecCard.tsx）は「map版」を run共通セクションに配置しており、
   スキーマ変更後の実体（slot別）と表示（run共通）が不一致になるため changed とした。
   また tier-facade.md の新規BDD Scenario「ジョブマップの必須フィールド欠落でバリデーションエラーになる」で
   `ジョブマップの必須フィールドが欠落しています: slot_type=green path=... field=...` という新しい具体的エラー文言が定義されており、
   既存の JobMapUnresolvedDashboard（JOB_ID未解決、終了コード1）とは別種のエラー（フィールド欠落、終了コード2）であるため新規バリエーションが必要と判定した。
4. 残り6件（011/013/014/015/016/017）は、該当するspec変更箇所を確認したうえで、
   いずれもRDB保存形式・監査ハッシュ算出・USDM文言整理・env var名の追加など「バックエンドの内部規則」または「テスト構成上の責務移動」であり、
   ユーザーに見える標準出力・標準エラー・終了コード・Storybook表示要素のいずれにも新規の文言・Props差分を生まないことを確認し not_impacted とした。
   CR-016 は design_system stage が同一 feedback request 内で既に no-change disposition
   （design:20260829_210210_design_system_feedback_disposition）を出しており、その判断が spec_stories レベルでも変わらないことを確認した。

## 実装内容

- `src/components/domain/ExecutionSpecCard.tsx`: 「map版」Rowをrun共通セクションからslot別実行設定セクションの末尾へ移動。
  ヘッダコメントに移動理由（CR-6078c4ed-018）を追記。credential_ref（認証情報参照名）は今回のCR群の対象外（既存のrun共通表示のまま、変更なし）。
- `起動slot選択画面.stories.tsx`: import RunnerResultPanel を追加。JobMapUnresolvedDashboardの文言をslot別ファイルパス付きに具体化。
  JobMapFieldMissingDashboard / LaunchEventFailedDashboard / LaunchEventTimeoutDashboard の3variantを新規追加。
- `実行結果応答管理画面.stories.tsx`: LaunchFailedDashboard variantを新規追加（state="failed", exitCode=125, stderrに補償記録の説明を明記）。
  meta冒頭のコメントに新しい退避コード125の対象範囲を追記。

## 検証

- `npx tsc --noEmit -p .`: エラーなし
- `npx storybook build`: ビルド成功（storybook-static は events/ latest/ いずれにもコミットしないため実行後に削除）
