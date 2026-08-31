# background 実行の経過時間と終了状態を判定する - 実行監視・復旧ティア仕様

## 変更概要

`hang-detector.sh` を追加する(走査・判定部分)。presentation(引数検証)→ usecase(feature flag 読込 → 成果物走査 → 依頼走査(on)→ 対象ごとの判定 → 通知 UC / 記録 UC へ)→ domain(判定表・異常判定表・対象除外)→ repository(成果物 / 依頼 / 監視記録)→ gateway(ファイルシステム走査 / RDB)。通知(`hang-alert-mail`)は UC「ハング疑い・実行エラー・比較異常を通知する」、記録(`monitor_records`)は UC「監視記録を保存する」の tier md に続く。

## コマンド契約

### hang-detector.sh

- **書式**: `hang-detector.sh [--verbose] [--help]`
- **アクセス権**: ジョブスケジューラのハング検知定期ジョブ(5 分ごと)。運用者が手動起動してもよい(冪等)。成果物ディレクトリの読み取り権限と、on のとき管理 DB の閉域接続(CTP-002)
- **トリガー**: ジョブスケジューラ定期ジョブ(5 分ごと。間隔はジョブ定義側で決める。hang-detector.sh 自身は常駐しない)

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--verbose` | boolean | No | false | 対象ごとの `info: judged ...` を stderr にも出す(既定は実行ログのみ) |
| `--help` | boolean | No | false | usage を stdout に出し終了コード 0 |

- **stdin**: なし

#### 設定契約(hang-detector.env。`RELAY_GATE_CONFIG_DIR/hang-detector.env`、仮採用: _inference.md #10)

| キー | 型 | 必須 | 既定値 | 検証ルール |
|------|---|------|-------|-----------|
| `RAPID_HANG_DETECT_LIMIT_MINUTES` | integer | No | 60 | 1 以上。速報比較依頼(role=rapid-crosscheck)のハング疑い上限(仮採用: 依頼は run の execution-spec.json ではなく hang-detector.env のクロスチェック側の値を使う。ui-design.md「依頼の場合はクロスチェック側の値」) |
| `HANG_SCAN_WINDOW_HOURS` | integer | No | 72 | 1 以上。started-at.txt がこの時間より古い run は走査しない(仮採用: 成果物の蓄積で走査が肥大しないための上限。監視記録が未終端の run は窓外でも走査する) |
| `HANG_DB_CONN_REF` | string | on のとき Yes | — | 管理 DB 接続情報の参照名(値は置かない) |
| `ALERT_MAIL_TO` / `ALERT_MAIL_CMD` | string | Yes | — | UC「ハング疑い・実行エラー・比較異常を通知する」を参照 |

- feature flag 設定(env 形式)の `RAPID_CROSSCHECK_MODE` を読む(ファイル名・所在は tier-facade の設定契約を正とする)。`BLUE_MODE` / `GREEN_MODE` は読まない(role の mode は run 開始時に確定した execution-spec.json を正とする)
- execution-spec.json(run 単位 1 ファイル。構造は UC「execution-spec.json を確定保存する」の契約 = step3 canonical C1 を正とする)から読むキー: `job_id`、`slots.<role>.mode`(foreground / background)、`slots.<role>.hang_detect_limit_minutes`。mode が off の slot は節を持たないため走査に現れない。ファイルが無い run(started-at.txt はあるが execution-spec.json が無い契約違反状態)は `warn: execution-spec missing run_id=...` を stderr に出して判定対象外にする(既定値で判定しない。監視記録も作らない。終了コードは 0 のまま)
- on のとき `slot_executions`(run_id, slot, status)を読む: status=ABORTED の background slot は中止済み(COMPLETED)として終端する。off では slot_executions が無いため成果物ファイルのみで判定する(off では abort-blue / abort-green が管理 DB なしで拒否されるため ABORTED は発生しない)
- 環境変数 `RELAY_GATE_NOW`(テスト専用。cli-command-contract.yaml environment_variables で宣言。ISO 8601 UTC。本番未設定): 設定時はシステム時刻の代わりに now として使う(経過時間・detected_at・judged_at)

## 出力契約

- **stdout**: 出力しない(0 行)。判定結果は実行ログと `--verbose` の stderr にのみ出す(ui-design.md「大量出力」)
- **stderr**: `error: ...`(+ `hint:`)、設定エラーは ui-design.md の定型文 `error: config file not found path: ...`(hang-detector.env 不在)/ `error: option required option=HANG_DB_CONN_REF|ALERT_MAIL_TO|ALERT_MAIL_CMD path: ...`(2)/ `error: ALERT_MAIL_CMD is not executable value=... path: ...`(2)、`error: management db connection failed conn_ref=...`(6)、`warn: execution-spec missing run_id=... path: ...`(当該 run は判定対象外。処理は継続)、`warn: started-at is invalid run_id=... role=... value=...`(当該 role は判定せず継続)、`warn: execution-spec invalid run_id=... key=...`、`--verbose` 時 `info: judged run_id=... role=... judgement=NOT_TARGET|COMPLETED|EXEC_ERROR|MONITORING|HANG_SUSPECTED|COMPARE_ERROR elapsed_minutes=... limit_minutes=...`
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 走査と判定が完了した(ハング疑い・エラーを検出しても 0。異常はメールで伝える) |
  | 2 | 入力・設定検証エラー | 未知のオプション、`hang-detector.env` 不在または on で `HANG_DB_CONN_REF` 欠落、`ALERT_MAIL_TO` 空 / `ALERT_MAIL_CMD` 実行不可(通知 UC)、feature flag 設定が読めない、`RELAY_GATE_ARTIFACT_ROOT` が存在しない |
  | 6 | 実行エラー | on で管理 DB 接続・SELECT 失敗(成果物側の判定は行ったうえで 6)、成果物ルートの読み取り失敗、メール送信失敗(通知 UC)、監視記録の保存失敗(記録 UC) |

- 実行ログ(`RELAY_GATE_LOG_DIR/hang-detector.sh.log`。run_id 欄は対象の run_id、全体処理は `-`):
  - ログ行の形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {UTC 出力日時} {LEVEL} {message}`)に従う。情報「実行ログ」の属性「出力日時」はこの UTC 出力日時の列に対応する(以下は `{LEVEL} {message}` 部分)
  - `INFO scan started mode=on artifact_root=... window_hours=72`
  - `INFO scanning artifacts only mode=off`
  - `INFO judged run_id=... role=... judgement=HANG_SUSPECTED elapsed_minutes=74 limit_minutes=60`(`--verbose` の stderr 行と同じ形式。cli-command-contract.yaml の `--verbose` 説明に合わせ job_id は含めない)
  - `WARN started-at is invalid run_id=... role=... value=...` / `WARN invalid exitcode run_id=... role=... value=...` / `WARN execution-spec missing run_id=... path: ...`(stderr の `warn:` と同じ文言を同時に残す)
  - `INFO scan finished targets=N judged=N alerts=N`

