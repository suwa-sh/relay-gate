---
schema_version: distillery.feedback-request/v1
feedback_id: 20260818_113601_impl_feedback_6078c4ed
created_at: 2026-08-18T11:36:01+09:00
source: distillery-impl
uc_id: 6078c4ed
supersedes: 20260817_234841_impl_feedback_6078c4ed
---

# 実装からの変更要求

本書は公開済み feedback request `20260817_234841_impl_feedback_6078c4ed` の訂正版である。旧 request を入力にした差分反映は、アーキテクチャ設計とインフラ設計まで完了したが、仕様生成の整合検証で上流正本間の矛盾4件が確認され、完了しなかった。本書はその4件の整合と、整合後に仕様生成で併せて反映する修正候補を変更要求として再定義する。

次の事項はユーザーレビューで確定済みであり、再選定を求めない。前提として扱うこと。

- RDB 製品は PostgreSQL とする
- slot 起動操作の構造化監査ログを追記する(CLI の既存 stdout 契約は変更しない)
- 監査イベントから認証情報、起動引数の実値、stdout / stderr 本文を除外する
- 監査ログの保持期間は6か月とする
- 監査ログは run_id / parent_run_id で照会可能にする

## CR-6078c4ed-003: 再実行の同一性の二重正本を解消する

- severity: blocker
- related_ids: [SPEC-008-03, CTP-006]
- related_files: [docs/usdm/latest/requirements.yaml, docs/rdra/latest/状態.tsv]

### 観測した事実

`docs/usdm/latest/requirements.yaml` の SPEC-008-03(289行付近)は、rapid-crosscheck の再実行で「業務ジョブを再実行せず、比較依頼だけを新規作成する」と規定している。一方 `docs/rdra/latest/状態.tsv`(20行付近)は、SUCCEEDED / FAILED / ABORTED の既存依頼を REQUESTED へ差し戻す状態遷移として再実行を定義している。仕様生成の整合検証で、この2つが両立しない二重正本であると確認され、仕様の再整合を完了できなかった。

### 現在の仕様と問題

再実行時に新しい run_id を発行するのか、既存 run_id の依頼を差し戻して再利用するのかが、要求正本と RDRA 状態モデルで矛盾している。このままでは、比較依頼の識別子発行規則、既存履歴の上書き有無、監査ログの実行系譜(run_id / parent_run_id)の意味を実装側で一意に決められない。

### 変更してほしいこと

推奨案を採用する: 再実行は新しい run_id を発行し、parent_run_id で元依頼と関連付ける。既存依頼のレコードと履歴は上書きしない。これに合わせて、RDRA の状態遷移を「完了済み依頼の REQUESTED への差し戻し」から「元依頼を参照する新規依頼の作成」へ改め、USDM と RDRA を同一の再実行 identity に整合させる。代替案は既存 run_id の差し戻し再利用だが、履歴の上書きが生じ、確定済みの run_id / parent_run_id 照会前提とも整合しないため推奨しない。

### 完了条件

requirements と RDRA が同じ再実行 identity(新 run_id + parent_run_id 関連付け、既存履歴の不変)を規定し、比較依頼の再実行を実装者が推測なしに一意に実装できる。

## CR-6078c4ed-004: 監査テーブルの partition 契約を PostgreSQL で成立する DDL に改める

- severity: blocker
- related_ids: [product.audit_event_persistence, CTP-004]
- related_files: [docs/infra/latest/docs/mcl/product/output/product-impl-onprem.yaml, docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml]

### 観測した事実

`docs/infra/latest/docs/mcl/product/output/product-impl-onprem.yaml` の slot 起動監査イベントストア定義(81行付近)は、occurred_at による月次 partition と、event_id 単独の主キーおよび `(run_id, slot, attempt_id, event_name)` の一意制約を同時に要求している。PostgreSQL の partitioned table は PRIMARY KEY / UNIQUE 制約に partition key を含めることを必須とするため、この組み合わせは実 DDL として作成できない。仕様生成の整合検証でこの不成立が確認された。

### 現在の仕様と問題

インフラ実装仕様のままでは監査テーブルの CREATE TABLE が成立せず、仕様生成でデータストア契約(rdb-schema)へ落とし込めない。一意制約に partition key を加えて回避すると、再試行の冪等化に使う一意性が弱まるという別の問題が生じる。

### 変更してほしいこと

推奨案を採用する: 初期構成では非 partition の追記専用 audit_logs(監査イベントテーブル)を採用し、occurred_at / run_id(および parent_run_id)の索引と、専用保守権限による6か月保持の運用を定義する。実測負荷が必要になった時点で、registry 分離を含む partition 設計へ移行する方針を明記する。代替案は一意制約へ occurred_at を含めて月次 partition を維持する構成だが、冪等一意性が弱まるため推奨しない。確定済みの除外項目(認証情報、引数実値、stdout / stderr 本文)、追記専用の権限境界、ハッシュチェーンによる改ざん検知は維持する。

### 完了条件

定義された監査テーブル契約が実 PostgreSQL でそのまま CREATE TABLE でき、主キー・一意制約・索引・6か月保持・追記専用権限が矛盾なく一体で成立する。

