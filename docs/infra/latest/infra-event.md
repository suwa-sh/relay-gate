# インフラ設計イベント

| 項目 | 値 |
|------|-----|
| イベント ID | 20260817_151023_infra_product_design |
| 作成日時 | 2026-08-17T15:10:23 |
| ソース | arch-design.yaml からのインフラ設計変換 |
| Arch 参照 | 20260817_150512_initial_arch |
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
| docs/cloud-context/conformance/product/product-conformance-onprem.yaml | generated |
| docs/cloud-context/sources/onprem/postgresql-high-availability.md | generated |
| docs/cloud-context/sources/onprem/minio-object-storage.md | generated |
| docs/cloud-context/sources/onprem/rabbitmq-production-checklist.md | generated |
| docs/cloud-context/sources/onprem/redis-replication.md | generated |

## Arch フィードバック

### フィードバック項目

| ターゲット | アクション | 説明 |
|-----------|-----------|------|
| technology_context.constraints | add | 外部SaaS型の監視・アラーティングサービスはエアギャップ環境のため利用不可。閉域内監視基盤の整備が前提となる |
| system_architecture.cross_tier_policies | add | SLI/SLOベースのオブザーバビリティ方針（可用性99.9%、p99レイテンシ1秒以内、エラーバジェット運用） |
| system_architecture.cross_tier_rules | add | 可用性・リストア運用手順の整備（自動フェイルオーバー/自動リストア非対応のため手順書化） |
| system_architecture.cross_tier_rules | add | アラートしきい値・エスカレーションの統一方針 |
| system_architecture.tiers[tier-datastore].policies | add | 実行ログのストレージ階層化（コールドストレージ相当への移動） |
