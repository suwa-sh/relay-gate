# 比較ツールで日次全量比較を実行して結果を保存する - 確報クロスチェックティア仕様

## 変更概要

`final-crosscheck-worker.sh` の比較実行部分(claim 後)を追加する。usecase(RUNNING 遷移 → 比較ツール起動 → 依頼保存)、domain(exit_code → 状態)、repository(依頼 / 確報の比較ツール起動コマンド)、gateway(比較ツール起動 / RDB)。コマンド契約(引数・終了コード)は UC「確報比較依頼を claim する」の tier md を正とし、本ファイルは比較実行に固有の契約を書く。確報の比較ツール起動コマンド(final-crosscheck.env の `FINAL_COMPARE_COMMAND`)の設定とその検証(`validate-config.sh --final-crosscheck`)もこの UC が所有する。

## コマンド契約

### final-crosscheck-worker.sh(比較実行部分)

- **書式**: `final-crosscheck-worker.sh [--once] [--worker-id <id>]`(UC「確報比較依頼を claim する」を参照)
- **アクセス権**: DB セグメント上の worker。比較ツールの起動権限を持つ OS ユーザーで動かす。runner と worker は別ネットワークセグメントで動き、worker は runner 側のファイルパスを読めない

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| (追加なし) | — | — | — | 比較の対象と方法は依頼レコードと設定ファイル(final-crosscheck.env の FINAL_COMPARE_COMMAND)から決まる |

- **stdin**: なし

#### 設定契約

- `final-crosscheck.env`(`RELAY_GATE_CONFIG_DIR/final-crosscheck.env`、KEY=VALUE、行頭 `#` はコメント行)の `FINAL_COMPARE_COMMAND`: 確報の比較ツール起動コマンド 1 行の文字列(プレースホルダ無し)。worker はこれをそのまま(置換なしで)起動する
  - `FINAL_COMPARE_COMMAND` のコマンド部分(先頭の語)は絶対パスで実行可能ファイルであること(検証は `validate-config.sh --final-crosscheck` が行う。本 worker は起動失敗を実行時に検出して FAILED にする)
- 比較対象(テーブル・ファイル)の一覧やジョブ ID ごとの比較定義は relay-gate の設定に持たない。worker は依頼レコード(final_crosscheck_requests)と final-crosscheck.env 以外の入力を読まない(適用側が比較ツール側で比較対象を定義する)

### validate-config.sh --final-crosscheck(確報の起動コマンドの検証)

- 検証本体の所有 tier は tier-facade(validate-config.sh。arch CTR-007。契約の正本は `_cross-cutting/api/cli-command-contract.yaml` の `validate-config.sh`)。本 UC は確報の起動コマンドの検証種別 `--final-crosscheck` を所有する
- **書式**: `validate-config.sh --final-crosscheck <path>`(値必須。既定パス `$RELAY_GATE_CONFIG_DIR/final-crosscheck.env` を使う場合も明示的に渡す)
- **検証内容**: `FINAL_COMPARE_COMMAND` のコマンド部分(先頭の語)が絶対パスで、存在し、実行可能であること。検証はコマンド部分だけに行い、引数部分の内容は検査しない。確報はプレースホルダ無しのため `{job_id}` の検査はしない
- **stdout(固定順)**: `config=final-crosscheck` / `path: <path>` / `command_path: <FINAL_COMPARE_COMMAND の先頭の語>` / `status=valid|invalid` / `violations=N`(invalid 時)
- **違反文言(終了コード 2)**:
  - 必須キー欠落・空: `error: option required option=FINAL_COMPARE_COMMAND path: ...`
  - コマンド部分が絶対パスでない: `error: path is not absolute key=FINAL_COMPARE_COMMAND path=...`
  - コマンド部分が存在しない・実行不可: `error: file not executable key=FINAL_COMPARE_COMMAND path=...`

## 出力契約

