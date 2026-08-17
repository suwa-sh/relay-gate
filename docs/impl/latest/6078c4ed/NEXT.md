# 次の作業: PostgreSQL・監査ログ仕様の反映

## 現在の状態

- state: `blocked_on_spec`
- feedback ID: `20260817_234841_impl_feedback_6078c4ed`
- 変更要求: 2件
- blocker: 0件
- 選択済み: PostgreSQL採用、slot起動監査ログ追記
- PR: 未作成。仕様・実装・テストへの反映と最終レビューが終わるまで作成しない

## 次に実行するコマンド

新しいセッション、またはコンテキストをクリアした後に1回実行する。

```text
/distillery:dist-pipeline docs/impl/latest/6078c4ed/feedback-requests/20260817_234841_impl_feedback_6078c4ed.md --recommended-auto
```

2件とも仕様上の詳細決定を含む。`--recommended-auto`は安全なroutingだけを自動採用し、
PostgreSQLのDSN・driver・timeoutや監査eventのschema・sink・保持など、意味を変える判断が
必要なら選択肢と推奨案を提示して停止する。

## 仕様反映後の再開

```text
/distillery-impl:dist-impl-run 6078c4ed
```

入力hashが変わった範囲だけを再実行し、PostgreSQL・監査ログの実装とテスト、独立検証、
更新版レビューでの最終認識合わせを行う。その後に限り、`feat: feature flag設定に基づきslotを選択して起動する`
の1 commitへsquashし、push・PR作成へ進む。

## 参照

- 変更要求: `docs/impl/latest/6078c4ed/feedback-requests/20260817_234841_impl_feedback_6078c4ed.md`
- 補助レビュー: `docs/impl/latest/6078c4ed/review/index.html`（Git管理外）
- 実装事実: `docs/impl/latest/6078c4ed/feedback/as-built-summary.md`
- レビュー回答: `docs/impl/latest/6078c4ed/review/review-notes.md`
