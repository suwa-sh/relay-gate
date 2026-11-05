# インフラ設計イベント

| 項目 | 値 |
|------|-----|
| イベント ID | 20261105_111000_feedback_single_management_db |
| 作成日時 | 2026-11-05T11:10:00+09:00 |
| ソース | 管理 DB の接続先の指摘(2026-11-05)に基づくインフラ設計の差分更新: 管理 DB は 1 つで、すべての接続先の参照名(RAPID_DB_CONN_REF、実行ホストと DB セグメントそれぞれの FINAL_DB_CONN_REF、HANG_DB_CONN_REF、HOUSEKEEP_DB_CONN_REF)が同じ 1 つの管理 DB に解決されることを前提として書く。条件は参照名の文字列ではなく解決先の DB が同じこと。構築時の検査は存在確認のままで、解決先が同じことは導入する側が確かめる |
| Arch 参照 | 20261103_133000_feedback_housekeeping_db_required |
| NFR 参照 | 20261103_132000_feedback_housekeeping_db_required |

## 変換サマリ

| 特性 | 値 |
|------|-----|
| ワークロードタイプ | batch |
| 可用性 | 99% |
| レイテンシ p99 | none |
| データ分類 | internal |
| トラフィック | scheduled |
| 整合性 | strong |
| コスト方針 | cost_optimized |
| 対象クラウド | onprem |

## MCL 実行結果

| ステータス | completed |

### 出力ファイル

| パス | ステータス |
|------|-----------|
| docs/mcl/product/input/product-input.yaml | generated |
| docs/mcl/product/output/product-workload-model.yaml | generated |
| docs/mcl/product/output/product-mapping-onprem.yaml | generated |
| docs/mcl/product/output/product-impl-onprem.yaml | generated |
| docs/mcl/product/output/product-observability.yaml | generated |
| docs/mcl/product/output/product-cost-hints.yaml | generated |
| docs/cloud-context/decisions/product/product-decision-001.yaml | generated |
| docs/cloud-context/decisions/product/product-decision-002.yaml | generated |
| docs/cloud-context/decisions/product/product-decision-003.yaml | generated |
| docs/cloud-context/decisions/product/product-decision-004.yaml | generated |
| docs/cloud-context/decisions/product/product-decision-005.yaml | generated |
| docs/cloud-context/conformance/product/product-conformance-onprem.yaml | generated |
| docs/cloud-context/generated-md/product/relay-gate-target-architecture.md | generated |
| infra/product/onprem/terraform/ | generated |
| infra/product/onprem/ansible/ | generated |
| docs/cloud-context/sources/onprem/ | generated |

## Arch フィードバック

### フィードバック項目

| ターゲット | アクション | 説明 |
|-----------|-----------|------|
| system_architecture.cross_tier_policies | add | SLI/SLOベースのオブザーバビリティ方針 |
| system_architecture.cross_tier_policies | add | コスト最適化方針(既存ホスト相乗り) |
| system_architecture.cross_tier_rules | add | オンプレミス代替構成における手動運用への配慮 |
| data_architecture.storage_mapping[E-008].confidence | upgrade | medium → high(config_storeのfidelity=exactで適合確認) |
| data_architecture.storage_mapping[E-012].confidence | upgrade | medium → high(execution_log_storeのfidelity=exactで適合確認) |
