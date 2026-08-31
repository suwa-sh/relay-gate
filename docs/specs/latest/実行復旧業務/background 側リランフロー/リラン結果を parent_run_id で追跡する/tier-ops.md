# リラン結果を parent_run_id で追跡する - 実行監視・復旧ティア仕様

## 変更概要

`run-lineage.sh` を追加する。`parallel_runs.parent_run_id` を辿ってリラン系譜(祖先 + 子孫)を TSV で出す参照系コマンドである。状態を変更しない。列定義の正本は `../../../_cross-cutting/ux-ui/data-visualization.md` 3. である。

## コマンド契約

### run-lineage.sh

- **書式**: `run-lineage.sh --run-id <RUN_ID> [--limit N] [--verbose] [--help]`
- **アクセス権**: 運用者の直接起動(relay-gate 配置ディレクトリ)。管理 DB への読み取り接続が必要

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--run-id` | string | Yes | なし | 系譜に含まれる任意の run_id(最新でも途中でも元の実行でもよい) |
| `--limit` | integer(1 以上) | No | 100 | 出力行数の上限。系譜の深さでは打ち切らない |
| `--verbose` | boolean | No | false | 各 run の成果物ディレクトリを stderr に `info: artifact_dir: {path} run_id={run_id}` で出す |
| `--help` | boolean | No | false | 使い方を stdout に出して終了コード 0 |

- **stdin**: なし

## 出力契約

- **stdout**: TSV(タブ区切り、1 行目ヘッダー)。列順固定
  `depth	run_id	parent_run_id	job_id	role	run_status	requested_at	completed_at`
  - `parent_run_id` / `completed_at` の空値は `-`。`role` は元の実行で `-`
  - ソート: `depth` 降順(最新のリランが先頭、元の実行が末尾)→ 同 depth は `requested_at` 昇順
  - 指定 run_id の行を含む
- **stderr**: `error: run not found run_id=...`(3)/ `error: management db is not configured (RAPID_CROSSCHECK_MODE=off)`(3)/ `error: lineage cycle detected run_id=...`(6)/ `error: management db connection failed run_id=... conn_ref=...`(6。接続失敗)/ `error: management db query failed run_id=...`(6。SQL 失敗)/ `error: option required option=--run-id` / `error: invalid value option=--run-id|--limit value=...` / `error: unknown option option=...`(2)/ `warn: output truncated limit=N` / `info: artifact_dir: {path} run_id={run_id}`(--verbose、1 run 1 行)
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 系譜を出力した |
  | 2 | 入力エラー | `--run-id` 欠落・形式不正、未知オプション、`--limit` 不正 |
  | 3 | 業務エラー | 対象 run_id が存在しない(`error: run not found run_id=...`)、RAPID_CROSSCHECK_MODE=off(`error: management db is not configured (RAPID_CROSSCHECK_MODE=off)`)|
  | 6 | 実行エラー | 管理 DB 接続・SQL 失敗(`error: management db query failed run_id=...`)、系譜の循環検出(`error: lineage cycle detected run_id=...`。既訪問 run_id に再到達) |

出力例:

```text
$ run-lineage.sh --run-id 20260830T140000Z-JOB001-c4d5e6f7
depth	run_id	parent_run_id	job_id	role	run_status	requested_at	completed_at
2	20260830T140000Z-JOB001-c4d5e6f7	20260830T124500Z-JOB001-7b2d9e01	JOB001	green	COMPLETED	2026-08-30T14:00:00Z	2026-08-30T15:10:00Z
1	20260830T124500Z-JOB001-7b2d9e01	20260830T113000Z-JOB001-3f9a1c2e	JOB001	green	ABORTED	2026-08-30T12:45:00Z	2026-08-30T13:50:00Z
0	20260830T113000Z-JOB001-3f9a1c2e	-	JOB001	-	ABORTED	2026-08-30T11:30:00Z	2026-08-30T12:40:00Z
```

## UC ロジック

- **バリデーション**: presentation で `--run-id` の形式(先頭 16 文字 `yyyymmddThhmmssZ`、末尾 8 文字 hex)を検証。NG は 2
- **確認プロンプト**: なし(参照系)
- **冪等性**: 読み取りのみ
- **系譜の収集(usecase)**:
  1. 指定 run を取得(0 行なら 3)
  2. 祖先: `parent_run_id` が空になるまで `SELECT ... WHERE run_id = parent_run_id` を繰り返す。循環(既訪問 run_id に再到達)は内部エラー(終了コード 6、`error: lineage cycle detected run_id=...`)
  3. 子孫: 幅優先で `SELECT ... WHERE parent_run_id = ?` を繰り返す(同じ元から role 違いで複数の子があり得る)
  4. role 導出: parent_run_id 空 → `-`、`slot_executions(run_id)` に行があればその slot、無ければ `rapid_crosscheck_requests(run_id)` があれば `rapid-crosscheck`、いずれも無ければ `-`
  5. depth を元の実行 = 0 で計算し、depth 降順 → requested_at 昇順でソート
  6. 行数が `--limit` を超えたら先頭 limit 行 + `warn: output truncated limit=N`
- **エラーハンドリング**: DB 障害は 6。エラーは 1 回だけ出す
- **クラッシュ耐性**: 書き込み無し。再実行でそのままやり直す
- **実行ログ**: `RELAY_GATE_LOG_DIR/run-lineage.sh.log` に `run-lineage.sh {run_id} {UTC} INFO lineage queried rows=N root_run_id=...`。ログ行形式は `_cross-cutting/ux-ui/ui-design.md` の `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従い、情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する

