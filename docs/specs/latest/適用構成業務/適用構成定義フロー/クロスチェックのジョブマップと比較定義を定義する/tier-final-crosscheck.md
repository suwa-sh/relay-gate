# クロスチェックのジョブマップと比較定義を定義する - 確報クロスチェックティア仕様

## 変更概要

対象カタログ(確報用 TSV)の設定契約と、`validate-config.sh --target-catalog <path>` の検証ロジック `validate_target_catalog` を定義する(validate-config.sh(tier-facade 定義。UC「feature flag を設定する」)のオプション `--target-catalog <path>`(値必須)を利用する。契約では uses。本 tier は関数を提供)。RDB には触れない。確報 runner / worker(確報クロスチェックフローの UC)は検証済みのカタログを `--catalog-version` で参照する。

## コマンド契約

### validate-config.sh --target-catalog

- **書式**: `validate-config.sh --target-catalog <path> [--verbose] [--help]`
- **アクセス権**: 基盤適用設計者の直接起動

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--target-catalog` | string(path) | Yes(値必須) | — | 検証する対象カタログのパス。既定パス `$RELAY_GATE_CONFIG_DIR/target-catalog.tsv` を使う場合も明示的に渡す(契約 validate-config.sh options。値省略は `error: option required option=--target-catalog` で 2) |
| `--verbose` | boolean | No | false | 行ごとの `info: checked target_identifier=...` |

- **stdin**: なし

## 出力契約

- **stdout**(順序固定): `config=target-catalog` / `path: <絶対パス>` / `rows=N` / `catalog_versions=v1,v2` / `tables=N` / `files=N` / `status=valid`(違反時 `status=invalid` / `violations=N`)
- **stderr**: 違反ごとに `error: ... line=N`(共通形式は契約 `validate-config.sh` の stderr。ファイル不在 `path: ...`、ヘッダー不一致 `expected= actual= path:`、列数不一致 `line= expected= actual=`、重複 `lines=<n1,n2,...>`)、最後に `hint: fix the rows above and rerun validate-config.sh --target-catalog <path>`
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 違反 0 件 |
  | 2 | 入力・設定検証エラー | ファイル不在、ヘッダー不一致、行の違反 1 件以上、未知のオプション |

## 設定契約

### 対象カタログ(TSV、ヘッダー行あり。`_inference.md` #5 仮採用)

ファイル: `$RELAY_GATE_CONFIG_DIR/target-catalog.tsv`。`#` で始まる行はコメント。複数の版を同一ファイルに持てる(catalog_version 列で区別)。

| 列 | 型 | 必須 | 検証ルール |
|---|---|---|---|
| catalog_version | string | Yes | 非空。英数字・`.`・`_`・`-` |
| target_type | enum | Yes | `table` または `file` |
| target_identifier | string | Yes | 非空。同一 catalog_version 内で target_type + target_identifier が一意 |
| compare_condition | string | No | 比較条件(例: `key=sales_id`)。無ければ `-` |
| business_date_handling | string | No | business_date の扱い(例: `column=business_date` / `filename` / `none`)。無ければ `-` |

### 検証ルール一覧

| # | ルール | 違反メッセージ |
|---|---|---|
| 1 | ファイルが存在し読める | `error: config file not found path: ...` |
| 2 | ヘッダー行が列定義と完全一致 | `error: header mismatch expected=catalog_version,target_type,... actual=... path: ...` |
| 3 | 各行の列数が 5 | `error: column count mismatch line=N expected=5 actual=<n>` |
| 4 | target_type が table / file | `error: target_type is not in table,file line=N value=...`(対象カタログは job_id 列を持たないため `job_id=` は付けない) |
| 5 | (catalog_version, target_type, target_identifier)が一意 | `error: duplicate target catalog_version=... target_type=... target_identifier=... lines=<n1,n2,...>` |
| 6 | 各 catalog_version に 1 行以上 | (集計上自明。違反なし) |
| 7 | 必須列が非空、タブ・改行を含まない | `error: <column> is empty line=N value=` |

