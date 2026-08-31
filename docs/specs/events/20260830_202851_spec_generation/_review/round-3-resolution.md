# round-3 resolution(Step6.5 最終ラウンドの修正記録)

- 入力: `_review/round-3.yaml`(reopened 1 / 新規 major 1 / 新規 minor 4)
- 担当: オーケストレータ本体(生成側)。レビュー前に発見した並列修正衝突 1 件(F-125 残件)も含む
- 結果: blocker 0 / 未解決 major 0 で収束

| finding | severity | resolution | 変更内容 | 変更ファイル |
|---|---|---|---|---|
| F-125 残件 | -(レビュー前の自己検出) | fixed | 契約が `status=` を採用したのに UC 側が落としたままだった衝突を解消。spec BDD Then に `status=REQUESTED`、tier stderr 一覧に `status=...`(超過時点の依頼 status)を追加 | 確報比較依頼を登録して終端状態まで待機する/spec.md, tier-final-crosscheck.md |
| F-201 | major | fixed | F-103 の規則(off=3 の is not configured / on で env 不在・キー欠落=2 の定型文)に統一。調整 UC tier-ops の stderr 一覧に定型文 2 種(2)を追加、終了コード表 2/3 行と _api-summary の meaning から「管理 DB 接続設定が無い」を 2 に移動。契約 hang-detect-trend.sh の stderr に定型文 2 種を追加、exit 2 condition に env 不在・キー欠落を追加、exit 3 condition を off のみに。run-lineage.sh 契約にも同処置(stderr 定型文 2 種 + exit 2 condition) | hang_detect_limit_minutes をジョブごとに調整する/tier-ops.md, _api-summary.yaml; _cross-cutting/api/cli-command-contract.yaml |
| F-141 | minor | fixed | 契約 run-lineage.sh stderr に `error: management db connection failed run_id=... conn_ref=...`(6)を追加し、`management db query failed ...` を `run_id=...` 付きに統一 | _cross-cutting/api/cli-command-contract.yaml |
| F-202 | minor | fixed | 検証 UC の connection failed に `role=` を追加(契約 background-rerun.sh L652 と同文に) | リラン対象を検証する/tier-ops.md, _api-summary.yaml |
| F-203 | minor | fixed | SR spec.md sequenceDiagram のラベルを `warn: runner does not respond to --help` に置換(旧文言の最後の残留) | slot runner の実体スクリプトを割り当てる/spec.md |
| F-204 | minor | fixed | 判定 UC の option required 列挙に ALERT_MAIL_CMD を追加し、`error: ALERT_MAIL_CMD is not executable value=... path: ...`(2)を併記(契約 hang-detector.sh stderr と同文) | background 実行の経過時間と終了状態を判定する/tier-ops.md, _api-summary.yaml |
| F-205 | minor | fixed | 登録 UC tier の query failed から ` conn_ref=...` を削除(契約・ui-design 定型文と同文に。conn_ref は connection failed のみ) | 確報比較依頼を登録して終端状態まで待機する/tier-final-crosscheck.md |

集計: fixed 7(major 1 / minor 5 / レビュー前検出 1)。deferred なし。

## 収束判定

- round-3 で round-2 の findings 46 件中 45 件 resolved、reopened 1(F-141)はここで fixed
- 新規 blocker 0 / 新規 major 1(F-201)はここで fixed
- **Step6.5 収束条件(blocker 0 かつ未解決 major 0)を満たす**
