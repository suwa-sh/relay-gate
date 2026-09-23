# S4 tier-impl 完了(eff24f55 / tier-facade / attempt 4)

- blocker 3 件を解消した
  - 任意入力の制御文字を、`--job-map` の全出力経路で可視表記(`\n` / `\t` / `\u00XX`)へ置き換える(先行 UC と共有の表示関数に追加。通常の値の出力は 1 バイトも変わらない)
  - 補助コマンド(tr / sed / sort)の失敗を検知し、成功サマリーを出さず error 1 行と終了コード 6 で終える。終了状態 0 でも出力が欠けた場合は失敗として扱う
  - UTF-8 として不正な行を、既存の `error: csv quote is invalid line=N` と終了コード 2 で拒否する(ユーザー確定の方針)
- 既存テストの期待値を 4 件変更した(生の制御文字の期待 3 件、不正 UTF-8 受理の期待 1 件)
- 前提は 28 件 → 34 件。bats 277 件、tier BDD 23 Scenario が pass
- 未対応: 先行 UC の `--feature-flag` の stderr に同じ穴(制御文字の素通し)が残る。issue に記録した
- 仕様に無い判断(終了コード 6 の error 文言、可視表記)は issue に変更要求として記録した
