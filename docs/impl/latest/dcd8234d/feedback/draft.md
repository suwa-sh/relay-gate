---
schema_version: distillery.feedback-request/v1
feedback_id: 20261010_104636_impl_feedback_dcd8234d
created_at: 2026-10-10T10:46:36+09:00
source: distillery-impl
uc_id: dcd8234d
---

# 実装からの変更要求

## CR-dcd8234d-007: クロスチェックの比較定義と依頼レコードを元の構想に戻す(簡素化)

- severity: spec-gap
- related_ids: [SPEC-004-01, SPEC-004-04, SPEC-005-01, SPEC-005-02, SPEC-005-03, SPEC-006-01, SPEC-006-02, SPEC-006-04, SPEC-007-02, SPEC-011-02, SPEC-011-03, SPEC-013-01, REQ-004, REQ-005, REQ-006, REQ-007, REQ-011, REQ-013]
- related_files: [docs/specs/latest/_inference.md, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml, docs/usdm/latest/requirements.yaml, docs/rdra/latest/情報.tsv, docs/rdra/latest/バリエーション.tsv, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-rapid-crosscheck.md, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-final-crosscheck.md, docs/specs/latest/クロスチェック業務/速報クロスチェックフロー/速報クロスチェック runner へ完了通知を送信する/spec.md, docs/specs/latest/クロスチェック業務/速報クロスチェックフロー/両系成功時に速報比較依頼を作成する/spec.md, docs/specs/latest/クロスチェック業務/速報クロスチェックフロー/速報比較依頼を claim する/spec.md, docs/specs/latest/クロスチェック業務/速報クロスチェックフロー/比較ツールでジョブ単位比較を実行して結果を登録する/spec.md, docs/specs/latest/クロスチェック業務/速報クロスチェックフロー/速報比較結果を参照する/spec.md, docs/specs/latest/クロスチェック業務/確報クロスチェックフロー/確報比較依頼を登録して終端状態まで待機する/spec.md, docs/specs/latest/クロスチェック業務/確報クロスチェックフロー/確報比較依頼を claim する/spec.md, docs/specs/latest/クロスチェック業務/確報クロスチェックフロー/比較ツールで日次全量比較を実行して結果を保存する/spec.md, docs/specs/latest/クロスチェック業務/確報クロスチェックフロー/保存済みの確報結果をジョブスケジューラへ返す/spec.md, docs/specs/latest/実行復旧業務/background 側リランフロー/速報比較依頼だけを新規作成する/spec.md]

### 観測した事実

- 元の方針資料(`tmp/RelayGateのしくみ.md`)が定めるクロスチェックの構成は次のとおりである。
  - 42 行目: 「比較対象の定義は、適用側で定義します」。relay-gate は比較対象の一覧を持たない。
  - 261 行目(確報の C1 Context): 「worker は起動した実装の `stdout`、`stderr`、`exitcode` を依頼レコードへ保存します。チェック結果、差分件数、レポート URI などをジョブスケジューラへの応答の連携データとして追加しません」。
  - 595〜625 行目(状態と運用): 「worker は終了時に `stdout`、`stderr`、`exitcode` を依頼へ保存します。`exitcode = 0` なら `SUCCEEDED`、非 0 または実行エラーなら `FAILED` とします」。確報は保存した exitcode をそのままジョブスケジューラへ中継し、速報はジョブスケジューラへ返さない。
  - `tmp/RelayGateの利用イメージ.md` 326 行目: 「rapid クロスチェックと final クロスチェックは、同じ比較ツールの収集・比較パターンを使用します。違いは、対象テーブルと対象ファイルの量です」。
- 利用者がレビュー対話(2026-10-10、`docs/impl/latest/dcd8234d/review/review-notes.md` の第 2 回の節)で示した元の構想と想定環境は次のとおりである。
  - 構成は「blue / green runner → DB ← worker → 比較ツール」(速報)と「確報 runner → DB ← worker → 比較ツール」(確報)。速報はジョブ ID を渡し、確報はパラメータなしで起動する。worker は任意の比較コマンドを 1 つ定義でき、速報はそのパラメータを動的に渡せる。
  - runner と worker は別ネットワークセグメントで動く。worker はファイルパスを渡されても読めない。worker に必要な情報は DB の依頼レコードに含める。
