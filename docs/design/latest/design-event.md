# Design System: RelayGate Ops

## Overview

| 項目 | 内容 |
|------|------|
| Event ID | 20260817_153235_design_system + 20260817_180235_spec_stories + 20260818_143057_design_system + 20260818_162251_spec_stories + 20260819_113049_design_system + 20260819_125615_spec_stories |
| Created At | 2026-08-19T12:56:15+09:00 (最終更新) |
| Source | dist-design-system: RDRA/NFR/Arch フィードバックからの初期デザインシステム構築 + dist-spec-stories: 全23 UC のページ Story生成 + 共通レイアウトシェル(OpsPortalShell)/Logo コンポーネント実装 + dist-design-system: feedback差分反映(CR-6078c4ed-003/005: Runner実行結果6値状態・attempt表示・run共通/slot別実行設定分離・parent_run_id系譜表示) + dist-spec-stories: feedback差分反映(CR-6078c4ed-003/005拡張コンポーネントへのページStory追随。リラン実行画面/リラン対象選定画面/background role起動画面の3画面を更新) + dist-design-system: feedback差分反映(CR-6078c4ed-008/010: RDRA状態モデル由来statesセクションの6値整合・foreground exitcode全値透過とrelay-gate退避終了コード125/124・stderr併記の表示契約) + dist-spec-stories: feedback差分反映(CR-6078c4ed-010: 実行結果応答管理画面のexitcode透過契約への整合。UnknownDashboard/AbortedDashboard/ValidationErrorDashboard追加) |
| Portals | 1 |
| Components | 14 (UI: 7, Domain: 5, Common: 2) |
| Screens | 23 |
| Page Stories | 23 |

## Brand

