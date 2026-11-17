# NEXT: slot ごとのジョブマップを定義する(eff24f55)

- state: **completed**(仕様への要求 0 件。還流は不要)
- 承認: `review_approved` event `20261118_005134_review_approved_eff24f55_final`(S9 evidence `20261118_005133_s9_review_generated_eff24f55_no_requests`)。前提 26 件すべて confirmed
- 取り込み準備: `delivery_prepared` event `20261118_005135_delivery_prepared_eff24f55_job_map_validation_speed_up`
- 生成日時: 2026-11-18T00:51:33+09:00

## 2026-11-16 〜 18 の経緯

| 順 | 内容 |
|---|---|
| 1 | 仕様の更新(2026-10 〜 2026-11-16)に追従して全工程を再実行(attempt 6 のまま) |
| 2 | `--job-map` の検証を速くした(出力と終了コードは不変。2 乗に比例する処理を除いた) |
| 3 | 重いテストに heavy の印を付け、通常の実行と CI の常時実行から外した |
| 4 | 性能についての仕様への要求 2 件を用意したが、利用者の決定(2026-11-18)で公開せず取り下げた |
| 5 | 最終承認(要求 0 件) |

## 取り込み

- base: `main`(`f2c82b2`)/ feature branch: `feature/define-slot-job-maps`
- squash commit message: `feat: slot ごとのジョブマップを定義する`
- 利用者の指示(2026-11-17): 1 コミットにまとめて取り込み依頼を作り、自動検査が通ったらマージする
- PR の存在は GitHub が正(`gh pr list --state all --head feature/define-slot-job-maps`)

## 次の機能へ引き継ぐ決定

- 性能で見るのは「ムダな処理がないこと」だけ(実際の利用で想定する形の入力で、行数に比例する時間で終わること)。目標から外すために作った入力は測らず、指摘・課題・仕様への要求にしない。性能のために実装の効率が下がるなら、目標のほうを取り下げる(利用者決定 2026-11-18。CLAUDE.md に記載)
- 重いテスト(heavy の印の 42 件)と仕分けの仕組み(`scripts/ci/heavy-tests.json`、`scripts/ci/heavy-test-files.js`、CI の該当ステップ、CLAUDE.md と impl-config の記載)は、次の機能の実装のはじめに削除する予定(利用者は 2026-11-18 に「削除しても良いくらい」と発言。利用者へ報告済み)
- 標準の slot runner を実装する機能では、本体を `src/` に置き、`runners/` と `lib/` は数行の入口にする(利用者決定 2026-11-16)
- 要求に足した受け入れ基準のうち未割当のものは、各機能の開始時に割り当てを確認する

## 残っている事実(合否には使わない)

- `issues/20261116_062901_job-map-bash-only-parse-exceeds-performance-target.md`、`issues/20261116_090543_housekeep-not-in-performance-target-scope.md`: どちらも要求にしない(利用者決定 2026-11-18)
- tier BDD・UC BDD・ATDD(cucumber)は、Linux では手元で実行していない(CI が実行する)

## 次の UC

`/distillery-impl:dist-impl-run 65b09d93`(slot runner の実体スクリプトを割り当てる)。

## 参照 path

- 実装事実: `docs/impl/latest/eff24f55/feedback/as-built-summary.md`
- 学び: `docs/impl/latest/eff24f55/learnings/`
- 承認対話: `docs/impl/latest/eff24f55/review/review-notes.md`
- レビュー資料(gitignore): `docs/impl/latest/eff24f55/review/index.html`
