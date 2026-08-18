# S8: 訂正版 feedback draft の作成

旧公開 request `20260817_234841_impl_feedback_6078c4ed` を入力にした dist-pipeline が
仕様生成段階の上流矛盾 4 件で中止されたため、「公開後の訂正」規約に従い
supersedes 付きの新 draft を作成した。

- feedback_id: `20260818_113601_impl_feedback_6078c4ed`(supersedes: 旧 ID)
- 変更要求 5 件(blocker 4 件: 再実行 identity / partition 契約 / slot 別実行設定と試行 identity / 履歴方針。spec-gap 1 件: 仕様再生成時の反映候補 7 項目の集約)
- 確定済み事項(PostgreSQL、監査ログ追記等)は再選定不要の前提として明記
- learnings に上流矛盾による仕様還流ブロックの学びを 1 件追加

次: S9 レビュー再生成 → ユーザー承認 → S8 publish。
