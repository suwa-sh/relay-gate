# 重複 job_id の `lines=` の列挙対象が、CLI 契約本文と tier BDD で矛盾する

- 起票: S4 Implementer(tier-facade attempt 6)
- 種別: 入力ソース間の矛盾(spec-conflict)。実装では触らない(S8 が変更要求候補として回収する)
- 対象: `facade/src/domain/job_map.sh` `validate_job_map_unique_job_ids`(`validate-config.sh --job-map`)
- 出典: `docs/impl/latest/eff24f55/stages/attempt-5/S5_verify.tier-facade.findings.yaml` の F-003(major)

## 仕様の記載

| 出典 | 記載 |
|---|---|
| `docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml#commands[validate-config.sh].stderr` | `error: duplicate job_id job_id=... lines=<n1,n2,...>`(2。**2 回目以降の行番号**をカンマ区切りで全部) |
| `tier-facade.md#設定契約(slot ジョブマップ CSV)` 列検証表(行 39) | 同じく「2 回目以降の行番号をカンマ区切りで全部」 |
| `tier-facade.md` ティア完了条件の BDD(行 186)/ `spec.md` BDD(行 244)/ `facade/features/define-slot-job-maps.feature` | 2 行目と 5 行目に JOB001 がある入力に対して `lines=2,5`(**初出行を含む**) |

## 実装で判明した事実

- 実装は BDD(feature は tier md の BDD と完全一致)に合わせ、その job_id が現れた行番号を出現順に全部並べる(2,3,4 行目の JOB001 は `lines=2,3,4`)
- 契約本文に合わせると tier BDD が fail し、BDD に合わせると契約本文と食い違う。両方を同時に満たせない

## 提案

- 仕様本文(CLI 契約 + tier md 列検証表)と BDD で「初出行を含めるか」を統一する
- 推奨: 初出行を含める(利用者が重複した全行を 1 行で把握できる。BDD と現行実装に一致し、実装変更が不要)。含めない側に統一する場合は BDD の期待値 `lines=2,5` を `lines=5` に変える変更要求を出す
