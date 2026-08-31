# Step3 Round 2 レビュー対応記録(G2: 速報クロスチェックフロー 5 UC + クロスチェックのジョブマップと比較定義を定義する)

- 対象レビュー: `step3-round-2-G2.md`
- 所有範囲: `クロスチェック業務/速報クロスチェックフロー/` 配下(5 UC + buc-spec.md)、`適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/` 配下
- 所有範囲外(`_cross-cutting/`、他 UC)は編集していない。契約側に必要な変更は末尾「契約側への要求」に列挙
- パスは E = `docs/specs/events/20260830_202851_spec_generation` からの相対。UC 名は略記(通知 UC = 速報クロスチェック runner へ完了通知を送信する / 依頼作成 UC = 両系成功時に速報比較依頼を作成する / claim UC = 速報比較依頼を claim する / 比較 UC = 比較ツールでジョブ単位比較を実行して結果を登録する / 参照 UC = 速報比較結果を参照する / 設定 UC = クロスチェックのジョブマップと比較定義を定義する)

## 指摘別の対応

| # | severity | 対応 | 変更ファイル | 理由・内容 |
|---|---|---|---|---|
| 1 | major | fixed | 通知 UC/tier-facade.md, spec.md, _api-summary.yaml | 確定決定に従い「通知失敗時の復旧」を新設。slot runner は stderr.log 末尾に `WARN rapid crosscheck notify failed ...` を残し、終了コードは exitcode.txt のまま。復旧手段は「運用者が同じ引数で rapid-crosscheck-runner.sh を再実行(先勝ちの冪等)」に統一し、background-rerun / ジョブスケジューラ再実行は新 run になるため復旧手段ではない旨を明記。自動検知はスコープ外とし「exitcode.txt=0 の slot の通知失敗は自動検知されない」を制約として記載。spec.md の分岐条件・BDD(「通知失敗を運用者が同じ引数の再実行で復旧する」を E2E / tier 両方に追加)を同じ内容にした |
| 2 | major | fixed | 比較 UC/spec.md, tier-rapid-crosscheck.md, _model-summary.yaml | 比較定義が無い job_id は comparison_results を INSERT せず、依頼を FAILED(exit_code=6, error_summary=`comparison definition not found job_id=...`)で終端する方式に確定。処理フロー(Note で明記)・分岐条件・状態遷移一覧・E2E BDD の Then(「行は無く」)・tier 処理フロー手順 2 / エラー表 / 冪等性・tier BDD 追加・_model-summary の comparison_type value を一致させた |
| 3 | major | fixed | claim UC/tier-rapid-crosscheck.md, spec.md, _model-summary.yaml, _api-summary.yaml、参照 UC/tier-rapid-crosscheck.md | 確定決定に従い `$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` を設定ファイルとして定義(`RAPID_DB_CONN_REF` 必須 / `RAPID_LEASE_SEC` 既定 600 / `RAPID_POLL_INTERVAL_SEC` 既定 30。HANG_DB_CONN_REF と同じ参照名を指してよい)。欠落時は `error: management db is not configured` で終了コード 2(BDD 追加)。参照 UC にも接続先の所在を追記。契約側の config_files への追加は別担当(下記「契約側への要求」) |
| 4 | minor | fixed | 通知 UC/tier-rapid-crosscheck.md, _api-summary.yaml | 受信 UC の stdout を 4 行(run_id / job_id / role / slot_status)に揃え、続く 3 行は依頼作成 UC が出す旨を注記。契約の 7 行と 1 つの stdout として整合 |
| 5 | minor | fixed | 通知 UC/spec.md | presentation の検証を「スキーム `file://` と絶対パス形式。存在確認はしない」に修正(tier md の方針に統一) |
| 6 | minor | fixed | 通知 UC/tier-rapid-crosscheck.md, spec.md, tier-facade.md, _api-summary.yaml | 確定決定どおり先勝ち(同一 run_id + role の 2 回目以降は既存値を変更せず終了コード 0)に統一。契約 stderr に無い `warn: completion already registered` は削除し、実行ログ INFO に置換。tier BDD「再通知は既存値を保持して 0 で終了する」を追加 |
| 7 | minor | fixed | 通知 UC/_api-summary.yaml | `$BLUE_RUNNER / $GREEN_RUNNER` の stdout / stderr を「なし(実装の出力は stdout.log / stderr.log へ)」に修正。通知失敗時の stderr.log 末尾 WARN を注記 |
| 8 | minor | fixed | 通知 UC/spec.md | Given を「rapid_runs の UPDATE が SQL エラーになる」に変更し、Then の `error: management db update failed ...` が一意に決まるようにした |
| 9 | minor | fixed | 依頼作成 UC/spec.md | 処理フローの `BEGIN` を「受信 UC で開始済みのトランザクションを継続。BEGIN は発行しない」に変更。データフロー図と gateway 行も同じ表現にした。受信 UC 側は既に「BEGIN(dispatcher の判定・INSERT と同一トランザクション)」「依頼作成 UC が COMMIT する」と対になっているため変更なし |
| 10 | minor | fixed | 依頼作成 UC/_model-summary.yaml | job_id の value を「parallel_runs.job_id(通知の --job-id は照合のみ。不一致は warn)」に修正 |
| 11 | minor | out-of-scope | — | `_cross-cutting/api/asyncapi.yaml` は所有範囲外。UC 側は正のため変更なし(契約側への要求に記載) |
| 12 | minor | fixed | 比較 UC/spec.md | gateway の変換内容とデータフロー図を `{blue}` / `{green}` プレースホルダ置換に修正 |
| 13 | minor | fixed | 比較 UC/spec.md, tier-rapid-crosscheck.md, _model-summary.yaml | comparison_result_id を「8 桁 hex 乱数(主キー。全体で一意。衝突時は取り直す)」に修正し契約 shared_rules と揃えた |
| 14 | minor | fixed | 比較 UC/spec.md, tier-rapid-crosscheck.md | 終端 UPDATE が 0 行(ABORTED 済み等)のとき comparison_results を INSERT せず ROLLBACK、実行ログ `WARN request already terminal run_id=... status=...`、終了コード 0(成果物は残す)を追記。E2E / tier BDD を追加 |
| 15 | minor | out-of-scope | — | `_cross-cutting/datastore/rdb-schema.yaml` は所有範囲外。UC 側(`job` / `full`)は正のため変更なし(契約側への要求に記載) |
| 16 | minor | fixed | 設定 UC/spec.md | Given を「前シナリオの crosscheck-job-map.tsv の 6 行目(JOB002 行)を JOB001 行の複製に置き換える」「前シナリオの target-catalog.tsv の 3 行目(file 行)の target_type を view に変える」に具体化 |
| 17 | minor | out-of-scope | — | 実行復旧業務/速報比較依頼だけを新規作成する は他担当 |
| 18 | minor | out-of-scope | — | 実装切替業務/実装スクリプトを実行して Runner Result を出力する は他担当 |

