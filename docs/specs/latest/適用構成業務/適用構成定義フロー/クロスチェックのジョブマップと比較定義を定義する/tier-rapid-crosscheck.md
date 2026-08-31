# クロスチェックのジョブマップと比較定義を定義する - 速報クロスチェックティア仕様

## 変更概要

クロスチェックジョブマップ(速報の比較定義 TSV)の設定契約と、`validate-config.sh --crosscheck-job-map <path>` の検証ロジックを定義する。validate-config.sh(tier-facade 定義。UC「feature flag を設定する」)のオプション `--crosscheck-job-map <path>`(値必須)を利用する(契約では uses)。本体は tier-facade が所有し、`--crosscheck-job-map` サブ検証の関数 `validate_crosscheck_job_map` を本 tier が提供する(bash の source で直接依存。CLP-003)。RDB には触れない。

## コマンド契約

### validate-config.sh --crosscheck-job-map

- **書式**: `validate-config.sh --crosscheck-job-map <path> [--verbose] [--help]`
- **アクセス権**: 基盤適用設計者の直接起動。設定ファイルの読み取り権限のみ必要

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| `--crosscheck-job-map` | string(path) | Yes(値必須) | — | 検証するクロスチェックジョブマップのパス。既定パス `$RELAY_GATE_CONFIG_DIR/crosscheck-job-map.tsv` を使う場合も明示的に渡す(契約 validate-config.sh options。値省略は `error: option required option=--crosscheck-job-map` で 2) |
| `--verbose` | boolean | No | false | 行ごとの `info: checked job_id=...` を stderr に出す |

- **stdin**: なし

## 出力契約

- **stdout**(順序固定): `config=crosscheck-job-map` / `path: <絶対パス>` / `rows=N` / `target_catalog_path: <パス>` / `catalog_version=` / `exit_code_contract=0:OK,3:NG,6:ERROR` / `status=valid`(違反ありのときは `status=invalid` と `violations=N`)
- **stderr**: 違反ごとに 1 行 `error: {原因} key=value... line=N`(共通形式は契約 `validate-config.sh` の stderr。ファイル不在 `path: ...`、ヘッダー不一致 `expected= actual= path:`、列数不一致 `line= expected= actual=`、重複 `lines=<n1,n2,...>`、宣言不正 `declaration not found / is invalid`)。最後に `hint: fix the rows above and rerun validate-config.sh --crosscheck-job-map <path>`
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 0 | 成功 | 違反 0 件 |
  | 2 | 入力・設定検証エラー | ファイル不在・読み取り不可、ヘッダー不一致、行の違反 1 件以上、未知のオプション |

## 設定契約

### クロスチェックジョブマップ(TSV、ヘッダー行あり。`_inference.md` #5 仮採用)

ファイル: `$RELAY_GATE_CONFIG_DIR/crosscheck-job-map.tsv`。`#` で始まる行はコメント。先頭のコメント行にファイル全体の宣言を置く。

| 宣言(コメント行) | 必須 | 説明 |
|---|---|---|
| `# exit_code_contract=0:OK,3:NG,6:ERROR` | Yes | 比較ツール終了コード契約への適合宣言。値は固定文字列 |
| `# target_catalog_path=<path>` | Yes | 確報用の対象カタログ TSV の所在(設定所有区分: 対象カタログ参照) |
| `# catalog_version=<ver>` | Yes | 参照する対象カタログの版 |
| `# map_version=<ver>` | No | マップ版(記録用) |

| 列 | 型 | 必須 | 検証ルール |
|---|---|---|---|
| job_id | string | Yes | 英数字・`_`・`-`。ファイル内で一意 |
| comparison_type | enum | Yes | `job`(速報。comparison_results.comparison_type に転記)または `full`(確報。予約 job_id 行のみ) |
| compare_targets | string | Yes | 非空。比較対象(テーブル・ファイル)の識別子。カンマ区切り可 |
| compare_command | string(path) | Yes | 絶対パス。存在し実行権限がある |
| compare_options | string | Yes | comparison_type=job の行は `{blue}` と `{green}` の両プレースホルダを含む(成果物 URI に置換される)。full 行は下記。空白区切り |
| definition_version | string | Yes | 非空 |

#### 予約 job_id `final-crosscheck`(確報用。任意・最大 1 行。canonical C5)

確報 worker(`final-crosscheck-worker.sh`)が起動する比較コマンドは、本ファイルの `job_id=final-crosscheck` / `comparison_type=full` の行で定義する。対象カタログはヘッダーコメント `# target_catalog_path=` / `# catalog_version=` で参照する。

| 列 | full 行の値 | 検証ルール |
|---|---|---|
| job_id | `final-crosscheck`(固定。業務ジョブの job_id と衝突しないよう予約) | 最大 1 行 |
| comparison_type | `full` | `full` 以外は違反。逆に job_id が `final-crosscheck` 以外で `full` も違反 |
| compare_targets | `catalog`(固定。対象はカタログが決める) | 非空 |
| compare_command | 確報比較ツールの絶対パス | 存在 + 実行権限 |
| compare_options | `{catalog_path}` `{catalog_version}` `{business_date}` のプレースホルダ(仮採用: 確報比較ツールへの引数の渡し方は方針資料に定めが無いため)。置換先: `{catalog_path}` は確報 worker が `# target_catalog_path=` のカタログから該当版(catalog_version)の行だけを抜き出した `facade/<final_crosscheck_id>/final-crosscheck/input/target-catalog.tsv` の絶対パス(全版の元カタログではない。契約 `cli-command-contract.yaml` external_interfaces の確報比較ツール launch が正)、`{catalog_version}` は runner の `--catalog-version`(未指定なら `# catalog_version=`)、`{business_date}` は runner の `--business-date` | `{catalog_version}` と `{business_date}` を含む(`{catalog_path}` は任意) |
| definition_version | string | 非空 |

