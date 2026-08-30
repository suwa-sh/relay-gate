# 変更サマリ

- event_id: 20260818_093020_infra_product_design
- trigger_event: arch:20260818_090120_arch_audit_contract_feedback, nfr:20260817_144844_initial_nfr
- feedback_request_id: 20260817_234841_impl_feedback_6078c4ed
- input_sha256: bc64202288e80a7c6a299affcff26d45d91238a851ec5483b2d9eecb1bdabb54
- request_ids: CR-6078c4ed-002
- direct_work_unit_ids: なし
- causal_work_unit_ids: CR-6078c4ed-002#1
- feedback_packet: docs/pipeline/feedback-runs/20260817_234841_impl_feedback_6078c4ed/stage-packets/infrastructure.md
- 種別: インフラ設計の差分具体化（MCL出力は全量再生成）

## 監査イベント永続化の具体化

- PostgreSQLの追記専用監査テーブルへ、操作受付・slot別起動試行・成功・失敗・timeout・最終状態を同一schemaで記録する。
- `run_id` / `parent_run_id`の複合索引と、`run_id`・`slot`・`attempt_id`・`event_name`の一意制約で照会と冪等再試行を支える。
- `previous_hash` / `event_hash`によるハッシュチェーンを定期検証し、月次パーティションで6ヶ月保持する。
- 認証情報、起動引数の実値、stdout/stderr本文は監査テーブルへ保存しない。
- 外部slot起動前の監査追記失敗は起動を中止する。起動後の失敗は結果と未記録イベントをローカル永続outboxへアトミックに保存し、照合ワーカーが重複なく追記する。

## MCL出力

- ワークロードモデルへ「監査イベント永続化 capability」と6件の必須要件を追加した。
- オンプレミスマッピングへPostgreSQL追記専用監査テーブルとローカル永続outboxを追加した。
- 実装仕様へ監査ゲート、監査イベントストア、再試行・照合ワーカーを追加した。
- 監視仕様へ監査追記失敗、再試行滞留、ハッシュチェーン不一致のメトリクスとアラートを追加した。
- 適合性レポートで監査要件6件をconformantとして照合した。

## Archフィードバック

- 追加なし。監査対象、append-only、ハッシュチェーン、6ヶ月保持、機密情報除外、外部作用前後の失敗契約は入力Archの監査ログ方針と失敗時契約で既に確定している。
- 入力Archイベント `20260818_090120_arch_audit_contract_feedback` を照合済みとして参照し、`docs/arch/latest/` は変更しない。

## 削除

- なし
