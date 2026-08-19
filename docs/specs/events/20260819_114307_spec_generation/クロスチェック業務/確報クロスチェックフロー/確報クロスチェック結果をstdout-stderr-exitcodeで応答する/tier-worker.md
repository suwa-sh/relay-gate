# 確報クロスチェック結果をstdout/stderr/exitcodeで応答する - tier-workerティア仕様

## 変更概要

確報比較依頼のstatus（SUCCEEDED/FAILED）を標準出力・標準エラー・終了コードのみに変換してジョブスケジューラへ応答する処理をtier-workerに追加する。比較結果・差分件数・レポートURIなどの詳細は一切含めない。

## イベント処理仕様

### 確報クロスチェック結果応答

- **トリガー**: 確報比較依頼のstatusがSUCCEEDED/FAILEDへ確定した直後の応答トリガー（CronJobで実行された確報比較実行処理の完了直後に同一プロセス内で呼び出される。lease/claim取得は不要）
- **入力**: RDBの `final_crosscheck_requests` テーブル（run_idに対応するstatus）
- **出力**: ジョブスケジューラへの標準出力・標準エラー・終了コード（差分件数・レポートURIは出力しない）
- **処理フロー**:
  1. run_idを受け取り、`final_crosscheck_requests` からstatusをSELECTする
  2. status=SUCCEEDEDならexitcode=0、status=FAILEDならexitcode=1に変換する
  3. status=REQUESTED/CLAIMED/RUNNINGなど未確定の場合はエラー応答（exitcode=1、「未完了」メッセージ）とする
  4. 標準出力（正常終了時）または標準エラー（異常終了時）に固定文言のみを出力し、差分件数・レポートURI等は一切含めない
  5. 決定したexitcodeでプロセスを終了する

#### エラーハンドリング

| エラー種別 | リトライ | 説明 |
|-----------|---------|------|
| status未確定（RUNNING等） | No | 標準エラーへ「確報クロスチェックが未完了です」を出力し終了コード1で応答する |
| run_id不明（レコード不存在） | No | 標準エラーへエラーメッセージを出力し終了コード1で応答する |
| RDB接続エラー | Yes（1回のみ再試行） | usecase層で1回だけログ出力し、再試行失敗時は終了コード1で応答する |

## データモデル変更

### final_crosscheck_requests

| カラム | 型 | 説明 | 変更種別 |
|--------|---|------|---------|
| run_id | VARCHAR | 確報比較依頼の一意識別子（PK） | 変更なし（参照のみ） |
| status | VARCHAR | REQUESTED/CLAIMED/RUNNING/SUCCEEDED/FAILED/ABORTED | 変更なし（参照のみ、本UCは応答専用で状態遷移させない） |

## ビジネスルール

- 応答は標準出力・標準エラー・終了コードの3項目のみに限定し、比較結果・差分件数・レポートURI等の詳細を一切含めない（確報比較依頼の応答契約）
- 確報クロスチェック結果は日次のリリース判断の唯一の正本であり、応答内容に曖昧さ（部分成功等の中間状態）を含めない。statusが未確定の場合は必ずエラー応答とする

## CLI 出力/画面表示マッピング

### 確報結果応答画面

- **route**: /cli/final-crosscheck/respond
- **表示要素とコンポーネントマッピング**:

| 要素 | 種別 | デザインシステムコンポーネント | 説明 |
|------|------|------------------------------|------|
| 応答結果パネル | パネル | RunnerResultPanel（variant: foreground） | stdout/stderr/exitCodeのみをターミナル調に表示し、比較結果・差分件数・レポートURIは表示しない |

- **デザイントークン参照**:

| 用途 | トークン | 値 |
|------|---------|---|
| ターミナルパネル背景 | var(--color-slate-900) | slate-900 (#0F172A) |
| ターミナルパネル文字色 | var(--color-slate-100) | slate-100 (#F1F5F9) |
| ターミナルパネルフォント | var(--font-family-ff-mono) | JetBrains Mono, ui-monospace, SFMono-Regular, Menlo, monospace |

- **UIロジック**: 状態管理は都度RDBの最新statusを参照するのみでクライアント側キャッシュを持たない。バリデーションはrun_id存在チェックとstatus確定チェック。ローディングは応答トリガー発火時点でstatusが確定済みであることを前提とし待機表示は行わない。エラーハンドリングはRunnerResultPanelのforeground variantの制約（stdout/stderr/exitCodeのみ表示）に従い、詳細情報を画面上にも一切表示しない

## 共通コンポーネント参照

参照元: `docs/specs/events/20260818_144847_spec_generation/_cross-cutting/ux-ui/common-components.md`（実行結果ターミナル表示パターン）

| コンポーネント | インポートパス | variant | Props マッピング |
|---|---|---|---|
| RunnerResultPanel | src/components/domain/RunnerResultPanel.tsx | foreground | runId←run_id, stdout/stderr/exitCode←確定statusから変換した固定文言（比較結果・差分件数・レポートURIは含めない） |

適用パターン: 実行結果ターミナル表示パターン（foreground variant。stdout/stderr/exitCodeのみをレンダリングし詳細は一切表示しない。運用性NFR「応答はstdout/stderr/exitcodeのみに限定」に対応）

## ティア完了条件（BDD）

```gherkin
Feature: 確報クロスチェック結果をstdout/stderr/exitcodeで応答する - tier-worker

  Scenario: presentation層がSUCCEEDEDのstatusをexitcode 0に変換して応答する
    Given execution_specs に run_id "e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f"、job_id "daily-settlement"、job_map_version "v1.4.0"、hang_detect_limit_minutes 30 の行が存在する
    And final_crosscheck_requests に run_id "e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f" status "SUCCEEDED" のレコードが存在する
    When tier-workerのpresentation層が RespondFinalCrossCheckResultCommand(run_id="e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f") を受け取る
    Then domain層はexitcode 0を返し、presentation層は差分件数・レポートURIを含めずに標準出力へ固定文言を出力し終了コード 0 で終了する

  Scenario: presentation層がstatus未確定の場合にエラー応答する
    Given execution_specs に run_id "e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f"、job_id "daily-settlement"、job_map_version "v1.4.0"、hang_detect_limit_minutes 30 の行が存在する
    And final_crosscheck_requests に run_id "e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f" status "RUNNING" のレコードが存在する
    When tier-workerのpresentation層が RespondFinalCrossCheckResultCommand(run_id="e57a03c8-9d21-4b6f-8a34-1c7e5b9d206f") を受け取る
    Then presentation層は標準エラーへ "確報クロスチェックが未完了です" を出力し終了コード 1 で終了する
