# 監視記録を保存する - 実行監視・復旧ティア仕様

## 変更概要

`hang-detector.sh` の記録部分を追加する。usecase(判定結果・alert 行を出した事実 → MonitorRecord → 保存)、domain(記録の組み立て。警告時経過時間の保持規則)、repository(`monitor_records` の UPSERT / 実行ログ)、gateway(RDB クライアントアダプタ)。コマンド契約は UC「background 実行の経過時間と終了状態を判定する」の tier md を正とし、本ファイルは記録に固有の契約(テーブル定義・UPSERT 規則・off 時のログ形式)を書く。`monitor_records` は tier-ops が所有する唯一の書き込みテーブルであり、`hang-detect-trend.sh`(UC「hang_detect_limit_minutes をジョブごとに調整する」)の集計元になる。

## コマンド契約

### hang-detector.sh(記録部分)

- **書式**: `hang-detector.sh [--verbose]`(UC「background 実行の経過時間と終了状態を判定する」を参照)
- **アクセス権**: ジョブスケジューラの定期ジョブ。RAPID_CROSSCHECK_MODE が off 以外のとき管理 DB(接続参照名はハング検知定期ジョブ設定の HANG_DB_CONN_REF)の `monitor_records` への INSERT / UPDATE 権限
- **トリガー**: 同 UC の判定と UC「ハング疑い・実行エラー・比較異常を通知する」の呼び出し(alert 行を出した対象は alert 行の直後に呼ばれる)

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| (追加なし) | — | — | — | 記録の有無はオプションで制御しない |

- **stdin**: なし

## 出力契約

