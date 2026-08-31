# 切り替えた運用モードで業務ジョブを実行する - facade / slot runner ティア仕様

## 変更概要

新規のコードは無い。本ファイルは運用者が読む **運用モード別の facade の振る舞いと見え方の契約** を定義する。実装は UC「slot 実行モードを選択して runner を起動する」「foreground slot の結果をジョブスケジューラへ中継する」。facade.sh の実行ログ `feature flag loaded` 行の `operation_mode=` は UC「slot 実行モードを選択して runner を起動する」(定義元)の tier-facade.md が定義し、本 UC はそれを読む(契約 `config_files.feature-flag.env.derived` の operation_mode は validate-config.sh と facade.sh 実行ログの両方に現れる)。

## コマンド契約

### facade.sh(運用モード別の振る舞い)

- **書式**: `facade.sh JOB_ID [PARAM...]`(運用モードによらず同一)
- **アクセス権**: ジョブスケジューラの業務ジョブ定義(運用モードによらず同一の定義)

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| JOB_ID | string | Yes | なし | 運用モードによらず同じ |
| PARAM... | string[] | No | なし | 運用モードによらず同じ |

- **stdin**: なし

#### 運用モード別の振る舞い

| 運用モード | feature flag | 起動順 | 待機 | 応答元 | 管理 DB | 完了通知 / 速報 | 通知メールの対象 |
|---|---|---|---|---|---|---|---|
| 並行稼働 | blue=foreground / green=background / rapid=on | green(bg)→ blue(fg) | blue | blue | parallel_runs / slot_executions / rapid_runs を作成 | 両 runner が送信。両系成功で速報比較依頼 | green の実行エラー・ハング疑い、速報の異常 |
| 新実装の単独本番 | blue=off / green=foreground / rapid=off | green(fg) | green | green | 接続しない | 送信しない | なし(hang-detector は成果物走査のみで対象無し) |
| 次世代実装との並行稼働 | blue=background / green=foreground / rapid=on | blue(bg)→ green(fg) | green | green | 作成 | 両 runner が送信 | blue の実行エラー・ハング疑い、速報の異常 |
| custom(表に無い有効な組合せ。例: blue=foreground / green=background / rapid=off) | — | background → foreground | foreground | foreground | rapid の値に従う | rapid の値に従う | background slot(hang-detector は off でも成果物を走査) |

- 世代交代(並行稼働 → 単独本番 → 次世代並行稼働)の切り替え単位は feature flag の変更のみ。次世代並行稼働への移行時は `BLUE_RUNNER` に旧 green の runner、`GREEN_RUNNER` に次世代の runner を割り当て、`blue-job-map.tsv` を旧 green のジョブマップから作る(UC「slot runner の実体スクリプトを割り当てる」「slot ごとのジョブマップを定義する」)

## 出力契約

- **stdout / stderr / 終了コード**: 運用モードによらず foreground slot の 3 ファイルを無加工中継(UC「foreground slot の結果をジョブスケジューラへ中継する」)。運用モードの違いは応答元 slot だけで、形式は同じ
- **実行ログ**(定義元: UC「slot 実行モードを選択して runner を起動する」): `feature flag loaded ... operation_mode=parallel`(起動のたび。値は parallel / green-only / next-parallel / custom)
- **実行ログの行形式**: `_cross-cutting/ux-ui/ui-design.md` のログ行形式 `{script} {run_id} {UTC 出力日時} {LEVEL} {message}` に従う。情報「実行ログ」の属性「出力日時」はこの UTC 時刻列に対応する
- **終了コード**:

| コード | 意味 | 条件 |
|-------|------|------|
| foreground の exitcode.txt の値 | 業務結果 | 運用モードによらず |
| 2 | 設定検証エラー | 誤った運用モード設定(両 foreground / foreground 無し等)。runner は起動しない |
| 6 | 実行エラー | 管理 DB(並行稼働系のみ)・runner 起動失敗 |

## UC ロジック

- **バリデーション**: facade は起動のたびに feature flag を検証する(UC「feature flag を設定する」の検証表と同じ関数)
- **確認プロンプト**: なし
- **冪等性**: 該当なし(読む UC)
- **エラーハンドリング**: 誤設定は業務ジョブを起動せずに終了コード 2。運用者はジョブスケジューラの実行結果で relay-gate 側の異常と判別できる(標準エラーが `error:` で始まる)
- **切り替えタイミング**: feature flag の変更は次回の facade 起動から有効。実行中の run(background slot を含む)は変更前の execution-spec.json で継続する。切り替え前に background slot の完了を待つかどうかは運用者の判断(hang-detector が監視を継続する)
- **クラッシュ耐性**: 該当なし

## 設定契約

feature flag(UC「feature flag を設定する」)、slot ジョブマップ(UC「slot ごとのジョブマップを定義する」)、runner 割当(UC「slot runner の実体スクリプトを割り当てる」)の契約に従う。本 UC が追加する設定は無い。

## データモデル変更

RDB テーブルは触らない(`tables: []`)。並行稼働系の運用モードでの parallel_runs 等の作成は UC「slot 実行モードを選択して runner を起動する」に含まれる。

## ビジネスルール

- foreground は同時に 1 slot(条件: foreground slot 排他)
- 運用モードの切り替えは feature flag の変更だけで行い、ジョブ定義と relay-gate のスクリプトは変更しない(条件: 設定所有区分)
- facade は設定された runner を起動するだけで、運用モードの意味を判断しない(条件: facade の責務限定)

## ティア完了条件(BDD)

```gherkin
Feature: 切り替えた運用モードで業務ジョブを実行する - facade / slot runner ティア

  Scenario: facade_sh は同じ引数で feature flag だけを変えると応答元 slot が変わる
    Given スタブ runner が blue/stdout.log に "blue"、green/stdout.log に "green" を書き exitcode.txt に 0 を書く
    And feature-flag.env が BLUE_MODE=foreground GREEN_MODE=background RAPID_CROSSCHECK_MODE=off である
    When `facade.sh JOB001` を実行する
    Then stdout は "blue" である
    When feature-flag.env を BLUE_MODE=off GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off に書き換えて `facade.sh JOB001` を実行する
    Then stdout は "green" であり、blue のスタブは起動されない

  Scenario: facade_sh は実行ログに operation_mode を記録する
    Given feature-flag.env が BLUE_MODE=background GREEN_MODE=foreground RAPID_CROSSCHECK_MODE=off である
    When `facade.sh JOB001` を実行する
    Then RELAY_GATE_LOG_DIR/facade.sh.log に "operation_mode=custom" を含む行が出る
    And feature-flag.env を RAPID_CROSSCHECK_MODE=on(管理 DB あり)にして実行すると "operation_mode=next-parallel" が出る

  Scenario: facade_sh は誤った運用モード設定で業務ジョブを起動しない
    Given feature-flag.env が BLUE_MODE=foreground GREEN_MODE=foreground である
    When `facade.sh JOB001` を実行する
    Then 終了コード 2 で、blue / green のスタブはどちらも起動されない
```
