# Design System: RelayGate Ops

## Overview

| 項目 | 内容 |
|------|------|
| Event ID | 20260817_153235_design_system |
| Created At | 2026-08-17T15:32:35+09:00 |
| Source | dist-design-system: RDRA/NFR/Arch フィードバックからの初期デザインシステム構築 |
| Portals | 1 |
| Components | 12 (UI: 6, Domain: 5, Common: 1) |
| Screens | 23 |

## Brand

- **Name**: RelayGate Ops
- **Primary Color**: slate-600 (#475569)
- **Secondary Color**: amber-600 (#D97706)
- **Sans Font**: Noto Sans JP, Inter, system-ui, sans-serif
- **Mono Font**: JetBrains Mono, ui-monospace, SFMono-Regular, Menlo, monospace
- **Type Scale**: xs, sm, base, lg, xl
- **Tone**: 簡潔・断定的・運用者向け。装飾語を排し、状態と次のアクションを明示する
- **Principles**: エラー/警告メッセージは原因と次アクションを1文ずつで示す, 対話確認（対象・影響範囲・取消不可の明示）は省略しない, 個人的な言い回しや絵文字を使わない
- **Logo Variants**:
  - full: `assets/logo-full.svg`
  - icon: `assets/logo-icon.svg`
  - stacked: `assets/logo-stacked.svg`

## Portals

| ID | Name | Actor | Primary Color | Screen Count |
|-----|------|-------|:-------------:|:------------:|
| ops | 運用ポータル（CLI出力／将来運用ダッシュボード） | 運用者・移行運用責任者・障害調査担当者・リリース判断者（社内・全て提供者/受益者の内部運用ロール） | #475569 | 23 |

## Design Tokens

### Primitive

- **Color Scales**: slate-900, slate-700, slate-600, slate-400, slate-200, slate-100, slate-50, white, black, green-600, green-100, red-600, red-100, amber-600, amber-100, blue-600, blue-100, violet-600, violet-100 (19 scales)
- **Spacing Scale**: space-1: 4px, space-2: 8px, space-3: 12px, space-4: 16px, space-6: 24px, space-8: 32px
- **Radius**: radius-none, radius-sm, radius-md
- **Shadow**: shadow-sm, shadow-md
- **Font Size**: fs-xs, fs-sm, fs-base, fs-lg
- **Duration**: duration-fast, duration-base

### Semantic

- **background**: var(--color-white)
- **foreground**: var(--color-slate-900)
- **border**: var(--color-slate-200)
- **success**: var(--color-green-600)
- **warning**: var(--color-amber-600)
- **destructive**: var(--color-red-600)
- **info**: var(--color-blue-600)
- **rating**: var(--color-violet-600)

### Component

- **terminal-panel**: background, foreground, font, padding, radius
- **status-badge-running**: background, foreground
- **status-badge-succeeded**: background, foreground
- **status-badge-failed**: background, foreground
- **status-badge-aborted**: background, foreground
- **status-badge-requested**: background, foreground
- **status-badge-claimed**: background, foreground
- **confirm-prompt**: background, border, destructive-border
- **banner-info**: background, foreground
- **banner-warning**: background, foreground
- **banner-error**: background, foreground
- **banner-success**: background, foreground

### Dark Mode Overrides

**Semantic overrides:**

- **background**: var(--color-slate-900)
- **foreground**: var(--color-slate-100)
- **border**: var(--color-slate-700)

**Component overrides:**

- **status-badge-succeeded**: background, foreground
- **status-badge-failed**: background, foreground
- **status-badge-requested**: background, foreground
- **status-badge-claimed**: background, foreground
- **status-badge-running**: background, foreground
- **status-badge-aborted**: background, foreground

## Components

### UI Components

| Name | Variants | Sizes |
|------|----------|-------|
| TerminalPanel | default, compact | sm, md, lg |
| StatusBadge | running, succeeded, failed, aborted, requested, claimed | sm, md |
| ConfirmPrompt | default, destructive | md |
| Banner | info, success, warning, error | md |
| ResultTable | default, compact | md |
| Button | primary, secondary, destructive | sm, md |

### Domain Components

| Name | Description | Screens |
|------|-------------|---------|
| ExecutionSpecCard | execution-spec.json（run_id/JOB_ID/host/実行ユーザー/スクリプト/固定引数・追加引数/マップ版・実装版/hang_detect_limit_minutes）を表示するカード。認証情報は参照名のみ表示し実値は表示しない | 起動slot選択画面, リラン実行画面 |
| RunnerResultPanel | Runner実行結果（started-at/stdout/stderr/exitcode）を表示するターミナル調パネル。foreground役割の応答はstdout/stderr/exitcodeのみに限定表示する | 並行稼働実行結果確認画面, 実行結果応答管理画面, 確報結果応答画面 |
| CrossCheckRequestRow | 速報比較依頼・確報比較依頼の一覧行。状態バッジ・lease期限・worker識別子を表示する | 速報クロスチェック結果確認画面, 速報比較依頼作成画面, 確報クロスチェック結果確認画面, リラン対象選定画面 |
| HangDetectionNotice | ハング検知記録（異常検知種別・検知日時・しきい値・対象slot・通知先）を表示する通知バナー／通知メール本文の共通表現 | ハング異常通知確認画面, background実行異常検知画面, 異常通知発信画面 |
| AbortConfirmDialog | blue/green background実行・速報/確報比較依頼の中止に対する対話確認。対象run_id・影響範囲・取消不可であることを明示し、y/nの二択のみ許可する | blue background中止確認画面, green background中止確認画面, 速報比較中止確認画面, 確報比較中止確認画面 |

### Common Components

| Name | Description |
|------|-------------|
| Icon | assets/icons 配下のSVGをname指定で描画する共通アイコンコンポーネント |

## Screen Mapping

### 運用ポータル（CLI出力／将来運用ダッシュボード） (ops)

| Name | Route | Components |
|------|-------|------------|
| 並行稼働実行結果確認画面 | /cli/concurrent-run/result | RunnerResultPanel, StatusBadge |
| 起動slot選択画面 | /cli/concurrent-run/select-slot | ExecutionSpecCard, Banner |
| background role起動画面 | /cli/concurrent-run/start-background | ExecutionSpecCard, RunnerResultPanel |
| 実行結果応答管理画面 | /cli/concurrent-run/respond-foreground | RunnerResultPanel |
| 速報クロスチェック結果確認画面 | /cli/rapid-crosscheck/result | CrossCheckRequestRow, StatusBadge |
| 速報比較依頼作成画面 | /cli/rapid-crosscheck/create | CrossCheckRequestRow, Banner |
| 速報クロスチェック実行画面 | /cli/rapid-crosscheck/run | RunnerResultPanel, StatusBadge |
| 確報クロスチェック結果確認画面 | /cli/final-crosscheck/result | CrossCheckRequestRow, StatusBadge |
| 確報クロスチェック実行画面 | /cli/final-crosscheck/run | CrossCheckRequestRow, RunnerResultPanel |
| 確報結果応答画面 | /cli/final-crosscheck/respond | RunnerResultPanel |
| ハング異常通知確認画面 | /cli/hang-watch/notice | HangDetectionNotice |
| background実行異常検知画面 | /cli/hang-watch/detect | HangDetectionNotice, RunnerResultPanel |
| 異常通知発信画面 | /cli/hang-watch/notify | HangDetectionNotice |
| blue background中止依頼画面 | /cli/abort/blue/request | RunnerResultPanel, Button |
| blue background中止確認画面 | /cli/abort/blue/confirm | AbortConfirmDialog |
| green background中止依頼画面 | /cli/abort/green/request | RunnerResultPanel, Button |
| green background中止確認画面 | /cli/abort/green/confirm | AbortConfirmDialog |
| 速報比較中止依頼画面 | /cli/abort/rapid-crosscheck/request | CrossCheckRequestRow, Button |
| 速報比較中止確認画面 | /cli/abort/rapid-crosscheck/confirm | AbortConfirmDialog |
| 確報比較中止依頼画面 | /cli/abort/final-crosscheck/request | CrossCheckRequestRow, Button |
| 確報比較中止確認画面 | /cli/abort/final-crosscheck/confirm | AbortConfirmDialog |
| リラン対象選定画面 | /cli/rerun/select | CrossCheckRequestRow, RunnerResultPanel |
| リラン実行画面 | /cli/rerun/run | ExecutionSpecCard, RunnerResultPanel |

## State Mapping

### background slot実行状態

| State | Label | Color | Actions |
|-------|-------|:-----:|---------|
| RUNNING | 実行中 | blue | - |
| SUCCEEDED | 正常終了 | green | - |
| FAILED | 異常終了 | red | - |
| ABORTED | 中止済み | gray | - |

### 速報比較依頼状態

| State | Label | Color | Actions |
|-------|-------|:-----:|---------|
| REQUESTED | 依頼中 | amber | - |
| CLAIMED | 取得済み | violet | - |
| RUNNING | 実行中 | blue | - |
| SUCCEEDED | 正常終了 | green | - |
| FAILED | 異常終了 | red | - |
| ABORTED | 中止済み | gray | - |

### 確報比較依頼状態

| State | Label | Color | Actions |
|-------|-------|:-----:|---------|
| REQUESTED | 依頼中 | amber | - |
| CLAIMED | 取得済み | violet | - |
| RUNNING | 実行中 | blue | - |
| SUCCEEDED | 正常終了 | green | - |
| FAILED | 異常終了 | red | - |
| ABORTED | 中止済み | gray | - |

## NFR Design Decisions

| NFR | Decision |
|-----|----------|
| 可用性 A.1.1.1（24時間無停止運用） | StatusBadge/RunnerResultPanelは常時いずれかの状態を明示し、未定義状態（空白）を許容しない。ハング検知通知は24時間いつでも発生しうる前提でBannerのみで完結する表現とする |
| 運用・保守性（障害時運用: ハング検知→運用者→移行運用責任者のエスカレーション） | HangDetectionNoticeはbanner/emailの2variantを持ち、CLI通知と将来のメール通知で同一の情報構造（run_id/検知種別/検知日時/しきい値/対象slot/通知先）を共有する |
| セキュリティ（認証情報は参照名のみ保存し実値は保存しない） | ExecutionSpecCardのcredentialRefは参照名のみを表示するpropとし、実値表示用のpropを設けない |
| 運用性（応答はstdout/stderr/exitcodeのみに限定） | RunnerResultPanelのforeground variantは比較結果・差分件数・レポートURIなどの詳細を表示せず、stdout/stderr/exitCodeのみをレンダリングする |
| 運用・保守性（対話確認による明示的なABORTED遷移） | AbortConfirmDialogは対象run_id・影響範囲を明示したうえでy/nの二択のみを許可し、誤操作防止のためdestructiveスタイル（赤系ボーダー）を強制する |
