# blue/green runnerの完了通知を受けて速報比較依頼を作成する - バックエンドワーカーティア仕様

## 変更概要

CronJob定期実行により、blue/green background runnerの完了（Runner実行結果のexit_code確定）を検知し、job_id単位でblue/green双方の完了ペアリングが揃った未依頼ジョブについて速報比較依頼を新規run_id・REQUESTED状態で作成する処理を追加する。比較対象はblue_run_id/blue_attempt_id/green_run_id/green_attempt_idの4項目で特定する。runner_resultsにはjob_id属性が存在しないため、run_idを介してexecution_specsテーブルとJOINしてjob_idを取得する。

## イベント処理仕様

### 速報比較依頼作成worker
- **トリガー**: CronJob定期実行（1分間隔想定）
- **入力**: `runner_results` テーブル（role_type='background' AND status IN ('SUCCEEDED','FAILED')）と `execution_specs` テーブル（run_idでJOINしjob_idを取得）から、(job_id, blue_run_id, blue_attempt_id, green_run_id, green_attempt_id) の組が `rapid_crosscheck_requests` に未存在の候補、および `comparison_definitions` テーブル（job_idと依頼作成時点で有効な世代を解決）
- **出力**: `rapid_crosscheck_requests` テーブルへの新規INSERT（run_id新規発番、parent_run_id=NULL、comparison_definition_valid_from=解決した比較定義世代のvalid_from、status=REQUESTED）
- **処理フロー**:
  1. presentation層がCronJobトリガーを受け付ける
  2. usecase層が `CreateRapidCrosscheckRequestCommand` を発行する
  3. gateway層が `runner_results` と `execution_specs` を run_id でJOINし、role_type='background'かつstatus確定済み（SUCCEEDED/FAILED）の起動試行からjob_id単位の候補を検索する
  4. domain層がjob_id単位にblue（slot_type=blue）・green（slot_type=green）双方のRunner実行結果がSUCCEEDED/FAILEDで確定しているかをペアリング判定する。片方のみ確定・UNKNOWN・ABORTEDの場合は当該job_idを対象外とし次回サイクルで再判定する
  5. domain層がfeature flag設定（RAPID_CROSSCHECK_MODE）を判定し、onかつペアリング完了の場合のみ新規run_idを発番して速報比較依頼エンティティ（status=REQUESTED）を生成する
  6. gateway層が `comparison_definitions` から対象job_idの依頼作成時点で有効な世代（valid_from <= 実行時点、かつ valid_to IS NULL または 実行時点 < valid_to）を1件解決し、そのvalid_fromをcomparison_definition_valid_fromとして依頼エンティティへ確定する。該当世代が無い場合は標準エラーへ記録し当該job_idの依頼作成をスキップする
  7. gateway層が `rapid_crosscheck_requests` へINSERTする（comparison_definition_valid_fromを含む）。(job_id, blue_run_id, blue_attempt_id, green_run_id, green_attempt_id) の一意制約違反は依頼済みとして冪等スキップする
  8. presentation層が処理件数・対象job_id一覧を構造化ログへ出力する
- **エラーハンドリング**:

| エラー種別 | リトライ | 説明 |
|-----------|---------|------|
| RDB接続エラー | Yes（次回CronJob実行時に再試行） | 標準エラーへ記録し終了コード1で終了。二重作成防止は比較対象試行ペアの一意性制約に依存する |
| 一意性制約違反（同一比較対象試行ペアの重複INSERT） | No（正常系として無視） | 楽観ロック競合ログとして記録し処理を継続する（LR-008準拠） |
| RAPID_CROSSCHECK_MODE=off | No（正常系） | 依頼を作成せず処理件数0件として正常終了する |
| blue/greenペアリング未完了 | No（正常系） | 依頼を作成せず当該job_idを次回サイクルで再判定する |
| 比較定義の該当世代なし | Yes（次回CronJob実行時に再判定） | 標準エラーへ記録し当該job_idの依頼作成をスキップする。有効な世代が登録された後の実行サイクルで依頼を作成する |

## データモデル変更

