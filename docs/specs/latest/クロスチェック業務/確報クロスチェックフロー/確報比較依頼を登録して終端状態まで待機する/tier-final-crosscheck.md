# 確報比較依頼を登録して終端状態まで待機する - 確報クロスチェックティア仕様

## 変更概要

ジョブスケジューラの確報ジョブ定義から起動される `final-crosscheck-runner.sh` を追加する。presentation(引数検証)→ usecase(final_crosscheck_id 発行 → 依頼登録 → 60 秒間隔の同期 polling → 終端判定)→ repository(`final_crosscheck_requests` / 対象カタログ)→ gateway(RDB クライアントアダプタ)の構成。runner は依頼を REQUESTED で作成するだけで、以降の状態遷移は行わない。終端状態到達後の中継は UC「保存済みの確報結果をジョブスケジューラへ返す」(同じプロセスの後半)に引き継ぐ。

## コマンド契約

### final-crosscheck-runner.sh

- **書式**: `final-crosscheck-runner.sh --business-date <YYYY-MM-DD> --catalog-version <ver> [--verbose] [--help]`
- **アクセス権**: ジョブスケジューラの確報クロスチェックジョブ定義から起動する(同期。終端状態まで戻らない)。運用者が手動で再実行してもよい(復旧手段の選択: 確報はジョブスケジューラの正規ジョブを直接再実行する)。管理 DB 接続は閉域セグメント内の OS 権限で行う(CTP-002)

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--business-date` | string | Yes | — | 比較対象の業務日付。`YYYY-MM-DD`(暦日として妥当な日付) |
| `--catalog-version` | string | Yes | — | 対象カタログの版。対象カタログ TSV の `catalog_version` 列に存在する値 |
| `--verbose` | boolean | No | false | `info:` を実行ログに出す(中継系のため stderr には出さない) |
| `--help` | boolean | No | false | usage を stdout に出し終了コード 0 |

- **stdin**: なし

#### 設定契約(final-crosscheck.env。`RELAY_GATE_CONFIG_DIR/final-crosscheck.env`、仮採用: _inference.md #5 / #6)

| キー | 型 | 必須 | 既定値 | 検証ルール |
|------|---|------|-------|-----------|
| `FINAL_POLL_INTERVAL_SEC` | integer | No | 60 | 1 以上の整数 |
| `FINAL_POLL_LIMIT_SEC` | integer | No | 28800(8 時間) | 1 以上の整数(cli-command-contract.yaml `integer(>=1)`。`FINAL_POLL_INTERVAL_SEC` より小さい値は最初の polling で上限超過となるが、検証エラーにはしない) |
| `FINAL_WORKER_POLL_INTERVAL_SEC` | integer | No | 30 | worker が使う(本 UC では読まない) |
| `FINAL_LEASE_MINUTES` | integer | No | 10 | worker が使う(本 UC では読まない) |
| `FINAL_DB_CONN_REF` | string | Yes | — | 管理 DB 接続情報の参照名(値は置かない。CTP-002)。解決方法は `_cross-cutting/datastore/` に従う |

- 対象カタログの所在は `RELAY_GATE_CONFIG_DIR/crosscheck-job-map.tsv` のヘッダーコメント `# target_catalog_path=<絶対パス>` / `# catalog_version=<既定版>` から解決する(step3 canonical C5。定義は G2 UC「クロスチェックのジョブマップと比較定義を定義する」を正とする)。`--catalog-version` は既定版より優先する
- 対象カタログ TSV(ヘッダー行あり): `catalog_version	target_type	target_identifier	compare_condition	business_date_handling`。`--catalog-version` の値を持つ行が 1 行以上あることを起動時に検証する

## 出力契約

- **stdout**: 待機中は何も出さない。終端到達後は UC「保存済みの確報結果をジョブスケジューラへ返す」が保存済み stdout を無加工で出す
- **stderr**: 中継に至る前の relay-gate 自身のエラーのみ `error: ...` + `hint: ...`。待機中の進捗は stderr に出さず実行ログに残す(ui-design.md「長時間処理」)
- **終了コード**(中継に至る前):
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 2 | 入力・設定検証エラー | 引数欠落、`--business-date` 形式不正、未知のオプション、`final-crosscheck.env` 不在または必須キー欠落、クロスチェックジョブマップのヘッダーコメント `# target_catalog_path=` が無い、対象カタログに `catalog_version` の行が無い |
  | 6 | 実行エラー | 管理 DB 接続・INSERT・SELECT 失敗、polling 上限超過(`FINAL_POLL_LIMIT_SEC`)、内部エラー |
  | 保存済み exit_code | 無加工中継 | 終端状態到達後(UC「保存済みの確報結果をジョブスケジューラへ返す」) |

