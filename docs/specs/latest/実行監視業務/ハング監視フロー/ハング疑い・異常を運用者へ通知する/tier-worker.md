# ハング疑い・異常を運用者へ通知する - tier-worker仕様

## 変更概要

hang-detectorが記録したハング検知記録のうち未通知分を対象に、CronJob定期実行で運用者へ通知するバッチ処理を追加する。banner（CLI標準出力／将来ダッシュボード）とemail（将来メール通知）の2チャネルで同一情報構造の通知を行う。

## イベント処理仕様

### 異常通知バッチ

- **トリガー**: CronJob定期実行（例: 1分間隔。hang-detectorの検知サイクルと独立して稼働する）
- **入力**: RDBの `hang_detections` テーブル（notified_at IS NULL）をポーリング
- **出力**: `hang_detections` テーブルの notified_at 更新、CLI標準出力（banner）への通知内容出力
- **処理フロー**: 1. 未通知のハング検知記録を全件取得する 2. HangDetectionNotice形式（runId/anomalyType/detectedAt/thresholdMinutes/slot/notifyTo）に整形する 3. banner（標準出力）へ通知を出力する 4. notified_atを現在時刻で更新する
- **エラーハンドリング**:

| エラー種別 | リトライ | 説明 |
|-----------|---------|------|
| RDB接続断（notified_at更新失敗） | No | 通知は出力済みだがnotified_at未更新のため、次回バッチで再通知される。冪等な運用上の重複通知として許容する |
| 通知送信自体の失敗（標準出力エラー等） | No | notified_atは更新せず、次回バッチで再試行する |

## データモデル変更

### hang_detections（ハング検知記録）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| notified_at | DATETIME(nullable) | 通知済み日時。NULLの場合は未通知として通知バッチの対象となる | 追加 |

## ビジネスルール

- notified_atがNULLのハング検知記録のみを通知対象とし、重複通知を防止する
- 通知送信後にnotified_at更新が失敗した場合は次回バッチで再通知を許容する（At-Least-Once配信。重複通知よりも通知漏れの防止を優先する）
- banner/emailの2 variantは同一の情報構造（run_id/検知種別/検知日時/しきい値/対象slot/通知先）を共有し、通知内容に差異を持たせない

## CLI 出力/画面表示マッピング

### 異常通知発信画面

- **route**: /cli/hang-watch/notify
- **表示要素とコンポーネントマッピング**:

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 通知本文 | 通知バナー | HangDetectionNotice（banner variant） | run_id・異常検知種別・検知日時・しきい値・対象slot・通知先を表示 |

- **デザイントークン参照**:

| 用途 | トークン | 値 |
|------|---------|---|
| 通知バナー背景（warning） | var(--semantic-warning) | amber-600 (#D97706) |
| 通知バナーテキスト | var(--color-slate-900) | #0F172A |

- **UIロジック**:
  - 状態管理: 通知バッチ実行ごとに未通知件数を取得し、送信結果をnotified_atへ反映する。状態は永続化されたnotified_atのみで管理し、画面側で独自の状態を保持しない
  - バリデーション: notify_targetが空の場合は送信をスキップしエラーログを出力する
  - ローディング: 該当なし（CronJob実行）
  - エラーハンドリング: 送信失敗時はnotified_atを更新せず、標準エラーへ失敗理由を出力する

## 共通コンポーネント参照

参照元: `docs/specs/events/20260817_155817_spec_generation/_cross-cutting/ux-ui/common-components.md`（共通状態表示パターン）

| コンポーネント | インポートパス | variant | Props マッピング |
|---|---|---|---|
| HangDetectionNotice | src/components/domain/HangDetectionNotice.tsx | banner | runId←run_id, anomalyType←detection_type, detectedAt←detected_at, thresholdMinutes←threshold_minutes, slot←slot_type, notifyTo←notify_target |

適用パターン: HangDetectionNoticeのbanner/email 2variantは同一情報構造（run_id/検知種別/検知日時/しきい値/対象slot/通知先）を共有する

## ティア完了条件（BDD）

```gherkin
Feature: ハング疑い・異常を運用者へ通知する - tier-worker

  Scenario: 未通知のハング検知記録をbannerで通知しnotified_atを更新する
    Given detection_id "det-20260817-001" のハング検知記録がnotified_at未設定で存在する
    When CronJobが異常通知バッチを起動する
    Then HangDetectionNotice（banner）がrun_id"run-20260817-010"、異常検知種別"ハング疑い"を含めて標準出力に表示され、notified_atが更新され、終了コード0で完了する
```