- 現在の仕様は、方針資料に無い次の構造を持つ。いずれも仕様策定フェーズの推論で、`docs/specs/latest/_inference.md` の「5: 設定ファイルの形式」は「仮採用」と記す。本 UC の確報ティア仕様も設定契約の所在を「`_inference.md` #5 仮採用」と注記し、速報ティア仕様も予約行の compare_options を「仮採用: 確報比較ツールへの引数の渡し方は方針資料に定めが無いため」と注記する。
  - 比較定義 CSV(`crosscheck-job-map.csv`)のジョブ ID ごとの行構造(列: job_id / comparison_type / compare_targets / compare_command / compare_options / definition_version)と、ヘッダーコメントの宣言(`# exit_code_contract=` / `# target_catalog_path=` / `# catalog_version=`)。
  - 対象カタログ CSV(`target-catalog.csv`。列: catalog_version / target_type / target_identifier / compare_condition / business_date_handling)と、その検証(`validate-config.sh --target-catalog`)。
  - 速報の完了通知(`rapid-crosscheck-runner.sh --artifact-uri`)が成果物ディレクトリの URI を `rapid_runs.blue_artifact_uri / green_artifact_uri` に保存し、速報 worker が比較定義の `{blue}` / `{green}` を成果物 URI に置換して比較ツールへ渡す受け渡し。
  - 速報 worker が比較ツールの stdout / stderr / exitcode を `facade/<run_id>/rapid-crosscheck/` に 3 ファイルとして保存し、確報 worker が `facade/<final_crosscheck_id>/final-crosscheck/` に `input/target-catalog.csv` と 3 ファイルを保存する成果物契約。
  - 速報 worker が比較ツールの stdout から `difference_count=N` / `report_uri=...` を抽出して `comparison_results` に登録する比較結果レコード。
  - 確報 runner の引数(`--business-date` / `--catalog-version`)と、`final_crosscheck_requests.business_date / catalog_version` 列。
  - `validate-config.sh --crosscheck-job-map` の検証ルール群(宣言 3 件、列数 6 固定、プレースホルダ `{blue}` `{green}` 必須、`{catalog_version}` `{business_date}` 必須、comparison_type の列挙、予約行 `final-crosscheck` の最大 1 行、compare_targets の `catalog` 固定、対象カタログ参照の解決)。
- 本 UC の実装は、この推論どおりに比較定義 CSV と対象カタログの検証を実装し、独立検証(attempt 4)・UC BDD・ATDD を通した。速報ティア bats 106 件、確報ティア bats 57 件のほとんどが、上記の廃止対象の検証ルールを対象にしている。
- 利用者は第 1 回のレビュー対話で「確報は起動のみ」(案 A)を決め、第 2 回でそれをクロスチェック全体の簡素化に広げて確定した。

### 現在の仕様と問題

