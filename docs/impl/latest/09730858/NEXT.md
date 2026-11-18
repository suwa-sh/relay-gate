# NEXT: slot 実行モードを選択して runner を起動する(09730858)

- state: **completed**(仕様への要求 0 件。還流は不要)
- 承認: `review_approved` event `20261118_120548_review_approved_09730858_final`(S9 evidence `20261118_120038_s9_review_generated_09730858`)。前提 22 件すべて confirmed
- 取り込み準備: `delivery_prepared` event `20261118_120549_delivery_prepared_09730858_select_slot_mode_and_launch_runners`
- 生成日時: 2026-11-18T12:05:49+09:00

## 作ったもの

| 対象 | 内容 |
|---|---|
| `facade/bin/facade.sh`(本体は `facade/src/`) | ジョブを起動するコマンド。モードの選択、background を先に起動して foreground だけを待つ、管理 DB への記録 |
| `facade/src/usecase/validate_*.sh` ほか | 設定の検査を共有関数にして、検証コマンドと facade.sh で共用(検証コマンドの出力は不変) |
| `facade/features/steps/support/temp-postgres.js` | テスト用の一時 PostgreSQL(initdb + pg_ctl。テーブルは契約の生成物から作る暫定の定義) |
| `features/uc/steps/support/facade-harness.js` | UC BDD と ATDD が共有する facade 起動の補助 |

## 取り込み

- base: `main`(`77e44a2`)/ feature branch: `feature/select-slot-mode-and-launch-runners`
- squash commit message: `feat: slot 実行モードを選択して runner を起動する`
- 利用者の指示(2026-11-18): 1 コミットにまとめて取り込み依頼を作り、自動検査が通ったらマージする
- PR の存在は GitHub が正(`gh pr list --state all --head feature/select-slot-mode-and-launch-runners`)

## 次の機能へ引き継ぐこと

- 管理 DB へは `psql` + 接続サービス名(`service=<参照名>`)。利用者決定 2026-11-18、CLAUDE.md に記載。機能ごとに決め直さない
- UC BDD「値が空のジョブマップの場所のキーがある slot の runner は固定の名前のジョブマップで実行先を解決する」は、標準の runner が仮の応答(正しい引数で終了コード 6、何も書かない)の間だけ、execution-spec.json と green の stderr.log を見る Then が `skipped` になる。標準の runner の中身を作る機能で、保留が外れて判定されることを確かめる
- 標準の runner(`facade/runners/standard-runner.sh`)は `--help` 以外まだ仮の応答。後続の機能が中身を作るとき、仮の応答とそのテスト、テストの記録用の包み(facade-harness.js)を見直す
- 管理 DB のテーブルの定義(マイグレーション)は別の機能の担当。それができたら、一時 PostgreSQL の暫定の定義を置き換える
- 実装者が補った前提のうち、foreground の `exitcode.txt` が無いときの文言は、結果を中継する機能で定義し直す可能性がある
- 性能で見るのは「ムダな処理がないこと」だけ。作為的な条件を掘り下げない(CLAUDE.md)

## 残っている事実(合否には使わない)

- `issues/20261118_091109_cross-uc-scenarios.md`: 機能をまたぐシナリオの担当の記録。仕様への要求にしていない
- tier BDD・UC BDD・ATDD(cucumber)は、Linux では手元で実行していない(CI が実行する)

## 次の UC

`/distillery-impl:dist-impl-run 7c41c7cd`(ジョブマップで JOB_ID から実行先を解決する)。

## 参照 path

- 実装事実: `docs/impl/latest/09730858/feedback/as-built-summary.md`
- 学び: `docs/impl/latest/09730858/learnings/`
- 承認対話: `docs/impl/latest/09730858/review/review-notes.md`
- レビュー資料(gitignore): `docs/impl/latest/09730858/review/index.html`