## UC ロジック

- **バリデーション**: オプション以外の引数は受け付けない(`error: unexpected argument value=...`、終了コード 2)
- **確認プロンプト**: なし
- **冪等性**: 判定は純粋関数(入力: 成果物ファイル・依頼レコード・現在時刻)。同じ状態で何度実行しても同じ判定。状態を変更せず(RUNNING → ABORTED にしない、プロセスを止めない、依頼を作らない)、副作用は通知 UC / 記録 UC に限る
- **走査手順**:
  1. `$RELAY_GATE_ARTIFACT_ROOT/facade/*/` を列挙。`<role>/started-at.txt`(role ∈ {blue, green})が 1 つも無い run ディレクトリは `execution-spec.json` を読まずに飛ばす。started-at.txt がある run だけ `execution-spec.json` の `job_id` と `slots.<role>` を読む。execution-spec.json が無い run は `warn: execution-spec missing run_id=...` を出して判定対象外にする(job_id / mode を埋められないため。監視記録も作らない)。`final-crosscheck` ディレクトリは走査しない
  2. started-at.txt が `HANG_SCAN_WINDOW_HOURS` より古く、かつ(on なら)監視記録が終端(COMPLETED / EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED / NOT_MONITORED)の run は除く。HANG_SUSPECTED_NOTIFIED は未終端として引き続き走査する。off では窓だけで絞る
  3. on のとき走査対象 run の `slot_executions.status` を読む(ABORTED の判定に使う)。ABORTED かつ monitor_records に未終端(MONITORING / HANG_SUSPECTED_NOTIFIED)の行が無い role は走査対象外(判定・記録しない。契約 hang-detector.sh exit 0「ABORTED 済みで監視記録が無い対象は走査しない」)
  4. on のとき `rapid_crosscheck_requests` から status ∈ {REQUESTED, CLAIMED, RUNNING} と、monitor_records が未終端(記録なし / MONITORING / HANG_SUSPECTED_NOTIFIED)の {SUCCEEDED, FAILED} と、monitor_records が未終端(MONITORING / HANG_SUSPECTED_NOTIFIED の記録あり)の ABORTED を取得し、`comparison_results.status` を結合(HANG_SUSPECTED_NOTIFIED の依頼を除外しない。除外すると warning 通知後に終端・中止した依頼が二度と判定されず run_count に永続的に数えられる)
  5. 対象ごとに domain の判定表で判定
