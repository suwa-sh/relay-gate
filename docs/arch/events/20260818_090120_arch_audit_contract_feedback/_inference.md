# アーキテクチャ推論根拠サマリ

- event_id: 20260818_090120_arch_audit_contract_feedback
- created_at: 2026-08-18T09:01:20

## 対象

- work unit: CR-6078c4ed-002#1
- constraint: slot-launch-audit-contract
- disposition: applied

## 根拠

| 入力 | 設計への反映 |
|---|---|
| ユーザー指定「監査ログ追記」 | slot起動の各監査対象イベントをappend-onlyで追記 |
| ユーザー指定「PostgreSQL」 | アーキテクチャ層ではベンダーニュートラルなRDB sinkとして表現 |
| BUC「feature flag設定に基づきslotを選択して起動する」 | 操作受付・slot別起動試行・成功/失敗/timeout・最終状態を監査対象化 |
| システム概要 run_id/parent_run_id | 実行系譜の一元照会キーとして必須化 |
| NFR E.7.1.1「操作ログ+改ざん検知」 | append-onlyとハッシュチェーン検証を採用 |
| NFR C.6.1.1「6ヶ月」 | 監査イベントの保持期間を6ヶ月に統一 |
| Runner Result Contract | stdout/stderr/exitcodeの外部契約を変更せず、本文を監査ログへ複製しない |

## 対話結果

- Option A「RDBのappend-only監査テーブル + ハッシュチェーン」を採用
- confidence: user
- 代替案は、DB権限制御のみでは改ざん検知が弱く、追記専用ファイルではrun_id横断照会と既存監査ログとの統合が複雑になるため不採用

## 変更しない設計

- ドメイン境界、ティア構成、レイヤー依存、概念エンティティは変更しない
- `audit_logs`の物理テーブル定義とイベント名の列挙は後続のspec/datastore契約で具体化する
