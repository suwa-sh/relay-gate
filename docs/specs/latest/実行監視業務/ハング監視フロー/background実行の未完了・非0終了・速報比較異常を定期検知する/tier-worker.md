# background実行の未完了・非0終了・速報比較異常を定期検知する - tier-worker仕様

## 変更概要

hang-detector を CronJob 定期実行として追加する。Runner実行結果（RUNNING状態）の走査によるハング疑い・background実行エラーの検知、速報比較結果（NG判定）の走査による速報クロスチェック異常の検知を行い、ハング検知記録を作成するとともにbackground slot実行状態をSUCCEEDED/FAILEDへ確定する。

## イベント処理仕様

### hang-detector（異常定期検知）

- **トリガー**: CronJob定期実行（例: 1分間隔）
- **入力**: RDBの `runner_results` テーブル（status='RUNNING' AND role_type='background'）、`rapid_crosscheck_results` テーブル（comparison_result='NG'）をポーリング
- **出力**: `hang_detections` テーブルへのINSERT（未解消の重複検知記録が存在しない場合のみ）、`runner_results` テーブルのstatus更新（SUCCEEDED/FAILED）、CLI標準出力への検知サマリ
- **処理フロー**:
  1. RUNNING状態かつrole_type='background'のRunner実行結果を全件取得する（foreground/rapid-crosscheckは対象外とする）
  2. 各レコードについて exitcode.txt の有無を確認する。未出力かつ started_at からの経過時間が hang_detect_limit_minutes を超過していればハング疑いとして記録対象に追加する
  3. exitcode.txt出力済みの場合、exit_codeが0ならSUCCEEDEDへ、非0ならFAILEDへ状態を確定し、非0の場合はbackground実行エラーとして記録対象に追加する
  4. comparison_result='NG'の速報比較結果を全件取得し、速報クロスチェック異常として記録対象に追加する
  5. 記録対象の各候補について、同一run_id・同一detection_typeの未解消（resolved_at IS NULL）の既存ハング検知記録が存在するか確認する。存在する場合は新規レコードを作成せず重複通知を抑止する
  6. 未解消の重複検知記録が存在しない候補のみをハング検知記録としてINSERTし、Runner実行結果の状態更新をコミットする
  7. 検知件数（新規作成分）・検知種別のサマリ・重複抑止件数を標準出力へ出力する
- **エラーハンドリング**:

| エラー種別 | リトライ | 説明 |
|-----------|---------|------|
| RDB接続断 | No | 当該実行サイクルを終了コード1で終了し、次回CronJob起動時に再試行する（リトライは行わずCronJobの周期に委ねる） |
| INSERT一意制約違反（同一detection_idの重複） | No | 冪等性のため既存レコードを保持しスキップする。楽観ロック競合ログを1回出力する |
| ハング検知記録の永続化失敗 | No | usecase層で技術例外を集約キャッチし1回ログ出力、終了コード1で終了する |
| 同一run_id・同一detection_typeの未解消検知記録が既存 | No（正常系として無視） | 新規レコードを作成せずスキップする。継続する異常（RUNNING固着・速報NG継続）による周期実行毎の重複検知記録の蓄積・重複通知を防止する |

## データモデル変更

### hang_detections（ハング検知記録）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| detection_id | VARCHAR | ハング検知記録の一意識別子（主キー） | 追加 |
| run_id | VARCHAR | 検知対象のRunner実行結果のrun_id | 追加 |
| detection_type | VARCHAR | 異常検知種別。値: ハング疑い, background実行エラー, 速報クロスチェック異常 | 追加 |
| detected_at | DATETIME | 検知日時 | 追加 |
| threshold_minutes | INTEGER | 検知しきい値（hang_detect_limit_minutes）。ハング疑い検知時のみ設定 | 追加 |
| slot_type | VARCHAR | 対象slot種別。値: blue, green | 追加 |
| notify_target | VARCHAR | 通知先（運用者） | 追加 |
| resolved_at | DATETIME | 異常解消日時（nullable）。対象の異常が解消（RUNNING→SUCCEEDED確定、速報比較結果のNG解消等）した時点で設定する。NULLの間は「未解消」として重複検知抑止の判定に用いる | 追加 |

### runner_results（Runner実行結果）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| status | VARCHAR | 実行状態。本UCによりRUNNING→SUCCEEDED/FAILEDへ更新される | 変更 |
| role_type | VARCHAR | foreground/background/rapid-crosscheck | 参照のみ（RUNNING行走査をbackground限定するため） |

## ビジネスルール