- 方針資料は「比較対象の定義は適用側」「worker は stdout / stderr / exitcode を依頼レコードへ保存する」「速報と確報は同じパターンで、違いは対象の量」と定める。現在の仕様は、relay-gate がジョブ ID ごとの比較定義と対象カタログを持ち、検証し、成果物の場所をファイルパスで比較ツールに配り、比較結果を抽出して別レコードに登録する。方針資料に無い責務が relay-gate 側に積み上がっている。
- 想定環境では runner と worker が別ネットワークセグメントで動くため、成果物ディレクトリの URI(`{blue}` / `{green}`、`artifact_uri`)を worker に渡しても worker は読めない。成果物パスの受け渡しと worker 側のファイル保存は、環境制約に合わない。
- 比較定義 CSV の行構造・対象カタログ・検証ルール群は、利用者から見て「複雑にし過ぎ」であり、適用側が本来持つべき比較対象の定義を relay-gate の設定ファイルに持ち込んでいる。
- `comparison_results` の `difference_count` / `report_uri` の抽出は、契約自身が「取得方法は比較ツール契約に依存。方針資料に定めが無い」と注記しており、比較ツール依存の推論である。
- 現在の仕様で廃止対象が分散している場所は次のとおりである。
  - CLI 契約(`cli-command-contract.yaml`): `validate-config.sh`(`--crosscheck-job-map` / `--target-catalog` と stdout の `target_catalog_path:` / `catalog_version=`)、`rapid-crosscheck-runner.sh`(`--artifact-uri`)、`rapid-crosscheck-worker.sh`(成果物 3 ファイル、`comparison_results` の登録、stdout の `result_status=` / `comparison_result_id=` / `artifact_dir:`、`comparison definition not found` の終端)、`rapid-crosscheck-result.sh`(比較結果 TSV)、`final-crosscheck-runner.sh`(`--business-date` / `--catalog-version`、`target_catalog_path declaration not found` / `catalog version not found` のエラー)、`final-crosscheck-worker.sh`(`input/target-catalog.csv` の抜き出し、`no catalog rows`、成果物保存)、`shared_rules`(`comparison_result_id`、`state_codes.comparison_result_status`)、`external_interfaces`(比較ツール 2 件の launch / stdout_stderr / result_registration)、`config_input_rules.scope`(CSV 4 ファイルの列挙)、`config_files`(`crosscheck-job-map.csv` の header_declarations と columns、`target-catalog.csv`)、`artifact_layout`(role=rapid-crosscheck の成果物、`facade/<final_crosscheck_id>/`、`artifact_uri`)。
  - RDB スキーマ(`rdb-schema.yaml`): `rapid_runs.blue_artifact_uri / green_artifact_uri`、`rapid_crosscheck_requests`(速報の起動に必要な値を持たない)、`comparison_results` テーブル全体、`final_crosscheck_requests.business_date / catalog_version` とそのユニーク制約の検討記録。
  - USDM: SPEC-004-01(所有者の表の「比較対象と対象カタログ」)、SPEC-004-04(クロスチェックジョブマップ・対象カタログの CSV)、SPEC-005-01(完了通知の「成果物ディレクトリまたは artifact_uri」)、SPEC-005-02(完了事実の「成果物 URI」)、SPEC-005-03(「job_id ごとの比較定義」「比較結果(comparison_result)を登録」)、SPEC-006-01(確報依頼の business_date / 対象カタログの版)、SPEC-006-02(「全テーブル・全ファイルの比較を起動」は残る)、SPEC-006-04(「対象カタログ」)、SPEC-007-02(「比較差分の詳細は comparison_result、stdout、stderr に保持」)、SPEC-011-02(rapid_run の artifact_uri、comparison_result の列)、SPEC-011-03(final_crosscheck_request の business_date / 対象カタログの版と紐付け)、SPEC-013-01(「比較対象と対象カタログはクロスチェックのジョブマップで適用側が定義」)。
  - RDRA 情報: 「比較定義」「クロスチェックジョブマップ」「対象カタログ」「完了通知」(成果物ディレクトリまたは artifact_uri)、「速報実行(rapid_run)」(artifact_uri)、「速報比較依頼(rapid_crosscheck_request)」、「比較結果(comparison_result)」、「確報比較依頼(final_crosscheck_request)」、「比較ツール実行結果」。RDRA バリエーション「比較種別」「対象カタログの対象種別」「比較結果ステータス」。
  - UC 仕様: 本 UC(spec.md / tier-rapid-crosscheck.md / tier-final-crosscheck.md)、速報クロスチェックフローの UC 5 件(完了通知の送信 / 両系成功時の依頼作成 / 依頼の claim / ジョブ単位比較の実行と結果登録 / 速報比較結果の参照)、確報クロスチェックフローの UC 4 件(依頼の登録と待機 / 依頼の claim / 日次全量比較の実行と結果保存 / 保存済み結果の返却)、background 側リランフローの UC「速報比較依頼だけを新規作成する」(元 run の `blue_artifact_uri / green_artifact_uri` を事前検証に使う)、background 実行監視フローの UC「background 実行の経過時間と終了状態を判定する」(`comparison_results` を SELECT する)。

### 変更してほしいこと

次の (a)〜(g) を仕様へ反映する。各項目に、変更する正本を挙げる。

1. **(a) worker に必要な情報は DB の依頼レコードに含める。** runner と worker は別ネットワークセグメントで動き、worker はファイルパスを読めないことを前提として仕様に明記する。比較ツールへ渡す値は依頼レコードの値だけとし、ファイルパス(成果物 URI・対象カタログのパス)を渡さない。
   - 正本: 本 UC の spec.md、速報 worker の UC「比較ツールでジョブ単位比較を実行して結果を登録する」、確報 worker の UC「比較ツールで日次全量比較を実行して結果を保存する」、CLI 契約 `external_interfaces` の比較ツール 2 件。
2. **(b) 比較ツールの起動コマンドは、速報・確報それぞれ設定に 1 行。**
   - 速報の起動コマンドは 1 行の文字列。プレースホルダは依頼レコードの値だけで、`{job_id}` を必須、`{run_id}` / `{params}` / `{blue_exit_code}` / `{green_exit_code}` を任意とする。worker は依頼レコードの値で置換して起動する。
   - 確報の起動コマンドは 1 行の文字列。プレースホルダは無い。確報 runner は引数なしで起動されるだけで、worker はコマンドをそのまま起動する。
   - 設定の置き場(ファイル名・キー名)は仕様側で決める。推奨は、既存の `rapid-crosscheck.env` と `final-crosscheck.env` にキーを 1 つずつ追加する案である(速報・確報の worker がすでに読む設定ファイルで、読み手・所有者が同じ。CSV 解析を必要としない)。別案は `crosscheck-job-map.csv` を速報・確報の 2 行に縮小する案だが、ジョブ ID ごとの行構造が無くなった後に CSV を残す理由が無い。
   - ジョブ ID ごとの比較定義が無くなるため、「比較定義が無い job_id」の扱い(`comparison definition not found` で FAILED)は廃止し、起動失敗(`launch failed`)だけを残す。
   - 正本: CLI 契約 `config_files`(`crosscheck-job-map.csv` の行構造・header_declarations を廃止し、置き場に合わせて設定を定義)、`config_input_rules.scope`(CSV 4 ファイル・env 4 ファイルの列挙を更新)、`external_interfaces` の比較ツール 2 件の launch、`rapid-crosscheck-worker.sh` / `final-crosscheck-worker.sh`、USDM SPEC-004-01 / SPEC-005-03 / SPEC-013-01、RDRA 情報「比較定義」「クロスチェックジョブマップ」、本 UC の spec.md / tier-rapid-crosscheck.md。
