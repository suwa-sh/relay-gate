# ハング検知ジョブの異常終了を確認する - 実行監視・復旧ティア仕様

## 変更概要

このティアに新しいコマンドは追加しない。
運用者がジョブスケジューラで受け取るハング検知ジョブの終了コードと標準エラーの alert 行を、受け手の観点で読み方と対処に結びつける。
終了コードの定義は UC「background 実行の経過時間と終了状態を判定する」、alert 行の出し方は UC「ハング疑い・実行エラー・比較異常を通知する」の tier 仕様を正とする。

## コマンド契約

### ハング検知ジョブの結果(受け手としての契約)

- **受け取り方**: ジョブスケジューラの既存のジョブ監視・障害通知。ハング検知定期ジョブのジョブステータスが警告終了または失敗になったときに通知される。通知の経路と宛先はジョブスケジューラ側の運用で定める
- **見る場所**: ジョブスケジューラの実行履歴に保管されたハング検知ジョブの標準エラー
- **アクセス権**: 運用者(ジョブスケジューラの障害通知を受ける運用体制。CTP-009)

#### 引数・オプション

| 名前 | 型 | 必須 | 既定値 | 説明 |
|------|---|------|-------|------|
| (該当なし) | — | — | — | 受け取りに引数は無い |

- **stdin**: なし

#### ジョブステータスの読み方

| 終了コード | ジョブステータス | 標準エラー | 運用者の判断 |
|---|---|---|---|
| 0 | 正常 | alert 行なし | 対処不要(通知済みの異常が続いていても 0) |
| 3 | 警告終了 | warning の alert 行だけ | 静観可。プロセスを確認する |
| 6 | 失敗 | error の alert 行が 1 行以上、または `error:` 行(ハング検知ジョブ自身の実行エラー) | 対処要。alert 行ごとに対処し、`error:` 行があれば原因を取り除く |
| 2 | 失敗 | `error:` 行(設定・入力エラー)。走査していない | 設定ファイルを直す |

#### alert 行の読み方

`alert: level=<warning|error> kind=<kind> run_id=<run_id> role=<role> job_id=<job_id> elapsed_minutes=<n>`

| kind | level | 意味 | 運用者の判断 |
|---|---|---|---|
| `hang-suspected` | warning | exitcode.txt が無いまま hang_detect_limit_minutes を超過(依頼なら RUNNING で超過) | 静観可。プロセスを確認し、ハングなら停止 → `abort-{role}.sh` |
| `background-exec-error` | error | exitcode.txt が非 0 | 対処要。stderr.log を確認 → `background-rerun.sh` |
| `rapid-crosscheck-error` | error | 速報比較依頼が FAILED または比較 NG | 対処要。`rapid-crosscheck-result.sh` で原因調査。ジョブスケジューラ応答には影響しない |

- 1 回の見回りで知らせるのは、その回に新たに見つけた異常だけ。並び順は run_id 昇順 → role(blue, green, rapid-crosscheck)
- 通知済みの異常は次の見回りから出ない。ハング疑いの後に実行エラー・比較異常になった場合は、別の異常として error の alert 行が 1 回出る

## 出力契約

- **stdout / stderr / 終了コード**: 該当なし(受け手の UC)
- **受け取りの保証**: 同じ run_id + role の同じ通知済み状態の alert 行は 1 回だけ出る。運用者が `abort-*` で中止した対象(slot は aborted.txt あり / 依頼は ABORTED)は次回の判定で監視記録が COMPLETED に終端し(off でハング疑いを知らせ済みなら、通知済みの印が COMPLETED に書き換わる)、以後 alert 行は出ない。ハング検知ジョブが alert 行を出したあとで監視記録・通知済みの印の保存に失敗した回は終了コード 6 になり、同じ alert 行が次の見回りでも出る

## UC ロジック

