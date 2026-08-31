# 出力規約(UI 画面を持たないプロダクト)

> design 無しモード(`design_available: false`、`interface_kind: cli`)。
> 本ファイルは全 UC の tier md が参照する **CLI 出力・終了コード・状態文字列・通知メールの正本**である。
> 個々のコマンドの引数・出力・終了コードの定義は `_cross-cutting/api/cli-command-contract.yaml` に置き、本ファイルは横断規約だけを書く。

## 適用範囲と適用外(無加工中継)

| 経路 | 規約の適用 | 理由 |
|---|---|---|
| 全コマンドの自身の出力(検証エラー・参照結果・info / warn / error) | 適用 | relay-gate が生成する出力 |
| `facade.sh` の foreground 中継(`<role>/stdout.log` → stdout、`<role>/stderr.log` → stderr、`<role>/exitcode.txt` → 終了コード) | **適用外(無加工)** | ジョブスケジューラ応答の決定(条件)。装飾・プレフィックス・追記を一切付けない |
| `final-crosscheck-runner.sh` の確報中継(依頼に保存された `stdout` → stdout、`stderr` → stderr、`exit_code` → 終了コード) | **適用外(無加工)** | 確報結果の中継制約(条件)。依頼の状態名・差分件数・レポート URI を追記しない |

- 中継経路でも、中継に至る**前**の relay-gate 自身のエラー(設定検証 NG・run_id 発行失敗・polling 上限超過など)は本規約に従い stderr + 終了コード 2 / 3 / 6 で返す
- 中継経路で relay-gate 自身の info / warn を出す必要がある場合は stderr ではなく実行ログファイルに出す(stdout / stderr を汚さない。arch CLP-002)

## 出力チャネル

| チャネル | 用途 | 例 |
|---------|------|---|
| stdout | 正常な結果・データ(パイプ可能)。`key=value` の 1 行 1 事実、または TSV(ヘッダー行あり) | `run_id=20260830T113000Z-JOB001-3f9a1c2e`<br>`status=SUCCEEDED` |
| stderr | エラー・警告・診断メッセージ。`error:` / `warn:` / `info:` 接頭辞 | `error: job_id=JOB001 not found in job map slot=green map=/etc/relay-gate/green-job-map.tsv` |
| 終了コード | 結果の分類(下記) | `2` |
| 実行ログファイル | 各スクリプトの run_id 付き実行ログ(stdout / stderr を汚さない) | `facade.sh 20260830T113000Z-JOB001-3f9a1c2e 2026-08-30T11:30:00Z INFO slot started slot=green mode=background pid=12345` |
| 成果物ファイル | Runner Result Contract(`started-at.txt` / `stdout.log` / `stderr.log` / `exitcode.txt` / `execution-spec.json`) | `facade/20260830T113000Z-JOB001-3f9a1c2e/green/exitcode.txt` |
| 通知メール | hang-detector の warning / error(下記「通知メール規約」) | 件名 `[relay-gate][warning] hang-suspected run_id=... job_id=JOB001 role=green` |

- 対話プロンプト(abort-*)は stderr に出す(stdout をパイプしても混ざらない)
- 進捗表示は行わない(非 TTY 起動が主経路。NFR B.2.1.1 の 10 秒以内で完了する CLI が対象)

## 終了コード規約

_inference.md 採用値 #2(共通 4 分類)。

| コード | 分類 | 条件 |
|-------|------|------|
| 0 | 成功 | 処理が完了した。参照系は対象が見つかり出力できた |
| 2 | 入力・引数・設定検証エラー | 引数不足・不正な値・未知のオプション、feature flag / ジョブマップ / クロスチェックジョブマップの検証 NG(foreground × foreground、JSON 配列不正、runner 実体なし等)、非対話で `--yes` なし、環境変数の未設定 |
| 3 | 業務エラー | 事前検証 NG(rerun: 元の mode が foreground / off、元の実行が RUNNING、role 未対応)、中止不可(abort: 対象が background かつ RUNNING でない / 依頼が RUNNING でない)、停止確認 `no`、参照系で対象 run_id が存在しない、RAPID_CROSSCHECK_MODE=off で管理 DB が無く状態更新先が無い |
| 6 | 実行エラー | SSH 接続・実行失敗、管理 DB 接続・SQL 失敗、比較ツールの起動失敗、メール送信失敗、成果物ファイルの書き込み失敗、polling 上限超過、内部エラー(想定外の例外) |

