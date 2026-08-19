# 次の作業: 仕様反映完了 → 実装フェーズ再開

## 現在の状態

- state: `spec_updated`(仕様側の還流は完了。実装・テストへの反映が未着手)
- 完了した還流(いずれも全 stage 成功・最終検証 PASS):
  - `20260818_113601_impl_feedback_6078c4ed`(2026-08-18): blocker 4件 + 修正候補7項目を反映。
    terminal event `20260818_162905_feedback_run_completed`
  - `20260818_164000_rdra_followup_6078c4ed`(2026-08-19): 後続3件を反映。
    terminal event `20260819_130140_feedback_run_completed`
    - CR-008: slot 別実行設定・attempt identity・実行状態6値の RDRA 追随(DIST-023/024 closed)
    - CR-009: 比較定義エンティティ追加(`comparison_definitions`。世代管理: `(job_id, valid_from)` 複合 PK)。
      SPEC-012-03 解消で USDM 逆引き 56/56 = 100%
    - CR-010: `respond-foreground` の終了コードを写像(0/1/2)から **exitcode.txt 全値透過**へ変更。
      relay-gate 自身のエラーは退避コード **125**(未確定・取得不能・中止済み)/ **124**(バリデーション)。
      エラー時 stderr は foreground の stderr.log 内容 + relay-gate エラー内容を併記
- 仕様の最新イベント: spec `20260819_114307_spec_generation` / arch `20260819_110531` /
  infra `20260819_111931` / design `20260819_125615` / rdra・usdm `20260819_104301`
- テスト規約変更(2026-08-19): tier/UC の feature・steps ファイル名は uc_id ハッシュでなく
  uc-map の `branch_slug`(`{uc_slug}.feature`)を使う。正本 `docs/dev-rules/test-strategy.md`。
  既存 5 ファイルはリネーム済み
- PR: 未作成。実装・テスト反映と最終レビューが終わるまで作成しない

## 次に実行するコマンド

```text
/distillery-impl:dist-impl-run 6078c4ed
```

入力 hash が変わった範囲だけが projection 照合で再実行される(tier-scoped staleness)。
今回の仕様差分で少なくとも次が実装対象に入る:

1. S1 input-preflight → S2 scoped test-scaffold: 更新された Gherkin の転写
   (rerun identity の新 run_id 化 / exitcode 透過・退避コード 125・124 / attempt identity /
   UNKNOWN→ABORTED / comparison_definitions 適用)
2. contracts 再生成(rdb-schema 11 テーブル化: `comparison_definitions` 追加等)
3. 実 PostgreSQL での DDL 作成試験(HANDOFF 再開手順 5。audit_logs 非 partition 化・
   comparison_definitions の排他制約を含む)
4. PostgreSQL・監査ログ・解消結果の実装とテスト、独立検証、更新版レビューでの最終認識合わせ。
   その後に限り `feat: feature flag設定に基づきslotを選択して起動する` の 1 commit へ squash し、
   push・PR 作成へ進む。実装工程の implementer は `gpt-5.6-terra` を使う

## 参照

- 公開 Markdown: `docs/impl/latest/6078c4ed/feedback-requests/`(2件)、
  `docs/pipeline/feedback-requests/20260818_164000_rdra_followup_6078c4ed.md`
- 還流の経緯: `docs/pipeline/HANDOFF.md`(20260818 版)、`docs/pipeline/feedback-runs/`(2 run の result.json)
- 実装事実: `docs/impl/latest/6078c4ed/feedback/as-built-summary.md`
- レビュー回答: `docs/impl/latest/6078c4ed/review/review-notes.md`
- 学び: `docs/impl/latest/6078c4ed/learnings/`
