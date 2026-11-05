# 実装可能性の判定(2026-11-05 の差分更新: 外部レビュー 2 巡目の指摘)

対象は、この差分更新で変更した UC です。変更していない UC は前イベントの判定(全 UC ready)を引き継ぎます。

| UC | 判定 | 根拠 |
|---|---|---|
| background 実行の経過時間と終了状態を判定する | ready | 未知キーの warn を出す時点(走査を始めるとき)・順(ファイル内の出現順・stderr の先頭)・出さない回(設定エラー・DB に接続/SELECT できない・印の置き場を読めない/存在を確認できない)、成果物ルートが無いの定義、feature-flag.env の検査の範囲が契約・tier md・シーケンス・_api-summary.yaml・BDD(9 件追加)で決まる。hang-detector.sh は未実装 |
| ハング疑い・実行エラー・比較異常を通知する | ready | 未知キーの warn 行が alert 行・対象ごとの行より前であることを並び順に書いた |
| 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する | ready | 成果物ルートが無いの定義と feature-flag.env の検査の範囲を契約の 1 か所から参照し、BDD 2 件で決まる。housekeep.sh は未実装 |
| 確報比較依頼を登録して終端状態まで待機する | ready | 実行ホストの置き場のファイルの中身(FINAL_DB_CONN_REF と FINAL_POLL_*)と、worker のキーが残っていても runner はエラーにも warn にもしないことを書いた。final-crosscheck-runner.sh は未実装 |
| 確報比較依頼を claim する | ready | DB セグメントの置き場のファイルの中身を書いた。final-crosscheck-worker.sh は未実装 |
| 比較ツールで日次全量比較を実行して結果を保存する | ready | validate-config.sh --final-crosscheck を DB セグメントで実行し、実行ホストのファイルを対象にしないことを書いた |

## 実装・ATDD との照合

- features/atdd/SPEC-008-06.feature の 1 件目の Scenario はメール送信のままで、USDM の現行の受け入れ条件と違う(spec の段階は features/ を変更しない。完了報告で確認推奨項目として返す。spec-decision-031 の 5)

## 反証レビュー

- round 1: major 1 / minor 4。すべて fixed
- round 2: minor 3。すべて fixed
- round 3(検証パス): minor 2。どちらも fixed(検証パス後の修正のため再レビューはしていない)
- blocker 0、未解決の major 0 で収束した