3. **(c) 完了通知で DB に入れる値は run_id / job_id / exit_code。** `rapid-crosscheck-runner.sh` の `--artifact-uri` と `rapid_runs.blue_artifact_uri / green_artifact_uri` を廃止する。速報の依頼レコードは、起動コマンドの置換に必要な run_id / job_id / parameters / blue と green の exit_code を持つ(列を `rapid_crosscheck_requests` に持つか、同一トランザクションで参照できる `rapid_runs` / `parallel_runs` の列から引くかは仕様側で決める。worker が DB だけで起動値を揃えられればよい)。
   - 正本: CLI 契約 `rapid-crosscheck-runner.sh`(options / idempotency / 復旧時の同一引数)、`artifact_layout.artifact_uri`、RDB スキーマ `rapid_runs` / `rapid_crosscheck_requests`、USDM SPEC-005-01 / SPEC-005-02 / SPEC-011-02、RDRA 情報「完了通知」「速報実行(rapid_run)」「速報比較依頼(rapid_crosscheck_request)」、UC「速報クロスチェック runner へ完了通知を送信する」「両系成功時に速報比較依頼を作成する」「速報比較依頼だけを新規作成する」(事前検証から成果物 URI の存在確認を外し、新しい依頼には元の依頼の job_id / parameters / exit_code を引き継ぐ)。
4. **(d) worker の結果保存は依頼レコードの stdout / stderr / exit_code 列だけ。** 速報 worker の `facade/<run_id>/rapid-crosscheck/` と確報 worker の `facade/<final_crosscheck_id>/final-crosscheck/` への 3 ファイル保存を廃止する。状態は exit_code 0 → SUCCEEDED、非 0 または起動失敗 → FAILED とする(方針資料 595〜625 行目のとおり。現在の SPEC-006-02 / SPEC-007-01 と同じ)。
   - 正本: CLI 契約 `rapid-crosscheck-worker.sh`(stdout の `artifact_dir:` 行、成果物 3 ファイル、`started-at.txt`)、`final-crosscheck-worker.sh`(`artifact dir is not writable`、成果物保存)、`artifact_layout`(role=rapid-crosscheck の tree、`facade/<final_crosscheck_id>/`、files の writer / readers から両 worker を外す)、USDM SPEC-005-03 / SPEC-006-02、RDRA 情報「比較ツール実行結果」、速報・確報の worker の UC 2 件。ハング検知が速報比較依頼を判定する材料(依頼の status / started_at / exit_code)は DB のままで変わらない。
5. **(e) 速報の比較結果レコードを廃止し、標準出力をそのまま保存する。** `comparison_results` テーブルと、stdout からの `difference_count` / `report_uri` の抽出を廃止する。速報比較の結果は依頼レコードの stdout / stderr / exit_code で参照する。`rapid-crosscheck-result.sh` は依頼レコードの固定行と `--show-output` の本文だけを出し、比較結果 TSV を出さない。
   - 正本: RDB スキーマ `comparison_results`(テーブル削除。`used_by` の 3 UC を更新)、CLI 契約 `shared_rules.comparison_result_id` / `state_codes.comparison_result_status`、`rapid-crosscheck-worker.sh`(stdout の `result_status=` / `comparison_result_id=`、条件「比較結果の登録条件」)、`rapid-crosscheck-result.sh`(stdout の TSV と `--limit`)、`external_interfaces` の速報比較ツールの result_registration、USDM SPEC-005-03 / SPEC-007-02 / SPEC-011-02、RDRA 情報「比較結果(comparison_result)」とバリエーション「比較結果ステータス」、UC「速報比較結果を参照する」「background 実行の経過時間と終了状態を判定する」(比較異常の判定を依頼の status / exit_code だけで行う)。
