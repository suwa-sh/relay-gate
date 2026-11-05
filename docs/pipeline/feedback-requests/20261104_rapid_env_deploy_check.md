---
schema_version: distillery.feedback-request/v1
feedback_id: 20261104_rapid_env_deploy_check
created_at: 2026-11-04T10:00:00+09:00
source: distillery-impl
uc_id: d8a2f4b6
---

# 構築手順の速報クロスチェック設定の検査を CLI 契約に合わせる

## CR-d8a2f4b6-001: 速報クロスチェック設定の配置時検査をファイルの存在確認だけにする

- severity: spec-gap
- related_ids: [REQ-004, SPEC-004-04]
- related_files: [docs/infra/latest/infra/product/onprem/ansible/roles/relay-gate-config/tasks/main.yml]

### 観測した事実

- インフラの Ansible ロール relay-gate-config は、rapid-crosscheck.env に `RAPID_DB_CONN_REF=` の行があり、かつ `RAPID_LEASE_SEC=<正の整数>` と `RAPID_POLL_INTERVAL_SEC=<正の整数>` の行があることを grep で必須にしている。product-impl-onprem.yaml の検証ルールも同じ前提。
- CLI 契約では RAPID_LEASE_SEC(既定 600)と RAPID_POLL_INTERVAL_SEC(既定 30)は任意キーで、行の解釈(前後の空白、字下げしたコメント、引用符)も grep の行頭一致と違う。中身の検査は validate-config.sh --rapid-crosscheck と各コマンドの起動時の読み込みが所有する。
- 前回の変更(2026-11-04)で、同じロールのハング検知設定の検査を存在確認だけに直した際に、同じ種類の食い違いとして見つかった。

### 現在の仕様と問題

- 任意の 2 キーを省いた正当な速報クロスチェック設定や、キーの前後に空白がある正当な設定で、構築が失敗する。

### 変更してほしいこと

- 配置時の検査は rapid-crosscheck.env があることの確認だけにする(ハング検知設定・ハウスキープ設定と同じ考え方)。中身の検査は CLI 契約(validate-config.sh --rapid-crosscheck と起動時の読み込み)に任せる旨をコメントに書く。配置タスクのタスク名・product-impl-onprem.yaml の検証ルールなど、関連する infra 記述も揃える。
- 確報クロスチェック worker 設定の検査(`test -s`)など、同じロールの他の設定ファイルの検査も CLI 契約と照らし、正当な設定で構築が失敗するものがあれば同じ考え方で揃える。

### 完了条件

- CLI 契約が許すすべての rapid-crosscheck.env(と同じロールの他の設定ファイル)で、構築の検査が失敗しない。
