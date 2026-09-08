# アーキテクチャ推論根拠サマリ

- event_id: 20260907_015000_feedback_todo_followup
- created_at: 2026-09-07T01:50:00Z
- trigger_event: rdra:20260907_011000_feedback_todo_followup, nfr:20260907_013000_feedback_todo_followup
- mode: 差分更新(feedback mode。Step1 の Part 別推論は起動せず、前段 `_changes.md` と CR slice を arch-design.yaml の該当項目に直接照合した)

## 入力

- RDRA 差分: `docs/rdra/events/20260907_011000_feedback_todo_followup/_changes.md`
- NFR 差分: `docs/nfr/events/20260907_013000_feedback_todo_followup/_changes.md`
- stage packet: `docs/pipeline/feedback-runs/20260907_todo_followup/stage-packets/architecture.md`(direct work unit 1 件: CR-c770d8f0-015#1。causal work unit 3 件: CR-c770d8f0-013#1 / 014#1 / 015#1)
- arch 正本: `docs/arch/latest/arch-design.yaml`(`_digest/index.md` から必要セクションだけ参照)
- 参照読み: `docs/specs/latest/_cross-cutting/api/cli-command-contract.yaml`(実行ログ行書式と RELAY_GATE_NOW の既存規則の確認のみ)

## RDRA/NFR モデル分析結果

### 分析した RDRA 要素(差分後の latest)

| モデル | 要素数 | 主な特徴 |
|--------|--------|---------|
| BUC | 5 | 変更なし。UC の入力情報に「速報クロスチェック設定」、UC「両系成功時に速報比較依頼を作成する」に条件「中止済み run の比較依頼作成除外」、UC「実行を ABORTED へ遷移させる」に未着手依頼の ABORTED 化 |
| アクター | 2 | 変更なし(運用者 / 基盤適用設計者) |
| 外部システム | 6 | 変更なし |
| 情報 | 27 | 速報クロスチェック設定を追加(管理 DB 接続参照名 / lease 期間 / poll 間隔。所有者: 基盤適用設計者)。速報実行・速報比較依頼・中止指示・完了通知の説明を更新 |
| 状態 | 5 | クロスチェック依頼に REQUESTED → ABORTED(abort-blue / abort-green。速報比較依頼のみ)を追加 |
| 条件 | 48 | 中止済み run の比較依頼作成除外を追加(判断主体: 速報クロスチェック runner)。両系成功判定 / 完了通知の系統独立 / slot 中止可否判定 / 設定所有区分を更新 |

### 参照した NFR グレード(グレードは全項目据え置き)

| カテゴリ | 主な影響 |
|---------|---------|
| A. 可用性 | 変更なし(A.4.1.3 の縮退運転 off の根拠は不変) |
| B. 性能・拡張性 | B.3.1.1 の lease 期間 / poll 間隔の出所を速報クロスチェック設定と明記(SP-010 の source_model) |
| C. 運用・保守性 | C.1.2.2 のバックアップ対象に速報クロスチェック設定(SP-025)。C.3.3.1 の手動復旧に中止スクリプトの未着手依頼 ABORTED 化と中止済み run の除外(SP-022) |
| D. 移行性 | 変更なし |
| E. セキュリティ | E.5.1.1 の管理 DB 接続を接続参照名で解決し値を置かない(SP-025 / SP-008) |
| F. 環境 | F.1.2.1 の RDB 接続先が速報クロスチェック設定の接続参照名で解決される(tier-facade / tier-rapid-crosscheck の technology_candidates) |

## 設計判断サマリ

### 影響照合(CR → arch 項目)

| CR | 種別 | 判断 | 反映内容 |
|---|---|---|---|
| CR-015 実行ログのローカル TZ | direct | applied | CLP-002 の UTC 統一を削除し、ローカルタイムゾーン(ISO 8601 秒精度、指示子なし。run_id と同じ時刻軸)に改める。管理 DB の *_at は RDB のタイムスタンプ型、CLI stdout もローカル時刻、RELAY_GATE_NOW は UTC 入力 → ローカル変換を維持。CTP-003 / CLP-004 / E-025 / E-015 に追従。confidence medium → high(arch-decision-014) |
| CR-013 速報クロスチェック設定 | causal | changed | E-027 を BC-005 所有で追加(storage: file / env)。設定所有区分(BC-005 / SP-025 / tier-datastore)、接続参照名の出所(SP-008 / tier-facade / tier-rapid-crosscheck / repository・gateway 責務)、lease 期間・poll 間隔の出所(SP-010 / AG-002 / E-017)を明記(arch-decision-016) |
| CR-014 中止済み run の比較除外と未着手依頼の ABORTED 化 | causal | changed | 比較の要否判断を dispatcher に置き(SP-009 / LP-010 / LP-023 / BC-002 / AG-002 / E-016)、slot runner は自 slot の中止状態を判断しない(SP-008 / E-015)。abort-blue / abort-green は REQUESTED の速報比較依頼も ABORTED にする(SP-022 / LP-019 / LP-021 / BC-004 / CM-005 / E-017 / E-024)(arch-decision-015) |

### システムアーキテクチャ(前回値からの変更点のみ)

| ティア | テクノロジー候補 | confidence | 変更 |
|--------|----------------|-----------|------|
| tier-facade | bash CLI / SSH / ファイルシステム / RDB クライアント | high | 管理 DB 接続参照名の出所(速報クロスチェック設定)。runner は自 slot の中止状態を判断しない(SP-008) |
| tier-rapid-crosscheck | bash / RDB クライアント / 比較ツールアダプタ | high | 中止済み run の依頼作成除外(SP-009)、lease 期間・poll 間隔の出所(SP-010) |
| tier-ops | bash / メール送信コマンド / RDB クライアント / ファイルシステム走査・書き込み | high | abort-blue / abort-green の未着手依頼 ABORTED 化(SP-022) |
| tier-datastore | RDB(内部) / ファイルシステム | high(SP-026 は medium) | 設定ファイルに速報クロスチェック設定(SP-025) |

cross_tier_policies: CTP-003 に実行ログ日時の時刻軸(ローカルタイムゾーン)を明記。tier-final-crosscheck と他の cross_tier_policies / rules は前回値。

### アプリケーションアーキテクチャ

tier-facade(CLP-002 / repository・gateway 責務)、tier-rapid-crosscheck(usecase・domain・repository・gateway 責務 / LP-010 / LP-023 新規 / CLP-004)、tier-ops(usecase・domain 責務 / LP-019 / LP-021)を更新。レイヤー構成(presentation → usecase → domain → repository / gateway)と依存ルールは前回値のまま。

### データアーキテクチャ(変更エンティティ)

| エンティティ | ストレージ | confidence | 根拠 |
|-------------|----------|-----------|------|
| E-027 速報クロスチェック設定(新規) | file | high | env 形式 rapid-crosscheck.env。RDRA 情報「速報クロスチェック設定」と設定所有区分。認証情報は参照名のみ |
| E-015 完了通知 | rdb(前回値) | 前回値 | occurred_at のローカルタイムゾーン、E-027 への関係、自 slot の中止状態を判断しない |
| E-016 速報実行 | rdb(前回値) | 前回値 | ABORTED run では比較依頼作成済みへ進めない。E-025(警告ログ)への関係 |
| E-017 速報比較依頼 | rdb(前回値) | 前回値 | REQUESTED → ABORTED の経路、lease_until の出所 |
| E-024 中止指示 | rdb(前回値) | 前回値 | 未着手依頼の ABORTED 化 |
| E-025 実行ログ | file(前回値) | 前回値 | occurred_at のローカルタイムゾーン |

## ユーザー確認による変更

| 対象 | 項目 | 推論値 | 確定値 | 変更理由 |
|------|------|--------|--------|---------|
| CLP-002 / CTP-003 / E-025 | 実行ログ日時のタイムゾーン | UTC(Z 付き ISO 8601) | ホストのローカルタイムゾーン(指示子なし。run_id と同じ時刻軸) | CR-015 に利用者の決定が明記(2026-09-07 DIST-022 A) |
| SP-009 / LP-010 / LP-023 | 中止済み run の比較依頼作成 | 両系成功なら作成 | 並行稼働実行が ABORTED なら作成せず完了事実の記録と警告のみ(判断主体: dispatcher) | CR-014 に利用者の決定が明記(2026-09-07 DIST-024 C) |
| SP-022 / LP-021 / E-017 | abort-blue / abort-green の対象 | slot と並行稼働実行のみ | 対象 run の REQUESTED で未着手の速報比較依頼も ABORTED | CR-014 に利用者の決定が明記(未着手依頼の ABORTED 化) |
| E-027 / SP-025 / BC-005 | 速報クロスチェック設定の所在 | spec 側のみ(RDRA 未登録) | RDRA 情報「速報クロスチェック設定」→ arch E-027(BC-005 所有、file) | CR-013 に利用者の決定が明記(2026-09-07 DIST-023 A) |

## confidence 内訳(latest 全体)

| セクション | high | medium | low | default | user | 合計 |
|-----------|:----:|:------:|:---:|:-------:|:----:|:----:|
| システムアーキテクチャ(policies + rules) | 39 | 8 | 0 | 1 | 1 | 49 |
| アプリケーションアーキテクチャ(policies + rules) | 24 | 3 | 0 | 8 | 0 | 35 |
| データアーキテクチャ(storage_mapping) | 24 | 2 | 2 | 0 | 0 | 28 |
| 合計 | 87 | 13 | 2 | 9 | 1 | 112 |

変更点: CLP-002 が medium → high(利用者決定)、LP-023(high)と storage_mapping E-027(high)を追加。残る low は storage_mapping E-009(ジョブ起動要求)/ E-022(通知メール)と集約境界仮説(AG-*)で、いずれも本 feedback request の対象外(前回値)。

## 確認推奨項目

- なし(利用者の決定が CR 本文に明記された事項をそのまま採用した)
