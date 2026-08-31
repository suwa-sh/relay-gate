# 確報クロスチェック結果を確認する - 確報クロスチェックティア仕様

## 変更概要

このティアに新しいコマンドは追加しない。運用者が読む「確報ジョブの実行結果」は `final-crosscheck-runner.sh` の応答契約(UC「保存済みの確報結果をジョブスケジューラへ返す」)そのものである。本ファイルは運用者向けに「応答に何が含まれ、何が含まれないか」と「終了コードの読み方」を確定する。

## コマンド契約

### final-crosscheck-runner.sh(応答の読み手としての契約)

- **書式**: `final-crosscheck-runner.sh --business-date <YYYY-MM-DD> --catalog-version <ver>`(ジョブスケジューラの確報ジョブ定義に登録する)
- **アクセス権**: 起動はジョブスケジューラ。結果の参照は運用者がジョブスケジューラの実行履歴で行う

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--business-date` | string | Yes | — | 比較対象の業務日付 |
| `--catalog-version` | string | Yes | — | 対象カタログの版 |

- **stdin**: なし

## 出力契約

- **stdout**: 比較ツールが出した標準出力そのもの(依頼の `stdout`)。relay-gate の `key=value` 行は含まれない
- **stderr**: 比較ツールが出した標準エラーそのもの(依頼の `stderr`)。例外は中継に至る前の relay-gate 自身のエラー(`error: ...` 1 行 + `hint:`)のみ(exit_code が NULL の ABORTED は終了コード 6 で stdout / stderr は保存済みのまま。追加行なし)
- **終了コード**(運用者の読み方):
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 比較 OK(日次整合性 OK) | 比較ツールが 0 で終了し依頼が SUCCEEDED |
  | 3 | 比較 NG(警告終了) | 比較ツールが 3 で終了し依頼が FAILED。差分の原因調査へ |
  | 6 | 実行エラー(エラー終了) | 比較ツールが 6 で終了(依頼 FAILED)、または relay-gate 自身の実行エラー(DB 接続失敗・polling 上限超過・ABORTED で exit_code NULL) |
  | 2 | 入力・設定検証エラー | ジョブ定義の引数誤り、対象カタログ不備(中継に至る前) |
  | その他の非 0 | 比較ツール実装の契約に従う | relay-gate は値を変換しない |

- 応答に**含まれないもの**: 依頼の状態名(SUCCEEDED / FAILED / ABORTED)、final_crosscheck_id、差分件数、レポート URI、速報比較の結果、background slot の結果
- 終了コード 6 が比較ツール由来か relay-gate 由来かは、標準エラーの先頭が `error: ` で始まり `final_crosscheck_id=` または `conn_ref=` を含むかどうかで区別できる(relay-gate 由来のみこの形式。`conn_ref=` は依頼 INSERT 前の管理 DB 接続失敗 `error: management db connection failed conn_ref=...`)。判別に迷う場合は runner の実行ログに `INFO request registered final_crosscheck_id=...` が有るか(有れば比較ツール由来の可能性がある)で確認する。例外として ABORTED で exit_code が NULL のときは stderr に追加行を書かず 0 バイトのまま 6 を返す(UC「保存済みの確報結果をジョブスケジューラへ返す」)ため、この場合は runner の実行ログ `WARN relay without stored exit_code final_crosscheck_id=... status=ABORTED` で確認する

## UC ロジック

- **バリデーション**: なし(運用者の参照操作)
- **確認プロンプト**: なし
- **冪等性**: 実行履歴の参照は何度行っても同じ。確報ジョブの再実行は新しい依頼を作る(前回の依頼は管理 DB に残る)
- **エラーハンドリング**(運用者の対処):
  - 終了コード 3 → 標準出力・標準エラーの差分内容を読む。必要なら速報結果(`rapid-crosscheck-result.sh --run-id`)を参考にするが、リリース判断は確報で行う
  - 終了コード 6 で標準エラーが比較ツール由来 → 比較ツール側の原因を取り除いて確報ジョブを直接再実行
  - 終了コード 6 で `error: polling limit exceeded` → worker の稼働を確認し、RUNNING のまま残った依頼は `abort-final-crosscheck.sh --run-id <final_crosscheck_id>` で中止してから再実行
  - 終了コード 2 → ジョブ定義の引数・対象カタログを修正
- **クラッシュ耐性**: 該当なし(参照のみ)。ジョブスケジューラの実行履歴が正本

## データモデル変更

### final_crosscheck_requests(参照。SQL で直接確認する場合)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| final_crosscheck_id | string | 応答には含まれない。実行ログ `final-crosscheck-runner.sh.log` の `request registered` 行から特定する | 追加(参照) |
| business_date / catalog_version | date / string | 対象 | 追加(参照) |
| status | string | 応答には含まれない | 追加(参照) |
| exit_code / stdout / stderr | integer / text / text | 応答と同じ値 | 追加(参照) |

## ビジネスルール

- 確報結果の中継制約: 応答は 3 値のみ。状態名・差分件数・レポート URI は返らない
- 速報結果の位置付け: 速報は原因調査用。リリース判断の正本は確報
- 実行履歴はジョブスケジューラの責務: 監査・履歴はジョブスケジューラ、relay-gate は実行ログと依頼レコードを残すだけ
- 復旧手段の選択: 確報の再実行はジョブスケジューラの正規ジョブ。`background-rerun.sh` の対象外

## ティア完了条件(BDD)

```gherkin
Feature: 確報クロスチェック結果を確認する - 確報クロスチェックティア

  Scenario: 応答に 3 値だけが含まれる
    Given final-crosscheck.env に FINAL_POLL_INTERVAL_SEC=1 がある
    And 別プロセスが 3 秒後に、runner が登録した最新の依頼(requested_at が最大の行)を status=FAILED exit_code=3 stdout="diff found: 12 rows\n" stderr="warn: table T_ORDER differs\n" に更新する(runner は起動のたびに新規 id を登録して polling するため、事前 INSERT した行は中継されない)
    When `final-crosscheck-runner.sh --business-date 2026-08-30 --catalog-version v3` を実行して応答を確認する
    Then 終了コード 3 で stdout は "diff found: 12 rows\n"、stderr は "warn: table T_ORDER differs\n" と完全一致する
    And stdout と stderr に "status=" "final_crosscheck_id=" "difference_count" "report_uri" は含まれない

  Scenario: relay-gate 由来の終了コード 6 を標準エラーで区別できる
    Given final-crosscheck-worker.sh が停止しており、final-crosscheck.env に FINAL_POLL_INTERVAL_SEC=1 FINAL_POLL_LIMIT_SEC=2 がある
    When `final-crosscheck-runner.sh --business-date 2026-08-30 --catalog-version v3` を実行する
    Then 終了コード 6 で stderr の 1 行目が "error: polling limit exceeded final_crosscheck_id=" で始まる
```
