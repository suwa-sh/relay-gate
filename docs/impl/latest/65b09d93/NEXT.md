# NEXT: slot runner の実体スクリプトを割り当てる(65b09d93)

- state: **completed**(仕様への要求 0 件。還流は不要)
- 承認: `review_approved` event `20261118_070423_review_approved_65b09d93_final`(S9 evidence `20261118_025247_s9_review_generated_65b09d93`)。前提 11 件すべて confirmed
- 取り込み準備: `delivery_prepared` event `20261118_070424_delivery_prepared_65b09d93_assign_slot_runner_scripts`
- 生成日時: 2026-11-18T07:04:22+09:00

## 作ったもの

| 対象 | 内容 |
|---|---|
| `facade/runners/standard-runner.sh` | 標準の runner の入口。`--help` に `usage:` の行と `runner-if-version=1` を返す |
| `facade/lib/runner-{resolve,spec,result,notify}.sh` | 共通ライブラリ 4 本の入口(中身は空) |
| `facade/src/presentation/standard_runner.sh`、`facade/src/usecase/runner_*.sh` | 本体の置き場 |
| テスト | 時間を確かめる 14 件と大きな入力だけの 3 件を削除。heavy の仕分けの仕組みを削除 |

## 取り込み

- base: `main`(`7ab3f24`)/ feature branch: `feature/assign-slot-runner-scripts`
- squash commit message: `feat: slot runner の実体スクリプトを割り当てる`
- 利用者の指示(2026-11-18): 1 コミットにまとめて取り込み依頼を作り、自動検査が通ったらマージする
- PR の存在は GitHub が正(`gh pr list --state all --head feature/assign-slot-runner-scripts`)

## 次の機能へ引き継ぐこと

- `facade/bin/facade.sh` が無い間、それを起動するシナリオは cucumber の `skipped` を返す(tier BDD 1 件、UC BDD 2 件)。次の機能で `facade.sh` を作ったら、この保留が外れて判定されることを確かめる
- 標準の runner は、`--help` 以外では仮の応答(引数の誤り 2、正しい引数 6)。後続の機能が中身を作るとき、この仮の応答とそのテストを置き換える
- 受け入れテストのうち、ジョブを起動するコマンドが要るものは後続の機能に回した。各機能の開始時に割り当てを確認する
- 性能で見るのは「ムダな処理がないこと」だけ(CLAUDE.md に記載)。時間や大きな入力のテストは書かない

## 残っている事実(合否には使わない)

- `issues/` の 3 件(機能をまたぐシナリオ / 10 秒のシナリオ / 準備失敗のシナリオ): どれも仕様への要求にしていない
- 実装者が補った前提のうち、1 件の文面と 1 件の分類に小さな不正確さが残る(`feedback/as-built-summary.md` に記載)
- tier BDD・UC BDD・ATDD(cucumber)は、Linux では手元で実行していない(CI が実行する)

## 次の UC

`/distillery-impl:dist-impl-run 09730858`(slot 実行モードを選択して runner を起動する)。

## 参照 path

- 実装事実: `docs/impl/latest/65b09d93/feedback/as-built-summary.md`
- 学び: `docs/impl/latest/65b09d93/learnings/`
- 承認対話: `docs/impl/latest/65b09d93/review/review-notes.md`
- レビュー資料(gitignore): `docs/impl/latest/65b09d93/review/index.html`
