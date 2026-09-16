# config_confirmed: bootstrap P2(tier / 契約 / uc-map / モデル)

ユーザーがレビュー HTML(`tmp/reviews/s0-bootstrap-config-review.html`)を確認し、推奨案を承認した。verifier_model のみ推奨(gpt-5.6-sol)から `gpt-6-astra` に変更。

| 項目 | 確定値 |
|---|---|
| tiers | facade / rapid-crosscheck / final-crosscheck / ops(全 kind: cli、lang: bash) |
| datastore_owner | tier-ops |
| contracts | management-db(rdb-schema、7 テーブル、provider tier-ops)のみ |
| cli-command-contract.yaml | 契約外の共有仕様として S1 の shared_spec_refs で扱う(Q1=A) |
| asyncapi / openapi | 契約として宣言しない(Q2=A、openapi はスタブ) |
| cucumber-js | ルート package.json の devDependency(Q3=A) |
| implementer_model / verifier_model | null(セッション既定)/ gpt-6-astra |
| uc-map | 32 UC、uc-dependencies.md のトポロジカル順、英名・slug は提案どおり |
