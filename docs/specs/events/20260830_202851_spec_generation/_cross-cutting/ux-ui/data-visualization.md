# データ可視化設計仕様

> design 無しモード(`design_available: false`、`interface_kind: cli`)。
> UI 画面が無いため、本ファイルは「出力の集計・表形式の設計」として書く。チャートは対象なし。
> 出力フォーマット(TSV の規約・日時・run_id 形式)は `ui-design.md` を正本とする。

## 可視化対象

_inference.md「データ可視化対象」の 3 つ。いずれも CLI の TSV 出力(ヘッダー行あり、タブ区切り)であり、チャートは描かない。

| 出力(RDRA の画面) | コマンド | 指標/データ | 用途 | 表現 |
|------|------|-----------|------|-----------|
| rapid-crosscheck 結果参照出力 | `rapid-crosscheck-result.sh --run-id` | run_id 単位の依頼状態・両系の完了結果・comparison_result(status / difference_count / report_uri) | Comparison(blue と green の差分の有無・件数)。原因調査 | `key=value` の要約 + comparison_result の TSV |
| hang-detect 警告傾向出力 | `hang-detect-trend.sh [--job-id JOB_ID] [--role ROLE]` | job_id × role ごとの監視記録(警告回数・最後の警告時経過時間・現在の上限) | Comparison(警告時経過時間 と hang_detect_limit_minutes の差)。上限調整の根拠 | TSV |
| background-rerun 系譜追跡出力 | `run-lineage.sh --run-id` | 最新 run_id から parent_run_id をたどった run の連鎖(状態・role・開始日時) | Relationship(親子の連鎖)+ Trend(時系列) | TSV(最新 → 元の順) |

### 1. 速報比較結果参照(`rapid-crosscheck-result.sh --run-id RUN_ID`)

要約部(stdout、`key=value`、固定順 9 行。`cli-command-contract.yaml` の `rapid-crosscheck-result.sh.stdout` と同一):

| 行順 | キー | 型 | 出典 |
|---|---|---|---|
| 1 | `run_id` | run_id | rapid_crosscheck_request |
| 2 | `job_id` | string | rapid_crosscheck_request |
| 3 | `request_status` | `REQUESTED` / `CLAIMED` / `RUNNING` / `SUCCEEDED` / `FAILED` / `ABORTED` | rapid_crosscheck_request |
| 4 | `blue_status` | `SUCCEEDED` / `FAILED` / `-` | rapid_run |
| 5 | `green_status` | `SUCCEEDED` / `FAILED` / `-` | rapid_run |
| 6 | `exit_code` | integer または `-` | rapid_crosscheck_request |
| 7 | `worker_id` | string または `-` | rapid_crosscheck_request |
| 8 | `requested_at` | UTC ISO 8601 | rapid_crosscheck_request |
| 9 | `completed_at` | UTC ISO 8601 または `-` | rapid_crosscheck_request |

- `parent_run_id` は `run-lineage.sh --run-id` で、`error_summary` / 比較ツール本文は `--show-output` で参照する(要約部には含めない)

comparison_result 部(stdout、TSV。要約部の直後。0 件でもヘッダー行は出す):

| 列順 | 列名 | 型 | 説明 |
|---|---|---|---|
| 1 | `comparison_result_id` | string | 比較結果 ID |
| 2 | `comparison_type` | string | 比較種別(比較定義の comparison_type) |
| 3 | `status` | `OK` / `NG` / `FAILED` | 比較結果ステータス |
| 4 | `difference_count` | integer または `-` | 差分件数(比較ツール stdout の `difference_count=N` 行から転記。行が無ければ `-`。FAILED は通常 `-`) |
| 5 | `report_uri` | URI または `-` | レポートの所在 |
| 6 | `compared_at` | UTC ISO 8601 | 比較日時 |

