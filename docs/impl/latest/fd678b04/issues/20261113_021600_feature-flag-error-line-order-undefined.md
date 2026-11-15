# `--feature-flag` のキーごとの検査で error 行が 2 行以上出るときの、error 行どうしの順が仕様に無い

- uc_id: fd678b04(feature flag を設定する / configure-feature-flags)
- 起票 stage: S2 test-scaffold(2026-11-13 の再実行)
- 種別: 仕様の定めが無い点(実装の blocker ではない。テストでは順を固定していない)

## 仕様の記載

検査の段ごとに、順が決まっている範囲と決まっていない範囲は次のとおり。

| 段 | 行どうしの順 | 根拠 |
|---|---|---|
| バイト・改行の検査 | 決まっている(行番号の昇順。同じ行は NUL → UTF-8 → BOM → CR。hint は最後の CR の error 行の次) | `docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml` 1337 行目・1339 行目(`config_input_rules.byte_checks.order` / `hint`) |
| 行の構造の検査 | 決まっている(invalid line を行番号の昇順 → duplicate key を初出行の昇順) | 同 1353 行目(`config_input_rules.env_files` の (ii)) |
| キーごとの検査の中の、行の種類の順 | 決まっている(info 全件 → 未知キーの warn 全件 → error 行(と hint)→ runner の未応答の warn) | 同 1353 行目(「validate-config.sh の --verbose の info 行」の (c))、`tier-facade.md` 76 行目 |
| キーごとの検査の error 行どうしの順 | **決まっていない** | 下記 |

「決まっていない」と判断した根拠:

1. `cli-command-contract.yaml` 1353 行目の (c) は「error 行どうしの順は各検証種別の契約のとおり。--rapid-crosscheck は UC『クロスチェックのジョブマップと比較定義を定義する』の検証ルールの表の順」と書く。`--feature-flag` については、error 行に含める範囲(組合せ検証・`FINAL_` で始まるキー・対応ジョブマップ)だけを書き、順の出所を書いていない。
2. 「各検証種別の契約」にあたる `--feature-flag` の記載には、順の定めが無い。
   - `cli-command-contract.yaml` 1403〜1409 行目(`config_files` の feature-flag.env の `validation_rules`)と 1410〜1418 行目(`error_messages`): 規則と文言の列挙だけ。
   - 同 1245 行目(`validate-config.sh` の stderr の feature flag の項): 文言の列挙だけ。
   - `tier-facade.md` 30〜46 行目(キー表と組合せ検証): 「この表の順に出す」といった記載が無い。
   - `tier-facade.md` 88 行目(バリデーション): 「(3) 上表のキーごとの検査・組合せ検証・未知キーの warn」と範囲を書くだけ。
3. 判断記録 `docs/specs/latest/decisions/spec-decision-033.yaml` 75 行目も「error 行どうしの順は各検証種別の契約のとおり」と書くだけで、`--feature-flag` の順を決めていない。
4. BDD シナリオも順を求めていない。error 行が 2 行以上出る場面は「両方が出る」という書き方である(`spec.md` 214 行目・237 行目、`tier-facade.md` 176 行目)。`--verbose` の順のシナリオ(`tier-facade.md` 234〜243 行目)は error 行が 1 行だけの入力である。

一方、同じ 1353 行目の末尾は「この 4 検証種別の --verbose は、どの入力・状態の組み合わせでも標準エラーの行数と内容を 1 つに決める」と書く。`--feature-flag` で error 行が 2 行以上出る入力では、この文が成り立たない。

## 実装で判明した事実

- 現行実装(`facade/src/domain/feature_flag.sh` の `validate_feature_flag` と `facade/src/usecase/validate_feature_flag.sh`)の順は次のとおり。仕様の根拠は無い。
  1. BLUE_MODE → GREEN_MODE → RAPID_CROSSCHECK_MODE の必須・列挙
  2. foreground の個数
  3. BLUE_IMPL → BLUE_RUNNER → GREEN_IMPL → GREEN_RUNNER
  4. RAPID_CROSSCHECK_RUNNER → RAPID_CROSSCHECK_WORKER
  5. `FINAL_` で始まるキー(ファイルに出た順)
  6. 対応ジョブマップ(blue → green)
- S2 で追加・更新したテストは、キーごとの検査の error 行が 1 行だけになる入力を使うか、「含まれる」ことだけを確認している。error 行どうしの順はどのテストでも固定していない。

## 関連して気づいた点(順とは別。件数に関わる)

mode の値が列挙外のとき(例: `BLUE_MODE=parallel`)に、その slot の実装版・runner・ジョブマップの必須検査を行うかどうかは、仕様の文面からは「off でないとき必須」(`tier-facade.md` 35〜40 行目)としか読めない。現行実装は列挙外の値も「off でない」として必須検査を行う。`spec.md` 234〜237 行目のシナリオは「両方が出る」だけを求めるため、どちらでも通る。

## 提案

次のどちらかを仕様(CLI 契約の feature-flag.env の節)に書く。推奨は案 A。

| 案 | 内容 | 利点 | 欠点 |
|---|---|---|---|
| A(推奨) | 「キー表の順(BLUE_MODE → GREEN_MODE → RAPID_CROSSCHECK_MODE → BLUE_IMPL → GREEN_IMPL → BLUE_RUNNER → GREEN_RUNNER → RAPID_CROSSCHECK_RUNNER → RAPID_CROSSCHECK_WORKER)→ foreground の個数 → `FINAL_` で始まるキー(ファイルに出た順)→ 対応ジョブマップ(blue → green)」のように、表の順を正とする | `--rapid-crosscheck` の「検証ルールの表の順」と同じ考え方にそろう。「行数と内容を 1 つに決める」が成り立つ | 現行実装の順(slot ごとに実装版 → runner、foreground の個数が 2 番目)と違うため、実装の並べ替えが要る |
| B | 現行実装の順をそのまま仕様に書く | 実装の変更が要らない | 表の順と違う並びを別に覚える必要がある |

あわせて、mode が列挙外のときに必須検査を行うかどうかも 1 文で決める。
