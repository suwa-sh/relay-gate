# round-1 resolution(G2: 速報クロスチェックフロー + クロスチェックのジョブマップと比較定義を定義する)

所有範囲: `クロスチェック業務/速報クロスチェックフロー/` 配下全部、`適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/`。
契約(`_cross-cutting/`)は別担当のため触れていない。契約側への要求は末尾にまとめる。

パスは `E/クロスチェック業務/速報クロスチェックフロー/` を `R/`、`E/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/` を `C/` と略記する。

## 対応表

| finding id | severity | resolution | 変更内容 | 変更ファイル |
|---|---|---|---|---|
| F-003 | major | fixed | 通知失敗時の stderr.log 追記を撤回。通知失敗は実行ログ `WARN completion notice failed run_id=... role=... exit_code=N` のみ。stdout.log / stderr.log / exitcode.txt は変更しない旨と理由(foreground 応答を変えない・exitcode.txt は完了マーカー)を明記。復旧は同一引数の再実行(先勝ち)。BDD Then を「3 ファイルは通知前と同一」に変更 | `R/速報クロスチェック runner へ完了通知を送信する/spec.md`(分岐条件・E2E BDD)/ `tier-facade.md`(出力契約・復旧・tier BDD)/ `_api-summary.yaml`(runner stderr) |
| F-006 | major | fixed | 受信側 tier md に設定契約「`$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` の `RAPID_DB_CONN_REF` を読む。不在・欠落は `error: management db is not configured` で終了コード 2」を追加。終了コード表・stderr 一覧・tier BDD(RAPID_DB_CONN_REF 欠落 → 2)を追加 | `R/速報クロスチェック runner へ完了通知を送信する/tier-rapid-crosscheck.md` / `_api-summary.yaml`(stderr・exit 2 meaning) |
| F-007 | major | fixed(所有範囲内) | claim UC の「現在時刻が ... である」Given をテスト専用環境変数 `RELAY_GATE_NOW`(ISO 8601 UTC。本番未設定。設定時は now() の代わりに使う)に書き換え。計算ルールに「現在時刻(now)」行、tier md に環境変数節、_model-summary の `?` / lease_until 値に出所を追記。所有範囲内の他 UC は now 由来の絶対値を Then で固定しておらず(fixture 値のみ)変更不要 | `R/速報比較依頼を claim する/spec.md` / `tier-rapid-crosscheck.md` / `_model-summary.yaml` |
| F-017 | major | fixed | 比較ツール起動失敗(exec 不可)では comparison_results を INSERT しない(依頼は FAILED exit_code=6 error_summary=`launch failed`)。分岐条件一覧に「comparison_results の登録条件」行を追加、状態遷移表・処理フロー手順 5 / 7・エラー表・冪等性・sequence(起動失敗 alt)・BDD Then(E2E / tier。tier に起動失敗シナリオを追加)・_model-summary INSERT 条件(比較ツールが終了コードを返したときのみ)を明記 | `R/比較ツールでジョブ単位比較を実行して結果を登録する/spec.md` / `tier-rapid-crosscheck.md` / `_api-summary.yaml` / `_model-summary.yaml` |
| F-018 | major | fixed | worker は起動時に feature-flag.env の `RAPID_CROSSCHECK_MODE` を読み、off なら DB に接続せず `error: management db is not configured mode=off` で終了コード 3。on で rapid-crosscheck.env 不在 / `RAPID_DB_CONN_REF` 欠落は 2。設定ファイル節(読む順)・終了コード表(3 追加)・stderr・データモデル(feature-flag.env 参照)・sequence・分岐条件・E2E / tier BDD(off シナリオ追加、既存の欠落シナリオに on を明記)を修正。buc-spec の CRUD(feature flag 設定)と共有条件 / バリエーションの適用 UC に claim UC を追加 | `R/速報比較依頼を claim する/spec.md` / `tier-rapid-crosscheck.md` / `_api-summary.yaml`、`R/buc-spec.md` |
| F-019 | major | fixed | 出力契約に「comparison_results を作らないケース(比較定義なし・起動失敗)は `result_status=-` / `comparison_result_id=-`、終端 UPDATE 0 件(ABORTED 検出)は `request_status=ABORTED`」を追記。該当 BDD(比較定義なし / 起動失敗 / ABORTED。E2E と tier)の Then で stdout を検証 | `R/比較ツールでジョブ単位比較を実行して結果を登録する/spec.md` / `tier-rapid-crosscheck.md` / `_api-summary.yaml` |
| F-022 | major | fixed | `{catalog_path}` の置換先を「該当版だけを抜き出した `facade/<final_crosscheck_id>/final-crosscheck/input/target-catalog.tsv` の絶対パス(全版の元カタログではない。契約 external_interfaces が正)」に修正。tier-final-crosscheck.md にもプレースホルダ置換先を 1 行追加 | `C/tier-rapid-crosscheck.md` / `C/tier-final-crosscheck.md` |
| uc-dependencies 残件 (a) | — | fixed | `rapid-crosscheck-runner.sh` の定義元は完了通知 UC。依頼作成 UC の `_api-summary.yaml` を `role: uses` に変更し、invoked_by に定義元 UC を明記 | `R/両系成功時に速報比較依頼を作成する/_api-summary.yaml` |
| F-028 | minor | fixed(所有範囲内) | `--exit-code`(完了通知)/ `--limit`(結果参照)の型を number → integer(契約に合わせる)。tier md の引数表も同じく integer | `R/速報クロスチェック runner へ完了通知を送信する/_api-summary.yaml` / `tier-facade.md` / `tier-rapid-crosscheck.md`、`R/速報比較結果を参照する/_api-summary.yaml` / `tier-rapid-crosscheck.md` |
| F-032 | minor | deferred | `--crosscheck-job-map [<path>]` の値省略可否は契約 `option_style` / `commands[validate-config.sh]` の default の決め(契約 L885 は default を持つ)。契約側で「値必須 / 既定パスあり」のどちらかが確定してから tier md を追従させる。validate-config.sh のメッセージ形式統一・`<slot>_runner_if_version` は所有範囲外(tier-facade UC) | — |
| F-033 | minor | fixed | 異常系に Scenario「ヘッダー列が契約と異なる」(host 列混入 → 終了コード 2 で `error: header mismatch expected=... actual=...`)を追加し、分岐条件一覧「設定所有区分」行のダングリング参照を解消 | `C/spec.md` |
| F-034 | minor | fixed(所有範囲内: UC4 の部分のみ) | UC4 の E2E BDD(比較 OK / 比較 NG)の Then に依頼レコードの stdout / stderr 列の検証を追加(SPEC-005-03 AC1「stdout・stderr・exitcode と比較結果を登録する」を覆う)。定義側 UC の注記(SPEC-004-02)、確認 UC(SPEC-012-02 / SPEC-009-04)、Scenario タグの複数 SPEC 併記は所有範囲外 | `R/比較ツールでジョブ単位比較を実行して結果を登録する/spec.md` |
| F-035 | minor | fixed(所有範囲内) | `--show-output` の出力構造を data-visualization.md に合わせ「TSV の後に空行 1 行 → `--- stdout ---`」に統一し「仮採用」注記を削除。TSV の並び順を「compared_at 昇順、同値は comparison_result_id 昇順」に統一(_model-summary の ORDER BY も修正)。difference_count の FAILED 時 `-` を計算ルールに転記。ui-design.md の出力例(exit 3 → SUCCEEDED)の修正は契約側(_cross-cutting)に依頼 | `R/速報比較結果を参照する/spec.md` / `tier-rapid-crosscheck.md` / `_api-summary.yaml` / `_model-summary.yaml` |
| F-044 | minor | fixed | 「起動失敗は依頼を終端できないため 6」の根拠文を「起動失敗は依頼を FAILED で終端するが worker 側の実行エラーとして 6 を返す」に書き換え。依頼作成 UC の全 Given(E2E 7 本・tier 3 本)に parallel_runs 行(run_id, job_id=JOB001。FK 先・job_id の正本)を追加 | `R/比較ツールでジョブ単位比較を実行して結果を登録する/tier-rapid-crosscheck.md`、`R/両系成功時に速報比較依頼を作成する/spec.md` / `tier-rapid-crosscheck.md` |