- **stdout**: 出力しない(比較ツールの stdout は依頼レコードの stdout 列に保存し、worker の stdout には流さない。成果物ファイルには保存しない)
- **stderr**: `error: ...`(worker 自身の実行エラー)。比較ツールの stderr は流さない
- **終了コード**(ui-design.md「worker」):
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 依頼を 1 件処理して終端(SUCCEEDED / FAILED どちらも)まで保存できた。比較ツールの非 0 は worker の終了コードに反映しない。RUNNING 遷移 UPDATE が 0 件(lease 失効で別 worker に回収済み)、終端 UPDATE が 0 件(比較中に ABORTED)も 0 |
  | 6 | 実行エラー | 比較ツールの起動失敗(実行ファイルなし・権限なし)、管理 DB の UPDATE 失敗(SQL エラー)。起動失敗は依頼を FAILED(exit_code=6、error_summary="launch failed")にしてから 6 で終了する |

- worker は成果物ディレクトリ・started-at.txt・比較対象の抜き出しファイルを作らない(比較ツールの結果は依頼レコードの stdout / stderr / exit_code 列だけに保存する。runner と worker は別ネットワークセグメントで動き、worker は runner 側のファイルパスを読めない)
- 実行ログ(`final-crosscheck-worker.sh.log`): `INFO comparison started final_crosscheck_id=...` / gateway `INFO compare tool started command=...` / `INFO compare tool finished exit_code=... duration_ms=...` / `INFO request completed final_crosscheck_id=... status=... exit_code=...` / `WARN request not claimable status changed final_crosscheck_id=...`(RUNNING 遷移 UPDATE 0 件)/ `WARN request already terminal final_crosscheck_id=... status=ABORTED`(終端 UPDATE 0 件)
  - ログ行の形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {ローカル出力日時} {LEVEL} {message}`。run_id 欄は final_crosscheck_id)に従う。情報「実行ログ」の属性「出力日時」はこの ローカル出力日時の列に対応する

## UC ロジック

- **バリデーション**: `FINAL_COMPARE_COMMAND` のコマンド部分が実行可能でなければ比較ツールを起動できず、依頼を FAILED(exit_code=6、error_summary="launch failed")にして worker は 6 で終了する(起動失敗と同じ扱い)
- **確認プロンプト**: なし
- **冪等性**: RUNNING 遷移は `WHERE status='CLAIMED' AND worker_id=?` の条件付き UPDATE。更新件数 0(lease 失効で別 worker に回収済み。abort-final-crosscheck.sh は RUNNING のみ中止できるため CLAIMED が ABORTED になる経路は無い)なら比較ツールを起動せず `WARN request not claimable status changed` を残して終了コード 0。終端遷移は `WHERE status='RUNNING'`。更新件数 0(比較中に abort-final-crosscheck.sh で ABORTED)は中止済みとみなし、`WARN request already terminal final_crosscheck_id=... status=ABORTED` を残して終了コード 0(依頼は変更しない)
- **比較ツールの起動**: cli-command-contract.yaml external_interfaces「比較ツール(確報)」のとおり `FINAL_COMPARE_COMMAND`(1 行、プレースホルダ無し)をそのまま空白区切りで引数に分割して起動する。worker は固定オプション・ファイルパスを追記しない(比較対象は比較ツール側が定義する)。比較ツールの stdout / stderr を受け取り、exit_code は `$?`。受け取った stdout / stderr / exit_code は依頼レコードの列へ保存する(ファイルへは保存しない)
- **エラーハンドリング**: 比較ツールの非 0 は例外ではなく結果(CLR-003)。起動失敗・DB 失敗は `error:` 1 回 + 終了コード 6。DB の終端 UPDATE に失敗した場合、依頼は RUNNING のまま残る(`abort-final-crosscheck.sh` で整理し正規ジョブを再実行)
- **クラッシュ耐性**: RUNNING 遷移後に worker が落ちると依頼は RUNNING のまま残り、lease 回収の対象外(started_at あり)。hang-detector は確報依頼を走査しない(cli-command-contract.yaml `hang-detector.sh` / asyncapi.yaml `hang-alert-mail` の監視対象は background slot と速報比較依頼のみ。方針資料 C2 図の HangDetector → FinalQueue 破線とは差異があり、確報依頼のハング監視は runner の polling 上限で代替する仮採用として rdra-feedback で記録する)ため、runner の polling 上限超過(終了コード 6)で運用者に伝わる
- **速報と確報のモデル分離**: 確報の結果は依頼レコードの stdout / stderr / exit_code 列だけで保持する(速報・確報とも比較結果の独立テーブルは持たない)

## イベント処理仕様

### final-crosscheck-requests(subscribe → 結果保存)

- **トリガー**: UC「確報比較依頼を claim する」の claim 成功
- **入力チャネル**: 管理 DB `final_crosscheck_requests`(CLAIMED、worker_id=自分)
- **出力チャネル**: 同テーブルの終端更新(runner の polling が読む)
- **AsyncAPI**: [asyncapi.yaml](../../../_cross-cutting/api/asyncapi.yaml) の `channels.final-crosscheck-requests` を参照

#### 処理フロー

1. `UPDATE final_crosscheck_requests SET status='RUNNING', started_at=:now WHERE final_crosscheck_id=? AND status='CLAIMED' AND worker_id=?`(更新件数 1 でなければ終了)
2. final-crosscheck.env の `FINAL_COMPARE_COMMAND` を読み、そのまま起動して stdout / stderr を受け取り、exit_code を取得する
3. `UPDATE final_crosscheck_requests SET status=?, exit_code=?, stdout=?, stderr=?, error_summary=?, completed_at=:now WHERE final_crosscheck_id=? AND status='RUNNING'`(更新件数 0 = 比較中に ABORTED。`WARN request already terminal` を残して終了コード 0)

#### エラーハンドリング

| エラー種別 | リトライ | DLQ | 説明 |
|-----------|---------|-----|------|
| 比較ツール非 0(3 / 6 / その他) | No | No | 結果として FAILED を保存。再実行はジョブスケジューラの正規ジョブ(新しい依頼) |
| 比較ツール起動失敗 | No | No | FAILED(exit_code=6、error_summary="launch failed")を保存し worker は 6 で終了 |
| RUNNING 遷移 UPDATE 0 件 | No | No | lease 失効で別 worker に回収済み。比較ツールを起動せず終了コード 0 |
| 終端 UPDATE 0 件(ABORTED 競合) | No | No | 中止済み。依頼は ABORTED のまま。終了コード 0 |
| DB UPDATE 失敗(終端。SQL エラー) | No | No | 6 で終了。依頼は RUNNING のまま。運用者が abort → 正規ジョブ再実行 |

## データモデル変更

### final_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | string | CLAIMED → RUNNING → SUCCEEDED / FAILED | 追加(更新) |
| started_at | datetime | RUNNING 遷移時刻(ローカル時刻) | 追加(更新) |
| completed_at | datetime | 終端遷移時刻 | 追加(更新) |
| exit_code | integer | 比較ツール終了コード(起動失敗は 6) | 追加(更新) |
| stdout | text | 比較ツール stdout 全文 | 追加(更新) |
| stderr | text | 比較ツール stderr 全文 | 追加(更新) |
| error_summary | string | 起動失敗の要約(正常終了・比較 NG は NULL。起動失敗は "launch failed") | 追加(更新) |

- worker は成果物ディレクトリ・ファイルを作らない(結果は依頼レコードの列だけに保持する)

## ビジネスルール

- 依頼状態遷移規則: CLAIMED → RUNNING → SUCCEEDED / FAILED。条件付き UPDATE
- 比較ツール終了コードの対応: 0 → SUCCEEDED、非 0 → FAILED。値は変換しない
- 適用側で定義する事項: 比較対象は比較ツール側が所有。relay-gate は確報の比較ツール起動コマンド 1 行(FINAL_COMPARE_COMMAND)だけを持ち、worker はそれをそのまま起動する
- 確報の起動コマンドの検証: `validate-config.sh --final-crosscheck` はコマンド部分が絶対パスで存在・実行可能であることだけを検証する(プレースホルダ無しのため {job_id} 検査なし)

## ティア完了条件(BDD)

```gherkin
Feature: 比較ツールで日次全量比較を実行して結果を保存する - 確報クロスチェックティア

  Scenario: 比較 OK を SUCCEEDED として保存する
    Given final_crosscheck_requests に final_crosscheck_id=20260830T210000-final-7b2c9e1f status=REQUESTED requested_at=2026-08-30T21:00:00 がある(1 プロセスで claim → RUNNING → 終端まで検証する)
    And final-crosscheck.env の FINAL_COMPARE_COMMAND が /opt/compare/stub-ok.sh(終了コード 0、stdout "all 42 targets matched\n")を指す
    When `final-crosscheck-worker.sh --once --worker-id final-worker-01` を実行する
    Then 終了コード 0 で該当行は status=SUCCEEDED worker_id=final-worker-01 exit_code=0 stdout="all 42 targets matched\n" になり、started_at と completed_at が設定される
    And 成果物ディレクトリ(facade/<final_crosscheck_id>/)は作成されない

  Scenario: 比較 NG(3)を FAILED として保存し worker は 0 で終了する
    Given 同じ依頼が status=REQUESTED で、FINAL_COMPARE_COMMAND が終了コード 3 を返す
    When `final-crosscheck-worker.sh --once --worker-id final-worker-01` を実行する
    Then worker の終了コードは 0 で、該当行は status=FAILED exit_code=3 である

  Scenario: 比較ツールが実行できない
    Given 同じ依頼が status=REQUESTED で、FINAL_COMPARE_COMMAND が /opt/compare/missing.sh(存在しない)を指す
    When `final-crosscheck-worker.sh --once --worker-id final-worker-01` を実行する
    Then 終了コード 6 で stderr に "error: compare tool launch failed final_crosscheck_id=20260830T210000-final-7b2c9e1f command=/opt/compare/missing.sh" が出る
    And 該当行は status=FAILED exit_code=6 error_summary="launch failed" である(速報 worker と同じ値。契約 final-crosscheck-worker.sh stderr と同文)

  Scenario: 依頼レコードと設定以外の入力を読まない
    Given 同じ依頼が status=REQUESTED で、FINAL_COMPARE_COMMAND が起動時の引数を記録して終了コード 0 で終わる比較ツールを指す
    When `final-crosscheck-worker.sh --once --worker-id final-worker-01` を実行する
    Then 比較ツールは FINAL_COMPARE_COMMAND の文字列と完全一致する引数だけで起動され、ファイルパスは追加されない
    And worker は final_crosscheck_requests の該当行と final-crosscheck.env 以外のファイルを開かない

  Scenario: 比較中に ABORTED された依頼は終端 UPDATE 0 件で終了コード 0
    Given 同じ依頼が status=REQUESTED で、FINAL_COMPARE_COMMAND が停止シグナルを受けるまで待機するスタブを指す
    And `final-crosscheck-worker.sh --once --worker-id final-worker-01` を起動し、該当行が status=RUNNING になった後に `abort-final-crosscheck.sh --run-id 20260830T210000-final-7b2c9e1f --yes` で ABORTED にする
    When スタブに停止シグナルを送る
    Then worker は終了コード 0 で終了し、該当行は status=ABORTED exit_code=NULL のままである
    And 実行ログに "WARN request already terminal final_crosscheck_id=20260830T210000-final-7b2c9e1f status=ABORTED" が残る

  Scenario: 確報の起動コマンドが絶対パスで実行可能なら valid になる
    Given final-crosscheck.env の FINAL_COMPARE_COMMAND が "/opt/compare/final.sh --full" で、/opt/compare/final.sh が存在し実行可能である
    When `validate-config.sh --final-crosscheck /etc/relay-gate/final-crosscheck.env` を実行する
    Then 終了コード 0 で stdout に "config=final-crosscheck"、"command_path: /opt/compare/final.sh"、"status=valid" が出る

  Scenario: 絶対パスでない起動コマンドは invalid になる
    Given final-crosscheck.env の FINAL_COMPARE_COMMAND が "compare-final.sh --full"(相対パス)である
    When `validate-config.sh --final-crosscheck /etc/relay-gate/final-crosscheck.env` を実行する
    Then 終了コード 2 で stderr に "error: path is not absolute key=FINAL_COMPARE_COMMAND path=compare-final.sh" が出る
    And stdout に "config=final-crosscheck"、"status=invalid"、"violations=1" が出る
```