## UC ロジック

- **バリデーション**: 上表。違反は全件収集
- **確認プロンプト**: なし
- **冪等性**: 参照のみ
- **エラーハンドリング**: 違反は stderr 1 行ずつ、終了コード 2
- **クラッシュ耐性**: 書き込みなし
- **速報と確報のモデル分離**: 対象カタログは確報のみが使う。速報の比較定義とは別ファイルで、rapid_* / final_* のいずれにも触れない
- **実行時の利用**: `final-crosscheck-runner.sh --catalog-version <ver>` が依頼に版を紐付け、worker がその版の行で全量比較を起動する(確報フローの UC)。版を追加する運用(v1 を残して v2 を追加)を想定し、既存版の行は変更しない
- **プレースホルダの置換先(確報 worker)**: `{catalog_path}` → 該当版の行だけを抜き出した `facade/<final_crosscheck_id>/final-crosscheck/input/target-catalog.tsv` の絶対パス(本ファイル全体ではない)、`{catalog_version}` → 依頼の catalog_version、`{business_date}` → 依頼の business_date。定義は tier-rapid-crosscheck.md「予約 job_id `final-crosscheck`」と契約 `cli-command-contract.yaml` external_interfaces が正

## データモデル変更

該当なし(RDB に触れない)。

### 設定ファイル

| ファイル | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| `$RELAY_GATE_CONFIG_DIR/target-catalog.tsv` | TSV | 上記「設定契約」 | 追加 |

## ビジネスルール

- 設定所有区分: 対象カタログはクロスチェックジョブマップ(適用側)が所有する
- 適用側で定義する事項: 比較対象と対象カタログは適用側が版管理して定義する
- 比較ツール終了コードの対応: 確報 worker が起動する比較ツールも 0 / 3 / 6 の契約に従う(宣言は crosscheck-job-map.tsv 側で行う)
- 確報の比較コマンドの所在(canonical C5): 確報 worker は crosscheck-job-map.tsv の `job_id=final-crosscheck` / `comparison_type=full` 行の compare_command / compare_options を使う。対象カタログはそのファイルのヘッダーコメント `# target_catalog_path=` / `# catalog_version=` で参照する。列定義と検証は tier-rapid-crosscheck.md「予約 job_id `final-crosscheck`」を正とする
- 中立表現(CTR-004): サンプルに特定案件の固有名を書かない

## ティア完了条件(BDD)

```gherkin
Feature: クロスチェックのジョブマップと比較定義を定義する - 確報クロスチェックティア

  Scenario: 妥当な対象カタログを検証する
    Given /etc/relay-gate/target-catalog.tsv がヘッダー + `v1	table	SALES_DAILY	key=sales_id	column=business_date` + `v1	file	/data/out/summary_{business_date}.tsv	-	filename` の 2 行である
    When `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.tsv` を実行する
    Then 終了コード 0 で stdout に `rows=2`、`catalog_versions=v1`、`tables=1`、`files=1`、`status=valid` が出る

  Scenario: 版を追加しても既存版は検証を通る
    Given 上記に `v2	table	SALES_DAILY	key=sales_id	column=business_date` を追加する
    When `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.tsv` を実行する
    Then 終了コード 0 で stdout に `catalog_versions=v1,v2` が出る

  Scenario: target_type が不正
    Given 3 行目の target_type が `view` である
    When `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.tsv` を実行する
    Then 終了コード 2 で stderr に `error: target_type is not in table,file line=3 value=view` が出る

  Scenario: 同一版内で対象が重複
    Given `v1	table	SALES_DAILY` の行が 2 行ある
    When `validate-config.sh --target-catalog /etc/relay-gate/target-catalog.tsv` を実行する
    Then 終了コード 2 で stderr に `error: duplicate target catalog_version=v1 target_type=table target_identifier=SALES_DAILY lines=3` が出る
```