- hang_detect_limit_minutesは background role ごとにexecution-spec.jsonへ保存された値を使用し、ハードコードしない
- exitcode.txtが未出力かつ経過時間がhang_detect_limit_minutesを超過した場合のみハング疑いとして記録する（超過前は記録対象外とする）
- RUNNING状態のRunner実行結果走査は role_type='background' に限定する。foreground・rapid-crosscheck役割のRUNNING行は本UCの検知対象に含めない
- 同一run_idに対する重複検知（同一detection_type・同一実行サイクル内）を防止するため、detection_idの一意制約違反時はスキップしログのみ記録する
- 同一run_id・同一detection_typeについて、直近の未解消（resolved_at IS NULL）検知記録が存在する場合は新規レコードを作成せず重複通知を抑止する。RUNNING固着や速報比較結果NGの継続など、異常が解消されるまで周期実行のたびに新規ハング検知記録が積み上がることを防ぐ
- background slot実行状態のRUNNING→SUCCEEDED/FAILED遷移は本UCのみがトリガーとなる（他UCからの直接更新は行わない）

## CLI 出力/画面表示マッピング

### background実行異常検知画面

- **route**: /cli/hang-watch/detect
- **表示要素とコンポーネントマッピング**:

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 検知結果一覧 | 通知バナー | HangDetectionNotice | run_id・異常検知種別・検知日時・しきい値・対象slot・通知先を表示 |
| 検知対象Runner実行結果 | ターミナル調パネル | RunnerResultPanel | 検知対象のstarted_at/stdout/stderr/exit_codeを表示（background variant） |

- **デザイントークン参照**:

| 用途 | トークン | 値 |
|------|---------|---|
| ハング疑い/background実行エラー表示色 | var(--semantic-warning) | amber-600 (#D97706) |
| SUCCEEDED表示色 | var(--color-green-600) | #16A34A |
| FAILED表示色 | var(--color-red-600) | #DC2626 |

- **UIロジック**:
  - 状態管理: CronJob実行ごとに検知サマリ（件数・種別内訳）を標準出力へレンダリングする。将来ダッシュボードでは直近実行サイクルの検知結果一覧をポーリング表示する
  - バリデーション: hang_detect_limit_minutesが未設定（null）のRunner実行結果はハング疑い判定の対象外とし警告ログを出力する
  - ローディング: 該当なし（CronJob実行のため対話的ローディング表示は不要）
  - エラーハンドリング: RDB接続断時はHangDetectionNoticeを出力せず、標準エラーへ検知処理失敗のメッセージを出力し終了コード1で終了する

## 共通コンポーネント参照

参照元: `docs/specs/events/20260817_155817_spec_generation/_cross-cutting/ux-ui/common-components.md`（実行結果ターミナル表示パターン、共通状態表示パターン）

| コンポーネント | インポートパス | variant | Props マッピング |
|---|---|---|---|
| HangDetectionNotice | src/components/domain/HangDetectionNotice.tsx | banner | runId←run_id, anomalyType←detection_type, detectedAt←detected_at, thresholdMinutes←threshold_minutes, slot←slot_type, notifyTo←notify_target |
| RunnerResultPanel | src/components/domain/RunnerResultPanel.tsx | background | runId←run_id, stdout/stderr/exitCode←検知対象Runner実行結果（started_at含む） |

適用パターン: 実行結果ターミナル表示パターン（検知対象実行結果の表示）とHangDetectionNoticeによる検知サマリ表示の併用

## ティア完了条件（BDD）

```gherkin
Feature: background実行の未完了・非0終了・速報比較異常を定期検知する - tier-worker

  Scenario: しきい値超過によりハング疑いを記録する
    Given run_id "run-20260817-010" のRunner実行結果がrole_type"background"、status"RUNNING"、started_at"2026-08-17T09:00:00+09:00"で存在する
    And hang_detect_limit_minutesが30、現在時刻が"2026-08-17T09:35:00+09:00"である
    When CronJobがhang-detectorを起動する
    Then detection_id "det-20260817-001" のハング検知記録がdetection_type"ハング疑い"で作成され、終了コード0で完了する

  Scenario: role_type='background'以外のRUNNING行は走査対象に含めない
    Given run_id "run-20260817-014" のRunner実行結果がrole_type"foreground"、status"RUNNING"で存在する
    When gateway層が `SELECT * FROM runner_results WHERE status='RUNNING' AND role_type='background'` を実行する
    Then run_id "run-20260817-014" は結果セットに含まれない

  Scenario: 未解消の既存検知記録がある場合は新規INSERTをスキップする
    Given run_id "run-20260817-016" detection_type"ハング疑い"のハング検知記録がdetection_id"det-20260817-004"、resolved_at未設定（未解消）で既に存在する
    And run_id "run-20260817-016" のRunner実行結果は引き続きstatus"RUNNING"でしきい値超過が継続している
    When CronJobがhang-detectorを再度起動する
    Then gateway層は run_id "run-20260817-016" detection_type"ハング疑い"の新規レコードをINSERTせず、処理サマリに重複抑止1件を記録する
```