- **判定表**(domain `judge_background_role`。hang_judgement は 6 値: NOT_TARGET / COMPLETED / EXEC_ERROR / MONITORING / HANG_SUSPECTED / COMPARE_ERROR。cli-command-contract.yaml `shared_rules.state_codes.hang_judgement`):
  | slot_executions.status(on のみ) | exitcode.txt | 経過時間 | 判定 |
  |---|---|---|---|
  | ABORTED(未終端の監視記録あり) | 任意 | — | COMPLETED(中止済み → COMPLETED) |
  | ABORTED(監視記録なし・終端済み) | 任意 | — | 走査対象外(判定・記録しない。契約 hang-detector.sh exit 0) |
  | ABORTED 以外 / off | あり・0 | — | COMPLETED(正常終了 → COMPLETED) |
  | ABORTED 以外 / off | あり・非 0 | — | EXEC_ERROR |
  | ABORTED 以外 / off | あり・整数でない | — | EXEC_ERROR(通知の exit_code は `-`。`WARN invalid exitcode` を残す) |
  | ABORTED 以外 / off | なし | ≤ limit | MONITORING |
  | ABORTED 以外 / off | なし | > limit | HANG_SUSPECTED |
  前提: mode=background かつ limit > 0。それ以外は NOT_TARGET(監視対象外 → NOT_MONITORED)。off では slot_executions を読まず成果物ファイルのみで判定する(off では abort-* が拒否されるため ABORTED は発生しない)。現在の monitor_status が HANG_SUSPECTED_NOTIFIED でも同じ表で再判定する(遷移の可否は通知 UC の冪等判定が決める)
- **異常判定表**(domain `judge_rapid_request`):
  | 依頼状態 | 比較結果 | 経過時間 | 判定 |
  |---|---|---|---|
  | FAILED | 任意 | — | COMPARE_ERROR |
  | SUCCEEDED | NG / FAILED | — | COMPARE_ERROR |
  | SUCCEEDED | OK | — | COMPLETED |
  | RUNNING | — | > RAPID_HANG_DETECT_LIMIT_MINUTES | HANG_SUSPECTED |
  | RUNNING | — | ≤ RAPID_HANG_DETECT_LIMIT_MINUTES | MONITORING |
  | REQUESTED / CLAIMED | — | — | MONITORING |
  | ABORTED(未終端の監視記録がある依頼のみ走査) | — | — | COMPLETED(運用者が中止済み → monitor_status COMPLETED で終端。仮採用: 状態.tsv に無い遷移。rdra-feedback 対象) |
- **エラーハンドリング**: 1 対象の読み取り失敗(不正な started-at.txt、execution-spec.json 欠落・不正)は `warn:` を出して他の対象を継続(終了コードは 0 のまま)。DB 失敗は成果物側の判定・通知・記録を終えてから終了コード 6
- **クラッシュ耐性**: 状態を変更しないため途中終了で壊れるものは無い。次回の定期起動が同じ判定をやり直す。通知の二重送信は監視記録の遷移判定で防ぐ(通知 UC)
- **監視は通知のみ**: usecase は abort / rerun / 依頼作成の repository を呼ばない(LP-017)

## データモデル変更

### monitor_records(参照。更新は UC「監視記録を保存する」)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id / role | string | 主キー | 追加(参照) |
| monitor_status | string | 終端済み(COMPLETED / EXEC_ERROR_NOTIFIED / COMPARE_ERROR_NOTIFIED / NOT_MONITORED)の判定に使う。HANG_SUSPECTED_NOTIFIED は未終端 | 追加(参照) |

### slot_executions / rapid_crosscheck_requests / comparison_results(参照。on のみ)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| slot_executions.run_id / slot / status | string / string / string | status=ABORTED の background slot を中止済み(COMPLETED)と判定する | 追加(参照) |
| rapid_crosscheck_requests.run_id / job_id / status / started_at / requested_at / exit_code | string / string / string / datetime / datetime / integer | 異常判定の入力(ABORTED は未終端の監視記録がある依頼のみ) | 追加(参照) |
| comparison_results.run_id / status | string / string | NG / FAILED の判定 | 追加(参照) |

