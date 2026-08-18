# 上流正本の矛盾が仕様再生成を止める

## 何が起きたか

公開済み feedback request を入力にした差分反映は、アーキテクチャ設計とインフラ設計までは完了したが、仕様生成の整合検証で上流正本間の矛盾4件(再実行 identity の二重正本、PostgreSQL で成立しない partition 契約、slot 別実行設定と試行 identity の欠落、Runner 実行結果の履歴方針矛盾)により中止された。仕様側で一度作成・機械検証まで通過した修正はすべてロールバックされた。

## 原因

feedback request が新しい契約(監査永続化、slot 別起動)を要求したのに対し、その契約が依存する既存の上流正本(USDM / RDRA / arch / infra)側の前提を整合対象として明示していなかった。差分反映は要求された箇所を更新できても、要求外の既存正本間の矛盾は仕様生成の整合検証で初めて表面化する。

## 回避方法

feedback request を書く時点で、要求する新契約が依存する既存正本の前提(識別子の発行規則、状態遷移、主キー・一意制約、永続化パターン)を洗い出し、矛盾の可能性がある箇所は正本のファイルパス・該当箇所つきで整合対象の変更要求として明示する。RDB 固有の制約(PostgreSQL の partitioned table では PRIMARY KEY / UNIQUE に partition key が必須、等)は、インフラ設計の段階で実 DDL の作成試験により検証する。

## 次回の対応

- 監査・履歴系の要求では、identity(run_id / attempt_id / slot)と状態遷移の正本箇所を feedback request に必ず併記する
- 仕様生成後に datastore validator だけでなく実 PostgreSQL での DDL 作成試験を行う
- 中止された run の未解決事項は、同じ feedback ID で続行せず、`supersedes` を付けた訂正版 request に集約する