### rapid_crosscheck_requests（速報比較依頼）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | UUID | 速報比較依頼の一意識別子（PK）。作成時に新規発番する | 追加（INSERT対象） |
| parent_run_id | UUID | リラン元依頼のrun_id。通常作成時はNULL | 追加（INSERT対象、初期値NULL） |
| job_id | VARCHAR | 対象ジョブのjob_id（execution_specs.job_idと同一） | 追加（INSERT対象） |
| blue_run_id | UUID | 比較対象のblue slot側background実行のrun_id。同一runの2 slot起動時はgreen_run_idと同値 | 追加（INSERT対象） |
| green_run_id | UUID | 比較対象のgreen slot側background実行のrun_id | 追加（INSERT対象） |
| blue_attempt_id | VARCHAR | 比較対象としたblue slot側background起動試行のattempt_id | 追加（INSERT対象） |
| green_attempt_id | VARCHAR | 比較対象としたgreen slot側background起動試行のattempt_id | 追加（INSERT対象） |
| comparison_definition_valid_from | DATETIME | 依頼作成時点で解決した比較定義世代のvalid_from。(job_id, comparison_definition_valid_from) で comparison_definitions(job_id, valid_from) を参照するFK。比較内容をこの世代へ固定する | 追加（INSERT対象） |
| requested_at | DATETIME | 依頼作成日時 | 追加（INSERT対象、CronJob実行時刻） |
| status | VARCHAR | REQUESTED/CLAIMED/RUNNING/SUCCEEDED/FAILED/ABORTED | 追加（初期値REQUESTED） |
| lease_expires_at | DATETIME | lease期限（nullable） | 追加（初期値NULL） |
| worker_id | VARCHAR | 取得中のworker識別子（nullable） | 追加（初期値NULL） |

### runner_results（Runner実行結果）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | UUID | 対象実行のrun_id（複合PKの一部） | 参照のみ |
| slot_type | VARCHAR | blue/green（複合PKの一部。ペアリング判定に使用） | 参照のみ |
| role_type | VARCHAR | foreground/background/rapid-crosscheck（background限定検索） | 参照のみ |
| attempt_id | VARCHAR | 比較対象試行の特定に使用（複合PKの一部） | 参照のみ |
| status | VARCHAR | STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED（SUCCEEDED/FAILED限定検索） | 参照のみ |

### execution_specs（execution-spec.json、参照のみ）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | UUID | Runner実行結果とのJOINキー | 参照のみ |
| job_id | VARCHAR | job_id単位のペアリング判定・速報比較依頼のキーとして使用 | 参照のみ |

### comparison_definitions（比較定義、参照のみ）

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| job_id / valid_from | VARCHAR / DATETIME | 比較定義世代のidentity（複合PK）。依頼作成時に有効な世代を解決しvalid_fromを依頼へ保存する | 参照のみ |
| valid_to | DATETIME | 有効期間の終了日時（現行世代はNULL）。valid_from <= 実行時点 < valid_to（NULLは無期限）の条件で世代を解決する | 参照のみ |

## ビジネスルール

- RAPID_CROSSCHECK_MODEがoffの場合、blue/green runnerからの完了通知送信・速報管理DBへの接続・書込みを一切行わない（依頼作成自体をスキップする）
- job_idはrunner_resultsに属性として存在しないため、必ずexecution_specsをrun_idでJOINして取得する
- 同一job_idについて、blue（slot_type=blue）・green（slot_type=green）双方のRunner実行結果（role_type=background）がSUCCEEDED/FAILEDで確定して初めて速報比較依頼を作成する（ペアリング判定）。UNKNOWN・ABORTEDは確定扱いとせず依頼を作成しない
- 比較対象はblue_run_id/blue_attempt_id/green_run_id/green_attempt_idの4項目で特定する。blueとgreenを同一runの2 slotとして起動した場合はblue_run_idとgreen_run_idが同値になる
- 依頼作成時点でjob_idと有効期間からcomparison_definitionsの有効な世代を1件解決し、そのvalid_fromをcomparison_definition_valid_fromとして依頼に保存する（比較内容の世代固定。SPEC-012-03）。現行世代の部分一意索引と有効期間の排他制約により該当世代は常に1件以下に保証され、該当世代が無い場合は当該job_idの依頼を作成しない
- 重複防止は (job_id, blue_run_id, blue_attempt_id, green_run_id, green_attempt_id) の一意制約で担保する（CTP-006冪等性方針。blue/greenの完了順に依存せず1件だけ作成される）
- 依頼のrun_idは作成時に新規発番する。再実行（リラン）では同一run_idを差し戻さず、新しいrun_idの依頼を新規作成しparent_run_idで元依頼へ関連付ける（元依頼のレコード・状態・履歴は不変。UC「execution-spec.jsonの実行設定を保ったまま再実行する」の責務）
- CLI応答は10秒以内、スループットは10TPS程度を目安とする（CTP-009）

## CLI 出力/画面表示マッピング

