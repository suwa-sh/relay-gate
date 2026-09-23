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
| stdout | 正常な結果・データ(パイプ可能)。`key=value` の 1 行 1 事実、または TSV(ヘッダー行あり) | `run_id=20260830T113000-JOB001-3f9a1c2e`<br>`status=SUCCEEDED` |
| stderr | エラー・警告・診断メッセージ。`error:` / `warn:` / `info:` 接頭辞 | `error: job_id=JOB001 not found in job map slot=green map=/etc/relay-gate/green-job-map.csv` |
| 終了コード | 結果の分類(下記) | `2` |
| 実行ログファイル | 各スクリプトの run_id 付き実行ログ(stdout / stderr を汚さない) | `facade.sh 20260830T113000-JOB001-3f9a1c2e 2026-08-30T11:30:00 INFO slot started slot=green mode=background pid=12345` |
| 成果物ファイル | Runner Result Contract(`started-at.txt` / `stdout.log` / `stderr.log` / `exitcode.txt` / `execution-spec.json`。中止時のみ `aborted.txt`。writer は abort-blue.sh / abort-green.sh) | `facade/20260830T113000-JOB001-3f9a1c2e/green/exitcode.txt` |
| 通知メール | hang-detector の warning / error(下記「通知メール規約」) | 件名 `[relay-gate][warning] hang-suspected run_id=... job_id=JOB001 role=green`(先頭の `[relay-gate]` は `hang-detector.env` の `ALERT_SUBJECT_PREFIX`。既定値) |

- 対話プロンプト(abort-*)は stderr に出す(stdout をパイプしても混ざらない)
- 進捗表示は行わない(非 TTY 起動が主経路。NFR B.2.1.1 の 10 秒以内で完了する CLI が対象)

## 終了コード規約

_inference.md 採用値 #2(共通 4 分類)。

