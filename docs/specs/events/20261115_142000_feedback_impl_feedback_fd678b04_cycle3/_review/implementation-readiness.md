# 実装可能性の判定(2026-11-15 の差分更新: 設定ファイルの検査の性能の目標値化と、feature flag の検証の細部の明記)

対象は、この差分更新で変更した UC です。変更していない UC は前イベントの判定(全 UC ready)を引き継ぎます。

この差分更新は、次の 4 点を CLI 契約に書きました。終了コード・stdout・error 文言は変えていません。

| 書いたこと | 契約の場所 |
|---|---|
| 設定ファイルの検査の性能は目標値(入力の制限でも合否の検査でもない)。runner の応答待ちは別に数える | `config_input_rules.performance_target`、`runner_help_probe.response_time_budget` |
| feature flag の検証の error 行どうしの順 | `config_files` の feature-flag.env の `error_order` |
| mode の値が列挙外・欠落・空のときの扱い(off でないとして検査する) | 同 `validation_rules` |
| 9 キー以外のキーの値をプロセスの変数・環境変数へ取り込まない | `config_input_rules.env_files` |

## 判定

| UC | 判定 | 根拠 |
|---|---|---|
| feature flag を設定する | ready | error 行の順・件数・文言(foreground の個数の行の値の表記を含む)と runner への問い合わせの有無が契約から 1 つに決まる。E2E 2 場面と tier 5 場面の期待値は、いまの実装を実走した出力と一致する。実装の変更は要らない |
| slot runner の実体スクリプトを割り当てる | ready | 応答しない runner の場面は残した。「10 秒以内」の出所を runner への問い合わせの上限(この入力での確認)に改めただけで、判定する値は変わらない |
| slot ごとのジョブマップを定義する | ready | 性能の記載を目標値の語に改め、入力の守備範囲の表の行を「5,000 行または 8 MB を超えるファイルは受理」に直した。検証の結果は変わらない |
| ジョブマップで JOB_ID から実行先を解決する | ready | 「NFR B.2.1.1 を満たす手段」を「目標に近づける手段」に改めただけ |

## 実装時に残る判断

- なし(変更した 4 UC の範囲)

## 今回定めなかったこと(未決事項)

- facade.sh / background-rerun.sh の起動時検証で、違反が 2 つ以上あるときに stderr へ出す error 行
  - 利用者の決定は検証コマンド(`validate-config.sh --feature-flag`)の出力の順までで、元の方針資料にも記載が無い
  - `error_order` の対象を検証コマンドの出力だけと契約に明記した。UC「slot 実行モードを選択して runner を起動する」は変えていない(前イベントの判定のまま)
  - docs/todo.md に記録し、確認推奨項目として返した

## 反証レビュー

- round 1: major 2(foreground の個数の error 行の値の表記が未定義、起動時検証の順との食い違い)、minor 1(spec-event.md の作り直し)。すべて fixed
- round 2: major 2(起動時検証へ順を広げた修正が、既存の場面と各コマンドの契約に合わない)。広げた修正を取り下げて fixed
- round 3(検証パス): minor 1(spec-event.md の作り直しの再掲)。最終段で作り直して fixed
- blocker 0、未解決の major 0 で収束した