- エラーメッセージ(1 回だけ出す。CLR-003):
  - `error: option required option=--business-date` / `error: option required option=--catalog-version`(ui-design.md「必須オプション欠落の定型文」。終了コード 2)
  - `error: invalid value option=--business-date value=20260830` + `hint: expected YYYY-MM-DD`(契約の共通形式。終了コード 2)
  - `error: config file not found path: /etc/relay-gate/final-crosscheck.env` / `error: option required option=FINAL_DB_CONN_REF path: /etc/relay-gate/final-crosscheck.env`(終了コード 2)
  - `error: target_catalog_path declaration not found path: /etc/relay-gate/crosscheck-job-map.tsv` + `hint: add a header comment line "# target_catalog_path=<absolute path>"`(終了コード 2)
  - `error: catalog version not found catalog_version=v3 path: /etc/relay-gate/target-catalog.tsv`
  - `error: management db query failed final_crosscheck_id=...`(終了コード 6)
  - `error: polling limit exceeded final_crosscheck_id=... status=... limit_sec=28800`(status は超過時点の依頼 status。実行ログ `INFO polling ...` にも残す)+ `hint: the request is left unchanged; check final-crosscheck-worker.sh, then abort with abort-final-crosscheck.sh --run-id ... if needed`(終了コード 6)

## UC ロジック

- **バリデーション**: `--business-date` は `^[0-9]{4}-[0-9]{2}-[0-9]{2}$` かつ `date -u -d` で妥当。`--catalog-version` は非空・タブ/改行を含まない。両方とも欠落は終了コード 2。feature flag ファイルは読まない(確報クロスチェック非起動)
- **確認プロンプト**: なし
- **冪等性**: 起動のたびに新しい final_crosscheck_id で依頼を 1 件登録する(同じ business_date / catalog_version で複数回起動すれば依頼は複数件になる。再実行はジョブスケジューラの正規ジョブで行う前提)。polling 中は状態を UPDATE しない
- **polling**: `FINAL_POLL_INTERVAL_SEC` ごとに `SELECT status FROM final_crosscheck_requests WHERE final_crosscheck_id = ?`(status のみ。保存済み exit_code / stdout / stderr は終端到達後に UC「保存済みの確報結果をジョブスケジューラへ返す」が 1 回だけ 4 列 SELECT する)。status ∈ {SUCCEEDED, FAILED, ABORTED} で抜ける。requested_at から `FINAL_POLL_LIMIT_SEC` を超過したら終了コード 6(依頼は変更しない)。poll ごとに実行ログへ `INFO polling final_crosscheck_id=... status=... elapsed_minutes=...`
- **エラーハンドリング**: polling 中の一時的な SELECT 失敗は同じ間隔で最大 3 回連続まで再試行し(仮採用: DB の短時間断に対する保守値)、4 回連続失敗で終了コード 6。INSERT 失敗は再試行せず終了コード 6
- **クラッシュ耐性**: INSERT 前に落ちた場合は何も残らない。INSERT 後に runner プロセスが落ちても依頼は REQUESTED のまま残り、worker が通常どおり処理する。ジョブスケジューラ側の再実行は新しい依頼を作る(残った依頼は運用者が `abort-final-crosscheck.sh` で整理する。RUNNING 以外は abort 不可のため REQUESTED / CLAIMED の残骸は worker に処理させてから判断する)
- **速報と確報のモデル分離**: 本コマンドが発行する SQL の対象は `final_crosscheck_requests` のみ
- **実行ログ**: `RELAY_GATE_LOG_DIR/final-crosscheck-runner.sh.log`。run_id 欄には final_crosscheck_id を置く(CLP-006)。`INFO request registered final_crosscheck_id=... business_date=... catalog_version=... status=REQUESTED`

## 非同期イベント

### final-crosscheck-requests(publish)

- **チャネル**: 管理 DB `final_crosscheck_requests`(RDB ジョブキュー)
- **方向**: publish(runner が REQUESTED 行を INSERT)。subscribe は UC「確報比較依頼を claim する」
- **AsyncAPI**: [asyncapi.yaml](../../../_cross-cutting/api/asyncapi.yaml) の `channels.final-crosscheck-requests` を参照
- **メッセージ**: FinalCrosscheckRequestMessage(final_crosscheck_id, business_date, catalog_version, status=REQUESTED, requested_at)

## データモデル変更

