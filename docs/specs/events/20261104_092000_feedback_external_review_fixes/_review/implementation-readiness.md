# 実装可能性の判定(2026-11-04 の差分更新: 外部レビューの指摘)

対象は、この差分更新で変更した UC です。変更していない UC は前イベントの判定(全 UC ready)を引き継ぎます。

| UC | 判定 | 根拠 |
|---|---|---|
| background 実行の経過時間と終了状態を判定する | ready | 管理 DB に接続・SELECT できない回と印の置き場を読めない回の stderr(error 1 行だけ)・終了コード 6・走査しないこと、検査の位置(走査前の設定の検査のあと、facade/ を列挙する前)、hang-detector.env の値の検査と検査の順が、契約・spec.md・tier-ops.md・_api-summary.yaml と BDD で決まる。hang-detector.sh は未実装 |
| ハング疑い・実行エラー・比較異常を通知する | ready | 印の規定の値(英字コード + LF の完全一致)、不正・読めない印の error 行・MONITORING としての判定・書き直し(alert → S、COMPLETED → COMPLETED、ディレクトリは中へ移さず保存失敗)、判定しない対象の印を読まないこと、対象ごとの行の順が BDD で決まる |
| 監視記録を保存する | ready | 管理 DB に接続・SELECT できない回はこの UC が動かないことが契約と揃う |
| ハング検知ジョブの異常終了を確認する | ready | alert 行が無い失敗(管理 DB・印の置き場)の読み方と、接続が戻った最初の回に未通知の異常だけが出ることが BDD で決まる |
| 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する | ready | parallel_runs 行がある実行は管理 DB の行で判定し、成果物の warn を出さないこと(成果物が無く行だけが残った実行も削除)が BDD で決まる。--housekeep のバイト・改行の違反の報告の順が契約と揃う |
| 成果物と管理 DB の履歴を削除する | ready | 置き場の残り・孤立した印の名前の昇順(バイト順)、単位内の rename と削除の順、手順 3 の失敗時の続け方と error 行の数が契約・tier-ops.md と BDD で決まる |
| slot ごとのジョブマップを定義する | ready | バイト・改行の違反の全件・行番号の昇順・同じ行の順・hint の位置・第 1 段で止めることが BDD で決まる。実装(validate_job_map.sh)は同じ行の BOM の順だけを契約に合わせる必要がある(spec-decision-029) |
| feature flag を設定する | ready | 同上の規則が BDD で決まる。実装(feature_flag_config.sh / validate_feature_flag.sh)は第 1 段の検査を足す必要がある(spec-decision-029) |
| クロスチェックのジョブマップと比較定義を定義する | ready | バイト・改行の違反の stderr 8 行と violations=7(hint を数えない)が BDD で決まる |
| ジョブマップで JOB_ID から実行先を解決する | ready | 実行時の読み手も validate-config.sh と同じ順・同じ件数で出すことが契約と揃う |
| 比較ツールで日次全量比較を実行して結果を保存する | ready | --final-crosscheck のバイト・改行の違反の報告の順が契約と揃う |

## 反証レビュー

- round 1: major 1 / minor 6。すべて fixed
- round 2: major 1 / minor 1。すべて fixed
- round 3(検証パス): 指摘 0
- blocker 0、未解決の major 0 で収束した