- `1` は使わない(`set -euo pipefail` による予期しない終了を `1` として区別できるようにするため。`1` を観測したら内部バグとして扱う)
- 中継系(`facade.sh` foreground / `final-crosscheck-runner.sh`)は保存済み exitcode を**そのまま**返す(上表を適用しない)
- worker(`rapid-crosscheck-worker.sh` / `final-crosscheck-worker.sh`)は比較ツールの終了コードを依頼レコードに保存するだけで、worker 自身の終了コードには反映しない(`--once` で依頼を 1 件処理できたら 0、依頼が無くても 0、claim / DB / 比較ツール起動に失敗したら 6)

### 比較ツール終了コード契約との対応

| 比較ツールの終了コード | 意味 | 依頼状態 | 比較結果ステータス | 確報 runner がジョブスケジューラへ返す終了コード | 速報での扱い |
|---|---|---|---|---|---|
| `0` | 比較 OK | SUCCEEDED | OK | `0`(無加工中継) | comparison_result に OK を登録。通知なし |
| `3` | 比較 NG(警告終了) | FAILED | NG | `3`(無加工中継) | comparison_result に NG を登録。hang-detector が error メール |
| `6` | 実行エラー(エラー終了) | FAILED | FAILED | `6`(無加工中継) | comparison_result に FAILED を登録。hang-detector が error メール |
| その他の非 0 | 比較ツール実装の契約に従う | FAILED | FAILED | その値(無加工中継) | 同上 |

- relay-gate の 4 分類(0 / 2 / 3 / 6)は比較ツール契約(0 / 3 / 6)と値の意味を揃えている(3 = 業務上の NG、6 = 実行失敗)。運用者は同じ読み方で判断できる
- 比較ツールを差し替えた場合、終了コードの値と意味はその実装の契約に従う(方針資料)。relay-gate は値を変換しない

## 出力フォーマット

