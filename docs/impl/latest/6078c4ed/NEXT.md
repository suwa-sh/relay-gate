# 次の作業: 上流矛盾4件の解消(訂正版 feedback の還流)

## 現在の状態

- state: `blocked_on_spec`
- feedback ID: `20260818_113601_impl_feedback_6078c4ed`
  (supersedes: `20260817_234841_impl_feedback_6078c4ed`)
- 変更要求: 5件 / blocker: 4件
  - blocker 4件 = 再実行 identity の二重正本 / 監査テーブルの partition 契約 /
    slot 別実行設定と試行 identity / Runner 実行結果の履歴方針
  - 残り1件 = 上流整合後の仕様再生成で反映する修正候補7項目の集約
- ユーザー確定済み(2026-08-18): 全4件とも推奨案を採用
  - 新しい `run_id` + `parent_run_id` 関連付け(履歴を上書きしない)
  - 監査テーブルは初期は非 partition(`occurred_at` / `run_id` 索引 + 6か月保持)
  - run 共通 execution spec と slot 別設定の分離 + slot・`attempt_id` を含む結果 identity +
    `STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED` の正式状態
  - append-only `runner_result_events` + `runner_results` snapshot の同一 transaction 更新
- 旧 feedback(20260817 版)による還流は architecture / infrastructure / design まで反映済み。
  仕様生成は上流矛盾により未完(docs/pipeline/HANDOFF.md 参照)
- PR: 未作成。仕様・実装・テストへの反映と最終レビューが終わるまで作成しない

## 次に実行するコマンド

新しいセッション、またはコンテキストをクリアした後に1回実行する。

```text
/distillery:dist-pipeline docs/impl/latest/6078c4ed/feedback-requests/20260818_113601_impl_feedback_6078c4ed.md --recommended-auto
```

blocker 4件はいずれも推奨案がユーザー確定済みのため、`--recommended-auto` で安全に自動採用できる。
意味を変える追加判断が必要になった場合のみ選択肢が提示されて停止する。
仕様生成後は datastore validator に加え、実 PostgreSQL での DDL 作成試験を行うこと
(HANDOFF の再開手順 5)。

## 仕様反映後の再開

```text
/distillery-impl:dist-impl-run 6078c4ed
```

入力 hash が変わった範囲だけが projection 照合で再実行される(tier-scoped staleness)。
PostgreSQL・監査ログ・4件の解消結果の実装とテスト、独立検証、更新版レビューでの
最終認識合わせを行う。その後に限り `feat: feature flag設定に基づきslotを選択して起動する` の
1 commit へ squash し、push・PR 作成へ進む。実装工程の implementer は `gpt-5.6-terra` を使う。

## 参照

- 公開 Markdown: `docs/impl/latest/6078c4ed/feedback-requests/20260818_113601_impl_feedback_6078c4ed.md`
- 還流の経緯: `docs/pipeline/HANDOFF.md`
- 補助レビュー: `docs/impl/latest/6078c4ed/review/index.html`(Git 管理外)
- 実装事実: `docs/impl/latest/6078c4ed/feedback/as-built-summary.md`
- レビュー回答: `docs/impl/latest/6078c4ed/review/review-notes.md`
- 学び: `docs/impl/latest/6078c4ed/learnings/`
