# NEXT: クロスチェックのジョブマップと比較定義を定義する(dcd8234d)

- state: **blocked_on_spec**(仕様反映待ち)
- feedback ID: `20261027_091000_impl_feedback_dcd8234d`
- 要求件数: 2(severity: spec-gap 2 / blocker 0)
- 公開 event: `20261027_113048_feedback_request_published_dcd8234d`(承認 event `20261027_112730_review_approved_dcd8234d_feedback_publish`、S9 evidence `20261027_100325_s9_review_generated_dcd8234d_refresh`)
- 承認回答: `要求=公開(変更要求 2 件) / 確認=前回の回答どおり`(前回回答: `機能=A / 要求=公開 / 前提=A-009:却下(仕様変更) / 前提=A-012:承認 / 前提=残り10件:一括承認`。これは公開許可であり delivery approval ではない)
- 生成日時: 2026-10-27T11:31:59+09:00

## 次に実行するコマンド(新セッションまたは `/clear` 後に 1 回)

```text
/distillery:dist-pipeline docs/impl/latest/dcd8234d/feedback-requests/20261027_091000_impl_feedback_dcd8234d.md
```

- `--recommended-auto` の判断材料: 2 件とも spec-gap で blocker 無し。どちらも仕様の記述を現行実装に揃える変更で、実装の変更は伴わない
  - CR-dcd8234d-009: 速報の起動コマンドの検証項目を、要求・受け入れ基準(USDM SPEC-004-04)でも仕様と同じ 3 点(絶対パスで実行可能 / `{job_id}` あり / `{params}` は引数全体のときだけ)に揃える
  - CR-dcd8234d-010: CLI 契約の引用符の外し方 2 か所を、現行実装の規則(先頭と末尾を別々に 1 文字ずつ外す。対の一致は要求しない)に揃えて書く

## pipeline 完了後の再開コマンド

```text
/distillery-impl:dist-impl-run dcd8234d
```

distillery 側の仕様更新で input hash が変わると、影響を受けた done だけが projection 照合で再実行される(tier-scoped staleness)。仕様反映後に要求 0 件で再レビューし、承認されたら squash → push → PR へ進む。

## 到達点

- ゲート 6/6 pass(facade bats 373 / tier BDD 46 / UC BDD 43 / ATDD 6 / format / lint)
- 独立検証(gpt-6-astra)blocker 0 / major 0 / minor 13
- UC の tiers は tier-facade のみ。ATDD は SPEC-004-04-5,6,7,8,10,11(-9 は日次全量比較の UC 256abc3b へ移動)
- 本 branch には bootstrap の再実行 commit(`impl(bootstrap): ...`)が混在する(還流成果物が feature branch にしか無いため。最終 squash に含まれる)
- 補足: 前提 A-012(`--final-crosscheck` は未実装の終了コード 6)により、UC 256abc3b の実装時に facade の変更が必要になる。方針資料(`tmp/`)の確報依頼データ項目はユーザーが仕様に合わせて直す

## 参照 path

- 公開 Markdown: `docs/impl/latest/dcd8234d/feedback-requests/20261027_091000_impl_feedback_dcd8234d.md`
- review HTML(gitignore、再生成可能): `docs/impl/latest/dcd8234d/review/index.html`
- review notes: `docs/impl/latest/dcd8234d/review/review-notes.md`
- issues: `docs/impl/latest/dcd8234d/issues/`
- git: branch `feature/define-crosscheck-job-map-and-comparison-definitions`(base main `eee392b`)。push / PR は未実施(仕様反映後の再レビューと要求 0 件の承認が条件)
