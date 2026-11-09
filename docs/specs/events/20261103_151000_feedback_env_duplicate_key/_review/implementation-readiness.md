# 実装可能性の判定(2026-11-03 の差分更新: env 形式の同じキーの重複)

対象は、この差分更新で変更した UC です。変更していない UC は前イベントの判定(全 UC ready)を引き継ぎます。

| UC | 判定 | 根拠 |
|---|---|---|
| feature flag を設定する | ready | 同じキーの重複の判定(キーの前後の空白を除いた完全一致、値が同じ・空・未知キーも数える)、文言と lines=、invalid line との報告の順、キーごとの検査を行わないこと、stdout を出さないことが、契約・spec.md・tier-facade.md と BDD で決まる。実装(feature_flag_config.sh)は契約に合わせて変える必要がある(spec-decision-028) |
| クロスチェックのジョブマップと比較定義を定義する | ready | 起動コマンドのキーの重複で 2、stdout の値の行が `-`、violations=1 が BDD で決まる。実装(rapid_crosscheck_env.sh / validate_rapid_crosscheck.sh)は契約に合わせて変える必要がある(spec-decision-028) |
| 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する | ready | --housekeep の重複キーの stdout・stderr と、housekeep.sh が使わないキーの重複でも何も削除せず 2 で終えることが BDD で決まる |
| 比較ツールで日次全量比較を実行して結果を保存する | ready | --final-crosscheck の入力の守備範囲の違反と stdout の `command_path: -` が契約と一致する |
| 現在状態を確認して停止確認に応答する | ready | abort-final-crosscheck.sh は final-crosscheck.env の入力の守備範囲の違反(FINAL_DB_CONN_REF の重複を含む)を 2 とし、管理 DB なし(3)の判定はその後に行うことが、契約・spec.md・tier-ops.md・_api-summary.yaml と BDD で一致する |
| 設定ファイルを読むその他の UC(実行時の読み手) | ready | 契約 conventions.exit_codes の 2 と config_input_rules.env_files により、各コマンドの終了コードと報告の順が一意に決まる。abort-final-crosscheck.sh は重複を 2 とし、管理 DB なし(3)とは扱わない |

## 反証レビュー

- round 1: major 4 / minor 3。すべて fixed
- round 2: minor 2。すべて fixed
- round 3(検証パス): minor 1。文言修正で fixed
- blocker 0、未解決の major 0 で収束した
