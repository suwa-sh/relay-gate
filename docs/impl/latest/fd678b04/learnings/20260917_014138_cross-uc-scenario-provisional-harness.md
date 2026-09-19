# UC 横断 Scenario は暫定スタブで通し、削除条件を記録する

## 何が起きたか

UC「feature flag を設定する」の E2E Scenario「ジョブ定義を変えずに feature flag だけで運用モードを切り替える(SPEC-001-03)」は、Given だけが本 UC の責務で、When(facade.sh の実行)と Then(green の結果、blue 非起動、管理 DB 非接続)は別 UC の責務だった。facade.sh は未実装のため、統合テストは本 UC の実装だけでは green にならなかった。

## 原因

spec.md の E2E 完了条件は要件(SPEC-001-03 の受け入れ条件)を Scenario 化しているが、Scenario 単位で「どの UC の実装で判定できるか」が分離されていない。要件の受け入れ条件が「検証」と「実行」をまたぐと、Scenario も UC をまたぐ。

## 回避方法

- テスト足場の作成時に、Scenario の Then ごとに担当 UC を判定して issue に一覧化した(`issues/20260917_004843_cross-uc-scenarios.md`)
- 統合テストでは facade.sh を「検証済み feature-flag.env を読み off でない slot の runner だけを起動する」暫定スタブで代替し、管理 DB クライアントの sentinel を PATH 先頭に置いて非接続を検証した
- 暫定注入は done ファイルの `injections` に、根拠 issue・削除条件(担当 UC の統合テスト完了後)・「pass はスタブに対するもの」という注記つきで記録した
- 仕様側には Then の責務分離を変更要求として出した(CR-fd678b04-001)

## 次回の対応

- Scenario 転写の段階で、When / Then の主語が自 UC の CLI でないものを機械的に抽出し、issue に載せる
- 暫定スタブは「担当 UC の完了時に削除する」だけでなく、担当 UC の統合テストが同じ Then を覆っていることを確認してから削除する
- 同じ構造(Given のみ自 UC)の Scenario を持つ UC が他にもある可能性があるため、UC 着手時に spec.md の E2E 節を先に読んで判定する