6. **(f) 確報の依頼レコードは識別子・状態・時刻・結果だけ。** `final_crosscheck_requests` から business_date / catalog_version を削除し、final_crosscheck_id / status / worker_id / lease_until / requested_at / started_at / completed_at / exit_code / stdout / stderr / error_summary だけにする。`final-crosscheck-runner.sh` は引数なし(`--verbose` / `--help` のみ)で依頼を 1 件登録し、終端まで polling して、保存された stdout / stderr / exit_code をそのままジョブスケジューラへ返す(現在の SPEC-006-03 のまま)。
   - 正本: RDB スキーマ `final_crosscheck_requests`(列削除とユニーク制約の検討記録の整理)、CLI 契約 `final-crosscheck-runner.sh`(synopsis / options / stderr / exit_codes の条件 / idempotency)、`shared_rules.final_crosscheck_id`、USDM SPEC-006-01 / SPEC-006-04 / SPEC-011-03、RDRA 情報「確報比較依頼(final_crosscheck_request)」、確報クロスチェックフローの UC 4 件。
7. **(g) 廃止と、残す検証 2 点。** 次を仕様・契約・スキーマ・USDM・RDRA から削除する: ジョブ ID ごとの比較定義 CSV の行構造、比較対象(compare_targets)と定義版(definition_version)の列、comparison_type の列、対象カタログ(`target-catalog.csv`、`validate-config.sh --target-catalog`、RDRA 情報「対象カタログ」、バリエーション「対象カタログの対象種別」「比較種別」)、`{blue}` / `{green}` / `{catalog_path}` / `{catalog_version}` / `{business_date}` のプレースホルダ、worker のファイル保存、現在の検証ルール群。
   - 残す検証は 2 点だけにする: 「起動コマンドのコマンド部分が絶対パスで、存在し、実行可能である」「速報の起動コマンドに `{job_id}` が含まれる」。検証はコマンド部分(先頭の語)に対して行い、引数部分の内容は検査しない。
   - 残す検証 2 点の違反文言を CLI 契約に明記する。推奨は、置き場を env にする場合に既存の `feature-flag.env` の文言形式に揃える案である: 絶対パスでない `error: path is not absolute key=<KEY> path=...`、存在しない・実行不可 `error: file not executable key=<KEY> path=...`、`{job_id}` 欠落は `error: placeholder {job_id} is missing key=<KEY> value=...` のような 1 文言(文言は仕様側で確定する)。実装が補っていた `compare_command is not absolute` / `compare_targets is not catalog` / `compare_options is missing {blue} or {green}` の文言は、対象の列が無くなるため廃止する。
   - `validate-config.sh` の検証種別は、`--crosscheck-job-map` / `--target-catalog` を廃止し、速報・確報の起動コマンドの設定を検証する種別に置き換える(置き場が env なら、そのファイルを検証する種別。stdout の固定行もそれに合わせる)。
   - 正本: CLI 契約 `validate-config.sh`(synopsis / options / tier_note / stdout / stderr の例)、`config_files`、本 UC の tier-rapid-crosscheck.md(検証ルール一覧と BDD)。
8. **本 UC の範囲の縮小。** 本 UC「クロスチェックのジョブマップと比較定義を定義する」は「速報の起動コマンド 1 行の設定とその検証」だけを対象にし、`tier-final-crosscheck.md` を削除する。確報の起動コマンド 1 行の設定とその検証は、確報クロスチェックフローの UC(推奨は「比較ツールで日次全量比較を実行して結果を保存する」。worker が読む設定であるため)に置く。UC 名の見直しは任意とする。
9. **推論記録と方針資料の整合。** `_inference.md` の「5: 設定ファイルの形式」の仮採用(クロスチェックジョブマップ / 対象カタログ)を、利用者決定で簡素化した旨に更新する。方針資料側(`tmp/RelayGateのしくみ.md` の確報依頼データ項目 business_date / 対象カタログの版、所有者の表「比較対象と対象カタログ: クロスチェックの job map」、rapid_run の artifact_uri)は、利用者が方針資料を更新してそろえる。

### 完了条件

- 仕様・契約・スキーマ・USDM・RDRA のどこにも、ジョブ ID ごとの比較定義 CSV、対象カタログ、`{blue}` / `{green}` の成果物パス受け渡し、worker の成果物ファイル保存、`comparison_results`、確報依頼の business_date / catalog_version が無い。
- 速報・確報の worker の仕様が「設定の 1 行を(速報は依頼レコードの値で置換して)起動し、stdout / stderr / exit_code を依頼レコードに保存して状態を決める」だけで読める。worker が読む入力は DB の依頼レコードと自分の設定ファイルだけである。
- 速報の依頼レコードから run_id / job_id / parameters / blue と green の exit_code が(直接の列または同一トランザクションの参照で)取れる。完了通知の引数に成果物 URI が無い。
- 確報 runner の仕様が「引数なしで起動され、依頼を 1 件登録し、終端まで待って保存値をそのまま返す」だけで読める。
- 残す検証 2 点(コマンド部分が絶対パスで実行可能 / 速報に `{job_id}` がある)の違反文言が CLI 契約から一意に読める。
- 本 UC の対象が速報の起動コマンド 1 行の設定と検証だけになり、確報側のティア仕様が無い。
- 方針資料と仕様で、確報依頼のデータ項目と完了通知の項目が一致する。

