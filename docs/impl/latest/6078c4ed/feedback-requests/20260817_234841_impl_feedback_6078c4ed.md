---
schema_version: distillery.feedback-request/v1
feedback_id: 20260817_234841_impl_feedback_6078c4ed
created_at: 2026-08-17T23:48:41+09:00
source: distillery-impl
uc_id: 6078c4ed
---

# 実装からの変更要求

## CR-6078c4ed-001: slot 起動の相互運用境界を確定する

- severity: spec-gap
- related_ids: [SPEC-001-01, CTP-006]
- related_files: [docs/specs/latest/並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/tier-facade.md, docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

最終検証では、remote handshake、共有 execution-spec 配布、RDB 接続契約と gateway timeout、runner_results の識別を一意に実装できないことが確認された。ユーザーレビューで、本番の RDB 製品に PostgreSQL を採用することは決定した。現行実装は検証境界として JSON ジョブマップ、SQLite、PATH 上の ssh、共有パス、単一の impl_version を用いる。`runner_results` の主キーは `(run_id, role_type)` であり、同一 run の blue と green の同一 role を別起動試行として識別できない。

### 現在の仕様と問題

対象 UC はジョブマップ解決、RDB への記録、SSH 起動、execution-spec.json の一度だけの確定保存を求める。RDB 製品は PostgreSQL に決定したが、現行仕様には未反映であり、DSN 形式、driver、lock・transaction timeout は未決定である。また、ジョブマップ形式と必須項目、SSH 接続先・認証・リモート起動引数、共有ファイルの所有者と配送方式を定義していない。remote 側の受理・開始・冪等再送確認、および timeout 後の状態も未定義である。さらに、blue/green を同時に起動する際の slot 別 impl_version と、slot を含む runner_results の一意性規則が、execution_specs の単数 impl_version および現在の主キーと両立しない。

### 変更してほしいこと

ジョブマップの Schema と slot ごとの host、exec_user、script、work_dir、impl_version の表現を定義する。RDB 製品は PostgreSQL として仕様に反映し、DSN 形式、gateway/driver、lock・transaction timeout を定める。SSH の認証、接続先、非対話実行、remote 起動引数を定め、run_id を用いた launch request、受理、開始、冪等再送、timeout 後の状態（少なくとも STARTING と UNKNOWN を含む）の状態遷移を定義する。execution-spec の共有・配送責務と参照可能性を定義し、runner_results を slot ごとの起動試行と最終状態を識別できるキー・状態規則へ整合させる。

### 完了条件

job map、RDB、SSH、remote runner が同じ入力・識別子・状態遷移で相互運用できる。blue/green の各 slot の実装版と起動試行を run_id から区別でき、timeout 後も推測で FAILED を確定せず回復処理を選べる。共有 execution-spec を remote runner が一意に参照できる。

## CR-6078c4ed-002: slot 起動の監査イベント契約を定義する

- severity: spec-gap
- related_ids: [CTP-004, CTP-005, E.7.1.1, LP-002]
- related_files: [docs/arch/latest/arch-design.yaml, docs/specs/latest/_cross-cutting/datastore/rdb-schema.yaml, docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml]

### 観測した事実

最終検証では、slot 起動操作について構造化監査 event の schema、sink、保持期間、相関規則が未確定であることを確認した。ユーザーレビューで、slot 起動の監査ログを追記することは決定した。CLI stdout は起動結果の3行契約であり、独自の構造化監査 event を追加する出力先として使えない。既存の audit_logs は rerun と abort 系操作を対象にする列と action 値だけを定義している。

### 現在の仕様と問題

アーキテクチャは run_id/parent_run_id を構造化ログの必須相関 ID とし、slot 起動を監査対象のビジネス event とする。slot 起動の監査ログを追記する方針は決定したが、対象 UC と cross-cutting 契約は select-slot の監査 event 名、必須フィールド、発生点、永続 sink、保持、改ざん検知、失敗時の扱いを定義していない。このため、stdout 契約を変えずに起動の監査証跡を一貫して実装・照会することができない。

### 変更してほしいこと

slot 起動の監査ログを追記する仕様に更新する。select-slot の受付、slot ごとの起動開始、受理・失敗・timeout・最終状態を対象に、event 名、schema、必須相関 ID（run_id、parent_run_id、slot、attempt ID）、時刻、操作者または起動主体、結果分類、秘密情報の除外を定義する。追記先 sink、失敗時の永続化規則、保持期間、改ざん検知または保全方式、run_id による照会方法を定義し、既存 audit_logs との関係を整合させる。

### 完了条件

CLI stdout の契約を変更せず、slot 起動の各監査対象 event を一意の schema と sink へ記録できる。run_id を起点に操作主体、slot、時刻、結果、timeout 後の状態を追跡でき、保持・保全の責務と照会方法が実装者間で一致する。