## CR-6078c4ed-005: slot 別実行設定と起動試行 identity を上位モデルに定義する

- severity: blocker
- related_ids: [E-001, CTP-006]
- related_files: [docs/arch/latest/arch-design.yaml, docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml]

### 観測した事実

`docs/arch/latest/arch-design.yaml` の execution spec エンティティ(748行付近)は、単一の host / impl_version を前提としている。Runner 実行結果は `(run_id, role_type)` を主キーとしており、同一 run で blue と green を同時に起動した場合に、同一 role の起動試行を別試行として識別できない。attempt_id、attempt_no、起動受付、結果不明状態は上位モデルに存在しない。この欠落は実装の最終検証と仕様生成の整合検証の双方で確認された。

### 現在の仕様と問題

blue / green の slot ごとに host と impl_version が異なる並行稼働を、単一値前提の execution spec では表現できない。また Runner 実行結果の主キーでは起動試行の識別ができず、timeout 後に結果不明の試行を FAILED と区別して扱えない。このため runner_results の識別規則と状態遷移を実装側で一意に決められない。

### 変更してほしいこと

推奨案を採用する: run 共通の execution spec と slot 別の実行設定(host、exec_user、script、work_dir、impl_version 等)を分離して定義する。Runner 実行結果の identity は slot と attempt_id を含むキーに改め、起動試行ごとに識別できるようにする。実行状態として STARTING / RUNNING / SUCCEEDED / FAILED / UNKNOWN / ABORTED を正式に定義し、timeout 後は推測で FAILED を確定せず UNKNOWN として回復処理を選べるようにする。

### 完了条件

同一 run の blue / green 各 slot の実装版と起動試行を run_id から一意に識別でき、timeout 後の結果不明状態を含む状態遷移が上位モデルとデータストア契約で一致して定義されている。

## CR-6078c4ed-006: Runner 実行結果の履歴方針の矛盾を解消する

- severity: blocker
- related_ids: [LR-002]
- related_files: [docs/arch/latest/arch-design.yaml, docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml]

### 観測した事実

`docs/arch/latest/arch-design.yaml` のレイヤールール LR-002(571行付近)は、Runner 実行結果の永続化を履歴 INSERT と snapshot UPSERT の併用(Event/Snapshot 併用パターン)と規定している。一方、既存のデータストア設計判断は snapshot-only を採用しており、仕様生成の整合検証で両者の矛盾が確認された。

### 現在の仕様と問題

アーキテクチャ設計とデータストア設計判断で永続化方針が食い違っているため、repository 実装(historyAdapter / snapshotAdapter の要否)とテーブル構成を一意に決められない。監査の実行系譜照会は履歴の保全を前提とするため、snapshot-only では起動試行の経過を追跡できない。

### 変更してほしいこと

推奨案を採用する: append-only の `runner_result_events`(履歴)と現在状態の `runner_results`(snapshot)を定義し、同一 transaction で履歴 INSERT と snapshot UPSERT を更新する方式に統一する。データストア設計判断を snapshot-only からこの併用方式へ更新する。代替案はアーキテクチャ側を snapshot-only に合わせる変更だが、起動試行の経過追跡と監査系譜が弱まるため推奨しない。

### 完了条件

アーキテクチャ設計とデータストア契約の永続化方針が一致し、Runner 実行結果の履歴と現在状態を同一 transaction で矛盾なく更新する実装を推測なしに書ける。

## CR-6078c4ed-007: 上流整合後の仕様再生成で確認済みの修正候補を反映する

- severity: spec-gap
- related_ids: [SPEC-001-01, CTP-004, LP-002]
- related_files: [docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml, docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml]

### 観測した事実

旧 request を入力にした仕様の再生成では、次の修正候補を一度作成し機械検証まで通過させたが、上流矛盾(CR-6078c4ed-003〜006)を残したまま成功証跡にしないため、仕様側の成果物からすべてロールバックした。

- USDM acceptance criteria から UC / Scenario / tier Scenario への逆引き行列
- feature flag 起動から background 起動 UC への依存宣言
- execution spec、`runner_results` の STARTING 記録、起動前監査を同一 transaction にする規定
- CLI の background / rapid-crosscheck dispatch ごとの環境変数・終了コード契約
- 監査イベントのフィールドを `actor` / `operation` / `outcome` 等へ統一する定義
- `run_id` 単位の hash-chain head を直列化する lock 契約
- Gherkin の UUID / FK 前提を実行可能な具体値へ修正

### 現在の仕様と問題

これらの候補は現在の仕様に存在しない。上流4件だけを整合させても、仕様のトレーサビリティ、UC 間依存、監査・transaction・lock の契約、および受け入れシナリオの実行可能性に不足が残る。

### 変更してほしいこと

CR-6078c4ed-003〜006 の上流整合が完了した後の仕様再生成で、上記7項目を併せて反映する。各項目の内容は新規の要求ではなく、確認済みの修正候補の再反映である。

### 完了条件

7項目がそれぞれ仕様成果物に反映され、機械検証を通過し、上流の整合済み内容(再実行 identity、非 partition 監査テーブル、slot 別設定と試行 identity、履歴 + snapshot 併用)と矛盾しない。
