# hang_detect_limit_minutes をジョブごとに調整する - 実行監視・復旧ティア仕様

## 変更概要

`hang-detect-trend.sh` を追加する。管理 DB の `monitor_records` を job_id × role で集計し、警告傾向(警告回数・通知後正常終了件数・最後の警告時経過時間・現在の上限)を TSV で出力する参照系コマンドである。状態を変更しない。列定義の正本は `../../../_cross-cutting/ux-ui/data-visualization.md` 2. である。

## コマンド契約

### hang-detect-trend.sh

- **書式**: `hang-detect-trend.sh [--job-id JOB_ID] [--role blue|green|rapid-crosscheck] [--since LOCAL_DATETIME] [--limit N] [--all] [--verbose] [--help]`
- **アクセス権**: 運用者の直接起動(relay-gate 配置ディレクトリ)。管理 DB への読み取り接続が必要

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--job-id` | string | No | なし(全 job_id) | 絞り込む job_id。英数字・`_`・`-` のみ |
| `--role` | enum(blue / green / rapid-crosscheck) | No | なし(全 role) | 絞り込む監視対象 role |
| `--since` | string(ホストのローカルタイムゾーンの ISO 8601 秒精度。タイムゾーン指示子(Z / オフセット)なし。例 `2026-06-01T00:00:00`) | No | 実行時刻の 3 ヶ月前 | 集計期間の開始(`judged_at >= since`)。表示・監視記録の judged_at と同じ時刻軸なので変換しない |
| `--limit` | integer(1 以上) | No | 100 | 出力行数の上限。超過時は stderr に `warn: output truncated limit=100` |
| `--all` | boolean | No | false | `hang_suspected_count = 0` の行も出す(既定は `> 0` の行のみ) |
| `--verbose` | boolean | No | false | `info:` を stderr に出す |
| `--help` | boolean | No | false | 使い方を stdout に出して終了コード 0 |

- **stdin**: なし

## 出力契約

- **stdout**: TSV(タブ区切り、1 行目ヘッダー)。列順は固定
  `job_id	role	run_count	hang_suspected_count	completed_after_alert_count	max_elapsed_minutes_at_alert	last_elapsed_minutes_at_alert	current_limit_minutes`
  - 空値は `-`。整数列は整数のみ
  - ソート: `last_elapsed_minutes_at_alert` 降順(`-` は末尾)→ `job_id` 昇順 → `role` の固定順(blue → green → rapid-crosscheck)
  - 該当行が無い場合はヘッダー行のみ
- **stderr**: `error: management db is not configured (RAPID_CROSSCHECK_MODE=off)`(3)/ `error: config file not found path: ...`(2。feature-flag.env / rapid-crosscheck.env 不在)/ `error: option required option=RAPID_DB_CONN_REF path: ...`(2)/ `error: management db query failed ...`(6)/ `error: invalid value option=--role|--since|--limit|--job-id value=...`(2)/ `error: unknown option option=...`(2)/ `warn: output truncated limit=N` / `info: ...`(--verbose。ui-design.md のメッセージ表現規約)
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 集計して出力した(0 行でも 0) |
  | 2 | 入力エラー | 未知のオプション、`--role` が列挙外、`--since` がローカル ISO 8601 秒精度・指示子なしの形式でない(Z / オフセット付きを含む)、`--limit` が 1 未満または非整数、job_id 形式不正、設定ファイル不在・`RAPID_DB_CONN_REF` 欠落(設定契約の定型文) |
  | 3 | 業務エラー | RAPID_CROSSCHECK_MODE=off(`error: management db is not configured (RAPID_CROSSCHECK_MODE=off)`)|
  | 6 | 実行エラー | 管理 DB 接続・SQL 失敗(`error: management db query failed ...`) |

出力例:

```text
$ hang-detect-trend.sh --job-id JOB001
job_id	role	run_count	hang_suspected_count	completed_after_alert_count	max_elapsed_minutes_at_alert	last_elapsed_minutes_at_alert	current_limit_minutes
JOB001	green	3	2	2	82	82	60
```

## UC ロジック

- **バリデーション**: presentation 層で引数を検証し、NG は状態を読む前に終了コード 2。`--key=value` 形式は受け付けない
- **確認プロンプト**: なし(参照系)
- **冪等性**: 読み取りのみ。同じ入力・同じ DB 内容で同じ出力
- **集計(usecase / repository)**:
  1. `RELAY_GATE_CONFIG_DIR` の feature flag を読み `RAPID_CROSSCHECK_MODE=off` なら終了コード 3(監視記録が実行ログにしか無いため)
  2. `monitor_records.job_id` 列を集計キーに使う(parallel_runs とは JOIN しない。C2)
  3. `monitor_status <> 'NOT_MONITORED' AND judged_at >= since` で絞り、job_id × role で集計する(計算式は spec.md「計算ルール一覧」)
  4. `current_limit_minutes` は job_id × role で集計期間内の `monitor_records.judged_at` が最大の行の `hang_detect_limit_minutes`(data-visualization.md 2. の列定義に従う)
  5. 既定は `hang_suspected_count > 0` の行のみ。`--all` で全行
- **エラーハンドリング**: DB エラーは gateway が非 0 で返し usecase が 1 回だけログ出力、presentation が終了コード 6 を決める
- **クラッシュ耐性**: 書き込みが無いため途中終了でも残るレコード・ファイルは無い。再実行はそのままやり直す
- **実行ログ**: `RELAY_GATE_LOG_DIR/hang-detect-trend.sh.log` に `hang-detect-trend.sh - {ローカル日時} INFO query since=... job_id=... role=... rows=N` を残す(run_id は `-`)。ログ行形式は `_cross-cutting/ux-ui/ui-design.md` の `{script} {run_id} {ローカル出力日時} {LEVEL} {message}` に従い、情報「実行ログ」の属性「出力日時」はこの ローカル時刻列に対応する

## 調整運用(手順)

1. `hang-detect-trend.sh --job-id {JOB_ID}` で `last_elapsed_minutes_at_alert` と `current_limit_minutes` を比較する
2. `completed_after_alert_count` が増えなくなった(正常終了パターンの警告が出そろった)時点で、`last_elapsed_minutes_at_alert` を基準に該当 slot のジョブマップ(CSV)の `hang_detect_limit_minutes` を編集する(tier-facade.md 参照)
3. 調整日時と調整根拠(`last_elapsed_minutes_at_alert`)を適用構成文書の「運用者の調整記録」に残す(ジョブマップの列・監視記録には持たない)
4. foreground role は 0 のままにする(検知対象外)
5. 変更は次回以降の run から有効になる。実行済み run・RUNNING 中の run の判定基準は変わらない

## データモデル変更

### monitor_records(読み取りのみ)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | 監視対象 run_id(PK 1) | 追加 |
| role | string | 監視対象 role(PK 2)。blue / green / rapid-crosscheck | 追加 |
| target_type | string | background_slot / rapid_request | 追加 |
| job_id | string | JOB_ID(集計キー。C2) | 追加 |
| monitor_status | string | NOT_MONITORED / MONITORING / HANG_SUSPECTED_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED / COMPLETED | 追加 |
| started_at | datetime | 監視対象の開始時刻(ローカル時刻。指示子なし)。background slot は started-at.txt の UTC 値をローカル時刻へ変換した値、速報比較依頼(role=rapid-crosscheck)は依頼の started_at(未開始は requested_at) | 追加 |
| elapsed_minutes | integer | 判定時点の経過時間(分) | 追加 |
| hang_detect_limit_minutes | integer | 判定に使った上限(分)。background slot は execution-spec.json の slots.<role>.hang_detect_limit_minutes、速報比較依頼は hang-detector.env の RAPID_HANG_DETECT_LIMIT_MINUTES(既定 60)を転記 | 追加 |
| hang_suspected_at | datetime | ハング疑い通知(hang-suspected)の送信成功日時(MONITORING → HANG_SUSPECTED_NOTIFIED の時刻。未通知は NULL) | 追加 |
| alerted_at | datetime | 通知日時(NULL 可) | 追加 |
| elapsed_minutes_at_alert | integer | 警告時の経過時間(NULL 可) | 追加 |
| judged_at | datetime | 最終判定日時 | 追加 |

## 設定契約

- **環境変数**: `RELAY_GATE_CONFIG_DIR`(設定ファイルの所在)/ `RELAY_GATE_LOG_DIR`(実行ログ)/ `RELAY_GATE_NOW`(テスト専用。UTC ISO 8601 Z 付きで受け取りローカル時刻へ変換する。`--since` 既定値「3 ヶ月前」の基準時刻)
- **feature-flag.env**(`$RELAY_GATE_CONFIG_DIR/feature-flag.env`。9 キー): `RAPID_CROSSCHECK_MODE`(foreground / background / off)を読む。`off` は `error: management db is not configured (RAPID_CROSSCHECK_MODE=off)` で終了コード 3。ファイル不在は `error: config file not found path: ...`(2)
- **rapid-crosscheck.env**(`$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env`。RDRA 情報「速報クロスチェック設定」。所有者: 基盤適用設計者(設定所有区分: 速報クロスチェック設定)。off 以外のときのみ): 属性「管理 DB 接続参照名」= `RAPID_DB_CONN_REF` を管理 DB の読み取り接続に使う(契約 config_files.rapid-crosscheck.env.readers)。ファイル不在は `error: config file not found path: ...`(2)、キー欠落は `error: option required option=RAPID_DB_CONN_REF path: ...`(2)。接続情報の値は保持・出力しない
- **hang-detector.env** は読まない(rapid-crosscheck の上限は monitor_records.hang_detect_limit_minutes に転記済みの値を使う)

## ビジネスルール

- hang_detect_limit_minutes は導入時に全ジョブ 60 分、foreground role は 0(条件「ハング検知上限の調整基準」「ハング検知対象の除外」)
- 調整基準は「最後の警告の経過時間」(`last_elapsed_minutes_at_alert`)。正常終了パターンの警告が出そろってから調整する
- 上限の正本は該当 slot のジョブマップ(条件「設定所有区分」)。`hang-detect-trend.sh` は RDB・ジョブマップ・execution-spec.json を変更しない。調整記録(調整日時・調整根拠)の正本は適用構成文書
- 変更は次回以降の run の execution-spec.json にのみ反映される(条件「実行設定の確定条件」)
- RAPID_CROSSCHECK_MODE=off では監視記録が実行ログのみのため集計できない(採用値 #8。運用ガイドの grep 手順に委ねる)。C2 の `job_id` 列は off 以外のときの集計を parallel_runs 非依存にするためのもので、off 時の終了コード 3 は変わらない

## ティア完了条件(BDD)

```gherkin
Feature: hang_detect_limit_minutes をジョブごとに調整する - 実行監視・復旧ティア

  Scenario: job_id で絞り込んで警告傾向を TSV で出す
    Given RAPID_CROSSCHECK_MODE=background で monitor_records に JOB001 × green の COMPLETED 行が 3 件(うち alerted_at 非 NULL が 2 件、elapsed_minutes_at_alert=75, 82)ある
    When `hang-detect-trend.sh --job-id JOB001` を実行する
    Then 終了コード 0 で stdout の 2 行目が `JOB001	green	3	2	2	82	82	60` である

  Scenario: 既定では警告のない行を出さない
    Given monitor_records に JOB002 × green の行が 5 件あり hang_suspected_at がすべて NULL である
    When `hang-detect-trend.sh --job-id JOB002` を実行する
    Then 終了コード 0 で stdout はヘッダー行のみである
    And `hang-detect-trend.sh --job-id JOB002 --all` では `JOB002	green	5	0	0	-	-	60` が出る

  Scenario: 管理 DB 未設定は終了コード 3
    Given RAPID_CROSSCHECK_MODE=off である
    When `hang-detect-trend.sh` を実行する
    Then 終了コード 3 で stderr に `error: management db is not configured (RAPID_CROSSCHECK_MODE=off)` が出る

  Scenario: 不正な --limit は終了コード 2
    When `hang-detect-trend.sh --limit 0` を実行する
    Then 終了コード 2 で stderr に `error: invalid value option=--limit value=0` が出る

  Scenario: --since はローカル日時(指示子なし)で受け取る
    Given RAPID_CROSSCHECK_MODE=background で monitor_records に JOB001 × green の行が judged_at=2026-08-01T03:30:00 / 2026-08-15T03:40:00 / 2026-08-29T02:50:00(ローカル時刻。TZ=UTC 前提)の 3 件ある
    When `hang-detect-trend.sh --job-id JOB001 --since 2026-08-10T00:00:00 --all` を実行する
    Then 終了コード 0 で、データ行の run_count は 2 である(judged_at >= since を変換なしで比較する)
    And `hang-detect-trend.sh --since 2026-08-10T00:00:00Z` は終了コード 2 で stderr に `error: invalid value option=--since value=2026-08-10T00:00:00Z` が出る
```
