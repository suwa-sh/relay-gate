# Step3 Round 2 G1 レビュー対応記録

- 対象レビュー: `_review/step3-round-2-G1.md`(major 5 / minor 10)+ `_review/step4-review-datastore.md` #1 + `_cross-cutting/uc-dependencies.md` 暗黙参照 #5 + `_cross-cutting/traceability-matrix.md` 未カバー要素(パターン A)
- 方針: 横断契約(cli-command-contract.yaml / rdb-schema.yaml)の値を正として UC 側を合わせる。契約側の変更が必要なものは末尾「契約側への要求」に列挙
- 件数: fixed 14 / deferred 1(#15 は所有範囲外)

| # | severity | 対応 | 変更ファイル | 理由(deferred のみ) |
|---|---|---|---|---|
| 1 | major | fixed | `実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/tier-facade.md`(`finished_at` → `completed_at`、説明を「SUCCEEDED / FAILED / ABORTED へ遷移した日時(UTC)」に統一) | |
| 2 | major | fixed | `実装スクリプトを実行して Runner Result を出力する/spec.md`(UPDATE 文に `exit_code=?, completed_at=now`)、同 `tier-facade.md`(データモデル変更表・BDD Then)、同 `_model-summary.yaml`(columns) | |
| 3 | major | fixed | `実装スクリプトを実行して Runner Result を出力する/tier-facade.md`(引数表 `-- PARAM...` を「復元起動では受け付けない(exitcode.txt=2)」に変更、UC ロジックのバリデーションに追加、tier BDD「--execution-spec 指定時に PARAM の併用を終了コード 2 で拒否する」を追加) | |
| 4 | major | fixed | `feature flag を設定する/tier-facade.md`(stdout 例を契約の 12 キーに揃え、末尾 4 行は UC「slot runner の実体スクリプトを割り当てる」定義と注記。BDD Then を「12 行、8 行目 operation_mode=parallel、最終行 green_runner_if_version=1(off は `-`)」に修正) | |
| 5 | major | fixed | `実装切替ジョブ実行フロー/buc-spec.md`(CRUD マトリクスを分断していた注記段落を表の直後へ移動) | |
| 6 | minor | fixed | `ジョブマップで JOB_ID から実行先を解決する/spec.md`(E2E BDD 2 本の When に `--run-id` / `--role` / `--mode` を明記) | |
| 7 | minor | fixed | 同 `spec.md`(異常系 BDD 2 本の Given に「RELAY_GATE_CONFIG_DIR は /etc/relay-gate である」を追加) | |
| 8 | minor | fixed | `業務ジョブの実行結果を確認する/spec.md`(Then から「GUI を必要としない」を削除) | |
| 9 | minor | fixed | `slot 実行モードを選択して runner を起動する/tier-facade.md`(BDD「runner 実体が実行不可」の Given に BLUE_MODE / BLUE_RUNNER / RAPID_CROSSCHECK_MODE を明記) | |
| 10 | minor | fixed | `実装スクリプトを実行して Runner Result を出力する/tier-facade.md`(冪等性: 通常起動は上書き再実行、復元起動は exitcode.txt=2 `error: restored run already started ...`) | |
| 11 | minor | fixed | `execution-spec.json を確定保存する/tier-facade.md`(既存 JSON の run_id 不一致・slots 欠落を契約 exit_codes 2 に寄せ、6 は lock タイムアウト・書き込み失敗のみと明記) | |
| 12 | minor | fixed | `切り替えた運用モードで業務ジョブを実行する/_model-summary.yaml`(`AlertMail` を `tier: tier-ops` に変更し「参照のみ」の note を追加) | |
| 13 | minor | fixed | `slot ごとのジョブマップを定義する/_model-summary.yaml`(`ApplicationDocument` に「参照のみ(R(間接))。relay-gate は読み込まない」の note を追加。削除はせず RDRA 情報との対応を残す) | |
| 14 | minor | fixed | `ジョブマップで JOB_ID から実行先を解決する/tier-facade.md`(引数表に `--help` 行を追加)、`slot runner の実体スクリプトを割り当てる/_api-summary.yaml`(`validate-config.sh` の options に `--feature-flag`(required)/ `--verbose` を列挙) | |
| 15 | minor | deferred | (なし) | `_cross-cutting/datastore/rdb-schema.yaml` は所有範囲外。「契約側への要求」に転記 |

## 追加対応(レビュー外の指示分)

| 項目 | 対応 | 変更ファイル |
|---|---|---|
| step4-review-datastore.md #1(`finished_at` 未追従) | fixed(上記 #1 / #2 と同一修正) | 同上 4 ファイル |
| uc-dependencies.md 暗黙参照 #5 | fixed | `切り替えた運用モードで業務ジョブを実行する/_api-summary.yaml` に `validate-config.sh`(tier-facade)/ `hang-detector.sh`(tier-ops)を `role: uses` で追加 |
| traceability パターン A: 適用構成文書.DB セグメント構成 / 文書版 | fixed | `slot runner の実体スクリプトを割り当てる/spec.md` 関連 RDRA モデル表の「適用構成文書」行に 情報.tsv の全 8 属性を列挙。DB 接続設定の根拠として「DB セグメント構成」を参照、「文書版」は適用構成文書側で版管理と明記 |
| traceability パターン A: 実行ログ.出力日時 | fixed | 実行ログ出力の記述がある tier-facade.md 8 件(slot 起動 / Runner Result / foreground 中継 / execution-spec 保存 / ジョブマップ解決 / 実行結果確認 / 切り替えた運用モード / feature flag)に ui-design.md のログ行形式 `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` と「出力日時 = UTC 時刻列」の対応を 1 行追記 |

## 契約側への要求(別担当)

| # | 契約ファイル | 要求 | 根拠 |
|---|---|---|---|
| C-1 | `cli-command-contract.yaml` `commands[validate-config.sh].used_by_ucs` / `commands[hang-detector.sh].used_by_ucs` | UC「適用構成業務/適用構成定義フロー/切り替えた運用モードで業務ジョブを実行する」を追加(UC 側は uses を宣言済み) | uc-dependencies.md 暗黙参照 #5 |
| C-2 | `rdb-schema.yaml` `comparison_results.comparison_type` description | 「table / file / full」→「クロスチェックジョブマップの comparison_type(job / full。速報は job)」 | G1 #15(所有範囲外のため転記) |
| C-3 | `cli-command-contract.yaml` runner IF `exit_codes` | 変更不要。UC「execution-spec.json を確定保存する」を契約の 2 / 6 の区分に合わせた(#11 は UC 側で解消) | 参考 |

## 検証結果

- `validateApiSummary.js` / `validateModelSummary.js`: 所有範囲 10 UC すべて PASS
- `npx md-mermaid-lint`: 変更した md 13 ファイル OK
