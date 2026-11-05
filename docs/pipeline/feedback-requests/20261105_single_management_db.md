---
schema_version: distillery.feedback-request/v1
feedback_id: 20261105_single_management_db
created_at: 2026-11-05T11:00:00+09:00
source: distillery-impl
uc_id: f4c8b261
---

# すべての接続先の参照名が同じ 1 つの管理 DB を指す前提を書く

## CR-f4c8b261-001: 管理 DB の接続先の参照名が同じ管理 DB に解決されることを、構築と仕様の前提として書く

- severity: spec-gap
- related_ids: [REQ-006, SPEC-006-02]
- related_files: [docs/infra/latest/infra/product/onprem/ansible/roles/relay-gate-config/tasks/main.yml, docs/infra/latest/infra/product/onprem/README.md, docs/infra/latest/docs/mcl/product/output/product-impl-onprem.yaml]

### 観測した事実

- 前回の変更(2026-11-05)で、final-crosscheck.env を実行ホスト用(files/final-crosscheck-runner.env)と DB セグメント用(files/final-crosscheck-worker.env)の別の元ファイルで配るようにした。構築の検査はファイルの存在確認だけ。
- 確報 runner は実行ホストの FINAL_DB_CONN_REF、確報 worker は DB セグメントの FINAL_DB_CONN_REF で管理 DB に接続する。方針資料では、runner が登録した確報比較依頼を同じキューから worker が取得する。
- 構築手順(README)・構築ロールのコメント・インフラ設計(product-impl-onprem.yaml の management_db.connection_resolution)・CLI 契約(config_files)のどこにも、2 つのホストの参照名が同じ管理 DB に解決されるという前提が書かれていない。
- 同じく RAPID_DB_CONN_REF(速報)、HANG_DB_CONN_REF(ハング検知)、HOUSEKEEP_DB_CONN_REF(ハウスキープ。専用 DB ロール)についても、管理 DB が 1 つで、すべての参照名がそこに解決されるという前提が書かれていない。

### 現在の仕様と問題

- 2 つのホストの参照名が別の DB に解決されると、設定の検査を通っても確報 worker が runner の依頼を取得できず、確報ジョブが完了しない。導入する側が確かめるべき条件が文書に無い。

### 変更してほしいこと

- すべての管理 DB の接続先の参照名(RAPID_DB_CONN_REF、実行ホストと DB セグメントの FINAL_DB_CONN_REF、HANG_DB_CONN_REF、HOUSEKEEP_DB_CONN_REF)が、同じ 1 つの管理 DB に解決されることを前提として書く。ハウスキープは専用 DB ロールで同じ管理 DB に接続する。参照名の文字列が同じことではなく、解決先(接続先の DB)が同じことを条件にする。
- 書く場所: 構築手順(README)、構築ロール relay-gate-config のコメント、インフラ設計(product-impl-onprem.yaml の management_db.connection_resolution と検証ルール)。関連する他の infra 成果物も揃える。
- 構築時の検査は今のまま(ファイルの存在確認だけ)とし、参照名の解決先が同じことは導入する側が確かめる旨を書く。relay-gate のコマンドに新しい検査は足さない。
- CLI 契約(config_files の各設定ファイルの説明、または共通の規約)にも同じ前提を書き、構築手順と食い違わないようにする。

### 完了条件

- 構築手順・インフラ設計・CLI 契約のすべてで、管理 DB が 1 つで、すべての接続先の参照名がそこに解決されることが前提として読み取れる。
