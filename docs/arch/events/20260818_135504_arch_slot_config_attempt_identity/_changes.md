# 変更サマリ

- event_id: 20260818_135504_arch_slot_config_attempt_identity
- trigger_event: rdra:20260818_133855_rerun_identity_new_run_id, nfr:20260817_144844_initial_nfr

```yaml
feedback_request:
  feedback_request_id: "20260818_113601_impl_feedback_6078c4ed"
  input_sha256: "57396b15a51da62949a111f13ef986398ac2e22674e9f47751100f6b24960746"
  request_ids: ["CR-6078c4ed-003","CR-6078c4ed-005"]
  work_unit_ids: ["CR-6078c4ed-003#1","CR-6078c4ed-005#1"]
```

- direct_work_unit_ids: CR-6078c4ed-005#1
- feedback_packet: docs/pipeline/feedback-runs/20260818_113601_impl_feedback_6078c4ed/stage-packets/architecture.md

## 追加

- domain_architecture/bounded_contexts/BC-001: ユビキタス言語に「slot別実行設定」「attempt（起動試行）」を追加。owned_entity_ids に E-007 を追加
- data_architecture/entities: slot実行設定（E-007。run 共通 execution spec から分離した slot 別実行設定: host / exec_user / script_path / work_dir / fixed_args / impl_version / credential_ref。PK は run_id + slot_type）
- data_architecture/storage_mapping: E-007 → rdb

## 変更

- domain_architecture/bounded_contexts/BC-001: run・実行設定の定義を更新（再実行は新 run_id + parent_run_id 関連付け・既存履歴不変、実行設定の run 共通部と slot 別の分離）
- domain_architecture/aggregate_hypotheses/AG-001: member に E-007 を追加。slot別実行設定の一度だけ確定・再実行 identity の不変条件を追加
- domain_architecture/aggregate_hypotheses/AG-002: 起動試行 identity（run_id, slot種別, role区分, attempt_id）+ attempt_no 連番、STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED 遷移、timeout 後は UNKNOWN（推測で FAILED を確定しない）へ不変条件を更新
- system_architecture/cross_tier_policies/CTP-006: 冪等性方針を再実行 identity（新 run_id 発行 + parent_run_id 関連付け、既存 run のレコード・状態・履歴不変）と整合するよう更新（confidence: user）
- app_architecture/tier_layers/tier-facade: L-facade-domain の責務と LP-003 を実行状態 6 値 + timeout 後 UNKNOWN の定義へ更新（confidence: user）。L-facade-repository / L-facade-gateway の責務に slot別実行設定を追記。LR-003 の重複起動防止キーを run_id・slot・attempt_id に更新
- data_architecture/entities/execution-spec.json（E-001）: slot 別属性（host / exec_user / script_path / work_dir / fixed_args / impl_version / credential_ref）を E-007 へ移動し、run 共通部（run_id / parent_run_id / job_id / additional_args / job_map_version / hang_detect_limit_minutes）のみに変更。E-007 への 1:N 関連を追加
- data_architecture/entities/Runner実行結果（E-002）: identity を（run_id, slot_type, role_type, attempt_id）の複合 PK に変更。attempt_no / accepted_at（起動受付）を追加し、started_at を nullable に変更。status を STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED に変更。E-007 への N:1 関連を追加
- data_architecture/diagram_mermaid: SLOT_CONFIG を追加

## 削除

- なし（E-001 の slot 別属性の除去は E-001 エンティティの「変更」として扱う。エンティティ・policy/rule の削除はない）
