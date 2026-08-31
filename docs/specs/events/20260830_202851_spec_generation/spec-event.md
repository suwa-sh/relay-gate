# Spec Event Summary

## Overview

| 項目 | 内容 |
|------|------|
| Event ID | 20260830_202851_spec_generation |
| Created At | 2026-08-30T20:28:51 |
| Source | Spec 生成: 初期構築(design 無しモード。UI 画面なし・CLI と定期ジョブのみ)。trigger_event: rdra:20260830_181841_initial_build, arch:20260830_202427_arch_infra_feedback_20260830_190412_infra_product_design |
| UC 総数 | 32 |
| API 総数 | 0 |
| 非同期イベント総数 | 4 |
| 業務数 | 5 |
| BUC 数 | 7 |

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
| 実行監視業務 | background 実行監視フロー | background 異常の通知メールを受け取る | 0 | - | - |
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

- **background 異常の通知メールを受け取る**: spec.md, tier-ops.md
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
- **クロスチェックのジョブマップと比較定義を定義する**: spec.md, tier-final-crosscheck.md, tier-rapid-crosscheck.md
- **切り替えた運用モードで業務ジョブを実行する**: spec.md, tier-facade.md

## 全体横断仕様

### UX Design

- User Flows: 4
- IA Pages: 18
- Psychology Principles: 8

### UI Design

- Layout Patterns: 0
- Responsive Breakpoints: 0
- Component Guidelines: 0

### Data Visualization

- Target Screens: 3
- Chart Types: 0
