# インフラ設計イベント

| 項目 | 値 |
|------|-----|
| イベント ID | 20260830_190412_infra_product_design |
| 作成日時 | 2026-08-30T20:17:49 |
| ソース | arch-design.yaml からのインフラ設計変換 |
| Arch 参照 | 20260830_184457_initial_arch |
| NFR 参照 | 20260830_183726_initial_nfr |

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
