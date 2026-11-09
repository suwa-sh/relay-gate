# Spec Event Summary

## Overview

| 項目 | 内容 |
|------|------|
| Event ID | 20261103_135000_feedback_housekeeping_db_required |
| Created At | 2026-11-03T13:50:00Z |
| Source | Spec 差分更新(design 無しモード。2026-11-03 のハウスキープの接続参照名の必須化・env の字下げしたコメント行)。CR-9d2e6c41-002(spec 直接所有): CLI 契約 config_input_rules.env_files のコメント行の定義を、行の前後の空白(半角空白とタブ)を除いた結果が # で始まる行に改め、例(# x / 字下げした # x / タブ + # x)を添えて全 env 設定ファイル共通とした(空白だけの行・キーが空の行・= の無い行は invalid line のまま、KEY=#abc は値 #abc)。compare_command_argv.split・feature-flag.env の format・出力規約・UC「feature flag を設定する」と確報の比較ツール UC の記述を揃え、速報クロスチェック設定の読み込みとの差分を記録(spec-decision-026)。CR-9d2e6c41-001(上流追従): ハウスキープ設定の管理 DB 接続参照名を RAPID_CROSSCHECK_MODE が off 以外または確報クロスチェックを使う設置(final-crosscheck.env があり FINAL_DB_CONN_REF が欠落していない。確報系コマンドの判定と同じ)で必須とし、欠落・空は error: option required option=HOUSEKEEP_DB_CONN_REF(終了コード 2)。設定の検査を processing_order の手順 0 として削除待ちの置き場の残りの削除より先に行い、管理 DB に接続しない振る舞いを管理 DB を一切使わない設置に絞った(shared_rules.housekeep_rules.db_requirement 新設。判定 UC の分岐 B-09・BDD・USDM 対応。spec-decision-027) |
| UC 総数 | 34 |
| API 総数 | 0 |
| 非同期イベント総数 | 3 |
| 業務数 | 6 |
| BUC 数 | 8 |

## UC 一覧

| 業務 | BUC | UC | API数 | 非同期 | インフラ |
|------|-----|-----|:-----:|:-----:|:-------:|
| クロスチェック業務 | 確報クロスチェックフロー | 確報クロスチェック結果を確認する | 0 | - | - |
| クロスチェック業務 | 確報クロスチェックフロー | 確報比較依頼を claim する | 0 | - | - |
| クロスチェック業務 | 確報クロスチェックフロー | 確報比較依頼を登録して終端状態まで待機する | 0 | - | - |
| クロスチェック業務 | 確報クロスチェックフロー | 比較ツールで日次全量比較を実行して結果を保存する | 0 | - | - |
| クロスチェック業務 | 確報クロスチェックフロー | 保存済みの確報結果をジョブスケジューラへ返す | 0 | - | - |
| クロスチェック業務 | 速報クロスチェックフロー | 速報クロスチェック runner へ完了通知を送信する | 0 | - | - |
| クロスチェック業務 | 速報クロスチェックフロー | 速報比較依頼を claim する | 0 | - | - |
| クロスチェック業務 | 速報クロスチェックフロー | 速報比較結果を参照する | 0 | - | - |
| クロスチェック業務 | 速報クロスチェックフロー | 比較ツールでジョブ単位比較を実行して結果を登録する | 0 | - | - |
| クロスチェック業務 | 速報クロスチェックフロー | 両系成功時に速報比較依頼を作成する | 0 | - | - |
| 実行監視業務 | background 実行監視フロー | ハング検知ジョブの異常終了を確認する | 0 | - | - |
| 実行監視業務 | background 実行監視フロー | background 実行の経過時間と終了状態を判定する | 0 | - | - |
| 実行監視業務 | background 実行監視フロー | hang_detect_limit_minutes をジョブごとに調整する | 0 | - | - |
| 実行監視業務 | background 実行監視フロー | ハング疑い・実行エラー・比較異常を通知する | 0 | - | - |
| 実行監視業務 | background 実行監視フロー | 監視記録を保存する | 0 | - | - |
| 実行復旧業務 | background 側リランフロー | リラン結果を parent_run_id で追跡する | 0 | - | - |
| 実行復旧業務 | background 側リランフロー | リラン対象を検証する | 0 | - | - |
| 実行復旧業務 | background 側リランフロー | 元の execution-spec.json から復元して新しい run_id で起動する | 0 | - | - |
| 実行復旧業務 | background 側リランフロー | 速報比較依頼だけを新規作成する | 0 | - | - |
| 実行復旧業務 | 実行中止フロー | 現在状態を確認して停止確認に応答する | 0 | - | - |
| 実行復旧業務 | 実行中止フロー | 実行を ABORTED へ遷移させる | 0 | - | - |
| 実装切替業務 | 実装切替ジョブ実行フロー | execution-spec.json を確定保存する | 0 | - | - |
| 実装切替業務 | 実装切替ジョブ実行フロー | foreground slot の結果をジョブスケジューラへ中継する | 0 | - | - |
| 実装切替業務 | 実装切替ジョブ実行フロー | slot 実行モードを選択して runner を起動する | 0 | - | - |
| 実装切替業務 | 実装切替ジョブ実行フロー | ジョブマップで JOB_ID から実行先を解決する | 0 | - | - |
| 実装切替業務 | 実装切替ジョブ実行フロー | 業務ジョブの実行結果を確認する | 0 | - | - |
| 実装切替業務 | 実装切替ジョブ実行フロー | 実装スクリプトを実行して Runner Result を出力する | 0 | - | - |
| 適用構成業務 | 適用構成定義フロー | feature flag を設定する | 0 | - | - |
| 適用構成業務 | 適用構成定義フロー | slot runner の実体スクリプトを割り当てる | 0 | - | - |
| 適用構成業務 | 適用構成定義フロー | slot ごとのジョブマップを定義する | 0 | - | - |
| 適用構成業務 | 適用構成定義フロー | クロスチェックのジョブマップと比較定義を定義する | 0 | - | - |
| 適用構成業務 | 適用構成定義フロー | 切り替えた運用モードで業務ジョブを実行する | 0 | - | - |
| ハウスキープ業務 | ハウスキープフロー | 保持日数を過ぎた終了済みの実行と確報比較依頼を判定する | 0 | - | - |
| ハウスキープ業務 | ハウスキープフロー | 成果物と管理 DB の履歴を削除する | 0 | - | - |

