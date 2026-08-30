# 変更サマリ

- event_id: 20260819_110531_arch_comparison_definition_exitcode
- trigger_event: rdra:20260819_104301_slot_config_comparison_def_exitcode, nfr:20260817_144844_initial_nfr

```yaml
feedback_request:
  feedback_request_id: "20260818_164000_rdra_followup_6078c4ed"
  input_sha256: "b4b730a7e786c58c6d949948b78ce20988e293d795ae752239a546e36557bf72"
  request_ids: ["CR-6078c4ed-008","CR-6078c4ed-009","CR-6078c4ed-010"]
  work_unit_ids: ["CR-6078c4ed-008#1","CR-6078c4ed-009#1","CR-6078c4ed-010#1"]
```

- direct_work_unit_ids: （なし。reconciliation 専用ステージ）
- feedback_packet: docs/pipeline/feedback-runs/20260818_164000_rdra_followup_6078c4ed/stage-packets/architecture.md

## 追加

- domain_architecture/bounded_contexts: BC-005 クロスチェック定義管理コンテキスト（比較定義 E-008 を所有。BUC を持たない参照専用コンテキストのため owned_buc_ids は空、related_subdomain_id は SD-002）
- domain_architecture/context_map: CM-005（BC-005 → BC-002、OHS+PL・upstream）、CM-006（BC-005 → BC-003、OHS+PL・upstream）
- domain_architecture/aggregate_hypotheses: AG-006（root: E-008。有効期間の重複禁止・世代の追記管理・速報/確報で同一世代参照の不変条件）
- system_architecture/tiers/tier-facade/rules: SR-006 relay-gateエラーの退避終了コード分離（実行結果未確定・取得不能・中止済み = 125、バリデーションエラー = 124、bash 予約 126/127 と非衝突、UNKNOWN の推測確定禁止、relay-gate エラー時の stderr 併記）
- data_architecture/entities: 比較定義（E-008。job_id + valid_from を PK とする resource_scd2。valid_to / target_tables / target_files / comparator_id）
- data_architecture/storage_mapping: E-008 → rdb
- data_architecture/entities/速報比較依頼（E-003）: E-008 への N:1 関連を追加
- data_architecture/entities/確報比較依頼（E-005）: E-008 への N:1 関連を追加

## 変更

- domain_architecture/diagram_mermaid: BC5（クロスチェック定義管理コンテキスト）と BC5 → BC2 / BC5 → BC3 を追加
- system_architecture/tiers/tier-facade/policies/SP-002: 名称を「foreground結果限定応答・終了コード透過」に変更し、foreground の exitcode.txt 値を 0 を含む全値そのまま透過する（丸め・再割り当てを行わない）方針を明記
- data_architecture/entities/slot実行設定（E-007）: source_info を「情報: execution-spec.json（slot別実行設定の分離）」から「情報: slot別実行設定」へ変更（RDRA 情報.tsv に独立エンティティとして追加された名称へ整合）
- data_architecture/entities/速報比較依頼（E-003）: job_id の説明に比較定義（E-008）の解決キーである旨を追記
- data_architecture/entities/確報比較依頼（E-005）: target_tables / target_files の説明に比較定義（E-008）から解決した対象を依頼時点で確定保持する旨を追記
- data_architecture/diagram_mermaid: COMPARISON_DEFINITION と速報／確報比較依頼への適用関連を追加

## 削除

- なし
