# デザインシステム推論根拠

## 1. ポータル構成

- アクター.tsv から4アクター（運用者・移行運用責任者・障害調査担当者・リリース判断者）を抽出。
  全て社内・内部運用ロールであり、外部利用者は存在しない。
- 立場（提供者/受益者）はフロー単位で異なるが、いずれも同一の運用チーム内で完結し、
  Web UIも存在しないため、ポータルを役割ごとに分割する必要性がない。
- → ポータルは単一「ops」（運用ポータル: CLI出力/将来運用ダッシュボード）とした。

## 2. 画面（screens）の解釈

- BUC.tsv の「画面」列には23件のエントリが存在するが、arch-design.yaml でフロントエンドティアが
  不要と判定されているため、これらはWebページではなくCLI上の入出力ポイント（対話確認・結果表示・
  通知確認）として解釈した。
- route は `/cli/{業務flow}/{ステップ}` の形式でCLIコマンド/フローの一意な識別に用い、
  実際のURLルーティングではない（design-event.yamlのschema要件を満たすための表現）。

## 3. トークン設計

- primitive: 色（slate系ニュートラル + 状態色5系統）・spacing・radius・shadow・font_size/family/weight・duration
- semantic: background/foreground/border + success/warning/destructive/info/rating
- component: terminal-panel（CLI出力パネル）、status-badge-*（6状態）、confirm-prompt、banner-*（4種）
- dark_overrides: status-badge系のみ半透明rgba値でオーバーライド（design-lessons-learnedの教訓に準拠）
- レイアウト・スペーシングの具体的なグリッド定義は、実画面が存在しないため本イベントでは策定せず、
  spacing primitiveのみ定義した（docs/todo.md DIST-022参照）。

## 4. ドメインコンポーネント

情報.tsv・状態.tsv から以下を導出:
- execution-spec.json → ExecutionSpecCard（認証情報は参照名のみ、実値は表示しない = NFRセキュリティ要件）
- Runner実行結果 → RunnerResultPanel（foreground/background variant、4状態）
- 速報比較依頼/確報比較依頼 → CrossCheckRequestRow（rapid/final variant、6状態）
- ハング検知記録 → HangDetectionNotice（banner/email variant = 運用者通知と将来メール通知の共通表現）
- 対話確認（blue/green中止、速報/確報比較中止）→ AbortConfirmDialog（y/n二択、destructiveスタイル）

## 5. NFRからの設計判断

- 可用性 A.1.1.1（24時間無停止）→ StatusBadge/RunnerResultPanelは未定義状態を許容しない
- 運用性（ハング検知→運用者→移行運用責任者のエスカレーション）→ HangDetectionNoticeのbanner/email共通構造
- セキュリティ（認証情報は参照名のみ保存）→ ExecutionSpecCardのcredentialRefは参照名のみ
- 運用性（応答はstdout/stderr/exitcodeのみ）→ RunnerResultPanel foreground variantの表示項目制限
- 運用・保守性（対話確認による明示的なABORTED遷移）→ AbortConfirmDialogのdestructiveスタイル強制

## 6. アーキテクチャからの技術判断

- presentation層がCLI入出力のみ（arch-design.yaml L-facade-presentation/L-worker-presentation）
  であるため、Storybookは「将来のWeb実装に備えたトークン検証環境」という位置づけとし、
  Next.js + Tailwind CSSの一般的な構成を採用（デプロイ先はオンプレLinuxでStorybook自体は開発時ツール）。
