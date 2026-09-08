# アーキテクチャ推論根拠サマリ

- event_id: 20260907_122000_feedback_abort_consistency
- created_at: 2026-09-07T12:20:00Z
- trigger_event: rdra:20260907_114000_feedback_abort_consistency, nfr:20260907_120000_feedback_abort_consistency
- mode: 差分更新(feedback mode。Step1 の Part 別推論は起動せず、前段 `_changes.md` と CR slice を arch-design.yaml の該当項目に直接照合した)

## 入力

- RDRA 差分: `docs/rdra/events/20260907_114000_feedback_abort_consistency/_changes.md`
- NFR 差分: `docs/nfr/events/20260907_120000_feedback_abort_consistency/_changes.md`
- stage packet: `docs/pipeline/feedback-runs/20260907_abort_consistency/stage-packets/architecture.md`(direct work unit: なし。causal work unit 3 件: CR-c770d8f0-016#1 / 017#1 / 018#1)
- arch 正本: `docs/arch/latest/arch-design.yaml`(`_digest/index.md` から必要セクションだけ参照)
- RDRA latest の該当行: 条件「中止済み run の比較依頼作成除外」「両系成功判定」「依頼中止可否判定」「slot 中止可否判定」、状態「クロスチェック依頼」、情報「速報実行」「速報比較依頼」「中止指示」「slot 実行」、バリエーション「中止対象種別」

## RDRA/NFR モデル分析結果

### 分析した RDRA 要素(差分後の latest)

| モデル | 要素数 | 主な特徴 |
|--------|--------|---------|
| BUC | 5 | 変更なし。UC「両系成功時に速報比較依頼を作成する」の中止済み run 判定に slot 実行 ABORTED、UC「比較ツールでジョブ単位比較を実行して結果を登録する」に条件「依頼中止可否判定」(条件付き UPDATE 0 件なら比較を開始しない)、UC「実行を ABORTED へ遷移させる」に abort-rapid-crosscheck の 3 状態中止 |
| アクター | 2 | 変更なし(運用者 / 基盤適用設計者) |
| 外部システム | 6 | 変更なし |
| 情報 | 27 | 速報実行(中止済み run の判定に slot 実行 ABORTED)、速報比較依頼(abort-rapid-crosscheck の 3 状態中止、CLAIMED 中止後は比較を開始しない)、中止指示(速報は 3 状態、確報は RUNNING のみ)を更新 |
| 状態 | 5 | クロスチェック依頼に CLAIMED → ABORTED(abort-rapid-crosscheck)を追加。REQUESTED → ABORTED を競合窓の保険に位置づけ直し、CLAIMED → RUNNING を条件付き UPDATE に |
| 条件 | 48 | 中止済み run の比較依頼作成除外(判定キー拡張と判定材料)、両系成功判定、依頼中止可否判定(3 状態 + CLAIMED 中止の競合規則)、slot 中止可否判定(保険の位置づけ)を更新 |

### 参照した NFR グレード(グレードは全項目据え置き)

| カテゴリ | 主な影響 |
|---------|---------|
| A. 可用性 | 変更なし(A.4.1.3 の縮退運転 off の根拠は不変) |
| B. 性能・拡張性 | 変更なし(B.3.1.1 の claim 排他・lease の根拠は不変) |
| C. 運用・保守性 | C.3.3.1(障害復旧方式)の手動復旧手順に、判定キーの拡張・abort-rapid-crosscheck の 3 状態中止・条件付き UPDATE による競合規則・REQUESTED 依頼中止の保険としての位置づけが反映された(SP-009 / SP-022 の source_model) |
| D. 移行性 | 変更なし |
| E. セキュリティ | 変更なし(E.7.1.1 の中止指示の記録範囲は不変) |
| F. 環境 | 変更なし |

## 設計判断サマリ

### 影響照合(CR → arch 項目)

| CR | 種別 | 判断 | 反映内容 |
|---|---|---|---|
| CR-016 中止済み run の判定キーに slot 実行 ABORTED | causal | changed | SP-009 / LP-010 / LP-023 の判定キーを「並行稼働実行 ABORTED または対象 slot の slot 実行 ABORTED」に拡張し、判定材料(parallel_run.status / slot_executions.status)と foreground 完了後の background 中止が slot 実行側で除外されることを明記。repository 責務に slot 実行の状態参照、E-016 に E-014 への関係、BC-002 / AG-002 / CLP-004 を追従(arch-decision-017) |
| CR-017 速報比較依頼の中止対象 REQUESTED / CLAIMED / RUNNING | causal | changed | SP-022 / LP-019 / LP-021 で abort-rapid-crosscheck を 3 状態対象(status IN 条件の条件付き UPDATE)、abort-final-crosscheck は RUNNING のみとし、SP-011 / LP-024(新規)/ L-rapid-gateway で worker の CLAIMED → RUNNING を条件付き UPDATE(0 件なら比較を開始しない)に。BC-004 / CM-005 / AG-002 / E-017 / E-024 を追従(arch-decision-017) |
| CR-018 REQUESTED → ABORTED の説明を競合窓の保険に | causal | changed | SP-022 / LP-021 / BC-004 / CM-005 / AG-002 / E-017 / E-024 の abort-blue / abort-green による REQUESTED 依頼 ABORTED 化を「完了通知で依頼が作成された直後に slot を中止した場合の競合窓を塞ぐ保険。dispatcher 側の中止済み run 判定と併用」に位置づけ直し(遷移と条件付き UPDATE は変更なし)(arch-decision-017) |

### システムアーキテクチャ(前回値からの変更点のみ)

| ティア | テクノロジー候補 | confidence | 変更 |
|--------|----------------|-----------|------|
| tier-rapid-crosscheck | bash / RDB クライアント / 比較ツールアダプタ(前回値) | high | SP-009 の判定キー拡張、SP-011 の CLAIMED → RUNNING 条件付き UPDATE |
| tier-ops | bash / メール送信コマンド / RDB クライアント / ファイルシステム走査・書き込み(前回値) | high | SP-022 の abort-rapid-crosscheck 3 状態中止・確報は RUNNING のみ・REQUESTED 依頼中止の保険としての位置づけ |

tier-facade / tier-final-crosscheck / tier-datastore と cross_tier_policies / rules は前回値。SP-008(runner は自 slot の中止状態を判断しない)は中止済み run の扱いを速報クロスチェック runner に委ねる記述のまま整合しており変更なし。

### アプリケーションアーキテクチャ

tier-rapid-crosscheck(usecase・domain・repository・gateway 責務 / LP-010 / LP-023 / LP-024 新規 / CLP-004)、tier-ops(usecase・domain 責務 / LP-019 / LP-021)を更新。レイヤー構成(presentation → usecase → domain → repository / gateway)と依存ルールは前回値のまま。

### データアーキテクチャ(変更エンティティ)

| エンティティ | ストレージ | confidence | 根拠 |
|-------------|----------|-----------|------|
| E-016 速報実行 | rdb(前回値) | 前回値 | completion_status と E-013 / E-017 関係の中止済み run 定義を更新。E-014(slot 実行)への関係を追加 |
| E-017 速報比較依頼 | rdb(前回値) | 前回値 | status の遷移経路(CLAIMED → ABORTED、CLAIMED → RUNNING の条件付き UPDATE、REQUESTED → ABORTED の保険) |
| E-024 中止指示 | rdb(前回値) | 前回値 | resulting_status と E-017 / E-019 関係(abort-rapid-crosscheck の 3 状態、abort-final-crosscheck は RUNNING のみ) |

storage_mapping と diagram_mermaid は変更なし。

## ユーザー確認による変更

| 対象 | 項目 | 推論値 | 確定値 | 変更理由 |
|------|------|--------|--------|---------|
| SP-009 / LP-010 / LP-023 / BC-002 / AG-002 / E-016 | 中止済み run の判定キー | 並行稼働実行 ABORTED のみ | 並行稼働実行 ABORTED、または完了通知の対象 slot の slot 実行 ABORTED(aborted.txt 公開済み) | CR-016 に利用者の決定が明記(2026-09-07 DIST-025 A) |
| SP-022 / SP-011 / LP-019 / LP-021 / LP-024 / BC-004 / CM-005 / E-017 / E-024 | abort-rapid-crosscheck の中止対象 | RUNNING のみ | REQUESTED / CLAIMED / RUNNING(worker 停止確認のうえ status IN 条件の条件付き UPDATE。worker は CLAIMED → RUNNING の条件付き UPDATE が 0 件なら比較を開始しない)。確報は RUNNING のみ | CR-017 に利用者の決定が明記(2026-09-07 DIST-026 A) |
| SP-022 / LP-021 / BC-004 / CM-005 / AG-002 / E-017 / E-024 | abort-blue / abort-green の REQUESTED 依頼 ABORTED 化の位置づけ | 両 slot 完了直後に中止した場合の抜けを防ぐ主手段 | 完了通知で依頼が作成された直後に slot を中止した場合の競合窓を塞ぐ保険(dispatcher 側の中止済み run 判定と併用) | CR-018 に利用者の決定が明記(2026-09-07 DIST-027 A) |

## confidence 内訳(latest 全体)

| セクション | high | medium | low | default | user | 合計 |
|-----------|:----:|:------:|:---:|:-------:|:----:|:----:|
| システムアーキテクチャ(policies + rules) | 39 | 8 | 0 | 1 | 1 | 49 |
| アプリケーションアーキテクチャ(policies + rules) | 25 | 3 | 0 | 8 | 0 | 36 |
| データアーキテクチャ(storage_mapping) | 24 | 2 | 2 | 0 | 0 | 28 |
| 合計 | 88 | 13 | 2 | 9 | 1 | 113 |

変更点: LP-024(high)を追加。既存項目の confidence は据え置き。残る low は storage_mapping E-009(ジョブ起動要求)/ E-022(通知メール)と集約境界仮説(AG-*)で、いずれも本 feedback request の対象外(前回値)。

## 確認推奨項目

- なし(利用者の決定が CR 本文に明記された事項をそのまま採用した)
