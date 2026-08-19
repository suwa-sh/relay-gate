# インフラ設計イベント

| 項目 | 値 |
|------|-----|
| イベント ID | 20260818_093020_infra_product_design |
| 作成日時 | 2026-08-18T09:30:20 |
| ソース | 実装フィードバックに基づくslot起動監査イベントのインフラ具体化 |
| Arch 参照 | 20260818_090120_arch_audit_contract_feedback |
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
| docs/mcl/product/input/product-input.yaml | generated |
| docs/mcl/product/output/product-workload-model.yaml | generated |
| docs/mcl/product/output/product-mapping-onprem.yaml | generated |
| docs/mcl/product/output/product-impl-onprem.yaml | generated |
| docs/mcl/product/output/product-observability.yaml | generated |
| docs/mcl/product/output/product-cost-hints.yaml | generated |
| docs/cloud-context/decisions/product/product-decision-onprem-only.yaml | generated |
| docs/cloud-context/decisions/product/product-decision-storage-approach.yaml | generated |
| docs/cloud-context/decisions/product/product-decision-audit-persistence.yaml | generated |
| docs/cloud-context/conformance/product/product-conformance-onprem.yaml | generated |
| docs/cloud-context/sources/onprem/postgresql-high-availability.md | generated |
| docs/cloud-context/sources/onprem/minio-object-storage.md | generated |
| docs/cloud-context/sources/onprem/rabbitmq-production-checklist.md | generated |
| docs/cloud-context/sources/onprem/redis-replication.md | generated |

## Arch フィードバック
