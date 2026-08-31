# hang_detect_limit_minutes をジョブごとに調整する - facade / slot runner ティア仕様

## 変更概要

このティアに新しいコマンドは追加しない。slot ジョブマップ TSV の `hang_detect_limit_minutes` 列を運用者が更新する手順と、その値が **次回以降の run の execution-spec.json にのみ反映される**契約(実行済み run に影響しない)を定義する。管理 DB は触らない。

## コマンド契約

### validate-config.sh --job-map(他 UC「slot ごとのジョブマップを定義する」の契約を使う)

- **書式**: `validate-config.sh --job-map <path>`
- **アクセス権**: 運用者 / 基盤適用設計者の直接起動
- 本 UC では編集後のジョブマップ検証に使う(`hang_detect_limit_minutes` は 0 以上の整数。空欄・負数・非整数は終了コード 2)

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--job-map` | string(パス) | Yes | なし | 検証する slot ジョブマップ TSV |

- **stdin**: なし

## 出力契約

- **stdout**: 検証 OK 時 `map_path: {path}` / `rows={N}` / `map_version={版}` / `impl_version={版}` の 4 行(他 UC「slot ごとのジョブマップを定義する」の契約に従う)
- **stderr**: `error: hang_detect_limit_minutes is not a non-negative integer line=N job_id=JOB001 value=abc`(他 UC「slot ごとのジョブマップを定義する」の列検証メッセージ)等
- **終了コード**: 0(検証 OK)/ 2(検証 NG。ファイル不在・読み取り不可は `error: config file not found path: ...` / `error: config file is not readable path: ...` で同じく 2。契約 validate-config.sh exit_codes)

## 設定契約(slot ジョブマップの `hang_detect_limit_minutes` 列)

slot ジョブマップ(TSV、ヘッダー行あり。`_inference.md` 採用値 #5、仮採用):

`job_id	host	exec_user	script_path	work_dir	fixed_args_json	hang_detect_limit_minutes	credential_ref	map_version	impl_version`

| 列 | 型 | 検証ルール | 本 UC での扱い |
|---|---|---|---|
| `hang_detect_limit_minutes` | integer(0 以上) | 空欄・負数・非整数は NG。0 は「検知対象外」 | 運用者が job_id 行ごとに編集する。導入時は全行 60。foreground slot のジョブマップは 0 |
| `map_version` | string | 必須 | 上限を変更したら版を進める(execution-spec.json の `map_version` で「どの版の上限で run が動いたか」を追跡できる) |

### 更新手順

1. `hang-detect-trend.sh --job-id {JOB_ID}`(tier-ops)で `last_elapsed_minutes_at_alert` を確認する
2. 該当 slot(background 側)のジョブマップ TSV の `{JOB_ID}` 行の `hang_detect_limit_minutes` を編集し、`map_version` を進める
3. `validate-config.sh --job-map {path}` で終了コード 0 を確認する
4. 反映は次回の `facade.sh {JOB_ID}` 起動から。RUNNING 中・実行済みの run には影響しない

### 反映タイミングの契約

| 対象 | 上限の参照元 | ジョブマップ変更の影響 |
|---|---|---|
| 変更後に開始する run | 新しいジョブマップ → 新しい execution-spec.json | 反映される |
| 変更時点で RUNNING の run | その run の execution-spec.json(確定済み) | 影響しない(hang-detector は execution-spec.json の値で判定する) |
| 実行済み run | その run の execution-spec.json | 影響しない(上書き禁止。LP-006) |
| background-rerun で復元する run | 元 run の execution-spec.json をコピー | 影響しない(最新ジョブマップを再解決しない) |

## UC ロジック

- **バリデーション**: `validate-config.sh --job-map` に委ねる。slot runner はジョブマップ解決時にも同じ検証を行い、NG なら Runner Result を非 0 で出力する(他 UC)
- **確認プロンプト**: なし
- **冪等性**: ジョブマップの編集は運用者の手作業。同じ値で再編集しても run の挙動は変わらない
- **エラーハンドリング**: 検証 NG は終了コード 2 と `error:` 行。ジョブマップの不在・読み取り不可も 2(`error: config file is not readable path: ...`)
- **クラッシュ耐性**: 編集途中のジョブマップを slot runner が読むことを避けるため、一時ファイルへ書いて `mv` で置き換える運用とする(成果物公開判定と同じ規則。仮採用: RDRA に編集手順の定義が無いため運用ガイドに置く)

## データモデル変更

### slot ジョブマップ(ファイル。RDB テーブルではない)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| hang_detect_limit_minutes | integer | job_id × slot の判定上限(分)。0 = 検知対象外 | 追加 |
| map_version | string | マップ版 | 追加 |

### execution-spec.json(ファイル)

| キー | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| hang_detect_limit_minutes(role ごと) | integer | run 開始時に解決した上限。以後不変 | 追加 |
| map_version | string | 解決に使ったジョブマップの版 | 追加 |

## ビジネスルール

- 上限の正本は該当 slot のジョブマップ(条件「設定所有区分」)。RDB・execution-spec.json を直接編集しない
- 導入時 60 分、foreground role は 0(条件「ハング検知上限の調整基準」「ハング検知対象の除外」)
- run 開始時に一度だけ execution-spec.json へ確定保存し、以後のジョブマップ変更は同じ run に影響しない(条件「実行設定の確定条件」)

## ティア完了条件(BDD)

```gherkin
Feature: hang_detect_limit_minutes をジョブごとに調整する - facade / slot runner ティア

  Scenario: 変更後の run にだけ新しい上限が記録される
    Given green slot ジョブマップの JOB001 行の hang_detect_limit_minutes が 60 で run_id=20260829T020000Z-JOB001-9c0d1e2f の execution-spec.json に 60 が記録されている
    And 運用者が同行を 90 に編集し map_version を v2 にして `validate-config.sh --job-map /etc/relay-gate/green-job-map.tsv` が終了コード 0 で終わる
    When `facade.sh JOB001` を BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=on で実行する
    Then 新しい run の execution-spec.json の green の hang_detect_limit_minutes は 90、map_version は v2 である
    And 20260829T020000Z-JOB001-9c0d1e2f の execution-spec.json は変更されていない

  Scenario: foreground slot の上限 0 が execution-spec.json に記録される
    Given blue slot ジョブマップの JOB001 行の hang_detect_limit_minutes が 0 である
    When `facade.sh JOB001` を BLUE_MODE=foreground GREEN_MODE=background で実行する
    Then execution-spec.json の blue の hang_detect_limit_minutes は 0 である

  Scenario: 不正な上限値はジョブマップ検証で拒否される
    Given green slot ジョブマップの JOB001 行の hang_detect_limit_minutes を abc に編集した
    When `validate-config.sh --job-map /etc/relay-gate/green-job-map.tsv` を実行する
    Then 終了コード 2 で stderr に `error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=abc` が出る
```
