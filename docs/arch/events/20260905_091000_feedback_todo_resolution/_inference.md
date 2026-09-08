# アーキテクチャ推論根拠サマリ

- event_id: 20260905_091000_feedback_todo_resolution
- created_at: 2026-09-05T09:10:00Z
- trigger_event: rdra:20260905_083000_feedback_todo_resolution, nfr:20260905_085000_feedback_todo_resolution
- mode: 差分更新(feedback mode。Step1 の Part 別推論は起動せず、前段 `_changes.md` と CR slice を arch-design.yaml の該当項目に直接照合した)

## 入力

- RDRA 差分: `docs/rdra/events/20260905_083000_feedback_todo_resolution/_changes.md`
- NFR 差分: `docs/nfr/events/20260905_085000_feedback_todo_resolution/_changes.md`
- stage packet: `docs/pipeline/feedback-runs/20260905_todo_resolution/stage-packets/architecture.md`(causal work unit 12 件。direct なし)
- arch 正本: `docs/arch/latest/arch-design.yaml`(`_digest/index.md` から必要セクションだけ参照)

## RDRA/NFR モデル分析結果

### 分析した RDRA 要素(差分後の latest)

| モデル | 要素数 | 主な特徴 |
|--------|--------|---------|
| BUC | 5 | 変更なし。UC の関連条件・情報が差分更新された(適用構成定義 / 実行中止 / リラン / 監視 / 速報クロスチェック) |
| アクター | 2 | 変更なし(運用者 / 基盤適用設計者) |
| 外部システム | 6 | 管理 DB(RDB)が外部システムから除かれ、システム概要の内部データストアになった(CR-006) |
| 情報 | 26 | ハング検知定期ジョブ設定を追加。feature flag 9 キー、ジョブマップ CSV 列名、Runner Result の aborted.txt、run_id 形式、調整記録の置き場を反映 |
| 状態 | 5 | 並行稼働実行に STARTED → ABORTED とリラン由来 run の COMPLETED、監視状態に通知後・中止後の終端遷移を追加 |
| 条件 | 47 | slot 実行の状態導出規則 / 完了通知失敗の扱い / 比較結果の登録条件を追加 |

### 参照した NFR グレード(前回値。グレードは全項目据え置き)

| カテゴリ | 主な影響 |
|---------|---------|
| A. 可用性 | A.4.1.3(RLO)の reason に縮退運転 off での中止・リラン成立が反映され、SP-020 / SP-022 / SP-024 の source_model に追加。A.2.5.1 は内部データストア表記へ |
| B. 性能・拡張性 | B.2.1.2 の内部データストア表記。設計値は変更なし |
| C. 運用・保守性 | C.5.1.1 を利用者が既定値として確定(CTP-009 の confidence を medium へ)。C.3.1.1 / C.3.3.1 に完了通知失敗の非検知と手動復旧(SP-008 / LP-022)。C.3.2.1 の通知設定の出所(SP-018)。C.2.2.1 / C.1.2.2 の設定版廃止と設定ファイル追加(SP-025)。C.1.3.2 の aborted.txt 走査(SP-016) |
| D. 移行性 | 変更なし |
| E. セキュリティ | E.6.1.2 / E.5.2.1 の表記変更のみ(CTP-002 の source_model) |
| F. 環境 | F.1.2.2 の Runner Result 構成に aborted.txt(SP-024) |

## 設計判断サマリ

### 影響照合(CR → arch 項目)

| CR | 判断 | 反映内容 |
|---|---|---|
| CR-001 feature flag 9 キー | changed | E-001 を 9 キー・3 値・設定版なしに戻す。実装版の出所を BLUE_IMPL / GREEN_IMPL、完了通知先を RAPID_CROSSCHECK_RUNNER と明記(SP-001 / SP-007 / SP-008 / SP-025) |
| CR-002 ジョブマップ CSV | changed | E-003 / E-010 の列名を元資料に統一し、CSV 形式と fixed_params セル規則を SP-006 / storage_mapping に明記。credential_ref / map_version は任意列 |
| CR-003 run_id 形式 | changed | 利用者決定(ローカルタイムゾーン)を CTP-003 / E-013 / BC-001 / LP-005 に記載。off でも facade 単独で発行するため SP-008 / E-009 を「run_id は常時発行、parallel_run は速報有効時のみ」に修正 |
| CR-004 aborted.txt | changed | Runner Result に aborted.txt を追加し、slot 実行の状態導出規則を CTR-001 / SR-001 / LP-005 / LP-019 に置く。storage_mapping E-014 の二重マッピング(ファイル正本 + 速報有効時の管理 DB)を high で確定 |
| CR-005 完了通知失敗 | changed | SP-008 に非検知と手動復旧を明記し、tier-facade gateway に LP-022 を追加。SP-016 の検知対象から除外 |
| CR-006 管理 DB 内部化 | changed | source_model の「外部システム: 管理 DB(RDB)」を「システム概要: ジョブキュー兼管理 DB(内部データストア)」へ。CTR-003 の外部システム数を 6 種に修正(gateway 隔離の方針は維持) |
| CR-007 属性整理 | changed | E-004 から調整記録を外し E-005 へ移動(SP-019 / CLP-008)。E-012 の応答日時を削除 |
| CR-008 監視状態統一 | changed | E-021 / SP-016 / SP-018 / LP-019 に 6 値と通知後・中止後の終端遷移 |
| CR-009 並行稼働実行の遷移 | changed | E-013 / SP-022 / LP-021 に STARTED → ABORTED、SP-011 / SR-001 / SR-003 / SP-020 にリラン由来 run の COMPLETED 更新者(worker / runner) |
| CR-010 hang-detector.env | changed | E-026 を BC-005 所有で追加し、SP-018 / SP-025 / tier-ops gateway・repository / E-022 に出所を明記 |
| CR-011 比較結果の登録条件 | changed | SP-011 に登録条件(比較定義なし・起動失敗では依頼だけ FAILED) |
| CR-012 NFR 確定 | changed | CTP-009 の confidence low → medium(利用者確定の既定値。適用側で上書き可能) |

