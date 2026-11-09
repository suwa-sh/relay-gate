# 実装可能性の判定(2026-11-03 の差分更新)

対象は、この差分更新で変更した UC です。変更していない UC は前イベントの判定(全 UC ready)を引き継ぎます。

| UC | 判定 | 根拠 |
|---|---|---|
| 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する | ready | 管理 DB に接続しない設定の判定の順(形式の検査 → rapid crosscheck mode → slot の確認)、warn の文言、終了コード、stdout の件数が、契約・spec.md・tier-ops.md で一致する。SPEC-014-03 / 04 / 08 の受け入れ基準は、それぞれ具体的な BDD に対応する |
| 成果物と管理 DB の履歴を削除する | ready | 管理 DB に接続しない設定で削除するシナリオに、rapid_crosscheck_mode が off であることを書いた。削除の順序と回復の規則は変えていない |
| feature flag を設定する | ready | キーが空の行、`=` の無い行、空白だけの行が、どれも invalid line(終了コード 2)になることが契約と BDD で決まる。実装(feature_flag_config.sh)は契約に合わせて変える必要がある(spec-decision-023) |

## 反証レビュー

- round 1: major 1 / minor 4。すべて fixed
- round 2: minor 3。すべて fixed
- blocker 0、未解決の major 0 で収束した
