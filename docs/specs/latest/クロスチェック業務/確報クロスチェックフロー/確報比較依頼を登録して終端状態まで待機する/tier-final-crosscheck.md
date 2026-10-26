# 確報比較依頼を登録して終端状態まで待機する - 確報クロスチェックティア仕様

## 変更概要

ジョブスケジューラの確報ジョブ定義から業務上の引数なしで起動される `final-crosscheck-runner.sh` を追加する。presentation(実行補助オプション検証)→ usecase(final_crosscheck_id 発行 → 依頼登録 → 60 秒間隔の同期 polling → 終端判定)→ repository(`final_crosscheck_requests`)→ gateway(RDB クライアントアダプタ)の構成。runner は依頼を REQUESTED で作成するだけで、以降の状態遷移は行わない。終端状態到達後の中継は UC「保存済みの確報結果をジョブスケジューラへ返す」(同じプロセスの後半)に引き継ぐ。

## コマンド契約

### final-crosscheck-runner.sh

- **書式**: `final-crosscheck-runner.sh [--verbose] [--help]`(業務上の引数は受け付けない)
- **アクセス権**: ジョブスケジューラの確報クロスチェックジョブ定義から起動する(同期。終端状態まで戻らない)。運用者が手動で再実行してもよい(復旧手段の選択: 確報はジョブスケジューラの正規ジョブを直接再実行する)。管理 DB 接続は閉域セグメント内の OS 権限で行う(CTP-002)

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--verbose` | boolean | No | false | `info:` を実行ログに出す(中継系のため stderr には出さない) |
| `--help` | boolean | No | false | usage を stdout に出し終了コード 0 |

- 業務上の引数(比較対象の業務日付・対象カタログの版など)は無い。依頼は識別子・状態・時刻・結果だけを持ち、比較対象は比較ツール側が定義する。最初の `--` 始まりでない引数・未知のオプションは `error: unknown option option=...` で終了コード 2
- **stdin**: なし

#### 設定契約(final-crosscheck.env。`RELAY_GATE_CONFIG_DIR/final-crosscheck.env`、仮採用: _inference.md #5 / #6)

| キー | 型 | 必須 | 既定値 | 検証ルール |
|------|---|------|-------|-----------|
| `FINAL_COMPARE_COMMAND` | string | Yes | — | 確報の比較ツール起動コマンド 1 行(プレースホルダ無し)。worker が使う(本 UC では読まない)。検証は UC「比較ツールで日次全量比較を実行して結果を保存する」の `validate-config.sh --final-crosscheck` が所有する |
| `FINAL_POLL_INTERVAL_SEC` | integer | No | 60 | 1 以上の整数 |
| `FINAL_POLL_LIMIT_SEC` | integer | No | 28800(8 時間) | 1 以上の整数(cli-command-contract.yaml `integer(>=1)`。`FINAL_POLL_INTERVAL_SEC` より小さい値は最初の polling で上限超過となるが、検証エラーにはしない) |
| `FINAL_WORKER_POLL_INTERVAL_SEC` | integer | No | 30 | worker が使う(本 UC では読まない) |
| `FINAL_LEASE_MINUTES` | integer | No | 10 | worker が使う(本 UC では読まない) |
| `FINAL_DB_CONN_REF` | string | Yes | — | 管理 DB 接続情報の参照名(値は置かない。CTP-002)。解決方法は `_cross-cutting/datastore/` に従う |

- 本 UC は比較対象の設定ファイル(対象カタログ・ジョブ ID ごとの比較定義)を読まない。比較対象は比較ツール側が定義する(適用側で定義する事項)

## 出力契約

- **stdout**: 待機中は何も出さない。終端到達後は UC「保存済みの確報結果をジョブスケジューラへ返す」が保存済み stdout を無加工で出す
- **stderr**: 中継に至る前の relay-gate 自身のエラーのみ `error: ...` + `hint: ...`。待機中の進捗は stderr に出さず実行ログに残す(ui-design.md「長時間処理」)
- **終了コード**(中継に至る前):
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 2 | 入力・設定検証エラー | 未知のオプション、業務上の引数が渡された、`final-crosscheck.env` 不在または必須キー欠落 |
  | 6 | 実行エラー | 管理 DB 接続・INSERT・SELECT 失敗、polling 上限超過(`FINAL_POLL_LIMIT_SEC`)、内部エラー |
  | 保存済み exit_code | 無加工中継 | 終端状態到達後(UC「保存済みの確報結果をジョブスケジューラへ返す」) |

- エラーメッセージ(1 回だけ出す。CLR-003):
  - `error: unknown option option=--business-date`(業務上の引数・未知のオプション。終了コード 2)
  - `error: config file not found path: /etc/relay-gate/final-crosscheck.env` / `error: option required option=FINAL_DB_CONN_REF path: /etc/relay-gate/final-crosscheck.env`(終了コード 2)
  - `error: management db query failed final_crosscheck_id=...`(終了コード 6)
  - `error: polling limit exceeded final_crosscheck_id=... status=... limit_sec=28800`(status は超過時点の依頼 status。実行ログ `INFO polling ...` にも残す)+ `hint: the request is left unchanged; check final-crosscheck-worker.sh, then abort with abort-final-crosscheck.sh --run-id ... if needed`(終了コード 6)

## UC ロジック

- **設定ファイルの読み込み(共通規約の参照)**: 読む設定ファイル(env)の入力の守備範囲は CLI 契約 `config_input_rules` に従う(形式(UTF-8 / LF)から外れた NUL バイト・不正な文字コード・BOM・CR は契約と同文の error 行で拒否して終了コード 2、読み込みは 1 時点の内容だけで判定、補助コマンドの失敗は終了コード 6。値は本 tier に複写しない)。stdout / stderr / 実行ログに出す任意入力の制御文字は `ui-design.md`「制御文字の表記」の可視表記にする。bash の最低版は 5.0(契約 `conventions.runtime_prerequisites`)
- **バリデーション**: 受け付けるのは `--verbose` / `--help` のみ。業務上の引数・未知のオプションは終了コード 2。feature flag ファイルは読まない(確報クロスチェック非起動)
- **確認プロンプト**: なし
- **冪等性**: 起動のたびに新しい final_crosscheck_id で依頼を 1 件登録する(複数回起動すれば依頼は複数件になる。再実行はジョブスケジューラの正規ジョブで行う前提)。polling 中は状態を UPDATE しない
- **polling**: `FINAL_POLL_INTERVAL_SEC` ごとに `SELECT status FROM final_crosscheck_requests WHERE final_crosscheck_id = ?`(status のみ。保存済み exit_code / stdout / stderr は終端到達後に UC「保存済みの確報結果をジョブスケジューラへ返す」が 1 回だけ 4 列 SELECT する)。status ∈ {SUCCEEDED, FAILED, ABORTED} で抜ける。requested_at から `FINAL_POLL_LIMIT_SEC` を超過したら終了コード 6(依頼は変更しない)。poll ごとに実行ログへ `INFO polling final_crosscheck_id=... status=... elapsed_minutes=...`
- **エラーハンドリング**: polling 中の一時的な SELECT 失敗は同じ間隔で最大 3 回連続まで再試行し(仮採用: DB の短時間断に対する保守値)、4 回連続失敗で終了コード 6。INSERT 失敗は再試行せず終了コード 6
- **クラッシュ耐性**: INSERT 前に落ちた場合は何も残らない。INSERT 後に runner プロセスが落ちても依頼は REQUESTED のまま残り、worker が通常どおり処理する。ジョブスケジューラ側の再実行は新しい依頼を作る(残った依頼は運用者が `abort-final-crosscheck.sh` で整理する。RUNNING 以外は abort-final-crosscheck では中止できない(条件「依頼中止可否判定」)。runner が落ちて polling が無い REQUESTED / CLAIMED の残骸は worker が通常どおり処理して終端させる(polling 中の未着手依頼は runner 側の polling 上限 FINAL_POLL_LIMIT_SEC で扱う))
- **速報と確報のモデル分離**: 本コマンドが発行する SQL の対象は `final_crosscheck_requests` のみ
- **実行ログ**: `RELAY_GATE_LOG_DIR/final-crosscheck-runner.sh.log`。run_id 欄には final_crosscheck_id を置く(CLP-006)。`INFO request registered final_crosscheck_id=... status=REQUESTED`

## 非同期イベント

### final-crosscheck-requests(publish)

- **チャネル**: 管理 DB `final_crosscheck_requests`(RDB ジョブキュー)
- **方向**: publish(runner が REQUESTED 行を INSERT)。subscribe は UC「確報比較依頼を claim する」
- **AsyncAPI**: [asyncapi.yaml](../../../_cross-cutting/api/asyncapi.yaml) の `channels.final-crosscheck-requests` を参照
- **メッセージ**: FinalCrosscheckRequestMessage(final_crosscheck_id, status=REQUESTED, requested_at)

## データモデル変更

### final_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| final_crosscheck_id | string | 主キー。`{ローカル yyyymmddThhmmss}-final-{8 hex}`(時刻部はホストのローカルタイムゾーン。タイムゾーン指示子なし) | 追加 |
| status | string | REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED。本 UC は REQUESTED で INSERT | 追加 |
| worker_id | string | claim した worker(NULL 可) | 追加 |
| lease_until | datetime | lease 失効時刻(NULL 可) | 追加 |
| requested_at | datetime | 登録日時(ローカル時刻) | 追加 |
| started_at | datetime | 比較開始日時(NULL 可) | 追加 |
| completed_at | datetime | 終端到達日時(NULL 可) | 追加 |
| exit_code | integer | 比較ツール終了コード(NULL 可) | 追加 |
| stdout | text | 比較ツール stdout(NULL 可) | 追加 |
| stderr | text | 比較ツール stderr(NULL 可) | 追加 |
| error_summary | string | 実行エラー時の要約(NULL 可) | 追加 |

- business_date 列・対象カタログの版の列・対象カタログへの紐付けは持たない(速報と確報のモデル分離。rdb-schema.yaml `final_crosscheck_requests`)

## ビジネスルール

- 確報依頼の登録条件: 業務上の引数なしで起動 1 回につき依頼 1 件を REQUESTED で登録し、終端状態まで同期 polling する
- 速報と確報のモデル分離: `rapid_runs` / `rapid_crosscheck_requests` / `parallel_runs` を作成・変更・参照しない
- 確報クロスチェック非起動: feature flag を読まず、facade からは起動されない
- 依頼状態遷移規則: runner は REQUESTED の作成のみ。CLAIMED / RUNNING / 終端は worker、ABORTED は abort-final-crosscheck が行う
- polling 上限超過は終了コード 6 で終了し、依頼の状態を変更しない(_inference.md #6)

## ティア完了条件(BDD)

```gherkin
Feature: 確報比較依頼を登録して終端状態まで待機する - 確報クロスチェックティア

  Scenario: 業務上の引数なしで依頼を REQUESTED で登録して polling を開始する
    Given RELAY_GATE_CONFIG_DIR/final-crosscheck.env に FINAL_POLL_INTERVAL_SEC=1 FINAL_POLL_LIMIT_SEC=10 FINAL_DB_CONN_REF=relaygate-db がある
    And 別プロセスが 3 秒後に該当依頼を status=SUCCEEDED exit_code=0 stdout="all targets matched" stderr="" に更新する
    When `final-crosscheck-runner.sh` を業務上の引数なしで実行する
    Then final_crosscheck_requests に status=REQUESTED の行が INSERT され、その行に business_date 列・catalog_version 列は無い
    And 実行ログに "INFO request registered" と "INFO polling" の行が残る
    And 終了コード 0 で stdout に "all targets matched" が出る

  Scenario: polling 上限超過で終了コード 6
    Given final-crosscheck.env に FINAL_POLL_INTERVAL_SEC=1 FINAL_POLL_LIMIT_SEC=2 がある
    And worker が稼働していない
    When `final-crosscheck-runner.sh` を業務上の引数なしで実行する
    Then 終了コード 6 で stderr に "error: polling limit exceeded" と "hint: the request is left unchanged" が出る
    And 該当依頼は status=REQUESTED のままである

  Scenario: 未知のオプション
    When `final-crosscheck-runner.sh --catalog-version v3` を実行する
    Then 終了コード 2 で stderr に "error: unknown option option=--catalog-version" が出る
    And final_crosscheck_requests に行は追加されない

  Scenario: 管理 DB に接続できない
    Given FINAL_DB_CONN_REF が解決できない接続先を指す
    When `final-crosscheck-runner.sh` を業務上の引数なしで実行する
    Then 終了コード 6 で stderr に "error: management db connection failed conn_ref=" で始まる行が出る
```
