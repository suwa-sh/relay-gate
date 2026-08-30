# アーキテクチャ推論根拠サマリ

- event_id: 20260818_135504_arch_slot_config_attempt_identity
- created_at: 2026-08-18T13:55:04

差分更新イベント。実装フィードバック 20260818_113601_impl_feedback_6078c4ed の
CR-6078c4ed-005（direct）と CR-6078c4ed-003（causal reconciliation）に基づく再推論のみを対象とする。

## 分析した入力

| 入力 | 参照内容 |
|------|---------|
| feedback packet | CR-6078c4ed-005（slot 別実行設定と起動試行 identity）、CR-6078c4ed-003（再実行 identity の二重正本解消） |
| RDRA 状態.tsv（rdra:20260818_133855_rerun_identity_new_run_id 反映後） | 再実行 = 新 run_id の新規作成 + parent_run_id 関連付け、既存履歴不変の遷移 |
| RDRA 情報.tsv | execution-spec.json / Runner実行結果 の属性・関連 |
| docs/arch/latest/arch-design.yaml（更新前） | E-001 が単一 host / impl_version 前提、E-002 が（run_id, role_type）主キー |

## 設計判断サマリ

### データアーキテクチャ

| 対象 | 判断 | confidence | 根拠 |
|------|------|-----------|------|
| E-001 execution-spec.json | run 共通実行設定のみに縮約 | -（エンティティは confidence 属性なし） | CR-6078c4ed-005 推奨案（ユーザー確定）: run 共通と slot 別の分離 |
| E-007 slot実行設定（新規） | slot 別実行設定を分離定義（PK: run_id + slot_type） | storage_mapping: high | blue/green で host・impl_version が異なる並行稼働を単一値前提では表現できないため |
| E-002 Runner実行結果 | PK を（run_id, slot_type, role_type, attempt_id）へ変更。attempt_no / accepted_at を追加。status を 6 値へ | storage_mapping: high（変更なし） | 同一 run・同一 role の起動試行識別と、timeout 後の結果不明（UNKNOWN）の区別のため |

### ドメイン・システム・アプリケーションアーキテクチャ

| 対象 | 判断 | confidence | 根拠 |
|------|------|-----------|------|
| BC-001 / AG-001 / AG-002 | ユビキタス言語と集約不変条件を slot 別実行設定・起動試行 identity・再実行 identity に整合 | medium / low（既存上限を維持） | CR 確定内容の問題空間への反映 |
| CTP-006 冪等性方針 | 再実行 = 新 run_id + parent_run_id 関連付け・既存履歴不変を明文化 | user | CR-6078c4ed-003 推奨案（ユーザー確定）+ RDRA 状態遷移との整合 |
| LP-003 状態遷移の整合性保証 | 実行状態 STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED を正式定義。timeout 後は UNKNOWN とし推測で FAILED を確定しない | user | CR-6078c4ed-005 推奨案（ユーザー確定） |

## ユーザー確認による変更

| 対象 | 項目 | 推論値 | 確定値 | 変更理由 |
|------|------|--------|--------|---------|
| CTP-006 / E-001 / E-002 / E-007 / LP-003 | slot 別実行設定の分離・起動試行 identity・実行状態 6 値・再実行 identity | （旧設計: 単一値前提 + (run_id, role_type) キー + 4 状態） | CR 推奨案どおり | feedback request 本文で「推奨案を採用する」と確定済みのため対話省略で採用 |

## confidence 内訳（今回変更分のみ）

| セクション | high | medium | low | default | user | 合計 |
|-----------|:----:|:------:|:---:|:-------:|:----:|:----:|
| ドメインアーキテクチャ | 0 | 1 | 2 | 0 | 0 | 3 |
| システムアーキテクチャ | 0 | 0 | 0 | 0 | 1 | 1 |
| アプリケーションアーキテクチャ（変更項目のみ） | 2 | 0 | 0 | 0 | 1 | 3 |
| データアーキテクチャ（storage_mapping 追加分） | 1 | 0 | 0 | 0 | 0 | 1 |
| 合計 | 3 | 1 | 2 | 0 | 2 | 8 |

## RDRA 整合性に関する注記

E-007（slot実行設定）と E-002 の attempt_id / attempt_no / accepted_at、実行状態 STARTING / UNKNOWN は、
RDRA の情報.tsv / 状態.tsv にまだ存在しない（情報.tsv は execution-spec.json を単一情報として保持し、
background slot実行状態は RUNNING/SUCCEEDED/FAILED/ABORTED の 4 状態のみ）。
RDRA への追随是非は docs/todo.md に登録し、確認推奨項目として返却する（アーキテクチャ側で自動追加はしない）。