### 速報比較依頼作成画面

- **route**: /cli/rapid-crosscheck/create
- **表示要素とコンポーネントマッピング**:

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 作成された速報比較依頼一覧行 | テーブル行 | CrossCheckRequestRow（variant: rapid） | 新規作成されたrun_id/job_id/blue_run_id/blue_attempt_id/green_run_id/green_attempt_id/status=REQUESTEDを表示 |
| 作成完了通知 | バナー | Banner（variant: info） | 「REQUESTED状態への遷移を即時反映する」（ux-design.md改善機会に対応） |

- **デザイントークン参照**:

| 用途 | トークン | 値 |
|------|---------|---|
| REQUESTED状態背景 | var(--color-amber-100) | #FEF3C7 |
| 作成完了バナー背景 | var(--color-blue-100) | #DBEAFE |

- **UIロジック**: 状態管理はCronJob実行のたびにステートレスに再計算する（DBの未依頼候補を都度検索）。バリデーションはRAPID_CROSSCHECK_MODEの参照のみで入力フォームは持たない。ローディングは将来ダッシュボードでのみ表示。エラーハンドリングは構造化ログ+終了コードで表現する

## 共通コンポーネント参照

参照元: `docs/specs/events/20260818_144847_spec_generation/_cross-cutting/ux-ui/common-components.md`（状態一覧+フィルターパターン）

| コンポーネント | インポートパス | variant | Props マッピング |
|---|---|---|---|
| CrossCheckRequestRow | src/components/domain/CrossCheckRequestRow.tsx | rapid | runId←run_id（依頼自身のrun_id。比較対象のblue_run_id/green_run_id・attempt_idは詳細列で別途表示）, jobIdOrTargetDate←job_id, state←status（作成時はREQUESTED固定）, leaseExpiry←lease_expires_at（作成時はNULL）, workerId←worker_id（作成時はNULL） |
| Banner | src/components/ui/Banner.tsx | info | 依頼作成完了メッセージ「REQUESTED状態への遷移を即時反映する」 |

適用パターン: 状態一覧+フィルターパターン（一覧表示）。中止依頼→対話確認の二段階パターンは対象外（本UCは自動作成のみで対話操作を持たない）

## ティア完了条件（BDD）

```gherkin
Feature: blue/green runnerの完了通知を受けて速報比較依頼を作成する - バックエンドワーカーティア

  Scenario: blue/green双方が揃った未依頼job_idから速報比較依頼を作成する
    Given execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement" の行が存在する
    And slot_execution_specs に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue") と (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green") の行が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="background", attempt_id="att-blue-0001", status="SUCCEEDED") の行が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001", status="SUCCEEDED") の行が存在する
    And rapid_crosscheck_requests に job_id="daily-settlement" の行が存在しない
    And comparison_definitions に (job_id="daily-settlement", valid_from="2026-08-01T00:00:00+09:00", valid_to=NULL, comparator_id="comparator-settlement-v1") の行が存在する
    And 環境変数 RAPID_CROSSCHECK_MODE が "on" である
    And 依頼run_idの発番が "c41d7e08-2b95-4f36-a8d1-5e7c93b204af" を返すよう固定されている
    And CronJob実行時点が "2026-08-17T10:00:00+09:00" である
    When worker presentation層がCronJobトリガーを受け付ける
    Then gateway層は rapid_crosscheck_requests へ (run_id="c41d7e08-2b95-4f36-a8d1-5e7c93b204af", job_id="daily-settlement", blue_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", blue_attempt_id="att-blue-0001", green_run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", green_attempt_id="att-green-0001", comparison_definition_valid_from="2026-08-01T00:00:00+09:00", status="REQUESTED") をINSERTし、構造化ログに処理件数1件を記録する

  Scenario: blue側のみ完了している場合はペアリング未完了として依頼を作成しない
    Given execution_specs に run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", job_id="daily-settlement" の行と slot_execution_specs の blue/green 行が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="blue", role_type="background", attempt_id="att-blue-0001", status="SUCCEEDED") の行が存在する
    And runner_results に (run_id="3f8c9d2e-5b41-4a7e-9c13-6d2a8b0f1e57", slot_type="green", role_type="background", attempt_id="att-green-0001", status="RUNNING") の行が存在する
    And 環境変数 RAPID_CROSSCHECK_MODE が "on" である
    When worker presentation層がCronJobトリガーを受け付ける
    Then gateway層は rapid_crosscheck_requests へINSERTせず、構造化ログに処理件数0件を記録する
```
