# credential_ref が参照名の形に合わず `/` も `BEGIN` も含まない値の扱いが未指定

- 起票: S4 Implementer(tier-facade attempt 6)
- 種別: 仕様の不足(spec-gap。秘密情報に関わる警告境界)。実装では触らない(S8 が変更要求候補として回収する)
- 対象: `facade/src/domain/job_map.sh:281`(`validate-config.sh --job-map` の credential_ref 列の検証)
- 出典: `docs/impl/latest/eff24f55/stages/attempt-5/S5_verify.tier-facade.findings.yaml` の F-010(major。前提 A-012 の spec_absent、category security)

## 仕様の記載

| 出典 | 記載 |
|---|---|
| `tier-facade.md#設定契約(slot ジョブマップ CSV)` 列検証表(行 46) | credential_ref は `^[A-Za-z0-9_.-]*$`(空可)。`/` を含む・`BEGIN` を含むは `warn: credential_ref looks like a secret or path line=N job_id=<v>` |
| `spec.md` 業務ルール「認証情報の非保存」(行 109) | 参照名 `^[A-Za-z0-9_.-]+$`。パス形式(`/` を含む)や `BEGIN` を含む値は warn(拒否はしない。**仮採用**) |
| `cli-command-contract.yaml#commands[validate-config.sh].stderr` | credential_ref の `error:` 行の定義は無い(warn のみ) |

## 実装で判明した事実

- 正規表現に合わず、`/` も `BEGIN` も含まない値(空白・記号・非 ASCII を含む値など)の扱いが、warn か error か、どの文言かのどれも決まっていない
- 実装は前提 A-012 として「同じ warn を出し、拒否しない」を選んでいる(値そのものは表示しない)。秘密情報の混入を見逃すか、参照名として使えない値を受理するかの境界なので、実装側で決めるべき事項ではない

## 提案

- 列検証表に「正規表現に合わない値」の行を追加し、warn(同じ文言)/ error(`error: credential_ref is invalid line=N job_id=... value=` 等。値は出さない)のどちらかを明記する
- 参照名として実行時に解決できない値を受理する意味が無ければ error(2)が妥当。運用で参照名の形式が実装依存(認証情報ストアに合わせて変わる)なら warn を維持し、その旨を契約に書く
