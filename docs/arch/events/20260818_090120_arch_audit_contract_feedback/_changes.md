# 変更サマリ

- event_id: 20260818_090120_arch_audit_contract_feedback
- trigger_event: feedback:20260817_234841_impl_feedback_6078c4ed
- feedback_request_id: 20260817_234841_impl_feedback_6078c4ed
- input_sha256: bc64202288e80a7c6a299affcff26d45d91238a851ec5483b2d9eecb1bdabb54
- request_ids: CR-6078c4ed-002
- direct_work_unit_ids: CR-6078c4ed-002#1
- causal_work_unit_ids: CR-6078c4ed-002#1
- feedback_packet: docs/pipeline/feedback-runs/20260817_234841_impl_feedback_6078c4ed/stage-packets/architecture.md

## 追加

- system_architecture/cross_tier_rules: CTR-008「slot起動監査ログの失敗時契約」を追加
  - 外部作用前は監査書込み失敗時に起動を中止し、外部作用後は結果を保持して再試行・照合する
  - run_id・slot・attempt_idにより重複追記を防ぐ

## 変更

- system_architecture/cross_tier_policies: CTP-005「監査ログ・操作ログ」を具体化
  - slot起動の操作受付、slot別の試行、成功、失敗、timeout、最終状態を監査対象へ追加
  - RDB append-only、共通schema、ハッシュチェーン、6ヶ月保持、run_id/parent_run_id照会を確定
  - 認証情報、起動引数の実値、stdout/stderr本文を監査イベントから除外

## 削除

- なし

## RDRA追加

- なし（監査ログは横断的な非機能契約として既存の状態遷移・run_id相関へ統合）
