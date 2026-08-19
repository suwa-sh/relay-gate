# インフラ設計変換 推論根拠

## 入力サマリ

| 項目 | 値 |
|---|---|
| arch event_id | 20260818_090120_arch_audit_contract_feedback |
| NFR event_id | 20260817_144844_initial_nfr |
| 対象 | slot起動の構造化監査イベント |
| 対象環境 | onprem（エアギャップ環境のオンプレミスLinuxサーバ） |

## 既存ワークロード特性

ワークロード種別、可用性、レイテンシ、トラフィック、データ機密性、整合性、復旧目標、コスト方針は前回のインフラ設計から変更しない。今回のArch差分は既存RDBへの監査イベント永続化を具体化するものであり、これらのMCL入力フィールドを変更しない。

## 監査イベント永続化への変換

| Arch契約 | MCL/インフラ具体化 | 根拠 |
|---|---|---|
| RDB append-only監査ログ | PostgreSQL追記専用テーブル。アプリケーションロールへUPDATE/DELETE権限を付与せず、訂正も新規イベントとしてINSERT | 監査方針とユーザー指定PostgreSQL |
| 同一schemaの監査対象 | event_id、event_name、schema_version、run_id、parent_run_id、slot、attempt_id、occurred_at、actor、operation、outcome、final_status、error_code、previous_hash、event_hash | Archの監査ログ方針 |
| 実行系譜照会 | run_id・occurred_at、parent_run_id・occurred_atの複合索引 | 既存run_id/parent_run_id契約 |
| 冪等な再試行・照合 | event_id主キーとrun_id・slot・attempt_id・event_name一意制約 | Archの失敗時契約 |
| 改ざん検知 | 正規化済みイベント本体とprevious_hashからevent_hashを算出し定期検証 | NFR E.7.1.1 |
| 6ヶ月保持 | 月次パーティション。期限超過分はチェーン検証後に削除 | NFR C.6.1.1 |
| 秘密情報除外 | 認証情報、起動引数の実値、stdout/stderr本文を列へ含めない | Archの監査ログ方針 |
| 外部作用前の失敗 | 操作受付・起動試行の追記成功をslot起動の前提条件にする | 未記録起動の防止 |
| 外部作用後の失敗 | RDB障害中でも失われないよう、起動結果と未記録イベントを既存の永続ファイル領域へ一時ファイル作成・同期・アトミックrenameで確定し、定期ワーカーでPostgreSQLへ照合する | 取り消せない外部作用後の整合回復 |

## ベンダーマッピング判断

- PostgreSQLは既存のジョブキュー兼管理DBとして選定済みであり、新しいRDB製品や外部監査製品を追加しない。
- トランザクション、一意制約、索引、権限制御、期間パーティションで監査永続化を実現できるため、fidelityは`exact`とする。
- ハッシュ値の算出はアプリケーション側で正規化したイベントから行い、DB拡張機能への新たな依存を必須にしない。

## Archへの書き戻し判定

MCLで具体化した内容は入力Archの監査ログ方針と失敗時契約を実装可能な形へ展開したものである。新しいベンダー中立制約、ティア構成、認証方式、DR方針、外部連携、storage_typeの変更はないため、Archへの追加フィードバックとMCL再実行は不要。
