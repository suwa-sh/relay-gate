# 比較ツールで日次全量比較を実行して結果を保存する - 確報クロスチェックティア仕様

## 変更概要

`final-crosscheck-worker.sh` の比較実行部分(claim 後)を追加する。usecase(RUNNING 遷移 → started-at.txt → 比較ツール起動 → 3 ファイル保存 → 依頼保存)、domain(exit_code → 状態)、repository(対象カタログ / クロスチェックジョブマップ / 依頼 / 成果物)、gateway(比較ツール起動 / RDB / ファイルシステム)。コマンド契約(引数・終了コード)は UC「確報比較依頼を claim する」の tier md を正とし、本ファイルは比較実行に固有の契約を書く。

## コマンド契約

### final-crosscheck-worker.sh(比較実行部分)

- **書式**: `final-crosscheck-worker.sh [--once] [--worker-id <id>]`(UC「確報比較依頼を claim する」を参照)
- **アクセス権**: DB セグメント上の worker。比較ツールの起動権限と成果物ディレクトリの書き込み権限を持つ OS ユーザーで動かす

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| (追加なし) | — | — | — | 比較の対象と方法は依頼レコードと設定ファイルから決まる |

- **stdin**: なし

#### 設定契約

- クロスチェックジョブマップ TSV(ヘッダー行あり。`RELAY_GATE_CONFIG_DIR/crosscheck-job-map.tsv`。6 列): `job_id	comparison_type	compare_targets	compare_command	compare_options	definition_version`
  - 確報用の行は `job_id=final-crosscheck`、`comparison_type=full`(step3 canonical C5。速報の job_id ごとの行と同じ TSV に確報行を 1 行置く)
  - `compare_command` は絶対パスで実行可能ファイルであること。`compare_options` は空可
  - 対象カタログの参照はヘッダーコメント `# target_catalog_path=<絶対パス>` / `# catalog_version=<既定版>`(依頼の catalog_version が優先)。定義は G2 UC「クロスチェックのジョブマップと比較定義を定義する」を正とする
- 対象カタログ TSV: `catalog_version	target_type	target_identifier	compare_condition	business_date_handling`。`target_type` は `table` / `file`

## 出力契約

- **stdout**: 出力しない(比較ツールの stdout は依頼レコードと `stdout.log` に保存し、worker の stdout には流さない)
- **stderr**: `error: ...`(worker 自身の実行エラー)。比較ツールの stderr は流さない
- **終了コード**(ui-design.md「worker」):
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 依頼を 1 件処理して終端(SUCCEEDED / FAILED どちらも)まで保存できた。比較ツールの非 0 は worker の終了コードに反映しない。RUNNING 遷移 UPDATE が 0 件(lease 失効で別 worker に回収済み)、終端 UPDATE が 0 件(比較中に ABORTED)も 0 |
  | 6 | 実行エラー | 比較ツールの起動失敗(実行ファイルなし・権限なし)、対象カタログに catalog_version の行が 0 行、成果物ディレクトリ書き込み失敗、管理 DB の UPDATE 失敗(SQL エラー)。起動失敗・カタログ 0 行は依頼を FAILED(exit_code=6、error_summary)にしてから 6 で終了する |

