# アーキテクチャ推論根拠サマリ

- event_id: 20260908_015000_feedback_slot_status_wording
- created_at: 2026-09-08T01:50:00Z
- trigger_event: rdra:20260908_011000_feedback_slot_status_wording
- mode: 差分更新(feedback mode。Step1 の Part 別推論は起動せず、前段 `_changes.md` と CR slice を arch-design.yaml の該当項目に直接照合した)

## 入力

- RDRA 差分: `docs/rdra/events/20260908_011000_feedback_slot_status_wording/_changes.md`(条件「slot 実行の状態導出規則」の管理 DB 側文言のみの変更)
- NFR: `docs/nfr/events/20260908_013000_feedback_slot_status_wording/feedback-disposition.json`(no-change manifest。nfr/latest は不変)
- stage packet: `docs/pipeline/feedback-runs/20260908_slot_status_wording/stage-packets/architecture.md`(direct work unit: なし。causal work unit 1 件: CR-c770d8f0-019#1)
- arch 正本: `docs/arch/latest/arch-design.yaml`(`_digest/index.md` から data_architecture と、条件「slot 実行の状態導出規則」を source_model に持つ policy を参照)
- RDRA latest の該当行: 条件「slot 実行の状態導出規則」

## RDRA/NFR モデル分析結果

### 分析した RDRA 要素(差分後の latest)

| モデル | 要素数 | 主な特徴 |
|--------|--------|---------|
| BUC | 5 | 変更なし |
| アクター | 2 | 変更なし |
| 外部システム | 6 | 変更なし |
| 情報 | 27 | 変更なし |
| 状態 | 5 | 変更なし |
| 条件 | 48 | 「slot 実行の状態導出規則」の管理 DB 側文言のみ変更(条件付き更新で一度だけ書く、abort 後は ABORTED のまま残す、判定材料としての用途)。判定表とバリエーション列は不変 |

### 参照した NFR グレード

- 全項目据え置き(nfr stage は no-change manifest)

## 設計判断サマリ

### 影響照合(CR → arch 項目)

| 照合対象 | 旧文言の引用 | 判断 |
|---|---|---|
| E-014 status 属性説明 | あり(「速報有効時は管理 DB にも同じ状態を保持する」) | changed: 新文言に置換 |
| storage_mapping E-014(rdb) | あり(「ファイル正本と同じ値で管理 DB にも保持し」「管理 DB 複製」) | changed: 一度書き・再同期しない・判定材料の用途に置換 |
| storage_mapping E-014(file) | なし | 変更なし |
| LP-021(条件付き ABORTED 更新) | なし(WHERE 句で RUNNING を条件にする記述で整合) | 変更なし |
| SP-009 / LP-023 / BC-002 / E-016(判定材料 = slot_executions.status(aborted.txt のミラー)) | なし | 変更なし(abort 後に ABORTED が残る新文言と整合) |
| LP-005(ファイル正本からの導出をドメイン層の関数に) | なし | 変更なし |
| CTR-001 / SR-001 / arch-decision-017 | なし | 変更なし |

### システムアーキテクチャ / アプリケーションアーキテクチャ

変更なし(tiers / cross_tier_policies / rules / tier_layers はすべて前回値)。

### データアーキテクチャ(変更エンティティ)

| エンティティ | ストレージ | confidence | 根拠 |
|-------------|----------|-----------|------|
| E-014 slot 実行 | file + rdb(前回値。二重マッピング) | high(前回値) | rdb 側の位置づけを「ファイル正本の複製」から「公開時点の状態を条件付き更新で一度だけ書く。abort 後は ABORTED のまま残す」に改めた(arch-decision-018) |

diagram_mermaid は変更なし。

## ユーザー確認による変更

| 対象 | 項目 | 推論値 | 確定値 | 変更理由 |
|------|------|--------|--------|---------|
| E-014 / storage_mapping E-014(rdb) | 管理 DB 側の slot 実行状態の位置づけ | ファイル正本と同じ値を保持する複製 | aborted.txt / exitcode.txt 公開時点の状態を条件付き更新(RUNNING のときだけ)で一度だけ書き、abort 後は ABORTED のまま残して再同期しない | CR-019 に利用者の決定が明記(2026-09-08 DIST-029 A) |

## confidence 内訳(latest 全体)

| セクション | high | medium | low | default | user | 合計 |
|-----------|:----:|:------:|:---:|:-------:|:----:|:----:|
| システムアーキテクチャ(policies + rules) | 39 | 8 | 0 | 1 | 1 | 49 |
| アプリケーションアーキテクチャ(policies + rules) | 25 | 3 | 0 | 8 | 0 | 36 |
| データアーキテクチャ(storage_mapping) | 24 | 2 | 2 | 0 | 0 | 28 |
| 合計 | 88 | 13 | 2 | 9 | 1 | 113 |

変更点: なし(既存項目の confidence は据え置き。policy / rule の追加・削除なし)。

## 確認推奨項目

- なし(利用者の決定が CR 本文に明記された事項をそのまま採用した)
