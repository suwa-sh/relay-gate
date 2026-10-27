---
schema_version: distillery.feedback-request/v1
feedback_id: 20261027_091000_impl_feedback_dcd8234d
created_at: 2026-10-27T09:10:00+09:00
source: distillery-impl
uc_id: dcd8234d
---

# 実装からの変更要求

## CR-dcd8234d-009: 速報の起動コマンドの検証項目が、要求(2 点)と仕様(3 点)で食い違っている

- severity: spec-gap
- related_ids: [SPEC-004-04, SPEC-004-04-10, REQ-004]
- related_files: [docs/usdm/latest/requirements.yaml, features/atdd/SPEC-004-04.feature, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-facade.md, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/_api-summary.yaml, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

- 要求 SPEC-004-04 の本文は「設定検証(validate-config.sh)が起動コマンドに対して行う検証は次の 2 点だけとする: (1) コマンド部分(先頭の語)が絶対パスで、存在し、実行可能であること、(2) 速報の起動コマンドに {job_id} が含まれること。検証はコマンド部分に対して行い、引数部分の内容は検査しない」と書く。
- 同じ要求の受け入れ基準(-10)は「Given 起動コマンドの引数部分に任意の文字列(存在しないパスや未知の語を含む) When validate-config.sh で検証する Then 引数部分を理由とする error 行は出ず、終了コードは引数部分の内容に影響されない」と書く。
- 一方、起動コマンドを引数ごとに分けて起動する決まり(2026-10-27 に反映)の後の仕様は、検証を 3 点にしている。CLI 契約 `validate-config.sh` の違反文言と、この UC の spec.md / tier-facade.md の検証ルール 5 は、`{params}` が引数 1 つ全体でない位置に現れると `error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=...`(終了コード 2)を出すと定める。
- 実装は spec.md / tier-facade.md / CLI 契約に従った。引数部分が `--args={params}` を含む設定では終了コード 2 になる。
- 受け入れ基準 -10 の受け入れテストは、引数部分に `{params}` を含めない値だけで判定して通過させた。字面どおりに `--args={params}` を引数部分に置くと、要求は「終了コード 0」、仕様は「終了コード 2」を求めることになり、両方を満たすテストは書けない。
- この UC の API 要約(`_api-summary.yaml`)の `validate-config.sh --rapid-crosscheck` の stderr と終了コード 2 の理由には、`{params}` の位置違反が載っていない。CLI 契約と tier-facade.md には載っている。

### 現在の仕様と問題

- 要求は「2 点だけ」「引数部分の内容は検査しない」と言い切っている。仕様は `{params}` の位置という、引数部分の内容に依存する 3 点目を加えている。要求と仕様のどちらを正とするかが読み手によって変わる。
- 受け入れ基準 -10 の Given「任意の文字列」には `{params}` を一部に含む引数も入るため、仕様どおりの実装では満たせない入力がある。
- API 要約だけが 3 点目を持たないため、API 要約を読んで実装やテストを作ると `{params}` の位置違反を見落とす。

### 変更してほしいこと

- 要求 SPEC-004-04 の本文に、3 点目として「速報の起動コマンドで `{params}` を使うなら、引数 1 つ全体がちょうど `{params}` であること」を加える。あわせて「引数部分の内容は検査しない」を「`{job_id}` の有無と `{params}` の位置のほかは、引数部分の内容を検査しない」に改める。
- 3 点目の受け入れ基準を 1 件追加する(例: Given 速報の起動コマンドの引数の一部に `{params}` を含む(`--args={params}`) When validate-config.sh で検証する Then 非 0 の終了コードで終了し、stderr に `{params}` が引数全体でない旨の error 行がキー名と値つきで 1 行出る)。
- 受け入れ基準 -10 の Given を「`{params}` を引数の一部に含まない任意の文字列」に絞る。
- この UC の API 要約の stderr と終了コード 2 の理由に、`{params}` の位置違反(`error: placeholder {params} must be a whole argument key=RAPID_COMPARE_COMMAND value=...`)を加え、CLI 契約・tier-facade.md と揃える。

### 完了条件

- 要求 SPEC-004-04、受け入れ基準、CLI 契約、この UC の spec.md / tier-facade.md / API 要約が、速報の起動コマンドの検証を同じ 3 点として記述している。
- 受け入れ基準 -10 の Given に、仕様では違反になる入力が含まれない。
- `{params}` の位置違反を判定する受け入れ基準が 1 件あり、受け入れテストで fixture を絞り込まずに字面どおり判定できる。
