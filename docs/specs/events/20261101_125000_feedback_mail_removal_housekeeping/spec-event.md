# Spec Event Summary

## Overview

| 項目 | 内容 |
|------|------|
| Event ID | 20261101_125000_feedback_mail_removal_housekeeping |
| Created At | 2026-11-01T12:50:00Z |
| Source | Spec 差分更新(design 無しモード。2026-11-01 のメール通知廃止・ハウスキープ新設・env 値の空白規則)。CR-e4ea8aaa-003(spec 直接所有): CLI 契約 config_input_rules.env_files に env 値の取り出し方を順序つき規則(最初の = で分割 → キーの前後の空白 → 値の前後の空白 → 引用符を独立に外す。空白は半角空白とタブ、CR は既存のバイト検査で拒否)で書き、例 4 件を添え、compare_command_argv.split の再掲にも反映した。実装は変えず VT / FF の差分を記録(spec-decision-022)。CR-e4ea8aaa-001(上流追従): hang-detector.sh の通知を終了コード 0 / 3(ハング疑いだけ・警告終了)/ 6(実行エラー・比較異常、または自身の実行エラー)と標準エラーの alert 行 1 件 1 行に改め、off の通知済みの判定を $RELAY_GATE_ARTIFACT_ROOT/hang-detector-notified/<run_id>.<role> で行う。hang-detector.env のメール 3 キー・AsyncAPI の通知メールチャネル・ui-design.md の通知メール規約を削除し、UC「background 異常の通知メールを受け取る」を「ハング検知ジョブの異常終了を確認する」へ改名(spec-decision-020)。CR-e4ea8aaa-002(上流追従): ハウスキープ業務 / ハウスキープフローの 2 UC を新設し、housekeep.sh・housekeep.env(HOUSEKEEP_RETENTION_DAYS 既定 90 / HOUSEKEEP_DB_CONN_REF)・validate-config.sh --housekeep・削除待ちの置き場 housekeep-pending/・専用 DB ロール housekeep_del・削除順序と回復・run ディレクトリ列挙の規則を契約と rdb-schema に追加(spec-decision-021) |
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
