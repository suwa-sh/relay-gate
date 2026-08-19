# 変更サマリ: 20260818_141149_infra_product_design

trigger_event: arch:20260818_135504_arch_slot_config_attempt_identity, nfr:20260817_144844_initial_nfr
feedback_request_id: 20260818_113601_impl_feedback_6078c4ed

## 追加

- `docs/cloud-context/decisions/product/product-decision-event-snapshot-persistence.yaml`
  - runner_result_events（append-only履歴INSERT）+ runner_results（snapshot UPSERT）を同一transactionで更新するEvent/Snapshot併用方式の Decision Record（CR-6078c4ed-006、arch LR-002整合）

## 変更

- `docs/mcl/product/output/product-impl-onprem.yaml`
  - comp-audit-store: 監査テーブルを非partitionの追記専用audit_logsへ変更（CR-6078c4ed-004）。event_id単独主キー + （run_id, slot, attempt_id, event_name）一意制約を実PostgreSQL DDLとして成立させる。occurred_at / run_id / parent_run_idの索引、専用保守権限ロールによる6ヶ月保持、実測負荷時のregistry分離を含むpartition設計への移行方針を明記。除外項目・追記専用の権限境界・ハッシュチェーンは維持
  - comp-datastore-rdb: run共通実行設定とslot別実行設定の分離、Runner実行結果identity（run_id, slot_type, role_type, attempt_id）と実行状態6値（STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED）、runner_result_events + runner_resultsのEvent/Snapshot併用（同一transaction更新）を反映（CR-6078c4ed-005 / 006）
- `docs/mcl/product/output/product-mapping-onprem.yaml`
  - 監査マッピング: 期間パーティション前提を撤回し、非partition追記専用テーブル + 専用保守権限による保持運用へ変更（CR-6078c4ed-004）
  - 永続化マッピング: event_snapshot型エンティティのEvent/Snapshot併用方式を追記（CR-6078c4ed-006）
- `docs/mcl/product/output/product-workload-model.yaml`
  - product.consistency_needs: REQ-CN-003（起動試行identityと再実行系譜の不変履歴）を追加（CR-6078c4ed-003 / 005）
  - product.persistence: REQ-PS-004（履歴追記とsnapshot更新の同一トランザクション実行）を追加（CR-6078c4ed-006）
- `docs/mcl/product/input/product-input.yaml`（および `product-input.yaml` コピー）
  - databaseエレメントにrun共通実行設定 / slot別実行設定（E-007）の分離、Runner実行結果identityと状態6値、Event/Snapshot併用要件、再実行の新run_id + parent_run_id関連付けを反映（CR-6078c4ed-003 / 005 / 006）
- `docs/cloud-context/decisions/product/product-decision-storage-approach.yaml`
  - snapshot-only前提を撤回し、Event/Snapshot併用方式（LR-002整合）を明記（CR-6078c4ed-006）
- `docs/cloud-context/decisions/product/product-decision-audit-persistence.yaml`
  - 非partition初期構成の根拠（partitioned tableのPRIMARY KEY/UNIQUE制約とidempotency契約の非両立）、専用保守権限による保持運用、partition移行方針を追記（CR-6078c4ed-004）
- `docs/cloud-context/conformance/product/product-conformance-onprem.yaml`
  - REQ-AU-003のevidenceを非partition保持へ更新、REQ-CN-003 / REQ-PS-004の適合行を追加

## 削除

- なし

## 変更なし

- `docs/mcl/product/output/product-observability.yaml`（監査identity表現run_id・slot・attempt_idはarch定義と一致済み）
- `docs/mcl/product/output/product-cost-hints.yaml`
- `docs/cloud-context/sources/`、`infra/product/`（IaCスケルトン）