- **既定**: plain。1 行 1 事実。`key=value`(値に空白を含まない場合)または `key: value`(値に空白・パスを含む場合。`:` の後に半角空白 1 つ)。キーは snake_case 英字。出力順はコマンドごとに固定し、`cli-command-contract.yaml` に記載する
- **表形式**: 複数行の参照系(`rapid-crosscheck-result.sh` の comparison_result 一覧 / `run-lineage.sh` / `hang-detect-trend.sh`)は **TSV**(タブ区切り、1 行目はヘッダー行、列名は snake_case)。値にタブ・改行を含めない(含む場合は半角空白へ置換)。列定義は `data-visualization.md` を正本とする
- **JSON**: 採用しない(`--format json` は将来拡張としても採用しない。jq 非依存を維持するため)
- **TTY 判定・色**: 行わない。ANSI エスケープを出さない。`--no-color` / `NO_COLOR` は不要(常に無色)
- **日時**: UTC ISO 8601 秒精度、`Z` 付き(`2026-08-30T11:30:00Z`)。ローカル時刻・タイムゾーンオフセット表記は使わない。経過時間は分単位の整数(`elapsed_minutes=75`)
- **run_id**: `{UTC yyyymmddThhmmssZ}-{job_id}-{8 桁 hex 乱数}`(例: `20260830T113000Z-JOB001-3f9a1c2e`。_inference.md 採用値 #9、仮採用)。job_id は英数字・`_`・`-` のみ許可する(区切り文字 `-` と衝突しないよう、run_id の解析は先頭 16 文字と末尾 8 文字で行う)
- **空値**: `key=`(値なし)ではなく `key=-` で出す(TSV も同様に `-`)。null / 空文字を区別しない
- **真偽値**: `true` / `false`
- **パス・URI**: 絶対パスまたは URI をそのまま出す(クォートしない)
- **ページング / 件数制限**: `--limit N`(既定 100)。`run-lineage.sh` は系譜の深さで打ち切らない(元の実行まで全件)。上限超過時は stderr に `warn: output truncated limit=100` を出す
- **stdout の末尾**: 改行で終える。成功時に何も出力しない場合は 0 行(空行を出さない)

### 出力例

```text
$ rapid-crosscheck-result.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e
run_id=20260830T113000Z-JOB001-3f9a1c2e
job_id=JOB001
request_status=FAILED
blue_status=SUCCEEDED
green_status=SUCCEEDED
exit_code=3
worker_id=worker-01
requested_at=2026-08-30T11:45:10Z
completed_at=2026-08-30T11:47:02Z
comparison_result_id	comparison_type	status	difference_count	report_uri	compared_at
c0a8f1d2	job	NG	12	file:///var/relay-gate/reports/20260830T113000Z-JOB001-3f9a1c2e/job.html	2026-08-30T11:47:01Z
```

```text
$ abort-green.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e
run_id=20260830T113000Z-JOB001-3f9a1c2e
job_id=JOB001
role=green
mode=background
status=RUNNING
pid=12345
started_at=2026-08-30T11:30:05Z
artifact_dir: /var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/green
対象ジョブのプロセスは強制終了してありますか？ [yes/no]: yes
status=ABORTED
aborted_at=2026-08-30T12:40:00Z
```

(現在状態の 8 行と `status=ABORTED` 以降は stdout、プロンプト行は stderr)

```text
$ background-rerun.sh --source-run-id 20260830T113000Z-JOB001-3f9a1c2e --role green
error: source run is not rerunnable run_id=20260830T113000Z-JOB001-3f9a1c2e role=green status=RUNNING
hint: abort the run with abort-green.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e before rerun
$ echo $?
3
```

## メッセージ表現規約

- **エラー**: stderr に `error: {原因}` を 1 行。原因は具体値(run_id / job_id / slot / role / 状態名 / ファイルパス / 設定キー)を `key=value` で末尾に含める。続けて `hint: {対処}` を 1 行(対処が明確な場合のみ)。エラーは 1 回だけ出す(arch CLR-001。多重ログ禁止)
- **警告**: `warn: {内容} key=value...`。処理は継続する
- **情報**: `info: {内容} key=value...`。既定では出さず、`--verbose` 指定時のみ出す。例外として速報結果参照の `info: rapid result is for investigation only; use final crosscheck for release decision` は常に出す
- **文法**: 英語、小文字始まり、句点なし、現在形。動詞は `not found` / `is not` / `failed` / `required` / `rejected` を優先し語彙を絞る
- **必須オプション欠落の定型文**(全コマンド共通): `error: option required option=--xxx`(`key=value` 規約に従う。`missing option` は使わない)。終了コード 2
- **管理 DB 障害の定型文**(速報・確報・監視・運用系で共通): 接続失敗は `error: management db connection failed ... conn_ref=...`、SELECT 失敗は `error: management db query failed ...`、INSERT / UPDATE 失敗は `error: management db insert failed table=... ...` / `error: management db update failed ...`(いずれも終了コード 6。「unavailable」系の旧文言は使わない)。管理 DB を使わない構成での拒否は終了コード 3 で、速報系は `error: management db is not configured (RAPID_CROSSCHECK_MODE=off) ...`、確報系(abort-final-crosscheck.sh)は `error: management db is not configured run_id=...`(final-crosscheck.env / FINAL_DB_CONN_REF の有無だけで判定。off 付記なし)(例外 2 つ: `rapid-crosscheck-result.sh` は `error: rapid crosscheck is off; no management db to query mode=off`、`rapid-crosscheck-worker.sh` は `error: management db is not configured mode=off`)
- **設定ファイル不在・必須キー欠落の定型文**(全コマンド共通): `error: config file not found path: ...` / `error: option required option=<KEY> path: ...`(終了コード 2。runner IF は exitcode.txt=2)
- **多言語**: メッセージ・キー・ログ・メール本文は英語(arch CTR-005)。日本語は運用者向け対話プロンプトのみ
- **対話プロンプト**(abort-* 共通、stderr へ出力、改行せず入力待ち):
  - `対象ジョブのプロセスは強制終了してありますか？ [yes/no]: `
  - `yes`(小文字完全一致)のみ肯定。`y` / `YES` / 空 Enter は `no` 扱い(意図的な壁)
  - `no` または `yes` 以外: stdout に `status={現在状態}`(変更なし)、stderr に `info: aborted by operator; status not changed`、終了コード 3
  - 非 TTY(stdin がパイプ / リダイレクト)で `--yes` なし: `error: interactive confirmation required (use --yes for non-interactive)`、終了コード 2
- **実行ログファイル**(arch CLP-002 / CTP-003):
  - 形式: `{script} {run_id} {UTC 日時} {LEVEL} {message}`(半角空白区切り。message 内の `key=value` は自由)
  - 例: `abort-green.sh 20260830T113000Z-JOB001-3f9a1c2e 2026-08-30T12:40:00Z INFO status changed from=RUNNING to=ABORTED operator=ops01 answer=yes`
  - LEVEL: `DEBUG` / `INFO` / `WARN` / `ERROR`
  - run_id が未確定の段階(引数検証前など)は `-` を置く
  - 出力先: `RELAY_GATE_LOG_DIR/{script}.log`(1 スクリプト 1 ファイル、追記。ローテーションは手動。arch CTR-006)
  - 中止・リランの運用操作は指示者(`operator=` に OS ユーザー名)と応答(`answer=`)を必ず含める(NFR E.7.1.1)
  - gateway 層の外部呼び出しは開始・終了・所要時間・成否を記録する(`ssh started host=... user=...` / `ssh finished exit_code=0 duration_ms=1234`)

## 状態表示

状態モデルの値は状態.tsv の値をそのまま英字コードにする(_inference.md 採用値 #11)。stdout / ログ / メールでは英字コードだけを出す。日本語名は文書上の対応表としてのみ使う。

| 状態モデル | 表示文字列(英字コード) | 日本語名 | 補足 |
|-----------|----------|------|------|
| 並行稼働実行(parallel_run) `status` | `STARTED` / `RUNNING` / `COMPLETED` / `ABORTED` | 開始 / 実行中 / 完了 / 中止 | RAPID_CROSSCHECK_MODE=off では parallel_run を作成しないため `-` を出す |
| slot 実行 `status` | `RUNNING` / `SUCCEEDED` / `FAILED` / `ABORTED` | 実行中 / 成功 / 失敗 / 中止 | off 時は成果物ファイルから導出(`exitcode.txt` なし=RUNNING、0=SUCCEEDED、非 0=FAILED。ABORTED は導出不可) |
| slot 実行モード `mode` | `foreground` / `background` / `off` | 前景 / 背景 / 停止 | feature flag の値をそのまま小文字で出す |
| クロスチェック依頼(速報・確報共通)`status` | `REQUESTED` / `CLAIMED` / `RUNNING` / `SUCCEEDED` / `FAILED` / `ABORTED` | 依頼済み / 取得済み / 実行中 / 成功 / 失敗 / 中止 | 終端状態は SUCCEEDED / FAILED / ABORTED |
| 速報実行の完了状況(rapid_run)`completion` | `PENDING` / `ONE_COMPLETED` / `BOTH_SUCCEEDED` / `ANY_FAILED` / `REQUEST_CREATED` | 両系未完了 / 片系完了 / 両系成功 / いずれか失敗 / 比較依頼作成済み | `blue_status` / `green_status` と併記する |
| 監視状態 `monitor_status` | `NOT_MONITORED` / `MONITORING` / `HANG_SUSPECTED_NOTIFIED` / `EXEC_ERROR_NOTIFIED` / `COMPARE_ERROR_NOTIFIED` / `COMPLETED` | 監視対象外 / 監視中 / ハング疑い通知済み / 実行エラー通知済み / 比較異常通知済み / 正常終了 | バリエーション「監視状態」(未検知 / ハング疑い / 通知済み / 通知後正常終了)とは値が一致しない。状態.tsv を正とする(rdra-feedback 対象) |
| 比較結果ステータス(comparison_result)`status` | `OK` / `NG` / `FAILED` | 比較 OK / 比較 NG / 実行失敗 | 比較ツール終了コード 0 / 3 / 6 に対応 |
| 通知レベル | `warning` / `error` | 警告 / 異常 | 小文字。件名の `[relay-gate][warning]` と本文の `level=warning` で同じ値 |
| 通知種別 | `hang-suspected` / `background-exec-error` / `rapid-crosscheck-error` | ハング疑い / background 実行エラー / 速報クロスチェック異常 | kebab-case。件名と本文 `kind=` で同じ値 |
| ハング検知判定結果 | `NOT_TARGET` / `COMPLETED` / `MONITORING` / `HANG_SUSPECTED` / `EXEC_ERROR` / `COMPARE_ERROR` | 監視対象外 / 正常終了(中止済み対象の終端を含む) / 継続監視 / ハング疑い / background 実行エラー / 速報クロスチェック異常(比較 NG・FAILED) | hang-detector の `--verbose` 出力とログにのみ現れる(`cli-command-contract.yaml` `shared_rules.state_codes.hang_judgement` と同じ 6 値)。監視状態への対応は NOT_TARGET → NOT_MONITORED、COMPLETED → COMPLETED、MONITORING → MONITORING、HANG_SUSPECTED → HANG_SUSPECTED_NOTIFIED、EXEC_ERROR → EXEC_ERROR_NOTIFIED、COMPARE_ERROR → COMPARE_ERROR_NOTIFIED |
| 実装スロット / run role | `blue` / `green` / `rapid-crosscheck` / `final-crosscheck` | — | 小文字。`--role` の引数値と同じ |
| 停止確認応答 | `yes` / `no` | — | ログの `answer=` に記録 |

- 色・記号は使わない。状態は文字列だけで伝える
- 状態の遷移を表示する場合は `from={旧} to={新}` の形式にする

## 通知メール規約

送信手段: OS 標準の `mail` / `sendmail` を gateway で呼ぶ(_inference.md 採用値 #10、仮採用)。宛先・送信コマンドは `hang-detector.env`(`ALERT_MAIL_TO` / `ALERT_MAIL_CMD`)で指定する。

- **件名**: `[relay-gate][{warning|error}] {通知種別} run_id={run_id} job_id={job_id} role={role}`
  - 例: `[relay-gate][warning] hang-suspected run_id=20260830T113000Z-JOB001-3f9a1c2e job_id=JOB001 role=green`
  - 例: `[relay-gate][error] rapid-crosscheck-error run_id=20260830T113000Z-JOB001-3f9a1c2e job_id=JOB001 role=rapid-crosscheck`
- **本文**: プレーンテキスト(`text/plain; charset=UTF-8`)。1 行 1 事実、`key=value` または `key: value`。空行で「事実」と「推奨対処」を区切る。HTML・添付ファイルは付けない
- **行長**: 80 桁制限は 1〜13 行目(事実部と空行)のうち 11 行目 `artifact_dir` を除く行に適用する。`artifact_dir` の `key: value` 行はパスが長くても折り返さない(80 桁制限の例外。BDD の「80 桁を超える行は無い」検証も 11 行目を除外する)。14 行目の `recommended_action` は定型文を折り返さず 1 行で出す(コピーしてそのまま実行できることを優先。15 行目以降なし)

| 行順 | キー | 値 | 備考 |
|---|---|---|---|
| 1 | `kind` | `hang-suspected` / `background-exec-error` / `rapid-crosscheck-error` | 通知種別 |
| 2 | `level` | `warning` / `error` | 通知レベル |
| 3 | `run_id` | run_id | |
| 4 | `job_id` | job_id | |
| 5 | `role` | `blue` / `green` / `rapid-crosscheck` | |
| 6 | `started_at` | UTC ISO 8601 | started-at.txt または依頼の started_at |
| 7 | `elapsed_minutes` | 整数 | 判定時点の経過時間(分) |
| 8 | `hang_detect_limit_minutes` | 整数 | execution-spec.json の role ごとの値。依頼の場合はクロスチェック側の値 |
| 9 | `exit_code` | 整数 または `-` | background-exec-error / rapid-crosscheck-error のみ値あり |
| 10 | `request_status` | 依頼状態 または `-` | rapid-crosscheck-error のみ |
| 11 | `artifact_dir` | 成果物ディレクトリの絶対パス | `key: value` 形式 |
| 12 | `detected_at` | UTC ISO 8601 | hang-detector の判定日時 |
| 13 | (空行) | | |
| 14 | `recommended_action` | 推奨対処(英語の定型文。折り返さず 1 行。80 桁制限の対象外) | 下表 |

| 通知種別 | level | recommended_action(定型文) |
|---|---|---|
| `hang-suspected` | warning | `check the process on the execution host; if it is still running normally, wait. if it is hung, stop the process, then run: abort-{role}.sh --run-id {run_id}` |
| `background-exec-error` | error | `inspect {artifact_dir}/stderr.log; after fixing the cause, run the rerun job: background-rerun.sh --source-run-id {run_id} --role {role}` |
| `rapid-crosscheck-error` | error | `inspect the comparison result: rapid-crosscheck-result.sh --run-id {run_id}; this result is for investigation only and does not affect the scheduler response` |

- **冪等性**: 同じ監視対象 ID(run_id + role)・同じ通知種別のメールは 1 回だけ送る(監視記録の `monitor_status` の遷移有無で判定。判定結果に対応する監視状態が現在値と同じなら送らない。`alerted_at` は送信成功の記録であり判定根拠ではない)。ハング疑い通知後に実行エラーへ遷移した場合は別種別として追加で 1 回送る
- **送信失敗**: 終了コード 6 で終了し、監視記録は `alerted_at` を更新しない(次回の定期実行で再送する)
- **日次メールサマリー**(arch CTP-010)は本規約の範囲外。採用する場合は件名 `[relay-gate][info] daily-summary date={business_date}`、本文は `data-visualization.md` 2. の警告傾向 TSV(`hang-detect-trend.sh --since {前日 00:00Z}` の出力)をそのまま貼る形を推奨する(仕様は未確定。todo。`data-visualization.md`「全体サマリー」と同文)

## 共通オプション・環境変数

### 共通オプション

| オプション | 対象コマンド | 動作 |
|---|---|---|
| `--help` | 全コマンド | 使い方を stdout に出して終了コード 0。1 行目に `usage: {script} ...`、以降に引数・オプション・終了コードの一覧 |
| `--yes` | `abort-blue.sh` / `abort-green.sh` / `abort-rapid-crosscheck.sh` / `abort-final-crosscheck.sh` | 停止確認プロンプトを省略して `yes` とみなす。ジョブスケジューラからの非対話起動用。ログに `answer=yes(--yes)` と記録する |
| `--once` | `rapid-crosscheck-worker.sh` / `final-crosscheck-worker.sh` | 1 回だけ poll / claim / 実行して終了する(定期ジョブ運転用。NFR A.1.1.1 計画停止への配慮) |
| `--verbose` | 全コマンド | `info:` を stderr に出す。中継系では実行ログにのみ出す |
| `--limit N` | 参照系(`rapid-crosscheck-result.sh` / `run-lineage.sh` / `hang-detect-trend.sh`) | 出力行数の上限(既定 100) |
| `--show-output` | `rapid-crosscheck-result.sh` | 比較ツールの stdout / stderr 本文を末尾に出す(段階的開示) |

- オプションは `--kebab-case`。値は `--key value` 形式(`--key=value` は受け付けない。bash の `case` で単純に解析するため)
- 未知のオプションは `error: unknown option option=--foo`、終了コード 2
- 短縮形(`-h` 等)は提供しない

### 環境変数(仮採用。_inference.md 採用値 #5 と整合。todo)

| 環境変数 | 用途 | 既定値 | 備考 |
|---|---|---|---|
| `RELAY_GATE_HOME` | relay-gate の配置ディレクトリ(スクリプトの所在) | スクリプト自身のディレクトリ(`$(dirname "$0")`) | 内部呼び出し(runner / rapid-crosscheck-runner)の解決に使う |
| `RELAY_GATE_CONFIG_DIR` | 設定ファイル置き場(feature flag の env、ジョブマップ TSV、クロスチェックジョブマップ TSV、`rapid-crosscheck.env` / `hang-detector.env` / `final-crosscheck.env`) | `$RELAY_GATE_HOME/config` | 未設定かつ既定パスが無い場合は終了コード 2 |
| `RELAY_GATE_ARTIFACT_ROOT` | 成果物ルート。`$RELAY_GATE_ARTIFACT_ROOT/facade/<run_id>/` に Runner Result を置く | `$RELAY_GATE_HOME/var` | 書き込み不可は終了コード 6 |
| `RELAY_GATE_LOG_DIR` | 実行ログの出力先(`{script}.log`) | `$RELAY_GATE_HOME/log` | 書き込み不可は stderr に `warn:` を出して処理は継続する |
| `RELAY_GATE_NOW` | テスト専用の現在時刻注入(UTC ISO 8601 秒精度、`Z` 付き。例 `2026-08-30T12:45:00Z`)。設定時は全スクリプトの時刻取得(経過時間・`*_at` 列・`started-at.txt`・run_id の時刻部・`detected_at`)がこの値になる | 未設定(実時刻) | 本番では設定しない。形式不正は終了コード 2。facade / background-rerun は runner にも引き継ぐ。run_id の乱数部は注入せず、テストでは形式パターンで照合する(`cli-command-contract.yaml` `environment_variables` / `shared_rules.run_id.test_verification`) |

- 管理 DB の接続参照名・lease / poll / polling 上限の設定キーは `cli-command-contract.yaml` の `config_files`(`rapid-crosscheck.env` / `hang-detector.env` / `final-crosscheck.env`)で定義する(本ファイルの範囲外)
- 認証情報(SSH 鍵パス・DB パスワード)は環境変数の値として扱わず、参照名のみを設定に置く(arch CTP-002)

## アクセシビリティ・運用配慮

- 色だけで意味を伝えない(色を使わない)。重要度は `error:` / `warn:` / `info:` の接頭辞と、メール件名の `[warning]` / `[error]` で伝える
- スクリーンリーダー向けに 1 行 1 事実、キー名は固定順。TSV はヘッダー行必須、列数 8 以内
- 罫線・アスキーアート・絵文字・全角記号を出力しない(対話プロンプトの日本語文言を除く)
- ログ・監査との整合: stdout に出した状態値と実行ログ・管理レコードの状態値は同じ英字コードを使う。中止・リランは指示者と応答を実行ログに残す(NFR E.7.1.1)。監査の正本はジョブスケジューラであり、relay-gate のログは 3 ヶ月保管(NFR C.6.1.1)の障害調査・警告傾向確認用
- 出力は `grep` / `cut -f` / `awk -F'\t'` で処理できる。JSON・YAML パーサや jq を要求しない(エアーギャップ・bash 単独)
- 大量出力(worker の常駐ログなど)は stdout ではなく実行ログファイルへ出す。stdout は 1 回の起動で人が読める分量(数十行)に収める
- 長時間処理(final runner の polling 最大 8 時間)は進捗を stdout / stderr に出さず、実行ログに `INFO polling final_crosscheck_id=... status=RUNNING elapsed_minutes=...` を poll 間隔ごとに残す(キー名は `cli-command-contract.yaml` `final-crosscheck-runner.sh.stderr` と同じ)
