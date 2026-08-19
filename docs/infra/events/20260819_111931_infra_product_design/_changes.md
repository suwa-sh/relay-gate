# 変更サマリ: 20260819_111931_infra_product_design

trigger_event: arch:20260819_110531_arch_comparison_definition_exitcode, nfr:20260817_144844_initial_nfr

```yaml
feedback_request:
  feedback_request_id: "20260818_164000_rdra_followup_6078c4ed"
  input_sha256: "b4b730a7e786c58c6d949948b78ce20988e293d795ae752239a546e36557bf72"
  request_ids: ["CR-6078c4ed-008","CR-6078c4ed-009","CR-6078c4ed-010"]
  work_unit_ids: ["CR-6078c4ed-008#1","CR-6078c4ed-009#1","CR-6078c4ed-010#1"]
```

- direct_work_unit_ids: （なし。reconciliation 専用ステージ）
- feedback_packet: docs/pipeline/feedback-runs/20260818_164000_rdra_followup_6078c4ed/stage-packets/infrastructure.md

## 追加

- `docs/mcl/product/output/product-workload-model.yaml`
  - product.workload_type: REQ-WT-003（foreground終了コードの全値透過と、基盤エラーの退避コード125/124への分離）を追加。constraints に「126/127と非衝突」「UNKNOWNの推測変換禁止」を追加
  - product.persistence: REQ-PS-005（有効期間付きマスタ定義の世代追記管理と、実行時点で有効な世代を高々1件に保つ制約）を追加
- `docs/mcl/product/output/product-observability.yaml`
  - メトリクス `relaygate_error_exit_count`（退避コード125/124の応答件数、内訳別）を追加
  - アラート `alert-relaygate-error-exit`（退避コード応答件数の閾値超過）を追加
- `docs/cloud-context/conformance/product/product-conformance-onprem.yaml`
  - REQ-WT-003 / REQ-PS-005 の適合行を追加（summary: total 19→21、conformant 15→17）

## 変更

- `docs/mcl/product/output/product-impl-onprem.yaml`
  - comp-facade: `exit_code_contract`（exitcode.txt値の丸め・再割り当て禁止、退避コード125=実行結果未確定/取得不能/中止済み・124=バリデーションエラー、126/127非衝突）と `error_stderr_composition`（foreground stderr.log内容とrelay-gateエラー内容の併記）を追加。対応する runtime validation rule を追加
  - comp-datastore-rdb: `tables` に比較定義（comparison_definitions）を追加し、`comparison_definition_versioning`（(job_id, valid_from)複合主キー、valid_to、現行世代の部分一意索引、有効期間の排他制約、世代追記のみ、依頼時点の解決値保持）を追加。有効期間の重複禁止を static validation rule として追加
- `docs/mcl/product/output/product-mapping-onprem.yaml`
  - product.workload_type: 終了コード透過と退避コードの写像を configuration_notes に追記
  - product.persistence（PostgreSQL）: 比較定義のSCD2テーブル写像（複合主キー・部分一意索引による世代重複防止）を configuration_notes に追記
- `docs/mcl/product/output/product-observability.yaml`
  - `job_error_rate` / `sli-error_rate` / `alert-error-rate`: 業務ジョブ由来の非0終了とrelay-gate退避コードを区別する定義へ変更
- `docs/mcl/product/input/product-input.yaml`（および `product-input.yaml` コピー）
  - databaseエレメントに比較定義（E-008）と世代管理要件を追加。workload.description に終了コード透過・退避コード分離を追記。source_refs を新しい arch イベントへ更新

## 削除

- なし

## 変更なし

- `docs/mcl/product/output/product-cost-hints.yaml`（比較定義テーブルと終了コード契約はコスト方針に影響しない）
- `docs/cloud-context/decisions/`（既存 Decision Record の判断は変更なし。比較定義は既決の rdb 永続化方針の範囲内）
- `docs/cloud-context/sources/`、`infra/product/`（IaCスケルトン）
- slot別実行設定・起動試行identity・実行状態6値（前回イベント 20260818_141149_infra_product_design で反映済み。今回の arch 変更は E-007 の source_info 名称整合のみで、インフラ写像に影響しない）
