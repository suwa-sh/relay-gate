# 業務ジョブの実行結果を確認する - facade / slot runner ティア仕様

## 変更概要

新規のコードは無い。本ファイルは運用者が読む **facade 応答の契約**(応答に含まれるもの・含まれないもの、運用モード別の見え方)を定義する。実装は UC「foreground slot の結果をジョブスケジューラへ中継する」。

## コマンド契約

### facade.sh(応答の受け手から見た契約)

- **書式**: `facade.sh JOB_ID [PARAM...]`
- **アクセス権**: ジョブスケジューラの業務ジョブ定義。運用者はジョブスケジューラの実行履歴で結果を読む

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| JOB_ID | string | Yes | なし | 実行履歴上のジョブ識別 |
| PARAM... | string[] | No | なし | 実装へ渡された追加引数(応答には現れない) |

- **stdin**: なし

## 出力契約

### 応答に含まれるもの

| チャネル | 内容 | 出典 |
|---|---|---|
| 標準出力 | foreground 実装の標準出力そのまま | `facade/<run_id>/<fg_role>/stdout.log` |
| 標準エラー | foreground 実装の標準エラーそのまま | `facade/<run_id>/<fg_role>/stderr.log` |
| 終了コード | foreground 実装の終了コードそのまま | `facade/<run_id>/<fg_role>/exitcode.txt` |

### 応答に含まれないもの

| 含まれないもの | 確認手段 |
|---|---|
| background slot の stdout / stderr / 終了コード | `facade/<run_id>/<bg_role>/` の 3 ファイル、hang-detector の error メール(`background-exec-error`) |
| 速報クロスチェックの状態・比較結果・exitcode | `rapid-crosscheck-result.sh --run-id <run_id>`、hang-detector の error メール(`rapid-crosscheck-error`) |
| run_id | 実行ログ `facade.sh.log`(JOB_ID と起動時刻で検索)。応答には出さない(無加工中継のため) |
| 並行稼働実行の状態(STARTED / RUNNING / COMPLETED) | 管理 DB `parallel_runs`(on のとき)、`run-lineage.sh --run-id` |
| relay-gate の info / warn | 実行ログ |
| 確報クロスチェックの結果 | 確報ジョブの実行履歴(UC「確報クロスチェック結果を確認する」) |

- **実行ログの行形式**: `_cross-cutting/ux-ui/ui-design.md` のログ行形式 `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従う。情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する

### 運用モード別の見え方

| 運用モード | 応答元 slot | 応答に現れない実行 | ジョブスケジューラの見え方 |
|---|---|---|---|
| 並行稼働(blue foreground / green background / 速報 on) | blue | green、速報 | 従来の現行実装の結果と同じ |
| 新実装の単独本番(blue off / green foreground / 速報 off) | green | なし | 新実装の結果。管理 DB 不要 |
| 次世代実装との並行稼働(blue background / green foreground / 速報 on) | green | blue、速報 | 新実装の結果 |

- **終了コード**:

| コード | 意味 | 条件 |
|-------|------|------|
| 実装の終了コード(0〜255) | foreground 実装の結果 | 正常な中継。0 = 成功、非 0 = 失敗(意味は実装側の契約) |
| 2 | relay-gate の設定・引数検証エラー | 実装は起動していない(両 slot foreground / foreground 無し / runner 実体なし等)。stderr の `error:` を読む(UC「slot 実行モードを選択して runner を起動する」) |
| 6 | relay-gate の実行エラー | 管理 DB 失敗・runner 起動失敗・Runner Result 未完備。実装が動いた可能性があるので成果物ディレクトリを確認する |

- 運用者の読み分け: 終了コード 2 / 6 かつ標準エラーが `error:` で始まる場合は relay-gate 側の異常。それ以外は実装側の結果(実装が 2 / 6 を返す可能性もあるため、標準エラーの先頭で区別する。仮採用)

## UC ロジック

- **バリデーション**: なし(読む UC)
- **確認プロンプト**: なし
- **冪等性**: 確認は何度でも可能。ジョブスケジューラの実行履歴が正本
- **エラーハンドリング**: 運用者の判断
  - 終了コード非 0(実装側): foreground の再実行はジョブスケジューラの正規ジョブ(条件: 復旧手段の選択)
  - relay-gate 側の 2: 設定を修正(validate-config.sh で検証)して正規ジョブを再実行
  - relay-gate 側の 6: 成果物ディレクトリと実行ログを確認してから再実行

## 設定契約

該当なし。

## データモデル変更

該当なし(`tables: []`)。

## ビジネスルール

- 応答は foreground の 3 ファイルだけ。background と速報は反映しない(条件: ジョブスケジューラ応答の決定)
- 速報の結果は原因調査用、リリース判断は確報(条件: 速報結果の位置付け)
- 実行履歴・監査はジョブスケジューラの責務。relay-gate は成果物と実行ログを残すだけ(条件: 実行履歴はジョブスケジューラの責務)

## ティア完了条件(BDD)

```gherkin
Feature: 業務ジョブの実行結果を確認する - facade / slot runner ティア

  Scenario: facade_sh の応答は foreground の 3 ファイル以外を含まない
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off がある
    And スタブ runner は blue/stdout.log に "blue ok"、green/stdout.log に "green ok" を書き、両 slot とも stderr.log(空)と exitcode.txt に 0 を書く
    When `facade.sh JOB001` を実行する
    Then stdout は "blue ok" のみで、"green ok" と "run_id" と "info:" を含まない

  Scenario: facade_sh の応答は運用モードを切り替えても同じ 3 チャネルである
    Given feature-flag.env を BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off に変更した
    And スタブ runner は green/stdout.log に "green ok"、stderr.log(空)、exitcode.txt に 0 を書く
    When `facade.sh JOB001` を実行する
    Then stdout は "green ok"、stderr は空、終了コードは 0 である

  Scenario: facade_sh の relay-gate 側エラーは stderr が error: で始まる
    Given feature-flag.env に BLUE_MODE=foreground GREEN_MODE=foreground がある
    When `facade.sh JOB001` を実行する
    Then 終了コード 2 で stderr の 1 行目は "error: " で始まる
```