## データモデル変更

### parallel_runs(読み取りのみ)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK | 追加 |
| parent_run_id | string | リラン元 run_id(NULL = 元の実行) | 追加 |
| job_id | string | JOB_ID | 追加 |
| status | string | STARTED / RUNNING / COMPLETED / ABORTED | 追加 |
| requested_at | datetime | 作成日時 | 追加 |
| completed_at | datetime | 終了日時(NULL 可) | 追加 |
| execution_spec_uri | string | 成果物の execution-spec.json(`--verbose` の artifact_dir 導出に使わず run_id から導出する) | 追加 |

### slot_executions(読み取りのみ)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK 1 | 追加 |
| slot | string | PK 2。role 導出に使う | 追加 |

### rapid_crosscheck_requests(読み取りのみ)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | string | PK。role=rapid-crosscheck の導出に使う | 追加 |

## ビジネスルール

- 最新の run_id から parent_run_id を辿ると元の実行まで数珠つなぎに追跡できる(条件「リラン系譜の追跡」)
- 実行履歴・監査の正本はジョブスケジューラ。relay-gate は parallel_runs と成果物・実行ログの範囲で追跡を補助する(条件「実行履歴はジョブスケジューラの責務」)
- RAPID_CROSSCHECK_MODE=off では parallel_runs が作成されないため追跡できない(条件「速報クロスチェック有効判定」)
- 系譜の深さで打ち切らない(ui-design.md「ページング / 件数制限」)

## ティア完了条件(BDD)

```gherkin
Feature: リラン結果を parent_run_id で追跡する - 実行監視・復旧ティア

  Scenario: 元の実行を指定しても子孫を含めて出す
    Given parallel_runs に run_id=20260830T113000Z-JOB001-3f9a1c2e(parent_run_id NULL)と、それを親に持つ run_id=20260830T124500Z-JOB001-7b2d9e01 がある
    When `run-lineage.sh --run-id 20260830T113000Z-JOB001-3f9a1c2e` を実行する
    Then 終了コード 0 で stdout のデータ行は 2 行、1 行目の depth が 1、2 行目の depth が 0 である

  Scenario: 同じ元から role 違いで 2 回リランした場合は同 depth に 2 行出る
    Given parallel_runs に元の実行 R0 と、R0 を親に持つ R1(requested_at=2026-08-30T12:45:00Z, slot_executions green)と R2(requested_at=2026-08-30T13:00:00Z, rapid_crosscheck_requests のみ)がある
    When `run-lineage.sh --run-id R0 の run_id` を実行する
    Then depth 1 の行が requested_at 昇順で R1(role=green)、R2(role=rapid-crosscheck)の順に出る

  Scenario: --limit を超えると打ち切り警告を出す
    Given 系譜に 5 run がある
    When `run-lineage.sh --run-id {最新の run_id} --limit 3` を実行する
    Then 終了コード 0 で stdout のデータ行は 3 行、stderr に `warn: output truncated limit=3` が出る

  Scenario: --run-id 形式不正は終了コード 2
    When `run-lineage.sh --run-id abc` を実行する
    Then 終了コード 2 で stderr に `error: invalid value option=--run-id value=abc` が出る
```
