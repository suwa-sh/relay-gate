# 速報比較結果を参照する - 速報クロスチェックティア仕様

## 変更概要

参照系コマンド `rapid-crosscheck-result.sh` を追加する。presentation(引数検証・出力整形)→ usecase(取得フロー)→ repository(3 テーブルの SELECT)→ gateway(RDB クライアントアダプタ)の構成。状態は変更しない。

## コマンド契約

### rapid-crosscheck-result.sh

- **書式**: `rapid-crosscheck-result.sh --run-id <run_id> [--limit N] [--show-output] [--verbose] [--help]`
- **アクセス権**: 運用者の直接起動。管理 DB への接続は閉域セグメント内の OS 権限で行う(CTP-002)

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--run-id` | string | Yes | — | 参照する run_id(`{UTC yyyymmddThhmmssZ}-{job_id}-{8 hex}`) |
| `--limit` | integer | No | 100 | comparison_result TSV の出力上限行数 |
| `--show-output` | boolean | No | false | 依頼に保存された比較ツールの stdout / stderr 本文を末尾に出す(段階的開示) |
| `--verbose` | boolean | No | false | `info:` を stderr に出す(本コマンドは位置付け info を常に出す) |
| `--help` | boolean | No | false | usage を stdout に出し終了コード 0 |

- **stdin**: なし

## 出力契約

- **stdout**(plain → TSV の順、キー順固定):
  1. `run_id=`
  2. `job_id=`
  3. `request_status=`(REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED)
  4. `blue_status=`(rapid_runs。無ければ `-`)
  5. `green_status=`
  6. `exit_code=`(未完了は `-`)
  7. `worker_id=`
  8. `requested_at=`
  9. `completed_at=`
  10. TSV ヘッダー `comparison_result_id	comparison_type	status	difference_count	report_uri	compared_at` + 行(compared_at 昇順、同値は comparison_result_id 昇順、`--limit` まで。difference_count / report_uri の NULL は `-`。FAILED は difference_count が `-`)
  11. `--show-output` 時のみ TSV の後に空行 1 行、`--- stdout ---` / 本文 / `--- stderr ---` / 本文(`_cross-cutting/ux-ui/data-visualization.md` の出力構造が正)
- **stderr**: `info: rapid result is for investigation only; use final crosscheck for release decision`(常時)、`warn: output truncated limit=N`、`error: ...` + `hint: ...`
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 依頼が見つかり出力できた(比較結果 0 件でも 0。TSV はヘッダー行のみ) |
  | 2 | 入力エラー | `--run-id` 欠落、run_id 形式不正、`--limit` が正の整数でない、未知のオプション、`RELAY_GATE_CONFIG_DIR` に feature flag 設定が無い |
  | 3 | 業務エラー | run_id の依頼が存在しない / `RAPID_CROSSCHECK_MODE=off` |
  | 6 | 実行エラー | 管理 DB 接続・SQL 失敗 |

## UC ロジック

- **バリデーション**: `--run-id` は先頭 16 文字が `yyyymmddThhmmssZ`、末尾 8 文字が hex、中間が `-{job_id}-`。`--limit` は 1 以上の整数
- **確認プロンプト**: なし(参照のみ)
- **冪等性**: 何度実行しても同じ出力。DB を更新しない
- **エラーハンドリング**: 依頼なし → `error: rapid crosscheck request not found run_id=...` + `hint: check run_id in facade artifact dir or run-lineage.sh --run-id ...` / off → `error: rapid crosscheck is off; no management db to query mode=off` / DB 失敗 → `error: management db query failed run_id=...` 終了コード 6。エラーは 1 回だけ出す(CLR-002)
- **クラッシュ耐性**: 書き込みを行わないため途中終了で残るレコード・ファイルは無い。実行ログ(`RELAY_GATE_LOG_DIR/rapid-crosscheck-result.sh.log`)の追記のみ。ログ書き込み不可は `warn:` で継続
- **実行ログの行形式**: `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {UTC 出力日時} {LEVEL} {message}`)に従う。情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する
- **管理 DB 接続先**: `$RELAY_GATE_CONFIG_DIR/rapid-crosscheck.env` の `RAPID_DB_CONN_REF`(UC「速報比較依頼を claim する」tier-rapid-crosscheck.md の設定ファイル)。`RAPID_CROSSCHECK_MODE=on` で欠落なら終了コード 2
- **速報と確報のモデル分離**: SELECT 対象は rapid_runs / rapid_crosscheck_requests / comparison_results の 3 表のみ

## データモデル変更

### rapid_crosscheck_requests(参照)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | 主キー | 追加(参照) |
| job_id | string | JOB_ID | 追加(参照) |
| status | string | REQUESTED / CLAIMED / RUNNING / SUCCEEDED / FAILED / ABORTED | 追加(参照) |
| worker_id | string | claim した worker | 追加(参照) |
| exit_code | integer | 比較ツール終了コード | 追加(参照) |
| stdout / stderr | text | 比較ツール出力(`--show-output`) | 追加(参照) |
| requested_at / completed_at | datetime | UTC | 追加(参照) |

### comparison_results(参照)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| comparison_result_id | string | 主キー | 追加(参照) |
| run_id | string | 依頼への FK | 追加(参照) |
| comparison_type | string | 比較種別(比較定義の comparison_type) | 追加(参照) |
| status | string | OK / NG / FAILED | 追加(参照) |
| difference_count | integer | 差分件数(NULL 可) | 追加(参照) |
| report_uri | string | レポート URI(NULL 可) | 追加(参照) |
| compared_at | datetime | UTC | 追加(参照) |

### rapid_runs(参照)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | 主キー | 追加(参照) |
| blue_status / green_status | string | SUCCEEDED / FAILED(未完了は NULL) | 追加(参照) |

## ビジネスルール

- 速報結果の位置付け: 参照結果はジョブスケジューラ応答に影響しない。stderr の info で明示する
- 比較ツール終了コードの対応: 表示は登録済みの値をそのまま出し、変換しない
- 速報クロスチェック有効判定: off のときは管理 DB へ接続しない
- 速報と確報のモデル分離: final_* を参照しない

## ティア完了条件(BDD)

```gherkin
Feature: 速報比較結果を参照する - 速報クロスチェックティア

  Scenario: 依頼と比較結果を run_id で出力する
    Given rapid_crosscheck_requests に run_id=20260830T113000Z-JOB001-3f9a1c2e, job_id=JOB001, status=SUCCEEDED, exit_code=0 の行がある
    And comparison_results に同 run_id の行が 1 件ある
    When `rapid-crosscheck-result.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e` を実行する
    Then 終了コード 0 で stdout に `request_status=SUCCEEDED` と TSV ヘッダー行 + 1 行が出る

  Scenario: --limit で出力を打ち切る
    Given comparison_results に同 run_id の行が 3 件ある
    When `rapid-crosscheck-result.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e --limit 2` を実行する
    Then 終了コード 0 で TSV は 2 行、stderr に `warn: output truncated limit=2` が出る

  Scenario: run_id の形式が不正
    Given 引数 `--run-id abc`
    When `rapid-crosscheck-result.sh --run-id abc` を実行する
    Then 終了コード 2 で stderr に `error: invalid value option=--run-id value=abc` が出る

  Scenario: 未知のオプション
    When `rapid-crosscheck-result.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e --json` を実行する
    Then 終了コード 2 で stderr に `error: unknown option option=--json` が出る
```
