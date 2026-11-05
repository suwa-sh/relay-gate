# 変更サマリ

- event_id: 20261105_111000_feedback_single_management_db
- trigger_event: infra:20261105_091000_feedback_final_env_per_segment(上流 latest は変更なし)
- created_at: 2026-11-05T11:10:00+09:00
- mode: 差分更新(infra-event-diff.yaml。MCL product-design の全量再実行なし: skipped_targeted_update)
- feedback request: 20261105_single_management_db(direct work unit: CR-f4c8b261-001#1。causal work unit: CR-f4c8b261-001#1(管理 DB の接続先の参照名が同じ管理 DB に解決されることを、構築と仕様の前提として書く)。packet: docs/pipeline/feedback-runs/20261105_single_management_db/stage-packets/infrastructure.md)
- 利用者が承認した直し方(2026-11-05)

## 書き足した前提

管理 DB は 1 つ。次の参照名はすべて、同じ 1 つの管理 DB に解決される。

| 参照名 | 置き場 | 読み手 |
|---|---|---|
| RAPID_DB_CONN_REF | rapid-crosscheck.env(実行ホスト) | facade / slot runner / 速報クロスチェック runner / 速報 worker |
| FINAL_DB_CONN_REF | final-crosscheck.env(実行ホスト) | 確報 runner / abort-final-crosscheck.sh / housekeep.sh |
| FINAL_DB_CONN_REF | final-crosscheck.env(DB セグメント) | 確報 worker |
| HANG_DB_CONN_REF | hang-detector.env(実行ホスト) | hang-detector |
| HOUSEKEEP_DB_CONN_REF | ハウスキープ設定(実行ホスト) | housekeep(専用 DB ロール housekeep_del) |

- 条件: 参照名の文字列が同じことではなく、解決先(接続先の DB)が同じこと
- 理由: 確報 runner が登録した依頼を、確報 worker が同じキューから取得するため。別の DB に解決されると、設定の検査を通っても確報ジョブが完了しない。速報・ハング検知・ハウスキープも同じ管理 DB の表を読み書きする
- 確かめる人: 導入する側。構築時の検査は設定ファイルの存在確認だけで、解決先は判定しない

## 追加

- 上の前提の記述(README の前提、config ロールの冒頭と確報設定のコメント、impl / mapping / workload / MCL 入力 / 適合性 notes / ターゲットアーキテクチャ図)

## 変更

- infra/product/onprem/README.md: 前提に、単一の管理 DB と 5 つの参照名、条件、理由、確かめる人を追記
- infra/product/onprem/ansible/roles/relay-gate-config/tasks/main.yml: コメントだけを変更(タスクは不変)
  - 冒頭: 単一の管理 DB の前提と、このロールは解決先を判定しないこと
  - 確報クロスチェック worker 設定: 2 つの置き場の FINAL_DB_CONN_REF が同じ管理 DB に解決されなければならない理由
- docs/mcl/product/output/product-impl-onprem.yaml
  - management_db の connection_resolution: 冒頭に前提と理由を書き、ハウスキープの参照名を HOUSEKEEP_DB_CONN_REF と明記
  - config_store の final-crosscheck.env の存在の検証規則の description: 解決先は存在確認では判定せず、導入する側が確かめることを追記(新しい検証規則は足さない)
- docs/mcl/product/output/product-mapping-onprem.yaml: management_db の configuration_notes に、確報 runner / 確報 worker の FINAL_DB_CONN_REF と HOUSEKEEP_DB_CONN_REF を加え、前提を追記
- docs/mcl/product/output/product-workload-model.yaml: management_db の説明に前提を追記
- docs/mcl/product/input/product-input.yaml(と直下のコピー): management_db の説明に前提を追記(translation は不変)
- docs/cloud-context/conformance/product/product-conformance-onprem.yaml: REQ-DB-005 / REQ-DB-007 の notes(判定は不変)
- docs/cloud-context/generated-md/product/relay-gate-target-architecture.md: 管理 DB のノードに、すべての接続参照名の解決先であることを追記

### ハウスキープの仮置き表現を CLI 契約の名前に揃えた(controller の追加指示)

CLI 契約(config_files の housekeep.env、shared_rules の artifact_root_entries)で確定している名前に揃えた。構築の変数名とタスクは変えていない。

| 対象 | 揃えた名前 |
|---|---|
| ハウスキープ設定のファイル | housekeep.env(配置先 /etc/relay-gate/housekeep.env) |
| ハウスキープ設定のキー | HOUSEKEEP_RETENTION_DAYS(既定 90)/ HOUSEKEEP_DB_CONN_REF(専用 DB ロール housekeep_del) |
| 削除待ちの置き場 | 成果物ルート直下の housekeep-pending/(この構成では /var/lib/relay-gate/housekeep-pending) |
| 通知済みの印 | 成果物ルート直下の hang-detector-notified/<run_id>.<role> |

変更したファイル:

- infra/product/onprem/ansible/roles/relay-gate-config/tasks/main.yml: ハウスキープ設定のコメント。変数 relay_gate_housekeep_config_file の値は housekeep.env にする
- infra/product/onprem/ansible/roles/relay-gate-runtime/tasks/main.yml: 削除待ちの置き場のコメント
- infra/product/onprem/ansible/inventory.ini.example: `relay_gate_housekeep_config_file=housekeep.env`、`relay_gate_housekeep_staging_dir=/var/lib/relay-gate/housekeep-pending`(例はコメントのまま)
- product-impl-onprem.yaml: config_store の contents、artifact_store の notified_marks / housekeep_staging
- product-mapping-onprem.yaml: config_store と artifact_store の configuration_notes
- product-workload-model.yaml: config_store の説明、REQ-ART-004 の rationale
- product-input.yaml(2 か所。同一内容): artifact_store と config_store の説明
- product-conformance-onprem.yaml: REQ-ART-004 の notes(判定は不変)
- README.md / ターゲットアーキテクチャ図: ハウスキープ設定を housekeep.env と書いた

## 削除

- 「ハウスキープ設定の接続参照名のキー名は仕様で確定」の記述(impl の connection_resolution、mapping の configuration_notes、適合性の REQ-DB-007 notes)。キー名 HOUSEKEEP_DB_CONN_REF に置き換えた
- 現行の記述に残っていた「仕様で確定」の仮置き表現(ハウスキープ設定のファイル名・キー名、削除待ちの置き場・通知済みの印の場所)。上の表の名前に置き換えた

## 変えなかったもの

- 構築時の検査: 設定ファイルの存在確認だけ。参照名の解決先を確かめる検査タスクは足さない
- site.yml: ロールの割り当ては不変
- 構築の変数名(relay_gate_housekeep_config_file / relay_gate_housekeep_staging_dir)とタスク
- product-observability.yaml / product-cost-hints.yaml: 接続参照名の解決先を書いていない
- arch: 新しい知見は無い(Phase4 で arch を更新しない)

## 検証

- `npx md-mermaid-lint`(ターゲットアーキテクチャ): 成功
- 変更した YAML の構文読み込み: 成功
- validateInfraEvent.js: PASS
