# round-1 resolution — G1(実装切替ジョブ実行フロー / 適用構成定義フロー(feature flag・slot runner・ジョブマップ・運用モード))

- 所有範囲: `実装切替業務/実装切替ジョブ実行フロー/*`、`適用構成業務/適用構成定義フロー/{feature flag を設定する, slot runner の実体スクリプトを割り当てる, slot ごとのジョブマップを定義する, 切り替えた運用モードで業務ジョブを実行する}`
- 検証: 変更 md 16 件 `md-mermaid-lint` PASS、変更 UC dir 10 件 `validateApiSummary.js` / `validateModelSummary.js` PASS
- パス略記: S=slot 実行モードを選択して runner を起動する / R=実装スクリプトを実行して Runner Result を出力する / M=foreground slot の結果をジョブスケジューラへ中継する / J=ジョブマップで JOB_ID から実行先を解決する / X=execution-spec.json を確定保存する / C=業務ジョブの実行結果を確認する / FF=feature flag を設定する / SR=slot runner の実体スクリプトを割り当てる / JM=slot ごとのジョブマップを定義する / OM=切り替えた運用モードで業務ジョブを実行する

| finding id | severity | resolution | 変更ファイル |
|---|---|---|---|
| F-004 | major | fixed: facade は runner 起動「前」に slot_executions を pid=NULL・status=RUNNING で INSERT、起動後に pid UPDATE(sequence / データフロー表 / 状態遷移 / 起動順序 step 3-4 / pid 列 null 可 / _model-summary に UPDATE 2 種)。runner 起動失敗時は該当行を FAILED にベストエフォート更新(終了コード 6 は不変)。Runner Result UC は終端 UPDATE 0 件時に実行ログ `ERROR slot_execution update matched no row` を残し INSERT せず終了コード不変。tier BDD を両 UC に追加 | S/spec.md, S/tier-facade.md, S/_model-summary.yaml, S/_api-summary.yaml, R/spec.md, R/tier-facade.md, R/_model-summary.yaml |
| F-005 | major | fixed: facade exit 6 を「foreground 待機前の管理 DB 書き込み失敗(parallel_runs INSERT / STARTED→RUNNING UPDATE、rapid_runs INSERT、slot_executions INSERT / pid UPDATE)」に限定し、「中継後の COMPLETED UPDATE 失敗は終了コードに反映しない(実行ログ ERROR)」を S / M の tier md と _api-summary に明記 | S/tier-facade.md, S/_api-summary.yaml, M/tier-facade.md, M/_api-summary.yaml |
| F-006 | major | fixed: S / R の tier md に「読み込む設定(管理 DB 接続)」節を追加(on のとき `$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` の RAPID_DB_CONN_REF。不在・欠落は終了コード 2 / runner は exitcode.txt=2。文言 `error: config file not found path=...` / `error: RAPID_DB_CONN_REF required path=...`)。runner へ引き継ぐ環境変数を RELAY_GATE_CONFIG_DIR / RELAY_GATE_ARTIFACT_ROOT / RELAY_GATE_LOG_DIR / RAPID_CROSSCHECK_MODE の 4 つに統一(SR tier の RELAY_GATE_HOME は引き継ぎ対象から外し、runner 実体が自身のパスから導出と注記)。tier BDD 追加。完了通知 UC(tier-rapid-crosscheck)は所有範囲外 | S/tier-facade.md, S/_api-summary.yaml, R/tier-facade.md, R/_api-summary.yaml, SR/tier-facade.md |
| F-007 | major | no change needed(所有範囲内): 所有 UC の Given/Then に絶対時刻・乱数値を固定した検証は無い(`rg "現在時刻|RELAY_GATE_NOW"` 0 件。固定 run_id は入力値としてのみ使用)。RELAY_GATE_NOW の契約宣言は別担当 | — |
| F-013 | major | fixed: FF/spec.md E2E 正常系 3 本と FF/tier BDD 2 本の Given に「両 runner が --help で runner-if-version=1 を返す」「`<slot>-job-map.tsv` が存在する」「mode≠off の RUNNER 指定」を追加 | FF/spec.md, FF/tier-facade.md |
| F-014 | major | fixed: FF / JM / SR の _api-summary の validate-config.sh を契約に揃えた(stdout 12 キー固定順、`--feature-flag` / `--job-map` required: false + 排他注記、exit 2 に検証種別 0 個・複数指定を追記) | FF/_api-summary.yaml, JM/_api-summary.yaml, SR/_api-summary.yaml |
| F-015 | major | fixed(採用案): 定義元 UC(S)の tier md 実行ログ `feature flag loaded` 行に `operation_mode=parallel|green-only|next-parallel|custom` を追加し、spec.md 計算ルールに「運用モード名」を追加。OM tier md は「定義元は S」に書き換え。**契約側要求**: `config_files.feature-flag.env.derived` の「validate-config.sh の出力にのみ現れる」を「validate-config.sh の出力と facade.sh 実行ログ」に修正 | S/spec.md, S/tier-facade.md, OM/tier-facade.md |
| F-016 | major | fixed: SR/spec.md E2E「facade は設定された runner を runner IF で起動するだけである」の Given に BLUE_MODE=foreground BLUE_RUNNER=<スタブ> GREEN_MODE=background RAPID_CROSSCHECK_MODE=off、--help 応答、ジョブマップ行を追加 | SR/spec.md |
| F-023 | major | fixed(所有範囲 J): `error: option required option=--job-id` / 実行ログ `ERROR option required option=--job-id` に修正。_api-summary の exit 2 文言も定型文に揃えた。確報 UC(--catalog-version)は所有範囲外 | J/tier-facade.md, J/_api-summary.yaml |
| F-028 | minor | fixed(所有範囲): X/_api-summary と X/tier に exit 2(復元起動の spec 不一致)を追加、M / C の _api-summary に --help / --verbose を追加、S / R / J / SR の runner IF synopsis に [--help] を追加(J は options にも --help)、SR/_api-summary exit 2 に PARAM 併用を追記。完了通知 / 速報結果参照 / 通知メール受信 UC の型(number→integer)は所有範囲外 | X/_api-summary.yaml, X/tier-facade.md, M/_api-summary.yaml, C/_api-summary.yaml, S/_api-summary.yaml, R/_api-summary.yaml, J/_api-summary.yaml, SR/_api-summary.yaml |
| F-029 | minor | fixed: J/spec.md 異常系 2 本の When に --run-id を補完、R/spec.md「3 ファイルが揃う」の When に --job-id、X/tier Given にジョブマップ行(hang_detect_limit_minutes=60)、X/spec の両 slot 保存 Given に blue=0 / green=60、C/tier Scenario 1・2 のスタブが stderr.log / exitcode.txt を書くよう明記 | J/spec.md, R/spec.md, X/tier-facade.md, X/spec.md, C/tier-facade.md |
| F-032 | minor | 部分 fixed: `--help` 未応答時の `<slot>_runner_if_version` は `-` を SR tier / SR spec / FF tier / SR _api-summary に明記。**deferred**: 検証種別間のメッセージ共通形式(duplicate / header mismatch / column count)と `--crosscheck-job-map [<path>]` の値必須化は契約 `commands[validate-config.sh]` で形式を 1 つ決める必要があり別担当(契約)の決定待ち。決定後に JM tier の文言を追従する | SR/tier-facade.md, SR/spec.md, SR/_api-summary.yaml, FF/tier-facade.md |
| F-033 | minor | 対象外(クロスチェックのジョブマップと比較定義を定義する UC は所有範囲外) | — |
| F-034 | minor | fixed(所有範囲): JM/spec.md の SPEC-004-02 / SPEC-004-03、FF/spec.md の SPEC-005-04 に「定義側。AC の実行側は UC〈...〉の Scenario〈...〉で覆う」を注記。確報確認 / UC4 / 検証 / abort UC は所有範囲外 | JM/spec.md, FF/spec.md |