集計: fixed 13(うち「所有範囲内のみ」4: F-007 / F-028 / F-034 / F-035)、deferred 1(F-032)。

所有範囲外のため未対応(他担当): F-002 / F-010 / F-011 / F-014 / F-016 / F-025 / F-038 / F-039 / F-040 / F-041 / F-046 / SR-001 / SR-002。

## 検証

- `npx md-mermaid-lint <file>`: 変更 md 15 ファイルすべて PASS
- `validateApiSummary.js` / `validateModelSummary.js`: 変更 UC 6 ディレクトリすべて PASS

## 契約側(_cross-cutting)への要求

| # | 要求 | 根拠 finding |
|---|---|---|
| 1 | `cli-command-contract.yaml` `rapid-crosscheck-runner.sh.notes[0]` の「stderr.log 末尾に warn: completion notice failed を残す」を「実行ログの WARN のみ。Runner Result 3 ファイルは変更しない」に修正 | F-003 |
| 2 | `cli-command-contract.yaml` `rapid-crosscheck-worker.sh`: exit_codes に 3(`RAPID_CROSSCHECK_MODE=off`。stderr `error: management db is not configured mode=off`)を追加、stderr にも追記。`config_files.feature-flag.env.readers` に rapid-crosscheck-worker.sh を追加 | F-018 |
| 3 | `cli-command-contract.yaml` `rapid-crosscheck-worker.sh.stdout` に `request_status=(SUCCEEDED\|FAILED\|ABORTED)` / `result_status=(OK\|NG\|FAILED\|-)` / `comparison_result_id=(8 hex\|-)` と、`-` / ABORTED を出す条件を追記 | F-019 |
| 4 | `cli-command-contract.yaml` `environment_variables` にテスト専用 `RELAY_GATE_NOW`(ISO 8601 UTC。本番未設定。設定時は now() の代わりに使う)を宣言(claim UC の tier md は「契約の environment_variables が正」と参照している) | F-007 |
| 5 | `ui-design.md` の rapid-crosscheck-result.sh 出力例(exit_code=3 なのに request_status=SUCCEEDED)を `request_status=FAILED` に修正 | F-035 |
| 6 | `validate-config.sh` の `--crosscheck-job-map` / `--target-catalog` の値省略可否(default の有無)を契約で確定(確定後に `C/tier-rapid-crosscheck.md` を追従させる) | F-032 |
