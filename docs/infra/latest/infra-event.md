# インフラ設計イベント

| 項目 | 値 |
|------|-----|
| イベント ID | 20261116_020000_feedback_standard_runner_job_map_location |
| 作成日時 | 2026-11-16T02:00:00Z |
| ソース | 標準の slot runner の正式な提供と、slot ジョブマップの場所を feature flag の任意の 2 キーで書けること(利用者決定 2026-11-16)に基づくインフラ設計の差分更新: 標準の slot runner(ローカル実行と SSH 実行)を facade と同じ実行ホストの配置物として書き、feature flag を 9 キー + 任意の 2 キー、ジョブマップの場所を任意のキーで指定でき無い・空なら固定の名前、と構築手順とインフラ設計に反映する。構築時の検査は存在確認のままで、指定先と配置先が一致することは導入する側が確かめる |
| Arch 参照 | 20261116_015000_feedback_standard_runner_job_map_location |
| NFR 参照 | 20261116_014000_feedback_standard_runner_job_map_location |

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
