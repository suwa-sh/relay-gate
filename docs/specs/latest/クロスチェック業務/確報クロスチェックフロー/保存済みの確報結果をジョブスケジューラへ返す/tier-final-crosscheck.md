# 保存済みの確報結果をジョブスケジューラへ返す - 確報クロスチェックティア仕様

## 変更概要

`final-crosscheck-runner.sh` の presentation 層に無加工中継(`relay_stored_result`)を追加する。UC「確報比較依頼を登録して終端状態まで待機する」の polling が終端状態を検知した直後に、同じプロセス内で依頼の `stdout` / `stderr` / `exit_code` を読み出し、標準出力・標準エラー・プロセス終了コードへそのまま流す。relay-gate の出力規約(0 / 2 / 3 / 6、`key=value`、`error:` 接頭辞)はこの経路に適用しない(ui-design.md「適用外(無加工中継)」)。

## コマンド契約

### final-crosscheck-runner.sh(中継部分)

- **書式**: `final-crosscheck-runner.sh --business-date <YYYY-MM-DD> --catalog-version <ver>`(引数契約は UC「確報比較依頼を登録して終端状態まで待機する」の tier md を正とする)
- **アクセス権**: ジョブスケジューラの確報クロスチェックジョブ定義

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| (追加なし) | — | — | — | 中継はオプションで制御しない。`--verbose` でも stdout / stderr に info を混ぜない |

- **stdin**: なし

## 出力契約

- **stdout**: 依頼の `stdout` 列の内容をバイト列のまま出す(NULL は 0 バイト)。末尾改行の追加・削除をしない。`key=value` 形式にしない
- **stderr**: 依頼の `stderr` 列の内容をバイト列のまま出す(NULL は 0 バイト)。exit_code が NULL(ABORTED で比較未完了)でも追加行は書かない(中継制約: 状態名や relay-gate 由来の行を混ぜない。理由は実行ログに `WARN relay without stored exit_code` として残す。仮採用)
- **終了コード**:
  | コード | 意味 | 条件 |
  |-------|------|------|
  | 保存済み exit_code | 無加工中継 | exit_code が NULL でない(0 / 3 / 6 / その他の非 0 をそのまま) |
  | 6 | 実行エラー | exit_code が NULL(ABORTED で比較未完了。仮採用)、または中継直前の SELECT 失敗 |

- 出力順: stdout を全量書き出してから stderr を書き出し、最後に `exit N`。パイプの都合で交互に混ざらないよう、それぞれ 1 回の書き込みで流す
- 実行ログ(`final-crosscheck-runner.sh.log`)には `INFO relay final_crosscheck_id=... status=... exit_code=... stdout_bytes=... stderr_bytes=...` を残す(stdout / stderr の本文はログに複写しない)
  - ログ行の形式は `_cross-cutting/ux-ui/ui-design.md` のログ行形式(`{script} {run_id} {UTC 出力日時} {LEVEL} {message}`。run_id 欄は final_crosscheck_id)に従う。情報「実行ログ」の属性「出力日時」はこの UTC 出力日時の列に対応する

## UC ロジック

- **バリデーション**: なし(引数検証は登録 UC で完了済み)
- **確認プロンプト**: なし
- **冪等性**: 読み出しのみで依頼を変更しない。同じ依頼を再度読めば同じ出力になる
- **エラーハンドリング**:
  - SELECT 失敗(終端到達後の 4 列 SELECT。polling は status のみ)→ 登録 UC の polling と同じ再試行規則(同じ間隔で最大 3 回連続まで再試行)。4 回連続失敗で `error: management db query failed final_crosscheck_id=...`、終了コード 6(この行だけは relay-gate 規約のメッセージ。中継に至る前のエラー扱い)。競合窓のため E2E では再現せず、gateway をスタブにした単体テストで検証する
  - exit_code NULL → 保存済み stdout / stderr(空なら空)をそのまま出し、終了コード 6。stderr に追加行は書かず、実行ログに `WARN relay without stored exit_code final_crosscheck_id=... status=ABORTED`
  - exit_code が 0〜255 の範囲外(比較ツール契約違反)→ 値をそのまま `exit` に渡せないため 6 とし、実行ログに `ERROR exit_code out of range value=...` を残す(仮採用)
- **クラッシュ耐性**: 中継中(stdout 書き出し途中)にプロセスが落ちた場合、依頼は終端状態のまま管理 DB に残る。ジョブスケジューラの正規ジョブ再実行は新しい依頼を作るため、保存済み結果は `final_crosscheck_requests` を SQL で参照して確認する(参照コマンドは提供しない。方針資料「確報はジョブスケジューラの正規ジョブを直接再実行する」)
- **速報と確報のモデル分離**: SELECT 対象は `final_crosscheck_requests` のみ

## データモデル変更

### final_crosscheck_requests(参照)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| final_crosscheck_id | string | 主キー | 追加(参照) |
| status | string | 終端状態の確認にのみ使う。出力しない | 追加(参照) |
| exit_code | integer | そのまま終了コードにする(NULL 可) | 追加(参照) |
| stdout | text | そのまま標準出力にする(NULL 可) | 追加(参照) |
| stderr | text | そのまま標準エラーにする(NULL 可) | 追加(参照) |

## ビジネスルール

- 確報結果の中継制約: 3 値以外の連携データ(状態名・差分件数・レポート URI・final_crosscheck_id)を stdout / stderr に追加しない
- 比較ツール終了コードの対応: 保存済み exit_code を変換しない。比較ツールを差し替えた場合もその契約の値をそのまま返す
- CLI とメールによる提示: 確報結果はメール通知しない(hang-detector の対象外)
- relay-gate 自身の info / warn は実行ログにのみ出す(CLP-006)

## ティア完了条件(BDD)

```gherkin
Feature: 保存済みの確報結果をジョブスケジューラへ返す - 確報クロスチェックティア

  Scenario: 保存済み 3 値を無加工で返す
    Given final_crosscheck_requests に final_crosscheck_id=20260830T210000Z-final-7b2c9e1f status=FAILED exit_code=3 stdout="diff found: 12 rows\n" stderr="warn: table T_ORDER differs\n" がある
    When `final-crosscheck-runner.sh` の relay_stored_result がこの依頼に対して実行される
    Then 終了コード 3 で stdout は "diff found: 12 rows\n"、stderr は "warn: table T_ORDER differs\n" と完全一致する
    And 実行ログに "INFO relay final_crosscheck_id=20260830T210000Z-final-7b2c9e1f status=FAILED exit_code=3" が残る

  Scenario: stdout が NULL でも 0 バイトで返す
    Given final_crosscheck_requests に status=SUCCEEDED exit_code=0 stdout=NULL stderr=NULL がある
    When relay_stored_result が実行される
    Then 終了コード 0 で stdout と stderr はともに 0 バイトである

  Scenario: exit_code が NULL の ABORTED
    Given final_crosscheck_requests に status=ABORTED exit_code=NULL stdout=NULL stderr=NULL がある
    When relay_stored_result が実行される
    Then 終了コード 6 で stdout と stderr はともに 0 バイトで、実行ログに "WARN relay without stored exit_code final_crosscheck_id=20260830T210000Z-final-7b2c9e1f status=ABORTED" が残る

  Scenario: exit_code が 255 を超える
    Given final_crosscheck_requests に status=FAILED exit_code=300 stdout="" stderr="" がある
    When relay_stored_result が実行される
    Then 終了コード 6 で実行ログに "ERROR exit_code out of range value=300" が残る
```
