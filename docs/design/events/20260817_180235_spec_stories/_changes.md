# 変更サマリ

- event_id: 20260817_180235_spec_stories
- trigger_event: design:20260817_153235_design_system

## 追加

- components.ui: Logo（`src/components/ui/Logo.tsx`。brand.logo.variants の full/icon/stacked を variant 指定で描画）
- components.common: OpsPortalShell（`src/components/common/OpsPortalShell.tsx`。運用ポータルの共通レイアウトシェル。header/sidebar/main/footer構成、headless propでCLI単体運用時のヘッドレス表示に切替）
- screens: 全23画面に `story` パス（`src/stories/Pages/運用ポータル/{画面名}.stories.tsx`）と `variants`（Story named export 一覧）を付与
  - 並行稼働実行結果確認画面 / 起動slot選択画面 / background role起動画面 / 実行結果応答管理画面
  - 速報クロスチェック結果確認画面 / 速報比較依頼作成画面 / 速報クロスチェック実行画面
  - 確報クロスチェック結果確認画面 / 確報クロスチェック実行画面 / 確報結果応答画面
  - ハング異常通知確認画面 / background実行異常検知画面 / 異常通知発信画面
  - blue background中止依頼画面 / blue background中止確認画面
  - green background中止依頼画面 / green background中止確認画面
  - 速報比較中止依頼画面 / 速報比較中止確認画面
  - 確報比較中止依頼画面 / 確報比較中止確認画面
  - リラン対象選定画面 / リラン実行画面
- storybook-app/ に layout Story（`src/stories/layout/OpsPortalShell.stories.tsx`）を追加

## 変更

- storybook.categories.screens: `Screens/*` → `Pages/*`（spec-stories スキルの配置パス規約 `src/stories/Pages/{ポータル名}/{画面名}.stories.tsx` に合わせて実際のカテゴリ構造と一致させた）
- src/components/ui/Logo.stories.tsx: 既存の raw `<img>` タグ実装から新規 Logo コンポーネント使用に更新（表示内容は変更なし）
- 異常通知発信画面の既存 `variants: [banner, email]`（component-level）は、より詳細な Story variants 一覧（BannerDashboard/EmailDashboard等、banner/email両方を包含）に置き換え

## 削除

なし

## 反証レビュー結果（round 1）

- major 1件: `storybook.categories.screens` の宣言（`Screens/*`）と実装（`Pages/*`）の不一致 → 本イベントで `Pages/*` に更新して解消
- minor 1件: リラン系2画面の `activeNavKey` が `concurrent-run` になっており実行制御ナビゲーションと不整合 → `control` に修正済み（Story側で解消。design-event.yaml側の変更は不要）
- minor 1件: Logo/OpsPortalShell が design-event.yaml 未宣言 → 本イベントで components.ui / components.common に追加して解消
- 詳細は `_review/round-1.yaml` を参照
