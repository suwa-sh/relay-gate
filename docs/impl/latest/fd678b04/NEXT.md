# NEXT: feature flag を設定する(fd678b04)

- state: **blocked_on_spec**(2026-11-15 の再実行。仕様への要求 4 件を公開済み・反映待ち)
- 再実行の理由: 2026-09 の完了後に変わった仕様(env 形式の設定ファイルの共通規則、`--verbose` の info 行の規則)への追従
- 承認: `review_approved` event `20261115_100850_review_approved_fd678b04_feedback_publish`(S9 evidence `20261115_094919_s9_review_generated_fd678b04`)。前提 21 件すべて confirmed
- 公開: `feedback_request_published` event `20261115_101101_feedback_request_published_fd678b04`
- 生成日時: 2026-11-15T10:20:00+09:00

## 次に起きること

1. 仕様への反映(新しいセッションで実行):

   ```text
   /distillery:dist-pipeline docs/impl/latest/fd678b04/feedback-requests/20261115_093126_impl_feedback_fd678b04.md
   ```

2. 反映後、`/distillery-impl:dist-impl-run fd678b04` で再開する(入力の hash が変わった stage だけ再実行される)。

## 取り込み(利用者の指示による)

利用者は最終確認で「要求の公開に続けて、作業ブランチの共有と取り込み依頼の作成まで」を指示した。
要求が残る状態のまま、branch `feature/configure-feature-flags`(base main `4f447df`)を 1 commit に squash して push し、PR を作成する。
PR の存在は GitHub が正(`gh pr list --state all --head feature/configure-feature-flags`)。前回の取り込みは PR #7(2026-09-18 完了)。

## 公開した要求(4 件。利用者はすべて推奨案を選択)

| 要求 | 利用者の決定 |
|---|---|
| 設定ファイルの検査の性能を「目標値」と明記する(入力を制限しない・合否の検査にしない)。大きさの条件(5,000 行以内かつ 8 MB 以内)を足す。runner の応答待ち(最大 9.2 秒)は別に数える | 4 種類の設定検証すべてに適用する |
| `--feature-flag` で error 行が 2 行以上出るときの順 | いまの順を仕様に書く |
| mode が列挙外・欠落のときの従属キーの検査 | いまどおり検査すると仕様に書く |
| 9 キー以外の値をプロセスの変数へ取り込まないこと | 仕様に書く |

## 残っている事実(合否には使わない。利用者決定「目標であってチェックではない」)

- 目標(5,000 行以内かつ 8 MB 以内を 10 秒以内)との差が 2 つの場合に残る: 大きな設定 + 応答しない runner 2 つ(Linux 約 11 秒)、UTF-8 ロケールで 3 行・8 MiB 弱(約 10 秒)。`issues/20261115_090000_performance-target-gaps-not-gating.md`
- `--rapid-crosscheck` と `--job-map` は 8 MB 付近で 10 秒を超える(この UC の変更の前後で同じ)。`issues/20261113_063000_other-validation-kinds-exceed-performance-target.md`。`--job-map` は eff24f55 の再実行で扱う

## 次の UC

`/distillery-impl:dist-impl-run eff24f55`(slot ごとのジョブマップを定義する。完了済み UC の再実行)。

## 参照 path

- 実装事実: `docs/impl/latest/fd678b04/feedback/as-built-summary.md`
- 学び: `docs/impl/latest/fd678b04/learnings/`
- 承認対話: `docs/impl/latest/fd678b04/review/review-notes.md`
- レビュー資料(gitignore): `docs/impl/latest/fd678b04/review/index.html`
- 公開済み変更要求: `docs/impl/latest/fd678b04/feedback-requests/20261115_093126_impl_feedback_fd678b04.md`(反映待ち)。`20260917_*` の 2 件は反映済み