- **Name**: RelayGate Ops
- **Primary Color**: slate-600 (#475569)
- **Secondary Color**: amber-600 (#D97706)
- **Sans Font**: Noto Sans JP, Inter, system-ui, sans-serif
- **Mono Font**: JetBrains Mono, ui-monospace, SFMono-Regular, Menlo, monospace
- **Type Scale**: xs, sm, base, lg, xl
- **Tone**: 簡潔・断定的・運用者向け。装飾語を排し、状態と次のアクションを明示する
- **Principles**: エラー/警告メッセージは原因と次アクションを1文ずつで示す, 対話確認(対象・影響範囲・取消不可の明示)は省略しない, 個人的な言い回しや絵文字を使わない
- **Logo Variants**:
  - full: `assets/logo-full.svg`
  - icon: `assets/logo-icon.svg`
  - stacked: `assets/logo-stacked.svg`

## Portals

| ID | Name | Actor | Primary Color | Screen Count |
|-----|------|-------|:-------------:|:------------:|
| ops | 運用ポータル(CLI出力／将来運用ダッシュボード) | 運用者・移行運用責任者・障害調査担当者・リリース判断者(社内・全て提供者/受益者の内部運用ロール) | #475569 | 23 |

## Design Tokens

### Primitive

- **Color Scales**: slate-900, slate-700, slate-600, slate-400, slate-200, slate-100, slate-50, white, black, green-600, green-100, red-600, red-100, amber-600, amber-100, blue-600, blue-100, violet-600, violet-100, cyan-600, cyan-100, orange-600, orange-100 (23 scales)
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
- **status-badge-starting**: background, foreground
- **status-badge-unknown**: background, foreground
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
- **status-badge-starting**: background, foreground
- **status-badge-unknown**: background, foreground

## Components

### UI Components

| Name | Variants | Sizes |
|------|----------|-------|
| TerminalPanel | default, compact | sm, md, lg |
| StatusBadge | running, succeeded, failed, aborted, requested, claimed, starting, unknown | sm, md |
| ConfirmPrompt | default, destructive | md |
| Banner | info, success, warning, error | md |
| ResultTable | default, compact | md |
| Button | primary, secondary, destructive | sm, md |
| Logo | - | - |

### Domain Components

| Name | Description | Screens |
|------|-------------|---------|
| ExecutionSpecCard | run共通execution spec(run_id/parent_run_id/JOB_ID/固定引数・追加引数/マップ版/hang_detect_limit_minutes)とslot別実行設定(slot/host/実行ユーザー/スクリプト/作業ディレクトリ/実装版)を分離して表示するカード。再実行では系譜(parent_run_id)を明示する。認証情報は参照名のみ表示し実値は表示しない | 起動slot選択画面, リラン実行画面 |
| RunnerResultPanel | Runner実行結果(started-at/stdout/stderr/exitcode)を表示するターミナル調パネル。実行結果identityは(run_id, slot, role, attempt)でattempt_no/attempt_idを併記する。実行状態はarch正本の6値(STARTING/RUNNING/SUCCEEDED/FAILED/UNKNOWN/ABORTED)を表示し、timeout後は推測でFAILEDを表示せずUNKNOWNを明示する。foreground役割の応答はstdout/stderr/exitcodeのみに限定表示し、exitCodeは0を含む全値をそのまま表示して退避終了コードへ丸めない。relay-gate自身のエラーは退避終了コード(実行結果未確定・取得不能・中止済み=125、バリデーションエラー=124)として表示し、stderr欄にはforeground stderr.logの内容とrelay-gateのエラー内容(原因と次アクション)を併記する | 並行稼働実行結果確認画面, 実行結果応答管理画面, 確報結果応答画面 |
| CrossCheckRequestRow | 速報比較依頼・確報比較依頼の一覧行。状態バッジ・lease期限・worker識別子を表示する | 速報クロスチェック結果確認画面, 速報比較依頼作成画面, 確報クロスチェック結果確認画面, リラン対象選定画面 |
| HangDetectionNotice | ハング検知記録(異常検知種別・検知日時・しきい値・対象slot・通知先)を表示する通知バナー／通知メール本文の共通表現 | ハング異常通知確認画面, background実行異常検知画面, 異常通知発信画面 |
| AbortConfirmDialog | blue/green background実行・速報/確報比較依頼の中止に対する対話確認。対象run_id・影響範囲・取消不可であることを明示し、y/nの二択のみ許可する | blue background中止確認画面, green background中止確認画面, 速報比較中止確認画面, 確報比較中止確認画面 |

### Common Components

| Name | Description |
|------|-------------|
| Icon | assets/icons 配下のSVGをname指定で描画する共通アイコンコンポーネント |
| OpsPortalShell | 運用ポータル(ops)の共通レイアウトシェル。header(Logo+運用モードバッジ)/sidebar(5セクションナビ)/main/footer(バージョン表示)で構成。headless propでCLI単体運用時のヘッドレス表示に切替可能 |

## Screen Mapping

### 運用ポータル(CLI出力／将来運用ダッシュボード) (ops)

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
| STARTING | 起動受付 | violet | - |
| RUNNING | 実行中 | blue | - |
| SUCCEEDED | 正常終了 | green | - |
| FAILED | 異常終了 | red | - |
| UNKNOWN | 結果不明 | orange | - |
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
| 可用性 A.1.1.1(24時間無停止運用) | StatusBadge/RunnerResultPanelは常時いずれかの状態を明示し、未定義状態(空白)を許容しない。ハング検知通知は24時間いつでも発生しうる前提でBannerのみで完結する表現とする |
| 運用・保守性(障害時運用: ハング検知→運用者→移行運用責任者のエスカレーション) | HangDetectionNoticeはbanner/emailの2variantを持ち、CLI通知と将来のメール通知で同一の情報構造(run_id/検知種別/検知日時/しきい値/対象slot/通知先)を共有する |
| セキュリティ(認証情報は参照名のみ保存し実値は保存しない) | ExecutionSpecCardのcredentialRefは参照名のみを表示するpropとし、実値表示用のpropを設けない |
| 運用性(応答はstdout/stderr/exitcodeのみに限定) | RunnerResultPanelのforeground variantは比較結果・差分件数・レポートURIなどの詳細を表示せず、stdout/stderr/exitCodeのみをレンダリングする |
| 運用・保守性(対話確認による明示的なABORTED遷移) | AbortConfirmDialogは対象run_id・影響範囲を明示したうえでy/nの二択のみを許可し、誤操作防止のためdestructiveスタイル(赤系ボーダー)を強制する |
| 運用・保守性(timeout後の結果不明はUNKNOWNとし推測でFAILEDを確定しない) | RunnerResultPanel/StatusBadgeはtimeoutや結果取得不能時にunknownバッジで結果不明を明示し、failed表示への推測倒しをしない。UNKNOWNからの確定は回復処理(実結果の回収または対話確認)へ誘導する |
| 運用・保守性(relay-gate自身のエラーと業務ジョブの終了コードの区別) | RunnerResultPanelのforeground variantはexitcode.txtの値を0を含む全値そのまま表示し、relay-gate自身のエラーだけを退避終了コード(125=実行結果未確定・取得不能・中止済み、124=バリデーションエラー)として表示する。relay-gateエラー時のstderr欄はforeground stderr.logの内容とrelay-gateのエラー内容(原因と次アクション)を併記し、UNKNOWNを推測でFAILED相当の業務終了コードへ変換した表示をしない |

## Storybook Page Stories

### 運用ポータル(CLI出力／将来運用ダッシュボード) (23画面)

| 画面 | UC | Story | Variants |
|------|---|-------|----------|
| 並行稼働実行結果確認画面 | 並行稼働実行結果を確認する | Pages/運用ポータル/並行稼働実行結果確認画面 | BlueGreenComparisonDashboard, BlueGreenDivergedDashboard, NotFoundDashboard, BlueGreenComparisonHeadless |
| 起動slot選択画面 | feature flag設定に基づきslotを選択して起動する | Pages/運用ポータル/起動slot選択画面 | ConcurrentModeDashboard, GreenSoloModeDashboard, BothForegroundRejectedDashboard, JobMapUnresolvedDashboard, ConcurrentModeHeadless |
| background role起動画面 | background roleを起動する | Pages/運用ポータル/background role起動画面 | StartedDashboard, StartFailedDashboard, StartUnknownDashboard, StartedHeadless |
| 実行結果応答管理画面 | foreground roleの標準出力・標準エラー・終了コードを応答する | Pages/運用ポータル/実行結果応答管理画面 | SucceededDashboard, FailedDashboard, UnresolvedDashboard, UnknownDashboard, AbortedDashboard, ValidationErrorDashboard, SucceededHeadless |
| 速報クロスチェック結果確認画面 | 速報クロスチェック結果を確認する | Pages/運用ポータル/速報クロスチェック結果確認画面 | OkDashboard, NgDashboard, NotFoundDashboard, ValidationErrorDashboard, NgHeadless |
| 速報比較依頼作成画面 | blue/green runnerの完了通知を受けて速報比較依頼を作成する | Pages/運用ポータル/速報比較依頼作成画面 | CreatedDashboard, NoneCreatedDashboard, ModeOffDashboard, FailedDashboard, CreatedHeadless |
| 速報クロスチェック実行画面 | 速報クロスチェックを実行し差分を検知する | Pages/運用ポータル/速報クロスチェック実行画面 | NoDiffDashboard, DiffDetectedDashboard, FailedDashboard, NoTargetsDashboard, DiffDetectedHeadless |
| 確報クロスチェック結果確認画面 | 確報クロスチェック結果を確認する | Pages/運用ポータル/確報クロスチェック結果確認画面 | SucceededDashboard, FailedDashboard, NotFoundDashboard, ValidationErrorDashboard, SucceededHeadless |
| 確報クロスチェック実行画面 | 全テーブル・全ファイルを対象に確報クロスチェックを実行する | Pages/運用ポータル/確報クロスチェック実行画面 | SucceededDashboard, FailedDashboard, NoTargetsDashboard, SucceededHeadless |
| 確報結果応答画面 | 確報クロスチェック結果をstdout/stderr/exitcodeで応答する | Pages/運用ポータル/確報結果応答画面 | SucceededDashboard, FailedDashboard, SucceededHeadless, UndeterminedHeadless |
| ハング異常通知確認画面 | ハング疑い・異常の通知を確認する | Pages/運用ポータル/ハング異常通知確認画面 | ListDashboard, FilteredByRunIdDashboard, EmptyDashboard, ValidationErrorDashboard, ListHeadless |
| background実行異常検知画面 | background実行の未完了・非0終了・速報比較異常を定期検知する | Pages/運用ポータル/background実行異常検知画面 | DetectedDashboard, NoDetectionDashboard, FailedDashboard, DetectedHeadless |
| 異常通知発信画面 | ハング疑い・異常を運用者へ通知する | Pages/運用ポータル/異常通知発信画面 | BannerDashboard, EmailDashboard, NoneToNotifyDashboard, FailedDashboard, BannerHeadless, EmailHeadless |
| blue background中止依頼画面 | blue background実行の中止を依頼する | Pages/運用ポータル/blue background中止依頼画面 | Dashboard, Accepted, ValidationError, Headless |
| blue background中止確認画面 | 対話確認のうえblue background実行をABORTEDへ遷移させる | Pages/運用ポータル/blue background中止確認画面 | Dashboard, Success, Error, Headless |
| green background中止依頼画面 | green background実行の中止を依頼する | Pages/運用ポータル/green background中止依頼画面 | Dashboard, Accepted, ValidationError, Headless |
| green background中止確認画面 | 対話確認のうえgreen background実行をABORTEDへ遷移させる | Pages/運用ポータル/green background中止確認画面 | Dashboard, Success, Error, Headless |
| 速報比較中止依頼画面 | RUNNING中の速報比較依頼の中止を依頼する | Pages/運用ポータル/速報比較中止依頼画面 | Dashboard, Accepted, ValidationError, Headless |
| 速報比較中止確認画面 | 対話確認のうえ速報比較依頼をABORTEDへ遷移させる | Pages/運用ポータル/速報比較中止確認画面 | Dashboard, Success, Error, Headless |
| 確報比較中止依頼画面 | RUNNING中の確報比較依頼の中止を依頼する | Pages/運用ポータル/確報比較中止依頼画面 | Dashboard, Accepted, ValidationError, Headless |
| 確報比較中止確認画面 | 対話確認のうえ確報比較依頼をABORTEDへ遷移させる | Pages/運用ポータル/確報比較中止確認画面 | Dashboard, Success, Error, Headless |
| リラン対象選定画面 | 再実行対象のbackground実行・速報比較依頼を選択する | Pages/運用ポータル/リラン対象選定画面 | BackgroundCandidatesDashboard, RapidCrosscheckCandidatesDashboard, EmptyDashboard, BackgroundCandidatesHeadless |
| リラン実行画面 | execution-spec.jsonの実行設定を保ったまま再実行する | Pages/運用ポータル/リラン実行画面 | AcceptedDashboard, RerunFailedDashboard, AcceptedHeadless |
