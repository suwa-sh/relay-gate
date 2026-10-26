# 変更サマリ

- event_id: 20261010_203000_feedback_impl_feedback_dcd8234d
- trigger_event: arch:20261010_202000_feedback_impl_feedback_dcd8234d, nfr:20261010_201000_feedback_impl_feedback_dcd8234d
- created_at: 2026-10-10T20:30:00Z
- mode: 差分更新(infra-event-diff.yaml。MCL は全面再実行せず該当箇所のみ差分更新 = skipped_targeted_update)
- feedback request: 20261010_104636_impl_feedback_dcd8234d(direct work unit: なし。causal work unit: CR-dcd8234d-007#1, CR-dcd8234d-001#1, CR-dcd8234d-002#1, CR-dcd8234d-003#1。packet: docs/pipeline/feedback-runs/20261010_104636_impl_feedback_dcd8234d/stage-packets/infrastructure.md)

本イベントは、クロスチェック簡素化(causal: CR-dcd8234d-007)が前段の RDRA / NFR / arch へ反映された結果を、インフラ設計(MCL 出力と IaC スケルトン)へ追従させる。方針資料(tmp/RelayGateのしくみ.md / tmp/RelayGateの利用イメージ.md)が定める「比較対象の定義は適用側(比較ツール側)」「worker は DB の依頼レコードと自身の設定だけで起動」「速報と確報は同じパターンで違いは対象の量」に沿う方向の変更であり、矛盾しない。

## 追加

- 設定ファイル `final-crosscheck.env`(確報クロスチェック worker 設定): 確報 worker の DB 接続参照と確報比較ツールの起動コマンド 1 行。config ロールが配置し、確報 worker が起動のたびに読む。確報 worker は DB セグメントで動き、runner 側の成果物ファイルパスを読まない
- `rapid-crosscheck.env` に速報比較ツールの起動コマンド 1 行(プレースホルダ {job_id} 必須)を追加
- impl-onprem の検証規則に final-crosscheck.env の存在・キー構成検査を追加(起動コマンドの内容検証は validate-config.sh が所有)

## 変更

- product-input.yaml(docs/mcl/product/input/ と latest 直下コピーの両方): management_db の entity_refs から E-018 を、config_store の entity_refs から E-007 / E-008 を除去。config_store の説明を env 起動コマンド方式へ更新
- product-workload-model.yaml: management_db 説明から「比較結果」を除去。config_store 説明を env 起動コマンド方式へ更新
- product-mapping-onprem.yaml: config_store の configuration_notes を env 起動コマンド方式へ更新
- product-impl-onprem.yaml: worker_start_update から comparison_result 登録文言を除去。connection_resolution を速報 worker=rapid-crosscheck.env / 確報 worker=final-crosscheck.env、別セグメント前提へ更新。config_store contents・検証規則を更新
- product-conformance-onprem.yaml: 設定配置 notes を env 起動コマンド方式へ更新
- ansible relay-gate-config/tasks/main.yml: 配置ループから 2 CSV を除去、final-crosscheck.env 配置と非空検査を追加

## 削除(設定ファイル集合から)

- `crosscheck-job-map.csv`(ジョブ ID ごとの比較定義。E-007 廃止)
- `target-catalog.csv`(対象カタログ。E-008 廃止)
- 管理 DB の「比較結果(comparison_result)」テーブルへの言及(E-018 廃止)

## 照合結果(work unit)

| work unit | 種別 | status | 理由の要点 |
|---|---|---|---|
| CR-dcd8234d-007#1 | causal | changed | 比較定義 CSV・対象カタログ・比較結果・成果物 URI 受け渡し・worker ファイル保存の廃止をインフラ設計へ追従。比較ツール起動コマンドを rapid / final の env へ移動 |
| CR-dcd8234d-001#1 | causal | not_impacted | validate-config.sh のティア間委譲撤廃・facade 単独検証(CTR-007)はアプリケーション内部構成の決定で、サーバ構成・配置ファイル・監視を変えない |
| CR-dcd8234d-002#1 | causal | not_impacted | 受け入れ基準の文言変更のみ。インフラ設計に影響しない |
| CR-dcd8234d-003#1 | causal | not_impacted | 名前空間の一般規則 CTR-007 は同一プロセス内のシェル関数規約で、インフラ構成に影響しない |

## MCL 再実行の有無

- 全面再実行は行わず、差分更新手順に沿って該当 6 ファイルのみを直した(mcl_rerun: skipped_targeted_update)。変更ファイルは本イベントディレクトリにスナップショットし、latest/ を同内容で更新した

## arch への追従と指摘

- 本 stage は feedback controller の指示により Phase4(arch フィードバック)を実行しない。arch root の latest・新規 arch event は作成しない
- 指摘: infra-event.yaml の historical `arch_feedback`(初期構築時)に `data_architecture.storage_mapping[E-008].confidence` の昇格記録が残る。arch は本 feedback で E-008 を削除したため、この過去記録は現行 arch と不整合になった(過去イベントの不変記録のため本 stage では変更しない)
