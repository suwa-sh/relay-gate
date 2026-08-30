# インフラ設計イベント

| 項目 | 値 |
|------|-----|
| イベント ID | 20260818_141149_infra_product_design |
| 作成日時 | 2026-08-18T14:11:49 |
| ソース | 実装フィードバックに基づく監査テーブルDDL契約の是正とEvent/Snapshot併用永続化への更新 |
| Arch 参照 | 20260818_135504_arch_slot_config_attempt_identity |
| NFR 参照 | 20260817_144844_initial_nfr |

## 変換サマリ

| 特性 | 値 |
|------|-----|
| ワークロードタイプ | api |
| 可用性 | 99.9% |
| レイテンシ p99 | 1s |
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
| docs/mcl/product/input/product-input.yaml | updated |
| docs/mcl/product/output/product-workload-model.yaml | updated |
| docs/mcl/product/output/product-mapping-onprem.yaml | updated |
| docs/mcl/product/output/product-impl-onprem.yaml | updated |
| docs/mcl/product/output/product-observability.yaml | unchanged |
| docs/mcl/product/output/product-cost-hints.yaml | unchanged |
| docs/cloud-context/decisions/product/product-decision-onprem-only.yaml | unchanged |
| docs/cloud-context/decisions/product/product-decision-storage-approach.yaml | updated |
| docs/cloud-context/decisions/product/product-decision-event-snapshot-persistence.yaml | generated |
| docs/cloud-context/decisions/product/product-decision-audit-persistence.yaml | updated |
| docs/cloud-context/conformance/product/product-conformance-onprem.yaml | updated |
| docs/cloud-context/sources/onprem/postgresql-high-availability.md | unchanged |
| docs/cloud-context/sources/onprem/minio-object-storage.md | unchanged |
| docs/cloud-context/sources/onprem/rabbitmq-production-checklist.md | unchanged |
| docs/cloud-context/sources/onprem/redis-replication.md | unchanged |

## Arch フィードバック
