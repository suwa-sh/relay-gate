# relay-gate 引き継ぎ

更新日時: 2026-08-18 10:50 JST

## この文書の目的

別セッションで、feature flag に基づく slot 選択・起動機能のレビュー後対応と、distillery feedback pipeline の続きから安全に再開するための引き継ぎ資料。

## リポジトリ

- ルート: `/Users/suwa_sh/src/github.com/suwa-sh/relay-gate`
- ブランチ: `feature/select-and-launch-slots-by-feature-flags`
- pipeline 開始時の固定 HEAD: `a1dfc90cc4052435ec436f2d36f0b96962685ffe`
- 未コミット差分あり。今回の architecture / infrastructure / pipeline 証跡であり、破棄しないこと
- `docs/specs/**` は pipeline 失敗時に開始前へ戻してあり、現在は差分なし
- `docs/pipeline/run-lease.json` は存在せず、lease は解放済み
- commit / push / PR は未実施

作業開始時は、必ず次を実行してからルートの `CLAUDE.md` を全文読む。

```bash
git rev-parse --show-toplevel
git branch --show-current
git status --short
```

## ユーザーが確定した事項

レビューで確認した内容は次の3点。

1. feature flag に基づく slot 選択・起動機能を承認する
2. RDB 製品は PostgreSQL とする
3. slot 起動操作の構造化監査ログを追記する

補足:

- PostgreSQL の選択は確定済みであり、製品選定をやり直す必要はない
- 監査ログは CLI の既存 stdout 契約を変更しない
- 監査イベントから認証情報、引数実値、stdout / stderr 本文を除外する
- 保持期間は6か月、`run_id` / `parent_run_id` で照会可能にする
- 人との認識合わせが終わるまでは squash / push / PR を行わない
- 最終的に squash する場合のコミットメッセージは `feat: feature flag設定に基づきslotを選択して起動する`
- 実装工程へ戻る場合、implementer は `gpt-5.6-terra` を使用する

## 実行した pipeline

元のコマンド:

```text
/distillery:dist-pipeline docs/impl/latest/6078c4ed/feedback-requests/20260817_234841_impl_feedback_6078c4ed.md --recommended-auto
```

実行 identity:

- feedback request ID: `20260817_234841_impl_feedback_6078c4ed`
- input SHA-256: `bc64202288e80a7c6a299affcff26d45d91238a851ec5483b2d9eecb1bdabb54`
- run ID: `feedback-20260817_234841_impl_feedback_6078c4ed-20260818_092759-21457`
- attempt: `2`
- model: `gpt-5.6-sol`
- 最終状態: `blocked`

正本:

- 状態: `docs/pipeline/feedback-runs/20260817_234841_impl_feedback_6078c4ed/status.json`
- 結果: `docs/pipeline/feedback-runs/20260817_234841_impl_feedback_6078c4ed/result.json`
- 仕様整合失敗イベント: `docs/pipeline/events/20260818_103940_feedback_stage_spec/event.json`
- 終端イベント: `docs/pipeline/events/20260818_104217_feedback_run_aborted/event.json`

この run は終端済みである。同じ feedback ID と input SHA で続行せず、未解決事項を入力にした新しい feedback request を作成すること。

## 完了している変更

### アーキテクチャ設計

次の方針を反映済み。

- PostgreSQL の追記専用監査テーブル
- ハッシュチェーンによる改ざん検知
- 6か月保持
- `run_id` / `parent_run_id` による実行系譜照会
- 外部起動前の監査永続化失敗時は起動中止
- 外部起動後の結果永続化失敗時は再試行・照合対象

主な証跡:

- `docs/arch/events/20260818_090120_arch_audit_contract_feedback/`
- `docs/arch/latest/decisions/arch-decision-003.yaml`

### インフラ設計

次を MCL の on-prem 設計へ反映済み。

- PostgreSQL 監査永続化
- 監査ハッシュチェーン
- 実行系譜索引
- 機密情報の除外
- 起動後失敗用のローカル永続 outbox と reconciliation

主な証跡:

- `docs/infra/events/20260818_093020_infra_product_design/`
- `docs/infra/latest/docs/cloud-context/decisions/product/product-decision-audit-persistence.yaml`

### デザインシステム

表示契約・画面・コンポーネントへの影響なしと判定済み。`docs/design/latest/` は変更していない。

- 証跡: `docs/design/events/20260818_094841_design_system_feedback_disposition/feedback-disposition.json`

## 未解決で、仕様生成を止めた事項

### 1. 再実行の同一性が矛盾している

- `docs/usdm/latest/requirements.yaml:289` 付近は rapid-crosscheck の比較依頼を新規作成するとしている
- `docs/rdra/latest/状態.tsv:20` 付近は既存依頼を `REQUESTED` へ差し戻す状態遷移としている
- 新しい `run_id` を作るのか、既存 `run_id` を再利用するのかが二重正本になっている

推奨: 新しい `run_id` を発行し、`parent_run_id` で元依頼と関連付ける。既存履歴を上書きしない。

### 2. PostgreSQL の partition 契約が DDL として成立しない

- `docs/infra/latest/docs/mcl/product/output/product-impl-onprem.yaml:81` 付近は `occurred_at` による月次 partition を要求している
- 同時に `event_id` 単独 PK と `(run_id, slot, attempt_id, event_name)` UNIQUE を要求している
- PostgreSQL の partitioned table では PRIMARY KEY / UNIQUE に partition key を含める必要があるため、そのままでは作成不能

