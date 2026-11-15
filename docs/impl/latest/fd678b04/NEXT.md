# NEXT: feature flag を設定する(fd678b04)

- state: **completed**(仕様への要求 0 件。還流は不要)
- 承認: `review_approved` event `20261116_044340_review_approved_fd678b04_final`(S9 evidence `20261116_040700_s9_review_generated_fd678b04`)。前提 25 件すべて confirmed
- 取り込み準備: `delivery_prepared` event `20261116_044341_delivery_prepared_fd678b04_job_map_location_keys`
- 生成日時: 2026-11-16T04:43:39+09:00

## 2026-11-16 の経緯

| 順 | 内容 |
|---|---|
| 1 | 公開済みの要求(9 キー以外の値の、読み取り途中の一時的な保持の条件)を仕様へ反映 |
| 2 | 利用者決定を要求から仕様まで反映: 標準の slot runner の正式提供、feature-flag.env の任意 2 キー(BLUE_JOB_MAP_CSV / GREEN_JOB_MAP_CSV)、ジョブを起動するコマンドの error 1 行、リランのコマンドの起動前の検査 |
| 3 | 検証コマンドを任意 2 キーに対応(attempt 5 の独立検証は Linux の ShellCheck 0.9.0 の blocker 1 件 → attempt 6 で修正・合格) |
| 4 | 最終確認で承認(要求 0 件) |

## 取り込み

- base: `main`(`44cb3a6`)/ feature branch: `feature/configure-feature-flags`
- squash commit message: `feat: feature flag を設定する`(本文に 2026-11-15 〜 16 の変更をまとめる)
- 利用者の指示(2026-11-16): 今回の分を 1 コミットにまとめ直して既存の取り込み依頼を更新し、自動検査が通ったらマージする。この branch の取り込み依頼は既にあるため、squash のやり直しは履歴の書き換えになる(利用者の指示による)
- PR の存在は GitHub が正(`gh pr list --state all --head feature/configure-feature-flags`)

## 次の機能へ引き継ぐ決定

- 標準の slot runner を実装する機能では、本体を `src/` に置き、`runners/` と `lib/` は数行の入口にする(静的検査の設定は変えない。利用者決定 2026-11-16)
- 要求に足した受け入れ基準のうち、runner やジョブを起動するコマンドが要る 15 件(SPEC-001-04-3〜8、SPEC-004-01-3〜8・10、SPEC-013-01-3・4)は、どの機能にも未割当。各機能の開始時に割り当てを確認する
- 実装の段で Linux(CI と同じ ShellCheck 0.9.0)の静的検査を実行する(`learnings/20261116_034712_linux-lint-version-gap.md`)

## 残っている事実(合否には使わない)

- 性能の目標との差: `issues/20261115_090000_performance-target-gaps-not-gating.md`、`issues/20261113_063000_other-validation-kinds-exceed-performance-target.md`

## 次の UC

`/distillery-impl:dist-impl-run eff24f55`(slot ごとのジョブマップを定義する。完了済み UC の再実行)。その次が `65b09d93`(slot runner の実体スクリプトを割り当てる)。

## 参照 path

- 実装事実: `docs/impl/latest/fd678b04/feedback/as-built-summary.md`
- 学び: `docs/impl/latest/fd678b04/learnings/`
- 承認対話: `docs/impl/latest/fd678b04/review/review-notes.md`
- レビュー資料(gitignore): `docs/impl/latest/fd678b04/review/index.html`