## CR-dcd8234d-001: validate-config.sh の検証ロジックの委譲と共有関数が、ティア間の契約として宣言されていない

- severity: spec-gap
- related_ids: [SPEC-004-04, REQ-004, CLP-003]
- related_files: [docs/arch/latest/arch-design.yaml, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-rapid-crosscheck.md, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md]

### 観測した事実

- `validate-config.sh` の本体(エントリポイント)は速報・確報クロスチェックのティアではなく、既存の facade ティアが所有する。CLI 契約の `tier_note` と `options[].owner_tier` は、`--crosscheck-job-map` の検証ロジックを速報クロスチェックティアに、`--target-catalog` を確報クロスチェックティアに割り当てる。
- 両ティアの仕様「変更概要」は、各ティアが検証関数を提供し、本体が「bash の source で直接依存(CLP-003)」すると書く。
- UC 仕様の E2E 完了条件(SPEC-004-04)の Then は「slot ジョブマップの読み込みと同じ CSV クォート解析関数が使われ」と書く。その関数(CSV の複製・バイト点検・クォート解析、出力フィールドの表記)の実体は facade ティアにある。
- 一方、実装リポジトリのティア間依存の宣言(契約一覧)には管理 DB のスキーマ 1 件しか無い。facade ティアと両クロスチェックティアのあいだの関数共有は、どちらの方向も宣言されていない。
- 開発規約「全種別共通」は、契約に無いティア間依存を実装で直接結ばず、変更要求で契約宣言の追加を求めると定める。
- 本 UC の実装は、次の 2 つの暫定依存で統合テストを通した。
  - facade ティアの本体が、両クロスチェックティアの固定パス(`<tier>/src/presentation/validate_config_<kind>.sh`)を存在時のみ source して `validate_config_<kind>` 関数を登録する(本 UC の書き込み範囲外の facade に 1 commit で追加)。
  - 両クロスチェックティアが、facade ティアの CSV 読み込み関数と出力フィールド表記関数を、本体が先に source している前提でそのまま呼ぶ(両ティアとも CSV パーサを持たない)。
- 独立検証は 4 回とも、この依存を「利用者が確定した意図的な逸脱」として blocker にせず minor で残した。実装者の前提記録にも両ティアで記録されている(確報ティア A-018 / A-019、速報ティア冒頭の除外事項)。
- CR-dcd8234d-007 の反映後、確報クロスチェックティアは `validate-config.sh` の検証関数を持たなくなる。本要求の対象は facade ティアと速報クロスチェックティアの 2 ティア間の共有だけになる。共有する関数の集合も、設定の置き場(CSV か env か)に応じて変わる(env なら CSV 解析関数は不要になり、env の読み込み関数と出力表記関数が共有面になる)。

### 現在の仕様と問題

- UC 仕様とティア仕様は「直接依存で共有する」と書き、開発規約は「契約に無い直接依存は禁止」と書く。両方を同時に満たす実装は無い。
- 共有面(どの関数を、どのティアが提供し、どのティアが使うか)が仕様に無いため、実装者が共有する関数の集合を自分で決めた。facade ティアが共有関数の名前や引数を変えると、利用側のティアが黙って壊れる。
- 検証関数の登録方法(固定パスを source する)も仕様に無い。facade ティアの本体に他ティアのパスを直書きしており、ティアを追加するたびに facade 側を書き換える。
- 元の方針資料との照合結果: 方針資料は「`validate-config.sh` で検証する」ことを定めるが、スクリプトの内部構成(ティア間の関数共有)の記載は無い。どちらの方向に決めても方針資料と矛盾しない。

### 変更してほしいこと

1. CR-dcd8234d-007 の反映後も、`validate-config.sh` の本体(facade ティア)が速報クロスチェックティアの検証関数を読み込む構成を残すなら、facade ティアと速報クロスチェックティアのあいだの依存を、ティア間の依存ルール(CLP-003 と同じ階層)と契約として明記する。次の 2 方向を区別する。
   - facade ティアが提供する共有関数(設定ファイルの単一スナップショット・バイト点検・解析、出力フィールドの可視表記)を、速報クロスチェックティアが使う。
   - 速報クロスチェックティアが提供する検証関数(`validate_config_<kind>`)を、facade ティアの本体が使う。
   - 確報側の共有は宣言しない(将来ティアを追加する場合は同じ契約の形で追加する)。
