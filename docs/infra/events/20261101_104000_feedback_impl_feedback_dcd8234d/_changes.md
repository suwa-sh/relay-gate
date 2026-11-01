# 変更サマリ

- event_id: 20261101_104000_feedback_impl_feedback_dcd8234d
- trigger_event: usdm:20261101_101000_feedback_impl_feedback_dcd8234d, arch:20261101_103000_feedback_impl_feedback_dcd8234d(RDRA・NFR は no-change)
- created_at: 2026-11-01T10:40:00Z
- mode: 差分更新(infra-event-diff.yaml。MCL は全面再実行せず該当箇所のみ差分更新 = skipped_targeted_update)
- feedback request: 20261027_091000_impl_feedback_dcd8234d(direct work unit: なし。causal work unit: CR-dcd8234d-009#1。packet: docs/pipeline/feedback-runs/20261027_091000_impl_feedback_dcd8234d/stage-packets/infrastructure.md)

本イベントは、速報の起動コマンドに対する設定検証(validate-config.sh)の検証項目を 2 点から 3 点にした上流の変更を、インフラ設計の説明文へ追従させる。インフラ設計は起動コマンドの内容検証を validate-config.sh の所有と書いており、その括弧書きに検証項目を 2 点で列挙していたため、3 点目を加えた。

## 追加

- なし

## 変更

| ファイル | 変更内容 |
|---|---|
| docs/mcl/product/output/product-impl-onprem.yaml | rapid-crosscheck.env 検証規則の説明で、validate-config.sh が所有する内容検証を 3 点(コマンド部分が絶対パスで実行可能 / {job_id} を含む / {params} を使うなら引数 1 つ全体がちょうど {params})に改めた |
| infra/product/onprem/ansible/roles/relay-gate-config/tasks/main.yml | config ロールのコメントで、validate-config.sh が所有する内容検証に速報の {params} の位置を追記した |
| infra-event.yaml | 上記 2 成果物の description に 20261101 差分の注記を追記。ヘッダー(event_id / trigger_event / feedback_request / arch_event_ref)を今回のイベントへ更新 |

## 削除

- なし

## 変えていないもの

- サーバ構成・配置先・ネットワークセグメント・ストレージ・監視・バックアップ
- 配置する設定ファイルの集合とキー構成の検査(ansible のタスク、impl の規則本体)
- final-crosscheck.env の検証規則(確報の起動コマンドは {job_id} / {params} の検証対象外のまま)
- MCL 入力(product-input.yaml)とその他の MCL 出力

## work unit の扱い

| work unit | 種別 | status | 理由 |
|---|---|---|---|
| CR-dcd8234d-009#1 | causal | changed | インフラ設計に検証項目を 2 点で列挙した記述が 2 か所あり、上流の 3 点へそろえた |

## arch フィードバック

- なし(controller の指示により Phase4 を実行しない。infra から arch へ戻す新しい知見も無い)
