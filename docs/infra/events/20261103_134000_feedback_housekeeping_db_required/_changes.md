# 変更サマリ

- event_id: 20261103_134000_feedback_housekeeping_db_required
- trigger_event: usdm:20261103_131000_feedback_housekeeping_db_required, rdra:20261103_131000_feedback_housekeeping_db_required, nfr:20261103_132000_feedback_housekeeping_db_required, arch:20261103_133000_feedback_housekeeping_db_required
- created_at: 2026-11-03T13:40:00Z
- mode: 差分更新(infra-event-diff.yaml。MCL product-design の全量再実行なし: skipped_targeted_update)
- feedback request: 20261103_housekeeping_db_required(direct work unit: なし。causal work unit: CR-9d2e6c41-001#1(管理 DB を使う機能が 1 つでもあれば、ハウスキープの管理 DB 接続参照名を必須にする)。packet: docs/pipeline/feedback-runs/20261103_housekeeping_db_required/stage-packets/infrastructure.md)

## 追加

- なし

## 変更

前回(2026-11-03 08:40 のイベント)で書いた「off では接続参照名を省略でき、そのとき管理 DB の行と確報比較依頼が削除されず増え続ける」趣旨の記述を、次の条件に揃えた。

| 項目 | 前回 | 今回 |
|---|---|---|
| 接続参照名が必須の設置 | RAPID_CROSSCHECK_MODE が off 以外 | off 以外、または確報クロスチェックを使う設置(確報クロスチェック worker の設定がある設置) |
| 省略・空にできる設置 | off の設置 | 管理 DB を一切使わない設置だけ |
| 必須なのに無い・空 | (off 以外はエラー) | 設定エラーで非 0 終了。削除待ちの置き場の中身も含めて何も削除しない(設定の検査を最初に行う) |
| 管理 DB の行が増え続ける状態 | off で接続しない間に起きる | 起きない(管理 DB を一切使わない設置では新たに行が増えない。off 以外の期間に作られた実行の行と成果物は残る) |
| off で確報クロスチェックを使う設置の確報比較依頼 | 削除されない | 保持日数で削除される |

- docs/mcl/product/input/product-input.yaml(と直下コピー): management_db の説明と config_store のハウスキープ設定(CR-9d2e6c41-001)
- product-workload-model.yaml: management_db / artifact_store の容量の頭打ちの例外、config_store のハウスキープ設定(CR-9d2e6c41-001)
- product-mapping-onprem.yaml: management_db / artifact_store / config_store の notes(CR-9d2e6c41-001)
- product-impl-onprem.yaml: housekeep_delete(設定の検査を最初に行い、設定エラーなら何も削除しない)、connection_resolution、artifact capacity、config contents、ハウスキープ設定の検証規則(CR-9d2e6c41-001)
- product-observability.yaml: alert-housekeep-failure に設定エラーも対象と明記し、warn が対象外になる条件を改めた(CR-9d2e6c41-001)
- product-cost-hints.yaml: storage_tiering の別に見込む分を、管理 DB を一切使わない設置で残る分だけに改めた(CR-9d2e6c41-001)
- product-conformance-onprem.yaml: 設定の要件の notes(判定は不変)(CR-9d2e6c41-001)
- relay-gate-target-architecture.md: housekeep → 管理 DB の辺のラベル(CR-9d2e6c41-001)
- infra/product/onprem/ansible/roles/relay-gate-config/tasks/main.yml: コメントのみ。検査タスクは変えない(CR-9d2e6c41-001)

## 削除

- なし

## 照合結果(causal work unit)

| work unit | status | 反映先 |
|---|---|---|
| CR-9d2e6c41-001#1 | changed | product-input / workload-model / mapping / impl / observability / cost-hints / conformance / 構成図 / config ロールのコメント |

## 変更しなかった箇所

- config ロールの検査タスク: 存在検査(空でもよい)のまま。配置時の静的検査でモードや確報設定を判定する仕組みは足さない(実際の検査は housekeep.sh の起動時に任せる。前回の判断を維持)
- IaC(relay-gate-postgresql ロール、inventory 例): housekeep_del ロールの作成とキー名・ファイル名の変数化は影響を受けない
- 判断記録(product-decision-001〜005): 選定の内容に影響しない
- arch: arch に戻す新しい知見は無い(本 stage は arch を更新しない)
