# blue/green runnerの完了通知を受けて速報比較依頼を作成する - バックエンドワーカーティア仕様

## 変更概要

CronJob定期実行により、blue/green background runnerの完了（Runner実行結果のexit_code確定）を検知し、job_id単位でblue/green双方の完了ペアリングが揃った未依頼ジョブについて速報比較依頼をREQUESTED状態で新規作成する処理を追加する。runner_resultsにはjob_id属性が存在しないため、run_idを介してexecution_specsテーブルとJOINしてjob_idを取得する。

## イベント処理仕様

### 速報比較依頼作成worker
- **トリガー**: CronJob定期実行（1分間隔想定）
- **入力**: `runner_results` テーブル（role='background' AND status IN ('SUCCEEDED','FAILED')）と `execution_specs` テーブル（run_idでJOINしjob_idを取得）から、job_idが `rapid_crosscheck_requests` に未存在の行
- **出力**: `rapid_crosscheck_requests` テーブルへの新規INSERT（status=REQUESTED）
- **処理フロー**:
  1. presentation層がCronJobトリガーを受け付ける
  2. usecase層が `CreateRapidCrosscheckRequestCommand` を発行する
  3. gateway層が `runner_results` と `execution_specs` を run_id でJOINし、role='background'かつstatus確定済みの行からjob_id単位の候補（未依頼job_id）を検索する
  4. domain層がjob_id単位にblue（slot_type=blue）・green（slot_type=green）双方のRunner実行結果がSUCCEEDED/FAILEDで確定しているかをペアリング判定する。片方のみ確定の場合は当該job_idを対象外とし次回サイクルで再判定する
  5. domain層がfeature flag設定（RAPID_CROSSCHECK_MODE）を判定し、onかつペアリング完了の場合のみ速報比較依頼エンティティ（status=REQUESTED）を生成する
  6. gateway層が `rapid_crosscheck_requests` へINSERTする
  7. presentation層が処理件数・対象job_id一覧を構造化ログへ出力する
- **エラーハンドリング**:

| エラー種別 | リトライ | 説明 |
|-----------|---------|------|
| RDB接続エラー | Yes（次回CronJob実行時に再試行） | 標準エラーへ記録し終了コード1で終了。二重作成防止のためjob_id一意性制約に依存する |
| 一意性制約違反（同一job_idの重複INSERT） | No（正常系として無視） | 楽観ロック競合ログとして記録し処理を継続する（LR-008準拠） |
| RAPID_CROSSCHECK_MODE=off | No（正常系） | 依頼を作成せず処理件数0件として正常終了する |
| blue/greenペアリング未完了 | No（正常系） | 依頼を作成せず当該job_idを次回サイクルで再判定する |

## データモデル変更

### rapid_crosscheck_requests（速報比較依頼）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| job_id | VARCHAR | 速報比較依頼の一意識別子（PK、execution_specs.job_idと同一） | 追加（INSERT対象） |
| blue_run_id | VARCHAR | blue実装（slot_type=blue）のrunner_results.run_id | 追加（INSERT対象） |
| green_run_id | VARCHAR | green実装（slot_type=green）のrunner_results.run_id | 追加（INSERT対象） |
| requested_at | DATETIME | 依頼作成日時 | 追加（INSERT対象、CronJob実行時刻） |
| status | VARCHAR | REQUESTED/CLAIMED/RUNNING/SUCCEEDED/FAILED/ABORTED | 追加（初期値REQUESTED） |
| lease_expires_at | DATETIME | lease期限（nullable） | 追加（初期値NULL） |
| worker_id | VARCHAR | 取得中のworker識別子（nullable） | 追加（初期値NULL） |

### runner_results（Runner実行結果）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | VARCHAR | Runner実行結果の識別子 | 参照のみ |
| slot_type | VARCHAR | blue/green | 参照のみ（blue/greenペアリング判定に使用） |
| role | VARCHAR | foreground/background/rapid-crosscheck | 参照のみ（background限定検索） |
| status | VARCHAR | RUNNING/SUCCEEDED/FAILED/ABORTED | 参照のみ（SUCCEEDED/FAILED限定検索） |

### execution_specs（execution-spec.json、参照のみ）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | VARCHAR | Runner実行結果とのJOINキー | 参照のみ |
| job_id | VARCHAR | job_id単位のペアリング判定・速報比較依頼のキーとして使用 | 参照のみ |

## ビジネスルール

