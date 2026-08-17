# 変更サマリ

- event_id: 20260817_151023_infra_product_design
- trigger_event: arch:20260817_150512_initial_arch, nfr:20260817_144844_initial_nfr
- 種別: 初期構築（infra-event.yaml 全量作成）

## product-input 変換サマリ（追加）

- workload_type: "api"
- availability_tier: "99.9%"（warm_standby）
- latency_target_p99: "1s"
- data_classification: "internal"
- traffic_pattern_type: "scheduled"（baseline_rps: 1, spike_multiplier: 3）
- consistency_model: "strong"
- cost_posture: "cost_optimized"
- target_clouds: ["onprem"]

foundation-context / shared-platform-context は、前段ステップでオンプレミス単一サイト向けの
最小構成コンテキストとして補完済み（shared-platform-context は最小構成のため
`available_shared_services: []`）。

## MCL 出力ファイル（新規生成）

- docs/mcl/product/output/product-workload-model.yaml
- docs/mcl/product/output/product-mapping-onprem.yaml
- docs/mcl/product/output/product-impl-onprem.yaml
- docs/mcl/product/output/product-observability.yaml
- docs/mcl/product/output/product-cost-hints.yaml
- docs/cloud-context/decisions/product/product-decision-onprem-only.yaml
- docs/cloud-context/decisions/product/product-decision-storage-approach.yaml
- docs/cloud-context/conformance/product/product-conformance-onprem.yaml
- docs/cloud-context/sources/onprem/*.md（4件）

対象クラウドはオンプレミス1系統のみ（エアギャップ環境の制約）。IaC スケルトン
（infra/product/onprem/）は本イベントでは生成されていない（MCL 出力の任意項目）。

## arch フィードバック

- Phase4 で実施。詳細は arch フィードバックイベントの _changes.md を参照。
