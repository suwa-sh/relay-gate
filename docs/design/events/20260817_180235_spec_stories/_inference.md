# 推論根拠

## 前提

RelayGate は Web UI を持たない CLI/バッチ運用基盤であり、`docs/specs/latest/` には tier-frontend-*.md
が存在しない（tier-facade.md / tier-worker.md のみ）。design-event.yaml の portal は `ops` の1つのみで、
「画面」は CLI 標準出力・標準エラー・終了コード、対話確認プロンプト、将来運用ダッシュボードの3形態を統合的に
表現したもの（`docs/specs/latest/_cross-cutting/ux-ui/ux-design.md` 冒頭の前提を踏襲）。

## Story 構成方針

- 各画面に「dashboard variant」（OpsPortalShell でラップした将来ダッシュボード表現）と「headless variant」
  （CLI単体運用時のターミナル出力そのままの表現）の両方を用意した。design-event.yaml の states/
  nfr_decisions が定義する状態（RUNNING/SUCCEEDED/FAILED/ABORTED、REQUESTED/CLAIMED 等）ごとに正常系・
  異常系の named export を分けた。
- 共通コンポーネント（RunnerResultPanel/CrossCheckRequestRow/ExecutionSpecCard/HangDetectionNotice/
  AbortConfirmDialog/StatusBadge/Banner/Button/ResultTable/TerminalPanel/ConfirmPrompt/Icon）は
  design-event.yaml の components セクションと `docs/specs/latest/_cross-cutting/ux-ui/
  common-components.md` の記述に厳密に従い、UC 固有の新規ドメインコンポーネントは追加しなかった
  （23 UC 全てが既存コンポーネントの組み合わせで表現可能と判断した）。

## OpsPortalShell（新規共通レイアウトシェル）

`docs/specs/latest/_cross-cutting/ux-ui/common-components.md` の「共通レイアウトシェル」節（ヘッダー固定+
サイドバー折りたたみ可能+メインコンテンツ+フッター）と `ui-design.md` の「運用（ops）ポータル」レイアウト
パターンをそのまま実装した。`headless` prop で CLI 単体運用時（ヘッダー/サイドバー/フッターを省いた
ターミナル出力のみ）に切り替えられる設計とし、「CLI単体運用時は上記シェルを持たず、ターミナル出力レイアウト
が正本」という ui-design.md の記述に対応した。

## Logo（新規コンポーネント）

design-event.yaml の `brand.logo.variants`（full/icon/stacked）を参照する実装コンポーネントとして新規
作成した。従来は `Logo.stories.tsx` が raw `<img>` タグで直接 SVG パスを参照していたが、OpsPortalShell の
ヘッダーで再利用するために共通コンポーネント化した。

## 反証レビューで発見した問題と対応

1. **ダークモードでのロゴ視認性低下**（画面確認フェーズで発見）: `logo-full.svg` は固定色（#0F172A近似黒の
   テキスト）で描画されており、OpsPortalShell のヘッダー背景をテーマ変数 `var(--background)` にすると、
   ダークモード時にテキストが背景に溶けて視認できなくなった。ヘッダー背景を常に固定の白背景
   （ブランドヘッダーとして扱う）に変更して解消した。
2. **`storybook.categories.screens` の宣言と実装の不一致**（反証レビュー round 1 で発見、major）:
   design-event.yaml の既存宣言は `Screens/*` だったが、spec-stories スキルの配置パス規約により
   実装は `Pages/{ポータル名}/{画面名}` とした。本イベントで宣言を `Pages/*` に更新して一致させた。
3. **リラン系画面の activeNavKey 不整合**（反証レビュー round 1 で発見、minor）: 「実行制御業務/background側
   リランフロー」に属する2画面（リラン対象選定画面・リラン実行画面）が `activeNavKey: 'concurrent-run'`
   になっていた（並列生成時の担当割り当てミス）。実行制御セクション（`control`）に修正した。
