# インフラ設計イベント

| 項目 | 値 |
|------|-----|
| イベント ID | 20260819_111931_infra_product_design |
| 作成日時 | 2026-08-19T11:19:31 |
| ソース | 比較定義エンティティの永続化とforeground終了コード透過・退避コード分離をインフラ設計へ反映 |
| Arch 参照 | 20260819_110531_arch_comparison_definition_exitcode |
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
| docs/mcl/product/output/product-observability.yaml | updated |
| docs/mcl/product/output/product-cost-hints.yaml | unchanged |
| docs/cloud-context/decisions/product/product-decision-onprem-only.yaml | unchanged |
| docs/cloud-context/decisions/product/product-decision-storage-approach.yaml | unchanged |
| docs/cloud-context/decisions/product/product-decision-event-snapshot-persistence.yaml | unchanged |
| docs/cloud-context/decisions/product/product-decision-audit-persistence.yaml | unchanged |
| docs/cloud-context/conformance/product/product-conformance-onprem.yaml | updated |
| docs/cloud-context/sources/onprem/postgresql-high-availability.md | unchanged |
| docs/cloud-context/sources/onprem/minio-object-storage.md | unchanged |
| docs/cloud-context/sources/onprem/rabbitmq-production-checklist.md | unchanged |
| docs/cloud-context/sources/onprem/redis-replication.md | unchanged |

## Arch フィードバック
