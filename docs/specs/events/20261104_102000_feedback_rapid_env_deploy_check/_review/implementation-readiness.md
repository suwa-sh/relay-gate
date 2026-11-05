# 実装可能性の判定(2026-11-04 の差分更新: 構築手順の配置時検査への追従)

対象は、この差分更新で変更した UC です。変更していない UC は前イベントの判定(全 UC ready)を引き継ぎます。

| UC | 判定 | 根拠 |
|---|---|---|
| 速報比較依頼を claim する | ready | rapid-crosscheck.env の起動時の検査の順(存在・読み取り → 入力の守備範囲 → 必須キー 2 つ → 整数キー 2 つ)、段ごとの出し方、error 行と hint、未知キーの扱いが契約・tier md・_api-summary.yaml・BDD で決まる。rapid-crosscheck-worker.sh は未実装。ATDD features/atdd/SPEC-005-06.feature の 1 件目の Scenario(9 行目の Given)の step 定義は、設定に RAPID_COMPARE_COMMAND も含める必要がある(spec-decision-030 の 5) |
| 確報比較依頼を登録して終端状態まで待機する | ready | runner の必須キーは FINAL_DB_CONN_REF だけで、worker だけが使うキーの欠落・不正で止まらないこと、FINAL_POLL_* の値の検査が BDD で決まる。final-crosscheck-runner.sh は未実装 |
| 確報比較依頼を claim する | ready | worker の必須キー(FINAL_DB_CONN_REF / FINAL_COMPARE_COMMAND)、FINAL_LEASE_MINUTES / FINAL_WORKER_POLL_INTERVAL_SEC の値の検査、runner だけが使うキーを検査しないことが BDD で決まる。final-crosscheck-worker.sh は未実装 |
| 確報クロスチェック結果を確認する | ready | 終了コード 2 の読み方を runner の必須キーに揃えた |
| クロスチェックのジョブマップと比較定義を定義する | ready | validate-config.sh --rapid-crosscheck の未知キーの warn(継続・violations に数えない)を明記した。検証範囲は変えていない。実装(validate_rapid_crosscheck.sh)は未知キーに warn を出さないため、契約に合わせる必要がある(spec-decision-030 の 5) |
| 比較ツールで日次全量比較を実行して結果を保存する | ready | validate-config.sh --final-crosscheck の未知キーの warn を明記した。worker のホストで検証する前提は契約 note にある |

## 反証レビュー

- round 1: major 5 / minor 5。すべて fixed
- round 2: major 1 / minor 3。すべて fixed
- round 3(検証パス): minor 2。どちらも fixed(検証パス後の修正のため再レビューはしていない)
- blocker 0、未解決の major 0 で収束した