2. 検証関数の登録方法を 1 つに決める。
   - 案 A(現在の実装): facade ティアの本体が、所有ティアの固定パス `<tier>/src/presentation/validate_config_<kind>.sh` を存在時のみ source する。関数名は `validate_config_<kind> <path> <verbose>`。
   - 案 B: facade ティアの本体が、設定したディレクトリ配下の検証関数ファイルを探索して source する(ティア追加時に facade 側を変えない)。
   - 推奨は案 A である。本 UC で動作確認済みで、探索の順序と衝突の規則を新たに決めなくてよい。
3. 共有関数の集合(関数名・引数・戻り値・出力)を契約の共有仕様として 1 か所に書き、速報クロスチェックティアの仕様からはその場所を参照する形にする。
4. 速報の起動コマンドの検証を facade ティア単独で完結させる(速報クロスチェックティアが検証関数を提供しない)構成にする場合は、本要求は不要になる。その場合は CLI 契約の `tier_note` / `owner_tier` からティア間の委譲の記述を外す。

### 完了条件

- facade ティアと速報クロスチェックティアの依存が、提供側・利用側・共有する関数の集合を含めて契約として読める。または、委譲自体が無くなり `tier_note` / `owner_tier` からティア間の委譲の記述が消えている。
- 検証関数の登録方法(パスと関数名)が仕様から一意に決まる。
- 開発規約「契約に無いティア間依存の禁止」と、ティア仕様「直接依存で共有する」が矛盾しない。

## CR-dcd8234d-002: 受け入れ基準の Then に「同じ関数を使う」という実装構造の要求が混ざり、テストで判定できない

- severity: spec-gap
- related_ids: [SPEC-004-04, REQ-004]
- related_files: [docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md, docs/usdm/latest/requirements.yaml]

### 観測した事実

- UC 仕様の E2E 完了条件の Scenario「クロスチェックジョブマップと対象カタログは slot ジョブマップと同じ CSV 形式である(SPEC-004-04)」の最後の Then は次の 1 文である。

```gherkin
And slot ジョブマップの読み込みと同じ CSV クォート解析関数が使われ、タブ区切りのファイルは `error: header mismatch` で拒否される
```

- 前半「同じ CSV クォート解析関数が使われ」は、コマンドの実行結果(終了コード・stdout・stderr)からは真偽を判定できない。同じ解析結果になることまでしか判定できない。
- 後半「タブ区切りのファイルは `error: header mismatch` で拒否される」は、実行結果で判定できる。
- UC BDD の step 実装は、前半を「二重化した引用符を含む引用セルを 1 セルとして受理する(`rows=2` / `status=valid`)」で代替し、代替した旨をコメントに残した。feature 本文は仕様からの転写規約により変更していない。
- 同じ Scenario の 1 つ前の Then「囲んだセルはカンマを含む 1 セルとして解析される」と、受け入れ基準 SPEC-004-04-5「slot ジョブマップと同じ CSV 形式である」は、実行結果で判定できている。
- Scenario 名と受け入れ基準の「対象カタログ」の語、および CSV の行構造そのものは、CR-dcd8234d-007 で廃止される。設定の置き場が env になれば、この Scenario のクロスチェック部分は無くなる。

### 現在の仕様と問題

- 受け入れ基準に「利用者が観測できる振る舞い」と「実装の構造(関数の共有)」が 1 文に混ざっている。
- 実装の構造は、テストでは判定できず、代替した判定が仕様の意図と一致しているかを step 実装者が毎回判断する。
- 関数の共有そのものは CR-dcd8234d-001 で契約として扱う。受け入れ基準には振る舞いだけを残すのが筋である。
- 元の方針資料との照合結果: 方針資料は「クロスチェックのジョブマップも slot ジョブマップと同じ CSV 形式」とだけ定める。関数の共有は方針資料の要求ではない。

### 変更してほしいこと

1. CR-dcd8234d-007 の反映後も速報の起動コマンドの設定を CSV 形式で残す場合は、当該 Then を観測できる振る舞いだけに書き直す。例:

```gherkin
And 二重化した引用符を含む引用セルは 1 セルとして解析され、タブ区切りのファイルは `error: header mismatch` で拒否される
```