## UC ファイル構成

### クロスチェック業務

#### 確報クロスチェックフロー

- **確報クロスチェック結果を確認する**: spec.md, tier-final-crosscheck.md
- **確報比較依頼を claim する**: spec.md, tier-final-crosscheck.md
- **確報比較依頼を登録して終端状態まで待機する**: spec.md, tier-final-crosscheck.md
- **比較ツールで日次全量比較を実行して結果を保存する**: spec.md, tier-final-crosscheck.md
- **保存済みの確報結果をジョブスケジューラへ返す**: spec.md, tier-final-crosscheck.md

#### 速報クロスチェックフロー

- **速報クロスチェック runner へ完了通知を送信する**: spec.md, tier-facade.md, tier-rapid-crosscheck.md
- **速報比較依頼を claim する**: spec.md, tier-rapid-crosscheck.md
- **速報比較結果を参照する**: spec.md, tier-rapid-crosscheck.md
- **比較ツールでジョブ単位比較を実行して結果を登録する**: spec.md, tier-rapid-crosscheck.md
- **両系成功時に速報比較依頼を作成する**: spec.md, tier-rapid-crosscheck.md

### 実行監視業務

#### background 実行監視フロー

- **ハング検知ジョブの異常終了を確認する**: spec.md, tier-ops.md
- **background 実行の経過時間と終了状態を判定する**: spec.md, tier-ops.md
- **hang_detect_limit_minutes をジョブごとに調整する**: spec.md, tier-facade.md, tier-ops.md
- **ハング疑い・実行エラー・比較異常を通知する**: spec.md, tier-ops.md
- **監視記録を保存する**: spec.md, tier-ops.md

### 実行復旧業務

#### background 側リランフロー

- **リラン結果を parent_run_id で追跡する**: spec.md, tier-ops.md
- **リラン対象を検証する**: spec.md, tier-ops.md
- **元の execution-spec.json から復元して新しい run_id で起動する**: spec.md, tier-facade.md, tier-ops.md
- **速報比較依頼だけを新規作成する**: spec.md, tier-ops.md, tier-rapid-crosscheck.md

#### 実行中止フロー

- **現在状態を確認して停止確認に応答する**: spec.md, tier-ops.md
- **実行を ABORTED へ遷移させる**: spec.md, tier-ops.md

### 実装切替業務

#### 実装切替ジョブ実行フロー

- **execution-spec.json を確定保存する**: spec.md, tier-facade.md
- **foreground slot の結果をジョブスケジューラへ中継する**: spec.md, tier-facade.md
- **slot 実行モードを選択して runner を起動する**: spec.md, tier-facade.md
- **ジョブマップで JOB_ID から実行先を解決する**: spec.md, tier-facade.md
- **業務ジョブの実行結果を確認する**: spec.md, tier-facade.md
- **実装スクリプトを実行して Runner Result を出力する**: spec.md, tier-facade.md

### 適用構成業務

#### 適用構成定義フロー

- **feature flag を設定する**: spec.md, tier-facade.md
- **slot runner の実体スクリプトを割り当てる**: spec.md, tier-facade.md
- **slot ごとのジョブマップを定義する**: spec.md, tier-facade.md
- **クロスチェックのジョブマップと比較定義を定義する**: spec.md, tier-facade.md
- **切り替えた運用モードで業務ジョブを実行する**: spec.md, tier-facade.md

### ハウスキープ業務

#### ハウスキープフロー

- **保持日数を過ぎた終了済みの実行と確報比較依頼を判定する**: spec.md, tier-facade.md, tier-ops.md
- **成果物と管理 DB の履歴を削除する**: spec.md, tier-ops.md

## 全体横断仕様

### UX Design

- User Flows: 5
- IA Pages: 18
- Psychology Principles: 8

### UI Design

- Layout Patterns: 0
- Responsive Breakpoints: 0
- Component Guidelines: 0

### Data Visualization

- Target Screens: 3
- Chart Types: 0
