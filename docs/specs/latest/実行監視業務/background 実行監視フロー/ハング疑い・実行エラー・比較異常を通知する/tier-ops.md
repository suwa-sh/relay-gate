# ハング疑い・実行エラー・比較異常を通知する - 実行監視・復旧ティア仕様

## 変更概要

`hang-detector.sh` の通知部分を追加する。usecase(遷移判定 → メール組み立て → 送信 → 記録 UC へ)、domain(通知レベル対応表・冪等判定・件名 / 本文の組み立て)、gateway(OS メール送信コマンドのアダプタ)。コマンド契約(引数・終了コード)は UC「background 実行の経過時間と終了状態を判定する」の tier md を正とし、本ファイルは通知に固有の契約を書く。

## コマンド契約

### hang-detector.sh(通知部分)

- **書式**: `hang-detector.sh [--verbose]`(UC「background 実行の経過時間と終了状態を判定する」を参照)
- **アクセス権**: ジョブスケジューラの定期ジョブ。メール送信コマンドの実行権限を持つ OS ユーザー
- **トリガー**: 同 UC の判定結果(EXEC_ERROR / HANG_SUSPECTED / COMPARE_ERROR)

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| (追加なし) | — | — | — | 通知の有無はオプションで制御しない(dry-run は提供しない) |

- **stdin**: なし

#### 設定契約(hang-detector.env、仮採用: _inference.md #10。RDRA に無い設定エンティティのため rdra-feedback 対象)

| キー | 型 | 必須 | 既定値 | 検証ルール |
|------|---|------|-------|-----------|
| `ALERT_MAIL_TO` | string | Yes | — | 宛先。カンマ区切りで複数可。空は終了コード 2 |
| `ALERT_MAIL_CMD` | string | Yes | — | 送信コマンドの絶対パス(例 `/usr/bin/mail`、`/usr/sbin/sendmail`)。実行可能でなければ終了コード 2 |

- 送信方法(仮採用): `ALERT_MAIL_CMD` が `mail` 系なら `"$ALERT_MAIL_CMD" -s "$subject" "$ALERT_MAIL_TO" < body.txt`、`sendmail` 系なら `Subject:` / `To:` / `Content-Type: text/plain; charset=UTF-8` ヘッダを本文先頭に付けて `"$ALERT_MAIL_CMD" -t < message.txt`。判定はコマンド名の末尾(`mail` / `mailx` / `sendmail`)で行う。それ以外は `mail` 系として扱う

## 出力契約

- **stdout**: 出力しない
- **stderr**: `error: mail send failed run_id=... role=... kind=... cmd_exit_code=N`(1 対象につき 1 回)、`--verbose` 時 `info: alert sent run_id=... role=... kind=... level=...` / `info: alert skipped already notified run_id=... role=... kind=...`
- **終了コード**: 送信失敗が 1 件でもあれば 6(他の対象の処理は継続したうえで最後に 6)。それ以外は判定 UC の終了コードに従う
- **通知メール**(ui-design.md「通知メール規約」を正とする):
  - 件名: `[relay-gate][{warning|error}] {hang-suspected|background-exec-error|rapid-crosscheck-error} run_id={run_id} job_id={job_id} role={blue|green|rapid-crosscheck}`
  - 本文: `text/plain; charset=UTF-8`。行順 1〜12 は `kind` / `level` / `run_id` / `job_id` / `role` / `started_at` / `elapsed_minutes` / `hang_detect_limit_minutes`(依頼は RAPID_HANG_DETECT_LIMIT_MINUTES)/ `exit_code`(hang-suspected は `-`)/ `request_status`(rapid-crosscheck-error 以外は `-`)/ `artifact_dir: <絶対パス>` / `detected_at`。13 行目は空行。14 行目は `recommended_action: <定型文>` の 1 行(定型文は下表)。**80 桁制限は 1〜13 行目のうち 11 行目 `artifact_dir:` を除く行に適用する**(artifact_dir は折り返さず 80 桁を超えてよい。ui-design.md「行長」/ asyncapi HangAlertMail と同じ)。14 行目は折り返さず 1 行で出す(80 桁を超えてよい。メールクライアントの表示折り返しに委ねる。run_id 付きコマンドをコピーしやすくするため)。15 行目以降は無い
  - `detected_at` は判定 UC と同じ now(`RELAY_GATE_NOW` 設定時はその値)
  - `artifact_dir` は background slot なら `<ARTIFACT_ROOT>/facade/<run_id>/<role>`、速報比較依頼なら `<ARTIFACT_ROOT>/facade/<run_id>/rapid-crosscheck`(ディレクトリが無くてもパスを出す)