例: `final-crosscheck	full	catalog	/opt/compare/compare-full.sh	--catalog {catalog_path} --catalog-version {catalog_version} --business-date {business_date}	v1`

### 検証ルール一覧

| # | ルール | 違反メッセージ |
|---|---|---|
| 1 | ファイルが存在し読める | `error: config file not found path: ...` |
| 2 | ヘッダー行が列定義と完全一致(順序含む) | `error: header mismatch expected=job_id,comparison_type,... actual=... path: ...` |
| 3 | 各行の列数が 6 | `error: column count mismatch line=N expected=6 actual=<n>` |
| 4 | job_id 一意 | `error: duplicate job_id job_id=... lines=<n1,n2,...>` |
| 5 | job_id 形式 | `error: job_id is invalid line=N job_id=... value=...` |
| 6 | compare_command が実行可能 | `error: compare_command is not executable line=N job_id=... value=...` |
| 7 | comparison_type=job の行: compare_options に `{blue}` `{green}` | `error: compare_options is missing {blue} or {green} line=N job_id=... value=...` |
| 7a | comparison_type=full の行: job_id が `final-crosscheck`、最大 1 行、compare_options に `{catalog_version}` `{business_date}` | `error: job_id is not final-crosscheck for comparison_type=full line=N job_id=... value=...` / `error: duplicate job_id job_id=final-crosscheck lines=<n1,n2,...>` / `error: compare_options is missing {catalog_version} or {business_date} line=N job_id=final-crosscheck value=...` |
| 7b | comparison_type は `job` または `full` | `error: comparison_type is not in job,full line=N job_id=... value=...` |
| 8 | `exit_code_contract` 宣言が `0:OK,3:NG,6:ERROR` | `error: exit_code_contract declaration not found path: ...` |
| 9 | `target_catalog_path` が存在し、そのカタログに `catalog_version` の行がある(対象カタログの列検証は tier-final-crosscheck に委ね、本ルールは参照解決のみ) | `error: target catalog reference unresolved path=... catalog_version=...` |
| 10 | 値にタブ・改行を含まない、必須列が非空 | `error: <column> is empty line=N job_id=... value=` |

## UC ロジック

- **バリデーション**: 上表。違反は全件収集してから出力する(1 件目で止めない)
- **確認プロンプト**: なし
- **冪等性**: 参照のみ。何度実行しても同じ結果
- **エラーハンドリング**: 違反は stderr に 1 行ずつ、終了コード 2。ファイル I/O 以外の実行エラーは想定しない(発生時は 6)
- **クラッシュ耐性**: 書き込みを行わない。途中終了で残る副作用は無い
- **速報と確報のモデル分離**: 本検証は速報の比較定義を対象にし、対象カタログの内容検証は tier-final-crosscheck が行う
- **実行時の利用**: worker(UC「比較ツールでジョブ単位比較を実行して結果を登録する」)は検証済みの前提で job_id 行を読む。設定変更は次回以降の依頼から反映される(実行中の依頼には影響しない)

## データモデル変更

該当なし(RDB に触れない)。

### 設定ファイル

| ファイル | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| `$RELAY_GATE_CONFIG_DIR/crosscheck-job-map.tsv` | TSV | 上記「設定契約」 | 追加 |

## ビジネスルール

- 設定所有区分: 比較対象と対象カタログ参照はクロスチェックジョブマップが所有する
- 比較定義の選択: job_id ごとに比較定義を差し替えられる
- 比較ツール終了コードの対応: 比較ツールは 0 / 3 / 6 の契約に従う。relay-gate は値を変換しない
- 適用側で定義する事項: 外部 IF 方針・ネットワーク制約・ホスト配置は適用文書に置き、本ファイルには書かない
- 中立表現(CTR-004): サンプルに特定案件の固有名を書かない

## ティア完了条件(BDD)

```gherkin
Feature: クロスチェックのジョブマップと比較定義を定義する - 速報クロスチェックティア

  Scenario: 妥当なジョブマップを検証する
    Given /etc/relay-gate/crosscheck-job-map.tsv が宣言 3 行 + ヘッダー + JOB001 / JOB002 の 2 行で構成され、compare_command が実行可能である
    When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.tsv` を実行する
    Then 終了コード 0 で stdout に `config=crosscheck-job-map`、`rows=2`、`status=valid` が出る

  Scenario: exit_code_contract 宣言が無い
    Given crosscheck-job-map.tsv に `# exit_code_contract=` の行が無い
    When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.tsv` を実行する
    Then 終了コード 2 で stderr に `error: exit_code_contract declaration not found path: /etc/relay-gate/crosscheck-job-map.tsv` が出る

  Scenario: compare_options にプレースホルダが無い
    Given JOB001 行の compare_options が `--fast` である
    When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.tsv` を実行する
    Then 終了コード 2 で stderr に `error: compare_options is missing {blue} or {green} line=5 job_id=JOB001 value=--blue {blue}` が出る

  Scenario: 複数の違反を全件出力する
    Given JOB001 行の compare_command が存在せず、JOB002 行の列数が 5 である
    When `validate-config.sh --crosscheck-job-map /etc/relay-gate/crosscheck-job-map.tsv` を実行する
    Then 終了コード 2 で stderr に error 行が 2 行出て、stdout に `status=invalid` と `violations=2` が出る
```
