# 変更サマリ

- event_id: 20261010_201000_feedback_impl_feedback_dcd8234d
- trigger_event: rdra:20261010_200000_feedback_impl_feedback_dcd8234d
- 生成日時: 2026-10-10T20:10:00Z
- feedback request: 20261010_104636_impl_feedback_dcd8234d(direct work unit: なし / causal work unit: CR-dcd8234d-007#1, CR-dcd8234d-002#1。packet: docs/pipeline/feedback-runs/20261010_104636_impl_feedback_dcd8234d/stage-packets/quality_attributes.md)
- mode: 差分更新(nfr-grade-diff.yaml。グレード値の変更なし。7 メトリクスの grade_description / reason / source_model を更新)

本イベントは direct work unit を持たず、前段 requirements stage のクロスチェック簡素化(CR-dcd8234d-007)への下流追従である。RDRA から廃止された要素(クロスチェックジョブマップ・対象カタログ・比較結果(comparison_result)・比較種別・business_date / カタログ版・成果物 URI の受け渡し)への言及を NFR グレード表から取り除き、簡素化後の正本(速報・確報の比較ツール起動コマンド各 1 行、対象は適用側が比較ツール側で定義、確報は業務上の引数なしで起動)に合わせた。グレード値はいずれも据え置きで、合否ラインに影響はない。

## 追加

- なし

## 変更(7 メトリクス。いずれも grade 変更なし)

- B.1.1.2 データ量(grade 1, user) → 5,000 行の共通前提が及ぶ CSV 形式の設定ファイルを「slot ジョブマップ・クロスチェックジョブマップ・対象カタログ」から「slot ジョブマップ」のみに改める。キー列・版の列の例から対象カタログ(target_identifier / カタログ版)を外す。source_model からクロスチェックジョブマップ・対象カタログを外す。利用者が 2026-09-21 に確定した 5,000 行・内容によらず 10 秒以内の判断自体は据え置き(CR-dcd8234d-007)
- B.1.1.4 バッチ処理件数(grade 2, medium) → 対象件数の定義元を「適用側の対象カタログ」から「適用側が比較ツール側で定義」に、reason を business_date 単位から業務上の引数なしの起動に改める。source_model の情報を対象カタログから確報比較依頼(final_crosscheck_request)に差し替え(CR-dcd8234d-007)
- B.2.1.1 レスポンスタイム(grade 2, user) → source_model の情報からクロスチェックジョブマップ・対象カタログを外す。grade_description / reason(利用者確定の 10 秒前提)は据え置き(CR-dcd8234d-007)
- B.2.2.2 バッチ処理量(grade 1, medium) → 確報対象を「対象カタログの全テーブル・全ファイル」から「全テーブル・全ファイル(対象は適用側が比較ツール側で定義)」に、reason を比較種別の区分から速報ジョブ単位・確報全量に改める。source_model を比較種別・対象カタログから速報/確報比較依頼に差し替え(CR-dcd8234d-007)
- C.1.2.2 バックアップ対象(grade 1, high) → 設定の列挙からクロスチェックジョブマップ・対象カタログを外し、確報クロスチェック worker 設定を加える(確報の比較ツール起動コマンドの正本)。比較定義は残す(CR-dcd8234d-007)
- C.2.2.1 ライフサイクル管理(grade 1, high) → grade_description から「カタログ版は対象カタログで管理」を外す。source_model から対象カタログを外す(CR-dcd8234d-007)
- F.2.2.1 アーキテクチャ拡張性(grade 2, high) → 差し替え対象の列挙から対象カタログを外す(runner・ジョブマップ・比較定義に改める)。方針資料の適用構成文書の記述と一致(CR-dcd8234d-007)

## 削除

- なし(メトリクスの削除は無い。廃止 RDRA 要素への言及の除去のみ)

## CR-dcd8234d-002#1 の扱い

受け入れ基準を観測できる振る舞いだけにする変更(CR-dcd8234d-002)は、RDRA では受け入れ基準の表現と BUC 画面名(「クロスチェックジョブマップ検証出力」→「速報クロスチェック設定検証出力」)の変更にとどまる。NFR グレード表は受け入れ基準・画面名を参照しないため、本 CR による NFR の更新は無い(not_impacted)。
