# 変更サマリ

- event_id: 20261105_091000_feedback_final_env_per_segment
- trigger_event: infra:20261104_101000_feedback_rapid_env_deploy_check(上流 latest は変更なし)
- created_at: 2026-11-05T09:10:00+09:00
- mode: 差分更新(infra-event-diff.yaml。MCL product-design の全量再実行なし: skipped_targeted_update)
- feedback request: 20261105_external_review_round2(direct work unit: CR-e3b7a915-002#1。causal work unit: CR-e3b7a915-002#1(確報クロスチェックの設定ファイルを、置き場ごとに必要な中身だけ配る)。packet: docs/pipeline/feedback-runs/20261105_external_review_round2/stage-packets/infrastructure.md)
- 正本: CLI 契約 config_files の final-crosscheck.env(readers / note / keys)。各読み手は自分のホストのファイルだけを読み、確報の比較ツール起動コマンドは worker 側のファイルの FINAL_COMPARE_COMMAND だけが持つ(2026-11-04 利用者決定)

## 追加

- 適用側が用意する 2 つの元ファイル(配置先はどちらも `/etc/relay-gate/final-crosscheck.env`)
  - `files/final-crosscheck-runner.env`: 実行ホストセグメント(`segment == 'execution'`)に配る
  - `files/final-crosscheck-worker.env`: DB セグメント(`segment == 'db'`)に配る

## 変更

構築手順は、同じ `files/final-crosscheck.env` を両方の置き場に配っていた。そのため確報 runner の置き場にも、runner が読まない比較コマンドが置かれていた。今回、配る中身を置き場ごとに分けた。

| 置き場 | 読み手 | 必須キー | 任意キー | 配らないキー |
|---|---|---|---|---|
| 実行ホストセグメント | 確報 runner(abort-final-crosscheck.sh / housekeep.sh も FINAL_DB_CONN_REF だけを使う) | FINAL_DB_CONN_REF | FINAL_POLL_INTERVAL_SEC(既定 60)/ FINAL_POLL_LIMIT_SEC(既定 28800) | FINAL_COMPARE_COMMAND |
| DB セグメント | 確報 worker、validate-config.sh --final-crosscheck | FINAL_DB_CONN_REF / FINAL_COMPARE_COMMAND | FINAL_LEASE_MINUTES / FINAL_WORKER_POLL_INTERVAL_SEC | - |

変更したファイル:

- infra/product/onprem/ansible/roles/relay-gate-config/tasks/main.yml
  - 配置タスクを segment ごとの 2 つに分けた
  - 配置タスク名とコメントを、置き場ごとに書き分けた
  - 起動時の検査を書き分けた: 実行ホストでは確報 runner が runner のキーを、DB セグメントでは確報 worker が worker のキーを検査する
  - validate-config.sh --final-crosscheck は DB セグメントで実行する、と書いた
- docs/mcl/product/output/product-impl-onprem.yaml
  - config_store の contents
  - final-crosscheck.env の検証規則の rule と description
  - management_db の connection_resolution(runner は実行ホストのファイル、worker は DB セグメントのファイル)
  - secret_handling(FINAL_DB_CONN_REF を追加)
- docs/mcl/product/output/product-mapping-onprem.yaml: config_store の configuration_notes
- docs/mcl/product/output/product-workload-model.yaml: config_store の説明
- docs/mcl/product/input/product-input.yaml(と直下のコピー): config_store の説明(translation は不変)
- docs/cloud-context/conformance/product/product-conformance-onprem.yaml: 設定の要件の notes(判定は不変)
- docs/cloud-context/generated-md/product/relay-gate-target-architecture.md: 設定ノード 2 つ(確報 runner 用 / 確報 worker 用)のキーを書き分けた。実行ホストの設定ノードは「共通」から「実行ホストセグメント」のサブグラフへ移した
- infra/product/onprem/ansible/inventory.ini.example: 確報の変数のコメントに 2 ファイルを追記
- infra/product/onprem/README.md: 前提に 2 ファイルとそれぞれのキー、validate-config.sh の実行場所を追記

## 削除

- 「両方の置き場に同じ内容を置く」の記述(main.yml のコメント、impl / mapping / conformance)
- 「確報 runner / 確報 worker が FINAL_DB_CONN_REF / FINAL_COMPARE_COMMAND を検査する」の記述(main.yml のコメント、impl の検証規則)
- 実行ホストセグメントへの FINAL_COMPARE_COMMAND の配布

## 変えなかったもの

- 変数 `relay_gate_final_crosscheck_enabled`(既定 false)の扱い
  - true なら両方の置き場に配置し、`test -f` で確認する
  - false なら両方の置き場から消す(state: absent)
- 配置時の検査はファイルの存在確認だけ。置き場ごとの中身の違いも、配置時には判定しない
- 認証情報らしい値は警告だけで、構築を止めない
- 全ホストが構築手順でデプロイされている前提。relay-gate の処理の中からは設定ファイルを配らない
- site.yml: DB セグメントには config ロールを割り当て済み。置き場の分け方はロールの中の segment 条件で決める
- product-observability.yaml / product-cost-hints.yaml: 確報の設定のキー構成を書いていない
- arch: 新しい知見は無い(Phase4 で arch を更新しない)

## 検証

- ansible-core 2.21.6 で検証した。手順: ロールを一時ディレクトリにコピーし、置き場を一時パスに置き換えて、segment × 変数の 4 通りを実行した
  - execution × true: 実行ホスト用の中身(FINAL_COMPARE_COMMAND なし)が配置された
  - db × true: worker 用の中身(FINAL_COMPARE_COMMAND あり)が配置された
  - execution × false / db × false: 前から置いてあったファイルが消えた
- `npx md-mermaid-lint`(ターゲットアーキテクチャ): 成功
- validateInfraEvent.js: PASS
