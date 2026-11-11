# 引き継ぎカード: クロスチェックのジョブマップと比較定義を定義する

このファイルは派生スナップショットである。状態の正は `docs/impl/events/` と各 done ファイルにある。

## いまの状態

| 項目 | 値 |
|---|---|
| state | `completed`(2026-11-11 に利用者が最終承認) |
| 仕様への要求 | 0 件(還流は不要) |
| 止める指摘 / 重要な指摘 | 0 / 0 |
| 承認の記録 | `20261111_084319_review_approved_dcd8234d_delivery` |
| 納品準備の記録 | 最新は `docs/impl/events/` の `delivery_prepared_dcd8234d_rebased_on_main`(起点を main `cae8412` に変更) |

## 次に行うこと

1. 作業ブランチを 1 コミットにまとめる(コミットメッセージ `feat: クロスチェックのジョブマップと比較定義を定義する`)。
2. ふつうの push で作業ブランチを公開し、新しい PR を作る。PR #14 は途中の内容で 2026-11-10 にマージ済み(main `cae8412`)で、リモートの作業ブランチは削除されていた。そのため、残りの変更をいまの main の上に 1 コミットでまとめ直す(2026-11-11 に利用者が確認。上書き push は使わない)。
3. マージは利用者の指示を待つ。
4. マージ後、完了済みの 2 機能を `dist-impl-run` で再実行する(利用者決定済み)。
   - `fd678b04`(feature flag を設定する): `--feature-flag --verbose` の info 行を、ほかの検証種別と同じ規則へ追従させる。
   - `eff24f55`(slot ごとのジョブマップを定義する): 共有関数のバイト検査の出力順の変更へ追従させる。

## git の情報

| 項目 | 値 |
|---|---|
| base branch | `main` |
| base head | `cae841231a7d8e7c9b76dbbc7fd63c94249cde2e`(PR #14 のマージ後の main) |
| feature branch | `feature/define-crosscheck-job-map-and-comparison-definitions` |

## この作業ブランチに混在しているもの

- 仕様の還流の成果物(`docs/` 配下。dist-pipeline の feedback run の結果)。
- 還流後の bootstrap 再実行(`impl(bootstrap): ...` のコミット)。還流の成果物が作業ブランチにしか無いため、作業ブランチ上で再実行した。

## マージ後の再実行で相談する未決事項

- 切り替え設定(`--feature-flag`)の検証で error 行が 2 行以上出るとき、error 行どうしの順が仕様に定められていない。推奨は「いまの実装の順を仕様にする」。

## 他の機能に関する既知の事実

- `validate-config.sh --housekeep` は未実装である(別の機能の担当)。
- 新しい 3 機能(`507350f0` / `24161a85` / `11f3d6b8`)は、着手時に英名と branch slug を利用者に確認する。

## 参照先

- 実装の事実: `docs/impl/latest/dcd8234d/feedback/as-built-summary.md`
- 利用者の判断の記録: `docs/impl/latest/dcd8234d/review/review-notes.md`
- 学び: `docs/impl/latest/dcd8234d/learnings/`
- 最終確認ページ(git 管理外): `docs/impl/latest/dcd8234d/review/index.html`
- 仕様の判断記録: `docs/specs/latest/decisions/spec-decision-033.yaml`