- **バリデーション**: なし
- **確認プロンプト**: なし(対処コマンド側の停止確認プロンプトは実行中止フローの UC)
- **冪等性**: 確認は状態を変えない
- **対処の手順**(運用者の判断):
  | kind | 確認するもの | 対処 |
  |---|---|---|
  | hang-suspected(role=blue / green) | 実行ホストのプロセス | 動いていれば待つ(正常終了すれば監視記録に警告時経過時間が残り、`hang-detect-trend.sh` で上限調整の根拠になる)。ハングなら自分でプロセスを止めてから `abort-{role}.sh --run-id {run_id}`、必要なら `background-rerun.sh` |
  | hang-suspected(role=rapid-crosscheck) | 速報クロスチェック worker と比較ツールのプロセス | 止めてから `abort-rapid-crosscheck.sh --run-id {run_id}`、必要なら `background-rerun.sh --role rapid-crosscheck` |
  | background-exec-error | `$RELAY_GATE_ARTIFACT_ROOT/facade/{run_id}/{role}/stderr.log` | 原因を取り除いてから `background-rerun.sh --source-run-id {run_id} --role {role}`(元の実行は FAILED なので abort 不要) |
  | rapid-crosscheck-error | `rapid-crosscheck-result.sh --run-id {run_id} --show-output` の status / exit_code と比較ツールの stdout / stderr | 原因調査。必要なら `background-rerun.sh --role rapid-crosscheck`。リリース判断は確報で行う |
- **監視記録の確認**: 実行ログ `$RELAY_GATE_LOG_DIR/hang-detector.sh.log` の `INFO monitor record run_id={run_id} role={role} ...` 行で、経過時間・警告時経過時間・監視状態を確認する(RAPID_CROSSCHECK_MODE によらない)。ジョブごとの警告傾向は `hang-detect-trend.sh`(off 以外)で確認する
- **クラッシュ耐性**: 該当なし

## データモデル変更

### monitor_records(参照。運用者は実行ログの監視記録行で確認する)

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| alerted_at | datetime | ハング検知ジョブが alert 行を出した回の判定時刻 | 追加(参照) |
| elapsed_minutes_at_alert | integer | 最初の警告時の経過時間 | 追加(参照) |

## ビジネスルール

- 通知レベルの判定: 警告終了(warning)= 静観可、失敗(error、またはハング検知ジョブ自身の実行エラー)= 対処要
- CLI による提示: 提示は終了コードと標準エラーだけ。alert 行の run_id と role をそのままコマンド引数に使える
- 監視は通知のみ: 自動中止・自動再実行は行われない。対処は運用者
- 復旧手段の選択: background slot / 速報比較依頼は `background-rerun.sh`、foreground / 確報はジョブスケジューラの正規ジョブ(ハング検知ジョブが知らせるのは前者のみ)

## ティア完了条件(BDD)

```gherkin
Feature: ハング検知ジョブの異常終了を確認する - 実行監視・復旧ティア

  Scenario: alert 行だけで段階・種別・対象を判別できる
    Given ハング検知ジョブが run_id=20260830T113000-JOB001-3f9a1c2e job_id=JOB001 role=green のハング疑いを新たに見つけた
    When 運用者がジョブスケジューラの実行履歴で標準エラーを読む
    Then 標準エラーに "alert: level=warning kind=hang-suspected run_id=20260830T113000-JOB001-3f9a1c2e role=green job_id=JOB001 elapsed_minutes=74" の 1 行があり、ジョブステータスは警告終了(終了コード 3)である

  Scenario: alert 行の run_id と role から対処コマンドを組み立てられる
    Given 前のシナリオと同じ alert 行を読んだ
    When 運用者が対処コマンドを組み立てる
    Then 中止は "abort-green.sh --run-id 20260830T113000-JOB001-3f9a1c2e"、リランは "background-rerun.sh --source-run-id 20260830T113000-JOB001-3f9a1c2e --role green" になり、どちらも alert 行の値をそのまま使う

  Scenario: 同じ対象の同じ異常は 1 回だけ届く
    Given 同じ run の green が 30 分間ハング疑いのままである
    When ハング検知ジョブが 5 分ごとに 6 回実行される
    Then hang-suspected の alert 行が出て警告終了になるのは最初の 1 回だけで、残りの 5 回は終了コード 0 である
```