### final_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| final_crosscheck_id | string | 主キー。`{UTC yyyymmddThhmmssZ}-final-{8 hex}` | 追加 |
| business_date | date | 比較対象の業務日付 | 追加 |
| catalog_version | string | 対象カタログの版 | 追加 |
| status | string | REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED。本 UC は REQUESTED で INSERT | 追加 |
| worker_id | string | claim した worker(NULL 可) | 追加 |
| lease_until | datetime | lease 失効時刻(NULL 可) | 追加 |
| requested_at | datetime | 登録日時(UTC) | 追加 |
| started_at | datetime | 比較開始日時(NULL 可) | 追加 |
| completed_at | datetime | 終端到達日時(NULL 可) | 追加 |
| exit_code | integer | 比較ツール終了コード(NULL 可) | 追加 |
| stdout | text | 比較ツール stdout(NULL 可) | 追加 |
| stderr | text | 比較ツール stderr(NULL 可) | 追加 |
| error_summary | string | 実行エラー時の要約(NULL 可) | 追加 |

### 対象カタログ TSV(設定ファイル。テーブルにしない)

| 列 | 型 | 説明 | 変更種別 |
|----|---|------|---------|
| catalog_version | string | 版 | 追加 |
| target_type | enum | `table` / `file` | 追加 |
| target_identifier | string | テーブル名またはファイルパスパターン | 追加 |
| compare_condition | string | 比較条件(比較ツールへ渡す) | 追加 |
| business_date_handling | string | business_date の扱い(比較ツールへ渡す) | 追加 |

## ビジネスルール

- 確報依頼の登録条件: 起動 1 回につき依頼 1 件を REQUESTED で登録し、終端状態まで同期 polling する
- 速報と確報のモデル分離: `rapid_runs` / `rapid_crosscheck_requests` / `parallel_runs` を作成・変更・参照しない
- 確報クロスチェック非起動: feature flag を読まず、facade からは起動されない
- 依頼状態遷移規則: runner は REQUESTED の作成のみ。CLAIMED / RUNNING / 終端は worker、ABORTED は abort-final-crosscheck が行う
- polling 上限超過は終了コード 6 で終了し、依頼の状態を変更しない(_inference.md #6)

## ティア完了条件(BDD)

```gherkin
Feature: 確報比較依頼を登録して終端状態まで待機する - 確報クロスチェックティア

  Scenario: 依頼を REQUESTED で登録して polling を開始する
    Given RELAY_GATE_CONFIG_DIR/final-crosscheck.env に FINAL_POLL_INTERVAL_SEC=1 FINAL_POLL_LIMIT_SEC=10 FINAL_DB_CONN_REF=relaygate-db がある
    And RELAY_GATE_CONFIG_DIR/crosscheck-job-map.tsv のヘッダーコメントに # target_catalog_path=/etc/relay-gate/target-catalog.tsv がある
    And /etc/relay-gate/target-catalog.tsv に catalog_version=v3 の行が 2 行ある
    And 別プロセスが 3 秒後に該当依頼を status=SUCCEEDED exit_code=0 stdout="all targets matched" stderr="" に更新する
    When `final-crosscheck-runner.sh --business-date 2026-08-30 --catalog-version v3` を実行する
    Then final_crosscheck_requests に business_date=2026-08-30 catalog_version=v3 status=REQUESTED の行が INSERT される
    And 実行ログに "INFO request registered" と "INFO polling" の行が残る
    And 終了コード 0 で stdout に "all targets matched" が出る

  Scenario: polling 上限超過で終了コード 6
    Given final-crosscheck.env に FINAL_POLL_INTERVAL_SEC=1 FINAL_POLL_LIMIT_SEC=2 がある
    And worker が稼働していない
    When `final-crosscheck-runner.sh --business-date 2026-08-30 --catalog-version v3` を実行する
    Then 終了コード 6 で stderr に "error: polling limit exceeded" と "hint: the request is left unchanged" が出る
    And 該当依頼は status=REQUESTED のままである

  Scenario: --catalog-version 欠落
    When `final-crosscheck-runner.sh --business-date 2026-08-30` を実行する
    Then 終了コード 2 で stderr に "error: option required option=--catalog-version" が出る
    And final_crosscheck_requests に行は追加されない

  Scenario: 管理 DB に接続できない
    Given FINAL_DB_CONN_REF が解決できない接続先を指す
    When `final-crosscheck-runner.sh --business-date 2026-08-30 --catalog-version v3` を実行する
    Then 終了コード 6 で stderr に "error: management db connection failed conn_ref=" で始まる行が出る
```