## 集計

- fixed: 11(F-004 / F-005 / F-006 / F-013 / F-014 / F-015 / F-016 / F-023 / F-028 / F-029 / F-034。所有範囲内の部分について)
- no change needed: 1(F-007。所有範囲内に該当箇所なし)
- deferred: 1(F-032 のメッセージ共通形式・値必須化。契約決定待ち)
- 対象外: 1(F-033)

## 契約側(別担当)への要求

1. F-015: `config_files.feature-flag.env.derived.operation_mode` の「validate-config.sh の出力にのみ現れる」を「validate-config.sh の出力と facade.sh 実行ログ `feature flag loaded` 行」に修正
2. F-005: `commands[facade.sh].exit_codes[6].condition` を「foreground 待機前の管理 DB 書き込み失敗(parallel_runs INSERT / STARTED→RUNNING UPDATE、rapid_runs INSERT、slot_executions INSERT / pid UPDATE)…」に限定し、「中継後の COMPLETED UPDATE 失敗は終了コードに反映しない」を追記
3. F-004: `commands[facade.sh]` の idempotency / 処理順に「slot_executions は runner 起動前に pid=NULL で INSERT、起動後に pid UPDATE」を反映(rdb-schema の pid nullable は既に整合)。runner IF 側に「slot_executions 終端 UPDATE 0 件は実行ログ ERROR、INSERT しない、終了コード不変」を追記
4. F-006: `commands[facade.sh].exit_codes[2].condition` と runner IF exit 2 に「on のとき rapid-crosscheck.env 不在・RAPID_DB_CONN_REF 欠落」を追記。runner へ引き継ぐ環境変数 4 つ(RELAY_GATE_CONFIG_DIR / RELAY_GATE_ARTIFACT_ROOT / RELAY_GATE_LOG_DIR / RAPID_CROSSCHECK_MODE)を `environment_variables` に明記(RELAY_GATE_HOME は引き継がない)
5. F-032: validate-config.sh の stderr 共通形式(duplicate / header mismatch / column count)を 1 つに決めて通知。JM tier を追従する
