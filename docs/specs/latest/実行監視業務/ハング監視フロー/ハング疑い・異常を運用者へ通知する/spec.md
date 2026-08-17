# ハング疑い・異常を運用者へ通知する

## 概要

検知済みのハング検知記録（未通知分）を対象に、移行運用責任者から運用者へ異常検知種別・対象run_id・検知日時・しきい値・対象slotを通知する。banner（CLI標準出力/将来ダッシュボード）とemail（将来のメール通知チャネル）の2 variantで同一の情報構造を用いる。

## データフロー

```mermaid
graph LR
  subgraph WK["tier-worker"]
    WK_Pres["presentation\nCronJobエントリポイント（通知バッチ起動）"]
    WK_UC["usecase\nNotifyAnomaliesCommand"]
    WK_Domain["domain\nハング検知記録\n未通知判定"]
    WK_GW["gateway\nハング検知記録Record / 通知送信client"]
    WK_Pres --> WK_UC --> WK_Domain
    WK_UC --> WK_GW
  end
  subgraph DB["RDB"]
    DB_Hang[("ハング検知記録\ndetection_id, run_id, notify_target")]
  end
  subgraph OUT["CLI出力/通知画面"]
    OUT_Screen["異常通知発信画面\nHangDetectionNotice（banner）"]
  end
  DB_Hang --> WK_GW
  WK_GW -->|"SELECT WHERE notified_at IS NULL"| DB_Hang
  WK_GW -->|"UPDATE notified_at"| DB_Hang
  WK_Domain --> WK_UC --> WK_Pres --> OUT_Screen
```

| レイヤー | データモデル | 変換内容 |
|---------|------------|---------|
| WK presentation | CronJobトリガー（通知バッチ間隔） | スケジュール起動 → NotifyAnomaliesCommand 生成 |
| WK usecase | NotifyAnomaliesCommand | 未通知のハング検知記録を取得し通知対象を集約 |
| WK domain | ハング検知記録 | notified_at IS NULL の未通知レコードのみ抽出 |
| WK gateway | ハング検知記録 UPDATE, 通知送信 | notified_at の記録更新、HangDetectionNotice形式での通知出力 |
| CLI出力 | 異常通知発信画面表示 | HangDetectionNotice（banner variant）のレンダリング |

## 処理フロー

```mermaid
sequenceDiagram
  actor Timer as CronJob（通知バッチ）

  box rgb(240,255,240) tier-worker
    participant Pres as presentation
    participant UC as usecase
    participant Domain as domain
    participant GW as gateway
  end

  participant DB as RDB

  Timer->>Pres: 定期実行トリガー（例: 1分間隔）
  Pres->>UC: NotifyAnomaliesCommand
  UC->>GW: 未通知のハング検知記録を取得
  GW->>DB: SELECT * FROM hang_detections WHERE notified_at IS NULL
  DB-->>GW: 未通知レコード一覧
  GW-->>UC: ハング検知記録一覧
  alt 未通知レコードが1件以上存在する
    UC->>Domain: 通知対象として整形（HangDetectionNotice形式）
    Domain-->>UC: 通知内容（run_id/anomalyType/detectedAt/thresholdMinutes/slot/notifyTo）
    UC->>GW: 通知送信（banner: 標準出力、将来email）
    GW-->>UC: 送信結果
    UC->>GW: notified_atを更新
    GW->>DB: UPDATE hang_detections SET notified_at = now()
    DB-->>GW: 完了
    GW-->>UC: 更新完了
    UC-->>Pres: 通知件数
    Pres-->>Timer: 標準出力へ通知サマリ出力（終了コード0）
  else 未通知レコードが0件
    UC-->>Pres: 通知対象なし
    Pres-->>Timer: 標準出力へ「通知対象なし」出力（終了コード0）
  end
```

## バリエーション一覧

| バリエーション名 | 値 | 処理内容 | 適用 tier | 適用箇所 |
|----------------|---|---------|----------|---------|
| 異常検知種別 | ハング疑い、background実行エラー、速報クロスチェック異常 | 通知メッセージ本文の異常種別ラベルを決定する | tier-worker | usecase「NotifyAnomaliesCommand」 |

## 分岐条件一覧

| 条件名 | 判定ルール | 適用 tier | 適用箇所 | BDD Scenario |
|--------|----------|----------|---------|-------------|
| notified_at未設定 | ハング検知記録のnotified_atがNULLの場合のみ通知対象とする（重複通知の防止） | tier-worker | usecase「NotifyAnomaliesCommand」 | 未通知のハング検知記録を運用者へ通知する |

## 計算ルール一覧

| 計算名 | 入力情報 | 計算式/ロジック | 出力情報 | 適用 tier |
|--------|---------|---------------|---------|----------|
| 通知対象抽出 | ハング検知記録.notified_at | notified_at IS NULL のレコードを全件抽出 | 通知対象一覧 | tier-worker |

## 状態遷移一覧

該当なし（本UCはハング検知記録の状態モデルを持たず、notified_atの有無で通知済み/未通知を管理する）

## 関連 RDRA モデル

| モデル種別 | 要素名 | 関連 |
|-----------|--------|------|
| 業務 | 実行監視業務 | このUCが属する業務 |
| BUC | ハング監視フロー | このUCを含むBUC |
| アクター | 移行運用責任者 | 検知した異常を運用者へ通知する主体 |
| アクター | 運用者 | 通知の受領者（通知先） |
| 情報 | ハング検知記録 | このUCが参照・notified_at更新する情報 |

## E2E 完了条件（BDD）

### 正常系

```gherkin
Feature: ハング疑い・異常を運用者へ通知する

  Scenario: 未通知のハング検知記録を運用者へ通知する
    Given detection_id "det-20260817-001" のハング検知記録がdetection_type"ハング疑い"、run_id"run-20260817-010"、notified_atが未設定で存在する
    When CronJobが通知バッチトリガーで起動する
    Then detection_id "det-20260817-001" のハング検知記録がHangDetectionNotice（banner）形式で運用者へ通知される
    And 同レコードのnotified_atが現在時刻で更新される

  Scenario: 通知対象が存在しない場合は正常終了する
    Given notified_atが未設定のハング検知記録が0件である
    When CronJobが通知バッチトリガーで起動する
    Then 標準出力に「通知対象なし」が出力され終了コード0で完了する
```

### 異常系

```gherkin
  Scenario: 通知送信の永続化失敗時はnotified_atを更新しない
    Given detection_id "det-20260817-004" のハング検知記録が未通知で存在する
    When 通知送信後のnotified_at更新でRDB接続断が発生する
    Then usecaseは技術例外を1回だけログ出力し終了コード1で終了する
    And 次回通知バッチ実行時に同レコードが再度通知対象として抽出される（冪等性の保証）
```

## ティア別仕様

- [tier-worker（バックエンドワーカーティア）](tier-worker.md)