| 通知種別 | level | recommended_action |
|---|---|---|
| `hang-suspected` | warning | `check the process on the execution host; if it is still running normally, wait. if it is hung, stop the process, then run: abort-{role}.sh --run-id {run_id}` |
| `background-exec-error` | error | `inspect {artifact_dir}/stderr.log; after fixing the cause, run the rerun job: background-rerun.sh --source-run-id {run_id} --role {role}` |
| `rapid-crosscheck-error` | error | `inspect the comparison result: rapid-crosscheck-result.sh --run-id {run_id}; this result is for investigation only and does not affect the scheduler response` |

- 実行ログ: `INFO alert sent run_id=... role=... kind=... level=... to=...`(本文は複写しない)/ `INFO alert skipped already notified ...` / gateway `INFO mail started cmd=... to=...` / `INFO mail finished exit_code=0 duration_ms=...` / `ERROR mail send failed exit_code=...`
  - ログ行の形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {UTC 出力日時} {LEVEL} {message}`)に従う。情報「実行ログ」の属性「出力日時」はこの UTC 出力日時の列に対応する
- 本文 `recommended_action` に埋め込むコマンド行(`abort-{role}.sh --run-id` / `background-rerun.sh --source-run-id --role` / `rapid-crosscheck-result.sh --run-id`)は cli-command-contract.yaml の各 synopsis を参照する(synopsis が変わると定型文も追従する。`_api-summary.yaml` に `uses` で宣言)

## UC ロジック

- **バリデーション**: `ALERT_MAIL_TO` 非空、`ALERT_MAIL_CMD` が実行可能。起動時(走査前)に検証し、NG なら終了コード 2 で何も走査しない
- **確認プロンプト**: なし
- **冪等性**(通知の二重送信防止):
  - on: `monitor_records.monitor_status` を読み、遷移が発生する場合だけ送る。送信成功時に記録 UC が monitor_status / alerted_at / elapsed_minutes_at_alert を更新する。送信失敗時は更新しない(次回再送)
  - off: `monitor_records` が無いため、`hang-detector.sh.log` 内の `INFO alert sent run_id=<run_id> role=<role> kind=<kind>` の有無で判定する(仮採用: off では実行ログが監視記録の代替。ログをローテーションすると再送の可能性がある旨を運用ガイドに記載)
  - 遷移表: MONITORING(または記録なし)→ HANG_SUSPECTED_NOTIFIED / EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED、HANG_SUSPECTED_NOTIFIED → EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED(HANG_SUSPECTED_NOTIFIED → COMPARE_ERROR_NOTIFIED は状態.tsv に無い遷移。仮採用)。EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED / COMPLETED / NOT_MONITORED からは送らない
- **エラーハンドリング**: 送信失敗は `error:` 1 回 + 実行ログ ERROR。他の対象の通知・記録は継続し、最後に終了コード 6。メールコマンドのタイムアウトは 30 秒(仮採用。`timeout 30` で起動し、超過は失敗扱い)
- **クラッシュ耐性**: 送信後・記録前にプロセスが落ちると次回に同じメールが再送される(記録が更新されていないため)。再送は「二重送信しない」の例外として許容し、記録 UC の UPSERT を送信直後に行うことで窓を最小にする
- **監視は通知のみ**: メール送信以外の副作用を持たない。`abort-*` / `background-rerun` / 依頼 INSERT を呼ばない(LP-017)

## 非同期イベント

### hang-alert-mail(publish)

- **チャネル**: OS メール送信コマンド(`ALERT_MAIL_CMD`)→ 運用者
- **方向**: publish
- **AsyncAPI**: [asyncapi.yaml](../../../_cross-cutting/api/asyncapi.yaml) の `channels.hang-alert-mail` を参照
- **メッセージ**: HangAlertMail(subject, kind, level, run_id, job_id, role, started_at, elapsed_minutes, hang_detect_limit_minutes, exit_code, request_status, artifact_dir, detected_at, recommended_action)

## データモデル変更

### monitor_records(参照。更新は UC「監視記録を保存する」)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id / role | string | 主キー | 追加(参照) |
| monitor_status | string | 冪等判定の入力 | 追加(参照) |
| alerted_at | datetime | 送信成功時に記録 UC が更新 | 追加(参照) |

## ビジネスルール

- 通知レベルの判定: ハング疑い = warning、background 実行エラー / 速報クロスチェック異常 = error
- 速報比較依頼の異常判定: FAILED / 比較 NG → error、RUNNING 上限超過 → warning(状態は変更しない)
- 監視は通知のみ: 状態変更・プロセス停止・依頼作成をしない
- 同じ監視対象・同じ通知種別のメールは 1 回だけ。ハング疑い通知後の実行エラー / 速報クロスチェック異常は別種別として 1 回
- 送信失敗は終了コード 6、alerted_at を更新しない(次回再送)
- メール本文・件名は英語(CTR-005)。HTML・添付なし

## ティア完了条件(BDD)

```gherkin
Feature: ハング疑い・実行エラー・比較異常を通知する - 実行監視・復旧ティア

  Scenario: warning メールを 1 通送る
    Given hang-detector.env に ALERT_MAIL_TO=ops@example.invalid ALERT_MAIL_CMD=/tmp/relay-gate-test/mail-stub(受け取った件名と本文をファイルに保存して 0 を返す)がある
    And run_id=20260830T113000Z-JOB001-3f9a1c2e role=green の判定が HANG_SUSPECTED で monitor_records に該当行が無い
    When `hang-detector.sh --verbose` を実行する
    Then mail-stub が 1 回だけ起動され、件名は "[relay-gate][warning] hang-suspected run_id=20260830T113000Z-JOB001-3f9a1c2e job_id=JOB001 role=green" である
    And 本文の 1 行目は "kind=hang-suspected"、2 行目は "level=warning"、13 行目は空行、14 行目は "recommended_action: check the process on the execution host; if it is still running normally, wait. if it is hung, stop the process, then run: abort-green.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e" の 1 行で、本文は 14 行である
    And 11 行目 `artifact_dir:` を除く 1〜13 行目に 80 桁を超える行は無い(11 行目と 14 行目は折り返さず 80 桁を超えてよい)
    And stderr に "info: alert sent run_id=20260830T113000Z-JOB001-3f9a1c2e role=green kind=hang-suspected level=warning" が出る

  Scenario: 2 回目の実行では送らない
    Given 前のシナリオの後、monitor_records の該当行が HANG_SUSPECTED_NOTIFIED である
    When `hang-detector.sh --verbose` を再実行する
    Then mail-stub は起動されず、stderr に "info: alert skipped already notified run_id=20260830T113000Z-JOB001-3f9a1c2e role=green kind=hang-suspected" が出る

  Scenario: ALERT_MAIL_TO が空
    Given RELAY_GATE_CONFIG_DIR=/etc/relay-gate で、hang-detector.env の ALERT_MAIL_TO が空である
    When `hang-detector.sh` を実行する
    Then 終了コード 2 で stderr に "error: option required option=ALERT_MAIL_TO path: /etc/relay-gate/hang-detector.env" が出て、走査は行われない(ui-design.md の必須キー欠落の定型文。契約 hang-detector.sh stderr と同文)

  Scenario: メール送信コマンドが失敗する
    Given ALERT_MAIL_CMD が終了コード 1 を返す
    And 判定が EXEC_ERROR で monitor_records の該当行が MONITORING である
    When `hang-detector.sh` を実行する
    Then 終了コード 6 で stderr に "error: mail send failed run_id=20260830T113000Z-JOB001-3f9a1c2e role=green kind=background-exec-error cmd_exit_code=1" が出る
    And monitor_records の該当行は MONITORING のままである
```
