# UC 横断 Scenario 一覧(S2 test-scaffold 起票。feedback run 2〜9 後の再生成)

- uc_id: dcd8234d(クロスチェックのジョブマップと比較定義を定義する / define-crosscheck-job-map-and-comparison-definitions)
- 起票 stage: S2 test-scaffold(2026-11-10。spec の還流 feedback run 2〜9 の後)
- 前回の一覧 `20261027_083500_cross-uc-scenarios.md` を引き継ぎ、追加・変更された Scenario を判定し直した。本ファイルが現行の一覧
- 種別: 仕様疑義ではなく責務分担の記録(実装の blocker ではない)

## 判定結果

ハーネス注入が必要な UC 横断 Scenario は **0 件**。

| 段 | Scenario | 他 UC の責務を含む行 | ハーネス注入 |
|---|---|---|---|
| UC BDD | 速報の起動コマンドを検証する(SPEC-004-01) | なし。追加された Then「stderr に error 行は出ない」も本 UC の検証コマンドの出力 | 不要 |
| UC BDD | 起動コマンドを差し替えて検証する | なし | 不要 |
| UC BDD | 引数部分の内容は検査しない(SPEC-004-04)(新規) | なし。Then は `validate-config.sh --rapid-crosscheck` の終了コード・stdout・stderr | 不要 |
| UC BDD | 異常系 5 件(Then が「の 1 行だけが error 行として出る」に変わった 4 件を含む) | なし | 不要 |
| UC BDD | クロスチェックジョブマップと対象カタログの検証種別は無い(SPEC-004-04)(新規。Scenario Outline 2 例) | Then の `error: unknown option option=<option>` は validate-config.sh のオプション解析(エントリポイントの定義元は UC「feature flag を設定する」fd678b04。CLI 契約 conventions.option_style)の共通の振る舞い。同じ tier-facade の同じコマンドで、本 UC が新たに作る状態や後続 UC の遷移は含まない | 不要(現行の validate-config.sh が既にこの振る舞いを持つ) |
| tier BDD | 新規 5 件(引数部分 / 字下げしたコメント行 / 同じキーが 2 行 / 字下げしてコメントにした起動コマンド / バイト・改行の違反の全件) | なし。いずれも rapid-crosscheck.env の読み込み(facade の repository / usecase)の範囲 | 不要 |
| ATDD | SPEC-004-04-5 / -6 / -7 / -8 / -10 / -11 / -12 | なし。-12(`--args={params}`)は本 UC の検証ルール 5 | 不要 |

## S4 で注意すること(仕様疑義ではない)

- spec-decision-029 の差分(同じ行のバイト違反の順を NUL → UTF-8 → BOM → CR にする)は、`facade/src/usecase/validate_job_map.sh` の
  `validate_job_map_report_byte_errors` を本 UC の検証も共有しているため、直すとジョブマップの検証(UC「slot ごとのジョブマップを定義する」eff24f55)の出力も同時に変わる。
  本 UC の S2 では `facade/test/usecase/validate_rapid_crosscheck.bats` に速報クロスチェック設定側の red テストだけを置き、ジョブマップ側のテストには触れていない。
- 前回の issue `20261027_083600_params-rule-vs-usdm-two-checks.md`(USDM が検証を 2 点とし spec の 3 点目と食い違う)は、
  USDM SPEC-004-04 が 3 点に改まり(feedback run 2〜9)解消した。ATDD step の該当コメントも現在の仕様に合わせて直した。

## 範囲外として扱うもの

- `@atdd_SPEC-004-04-9`(確報の起動コマンド)は UC 256abc3b の担当。本 UC では step を定義しない
- 確報の起動コマンド(`final-crosscheck.env` の `FINAL_COMPARE_COMMAND` / `--final-crosscheck`)は別 UC の担当
- spec-decision-023 / 026 / 028 / 029 の feature flag 設定(`feature_flag_config.sh` / `validate_feature_flag.sh`)側の差分は UC「feature flag を設定する」の担当
- spec-decision-030 の速報 worker・確報 runner / worker の起動時検査と、spec-decision-031(hang-detector.sh・確報の置き場)は他 UC・他 tier の担当
