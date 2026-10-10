# NEXT: クロスチェックのジョブマップと比較定義を定義する(dcd8234d)

- state: **blocked_on_spec**(仕様反映待ち)
- feedback ID: `20261010_104636_impl_feedback_dcd8234d`
- 要求件数: 4(severity: spec-gap 4 / blocker 0)
- 公開 event: `20261010_185203_feedback_request_published_dcd8234d`(承認 event `20261010_184919_review_approved_dcd8234d_feedback_publish`、S9 evidence `20261010_182853_s9_review_generated_dcd8234d_simplification`)
- 承認回答: `機能=A / 要求=公開 / 登録=A / 前提=一括承認`(前提 36 件は auto_confirmed。これは公開許可であり delivery approval ではない)
- 生成日時: 2026-10-10T18:55:00+09:00

## 次に実行するコマンド(新セッションまたは `/clear` 後に 1 回)

```text
/distillery:dist-pipeline docs/impl/latest/dcd8234d/feedback-requests/20261010_104636_impl_feedback_dcd8234d.md
```

- `--recommended-auto` の判断材料: 4 件すべて spec-gap で blocker 無し。主要求 CR-007(クロスチェックの簡素化)は要求定義(USDM / RDRA)から仕様・契約・RDB スキーマまで広く変わる大きな変更で、起動コマンドの置き場(env キー追加 vs CSV 2 行)と違反文言は仕様側の決定事項として推奨案付きで書いてある。推奨案を自動採用してよいなら付ける。CR-001 / 002 / 003 は簡素化後の構成に依存する条件付き要求
- 方針資料(`tmp/RelayGateのしくみ.md` / `tmp/RelayGateの利用イメージ.md`。git 管理外)の確報依頼データ項目(business_date / 対象カタログの版)と rapid_run の artifact_uri は、ユーザーが簡素化に合わせて直す(CR-007 に注記)

## pipeline 完了後の再開コマンド

```text
/distillery-impl:dist-impl-run dcd8234d
```

distillery 側の仕様更新で input hash が変わると、影響を受けた done だけが projection 照合で再実行される(tier-scoped staleness)。簡素化が反映されると本 UC の範囲は「速報の起動コマンド 1 行の設定とその検証」に縮小し、確報側 tier(tier-final-crosscheck)は UC から外れる見込み。uc-map の tiers 変更は S0(bootstrap P2)の content-stable 照合で検知されるため、S0 から再判定して S1 以降をやり直す。既存の確報側実装(final-crosscheck/)と速報側の比較定義 CSV 検証の大半は削除・縮小対象。

## 到達点(仕様反映前の記録)

- ゲート 6/6 pass(速報側 bats 106 / 確報側 bats 57 / tier BDD 4+4 / UC BDD 43 / ATDD 1 / format / lint。Linux コンテナ ubuntu24 でも pass)
- 独立検証(gpt-6-astra)attempt 4 で両 tier blocker 0 / major 0 / minor 18+18。経緯: blocker 8 → 2 → 1 → 0(attempt 上限 3 到達後、ユーザーが 4 回目を承認)
- facade の `validate-config.sh` に 2 tier の handler を固定パスで source する hook を追加(commit 4b0be23。要求 CR-001 の案 A = 現行)
- レビュー対話で仕様選択 2 回(案 A: 確報は起動のみ → 簡素化: runner → DB ← worker → 比較ツール、速報はジョブ ID、確報は引数なし、runner / worker は別セグメントで値は依頼レコードに持つ)。記録は `review/review-notes.md`

## 参照 path

- 公開 Markdown: `docs/impl/latest/dcd8234d/feedback-requests/20261010_104636_impl_feedback_dcd8234d.md`
- review HTML(gitignore、再生成可能): `docs/impl/latest/dcd8234d/review/index.html`
- as-built: `docs/impl/latest/dcd8234d/feedback/as-built-summary.md`
- learnings: `docs/impl/latest/dcd8234d/learnings/`(関数名衝突 / 参照先 CSV の共通規則 / attempt 上限 / 仮採用の事前確認 / 別セグメントは DB で受け渡し)
- issues: `docs/impl/latest/dcd8234d/issues/`(4 件。すべて要求へ回収済み)
- git: branch `feature/define-crosscheck-job-map-and-comparison-definitions`(base main `eee392b`)。push / PR は未実施(仕様反映後の再レビューと要求 0 件の承認が条件)
