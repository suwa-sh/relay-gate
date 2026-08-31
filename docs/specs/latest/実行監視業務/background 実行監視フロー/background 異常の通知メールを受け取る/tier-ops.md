# background 異常の通知メールを受け取る - 実行監視・復旧ティア仕様

## 変更概要

このティアに新しいコマンドは追加しない。運用者が受け取る通知メールの契約(件名・本文・推奨対処)を、受け手の観点で確定する。送信側の実装は UC「ハング疑い・実行エラー・比較異常を通知する」、件名・本文の横断規約は `_cross-cutting/ux-ui/ui-design.md`「通知メール規約」を正とする。

## コマンド契約

### 通知メール(受け手としての契約)

- **書式**: メール(`text/plain; charset=UTF-8`)。宛先は `hang-detector.env` の `ALERT_MAIL_TO`
- **アクセス権**: 運用者(運用体制で定めた異常メールの受け手。CTP-009)

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| (該当なし) | — | — | — | メールに引数は無い |

- **stdin**: なし

#### 件名

`[relay-gate][{warning|error}] {hang-suspected|background-exec-error|rapid-crosscheck-error} run_id={run_id} job_id={job_id} role={blue|green|rapid-crosscheck}`

| 通知種別 | level | 意味 | 運用者の判断 |
|---|---|---|---|
| `hang-suspected` | warning | exitcode.txt が無いまま hang_detect_limit_minutes を超過(依頼なら RUNNING で超過) | 静観可。プロセスを確認し、ハングなら停止 → `abort-{role}.sh` |
| `background-exec-error` | error | exitcode.txt が非 0 | 対処要。stderr.log を確認 → `background-rerun.sh` |
| `rapid-crosscheck-error` | error | 速報比較依頼が FAILED または比較 NG | 対処要。`rapid-crosscheck-result.sh` で原因調査。ジョブスケジューラ応答には影響しない |

#### 本文(行順固定。1 行 1 事実。80 桁制限は 1〜13 行目のみ。14 行目の recommended_action は折り返さず 1 行で、80 桁を超えてよい)

| 行 | 内容 | 例 |
|---|---|---|
| 1 | `kind={通知種別}` | `kind=hang-suspected` |
| 2 | `level={warning|error}` | `level=warning` |
| 3 | `run_id={run_id}` | `run_id=20260830T113000Z-JOB001-3f9a1c2e` |
| 4 | `job_id={job_id}` | `job_id=JOB001` |
| 5 | `role={role}` | `role=green` |
| 6 | `started_at={UTC}` | `started_at=2026-08-30T11:30:05Z` |
| 7 | `elapsed_minutes={整数}` | `elapsed_minutes=74` |
| 8 | `hang_detect_limit_minutes={整数}` | `hang_detect_limit_minutes=60` |
| 9 | `exit_code={整数 または -}` | `exit_code=-` |
| 10 | `request_status={依頼状態 または -}` | `request_status=-` |
| 11 | `artifact_dir: {絶対パス}` | `artifact_dir: /var/relay-gate/facade/20260830T113000Z-JOB001-3f9a1c2e/green` |
| 12 | `detected_at={UTC}` | `detected_at=2026-08-30T12:45:00Z` |
| 13 | (空行) | |
| 14 | `recommended_action: {定型文}`(1 行。折り返さない。15 行目以降は無い) | 下表 |

| 通知種別 | recommended_action |
|---|---|
| `hang-suspected` | `check the process on the execution host; if it is still running normally, wait. if it is hung, stop the process, then run: abort-{role}.sh --run-id {run_id}` |
| `background-exec-error` | `inspect {artifact_dir}/stderr.log; after fixing the cause, run the rerun job: background-rerun.sh --source-run-id {run_id} --role {role}` |
| `rapid-crosscheck-error` | `inspect the comparison result: rapid-crosscheck-result.sh --run-id {run_id}; this result is for investigation only and does not affect the scheduler response` |

## 出力契約

- **stdout / stderr / 終了コード**: 該当なし(メール)
- **受信の保証**: 同じ run_id + role + kind のメールは 1 通。ハング疑い(warning)の後に実行エラー(error)が来ることがある(別種別)。運用者が `abort-*` で中止した対象(on で slot_executions / 依頼が ABORTED)は次回の判定で監視記録が COMPLETED に終端し、以後メールは来ない。メールが来ないことは「異常なし」または「hang-detector.sh 自体の失敗(送信失敗は終了コード 6 でジョブスケジューラの定期ジョブが失敗する)」のどちらかであり、後者はジョブスケジューラの定期ジョブの実行結果で検知する

## UC ロジック

- **バリデーション**: なし
- **確認プロンプト**: なし(対処コマンド側の停止確認プロンプトは実行中止フローの UC)
- **冪等性**: 受信は状態を変えない。同じメールを何度読んでも同じ
- **エラーハンドリング**(運用者の判断):
  - warning(hang-suspected): 実行ホストのプロセスを確認。動いていれば待つ(正常終了すれば監視記録に警告時経過時間が残り、`hang-detect-trend.sh` で上限調整の根拠になる)。ハングなら自分でプロセスを止めてから `abort-{role}.sh --run-id`、必要なら `background-rerun.sh`
  - error(background-exec-error): `{artifact_dir}/stderr.log` で原因を確認し、取り除いてから `background-rerun.sh --source-run-id --role`(元の実行は FAILED なので abort 不要)
  - error(rapid-crosscheck-error): `rapid-crosscheck-result.sh --run-id` で status / difference_count / report_uri を見て原因調査。必要なら `background-rerun.sh --role rapid-crosscheck`。リリース判断は確報で行う
- **クラッシュ耐性**: 該当なし

## データモデル変更

### monitor_records(参照。受け手は直接読まない)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| alerted_at | datetime | このメールの送信時刻に対応 | 追加(参照) |

## ビジネスルール

- 通知レベルの判定: warning = 静観可、error = 対処要
- CLI とメールによる提示: 通知はメールのみ。メールの run_id をそのままコマンド引数に使える
- 監視は通知のみ: 自動中止・自動再実行は行われない。対処は運用者
- 復旧手段の選択: background slot / 速報比較依頼は `background-rerun.sh`、foreground / 確報はジョブスケジューラの正規ジョブ(メールの対象は前者のみ)

## ティア完了条件(BDD)

```gherkin
Feature: background 異常の通知メールを受け取る - 実行監視・復旧ティア

  Scenario: 件名だけで重要度・種別・対象を判別できる
    Given hang-detector.sh が run_id=20260830T113000Z-JOB001-3f9a1c2e job_id=JOB001 role=green のハング疑いを通知した
    When 運用者がメールクライアントで件名を読む
    Then 件名は "[relay-gate][warning] hang-suspected run_id=20260830T113000Z-JOB001-3f9a1c2e job_id=JOB001 role=green" と完全一致する

  Scenario: 本文の推奨対処に run_id 付きのコマンドが書かれている
    Given 同じメールを受け取った
    When 運用者が本文を読む
    Then 14 行目は "recommended_action: check the process on the execution host; if it is still running normally, wait. if it is hung, stop the process, then run: abort-green.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e" の 1 行で、本文は 14 行である
    And 本文に HTML タグ・添付ファイルは無く、1〜13 行目に 80 桁を超える行は無い(14 行目は折り返されず 80 桁を超えてよい)

  Scenario: 同じ対象の同じ種別は 1 通だけ届く
    Given 同じ run の green が 30 分間ハング疑いのままである
    When hang-detector.sh が 5 分ごとに 6 回実行される
    Then 運用者に届く hang-suspected のメールは 1 通である
```
