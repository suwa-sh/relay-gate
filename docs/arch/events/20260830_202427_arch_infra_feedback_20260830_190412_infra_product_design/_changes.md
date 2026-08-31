# arch フィードバック変更サマリ

- event_id: `20260830_202427_arch_infra_feedback_20260830_190412_infra_product_design`
- trigger_event: `infra:20260830_190412_infra_product_design`

## 追加

- `CTP-010`: SLI/SLOベースのオブザーバビリティ方針(根拠: `product-observability.yaml`)
- `CTP-011`: コスト最適化方針(既存ホスト相乗り)(根拠: `product-cost-hints.yaml`)
- `CTR-006`: オンプレミス代替構成における手動運用への配慮(根拠: `product-mapping-onprem.yaml` の fidelity=partial 4件)

## 変更(confidence昇格。既存項目の削除・内容変更は無し)

- `data_architecture.storage_mapping[E-008]`(対象カタログ): `confidence: medium → high`(根拠: config_store の fidelity=exact)
- `data_architecture.storage_mapping[E-012]`(応答/実行ログ): `confidence: medium → high`(根拠: execution_log_store の fidelity=exact)

## 削除

なし(既存 policy/rule/constraint は一切変更していない)

## 見送り(todo.md 登録)

- 管理DBのRPO 4h/RTO 12h具体値の `technology_context.constraints` への明文化は、既存 CTP-006 との重複可能性を
  考慮し保守的に見送り、`docs/todo.md`(DIST-014)に確認事項として登録した。

## confidence: "user" の保護確認

CTR-005(実装言語と実行環境、confidence: user)を含め、confidence: "user" の全項目は変更していない。
