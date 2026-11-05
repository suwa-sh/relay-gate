# 実装可能性の判定(2026-11-05 の差分更新: 管理 DB を 1 つとする前提の明記)

対象は、この差分更新で変更した UC です。変更していない UC は前イベントの判定(全 UC ready)を引き継ぎます。

この差分更新は前提の明記だけで、コマンドの振る舞い(検査・error 文言・終了コード・出力)を変えていません。

| UC | 判定 | 根拠 |
|---|---|---|
| 速報比較依頼を claim する | ready | RAPID_DB_CONN_REF の解決先が他の参照名と同じ 1 つの管理 DB であること、relay-gate は検査しないことを契約 conventions.credentials から参照した。振る舞いは不変 |
| 速報クロスチェック runner へ完了通知を送信する | ready | 同上 |
| 確報比較依頼を登録して終端状態まで待機する | ready | 実行ホストの置き場の FINAL_DB_CONN_REF が DB セグメントの置き場の値と同じ管理 DB に解決されることを書いた。解決先は検査しない。final-crosscheck-runner.sh は未実装 |
| 確報比較依頼を claim する | ready | DB セグメントの置き場の FINAL_DB_CONN_REF について同じ前提を書いた。final-crosscheck-worker.sh は未実装 |
| background 実行の経過時間と終了状態を判定する | ready | HANG_DB_CONN_REF について同じ前提を書いた。hang-detector.sh は未実装 |
| 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する | ready | HOUSEKEEP_DB_CONN_REF は別ロールを指すが解決先は同じ管理 DB であることを書いた。housekeep.sh は未実装 |

## 反証レビュー

- round 1: minor 1(ハウスキープ判定 UC の HOUSEKEEP_DB_CONN_REF に前提への参照が無い)。fixed
- blocker 0、未解決の major 0 で収束した。minor の修正は文言の追加だけのため、再レビューはしていない
