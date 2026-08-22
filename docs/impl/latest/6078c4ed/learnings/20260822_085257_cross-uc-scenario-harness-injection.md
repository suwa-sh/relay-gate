# 後続 UC の責務を含む E2E Scenario はハーネス注入で通さず、注入箇所と削除条件を記録する

## 何が起きたか

spec.md の Scenario「background roleを先に起動しforeground待機中もbackgroundが並走する」は、Then で green の RUNNING 遷移(後続 UC c3c7ab31 の責務)と blue foreground の完了待ち(foreground 応答 UC の責務)を要求しており、本 UC の tier 実装だけでは成立しなかった。また、仕様が「CLI 応答 10 秒以内」と「60 秒の foreground 完了待ち」を同時に要求していた。

## 原因

UC 単位の E2E Scenario が UC 間の統合観点で書かれており、責務境界(起動受付まで / 起動後の遷移 / 完了応答)を跨いでいた。依存宣言(`uc-dependencies.md`)は存在するが、Scenario 単位で「どの UC が実装されたら成立するか」は示されていない。

## 回避方法

- 仕様を曲げず、UC BDD の ssh スタブに後続 UC の振る舞い(RUNNING 遷移、detached 実行)を模擬するハーネスを注入して通過させる。注入箇所には issue への参照と「暫定注入・削除条件」をコメントで残し、done ファイルに `harness_injections`(場所・模擬対象・部分検証の範囲・削除条件)を記録する
- 検証できなかった Then(foreground 完了待ち)は「部分検証」と明示し、通ったことにしない
- 仕様側には Then を本 UC の責務内へ改める要求(CR-013)を出す

## 次回の対応

- 仕様生成時に、E2E Scenario の各 Then に「担う UC」を付け、他 UC の責務を含む Scenario は UC 横断の統合シナリオとして分離する
- 後続 UC 実装後に注入を外して再検証する手順を uc-map か NEXT に残す