2. 「同じ CSV クォート解析関数を使う」という構造の要求は、受け入れ基準から外し、CR-dcd8234d-001 の契約(共有関数の集合)へ移す。
3. USDM の受け入れ基準(SPEC-004-04)に同じ文言があれば、同じ方針でそろえる。
4. 設定の置き場が env になり、この Scenario のクロスチェック部分が無くなる場合は、書き直しは不要である。その場合も、新しく書く受け入れ基準(残す検証 2 点)には実装の構造(関数の共有・内部の呼び出し)を書かず、`validate-config.sh` の終了コード・stdout・stderr で判定できる文言だけにする。
5. Scenario 名・受け入れ基準・Given から「対象カタログ」の語を外す作業は CR-dcd8234d-007 で行う。本要求は Then の文言だけを対象にする。

### 完了条件

- 本 UC の E2E 完了条件のすべての Then が、`validate-config.sh` の終了コード・stdout・stderr だけで判定できる。
- UC BDD の step 実装から「代替した」コメントを消せる。

## CR-dcd8234d-003: 同じシェルに source されるティアの関数名・グローバル変数名の名前空間の規則が無い

- severity: spec-gap
- related_ids: [CLP-003, SPEC-004-04, REQ-004]
- related_files: [docs/arch/latest/arch-design.yaml, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/tier-rapid-crosscheck.md]

### 観測した事実

- `validate-config.sh` の本体は、速報クロスチェックティアと確報クロスチェックティアの検証関数ファイルを、同じシェルに順に source する。
- 速報クロスチェックティアの実装(2 回目)が repository 層に `target_catalog_repo_load` を定義したところ、確報クロスチェックティアにも同名の関数があり、後から source された確報側の定義で上書きされた。両者は戻り値の意味が異なるため、`--crosscheck-job-map` の対象カタログ参照の解決が内部障害(終了コード 6)になった。
- bash は関数の再定義を黙って受け入れる。lint(shellcheck)でも、ティア単独で source する単体テストでも検出されない。本体を実プロセスとして起動するテストでだけ現れた。
- 速報クロスチェックティアは、自ティアの関数名・定数名にティア固有の接頭辞(`crosscheck_` / `CROSSCHECK_`)を付けて回避した。両ティアのトップレベル名に他の衝突が無いことは実装者と独立検証の双方が確認した。
- アーキテクチャ設計のティア間依存ルール(CLP-003「IF なし(直接依存)」)、CLI 契約、両ティアの仕様のいずれにも、同じプロセスに読み込まれるティア間の名前空間の規則は無い。
- CR-dcd8234d-007 の反映後は、確報クロスチェックティアの検証関数は無くなり、同じシェルに source されるのは facade ティアと速報クロスチェックティアの 2 つになる。衝突の実例は確報側の関数で起きたが、規則の不在は残る。

### 現在の仕様と問題

- 「bash の source で直接依存」する設計を採る以上、名前の衝突は設計上の制約として仕様に書く必要がある。実装規約だけで扱うと、ティアごとの実装者が独立に名前を決め、統合時にだけ壊れる。
- 今回の回避は速報側だけが接頭辞を付けた片務的なもので、facade ティアの共有関数(`job_map_*` / `csv_*` / `cli_field_*`)には規則が無い。次にティアを追加すると同じ衝突が起こり得る。
- 元の方針資料との照合結果: 方針資料はシェルスクリプトの内部構成を定めていない。規則の追加は方針資料と矛盾しない。

### 変更してほしいこと

1. ティア間依存ルール(CLP-003)に、同じプロセスに source されるティア間の名前空間の規則を追加する。
   - 各ティアが定義するトップレベルの関数名・グローバル変数名には、ティア固有の接頭辞を付ける(例: 速報クロスチェックは `crosscheck_` / `CROSSCHECK_`)。
   - facade ティアが提供する共有関数は、共有面として契約に列挙した名前だけを他ティアから呼べる名前とし、それ以外は facade 固有の接頭辞で閉じる。
   - 他ティアが定義した名前を再定義してはならない。
2. `validate-config.sh` のエントリポイントの契約(`tier_note`)に、検証関数ファイルは関数の定義だけを行い、source 時に副作用(シェルオプションの変更・グローバル変数の上書き・コマンドの実行)を起こさないことを明記する。
3. 可能なら、統合テストの観点として「所有ティアごとの関数名の集合に重複が無いこと」を仕様に書く(実装側はそれをゲートにできる)。
4. CR-dcd8234d-001 の 4 項(委譲自体を無くす構成)を採る場合、本要求の対象は facade ティア内部に閉じるため不要になる。

### 完了条件

- 同じプロセスに読み込まれるティアの名前空間の規則が、ティア間依存ルールまたは契約から読める。または、同じプロセスに読み込まれるティアが facade 1 つになっている。
- 同じプロセスに読み込まれるティア(facade / 速報クロスチェック)の関数名が、その規則に照らして衝突しないことを人が確認できる。
