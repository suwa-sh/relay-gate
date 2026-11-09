# UC 横断 Scenario 一覧(S2 test-scaffold 起票。仕様還流後の再生成)

- uc_id: dcd8234d(クロスチェックのジョブマップと比較定義を定義する / define-crosscheck-job-map-and-comparison-definitions)
- 起票 stage: S2 test-scaffold(クロスチェック簡素化と起動コマンドの argv 規則の還流後)
- 前回の一覧 `20261010_084142_cross-uc-scenarios.md` は旧仕様(比較定義 CSV / 対象カタログ)向けで、対象 Scenario がすべて無くなった。本ファイルが現行の一覧
- 種別: 仕様疑義ではなく責務分担の記録(実装の blocker ではない)

## 判定結果

UC 横断 Scenario は **0 件**。ハーネス注入は不要。

| 段 | Scenario | 他 UC の責務を含む行 | ハーネス注入 |
|---|---|---|---|
| UC BDD | 速報の起動コマンドを検証する(SPEC-004-01) | なし。Given「/opt/compare/compare.sh が実行可能である」は外部システム(比較ツール)の前提で、どの UC の成果物でもない。Then「管理 DB への接続は行われず、relay-gate のスクリプトは変更されていない」は本 UC の検証コマンドの性質 | 不要(実行可能なスタブを一時ディレクトリに置く fixture で足りる) |
| UC BDD | 起動コマンドを差し替えて検証する | なし(同上) | 不要 |
| UC BDD | 異常系 5 件(コマンド部分が実行できない / 絶対パスでない / {job_id} が無い / {params} が引数全体でない / {params} が引数 1 つ全体なら valid) | なし。Then はすべて `validate-config.sh --rapid-crosscheck` の終了コード・stdout・stderr | 不要 |
| ATDD | SPEC-004-04-5 / -6 / -7 / -8 / -10 / -11 | なし。-11 の「設定ファイル置き場に CSV が無く、validate-config.sh に検証種別も無い」も本 UC の範囲(旧検証種別の廃止) | 不要 |

## 範囲外として扱うもの

- `@atdd_SPEC-004-04-9`(確報の起動コマンド)は UC 256abc3b の担当。本 UC では step を定義しない
- 確報の起動コマンド(`final-crosscheck.env` の `FINAL_COMPARE_COMMAND` / `--final-crosscheck`)は別 UC の担当
