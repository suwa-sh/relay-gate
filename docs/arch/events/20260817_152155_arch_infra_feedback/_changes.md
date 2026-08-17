# 変更サマリ

- event_id: 20260817_152155_arch_infra_feedback
- trigger_event: infra:20260817_151023_infra_product_design

## 追加

- technology_context/constraints: 「外部SaaS型の監視・アラーティングサービスはエアギャップ環境のため利用不可。閉域内監視基盤（ログ集約・可視化）の整備が前提となる」を追加
  - 根拠: product-mapping-onprem.yaml（observability_needs, fidelity: partial）
- system_architecture/cross_tier_policies: CTP-013「SLI/SLOベースのオブザーバビリティ方針」を追加
  - 根拠: product-observability.yaml（sli / slo）
- system_architecture/cross_tier_rules: CTR-006「可用性・リストア運用手順の整備」を追加
  - 根拠: product-mapping-onprem.yaml（fidelity: partial — availability_target, recovery_target, persistence）
- system_architecture/cross_tier_rules: CTR-007「アラートしきい値・エスカレーションの統一方針」を追加
  - 根拠: product-observability.yaml（alerting.rules）
- system_architecture/tiers[tier-datastore]/policies: SP-013「実行ログのストレージ階層化」を追加
  - 根拠: product-cost-hints.yaml（hints[category=storage_tiering]）

## 変更

- なし（既存項目の書き換え・confidence変更は行っていない）

## 削除

- なし

## 見送った項目

- ストレージマッピング（data_architecture.storage_mapping）の confidence 昇格: 既に全エンティティが
  confidence: high のため対象なし
- 技術制約（DB接続プール上限等の数値制約）: MCL 出力（product-impl-onprem.yaml）に該当する数値制約の
  記載がなく、対象なし
