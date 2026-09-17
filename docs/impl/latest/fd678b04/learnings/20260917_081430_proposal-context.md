# CLAUDE.md / dev-rules への追記提案(既存ファイルは編集しない。提案のみ)

## 提案 1(CLAUDE.md「実装は distillery specs に従う」): 検証規則の正本は「文言 = 契約、範囲 = 一致していることを確認してから」

追記案:

> 設定ファイルの検証規則は、error / warn の文言は `cli-command-contract.yaml` の `config_files.<file>.error_messages` が正本だが、拒否・警告するキーの**範囲**(接頭辞・列挙)は契約に無いことがある。範囲を持つ規則を実装するときは、spec.md の処理フロー(シーケンス図)・spec.md の分岐条件一覧・tier md の設定契約・契約の validation_rules の 4 箇所を突き合わせ、表記が違えば実装で 1 つを選ばず issues/ に起票して仕様側へ戻す。

理由: 確報の制御キーの範囲が 3 通り(`FINAL_*` / `FINAL_CROSSCHECK_MODE` 等 / `FINAL_CROSSCHECK_*`)に書かれており、実装者が 1 つを選んだ結果、独立した検証で major になった。

## 提案 2(docs/dev-rules/test-strategy.md): 範囲規則の境界ケースを TDD の必須ケースにする

追記案:

- 接頭辞・ワイルドカード・列挙で範囲を定める検証規則には、「範囲に含まれるが仕様の例示に無い値」と「範囲の直外の値」の 2 ケースを TDD に置く(例: `FINAL_` 接頭辞なら `FINAL_DB_CONN_REF` と `FINALIZE`)
- BDD Scenario の例示値だけでは範囲の解釈差を検出できないため、TDD 側で境界を固定する

理由: BDD の入力 `FINAL_CROSSCHECK_MODE` はどの解釈でも通過し、表記差が検証まで表面化しなかった。

## 提案 3(docs/dev-rules/test-strategy.md): 仕様反映後の再実行の手順

追記案:

- 仕様反映(spec event)後の再実行では、変更された契約の節を先に列挙し、節ごとに 1 項目 1 ケースの TDD を追加して pass / red を記録する。実装の再実行は red の一覧を入力にする
- 前提(AssumptionRecord)の再抽出では、契約に明記された項目を explicit として除外し、除外した旧 ID と契約の節をコメントに残す

理由: 今回この手順で、前サイクルの major(準備失敗が未応答に化ける)と前提 3 件(待機上限など)が契約追従だけで解消した。手順として定型化すると次の UC でも再現できる。
