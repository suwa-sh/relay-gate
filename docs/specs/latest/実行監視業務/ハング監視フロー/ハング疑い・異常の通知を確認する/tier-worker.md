# ハング疑い・異常の通知を確認する - tier-worker仕様

## 変更概要

運用者向けの照会コマンドとして、通知済みのハング検知記録を検知日時降順で一覧表示する処理を追加する。CronJob定期実行ではなく運用者のCLI操作トリガーで動作する点が本BUC内の他2 UCと異なる。

## イベント処理仕様

### ハング検知記録照会

- **トリガー**: 運用者によるCLIコマンド実行（`relaygate hang-watch notice`）
- **入力**: RDBの `hang_detections` テーブル（notified_at IS NOT NULL、任意でrun_id絞り込み）
- **出力**: CLI標準出力へのHangDetectionNotice一覧
- **処理フロー**: 1. CLI引数（--run-id任意）を解析する 2. 通知済み（notified_at IS NOT NULL）のハング検知記録を検知日時降順で取得する 3. HangDetectionNotice形式に整形し標準出力へ出力する
- **エラーハンドリング**:

| エラー種別 | リトライ | 説明 |
|-----------|---------|------|
| RDB接続断 | No | usecase層で技術例外を1回ログ出力し、presentation層で終了コード1に変換する |
| 該当レコードなし | No | エラーとせず「該当するハング検知記録はありません」を標準出力へ出力し終了コード0で終了する |

## データモデル変更

本UCはデータモデルの変更（追加・変更・削除）を行わない。参照のみ。

## ビジネスルール

- notified_at IS NULL（未通知）のハング検知記録は照会結果に含めない
- --run-id未指定時は通知済み全件を検知日時降順で返す

## CLI 出力/画面表示マッピング

### ハング異常通知確認画面

- **route**: /cli/hang-watch/notice
- **表示要素とコンポーネントマッピング**:

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 検知記録一覧 | 通知バナー一覧 | HangDetectionNotice | run_id・異常検知種別・検知日時・しきい値・対象slot・通知先を検知日時降順で表示 |

- **デザイントークン参照**:

| 用途 | トークン | 値 |
|------|---------|---|
| ハング疑い/background実行エラー表示色 | var(--semantic-warning) | amber-600 (#D97706) |
| 速報クロスチェック異常表示色 | var(--semantic-destructive) | red-600 (#DC2626) |

- **UIロジック**:
  - 状態管理: 照会結果は都度RDBから取得しCLIプロセス内で保持しない（ステートレス）
  - バリデーション: --run-idの形式が不正な場合はバリデーションエラーとして終了コード2で終了する
  - ローディング: 該当なし（CLI応答は10秒以内。CTP-009準拠）
  - エラーハンドリング: RDB接続断時は標準エラーへ「ハング検知記録の取得に失敗しました」を出力し終了コード1で終了する

## 共通コンポーネント参照

参照元: `docs/specs/events/20260817_155817_spec_generation/_cross-cutting/ux-ui/common-components.md`（共通状態表示パターン）

| コンポーネント | インポートパス | variant | Props マッピング |
|---|---|---|---|
| HangDetectionNotice | src/components/domain/HangDetectionNotice.tsx | banner | runId←run_id, anomalyType←detection_type, detectedAt←detected_at, thresholdMinutes←threshold_minutes, slot←slot_type, notifyTo←notify_target |

適用パターン: HangDetectionNoticeによる異常検知種別・しきい値・対象slotの専用属性表示（汎用Bannerではなく専用コンポーネントを使用する理由はui-design.mdの代替案却下理由を参照）

## ティア完了条件（BDD）

```gherkin
Feature: ハング疑い・異常の通知を確認する - tier-worker

  Scenario: 通知済みのハング検知記録を検知日時降順で表示する
    Given detection_id "det-20260817-001"（notified_at"2026-08-17T09:36:00+09:00"）と detection_id "det-20260817-002"（notified_at"2026-08-17T10:05:00+09:00"）のハング検知記録が存在する
    When 運用者が"relaygate hang-watch notice"を実行する
    Then 標準出力にdetection_id"det-20260817-002"が先、detection_id"det-20260817-001"が後の順で表示され終了コード0で完了する
```