集計: fixed 14(major 3 / minor 11)、deferred 0、out-of-scope 4(#11, #15, #17, #18)

## 指摘外の追加修正

| 項目 | 変更ファイル | 内容 |
|---|---|---|
| 実行ログ行形式の明記 | 通知 UC/tier-facade.md, tier-rapid-crosscheck.md、依頼作成 UC/tier-rapid-crosscheck.md、claim UC/tier-rapid-crosscheck.md、比較 UC/tier-rapid-crosscheck.md、参照 UC/tier-rapid-crosscheck.md | 実行ログの記述がある tier md すべてに「行形式は `_cross-cutting/ux-ui/ui-design.md` の `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従い、情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する」を追記。設定 UC の tier md は実行ログ出力の記述が無いため対象外 |
| uc-dependencies.md「補足: 宣言の不一致」d | 参照 UC/spec.md | docs/usdm/latest/requirements.yaml で確認: SPEC-011-03 は final_crosscheck_request(確報)の保持項目、SPEC-011-02 が rapid_run / rapid_crosscheck_request / comparison_result の保持項目。関連 USDM と BDD シナリオ名を SPEC-011-02 に修正 |
| env キー名 | claim UC/spec.md, tier-rapid-crosscheck.md, _model-summary.yaml | 確定決定のキー名 `RAPID_LEASE_SEC` / `RAPID_POLL_INTERVAL_SEC` に統一(旧 `RAPID_LEASE_MINUTES` / `RAPID_POLL_INTERVAL_SECONDS` は UC 側から削除) |

## 契約側への要求(所有範囲外。別担当)

| # | 対象 | 要求 |
|---|---|---|
| C1 | cli-command-contract.yaml `config_files` | `rapid-crosscheck.env`(`$RELAY_GATE_CONFIG_DIR`)を追加: `RAPID_DB_CONN_REF`(on のとき必須。参照名のみ。HANG_DB_CONN_REF と同じ参照名を指してよい)/ `RAPID_LEASE_SEC`(既定 600)/ `RAPID_POLL_INTERVAL_SEC`(既定 30)。readers は rapid-crosscheck-runner.sh / rapid-crosscheck-worker.sh / rapid-crosscheck-result.sh。現行の「速報 worker 設定(RAPID_* env)」(RAPID_LEASE_MINUTES / RAPID_POLL_INTERVAL_SECONDS。L142-143 の shared 値と L1123-1139)を置き換える。`RELAY_GATE_CONFIG_DIR` の purpose にも追記 |
| C2 | cli-command-contract.yaml / asyncapi.yaml / rdb-schema.yaml の `RAPID_LEASE_MINUTES` 参照(rdb-schema L275、asyncapi L56-57 / L415) | `RAPID_LEASE_SEC`(既定 600 秒 = 10 分)へ表記統一 |
| C3 | cli-command-contract.yaml `rapid-crosscheck-runner.sh` idempotency | 「同値で更新するだけ」→「先勝ち: 同一 run_id + role の 2 回目以降は `WHERE {role}_status IS NULL` で 0 行となり、既存値を変更せず終了コード 0」に変更。asyncapi.yaml `slot-completed` の「再通知は同値更新で 0」も同じ表現に |
| C4 | cli-command-contract.yaml `rapid-crosscheck-worker.sh` stderr / exit_codes | stderr に `error: management db is not configured`(rapid-crosscheck.env 不在・RAPID_DB_CONN_REF 欠落。終了コード 2)を追加。`comparison_results` の INSERT を「比較定義行あり、かつ終端 UPDATE 1 行のときのみ」と明記(比較定義なし・ABORTED 済みは INSERT しない) |
| C5 | cli-command-contract.yaml `$BLUE_RUNNER / $GREEN_RUNNER`、artifact_layout | 通知失敗時に stderr.log 末尾へ `WARN rapid crosscheck notify failed exit_code=... run_id=... role=...` を 1 行追記する旨を artifact_layout(「relay-gate 自身のエラーは末尾に 1 行」)と runner の条件に追加。復旧手段は「運用者が同じ引数で rapid-crosscheck-runner.sh を再実行」 |
| C6 | asyncapi.yaml `schemas.RapidCrosscheckRequest`(指摘 #11) | blue_artifact_uri / green_artifact_uri / parent_run_id を削除し、rapid_runs / parallel_runs.parent_run_id 参照と記載 |
| C7 | rdb-schema.yaml `comparison_results.comparison_type.description`(指摘 #15) | 「例: table / file / full」→「クロスチェックジョブマップの comparison_type(速報は job)」 |
| C8 | rdra-feedback / todo | 通知失敗の自動検知(exitcode.txt=0 の slot の通知失敗は hang-detector が検知しない)をスコープ外として記録 |

## 検証結果

- `npx md-mermaid-lint`: 変更した md 12 ファイル → All Mermaid diagrams are syntactically correct
- `validateApiSummary.js` / `validateModelSummary.js`: 6 UC ディレクトリすべて PASS
