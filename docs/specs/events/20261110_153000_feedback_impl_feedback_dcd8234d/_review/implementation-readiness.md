# 実装可能性の判定(2026-11-10 の差分更新: 設定検証の --verbose の info 行の明記)

対象は、この差分更新で変更した UC です。変更していない UC は前イベントの判定(全 UC ready)を引き継ぎます。

この差分更新は、`validate-config.sh` の env 形式の 4 検証種別(`--feature-flag` / `--rapid-crosscheck` / `--final-crosscheck` / `--housekeep`)の `--verbose` の info 行について、文言・出す回・標準エラーの行の順を書き足しました。終了コード・stdout・error 文言は変えていません。

| UC | 判定 | 根拠 |
|---|---|---|
| クロスチェックのジョブマップと比較定義を定義する | ready | info 行の文言・出す回・順は契約 `config_input_rules.env_files` の「validate-config.sh の --verbose の info 行」から 1 つに決まる。いまの実装を実走した出力と BDD 4 場面の期待値が一致する |
| 比較ツールで日次全量比較を実行して結果を保存する | ready | `--final-crosscheck` も同じ規則。BDD 2 場面(3 段目の順、行の構造の検査で止めた回)。検証種別は未実装 |
| feature flag を設定する | ready | `--feature-flag` も同じ規則(2026-11-11 利用者決定)。BDD 3 場面(3 段目の順、有効な設定で stdout を変えないこと、行の構造の検査で止めた回)。いまの実装は未追従で、この UC の実装の再実行で直す |
| 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する | ready | `--housekeep` も同じ規則(error 行のあとの hint を含む)。BDD 2 場面。検証種別は未実装 |

## 表記だけを揃えた UC

次の 4 UC は、検証種別の数の表記を契約どおり 5 つ(`--housekeep` を含む)に直しただけで、振る舞いは変えていません。判定は前イベントのまま ready です。

- slot runner の実体スクリプトを割り当てる(_api-summary.yaml)
- 切り替えた運用モードで業務ジョブを実行する(_api-summary.yaml)
- slot ごとのジョブマップを定義する(_api-summary.yaml)
- feature flag を設定する(_api-summary.yaml、tier-facade.md の排他の列挙。--verbose の反映は上の表)

## feature flag の扱い

- 当初は対象外として利用者に確認し、2026-11-11 に「ほかの 3 種類と同じ規則にそろえる」と決まったため、同じイベントで反映した

## 反証レビュー

- round 1: minor 5(--verbose の説明の言い方、段の呼び名の不揃い、止めた回の stdout の判定、確報の止めた回の場面、速報の書式の書き方)。すべて fixed
- blocker 0、未解決の major 0 で収束した。minor の修正は文言と場面の追加だけのため、再レビューはしていない