### システムアーキテクチャ(前回値からの変更点のみ)

| ティア | テクノロジー候補 | confidence | 変更 |
|--------|----------------|-----------|------|
| tier-facade | bash CLI / SSH / ファイルシステム / RDB クライアント | high | 9 キー feature flag、CSV ジョブマップ、run_id 常時発行、完了通知失敗の扱い |
| tier-rapid-crosscheck | bash / RDB クライアント / 比較ツールアダプタ | high | 比較結果の登録条件、リラン由来 run の COMPLETED |
| tier-ops | bash / メール送信コマンド / RDB クライアント / ファイルシステム走査・書き込み | high | aborted.txt、監視状態 6 値、ハング検知定期ジョブ設定 |
| tier-datastore | RDB(内部) / ファイルシステム | high(SP-026 は medium) | 内部データストア表記、設定ファイルの所有区分 |

### アプリケーションアーキテクチャ

tier-facade(LP-004 / LP-005 / LP-022)、tier-rapid-crosscheck(usecase 責務)、tier-ops(LP-019 / LP-020 / LP-021 / CLP-008)を更新。レイヤー構成(presentation → usecase → domain → repository / gateway)と依存ルールは前回値のまま。

### データアーキテクチャ(変更エンティティ)

| エンティティ | ストレージ | confidence | 根拠 |
|-------------|----------|-----------|------|
| E-001 feature flag 設定 | file | high | env 形式 9 キー。設定版なし |
| E-003 ジョブマップ | file | high | CSV(元資料の列名)。任意列 credential_ref / map_version |
| E-014 slot 実行 | file + rdb | high / high | ファイル正本(exitcode.txt / aborted.txt)+ 速報有効時の管理 DB 複製。low → high に確定 |
| E-021 監視記録 | rdb | medium | 6 値と終端。off では実行ログのみ(前回値) |
| E-024 中止指示 | rdb | high | aborted.txt を正本、off 以外で管理 DB も更新 |
| E-026 ハング検知定期ジョブ設定 | file | high | env 形式。認証情報は参照名のみ |

## ユーザー確認による変更

| 対象 | 項目 | 推論値 | 確定値 | 変更理由 |
|------|------|--------|--------|---------|
| CTP-003 / E-013 | run_id 形式 | UTC yyyymmddThhmmssZ(spec 仮採用) | ローカルタイムゾーン yyyymmddThhmmss(Z なし)-{job_id}-{8 桁 hex} | CR-003 に利用者の決定が明記(2026-09-05 D3) |
| CTP-009 | 運用体制の confidence | low | medium | CR-012 で利用者が NFR C.5.1.1 を既定値として確定 |

## confidence 内訳(latest 全体)

| セクション | high | medium | low | default | user | 合計 |
|-----------|:----:|:------:|:---:|:-------:|:----:|:----:|
| システムアーキテクチャ(policies + rules) | 39 | 8 | 0 | 1 | 1 | 49 |
| アプリケーションアーキテクチャ(policies + rules) | 22 | 4 | 0 | 8 | 0 | 34 |
| データアーキテクチャ(storage_mapping) | 23 | 2 | 2 | 0 | 0 | 27 |
| 合計 | 84 | 14 | 2 | 9 | 1 | 110 |

残る low は storage_mapping E-009(ジョブ起動要求)/ E-022(通知メール)と集約境界仮説(AG-*)で、いずれも本 feedback request の対象外(前回値)。

## 確認推奨項目

- CLP-002 の実行ログ日時 TZ(UTC)と run_id の時刻部(ローカルタイムゾーン)の不一致。完了報告で 3 案 + 推奨を返却し、本イベントでは CLP-002 を変更しない