- ソート順: `compared_at` 昇順、同値は `comparison_result_id` 昇順(SQL は `ORDER BY compared_at ASC, comparison_result_id ASC LIMIT ?`。`cli-command-contract.yaml` `rapid-crosscheck-result.sh.stdout` と同じ)
- `--show-output` 指定時の構造は本節が正本: TSV の後に空行 1 行 → `--- stdout ---` 行 → 依頼に保存された stdout 本文(バイト列そのまま。NULL は 0 バイト)→ `--- stderr ---` 行 → stderr 本文。区切り行の文字列は `--- stdout ---` / `--- stderr ---` で固定(仮採用ではない)
- stderr に常に `info: rapid result is for investigation only; use final crosscheck for release decision` を出す(条件「速報結果の位置付け」)
- 対象 run_id の依頼が存在しない: `error: rapid crosscheck request not found run_id=...`、終了コード 3。RAPID_CROSSCHECK_MODE=off で管理 DB が無い: `error: rapid crosscheck is off; no management db to query mode=off`、終了コード 3(文言は `cli-command-contract.yaml` の `rapid-crosscheck-result.sh.stderr` が正。`run-lineage.sh` / `hang-detect-trend.sh` の off 時文言 `management db is not configured (RAPID_CROSSCHECK_MODE=off)` とは別系統)

### 2. 監視記録の警告傾向(`hang-detect-trend.sh [--job-id JOB_ID] [--role ROLE] [--since UTC 日時] [--limit N]`)

`monitor_records`(RAPID_CROSSCHECK_MODE=on)を job_id × role で集計する。off では実行ログにのみ残るため、`error: management db is not configured (RAPID_CROSSCHECK_MODE=off)`、終了コード 3(grep 手順は運用ガイドに記載する)。

| 列順 | 列名 | 型 | 説明 |
|---|---|---|---|
| 1 | `job_id` | string | ジョブ ID |
| 2 | `role` | `blue` / `green` / `rapid-crosscheck` | 監視対象 role |
| 3 | `run_count` | integer | 集計期間内の監視対象 run 数(NOT_MONITORED を除く) |
| 4 | `hang_suspected_count` | integer | ハング疑い通知を出した run 数 |
| 5 | `completed_after_alert_count` | integer | 通知後に正常終了した run 数(調整根拠になる件数) |
| 6 | `max_elapsed_minutes_at_alert` | integer または `-` | 通知後正常終了した run の警告時経過時間の最大値(分) |
| 7 | `last_elapsed_minutes_at_alert` | integer または `-` | 最後の警告の経過時間(分)。条件「ハング検知上限の調整基準」の基準値 |
| 8 | `current_limit_minutes` | integer | 集計期間内で最新(`judged_at` 最大)の監視記録の `hang_detect_limit_minutes`(blue / green は execution-spec.json の `slots.<role>.hang_detect_limit_minutes`、rapid-crosscheck は hang-detector.env の `RAPID_HANG_DETECT_LIMIT_MINUTES` を hang-detector が転記した値) |

- ソート順: `last_elapsed_minutes_at_alert` 降順(上限超過が大きい順。調整優先度が高い行が先頭)、同値は `job_id` 昇順 → `role` の固定順(blue → green → rapid-crosscheck)
- 集計期間の既定は `--since` 未指定で 3 ヶ月前(NFR C.6.1.1 のログ保管期間と揃える)
- 「比較」の設計: `last_elapsed_minutes_at_alert` と `current_limit_minutes` を隣接させ、運用者が差分(調整余地)を一目で読めるようにする(データ可視化ルール「数値情報に意味を与えるのは比較」)
- 列は 8 列で認知負荷の上限(4〜5 項目)を超えるため、`--job-id` / `--role` の絞り込みを前提とし、既定では `hang_suspected_count > 0` の行だけを出す(`--all` で全行)

### 3. リラン系譜(`run-lineage.sh --run-id RUN_ID`)

指定 run_id から `parent_run_id` を辿り、元の実行まで 1 行 1 run で出す。指定 run_id を子に持つ run(指定 run_id より新しいリラン)も含める(系譜全体)。

| 列順 | 列名 | 型 | 説明 |
|---|---|---|---|
| 1 | `depth` | integer | 元の実行を 0 とした世代(1 = 1 回目のリラン) |
| 2 | `run_id` | run_id | |
| 3 | `parent_run_id` | run_id または `-` | 元の実行は `-` |
| 4 | `job_id` | string | |
| 5 | `role` | `blue` / `green` / `rapid-crosscheck` / `-` | リランで指定した role。元の実行(facade 起動)は `-` |
| 6 | `run_status` | `STARTED` / `RUNNING` / `COMPLETED` / `ABORTED` | parallel_run の状態 |
| 7 | `requested_at` | UTC ISO 8601 | parallel_run の requested_at |
| 8 | `completed_at` | UTC ISO 8601 または `-` | |

