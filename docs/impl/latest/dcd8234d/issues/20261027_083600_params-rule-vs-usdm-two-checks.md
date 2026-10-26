# 起動コマンドの検証項目数が USDM(2 点)と spec(3 点)で異なる

- uc_id: dcd8234d
- 起票 stage: S2 test-scaffold
- 重大度: spec-gap(blocker ではない。spec.md / tier-facade.md を正として進める)

## 仕様の記載

- USDM SPEC-004-04 の本文(`features/atdd/SPEC-004-04.feature` の Feature 説明に転写済み): 「設定検証が起動コマンドに対して行う検証は次の 2 点だけとする: (1) コマンド部分が絶対パスで存在し実行可能、(2) 速報の起動コマンドに {job_id} が含まれる。検証はコマンド部分に対して行い、引数部分の内容は検査しない」
- ATDD `@atdd_SPEC-004-04-10`: 「起動コマンドの引数部分に任意の文字列 → 引数部分を理由とする error 行は出ず、終了コードは引数部分の内容に影響されない」
- spec.md / tier-facade.md(argv 規則の還流後): 検証は 3 点。3 点目は「`{params}` を使うなら引数 1 つ全体のときだけ」(違反文言 `error: placeholder {params} must be a whole argument ...`)
- `_api-summary.yaml` の stderr / exit_codes には `{params}` の違反文言・終了コード 2 の理由が載っていない

## 実装で判明した事実

- 引数部分が `--args={params}` のような文字列のとき、spec のルール 5 では終了コード 2 になる。USDM の「2 点だけ」と ATDD -10 の「引数部分の内容に影響されない」を字面どおりに読むと終了コード 0 になり、両立しない
- S2 では spec.md / tier-facade.md を正として tier BDD・UC BDD・単体テストを書いた。ATDD -10 の step は skeleton のみで、S7 で fixture を作る際は引数部分に `{params}` を含めない(両仕様が一致する範囲で判定する)

## 提案

- USDM SPEC-004-04 の本文と acceptance_criteria に `{params}` の位置規則(3 点目)を加え、-10 の Given を「`{params}` 以外の任意の文字列」に絞る
- `_api-summary.yaml` の stderr / exit_codes に `{params}` の違反文言を加える(tier-facade.md と揃える)
