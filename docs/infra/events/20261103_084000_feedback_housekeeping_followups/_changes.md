# 変更サマリ

- event_id: 20261103_084000_feedback_housekeeping_followups
- trigger_event: usdm:20261103_081000_feedback_housekeeping_followups, rdra:20261103_081000_feedback_housekeeping_followups, nfr:20261103_082000_feedback_housekeeping_followups, arch:20261103_083000_feedback_housekeeping_followups
- created_at: 2026-11-03T08:40:00Z
- mode: 差分更新(infra-event-diff.yaml。MCL product-design の全量再実行なし: skipped_targeted_update)
- feedback request: 20261103_housekeeping_followups(direct work unit: なし。causal work unit: CR-f3b8a1d0-001#1(管理 DB に接続しないハウスキープ)/ CR-f3b8a1d0-003#1(実行ログの整理を logrotate に任せる)。packet: docs/pipeline/feedback-runs/20261103_housekeeping_followups/stage-packets/infrastructure.md)

## 追加

- なし

## 変更

- docs/mcl/product/input/product-input.yaml(と直下コピー): management_db に接続しない設定の間は量が頭打ちにならないこと、config_store のハウスキープ設定に off では接続参照名を省略・空にできることを追記(CR-f3b8a1d0-001)
- product-workload-model.yaml: management_db / artifact_store の容量の頭打ちに接続しない設定の例外、config_store のハウスキープ設定に接続参照名の省略を追記(CR-f3b8a1d0-001)
- product-mapping-onprem.yaml: management_db / artifact_store / config_store の notes に接続しない設定の振る舞いを追記(CR-f3b8a1d0-001)
- product-impl-onprem.yaml: housekeep_delete / connection_resolution / artifact capacity / config contents に接続しない設定を追記し、ハウスキープ設定の検証規則を「存在すること。保持日数のキーは省略可(既定 90 日)、接続参照名のキーは off 以外で必須(off では省略・空を許す)」に改めた(CR-f3b8a1d0-001)
- product-observability.yaml: alert-housekeep-failure の対象から、接続しない設定の warn(終了コードに影響しない)を除くと明記(CR-f3b8a1d0-001)
- product-cost-hints.yaml: storage_tiering に接続しない設定の間の増加分を別に見込むことを追記(CR-f3b8a1d0-001)
- product-conformance-onprem.yaml: 設定の notes に接続参照名の省略を追記(判定・集計は不変)(CR-f3b8a1d0-001)
- relay-gate-target-architecture.md: housekeep → 管理 DB の辺のラベルに接続しない条件を追記(CR-f3b8a1d0-001)
- infra/product/onprem/ansible/roles/relay-gate-config/tasks/main.yml: ハウスキープ設定の検査を「空でないこと」から「存在すること(空でもよい)」へ改めた。保持日数のキーは省略でき(既定 90 日。CLI 契約の validate-config --housekeep と同じ)、off では接続参照名も省略・空にできるため(CR-f3b8a1d0-001)
- docs/mcl/foundation/output/foundation-context.yaml、docs/mcl/shared-platform/output/shared-platform-context.yaml: プロジェクトルート(2026-11-03 に SMTP / メール通知の記述を削除済み)からコピーを取り直した。latest のコピーに残っていた古い SMTP の記述が消えた

## 削除

- なし

## 照合結果(causal work unit)

| work unit | status | 反映先 |
|---|---|---|
| CR-f3b8a1d0-001#1 | changed | product-input / workload-model / mapping / impl / observability / cost-hints / conformance / 構成図 / config ロール |
| CR-f3b8a1d0-003#1 | not_impacted | なし(実行ログは logrotate(日次・90 世代・圧縮)で 3 か月保管する記述のままで、手動前提の記述が無いことを確認) |

## 変更しなかった箇所

- IaC(relay-gate-postgresql / relay-gate-runtime ロール、inventory 例): housekeep_del ロールは接続しない設定でも害が無い。logrotate 配置は残す
- 判断記録(product-decision-001〜005): 選定の内容に影響しない
- arch: arch に戻す新しい知見は無い(本 stage は arch を更新しない)