- RAPID_CROSSCHECK_MODEがoffの場合、blue/green runnerからの完了通知送信・速報管理DBへの接続・書込みを一切行わない（依頼作成自体をスキップする）
- job_idはrunner_resultsに属性として存在しないため、必ずexecution_specsをrun_idでJOINして取得する
- 同一job_idについて、blue（slot_type=blue）・green（slot_type=green）双方のRunner実行結果（role=background）がSUCCEEDED/FAILEDで確定して初めて速報比較依頼を作成する（ペアリング判定）。片方のみ完了している場合は依頼を作成せず、次回CronJob実行時に再判定する
- 同一job_idに対する速報比較依頼は一意（job_idユニーク制約）とし、重複作成をRDB制約で防止する（CTP-006冪等性方針準拠）
- CronJob定期実行はjob_idの相関IDにより処理の重複起動を検知・防止する
- CLI応答は10秒以内、スループットは10TPS程度を目安とする（CTP-009）

## CLI 出力/画面表示マッピング

### 速報比較依頼作成画面

- **route**: /cli/rapid-crosscheck/create
- **表示要素とコンポーネントマッピング**:

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 作成された速報比較依頼一覧行 | テーブル行 | CrossCheckRequestRow（variant: rapid） | 新規作成されたjob_id/blue_run_id/green_run_id/status=REQUESTEDを表示 |
| 作成完了通知 | バナー | Banner（variant: info） | 「REQUESTED状態への遷移を即時反映する」（ux-design.md改善機会に対応） |

- **デザイントークン参照**:

| 用途 | トークン | 値 |
|------|---------|---|
| REQUESTED状態背景 | var(--color-amber-100) | #FEF3C7 |
| 作成完了バナー背景 | var(--color-blue-100) | #DBEAFE |

- **UIロジック**: 状態管理はCronJob実行のたびにステートレスに再計算する（DBの未依頼行を都度検索）。バリデーションはRAPID_CROSSCHECK_MODEの参照のみで入力フォームは持たない。ローディングは将来ダッシュボードでのみ表示。エラーハンドリングは構造化ログ+終了コードで表現する

## 共通コンポーネント参照

参照元: `docs/specs/events/20260817_155817_spec_generation/_cross-cutting/ux-ui/common-components.md`（状態一覧+フィルターパターン）

| コンポーネント | インポートパス | variant | Props マッピング |
|---|---|---|---|
| CrossCheckRequestRow | src/components/domain/CrossCheckRequestRow.tsx | rapid | runId←blue_run_id（一覧の代表run_id。green_run_idは詳細列で別途表示）, jobIdOrTargetDate←job_id, state←status（作成時はREQUESTED固定）, leaseExpiry←lease_expires_at（作成時はNULL）, workerId←worker_id（作成時はNULL） |
| Banner | src/components/ui/Banner.tsx | info | 依頼作成完了メッセージ「REQUESTED状態への遷移を即時反映する」 |

適用パターン: 状態一覧+フィルターパターン（一覧表示）。中止依頼→対話確認の二段階パターンは対象外（本UCは自動作成のみで対話操作を持たない）

## ティア完了条件（BDD）

```gherkin
Feature: blue/green runnerの完了通知を受けて速報比較依頼を作成する - バックエンドワーカーティア

  Scenario: blue/green双方が揃った未依頼job_idから速報比較依頼を作成する
    Given execution_specs に run_id "run-20260817-020" job_id "JOB-BATCH-20" が存在する
    And execution_specs に run_id "run-20260817-021" job_id "JOB-BATCH-20" が存在する
    And runner_results に run_id "run-20260817-020" slot_type "blue" role "background" status "SUCCEEDED" が存在する
    And runner_results に run_id "run-20260817-021" slot_type "green" role "background" status "SUCCEEDED" が存在する
    And rapid_crosscheck_requests に job_id "JOB-BATCH-20" のレコードが存在しない
    And feature flag設定 RAPID_CROSSCHECK_MODE が "on" である
    When worker presentation層がCronJobトリガーを受け付ける
    Then gateway層は rapid_crosscheck_requests へ job_id "JOB-BATCH-20" blue_run_id "run-20260817-020" green_run_id "run-20260817-021" status "REQUESTED" をINSERTし、構造化ログに処理件数1件を記録する

  Scenario: blue側のみ完了している場合はペアリング未完了として依頼を作成しない
    Given execution_specs に run_id "run-20260817-022" job_id "JOB-BATCH-21" が存在する
    And runner_results に run_id "run-20260817-022" slot_type "blue" role "background" status "SUCCEEDED" が存在する
    And 同一job_id "JOB-BATCH-21" のslot_type "green" のrunner_resultsはstatus "RUNNING"でまだ確定していない
    And feature flag設定 RAPID_CROSSCHECK_MODE が "on" である
    When worker presentation層がCronJobトリガーを受け付ける
    Then gateway層は job_id "JOB-BATCH-21" の速報比較依頼をINSERTせず、構造化ログに処理件数0件を記録する
```
