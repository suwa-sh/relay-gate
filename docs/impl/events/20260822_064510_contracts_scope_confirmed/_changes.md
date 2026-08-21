# 契約 relay-gate-db の scope を全 11 テーブルへ拡張

仕様還流で rdb-schema.yaml が 11 テーブルになったため、S0 bootstrap を再実行した。
P2 の content-stable 導出で差分が出たのは `contracts[relay-gate-db].scope` のみ。

- 追加: slot_execution_specs / runner_result_events / comparison_definitions / audit_chain_heads
- 規則: 既存どおり「rdb-schema の全テーブルを scope にする」を継続(ユーザー承認: 案 A)
- provider / consumers は変更なし(tier-worker / [tier-facade])
