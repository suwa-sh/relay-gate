# Verifier が記録する assumptions_sha256 の算出基準が食い違い、形式だけの差し戻しが 2 回起きた

## 何が起きたか

- 独立検証(Verifier)は、実装者の前提ファイル(`S4_tier-impl.*.assumptions.yaml`)のハッシュを findings に記録する。
- attempt 5 再実行と attempt 6 の 2 回とも、Verifier が記録した `assumptions_sha256` がオーケストレータの期待値と一致せず、内容を変えない「形式だけの差し戻し」が発生した。

| 回 | Verifier の算出 | 期待値 | 結果 |
|---|---|---|---|
| attempt 5 再実行 | 誤った値 | `validateAssumptions.js record` の canonical hash | 差し戻して修正(内容の変更なし) |
| attempt 6 | ファイルの生バイトの SHA-256(`shasum -a 256`)。findings に `assumptions_hash_basis: raw file bytes; user instruction overrides canonical record hash` と明記 | 同上 | 差し戻して修正(内容の変更なし) |

- attempt 6 では、Verifier が「利用者の指示が canonical hash より優先する」と解釈し、生バイトのハッシュを意図的に記録した。
- 検証の内容(verdict / findings)は正しく、差し戻しはハッシュ 1 行の修正だけだった。

## 原因

- 「前提ファイルのハッシュ」に 2 つの算出基準がある。
  - canonical record hash: `validateAssumptions.js record` が、YAML を正規化してから計算する。S9 の承認証跡(`assumption_evidence_sha256`)はこれを使う。
  - 生バイトの SHA-256: ファイルをそのまま `shasum` した値。
- Verifier への指示に、どちらの基準を使うかが明示されていなかった。Verifier は指示文中の「ハッシュ」を生バイトと解釈した。
- attempt 6 では、Verifier が前回の差し戻しを「利用者の指示」と受け取り、同じ解釈を維持した。

## 回避方法

- Verifier への指示に、ハッシュの算出コマンドをそのまま書く(例: `node validateAssumptions.js record <path>` の出力を転記する)。「SHA-256」とだけ書かない。
- Verifier は、findings の `assumptions_sha256` を書く前に、同じコマンドで自分の値を再計算して一致を確認する。
- 差し戻しの理由を「形式の修正」と明記し、次の attempt の Verifier 指示にも同じ算出コマンドを繰り返す(Verifier は attempt をまたいで記憶しない)。

## 次回の対応

- 次の UC の S5 の Verifier 指示に、ハッシュの算出コマンドを 1 行で書く。
- 差し戻しが 2 回続いたら、指示文の側を直す(Verifier の再実行を繰り返さない)。
