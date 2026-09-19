# 同じ検証規則が spec.md / tier md / 契約で別表記のときは、1 つを選ばず issue に起票する

## 何が起きたか

feature-flag.env で拒否する「確報の制御キー」の範囲が、同じ UC の仕様の中で 3 通りに書かれていた。spec.md の処理フロー(シーケンス図の分岐)は `FINAL_*`、spec.md の分岐条件一覧は「`FINAL_CROSSCHECK_MODE` 等」、tier-facade.md の設定契約は `FINAL_CROSSCHECK_*`、CLI 契約は範囲を定めない。実装者は spec.md の処理フローの `FINAL_` を選んで実装し、AssumptionRecord にも issue にも残さなかった。独立した検証が `FINAL_RELEASE_LABEL` の境界入力で不整合を検出し、major(F-001)として記録した。2 サイクル目で初めて表面化した。

## 原因

- 同じ規則が 4 箇所(spec.md の図・表、tier md、契約)に書かれ、どれが正本かが規則の種類ごとに違う。文言は契約が正本だが、キーの範囲は契約が定めていない
- BDD Scenario の入力(`FINAL_CROSSCHECK_MODE`)がどの解釈でも通過する値であり、テストが表記差を検出しない
- 実装者が「表記差」を「仕様に無い」ではなく「どれかを選べばよい」と扱い、AssumptionRecord(spec_absent)にも issue にも載せなかった。前提の抽出規則が「仕様に無い判断」を対象にしており、「仕様が複数あって選んだ判断」を対象にしていなかった

## 回避方法

- 実装前に、対象 UC の検証規則(分岐条件一覧の各行)を spec.md の図・spec.md の表・tier md・契約の 4 箇所で突き合わせ、表記が違う行を issue に起票する
- 表記差のある規則を実装するときは、選んだ表記と根拠を AssumptionRecord に `category: spec_conflict` 相当として記録する(現行スキーマでは spec_absent に載せ、reason に「仕様間の表記差から選択」と書く)
- 接頭辞・列挙など「範囲」を持つ規則には、範囲の境界を判定する TDD ケース(接頭辞に含まれるが列挙に無いキー)を先に置く

## 次回の対応

- UC 着手時に分岐条件一覧を起点に 4 箇所の表記を照合する手順を、テスト足場作成の前に置く
- 独立した検証の spec_conformance 観点で行われた「境界入力による表記差の検出」を、実装者側の TDD にも取り込む(範囲規則には境界ケースを必ず 1 つ書く)
