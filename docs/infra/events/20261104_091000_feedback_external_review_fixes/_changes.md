# 変更サマリ

- event_id: 20261104_091000_feedback_external_review_fixes
- trigger_event: infra:20261103_134000_feedback_housekeeping_db_required(上流 latest は変更なし)
- created_at: 2026-11-04T09:10:00Z
- mode: 差分更新(infra-event-diff.yaml。MCL product-design の全量再実行なし: skipped_targeted_update)
- feedback request: 20261104_external_review_fixes(direct work unit: CR-c5e19a72-002#1。causal work unit: CR-c5e19a72-002#1(構築手順のハング検知設定の検査を CLI 契約に合わせる)。packet: docs/pipeline/feedback-runs/20261104_external_review_fixes/stage-packets/infrastructure.md)

## 追加

- なし

## 変更

構築手順(config ロール)のハング検知定期ジョブ設定(hang-detector.env)の配置時検査が CLI 契約より厳しく、仕様どおりの正当な設定で構築が失敗していた。配置時はファイルの存在確認だけにし、中身の検査は CLI 契約に任せた。

| 項目 | 前回 | 今回 |
|---|---|---|
| 配置時の検査 | HANG_DB_CONN_REF の行が必須。それ以外の非コメント行は拒否(grep) | ファイルがあることの確認だけ(`test -f /etc/relay-gate/hang-detector.env`) |
| 持ち得るキー | HANG_DB_CONN_REF だけ | HANG_DB_CONN_REF / 任意キー RAPID_HANG_DETECT_LIMIT_MINUTES(既定 60)/ HANG_SCAN_WINDOW_HOURS(既定 72) |
| HANG_DB_CONN_REF の必須 | 常に必須 | RAPID_CROSSCHECK_MODE が off 以外のときだけ(off では読まない) |
| 中身の検査の所有者 | 構築手順(配置時) | CLI 契約(config_files の hang-detector.env と config_input_rules の env_files)。hang-detector.sh が起動時に行い、違反は終了コード 2 |

構築が失敗していた正当な設定の例:

- RAPID_CROSSCHECK_MODE=off で HANG_DB_CONN_REF を書かない設定
- ハング疑い上限や走査窓を調整した設定(RAPID_HANG_DETECT_LIMIT_MINUTES / HANG_SCAN_WINDOW_HOURS を持つ)
- 字下げしたコメント行を持つ設定(CLI 契約では前後の空白を除いて `#` で始まる行はコメント行)

変更したファイル:

- infra/product/onprem/ansible/roles/relay-gate-config/tasks/main.yml: 検査タスクを存在確認に改め、中身の検査の所有者をコメントに書いた。配置タスク名の「HANG_DB_CONN_REF だけ」を 3 キーを持ち得る旨に直した
- docs/mcl/product/output/product-impl-onprem.yaml: config_store の contents と検証規則
- docs/mcl/product/output/product-mapping-onprem.yaml: config_store の notes
- docs/mcl/product/output/product-workload-model.yaml: config_store の説明
- docs/cloud-context/conformance/product/product-conformance-onprem.yaml: 設定の要件の notes(判定は不変)
- docs/mcl/product/input/product-input.yaml(と直下コピー): config_store の説明(translation は不変)

## 削除

- 配置時の「HANG_DB_CONN_REF だけを持つこと」の検査(上の存在確認に置き換え)

## 変えなかったもの

- product-observability.yaml / product-cost-hints.yaml / ターゲットアーキテクチャ図 / README / inventory.ini.example / site.yml: hang-detector.env のキー構成を書いていない。latest に files/(設定の例)は無い
- arch: 新しい知見は無い(Phase4 で arch を更新しない)