推奨: 初期構成では非 partition の `audit_logs` を採用し、`occurred_at` / `run_id` 索引と専用保守権限による6か月保持を定義する。実測負荷が必要になった時点で registry 分離を含む partition 設計へ移行する。

### 3. slot 別実行設定と試行 identity が上位モデルにない

- `docs/arch/latest/arch-design.yaml:748` 付近の execution spec は単一 host / impl_version を前提としている
- Runner 実行結果は `(run_id, role_type)` が主キーで、同一 run の blue / green を別試行として識別できない
- `attempt_id`、`attempt_no`、起動受付、結果不明状態がない

推奨:

- run 共通の execution spec と slot 別設定を分離する
- Runner 実行結果は slot と `attempt_id` を含む identity にする
- `STARTING` / `RUNNING` / `SUCCEEDED` / `FAILED` / `UNKNOWN` / `ABORTED` を正式状態として定義する

### 4. Runner 実行結果の履歴方針が矛盾している

- `docs/arch/latest/arch-design.yaml:571` 付近は履歴 INSERT と snapshot UPSERT の併用を要求する
- 既存 spec decision は snapshot-only を採用している

推奨: append-only の `runner_result_events` と現在状態の `runner_results` snapshot を同一 transaction で更新する。

## 仕様生成で確認済みだった修正候補

上記の上流矛盾が解消された後、仕様生成時に次も反映する。

- USDM acceptance criteria から UC / Scenario / tier Scenario への逆引き行列
- feature flag 起動から background 起動 UC への依存宣言
- execution spec、`runner_results STARTING`、起動前監査を同一 transaction にする
- CLI の background / rapid-crosscheck dispatch ごとの環境変数・終了コード契約
- 監査イベントの `actor` / `operation` / `outcome` 等への統一
- `run_id` 単位の hash-chain head を直列化する lock 契約
- Gherkin の UUID / FK 前提を実行可能な具体値へ修正

これらは一度作成・機械検証まで進めたが、上流矛盾を残した成功証跡にしないため、`docs/specs/**` からすべてロールバック済み。

## 推奨する再開手順

1. 新しい feedback request を作る。上記4件を requirements / RDRA / architecture / infrastructure の整合対象として含める
2. 次の推奨セットを人が確認する
   - 再実行は新しい `run_id` + `parent_run_id`
   - 監査テーブルは初期は非 partition
   - slot 別 execution spec + attempt identity + `UNKNOWN`
   - append-only history + current snapshot
3. `gpt-5.6-sol` で新しい feedback request に対して `dist-pipeline --recommended-auto` を実行する
4. requirements / RDRA → architecture → infrastructure → spec の順で矛盾が閉じたことを確認する
5. spec 生成後に datastore validator だけでなく、実 PostgreSQL DDL の作成試験を追加する
6. 人向け review HTML を再生成し、機能承認と追加決定を認識合わせする
7. 認識合わせ完了後に実装工程へ戻り、implementer は `gpt-5.6-terra` を使う
8. 全レビュー完了後に squash、push、PR を行う

## 検証結果

pipeline 終端証跡の検証:

```bash
node /Users/suwa_sh/.claude/plugins/cache/suwa-sh-claude-plugins/distillery/1.4.4/skills/dist-pipeline/scripts/verifyFeedbackResult.js \
  docs/pipeline/feedback-runs/20260817_234841_impl_feedback_6078c4ed
```

結果: `PASS: feedback result coverage and lineage are valid`

dist-pipeline 回帰テスト:

```text
46 tests / 46 pass / 0 fail
```

その他:

- architecture validator: PASS
- infrastructure event/latest validator: PASS
- MCL mapping coverage: 12要素 PASS
- infrastructure conformance: 17件 PASS
- spec の途中生成時検証: YAML / spec event / RDB schema / model summaries / Mermaid / Redocly はPASS。ただし意味反証で停止したため成功証跡には不採用
- `git diff --check`: PASS

## インストール済み dist-pipeline の一時補正

実行中に distillery `1.4.4` の検証器で2件の不具合を確認し、インストールキャッシュへ最小補正した。

対象:

- `/Users/suwa_sh/.claude/plugins/cache/suwa-sh-claude-plugins/distillery/1.4.4/skills/dist-pipeline/scripts/verifyFeedbackResult.js`
  - frozen routing 再構築時に `routing.routing_basis.model_id` を渡すよう補正
- `/Users/suwa_sh/.claude/plugins/cache/suwa-sh-claude-plugins/distillery/1.4.4/skills/dist-pipeline/scripts/planFeedbackRequest.js`
  - domain latest tree の hash 対象から `node_modules` を除外

補正後、実 run の終端検証と46件の回帰テストはPASS。

注意: marketplace 正本 `/Users/suwa_sh/.claude/plugins/marketplaces/suwa-sh-claude-plugins/plugins/distillery/` にはまだ反映していない。恒久対応する場合は、正本へテストとともに反映し、plugin version を `1.4.5` 以上へ上げ、commit / push / marketplace update / uninstall / install を行うこと。

## 関連する以前の運用決定

- review HTML は補助資料であり、`docs/impl/**/review/*.html` で git 管理対象外
- HTML 再生成で実装証跡の SHA 整合を取り直さない
- 図解は `diagram-design` skill を使用する
- `diagram-design` が未導入なら、dist-impl-run は停止してインストールを促す
- ユーザー向け文書では内部工程コードではなく、アーキテクチャ設計、仕様生成、受入テスト等の意味のある名称を使う

