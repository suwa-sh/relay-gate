# CLAUDE.md / dev-rules への改善提案(dcd8234d、還流 run 2〜9 後の再実装)

既存の CLAUDE.md と dev-rules は変更していない。採否は人が判断する。前回(`20261027_091000_proposal-context.md`)の提案は繰り返さない。

## 提案 1: テストの期待値づくりで BSD/GNU 差のあるコマンドを使わない

- 対象: `docs/dev-rules/test-strategy.md`(または coding-rules のテストの節)
- 理由: macOS の `seq -s` が末尾にも区切りを付け、Linux では通る期待値が macOS で一致しなかった(learnings `20261110_080548_bsd-seq-trailing-separator.md`)。既存の注意は「macOS で通るが Linux CI で落ちる」向きだけで、逆向きもある
- 案: 「テストの期待値は bash の組み込みだけで組み立てる。`seq -s` / `sed -i` / `date` / `stat` などの BSD/GNU 差のあるコマンドを期待値づくりに使わない」を加える

## 提案 2: 還流の後は、同じ共通規則を使う完了済み UC の再実行要否を確かめる

- 対象: relay-gate の CLAUDE.md「開発プロセス」の 3. 実装フェーズ
- 理由: env の共通規則の還流後、完了済み UC「feature flag を設定する」の実装と tier BDD(仕様 17 / 実装 9)が未追従のまま completed だった(learnings `20261110_080548_completed-uc-drift-after-reflux.md`)
- 案: 「共通規則(cross-cutting)を変える還流の後は、その規則を使う completed の UC について、仕様の Scenario 数と tier BDD の Scenario 数を比べ、不一致なら再実行する」を加える

## 提案 3: 共有関数の変更は呼び出し元 UC のテストと同じ commit で行う

- 対象: `docs/dev-rules/tier-rules.md`(tier-facade 内の共有関数)
- 理由: バイト検査の報告関数の修正で、完了済み UC の `--job-map` の出力順が変わった(learnings `20261110_080548_shared-function-fix-changes-completed-uc-output.md`)
- 案: 「tier 内の共有関数の出力を変えるときは、呼び出し元 UC ごとに出力の変化をテストで判定し、同じ commit に含める。判定するテストが無ければ足す」を加える