- ソート順: `depth` 降順(最新のリランが先頭、元の実行が末尾)。同じ depth に複数の run がある場合(同じ元から role 違いでリラン)は `requested_at` 昇順
- 指定 run_id の行を含む(自分自身も 1 行として出す)
- run_id 形式が時系列ソート可能(`{UTC 時刻}-...`)なため、`run_id` 列だけでも時系列が読める(_inference.md 採用値 #9 の根拠)
- 対象 run_id が存在しない: `error: run not found run_id=...`、終了コード 3。RAPID_CROSSCHECK_MODE=off では parallel_run が無く系譜を追跡できない: 終了コード 3

## チャート選定ガイドライン

チャートは**対象なし**(CLI 出力のみ。UI 画面・グラフ描画ライブラリを持たない。arch CTP-001)。

### 観点別チャート選定

| 観点 | 推奨チャート | 使用場面 |
|------|-----------|---------|
| Comparison(比較) | 該当なし(CLI 出力のみ) | 速報比較結果の `status` / `difference_count`、警告傾向の `last_elapsed_minutes_at_alert` と `current_limit_minutes` の隣接列で代替 |
| Composition(構成比) | 該当なし(CLI 出力のみ) | — |
| Relationship(関連性) | 該当なし(CLI 出力のみ) | リラン系譜の `parent_run_id` 列(連鎖リスト)で代替 |
| Distribution(分布) | 該当なし(CLI 出力のみ) | 警告傾向の `max_elapsed_minutes_at_alert` / `last_elapsed_minutes_at_alert` の 2 列で代替 |
| Trend(傾向) | 該当なし(CLI 出力のみ) | run_id の時系列ソートと `requested_at` 列で代替 |

- 運用者が組織既存の監視基盤や表計算でグラフ化したい場合に備え、TSV はそのまま取り込める形(ヘッダー行あり・数値列は整数・日時は ISO 8601)にする

## ダッシュボード設計原則

ダッシュボードは新規構築せず、**組織既存監視への統合と運用者向け日次メールサマリー**で代替する(arch CTP-010)。

### 情報の階層化

- **全体サマリー**: 日次メールサマリー(arch CTP-010)は本規約の範囲外。採用する場合は件名 `[relay-gate][info] daily-summary date={business_date}`、本文は本ファイル 2. の警告傾向 TSV(`hang-detect-trend.sh --since {前日 00:00Z}` の出力)をそのまま貼る形を推奨する(仕様は未確定。todo。`ui-design.md`「通知メール規約」と同文)
- **ドリルダウン**: サマリーの run_id を引数にして `rapid-crosscheck-result.sh --run-id` / `run-lineage.sh --run-id` を運用者が手動で実行する(メール本文に実行例を 1 行ずつ書く)
- **フィルター**: `hang-detect-trend.sh --job-id / --role / --since`、参照系の `--limit`

### データストーリーテリング

- **ナラティブ**: 「foreground の結果はジョブスケジューラで判定済み。background と速報の異常だけがここに現れる。error は対処、warning は静観候補」
- **比較軸**: 警告時経過時間 vs 現在の上限(調整余地)、blue vs green(差分件数)、リラン世代 vs 元の実行(復旧の進み)
- **アクション**: error → `abort-*` → `background-rerun.sh`。warning → 静観 or `hang-detect-trend.sh` で上限調整。速報 NG → `rapid-crosscheck-result.sh --show-output` で原因調査(リリース判断は確報の結果で行う)

## 認知負荷への配慮

- 要約部の `key=value` は 9 行以内、TSV は 8 列以内に収める。超える情報は `--show-output` / `--verbose` / `--all` の段階的開示に回す
- Data-Ink Ratio: 罫線・色・整形用の空白パディングを出さない。タブ区切りとヘッダー行だけを出す
- ゲシュタルト(近接): 比較して読む列(`last_elapsed_minutes_at_alert` と `current_limit_minutes`、`blue_status` と `green_status`)を隣接させる。識別子(run_id / job_id)は左端、判断材料(status / count)は右端に固定する(系列位置効果)
- 既定出力は「判断に必要な行だけ」(警告傾向は `hang_suspected_count > 0` のみ)に絞り、全件は明示オプションで出す
