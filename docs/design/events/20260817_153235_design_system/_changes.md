# 変更内容（初期構築）

このイベントは RelayGate の初回デザインシステム構築であり、以下すべてを「追加」として記録する。

## 追加

- **brand**: RelayGate Ops（primary: slate-600 #475569 / secondary: amber-600 #D97706 / sans: Noto Sans JP+Inter / mono: JetBrains Mono）
- **portals**: 1件（ops = 運用ポータル: CLI出力／将来運用ダッシュボード）
- **tokens**: primitive（colors/spacing/radius/shadow/font_size/font_family/font_weight/duration）、
  semantic（background/foreground/border/success/warning/destructive/info/rating）、
  component（terminal-panel, status-badge-*×6, confirm-prompt, banner-*×4）、dark_overrides
- **components.ui**: TerminalPanel, StatusBadge, ConfirmPrompt, Banner, ResultTable, Button（6件）
- **components.domain**: ExecutionSpecCard, RunnerResultPanel, CrossCheckRequestRow, HangDetectionNotice, AbortConfirmDialog（5件）
- **components.common**: Icon（1件）
- **screens**: RDRA BUC.tsv の「画面」列23件をCLIタッチポイントとしてマッピング
- **states**: background slot実行状態 / 速報比較依頼状態 / 確報比較依頼状態（3モデル）
- **nfr_decisions**: 5件（可用性・運用性×2・セキュリティ・運用保守性）
- **assets**: logo-full.svg / logo-icon.svg / logo-stacked.svg、icons 8件
  （check, x-circle, alert-triangle, clock, refresh-cw, terminal, mail, chevron-right）
- **decisions**: design-decision-001（適用範囲の判断）, design-decision-002（ブランド/トークン/コンポーネントスタイル採用）
- **storybook-app**: Next.js 15 + TypeScript + Tailwind CSS + Storybook 10 (CSF3) 一式
  （UI 6コンポーネント、Domain 5コンポーネント、Brand（Logo/Icons）、Foundations（Introduction/DesignTokens/ScreenMapping）のStories/MDX）

## docs/todo.md への登録

- DIST-022: 将来運用ダッシュボードのレイアウト/画面構成が未確定（confidence: low、仮採用）