### 成果物ディレクトリ(参照)

| ファイル | 型 | 説明 | 変更種別 |
|---------|---|------|---------|
| `facade/<run_id>/execution-spec.json` | JSON | job_id、role ごとの mode / hang_detect_limit_minutes | 追加(参照) |
| `facade/<run_id>/<role>/started-at.txt` | text | 経過時間の起点 | 追加(参照) |
| `facade/<run_id>/<role>/exitcode.txt` | text | 終了状態(確定名のみ) | 追加(参照) |

## ビジネスルール

- ハング検知判定: 判定表のとおり(hang_judgement 6 値)。exitcode.txt は確定名だけを読む(成果物公開判定)。on では slot_executions.status=ABORTED を中止済み(COMPLETED)とする
- ハング検知対象の除外: foreground role と hang_detect_limit_minutes=0 は NOT_TARGET → NOT_MONITORED。execution-spec.json が無い run は判定対象外(監視記録なし)
- 速報比較依頼の異常判定: FAILED / 比較 NG → 比較異常、RUNNING で上限超過 → ハング疑い(状態は変更しない)
- 速報クロスチェック有効判定: off では管理 DB に接続しない(LP-020)
- 監視は通知のみ: 状態変更・プロセス停止・依頼作成をしない(LP-017)
- 上限は run 開始時に確定した execution-spec.json の値(ハング検知上限の調整基準: 変更は次回以降の run に反映)

## ティア完了条件(BDD)

```gherkin
Feature: background 実行の経過時間と終了状態を判定する - 実行監視・復旧ティア

  Scenario: 成果物だけでハング疑いを判定する(off)
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=off がある
    And facade/20260830T113000Z-JOB001-3f9a1c2e/execution-spec.json に job_id=JOB001 slots.green.mode=background slots.green.hang_detect_limit_minutes=60 がある
    And green/started-at.txt が 2026-08-30T11:30:05Z、exitcode.txt が無く、RELAY_GATE_NOW=2026-08-30T12:45:00Z である
    When `hang-detector.sh --verbose` を実行する
    Then 終了コード 0 で stdout は 0 行、stderr に "info: judged run_id=20260830T113000Z-JOB001-3f9a1c2e role=green judgement=HANG_SUSPECTED elapsed_minutes=74 limit_minutes=60" が出る

  Scenario: 継続監視は通知しない
    Given 同じ run で RELAY_GATE_NOW=2026-08-30T12:00:00Z である
    When `hang-detector.sh --verbose` を実行する
    Then 終了コード 0 で stderr に "judgement=MONITORING elapsed_minutes=29 limit_minutes=60" を含む行が出る

  Scenario: 正常終了は COMPLETED と判定する
    Given 同じ run の green/exitcode.txt の中身が 0 である
    When `hang-detector.sh --verbose` を実行する
    Then 終了コード 0 で stderr に "judgement=COMPLETED" を含む行が出る

  Scenario: on で ABORTED の slot 実行は COMPLETED と判定する
    Given feature flag 設定に RAPID_CROSSCHECK_MODE=on があり、slot_executions に run_id=20260830T113000Z-JOB001-3f9a1c2e slot=green status=ABORTED の行がある
    And monitor_records に run_id=20260830T113000Z-JOB001-3f9a1c2e role=green monitor_status=MONITORING の行がある
    And green/exitcode.txt が無く、RELAY_GATE_NOW=2026-08-30T12:45:00Z である
    When `hang-detector.sh --verbose` を実行する
    Then 終了コード 0 で stderr に "info: judged run_id=20260830T113000Z-JOB001-3f9a1c2e role=green judgement=COMPLETED" で始まる行が出て、メールは送られない

  Scenario: execution-spec.json が無い run は判定対象外にする
    Given facade/20260830T113000Z-JOB002-9a8b7c6d/execution-spec.json が無く green/started-at.txt がある
    When `hang-detector.sh --verbose` を実行する
    Then 終了コード 0 で stderr に "warn: execution-spec missing run_id=20260830T113000Z-JOB002-9a8b7c6d path: $RELAY_GATE_ARTIFACT_ROOT/facade/20260830T113000Z-JOB002-9a8b7c6d/execution-spec.json" が出る
    And stderr に "info: judged run_id=20260830T113000Z-JOB002-9a8b7c6d" で始まる行は出ず、monitor_records に該当 run_id の行は作られない

  Scenario: 未知のオプション
    When `hang-detector.sh --all` を実行する
    Then 終了コード 2 で stderr に "error: unknown option option=--all" が出る
```