- 成果物(Runner Result Contract、role=final-crosscheck): `$RELAY_GATE_ARTIFACT_ROOT/facade/<final_crosscheck_id>/final-crosscheck/{started-at.txt, stdout.log, stderr.log, exitcode.txt}`。`execution-spec.json` は置かない(facade の run ではないため。hang-detector の走査対象外)
- 実行ログ(`final-crosscheck-worker.sh.log`): `INFO comparison started final_crosscheck_id=... business_date=... catalog_version=... targets=N` / gateway `INFO compare tool started command=...` / `INFO compare tool finished exit_code=... duration_ms=...` / `INFO request completed final_crosscheck_id=... status=... exit_code=...` / `WARN request not claimable status changed final_crosscheck_id=...`(RUNNING 遷移 UPDATE 0 件)/ `WARN request already terminal final_crosscheck_id=... status=ABORTED`(終端 UPDATE 0 件)
  - ログ行の形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {UTC 出力日時} {LEVEL} {message}`。run_id 欄は final_crosscheck_id)に従う。情報「実行ログ」の属性「出力日時」はこの UTC 出力日時の列に対応する

## UC ロジック

- **バリデーション**: 対象カタログに catalog_version の行が 0 行なら起動せず FAILED(exit_code=6、`error_summary=no catalog rows catalog_version=...`)にして worker は 6 で終了する(起動失敗と同じ扱い)。compare_command が実行可能でなければ同様に FAILED + 6
- **確認プロンプト**: なし
- **冪等性**: RUNNING 遷移は `WHERE status='CLAIMED' AND worker_id=?` の条件付き UPDATE。更新件数 0(lease 失効で別 worker に回収済み。abort-final-crosscheck.sh は RUNNING のみ中止できるため CLAIMED が ABORTED になる経路は無い)なら比較ツールを起動せず `WARN request not claimable status changed` を残して終了コード 0。終端遷移は `WHERE status='RUNNING'`。更新件数 0(比較中に abort-final-crosscheck.sh で ABORTED)は中止済みとみなし、成果物 3 ファイルは残したまま `WARN request already terminal final_crosscheck_id=... status=ABORTED` を残して終了コード 0(依頼は変更しない)。成果物ファイルは既存があれば上書きせず `.tmp` → `mv` で置く(Runner Result Contract)
- **比較ツールの起動**: 対象カタログの該当行だけを一時 TSV(`facade/<id>/final-crosscheck/input/target-catalog.tsv.tmp` → 確定名 `input/target-catalog.tsv`。仮採用: 比較の再現性のため入力を成果物に残す。`input/` 配下に置くため Runner Result Contract の 4 ファイルには影響しない)へ抜き出し、cli-command-contract.yaml external_interfaces「比較ツール(確報)」のとおり `compare_options` 内のプレースホルダを置換して `compare_command <置換後の compare_options>` を起動する(`{catalog_path}` → 抜き出した一時 TSV の絶対パス、`{catalog_version}` → 依頼の catalog_version、`{business_date}` → 依頼の business_date。空白区切りで引数に分割)。worker は固定オプションを追記しない(引数名は比較ツール契約に依存するため、適用側が compare_options で定義する。`{catalog_version}` / `{business_date}` の欠落は validate-config.sh が検出する)。stdout / stderr はそれぞれ `.tmp` ファイルへリダイレクトし、終了後に `mv`。exit_code は `$?`
- **エラーハンドリング**: 比較ツールの非 0 は例外ではなく結果(CLR-003)。起動失敗・書き込み失敗・DB 失敗は `error:` 1 回 + 終了コード 6。DB の終端 UPDATE に失敗した場合、成果物の 3 ファイルは残るため運用者は成果物で結果を確認できる(依頼は RUNNING のまま。`abort-final-crosscheck.sh` で整理し正規ジョブを再実行)
- **クラッシュ耐性**: RUNNING 遷移後に worker が落ちると依頼は RUNNING のまま残り、lease 回収の対象外(started_at あり)。hang-detector は確報依頼を走査しない(cli-command-contract.yaml `hang-detector.sh` / asyncapi.yaml `hang-alert-mail` の監視対象は background slot と速報比較依頼のみ。方針資料 C2 図の HangDetector → FinalQueue 破線とは差異があり、確報依頼のハング監視は runner の polling 上限で代替する仮採用として rdra-feedback で記録する)ため、runner の polling 上限超過(終了コード 6)で運用者に伝わる。成果物は `.tmp` のまま残り、確定名は存在しない(成果物公開判定)
- **速報と確報のモデル分離**: `comparison_results` には登録しない(速報のみ)。確報の結果は依頼レコードと成果物ファイルだけ

## イベント処理仕様

### final-crosscheck-requests(subscribe → 結果保存)

- **トリガー**: UC「確報比較依頼を claim する」の claim 成功
- **入力チャネル**: 管理 DB `final_crosscheck_requests`(CLAIMED、worker_id=自分)
- **出力チャネル**: 同テーブルの終端更新(runner の polling が読む)
- **AsyncAPI**: [asyncapi.yaml](../../../_cross-cutting/api/asyncapi.yaml) の `channels.final-crosscheck-requests` を参照

#### 処理フロー

1. `UPDATE final_crosscheck_requests SET status='RUNNING', started_at=:now WHERE final_crosscheck_id=? AND status='CLAIMED' AND worker_id=?`(更新件数 1 でなければ終了)
2. `started-at.txt`(UTC ISO 8601)を `.tmp` → `mv`
3. 対象カタログ TSV から catalog_version の行を抜き出して一時 TSV に書く
4. 比較ツールを起動し stdout / stderr を `.tmp` へ、exit_code を取得
5. `stdout.log` / `stderr.log` / `exitcode.txt` を `mv` で確定
6. `UPDATE final_crosscheck_requests SET status=?, exit_code=?, stdout=?, stderr=?, error_summary=?, completed_at=:now WHERE final_crosscheck_id=? AND status='RUNNING'`(更新件数 0 = 比較中に ABORTED。`WARN request already terminal` を残して終了コード 0)

#### エラーハンドリング

| エラー種別 | リトライ | DLQ | 説明 |
|-----------|---------|-----|------|
| 比較ツール非 0(3 / 6 / その他) | No | No | 結果として FAILED を保存。再実行はジョブスケジューラの正規ジョブ(新しい依頼) |
| 比較ツール起動失敗 / カタログ 0 行 | No | No | FAILED(exit_code=6、error_summary)を保存し worker は 6 で終了 |
| 成果物書き込み失敗 | No | No | 依頼を FAILED(error_summary=artifact write failed)にできれば保存し 6 で終了 |
| RUNNING 遷移 UPDATE 0 件 | No | No | lease 失効で別 worker に回収済み。比較ツールを起動せず終了コード 0 |
| 終端 UPDATE 0 件(ABORTED 競合) | No | No | 中止済み。成果物 3 ファイルは残し、依頼は ABORTED のまま。終了コード 0 |
| DB UPDATE 失敗(終端。SQL エラー) | No | No | 6 で終了。依頼は RUNNING のまま。運用者が abort → 正規ジョブ再実行 |

## データモデル変更

### final_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | string | CLAIMED → RUNNING → SUCCEEDED / FAILED | 追加(更新) |
| started_at | datetime | RUNNING 遷移時刻(UTC) | 追加(更新) |
| completed_at | datetime | 終端遷移時刻 | 追加(更新) |
| exit_code | integer | 比較ツール終了コード(起動失敗は 6) | 追加(更新) |
| stdout | text | 比較ツール stdout 全文 | 追加(更新) |
| stderr | text | 比較ツール stderr 全文 | 追加(更新) |
| error_summary | string | 起動失敗・書き込み失敗の要約(正常終了・比較 NG は NULL) | 追加(更新) |

### 成果物ディレクトリ(ファイル。テーブルにしない)

| ファイル | 型 | 説明 | 変更種別 |
|---------|---|------|---------|
| `facade/<final_crosscheck_id>/final-crosscheck/started-at.txt` | text | 比較開始時刻(UTC ISO 8601、1 行) | 追加 |
| `.../stdout.log` / `.../stderr.log` | text | 比較ツール出力 | 追加 |
| `.../exitcode.txt` | text | 数値 1 行 | 追加 |
| `.../input/target-catalog.tsv` | TSV | 比較に使った対象カタログの抜粋(仮採用。Contract 4 ファイルと同階層には置かない) | 追加 |

## ビジネスルール

- 依頼状態遷移規則: CLAIMED → RUNNING → SUCCEEDED / FAILED。条件付き UPDATE
- 比較ツール終了コードの対応: 0 → SUCCEEDED、非 0 → FAILED。値は変換しない
- 適用側で定義する事項: 対象カタログと比較コマンドは設定ファイルが所有。worker は変更しない
- 成果物公開判定: `.tmp` → `mv`
- Runner Result Contract: 3 ファイル + started-at.txt を role=final-crosscheck に残す

## ティア完了条件(BDD)

```gherkin
Feature: 比較ツールで日次全量比較を実行して結果を保存する - 確報クロスチェックティア

  Scenario: 比較 OK を SUCCEEDED として保存する
    Given final_crosscheck_requests に final_crosscheck_id=20260830T210000Z-final-7b2c9e1f status=REQUESTED requested_at=2026-08-30T21:00:00Z catalog_version=v3 business_date=2026-08-30 がある(1 プロセスで claim → RUNNING → 終端まで検証する)
    And crosscheck-job-map.tsv の job_id=final-crosscheck 行の compare_command が /opt/compare/stub-ok.sh(終了コード 0、stdout "all 42 targets matched\n")を指す
    When `final-crosscheck-worker.sh --once --worker-id final-worker-01` を実行する
    Then 終了コード 0 で該当行は status=SUCCEEDED worker_id=final-worker-01 exit_code=0 stdout="all 42 targets matched\n" になり、started_at と completed_at が設定される
    And facade/20260830T210000Z-final-7b2c9e1f/final-crosscheck/exitcode.txt の中身は "0" で、同ディレクトリに *.tmp は残っていない

  Scenario: 比較 NG(3)を FAILED として保存し worker は 0 で終了する
    Given 同じ依頼が status=REQUESTED で、compare_command が終了コード 3 を返す
    When `final-crosscheck-worker.sh --once --worker-id final-worker-01` を実行する
    Then worker の終了コードは 0 で、該当行は status=FAILED exit_code=3 である

  Scenario: 比較ツールが実行できない
    Given 同じ依頼が status=REQUESTED で、compare_command が /opt/compare/missing.sh(存在しない)を指す
    When `final-crosscheck-worker.sh --once --worker-id final-worker-01` を実行する
    Then 終了コード 6 で stderr に "error: compare tool launch failed final_crosscheck_id=20260830T210000Z-final-7b2c9e1f command=/opt/compare/missing.sh" が出る
    And 該当行は status=FAILED exit_code=6 error_summary="launch failed" である(速報 worker と同じ値。契約 final-crosscheck-worker.sh stderr と同文)

  Scenario: catalog_version の行が 0 行
    Given 同じ依頼が status=REQUESTED catalog_version=v9 で、対象カタログ TSV に catalog_version=v9 の行が無い
    When `final-crosscheck-worker.sh --once --worker-id final-worker-01` を実行する
    Then 比較ツールは起動されず、該当行は status=FAILED exit_code=6 error_summary="no catalog rows catalog_version=v9" である
    And worker は終了コード 6 で終了する

  Scenario: 比較中に ABORTED された依頼は終端 UPDATE 0 件で終了コード 0
    Given 同じ依頼が status=REQUESTED で、compare_command が停止シグナルを受けるまで待機するスタブを指す
    And `final-crosscheck-worker.sh --once --worker-id final-worker-01` を起動し、該当行が status=RUNNING になった後に `abort-final-crosscheck.sh --run-id 20260830T210000Z-final-7b2c9e1f --yes` で ABORTED にする
    When スタブに停止シグナルを送る
    Then worker は終了コード 0 で終了し、該当行は status=ABORTED exit_code=NULL のままである
    And facade/20260830T210000Z-final-7b2c9e1f/final-crosscheck/ に exitcode.txt が確定名で残り、実行ログに "WARN request already terminal final_crosscheck_id=20260830T210000Z-final-7b2c9e1f status=ABORTED" が残る
```
