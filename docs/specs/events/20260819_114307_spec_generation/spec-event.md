# Spec Event Summary

## Overview

| 項目 | 内容 |
|------|------|
| Event ID | 20260819_114307_spec_generation |
| Created At | 2026-08-19T11:43:07+09:00 |
| Source | dist-spec: feedback差分反映(reconciliation専用stage。CR-6078c4ed-008/009/010の上流確定内容への仕様追随) |
| UC 総数 | 23 |
| API 総数 | 24 |
| 非同期イベント総数 | 0 |
| 業務数 | 4 |
| BUC 数 | 9 |

## UC 一覧

| 業務 | BUC | UC | API数 | 非同期 | インフラ |
|------|-----|-----|:-----:|:-----:|:-------:|
| 並行稼働実行業務 | 並行稼働実行フロー | 並行稼働実行結果を確認する | 1 | - | - |
| 並行稼働実行業務 | 並行稼働実行フロー | feature flag設定に基づきslotを選択して起動する | 1 | - | - |
| 並行稼働実行業務 | 並行稼働実行フロー | background roleを起動する | 2 | - | - |
| 並行稼働実行業務 | 並行稼働実行フロー | foreground roleの標準出力・標準エラー・終了コードを応答する | 1 | - | - |
| クロスチェック業務 | 速報クロスチェックフロー | 速報クロスチェック結果を確認する | 1 | - | - |
| クロスチェック業務 | 速報クロスチェックフロー | blue/green runnerの完了通知を受けて速報比較依頼を作成する | 1 | - | - |
| クロスチェック業務 | 速報クロスチェックフロー | 速報クロスチェックを実行し差分を検知する | 1 | - | - |
| クロスチェック業務 | 確報クロスチェックフロー | 確報クロスチェック結果を確認する | 1 | - | - |
| クロスチェック業務 | 確報クロスチェックフロー | 全テーブル・全ファイルを対象に確報クロスチェックを実行する | 1 | - | - |
| クロスチェック業務 | 確報クロスチェックフロー | 確報クロスチェック結果をstdout/stderr/exitcodeで応答する | 1 | - | - |
| 実行監視業務 | ハング監視フロー | ハング疑い・異常の通知を確認する | 1 | - | - |
| 実行監視業務 | ハング監視フロー | background実行の未完了・非0終了・速報比較異常を定期検知する | 1 | - | - |
| 実行監視業務 | ハング監視フロー | ハング疑い・異常を運用者へ通知する | 1 | - | - |
| 実行制御業務 | blue中止フロー | blue background実行の中止を依頼する | 1 | - | - |
| 実行制御業務 | blue中止フロー | 対話確認のうえblue background実行をABORTEDへ遷移させる | 1 | - | - |
| 実行制御業務 | green中止フロー | green background実行の中止を依頼する | 1 | - | - |
| 実行制御業務 | green中止フロー | 対話確認のうえgreen background実行をABORTEDへ遷移させる | 1 | - | - |
| 実行制御業務 | 速報比較中止フロー | RUNNING中の速報比較依頼の中止を依頼する | 1 | - | - |
| 実行制御業務 | 速報比較中止フロー | 対話確認のうえ速報比較依頼をABORTEDへ遷移させる | 1 | - | - |
| 実行制御業務 | 確報比較中止フロー | RUNNING中の確報比較依頼の中止を依頼する | 1 | - | - |
| 実行制御業務 | 確報比較中止フロー | 対話確認のうえ確報比較依頼をABORTEDへ遷移させる | 1 | - | - |
| 実行制御業務 | background側リランフロー | 再実行対象のbackground実行・速報比較依頼を選択する | 1 | - | - |
| 実行制御業務 | background側リランフロー | execution-spec.jsonの実行設定を保ったまま再実行する | 1 | - | - |

## UC ファイル構成

### 並行稼働実行業務

#### 並行稼働実行フロー

- **並行稼働実行結果を確認する**: spec.md, tier-facade.md
- **feature flag設定に基づきslotを選択して起動する**: spec.md, tier-facade.md
- **background roleを起動する**: spec.md, tier-facade.md, tier-worker.md
- **foreground roleの標準出力・標準エラー・終了コードを応答する**: spec.md, tier-facade.md

### クロスチェック業務

#### 速報クロスチェックフロー

- **速報クロスチェック結果を確認する**: spec.md, tier-worker.md
- **blue/green runnerの完了通知を受けて速報比較依頼を作成する**: spec.md, tier-worker.md
- **速報クロスチェックを実行し差分を検知する**: spec.md, tier-worker.md

#### 確報クロスチェックフロー

- **確報クロスチェック結果を確認する**: spec.md, tier-worker.md
- **全テーブル・全ファイルを対象に確報クロスチェックを実行する**: spec.md, tier-worker.md
- **確報クロスチェック結果をstdout/stderr/exitcodeで応答する**: spec.md, tier-worker.md

### 実行監視業務

#### ハング監視フロー

- **ハング疑い・異常の通知を確認する**: spec.md, tier-worker.md
- **background実行の未完了・非0終了・速報比較異常を定期検知する**: spec.md, tier-worker.md
- **ハング疑い・異常を運用者へ通知する**: spec.md, tier-worker.md

### 実行制御業務

#### blue中止フロー

- **blue background実行の中止を依頼する**: spec.md, tier-facade.md
- **対話確認のうえblue background実行をABORTEDへ遷移させる**: spec.md, tier-facade.md

#### green中止フロー

- **green background実行の中止を依頼する**: spec.md, tier-facade.md
- **対話確認のうえgreen background実行をABORTEDへ遷移させる**: spec.md, tier-facade.md

#### 速報比較中止フロー

- **RUNNING中の速報比較依頼の中止を依頼する**: spec.md, tier-worker.md
- **対話確認のうえ速報比較依頼をABORTEDへ遷移させる**: spec.md, tier-worker.md

#### 確報比較中止フロー

- **RUNNING中の確報比較依頼の中止を依頼する**: spec.md, tier-worker.md
- **対話確認のうえ確報比較依頼をABORTEDへ遷移させる**: spec.md, tier-worker.md

#### background側リランフロー

- **再実行対象のbackground実行・速報比較依頼を選択する**: spec.md, tier-facade.md, tier-worker.md
- **execution-spec.jsonの実行設定を保ったまま再実行する**: spec.md, tier-facade.md, tier-worker.md

## 全体横断仕様

### UX Design

- User Flows: 6
- IA Pages: 23
- Psychology Principles: 5

### UI Design

- Layout Patterns: 2
- Responsive Breakpoints: 3
- Component Guidelines: 4

### Data Visualization

- Target Screens: 5
- Chart Types: 3
