# infra イベント変更サマリ

- event_id: `20260905_093000_feedback_todo_resolution`
- trigger_event: `arch:20260905_091000_feedback_todo_resolution, nfr:20260905_085000_feedback_todo_resolution`
- created_at: 2026-09-05T09:30:00Z
- 種別: 差分更新(infra-event-diff.yaml。前イベント `20260830_190412_infra_product_design`)
- dialogue_policy: interactive(CR 本文に利用者の決定が明記された事項は決定を採用。確認推奨項目は完了報告で返却)
- feedback request: 20260905_todo_resolution(direct work unit: なし。causal work unit: CR-c770d8f0-001#1 〜 CR-c770d8f0-012#1。packet: docs/pipeline/feedback-runs/20260905_todo_resolution/stage-packets/infrastructure.md)

```yaml
feedback_request:
  feedback_request_id: "20260905_todo_resolution"
  input_sha256: "285429579e9c9d28307d4c779317f01941b915a1203d0e5b5f53a6c014ed7108"
  request_ids: ["CR-c770d8f0-001","CR-c770d8f0-002","CR-c770d8f0-003","CR-c770d8f0-004","CR-c770d8f0-005","CR-c770d8f0-006","CR-c770d8f0-007","CR-c770d8f0-008","CR-c770d8f0-009","CR-c770d8f0-010","CR-c770d8f0-011","CR-c770d8f0-012"]
  work_unit_ids: ["CR-c770d8f0-001#1","CR-c770d8f0-002#1","CR-c770d8f0-003#1","CR-c770d8f0-004#1","CR-c770d8f0-005#1","CR-c770d8f0-006#1","CR-c770d8f0-007#1","CR-c770d8f0-008#1","CR-c770d8f0-009#1","CR-c770d8f0-010#1","CR-c770d8f0-011#1","CR-c770d8f0-012#1"]
```

## MCL 再実行の判断

- translation(workload_type / availability_tier / latency_target_p99 / data_classification / traffic_pattern_type / consistency_model / cost_posture / target_clouds)は無変更
- 影響は canonical element の説明、実装仕様の configuration / validation_rules、conformance の notes、IaC スケルトンの配置ファイル名に限られる
- したがって mcl-product-design の全量再実行はスキップし、MCL 出力を対象箇所だけ更新した(ハイブリッド方式: MCL 出力は全量を本イベントに保持し latest へ全量上書き)

## product-input 変更フィールド

- source_refs: `arch-design:20260830_184457_initial_arch` / `nfr-grade:20260830_183726_initial_nfr` → `arch-design:20260905_091000_feedback_todo_resolution` / `nfr-grade:20260905_085000_feedback_todo_resolution`
- availability_target.notes / recovery_target.notes / observability_needs.notes: NFR A.2.1.1 / A.3.1.1 / A.3.1.2 / C.6.1.1 の 2026-09-05 利用者確定(適用側で上書き可能な既定値)を追記。observability_needs.notes に通知設定の出所(hang-detector.env)と完了通知失敗が自動検知対象外である旨を追記(CR-c770d8f0-012 / 010)
- elements.artifact_store.description: Runner Result に aborted.txt(中止時のみ)を追加し、状態導出規則(ファイル正本)を明記(CR-c770d8f0-004)
- elements.config_store.description / entity_refs: feature flag 9 キー env、ジョブマップ系 CSV、ハング検知定期ジョブ設定 env、設定版なし・マップ版は任意列。entity_refs に E-026 を追加(CR-c770d8f0-001 / 002 / 010)
- elements.mail_notification.description / entity_refs: 送信コマンドの出所を hang-detector.env とし E-026 を追加(CR-c770d8f0-010)

## MCL 出力ファイル(更新)

- `docs/mcl/product/output/product-workload-model.yaml`(更新): artifact_store(aborted.txt、状態導出、off でも中止・リラン・ハング検知が成立)、config_store(9 キー / CSV 規則 / hang-detector.env / 版の出所 / 正本は適用側の版管理)、mail_notification(hang-detector.env)
- `docs/mcl/product/output/product-mapping-onprem.yaml`(更新): artifact_store notes(aborted.txt を同じ規則で確定し管理 DB を参照せず判定)、config_store notes(feature-flag.env / <role>-job-map.csv / crosscheck-job-map.csv / target-catalog.csv / hang-detector.env。版番号付き配置の記述を削除)、mail_notification notes(ALERT_MAIL_CMD / ALERT_MAIL_TO / ALERT_SUBJECT_PREFIX)
- `docs/mcl/product/output/product-impl-onprem.yaml`(更新): impl.storage.artifact_store に artifacts / state_derivation、impl.storage.config_store に contents / versioning / backup と validation_rules 2 件(9 キー検証、CSV ヘッダー・fixed_params 検証)、impl.messaging.mail_relay に send_command の出所と config_store 依存
- `docs/mcl/product/output/product-observability.yaml`(更新): alert-health-check の condition(aborted.txt は終端し通知しない)、alert-health-check / alert-error-rate の channel(通知設定の出所)
- `docs/mcl/product/output/product-cost-hints.yaml`(変更なし)
- `docs/cloud-context/conformance/product/product-conformance-onprem.yaml`(更新): REQ-DB-004 / REQ-ART-001 / REQ-CFG-001 / REQ-CFG-002 / REQ-LOG-001 / REQ-MAIL-001 の notes。status / summary(conformant 18 / partial 5)は据え置き
- `docs/cloud-context/generated-md/product/relay-gate-target-architecture.md`(更新): 成果物・設定ノードの注記、hang-detector → 成果物 / 設定、ops CLI → 成果物(aborted.txt)の辺
- `docs/cloud-context/decisions/product/*.yaml`(変更なし。決定記録は履歴として据え置き)
- `infra/product/onprem/ansible/roles/relay-gate-config/tasks/main.yml`(更新): 配置ファイルを `feature-flag.env` / `blue-job-map.csv` / `green-job-map.csv` / `crosscheck-job-map.csv` / `target-catalog.csv` に変更(旧: `feature-flags.env` / `job-map.yaml` / `crosscheck-job-map.yaml` / `target-catalog.yaml`)。`hang-detector.env` の配置(0640)と平文認証情報の静的検査タスクを追加
- その他の IaC スケルトン(runtime / postgresql / mail / backup ロール、terraform)は変更なし

## infra-event.yaml 変更フィールド

- event_id / created_at / source / arch_event_ref / nfr_event_ref を本イベントへ更新。trigger_event / previous_event_ref / feedback_request を追加
- mcl_execution.outputs の description に 20260905 差分の要約を追記
- arch_feedback: 据え置き(新規フィードバックなし)

## arch フィードバック

- なし。本イベントの差分はすべて arch 20260905_091000_feedback_todo_resolution の変更を下流へ追従したもので、infra から arch へ新たに戻す知見は無い。arch のイベントは作成していない

## 書き戻しチェック

- 不要。arch 差分はティア構成・認証認可方式・DR 方針・外部連携・storage_type を変えておらず、product-input の translation フィールドに影響しない

## 照合結果(causal work unit)

| work unit | status | 反映先 / 理由 |
|---|---|---|
| CR-c770d8f0-001#1 | changed | config_store(9 キー env、設定版なし、実装版の出所)を workload-model / mapping / impl / conformance / product-input / ansible config ロールへ反映 |
| CR-c770d8f0-002#1 | changed | ジョブマップ系の CSV 形式・ファイル名・セル規則・fixed_params 検証を同上へ反映 |
| CR-c770d8f0-003#1 | not_impacted | run_id の形式は infra の要素(主キー一意性・ログ相関キー)に影響せず、形式自体を infra は定めていない |
| CR-c770d8f0-004#1 | changed | aborted.txt と状態導出規則を artifact_store(workload-model / mapping / impl / conformance / product-input)、observability、構成図へ反映 |
| CR-c770d8f0-005#1 | not_impacted | 完了通知失敗の扱いは RDRA 条件・spec の責務。infra の観測仕様は NFR observability_needs(無変更)から導出しており、product-input の notes への注記以外に構成変更は無い |
| CR-c770d8f0-006#1 | already_current | infra は初期構築時から管理 DB を relay-gate 内部の canonical element(product.database.management_db / product-decision-002)として扱っており、外部システム表記は無い |
| CR-c770d8f0-007#1 | not_impacted | 情報属性(調整記録の置き場、応答日時)は infra の要素・実装仕様に現れない |
| CR-c770d8f0-008#1 | not_impacted | 監視状態の値集合と遷移は infra の観測仕様に列挙されていない |
| CR-c770d8f0-009#1 | not_impacted | 並行稼働実行の遷移は管理 DB 内の状態機械であり infra の構成に影響しない |
| CR-c770d8f0-010#1 | changed | hang-detector.env を config_store / mail_notification / observability / conformance / ansible config ロールへ反映 |
| CR-c770d8f0-011#1 | not_impacted | 比較結果の登録条件は worker のアプリケーション規則であり infra に影響しない |
| CR-c770d8f0-012#1 | changed | NFR 7 項目の利用者確定(既定値)を product-input の notes と conformance の notes(REQ-DB-004 / REQ-LOG-001)へ反映 |

## 仮採用(confidence: low)

- なし(新規 low は作らない。既存の REQ-OPS-002(組織既存監視の有無。todo DIST-013)は本 CR の対象外で据え置き)

## 確認推奨項目

- ジョブマップの配置ファイル名: IaC スケルトンでは slot ごとに `blue-job-map.csv` / `green-job-map.csv` とした(元資料の例示は実装名を含むため中立名に置換)。spec の CLI 契約でのファイル名確定時に揃える