| コード | 分類 | 条件 |
|-------|------|------|
| 0 | 成功 | 処理が完了した。参照系は対象が見つかり出力できた |
| 2 | 入力・引数・設定検証エラー | 引数不足・不正な値・未知のオプション、feature flag / ジョブマップ / クロスチェックジョブマップの検証 NG(foreground × foreground、必須キー欠落、enum 外の値、runner 実体なし・実行不可、CSV クォート不正、`fixed_params` の JSON 配列不正、host / user の片方だけ空 等)、非対話で `--yes` なし、環境変数の未設定 |
| 3 | 業務エラー | 事前検証 NG(rerun: 元の mode が foreground / off、元の実行が RUNNING(`exitcode.txt` も `aborted.txt` も無い)、role 未対応)、中止不可(abort: 対象が background かつ RUNNING でない / 速報比較依頼が REQUESTED・CLAIMED・RUNNING のいずれでもない(終端状態)/ 確報比較依頼が RUNNING でない)、停止確認 `no`、参照系で対象 run_id が存在しない、RAPID_CROSSCHECK_MODE=off で管理 DB を使わない構成での速報系・参照系の拒否(`abort-rapid-crosscheck.sh` / `rapid-crosscheck-result.sh` / `run-lineage.sh` / `hang-detect-trend.sh`。`abort-blue.sh` / `abort-green.sh` は off でも `aborted.txt` で中止が成立するため該当しない) |
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
- **表形式**: 複数行の参照系(`rapid-crosscheck-result.sh` の comparison_result 一覧 / `run-lineage.sh` / `hang-detect-trend.sh`)は **TSV**(タブ区切り、1 行目はヘッダー行、列名は snake_case)。値にタブ・改行を含めない(含む場合は下記「制御文字の表記」の可視表記 `\t` / `\n` へ置き換える。旧規則の「半角空白へ置換」は使わない)。列定義は `data-visualization.md` を正本とする
- **制御文字の表記**(全コマンドの stdout / stderr、実行ログ、メール本文に共通。任意入力 = 設定ファイルのセルの値・列名・キー名・パス・コマンド引数を出力するときの規則。利用者決定 2026-09-22):
  - 置き換える文字の範囲: C0 制御文字(U+0001〜U+001F)、DEL(U+007F)、UTF-8 で符号化した C1 制御文字(U+0080〜U+009F。バイト列 `C2 80`〜`C2 9F`)。U+0000(NUL)は設定ファイルの形式違反として読み込み時に拒否されるため出力に現れない
  - 置き換え後の表記: 改行(U+000A)は `\n`、タブ(U+0009)は `\t`、それ以外は `\u00XX`(16 進小文字 4 桁。例: ESC は `\u001b`、CR は `\u000d`、U+009B は `\u009b`)
  - バックスラッシュ(`\`)は置き換えない。理由: 制御文字を含まない値の出力を 1 バイトも変えないため。方針資料のジョブマップ例の Windows パス `G:\scripts` はそのまま `G:\scripts` と表示される。生のタブと 2 文字の `\t` を表示上区別できないことは許容する
  - 制御文字以外のバイトは変えない。UTF-8 として不正なバイトを含む引数(パスなど。設定ファイルの中身は形式違反として拒否されるが、コマンド引数のパスは拒否しない)もそのまま出す
  - `key=value` と `key: value` の選択は置き換え前の元の値で判定する(元の値に空白・パスを含めば `key: value`)。置き換えでタブが `\t` になり空白が消えても `key: value` のまま
  - 例外: `--verbose` の fixed_params の JSON 配列表記は JSON の文字列規則を優先する(`"` → `\"`、`\` → `\\`、制御文字は同じ `\n` / `\t` / `\u00XX`)。JSON 表記の中だけバックスラッシュがエスケープされる
  - 正本は本節。`cli-command-contract.yaml` の `conventions.output_format.control_chars` は本節の要約と参照。先行機能「feature flag を設定する」の stderr(`error: invalid value key=... value=...` / `warn: unknown key key=...`)を含む既存の全コマンドに適用する
- **JSON**: 採用しない(`--format json` は将来拡張としても採用しない。jq 非依存を維持するため)
- **TTY 判定・色**: 行わない。ANSI エスケープを出さない。`--no-color` / `NO_COLOR` は不要(常に無色)
- **日時**: ホストのローカルタイムゾーン(プロセスの `TZ` 環境変数に従う)、ISO 8601 秒精度、タイムゾーン指示子なし(`2026-08-30T11:30:00`)。run_id の時刻部と同じ時刻軸。UTC や `Z` 付き・オフセット表記は使わない(利用者決定 2026-09-07。arch CLP-002 / CTP-003)。例外: `started-at.txt` / `aborted.txt` の中身は UTC `Z` 付き(Runner Result Contract。表示・DB 転記時はローカルへ変換する)。`RELAY_GATE_NOW` は UTC `Z` 付きで受け取りローカルへ変換する。経過時間は分単位の整数(`elapsed_minutes=75`)。経過時間・lease 失効・走査窓(`--since`)の判定は epoch 秒で計算し、表記の比較では行わない。DST のあるタイムゾーンでは切替前後の表記が一意でないことを許容する。UTC → ローカルの変換は 1 箇所の共通関数に置き、全スクリプトが同じ変換を使う
- **run_id**: `{ローカル yyyymmddThhmmss}-{job_id}-{8 桁 hex 乱数}`(例: `20260830T113000-JOB001-3f9a1c2e`。利用者決定 2026-09-05)。時刻部はホストのローカルタイムゾーン(プロセスの `TZ` 環境変数に従う)で、タイムゾーン指示子(`Z` / オフセット)は付けない。`RELAY_GATE_NOW` 設定時はその UTC 値をローカルタイムゾーンへ変換した値になる(BDD の例示値は `TZ=UTC` 前提)。`final_crosscheck_id` も同じ形式(`{ローカル yyyymmddThhmmss}-final-{8 桁 hex}`)。RAPID_CROSSCHECK_MODE によらず facade が常に発行し、成果物ディレクトリ名と管理 DB の `run_id` は同じ値。job_id は英数字・`_`・`-` のみ許可する(区切り文字 `-` と衝突しないよう、run_id の解析は先頭 16 文字と末尾 8 文字で行う)。実行ログ・`*_at` 列・stdout・メール本文の日時も同じローカルタイムゾーン(指示子なし)で表す(上記「日時」)
- **空値**: `key=`(値なし)ではなく `key=-` で出す(TSV も同様に `-`)。null / 空文字を区別しない
- **真偽値**: `true` / `false`
- **パス・URI**: 絶対パスまたは URI をそのまま出す(クォートしない。制御文字だけは上記「制御文字の表記」で置き換える。設定ファイルの値としてのパス(ジョブマップの work_dir / script)は Windows 形式・相対パスも値のまま出す)
- **ページング / 件数制限**: `--limit N`(既定 100)。`run-lineage.sh` は系譜の深さで打ち切らない(元の実行まで全件)。上限超過時は stderr に `warn: output truncated limit=100` を出す
- **stdout の末尾**: 改行で終える。成功時に何も出力しない場合は 0 行(空行を出さない)

### 出力例

```text
$ rapid-crosscheck-result.sh --run-id 20260830T113000-JOB001-3f9a1c2e
run_id=20260830T113000-JOB001-3f9a1c2e
job_id=JOB001
request_status=FAILED
blue_status=SUCCEEDED
green_status=SUCCEEDED
exit_code=3
worker_id=worker-01
requested_at=2026-08-30T11:45:10
completed_at=2026-08-30T11:47:02
comparison_result_id	comparison_type	status	difference_count	report_uri	compared_at
c0a8f1d2	job	NG	12	file:///var/relay-gate/reports/20260830T113000-JOB001-3f9a1c2e/job.html	2026-08-30T11:47:01
```

```text
$ abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e
run_id=20260830T113000-JOB001-3f9a1c2e
job_id=JOB001
role=green
mode=background
status=RUNNING
pid=12345
started_at=2026-08-30T11:30:05
artifact_dir: /var/relay-gate/facade/20260830T113000-JOB001-3f9a1c2e/green
対象ジョブのプロセスは強制終了してありますか？ [yes/no]: yes
status=ABORTED
aborted_at=2026-08-30T12:40:00
```

(現在状態の 8 行と `status=ABORTED` 以降は stdout、プロンプト行は stderr)

- `abort-blue.sh` / `abort-green.sh` の現在状態(`status`)は成果物ファイルから導出する(条件「slot 実行の状態導出規則」。下記「状態表示」)。`mode` は `execution-spec.json` の `slots.<role>.mode`
- `yes` のとき `aborted.txt` を `.tmp` → `mv` で公開し、RAPID_CROSSCHECK_MODE が off 以外なら加えて管理 DB(`slot_executions` / `parallel_runs`)を条件付き UPDATE で ABORTED にする。同じ run に REQUESTED で未着手の速報比較依頼があればそれも ABORTED にする(`rapid_crosscheck_requests` を `WHERE run_id=? AND status='REQUESTED'` で条件付き UPDATE。0 件は正常。両系の完了通知で依頼が作成された直後に slot を中止した場合の競合窓を塞ぐ保険で、dispatcher 側の中止済み run 判定と併用する。CLAIMED / RUNNING の依頼は変更せず、REQUESTED / CLAIMED / RUNNING の明示中止は `abort-rapid-crosscheck.sh`(`status IN` の条件付き UPDATE)で行う。stdout には依頼の状態を出さず、実行ログに `INFO rapid request aborted run_id=... from=REQUESTED to=ABORTED operator=... answer=yes` を残す。条件「slot 中止可否判定」)。off では管理 DB に触れず `aborted.txt` だけで完了する(終了コード 0。stdout の出力順は上と同じ)
- `started_at=` / `aborted_at=` は `started-at.txt` / `aborted.txt` の UTC 値をローカルタイムゾーンへ変換した同時刻(指示子なし。上記「出力フォーマット」の日時)
- 管理 DB の UPDATE が 0 件(既に終端・中止済み): 実行ログに `WARN management db not updated ...` を残し終了コード 0。接続・SQL 失敗: `error: management db update failed ...` + `hint: rerun abort-<role>.sh --run-id ... to reapply`、終了コード 6(`aborted.txt` は公開済みのまま残す)
- 再適用(冪等): `aborted.txt` が既にあり、off 以外で管理 DB がまだ RUNNING(または parallel_run が STARTED / RUNNING)なら、確認の後に管理 DB だけ更新し、stdout `status=ABORTED`、stderr `warn: aborted.txt already published; management db updated`、終了コード 0。管理 DB も更新済み(または off)なら `error: run is not abortable ... status=ABORTED`、終了コード 3

```text
$ validate-config.sh --feature-flag /etc/relay-gate/feature-flag.env
config_path: /etc/relay-gate/feature-flag.env
blue_mode=foreground
green_mode=background
blue_impl=v1.4.2
green_impl=v2.0.0
blue_runner: /opt/relay-gate/runners/blue-runner.sh
green_runner: /opt/relay-gate/runners/green-runner.sh
rapid_crosscheck_mode=background
rapid_crosscheck_runner: /opt/relay-gate/rapid-crosscheck-runner.sh
rapid_crosscheck_worker: /opt/relay-gate/rapid-crosscheck-worker.sh
operation_mode=parallel
blue_job_map: /etc/relay-gate/blue-job-map.csv
green_job_map: /etc/relay-gate/green-job-map.csv
blue_runner_if_version=1
green_runner_if_version=1
```

(`validate-config.sh --feature-flag` の stdout キー順は上の 15 行で固定。`config_version` / `impl_version` は出さない。off の slot は `<slot>_impl` / `<slot>_runner` / `<slot>_job_map` / `<slot>_runner_if_version` が `-`。`--job-map` の stdout は `map_version` を任意とし、列が無ければ `map_version=-`。`operation_mode` の値は英字コード。導出は `cli-command-contract.yaml` `validate-config.sh` / `config_files.feature-flag.env.derived` が正本。facade.sh の実行ログ `operation_mode=` も同じ英字コードを出す)

`operation_mode` の英字コードと RDRA バリエーション「運用モード」の日本語名の対応:

| コード | 運用モード(日本語名) | blue_mode / green_mode / rapid_crosscheck_mode |
|---|---|---|
| `parallel` | 並行稼働 | foreground / background / background |
| `green_only` | 新実装の単独本番 | off / foreground / off |
| `next_gen_parallel` | 次世代実装との並行稼働 | background / foreground / background |
| `custom` | その他 | 上記以外の組合せ |

```text
$ background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green
error: source run is not rerunnable run_id=20260830T113000-JOB001-3f9a1c2e role=green status=RUNNING
hint: abort the run with abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e before rerun
$ echo $?
3
```

## メッセージ表現規約

- **エラー**: stderr に `error: {原因}` を 1 行。原因は具体値(run_id / job_id / slot / role / 状態名 / ファイルパス / 設定キー)を `key=value` で末尾に含める。続けて `hint: {対処}` を 1 行(対処が明確な場合のみ)。エラーは 1 回だけ出す(arch CLR-001。多重ログ禁止)
- **警告**: `warn: {内容} key=value...`。処理は継続する
- **情報**: `info: {内容} key=value...`。既定では出さず、`--verbose` 指定時のみ出す。例外として速報結果参照の `info: rapid result is for investigation only; use final crosscheck for release decision` は常に出す
- **文法**: 英語、小文字始まり、句点なし、現在形。動詞は `not found` / `is not` / `failed` / `required` / `rejected` を優先し語彙を絞る
- **必須オプション欠落の定型文**(全コマンド共通): `error: option required option=--xxx`(`key=value` 規約に従う。`missing option` は使わない)。終了コード 2
- **管理 DB 障害の定型文**(速報・確報・監視・運用系で共通): 接続失敗は `error: management db connection failed ... conn_ref=...`、SELECT 失敗は `error: management db query failed ...`、INSERT / UPDATE 失敗は `error: management db insert failed table=... ...` / `error: management db update failed ...`(いずれも終了コード 6。「unavailable」系の旧文言は使わない)。管理 DB を使わない構成での拒否は終了コード 3 で、速報系は `error: management db is not configured (RAPID_CROSSCHECK_MODE=off) ...`、確報系(abort-final-crosscheck.sh)は `error: management db is not configured run_id=...`(final-crosscheck.env / FINAL_DB_CONN_REF の有無だけで判定。off 付記なし)(例外 2 つ: `rapid-crosscheck-result.sh` は `error: rapid crosscheck is off; no management db to query mode=off`、`rapid-crosscheck-worker.sh` は `error: management db is not configured mode=off`)。`abort-blue.sh` / `abort-green.sh` は off で拒否しない(`aborted.txt` を正本として中止が成立する。上記「出力例」)。管理 DB は relay-gate 内部のデータストア(ジョブキュー兼管理 DB)であり、外部システムではない
- **設定ファイル不在・必須キー欠落の定型文**(全コマンド共通): `error: config file not found path: ...` / `error: option required option=<KEY> path: ...`(終了コード 2。runner IF は exitcode.txt=2)
- **feature flag 検証の定型文**(`validate-config.sh --feature-flag` / `facade.sh` / `background-rerun.sh` 共通。`cli-command-contract.yaml` `config_files.feature-flag.env.error_messages` と同文):
  - 必須キー欠落・空: `error: option required option=<KEY> path: ...`
  - enum 外の値(`BLUE_MODE` / `GREEN_MODE` / `RAPID_CROSSCHECK_MODE` は foreground / background / off): `error: invalid value key=<KEY> value=...`。続けて `hint: use foreground, background or off` を 1 行出す
  - 絶対パスでない: `error: path is not absolute key=<KEY> path=...`
  - 実体が無い / 実行不可: `error: file not executable key=<KEY> path=...`
  - foreground が 1 slot ちょうどでない: `error: foreground slot must be exactly one blue_mode=... green_mode=...`
  - 未知キー(9 キー以外): `warn: unknown key key=<KEY> path: ...`(処理は継続)
  - いずれのエラーも終了コード 2
- **設定ファイルの入力の守備範囲の定型文**(全設定ファイル・全読み手共通。正本は `cli-command-contract.yaml` の `config_input_rules`。原則「形式(UTF-8 / LF / ヘッダー)から外れた入力は拒否する」。例外は最終行の改行なしとデータ行 0 件の受理):
  - NUL バイト: `error: nul byte is not allowed line=N path: ...`
  - UTF-8 として不正なバイト列(コメント行を含む): `error: encoding is not utf-8 line=N path: ...`
  - BOM: `error: byte order mark is not allowed line=1 path: ...`
  - CR(CRLF を含む): `error: carriage return is not allowed line=N path: ...` + `hint: use LF line endings`
  - ヘッダー列名の重複(CSV): `error: duplicate column column=<name> path: ...`
  - `=` を含まない行(env): `error: invalid line line=N path: ...`
  - いずれも終了コード 2(runner IF は exitcode.txt=2)。行番号は物理行番号、`path:` は利用者が指定したパス(一時ファイルのパスは出さない)
  - 検証器の内部障害(補助コマンドの失敗 / 入力の複製の失敗): `error: internal command failed commands=<name,...> path: ...` / `error: config snapshot failed path: ...` + `hint: check TMPDIR is writable`。終了コード 6(runner IF は exitcode.txt=6)。stdout は出さず、検証 OK も違反も返さない
- **ジョブマップ検証の定型文**(`validate-config.sh --job-map` / slot runner 共通。CSV。列はヘッダー名で対応付ける):
  - 必須列(`job_id` / `work_dir` / `script` / `fixed_params` / `hang_detect_limit_minutes`)の欠落、または `host` / `user` の片方だけ: `error: job map header mismatch missing=<col,...> path: ...`
  - CSV クォート不正: `error: csv quote is invalid line=N path: ...`
  - 値の違反: `error: <column> is <reason> line=N job_id=... value=...`(例: `error: user is empty ...`(host のみ値あり)/ `error: work_dir is empty ...` / `error: fixed_params is not a json array of strings ...`)。`work_dir` / `script` は空でなければ受理し、パスの形式(絶対 / 相対 / Windows 形式)は検査しない(旧 `is not absolute` は使わない)
  - 未知列(`impl_version` を含む): `warn: unknown column column=<name> path: ...`
  - `value=` / `column=` に出す任意入力は上記「制御文字の表記」で置き換える
  - いずれのエラーも終了コード 2(runner IF は exitcode.txt=2)
- **完了通知失敗の実行ログ**(条件「完了通知失敗の扱い」): slot runner は `WARN completion notice failed run_id=... role=... runner=<RAPID_CROSSCHECK_RUNNER> exit_code=...` を実行ログに残し、Runner Result と終了コードは実装スクリプトの exitcode のまま。自動検知はしない。復旧は運用者が `RAPID_CROSSCHECK_RUNNER` を同一引数で再実行する(冪等・先勝ち)
- **多言語**: メッセージ・キー・ログ・メール本文は英語(arch CTR-005)。日本語は運用者向け対話プロンプトのみ
- **対話プロンプト**(abort-* 共通、stderr へ出力、改行せず入力待ち):
  - `対象ジョブのプロセスは強制終了してありますか？ [yes/no]: `
  - `yes`(小文字完全一致)のみ肯定。`y` / `YES` / 空 Enter は `no` 扱い(意図的な壁)
  - `no` または `yes` 以外: stdout に `status={現在状態}`(変更なし)、stderr に `info: aborted by operator; status not changed`、終了コード 3
  - 非 TTY(stdin がパイプ / リダイレクト)で `--yes` なし: `error: interactive confirmation required (use --yes for non-interactive)`、終了コード 2
- **実行ログファイル**(arch CLP-002 / CTP-003):
  - 形式: `{script} {run_id} {ローカル日時} {LEVEL} {message}`(半角空白区切り。message 内の `key=value` は自由)
  - 例: `abort-green.sh 20260830T113000-JOB001-3f9a1c2e 2026-08-30T12:40:00 INFO status changed from=RUNNING to=ABORTED operator=ops01 answer=yes`
  - LEVEL: `DEBUG` / `INFO` / `WARN` / `ERROR`
  - run_id が未確定の段階(引数検証前など)は `-` を置く
  - 出力先: `RELAY_GATE_LOG_DIR/{script}.log`(1 スクリプト 1 ファイル、追記。ローテーションは手動。arch CTR-006)
  - 中止・リランの運用操作は指示者(`operator=` に OS ユーザー名)と応答(`answer=`)を必ず含める(NFR E.7.1.1)
  - gateway 層の外部呼び出しは開始・終了・所要時間・成否を記録する(`INFO ssh exec started run_id=... role=... host=... user=... work_dir=... script=...` / `INFO ssh exec finished run_id=... role=... exit_code=N`。ローカル実行(host / user が null)は `INFO local exec started run_id=... role=... work_dir=... script=...` / `INFO local exec finished run_id=... role=... exit_code=N`)

## 状態表示

状態モデルの値は状態.tsv の値をそのまま英字コードにする(_inference.md 採用値 #11)。stdout / ログ / メールでは英字コードだけを出す。日本語名は文書上の対応表としてのみ使う。

| 状態モデル | 表示文字列(英字コード) | 日本語名 | 補足 |
|-----------|----------|------|------|
| 並行稼働実行(parallel_run) `status` | `STARTED` / `RUNNING` / `COMPLETED` / `ABORTED` | 開始 / 実行中 / 完了 / 中止 | RAPID_CROSSCHECK_MODE=off では parallel_run を作成しないため `-` を出す |
| slot 実行 `status` | `RUNNING` / `SUCCEEDED` / `FAILED` / `ABORTED` | 実行中 / 成功 / 失敗 / 中止 | 成果物ファイルが正本(条件「slot 実行の状態導出規則」): `exitcode.txt` があれば 0=SUCCEEDED / 非 0=FAILED、無く `aborted.txt` があれば ABORTED、どちらも無ければ RUNNING。両方あるときは `exitcode.txt` を優先する。off 以外では同条件の管理 DB 側の規則に従い、管理 DB `slot_executions.status` に `aborted.txt` / `exitcode.txt` の公開時点の状態を条件付き UPDATE(WHERE status='RUNNING')で一度だけ書く(abort-blue / abort-green が ABORTED にした後に実装が走り切って `exitcode.txt` を公開した経路だけ、導出値と異なり ABORTED のまま残る。再同期しない。正本: `rdb-schema.yaml` slot_executions.status) |
| slot 実行モード `mode` | `foreground` / `background` / `off` | 前景 / 背景 / 停止 | feature flag の値をそのまま小文字で出す |
| クロスチェック依頼(速報・確報共通)`status` | `REQUESTED` / `CLAIMED` / `RUNNING` / `SUCCEEDED` / `FAILED` / `ABORTED` | 依頼済み / 取得済み / 実行中 / 成功 / 失敗 / 中止 | 終端状態は SUCCEEDED / FAILED / ABORTED |
| 速報実行の完了状況(rapid_run)`completion` | `PENDING` / `ONE_COMPLETED` / `BOTH_SUCCEEDED` / `ANY_FAILED` / `REQUEST_CREATED` | 両系未完了 / 片系完了 / 両系成功 / いずれか失敗 / 比較依頼作成済み | `blue_status` / `green_status` と併記する |
| 監視状態 `monitor_status` | `NOT_MONITORED` / `MONITORING` / `HANG_SUSPECTED_NOTIFIED` / `EXEC_ERROR_NOTIFIED` / `COMPARE_ERROR_NOTIFIED` / `COMPLETED` | 監視対象外 / 監視中 / ハング疑い通知済み / 実行エラー通知済み / 比較異常通知済み / 正常終了 | 状態.tsv とバリエーション「監視状態」は同じ 6 値(利用者決定 2026-09-05)。「通知後正常終了」は遷移 HANG_SUSPECTED_NOTIFIED → COMPLETED の別名。遷移: MONITORING → COMPLETED(exitcode 0、または監視対象が ABORTED で中止済み終端)、HANG_SUSPECTED_NOTIFIED → EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED / COMPLETED |
| 比較結果ステータス(comparison_result)`status` | `OK` / `NG` / `FAILED` | 比較 OK / 比較 NG / 実行失敗 | 比較ツール終了コード 0 / 3 / 6 に対応 |
| 通知レベル | `warning` / `error` | 警告 / 異常 | 小文字。件名の `{ALERT_SUBJECT_PREFIX}[warning]`(既定 `[relay-gate][warning]`)と本文の `level=warning` で同じ値 |
| 通知種別 | `hang-suspected` / `background-exec-error` / `rapid-crosscheck-error` | ハング疑い / background 実行エラー / 速報クロスチェック異常 | kebab-case。件名と本文 `kind=` で同じ値 |
| ハング検知判定結果 | `NOT_TARGET` / `COMPLETED` / `MONITORING` / `HANG_SUSPECTED` / `EXEC_ERROR` / `COMPARE_ERROR` | 監視対象外 / 正常終了(中止済み対象の終端を含む) / 継続監視 / ハング疑い / background 実行エラー / 速報クロスチェック異常(比較 NG・FAILED) | hang-detector の `--verbose` 出力とログにのみ現れる(`cli-command-contract.yaml` `shared_rules.state_codes.hang_judgement` と同じ 6 値)。監視状態への対応は NOT_TARGET → NOT_MONITORED、COMPLETED → COMPLETED、MONITORING → MONITORING、HANG_SUSPECTED → HANG_SUSPECTED_NOTIFIED、EXEC_ERROR → EXEC_ERROR_NOTIFIED、COMPARE_ERROR → COMPARE_ERROR_NOTIFIED |
| 実装スロット / run role | `blue` / `green` / `rapid-crosscheck` / `final-crosscheck` | — | 小文字。`--role` の引数値と同じ |
| 停止確認応答 | `yes` / `no` | — | ログの `answer=` に記録 |

- 色・記号は使わない。状態は文字列だけで伝える
- 状態の遷移を表示する場合は `from={旧} to={新}` の形式にする

## 通知メール規約

送信手段: OS 標準の `mail` / `sendmail` を gateway で呼ぶ。宛先・送信コマンド・件名プレフィックスは `hang-detector.env`(RDRA 情報「ハング検知定期ジョブ設定」。`ALERT_MAIL_TO` / `ALERT_MAIL_CMD` / `ALERT_SUBJECT_PREFIX`)で指定する。所有者は基盤適用設計者(設定所有区分「ハング検知定期ジョブ設定」)。認証情報は置かない。

- **件名**: `{ALERT_SUBJECT_PREFIX}[{warning|error}] {通知種別} run_id={run_id} job_id={job_id} role={role}`
  - `ALERT_SUBJECT_PREFIX` は任意キー。既定 `[relay-gate]`。以下の例は既定値
  - 例: `[relay-gate][warning] hang-suspected run_id=20260830T113000-JOB001-3f9a1c2e job_id=JOB001 role=green`
  - 例: `[relay-gate][error] rapid-crosscheck-error run_id=20260830T113000-JOB001-3f9a1c2e job_id=JOB001 role=rapid-crosscheck`
- **本文**: プレーンテキスト(`text/plain; charset=UTF-8`)。1 行 1 事実、`key=value` または `key: value`。空行で「事実」と「推奨対処」を区切る。HTML・添付ファイルは付けない
- **行長**: 80 桁制限は 1〜13 行目(事実部と空行)のうち 11 行目 `artifact_dir` を除く行に適用する。`artifact_dir` の `key: value` 行はパスが長くても折り返さない(80 桁制限の例外。BDD の「80 桁を超える行は無い」検証も 11 行目を除外する)。14 行目の `recommended_action` は定型文を折り返さず 1 行で出す(コピーしてそのまま実行できることを優先。15 行目以降なし)

| 行順 | キー | 値 | 備考 |
|---|---|---|---|
| 1 | `kind` | `hang-suspected` / `background-exec-error` / `rapid-crosscheck-error` | 通知種別 |
| 2 | `level` | `warning` / `error` | 通知レベル |
| 3 | `run_id` | run_id | |
| 4 | `job_id` | job_id | |
| 5 | `role` | `blue` / `green` / `rapid-crosscheck` | |
| 6 | `started_at` | ローカル ISO 8601(指示子なし) | started-at.txt(UTC 値をローカルへ変換して載せる)または依頼の started_at |
| 7 | `elapsed_minutes` | 整数 | 判定時点の経過時間(分) |
| 8 | `hang_detect_limit_minutes` | 整数 | execution-spec.json の role ごとの値。依頼の場合はクロスチェック側の値 |
| 9 | `exit_code` | 整数 または `-` | background-exec-error / rapid-crosscheck-error のみ値あり |
| 10 | `request_status` | 依頼状態 または `-` | rapid-crosscheck-error のみ |
| 11 | `artifact_dir` | 成果物ディレクトリの絶対パス | `key: value` 形式 |
| 12 | `detected_at` | ローカル ISO 8601(指示子なし) | hang-detector の判定日時 |
| 13 | (空行) | | |
| 14 | `recommended_action` | 推奨対処(英語の定型文。折り返さず 1 行。80 桁制限の対象外) | 下表 |

| 通知種別 | level | recommended_action(定型文) |
|---|---|---|
| `hang-suspected` | warning | `check the process on the execution host; if it is still running normally, wait. if it is hung, stop the process, then run: abort-{role}.sh --run-id {run_id}` |
| `background-exec-error` | error | `inspect {artifact_dir}/stderr.log; after fixing the cause, run the rerun job: background-rerun.sh --source-run-id {run_id} --role {role}` |
| `rapid-crosscheck-error` | error | `inspect the comparison result: rapid-crosscheck-result.sh --run-id {run_id}; this result is for investigation only and does not affect the scheduler response` |

- **冪等性**: 同じ監視対象 ID(run_id + role)・同じ通知種別のメールは 1 回だけ送る(監視記録の `monitor_status` の遷移有無で判定。判定結果に対応する監視状態が現在値と同じなら送らない。`alerted_at` は送信成功の記録であり判定根拠ではない)。ハング疑い通知後に実行エラー・比較異常へ遷移した場合は別種別として追加で 1 回送る
- **通知しない終端**: `exitcode.txt` が無く `aborted.txt` がある監視対象(中止済み)と、ABORTED の速報比較依頼は判定 `COMPLETED` として監視記録を終端し、メールは送らない。完了通知の送信失敗は監視対象外(条件「完了通知失敗の扱い」)
- **送信失敗**: 終了コード 6 で終了し、監視記録は `alerted_at` を更新しない(次回の定期実行で再送する)
- **日次メールサマリー**(arch CTP-010)は本規約の範囲外。採用する場合は件名 `[relay-gate][info] daily-summary date={business_date}`、本文は `data-visualization.md` 2. の警告傾向 TSV(`hang-detect-trend.sh --since {前日 00:00:00(ローカル)}` の出力)をそのまま貼る形を推奨する(仕様は未確定。todo。`data-visualization.md`「全体サマリー」と同文)

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

### 環境変数(環境変数名と既定値は仮採用。todo)

| 環境変数 | 用途 | 既定値 | 備考 |
|---|---|---|---|
| `RELAY_GATE_HOME` | relay-gate の配置ディレクトリ(スクリプトの所在) | スクリプト自身のディレクトリ(`$(dirname "$0")`) | 設定・成果物・ログの既定パスの解決に使う。slot runner と速報クロスチェック runner / worker の実体は feature flag(`BLUE_RUNNER` / `GREEN_RUNNER` / `RAPID_CROSSCHECK_RUNNER` / `RAPID_CROSSCHECK_WORKER`)で解決する(固定パス解決はしない) |
| `RELAY_GATE_CONFIG_DIR` | 設定ファイル置き場(`feature-flag.env`、`blue-job-map.csv` / `green-job-map.csv`、`crosscheck-job-map.csv`、`target-catalog.csv`、`rapid-crosscheck.env` / `hang-detector.env` / `final-crosscheck.env`) | `$RELAY_GATE_HOME/config` | 未設定かつ既定パスが無い場合は終了コード 2 |
| `RELAY_GATE_ARTIFACT_ROOT` | 成果物ルート。`$RELAY_GATE_ARTIFACT_ROOT/facade/<run_id>/` に Runner Result を置く | `$RELAY_GATE_HOME/var` | 書き込み不可は終了コード 6 |
| `RELAY_GATE_LOG_DIR` | 実行ログの出力先(`{script}.log`) | `$RELAY_GATE_HOME/log` | 書き込み不可は stderr に `warn:` を出して処理は継続する |
| `RELAY_GATE_NOW` | テスト専用の現在時刻注入(UTC ISO 8601 秒精度、`Z` 付き。例 `2026-08-30T12:45:00Z`)。設定時は全スクリプトの時刻取得(経過時間・`*_at` 列・`started-at.txt`・`aborted.txt`・`detected_at`)がこの値になる。`started-at.txt` / `aborted.txt` の中身はこの UTC 値のまま。run_id / final_crosscheck_id の時刻部・実行ログ・`*_at` 列・stdout の日時はこの UTC 値をプロセスのローカルタイムゾーン(`TZ`)へ変換した値(BDD の例示値は `TZ=UTC` 前提。`RELAY_GATE_NOW=2026-08-30T11:30:00Z` → run_id `20260830T113000`、ログ・stdout `2026-08-30T11:30:00`) | 未設定(実時刻) | 本番では設定しない。形式不正は終了コード 2。facade / background-rerun は runner にも引き継ぐ。run_id の乱数部は注入せず、テストでは形式パターンで照合する(`cli-command-contract.yaml` `environment_variables` / `shared_rules.run_id.test_verification`) |

- 管理 DB の接続参照名・lease / poll / polling 上限の設定キーは `cli-command-contract.yaml` の `config_files`(`rapid-crosscheck.env` / `hang-detector.env` / `final-crosscheck.env`)で定義する(本ファイルの範囲外)
- slot runner は `feature-flag.env` を自分で読まない。`facade.sh` / `background-rerun.sh` が読み、runner へ環境変数で渡す: 上記 4 つ(`RELAY_GATE_CONFIG_DIR` / `RELAY_GATE_ARTIFACT_ROOT` / `RELAY_GATE_LOG_DIR`)と `RAPID_CROSSCHECK_MODE`、off 以外のとき `RAPID_CROSSCHECK_RUNNER`(完了通知の送信先実体)、通常起動では自 slot の `BLUE_IMPL` / `GREEN_IMPL`(runner が `execution-spec.json` の `slots.<role>.impl_version` に転記。復元起動 `--execution-spec` では渡さない)
- 認証情報(SSH 鍵パス・DB パスワード)は環境変数の値として扱わず、参照名のみを設定に置く(arch CTP-002)

## アクセシビリティ・運用配慮

- 色だけで意味を伝えない(色を使わない)。重要度は `error:` / `warn:` / `info:` の接頭辞と、メール件名の `[warning]` / `[error]` で伝える
- スクリーンリーダー向けに 1 行 1 事実、キー名は固定順。TSV はヘッダー行必須、列数 8 以内
- 罫線・アスキーアート・絵文字・全角記号を出力しない(対話プロンプトの日本語文言を除く)
- ログ・監査との整合: stdout に出した状態値と実行ログ・管理レコードの状態値は同じ英字コードを使う。中止・リランは指示者と応答を実行ログに残す(NFR E.7.1.1)。監査の正本はジョブスケジューラであり、relay-gate のログは 3 ヶ月保管(NFR C.6.1.1)の障害調査・警告傾向確認用
- 出力は `grep` / `cut -f` / `awk -F'\t'` で処理できる。JSON・YAML パーサや jq を要求しない(エアーギャップ・bash 単独)
- 大量出力(worker の常駐ログなど)は stdout ではなく実行ログファイルへ出す。stdout は 1 回の起動で人が読める分量(数十行)に収める
- 長時間処理(final runner の polling 最大 8 時間)は進捗を stdout / stderr に出さず、実行ログに `INFO polling final_crosscheck_id=... status=RUNNING elapsed_minutes=...` を poll 間隔ごとに残す(キー名は `cli-command-contract.yaml` `final-crosscheck-runner.sh.stderr` と同じ)
