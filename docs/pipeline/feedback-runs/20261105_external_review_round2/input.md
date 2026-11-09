---
schema_version: distillery.feedback-request/v1
feedback_id: 20261105_external_review_round2
created_at: 2026-11-05T09:00:00+09:00
source: distillery-impl
uc_id: e3b7a915
---

# 外部レビュー 2 回目の指摘 2 件を直す

## CR-e3b7a915-001: ハング検知の未知キーの警告を、走査を始めるときだけ出す

- severity: spec-gap
- related_ids: [REQ-008, SPEC-008-07]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/_cross-cutting/ux-ui/ui-design.md]

### 観測した事実

- CLI 契約の hang-detector.sh は、走査前の検査の (d)(hang-detector.env のキー)を通ったときに `warn: unknown key key=<KEY> path: ...` を出して継続すると書いている。
- 同じ契約は、RAPID_CROSSCHECK_MODE が off 以外で管理 DB に接続・SELECT できない回は「error 1 行だけを出し、warn / info / alert 行を出さない」とし、off で印の置き場を読めない回も「error 1 行だけ」としている。
- hang-detector.env に未知キーがあり、同じ回に管理 DB に接続できない(または印の置き場を読めない)とき、2 つの規則がぶつかり、標準エラーの行数と内容が 1 つに決まらない。

### 現在の仕様と問題

- 同じ入力・状態に対して、warn 行を出すか出さないかが仕様から決まらない。実装と BDD の期待値が割れる。

### 変更してほしいこと

- 未知キーの warn は、走査を始めるときに出す。off 以外では管理 DB への接続と SELECT が通ったあと、off では印の置き場の検査が通ったあと(facade/ を列挙する前)に出す。
- 管理 DB に接続・SELECT できない回と、印の置き場を読めない回は、今のとおり error 1 行だけを出し、未知キーの warn も出さない。
- 走査前の検査の順の記述、DB 障害の回・印の置き場を読めない回の記述、横断 stderr 規約(ui-design.md)、関連する UC の spec / BDD を同じ規則に揃える。実装との差分があれば判断記録に書く。

### 完了条件

- 未知キーと管理 DB 障害(または印の置き場の読み取り失敗)が同じ回に重なったとき、標準エラーが error 1 行だけに決まる。
- 走査を始める回では、未知キーの warn が出る位置(走査の前、どの alert 行よりも前)が 1 つに決まる。

## CR-e3b7a915-002: 確報クロスチェックの設定ファイルを、置き場ごとに必要な中身だけ配る

- severity: spec-gap
- related_ids: [REQ-006, SPEC-006-02]
- related_files: [docs/infra/latest/infra/product/onprem/ansible/roles/relay-gate-config/tasks/main.yml, docs/infra/latest/docs/mcl/product/output/product-impl-onprem.yaml]

### 観測した事実

- インフラの Ansible ロール relay-gate-config は、同じ `files/final-crosscheck.env` を実行ホストセグメント(確報 runner)と DB セグメント(確報 worker)の両方に配り、コメントに「両方の置き場に同じ内容を置く」「必須は FINAL_DB_CONN_REF と FINAL_COMPARE_COMMAND」と書いている。
- product-impl-onprem.yaml の検証ルールも、必須キー(FINAL_DB_CONN_REF / FINAL_COMPARE_COMMAND)を確報 runner / 確報 worker が検査すると書いている。
- CLI 契約(config_files の final-crosscheck.env)は、runner の必須は FINAL_DB_CONN_REF だけで FINAL_COMPARE_COMMAND を読まず、比較ツール起動コマンドは worker 側のファイルの FINAL_COMPARE_COMMAND だけが持つとしている(2026-11-04 利用者決定)。

### 現在の仕様と問題

- 構築手順が、使わない比較コマンドを runner の置き場にも配り、runner でも必須だと説明している。仕様の「比較コマンドは worker 側だけ」と食い違う。

### 変更してほしいこと

- 配る中身を置き場ごとに分ける。実行ホストセグメント(runner)には FINAL_DB_CONN_REF と runner の任意キー(FINAL_POLL_INTERVAL_SEC / FINAL_POLL_LIMIT_SEC)だけ、DB セグメント(worker)には FINAL_DB_CONN_REF・FINAL_COMPARE_COMMAND と worker の任意キー(FINAL_LEASE_MINUTES / FINAL_WORKER_POLL_INTERVAL_SEC)を置く。置き場のファイル名は両方とも `/etc/relay-gate/final-crosscheck.env` のまま。
- 配置タスク名・コメント・product-impl-onprem.yaml の検証ルールの必須キーの説明を、置き場ごとに書き分ける。確報を使わない設置で両方から消す扱いと、検査がファイルの存在確認だけである扱いは変えない。
- CLI 契約側の記述が構築手順と食い違わないか確認し、必要なら揃える。

### 完了条件

- runner の置き場に FINAL_COMPARE_COMMAND を配らず、構築手順と CLI 契約のあいだで、どの置き場にどのキーがあり、どの読み手が何を必須にするかが一致する。
