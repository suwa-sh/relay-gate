---
schema_version: distillery.feedback-request/v1
feedback_id: 20260917_081430_impl_feedback_fd678b04
created_at: 2026-09-17T08:14:30+09:00
source: distillery-impl
uc_id: fd678b04
---

# 実装からの変更要求

## CR-fd678b04-001: feature flag で拒否する「確報の制御キー」の範囲を一意に定める

- severity: spec-gap
- related_ids: [REQ-001, SPEC-001-01]
- related_files: [docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/spec.md, docs/specs/latest/適用構成業務/適用構成定義フロー/feature flag を設定する/tier-facade.md, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

`validate-config.sh --feature-flag` は、feature-flag.env に確報クロスチェックの制御キーがあれば `error: final crosscheck key is not allowed key=<KEY>` を出して終了コード 2 で拒否する。この「確報の制御キー」の範囲が、同じ UC の仕様の中で 3 通りに書かれている。

- spec.md の処理フロー(シーケンス図の分岐)は「`FINAL_*` キーがある」と書く
- spec.md の分岐条件一覧は「`FINAL_CROSSCHECK_MODE` 等の確報制御キー」と書く(接頭辞を明示しない)
- tier-facade.md の設定契約(組合せ検証)は「`FINAL_CROSSCHECK_*` キー」と書く
- CLI 契約(cli-command-contract.yaml の config_files.feature-flag.env)は「確報の制御キーは置かない」とだけ書き、キー名・接頭辞のどちらも定めない

実装は spec.md の処理フローに従い、接頭辞 `FINAL_` で判定している。独立した検証で、有効な設定に `FINAL_RELEASE_LABEL=x` を 1 行加えて実行したところ、終了コード 2・stdout 0 行・`error: final crosscheck key is not allowed key=FINAL_RELEASE_LABEL` となった。tier-facade.md の記述(`FINAL_CROSSCHECK_*` 以外の未知キーは warn で継続)に従えば、同じ入力は終了コード 0・`warn: unknown key key=FINAL_RELEASE_LABEL` になる。同じ入力に対する期待結果を仕様から一意に決められず、独立した検証はこれを major の指摘として記録した。

BDD Scenario「確報の制御キーは拒否される(SPEC-001-01)」の入力は `FINAL_CROSSCHECK_MODE=background` であり、どちらの解釈でも通過する。境界(`FINAL_` で始まるが `FINAL_CROSSCHECK_` で始まらないキー)を判定できる Scenario は無い。

### 現在の仕様と問題

- 要件(REQ-001 / SPEC-001-01)の受け入れ条件は「確報クロスチェックの制御設定は feature flag に含まれない」であり、方針資料も「確報クロスチェックは runner をジョブスケジューラから直接起動するため facade の設定には含めない」と述べる。どのキー名を「確報の制御設定」とみなすかは要件・方針資料のどちらにも無い
- 同じ UC の spec.md 内で処理フロー(`FINAL_*`)と分岐条件一覧(`FINAL_CROSSCHECK_MODE` 等)の表記が異なり、tier-facade.md(`FINAL_CROSSCHECK_*`)とも異なる。CLI 契約は文言の正本だが、キーの範囲を定めていないため、契約からも決められない
- `FINAL_` を接頭辞にすると、確報クロスチェック設定(final-crosscheck.env)のキー(FINAL_DB_CONN_REF / FINAL_POLL_INTERVAL_SEC / FINAL_POLL_LIMIT_SEC / FINAL_LEASE_MINUTES / FINAL_WORKER_POLL_INTERVAL_SEC)を feature-flag.env に誤って置いた場合も拒否できる。`FINAL_CROSSCHECK_` を接頭辞にすると、これらは未知キーの warn で通過する。どちらを意図しているかで利用者に見える挙動(拒否か警告か)が変わる
- 実装は現在 `FINAL_` を採用しているが、これは 3 通りの記述のうち 1 つを実装者が選んだ結果であり、仕様の裏付けが無い

### 変更してほしいこと

- 「確報の制御キー」として feature-flag.env で拒否するキーの範囲を 1 つに定める。判定方法は接頭辞(例: `FINAL_` で始まるすべてのキー)か、キー名の列挙かのどちらかを明示する
- 定めた範囲を CLI 契約(config_files.feature-flag.env の validation_rules)に書き、spec.md の処理フロー・分岐条件一覧と tier-facade.md の設定契約はその範囲と同じ表記にそろえる
- 範囲の境界を判定できる BDD Scenario を 1 つ追加する。例: 接頭辞 `FINAL_` を採用するなら「`FINAL_DB_CONN_REF` を feature-flag.env に置くと拒否される」、`FINAL_CROSSCHECK_` を採用するなら「`FINAL_DB_CONN_REF` は未知キーの warn で通過する」
- 現行実装の値としては、確報クロスチェック設定のキーの誤配置も拒否できる `FINAL_` 接頭辞(spec.md の処理フローの表記)を希望する

### 完了条件

- `FINAL_` で始まり `FINAL_CROSSCHECK_` で始まらないキー(例: `FINAL_DB_CONN_REF`)を feature-flag.env に置いたときの終了コードと stderr が、CLI 契約・spec.md・tier-facade.md のどれを読んでも同じに決まる
- その境界を判定する BDD Scenario が UC「feature flag を設定する」の完了条件にある
- 3 つの仕様ファイルに、確報の制御キーの範囲について互いに異なる表記が残っていない