- **stdout**: 出力しない
- **stderr**: `error: monitor record save failed run_id=... role=...`(1 対象につき 1 回。alert 行を出した対象ではその alert 行の直後)
- **終了コード**: UPSERT 失敗が 1 件でもあれば 6(他の対象は継続)。それ以外は判定 UC の終了コード表に従う
- **実行ログ**(RAPID_CROSSCHECK_MODE によらず常に追記): `INFO monitor record run_id=... role=... job_id=... target_type=... monitor_status=... started_at=... elapsed_minutes=... limit_minutes=... hang_suspected_at=... alerted_at=... elapsed_minutes_at_alert=... judged_at=...`(NULL は `-`)。off ではこの行が判定結果の記録先になり、通知済み状態は成果物ルート配下の通知済みの印で持つ(ハング疑いを知らせたあとで正常終了・中止した対象は、印が COMPLETED に書き換わって終端する。印の契約は UC「ハング疑い・実行エラー・比較異常を通知する」の tier 仕様)
  - ログ行の形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {ローカル出力日時} {LEVEL} {message}`)に従う。情報「実行ログ」の属性「出力日時」はこの ローカル出力日時の列に対応する(judged_at は message 内の値で、出力日時とは別)

## UC ロジック

- **バリデーション**: なし(入力は同一プロセス内の判定結果)
- **確認プロンプト**: なし
- **冪等性**: UPSERT(主キー run_id + role)。同じ判定を繰り返しても行は 1 件で、elapsed_minutes / judged_at が更新されるだけ。hang_suspected_at / alerted_at / elapsed_minutes_at_alert は NULL で上書きしない(`COALESCE(EXCLUDED.x, monitor_records.x)`。alerted_at のみ alert 行を出したときは新しい値で上書き)
- **記録規則**(domain `build_record`):
  | 入力 | monitor_status | hang_suspected_at | alerted_at | elapsed_minutes_at_alert |
  |---|---|---|---|---|
  | NOT_TARGET(監視対象外) | NOT_MONITORED | 保持 | 保持 | 保持 |
  | COMPLETED(正常終了、または中止済み = exitcode.txt なし・aborted.txt あり / 依頼 ABORTED(abort-blue / abort-green による未着手依頼の中止を含む)) | COMPLETED | 保持 | 保持 | 保持 |
  | MONITORING | MONITORING(既存が *_NOTIFIED なら既存を保持) | 保持 | 保持 | 保持 |
  | alert 行を出した: hang-suspected | HANG_SUSPECTED_NOTIFIED | now(既存があれば保持) | now | elapsed(既存があれば保持) |
  | alert 行を出した: background-exec-error | EXEC_ERROR_NOTIFIED | 保持 | now | elapsed(既存があれば保持) |
  | alert 行を出した: rapid-crosscheck-error | COMPARE_ERROR_NOTIFIED(既存が HANG_SUSPECTED_NOTIFIED でも遷移する) | 保持 | now | elapsed(既存があれば保持) |
  | 通知済みで知らせなかった | 既存を保持 | 保持 | 保持 | 保持 |
  - `elapsed_minutes` / `judged_at` / `hang_detect_limit_minutes` / `started_at` は毎回の判定値で更新する
  - 入力は判定 UC の hang_judgement 6 値(NOT_TARGET / COMPLETED / EXEC_ERROR / MONITORING / HANG_SUSPECTED / COMPARE_ERROR)と、通知 UC が alert 行を出したかどうか。alert 行を出した対象の monitor_status は判定値だけで決まる(CLI 契約 `shared_rules.state_codes.hang_judgement_to_monitor_status`)
  - now は alert 行を出した回の判定時刻。hang_suspected_at / alerted_at はこの値を記録する
  - UPSERT に失敗した場合は行が変わらない(monitor_status も変わらない)ため、通知 UC は次回同じ異常を再び知らせる
  - execution-spec.json が無い run は判定 UC が飛ばすため、この UC に渡されず記録も作らない
  - now は判定 UC と同じ(`RELAY_GATE_NOW` 設定時はその UTC 値をローカル時刻へ変換した値)。日時列(started_at / hang_suspected_at / alerted_at / judged_at)はホストのローカルタイムゾーンの値(ISO 8601 秒精度・指示子なし)を RDB のタイムスタンプ型(タイムゾーンなし)に入れる。started_at は started-at.txt の UTC Z 付きの値をローカル時刻へ変換して転記する
  - MONITORING の入力で既存が *_NOTIFIED の場合(ハング疑い通知後にまだ exitcode.txt が無い)は状態を戻さない
- **off 時**: 管理 DB に接続しない。判定結果は実行ログの `INFO monitor record` 行に残り、通知済み状態は通知 UC が書く通知済みの印で持つ(HANG_SUSPECTED_NOTIFIED → COMPLETED のときも通知 UC が印を書き換える)。`hang-detect-trend.sh` は off では終了コード 3(data-visualization.md)。off で経過時間の傾向を確認するときは、ハング検知ジョブの出力(alert 行の elapsed_minutes)と実行ログの `INFO monitor record` 行を使う
- **エラーハンドリング**: その回に管理 DB へ接続できなかった場合(判定 UC が `error: management db connection failed` を出した回)は UPSERT を試みず、実行ログの `INFO monitor record` 行だけを残す。UPSERT 失敗は `error:` 1 回 + 実行ログ ERROR。他の対象を継続して最後に 6。実行ログの書き込み不可は `warn:` で継続(ui-design.md 環境変数)
- **クラッシュ耐性**: UPSERT は 1 対象 1 文で原子的。途中終了しても部分更新の行は生じない。alert 行を出したあと記録前にプロセスが終了した場合は、次回同じ異常を再び知らせる(通知 UC のクラッシュ耐性)
- **監視は通知のみ**: `monitor_records` 以外のテーブルに書かない(LP-017)。`rapid_crosscheck_requests` には SELECT しか発行せず(判定 UC)、`slot_executions` / `parallel_runs` には触れない(slot 実行の状態は成果物ファイルから導出する)

## データモデル変更

### monitor_records(新規。datastore_owner: tier-ops の書き込み。参照は hang-detect-trend.sh)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | 監視対象の run_id(主キーの一部) | 追加 |
| role | string | `blue` / `green` / `rapid-crosscheck`(主キーの一部) | 追加 |
| job_id | string | execution-spec.json または依頼の job_id(警告傾向の集計キー。step3 canonical C2 で確定。off モードで parallel_runs が無くても `hang-detect-trend.sh` が集計できるようにする) | 追加 |
| target_type | string | `background_slot` / `rapid_request` | 追加 |
| monitor_status | string | NOT_MONITORED / MONITORING / HANG_SUSPECTED_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED / COMPLETED(状態モデル「監視状態」の 6 値: 監視対象外 / 監視中 / ハング疑い通知済み / 実行エラー通知済み / 比較異常通知済み / 正常終了。中止済みは COMPLETED) | 追加 |
| started_at | datetime | 監視対象の開始時刻(ローカル時刻)。background slot は started-at.txt の UTC 値をローカル時刻へ変換した値、速報比較依頼は依頼の started_at(未開始は requested_at) | 追加 |
| elapsed_minutes | integer | 最新の判定時点の経過時間(分) | 追加 |
| hang_detect_limit_minutes | integer | background slot は execution-spec.json の slots.<role>.hang_detect_limit_minutes を転記(0 は対象外)、速報比較依頼(role=rapid-crosscheck)は hang-detector.env の RAPID_HANG_DETECT_LIMIT_MINUTES(既定 60)を転記(rdb-schema.yaml の列説明と同じ) | 追加 |
| hang_suspected_at | datetime | 最初にハング疑いの alert 行を出した回の判定時刻(NULL 可) | 追加 |
| alerted_at | datetime | 最後に alert 行を出した回の判定時刻(NULL 可。記録用で、再通知の判定には使わない) | 追加 |
| elapsed_minutes_at_alert | integer | 最初の警告時の経過時間(NULL 可)。調整根拠 | 追加 |
| judged_at | datetime | 最新の判定時刻(ローカル時刻。指示子なし) | 追加 |

- 主キー: (run_id, role)
- インデックス: (job_id, role, judged_at)(rdb-schema.yaml `idx_monitor_records_job_id_role_judged_at`)— `hang-detect-trend.sh` の `--since` 絞り込みと集計 / (monitor_status) — 未終端の走査
- UPSERT(RDB 方言は gateway で吸収。CTR-003): `INSERT INTO monitor_records (...) VALUES (...) ON CONFLICT (run_id, role) DO UPDATE SET monitor_status=EXCLUDED.monitor_status, elapsed_minutes=EXCLUDED.elapsed_minutes, hang_detect_limit_minutes=EXCLUDED.hang_detect_limit_minutes, started_at=EXCLUDED.started_at, judged_at=EXCLUDED.judged_at, hang_suspected_at=COALESCE(monitor_records.hang_suspected_at, EXCLUDED.hang_suspected_at), alerted_at=COALESCE(EXCLUDED.alerted_at, monitor_records.alerted_at), elapsed_minutes_at_alert=COALESCE(monitor_records.elapsed_minutes_at_alert, EXCLUDED.elapsed_minutes_at_alert)`

## ビジネスルール

- 警告傾向の記録: monitor_status / hang_suspected_at / alerted_at を記録。通知後正常終了でも elapsed_minutes_at_alert を保持
- 監視は通知のみ: monitor_records 以外を変更しない
- 速報クロスチェック有効判定: off では判定結果を実行ログに残し、通知済み状態は通知済みの印で持つ。foreground / background(off 以外)では UPSERT + 実行ログ
- 監視状態の値は状態.tsv の英字コード(_inference.md #11)。バリエーション「監視状態」と状態モデル「監視状態」は同じ 6 値(「通知後正常終了」はハング疑い通知済み → 正常終了の遷移の別名)

## ティア完了条件(BDD)

```gherkin
Feature: 監視記録を保存する - 実行監視・復旧ティア

  Scenario: 初回判定で行を INSERT する
    Given RAPID_CROSSCHECK_MODE=background で monitor_records が空である
    And facade/20260830T113000-JOB001-3f9a1c2e/ の green が MONITORING と判定される(elapsed_minutes=29 limit=60)
    When `hang-detector.sh` を実行する
    Then monitor_records に (run_id=20260830T113000-JOB001-3f9a1c2e, role=green) の行が 1 件あり monitor_status=MONITORING elapsed_minutes=29 hang_detect_limit_minutes=60 である

  Scenario: 2 回目の判定で同じ行を UPDATE する
    Given 前のシナリオの後、5 分経過して elapsed_minutes=34 になった
    When `hang-detector.sh` を再実行する
    Then monitor_records の行数は 1 のままで、該当行は elapsed_minutes=34 に更新され judged_at が進む

  Scenario: 通知後正常終了でも警告時経過時間を保持する
    Given 該当行が HANG_SUSPECTED_NOTIFIED hang_suspected_at=2026-08-30T12:45:00 elapsed_minutes_at_alert=74 で、green/exitcode.txt に 0 が書かれた
    When `hang-detector.sh` を実行する
    Then 該当行は monitor_status=COMPLETED で hang_suspected_at=2026-08-30T12:45:00 elapsed_minutes_at_alert=74 のままである

  Scenario: 中止済みの slot 実行は COMPLETED で終端する
    Given 該当行が HANG_SUSPECTED_NOTIFIED で、green/exitcode.txt が無く green/aborted.txt が書かれた
    When `hang-detector.sh` を実行する
    Then 該当行は monitor_status=COMPLETED になり、次回の `hang-detector.sh` はこの行を走査対象にしない

  Scenario: off では管理 DB に触れない
    Given RAPID_CROSSCHECK_MODE=off でハング検知定期ジョブ設定の HANG_DB_CONN_REF が未設定である
    When `hang-detector.sh` を実行する
    Then 終了コード 0 で、hang-detector.sh.log に "INFO monitor record run_id=20260830T113000-JOB001-3f9a1c2e role=green" で始まる行が残る
```
