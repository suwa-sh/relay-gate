# hang_detect_limit_minutes をジョブごとに調整する - facade / slot runner ティア仕様

## 変更概要

このティアに新しいコマンドは追加しない。slot ジョブマップ CSV の `hang_detect_limit_minutes` 列を運用者が更新する手順と、その値が **次回以降の run の execution-spec.json にのみ反映される**契約(実行済み run に影響しない)を定義する。管理 DB は触らない。調整の記録(調整日時・調整根拠)はジョブマップに持たず適用構成文書に残す。

## コマンド契約

### validate-config.sh --job-map(他 UC「slot ごとのジョブマップを定義する」の契約を使う)

- **書式**: `validate-config.sh --job-map <path>`
- **アクセス権**: 運用者 / 基盤適用設計者の直接起動
- 本 UC では編集後のジョブマップ検証に使う(`hang_detect_limit_minutes` は 0 以上の整数。空欄・負数・非整数は終了コード 2)

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--job-map` | string(パス) | Yes | なし | 検証する slot ジョブマップ CSV |

- **stdin**: なし

## 出力契約

- **stdout**: 検証 OK 時 `map_path: {path}` / `rows={N}` / `map_version={版}`(任意列 `map_version` が無ければ `map_version=-`)の 3 行(他 UC「slot ごとのジョブマップを定義する」の契約に従う。`impl_version` は出さない: 実装版はジョブマップではなく feature flag の BLUE_IMPL / GREEN_IMPL が所有する)
- **stderr**: `error: hang_detect_limit_minutes is not a non-negative integer line=N job_id=JOB001 value=abc`(他 UC「slot ごとのジョブマップを定義する」の列検証メッセージ。契約 `error: <column> is <reason> line=N job_id=... value=...`)等
- **終了コード**: 0(検証 OK)/ 2(検証 NG。ファイル不在・読み取り不可は `error: config file not found path: ...` / `error: config file is not readable path: ...` で同じく 2。契約 validate-config.sh exit_codes)

## 設定契約(slot ジョブマップの `hang_detect_limit_minutes` 列)

slot ジョブマップ(CSV、1 行目ヘッダー、1 行 1 job_id。列はヘッダー名で対応付ける。RDRA 情報「ジョブマップ」/ 条件「ジョブマップ解決条件」):

`job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes[,credential_ref][,map_version]`

| 列 | 型 | 検証ルール | 本 UC での扱い |
|---|---|---|---|
| `hang_detect_limit_minutes` | integer(0 以上) | 必須列。空欄・負数・非整数は NG。0 は「検知対象外」 | 運用者が job_id 行ごとに編集する。導入時は全行 60。foreground slot のジョブマップは 0 |
| `map_version` | string | 末尾の任意列(ヘッダーに無ければ無いものとして扱う。値が空も可) | 列を置いている場合は上限を変更したら版を進める(execution-spec.json の `map_version` で「どの版の上限で run が動いたか」を追跡できる。列が無ければ execution-spec.json の `map_version` は `null`) |

- 調整日時・調整根拠の列は置かない(未知列は `warn: unknown column column=<name> path: ...`)。調整の記録は適用構成文書に残す

### 更新手順

1. `hang-detect-trend.sh --job-id {JOB_ID}`(tier-ops)で `last_elapsed_minutes_at_alert` を確認する
2. 該当 slot(background 側)のジョブマップ CSV の `{JOB_ID}` 行の `hang_detect_limit_minutes` を編集し、`map_version` 列があれば版を進める
3. `validate-config.sh --job-map {path}` で終了コード 0 を確認する
4. 調整日時と調整根拠(手順 1 の `last_elapsed_minutes_at_alert`)を適用構成文書の「運用者の調整記録」に残す(文書またはそのコミット履歴)
5. 反映は次回の `facade.sh {JOB_ID}` 起動から。RUNNING 中・実行済みの run には影響しない

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
| hang_detect_limit_minutes | integer | job_id × slot の判定上限(分)。0 = 検知対象外(必須列) | 追加 |
| map_version | string | マップ版(末尾の任意列) | 追加 |

### execution-spec.json(ファイル)

| キー | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| hang_detect_limit_minutes(role ごと) | integer | run 開始時に解決した上限。以後不変 | 追加 |
| map_version | string / null | 解決に使ったジョブマップの版(任意列が無ければ null) | 追加 |

### 適用構成文書(文書。relay-gate は読まない)

| 項目 | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| 運用者の調整記録 | 文書記載 | hang_detect_limit_minutes の調整日時、調整根拠となる警告時経過時間(文書またはそのコミット履歴) | 追加 |

## ビジネスルール

- 上限の正本は該当 slot のジョブマップ(条件「設定所有区分」)。RDB・execution-spec.json を直接編集しない。調整記録の正本は適用構成文書
- 導入時 60 分、foreground role は 0(条件「ハング検知上限の調整基準」「ハング検知対象の除外」)
- run 開始時に一度だけ execution-spec.json へ確定保存し、以後のジョブマップ変更は同じ run に影響しない(条件「実行設定の確定条件」)

## ティア完了条件(BDD)

```gherkin
Feature: hang_detect_limit_minutes をジョブごとに調整する - facade / slot runner ティア

  Scenario: 変更後の run にだけ新しい上限が記録される
    Given green slot ジョブマップ(CSV。ヘッダー job_id,host,user,work_dir,script,fixed_params,hang_detect_limit_minutes,map_version)の JOB001 行の hang_detect_limit_minutes が 60 で run_id=20260829T020000-JOB001-9c0d1e2f の execution-spec.json に 60 が記録されている
    And 運用者が同行を 90 に編集し map_version を v2 にして `validate-config.sh --job-map /etc/relay-gate/green-job-map.csv` が終了コード 0 で stdout に `map_version=v2` を出す
    When `facade.sh JOB001` を BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=background で実行する
    Then 新しい run の execution-spec.json の green の hang_detect_limit_minutes は 90、map_version は v2 である
    And 20260829T020000-JOB001-9c0d1e2f の execution-spec.json は変更されていない

  Scenario: foreground slot の上限 0 が execution-spec.json に記録される
    Given blue slot ジョブマップの JOB001 行の hang_detect_limit_minutes が 0 である
    When `facade.sh JOB001` を BLUE_MODE=foreground GREEN_MODE=background で実行する
    Then execution-spec.json の blue の hang_detect_limit_minutes は 0 である

  Scenario: 不正な上限値はジョブマップ検証で拒否される
    Given green slot ジョブマップの JOB001 行の hang_detect_limit_minutes を abc に編集した
    When `validate-config.sh --job-map /etc/relay-gate/green-job-map.csv` を実行する
    Then 終了コード 2 で stderr に `error: hang_detect_limit_minutes is not a non-negative integer line=2 job_id=JOB001 value=abc` が出る
```
