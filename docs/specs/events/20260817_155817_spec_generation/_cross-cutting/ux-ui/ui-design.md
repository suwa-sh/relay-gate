# UI デザイン仕様（RelayGate）

> 前提: 主インターフェースは CLI（標準出力・標準エラー・終了コード）である。本書のレイアウト・レスポンシブ規定は
> design-event.yaml が定義する「運用ポータル（CLI出力／将来運用ダッシュボード）」（portal id: `ops`）が
> 将来 Web/TUI ダッシュボードとして実装される場合に適用する仕様であり、CLI 単体運用時は「ターミナル出力レイアウト」
> の節を正本とする。

## レイアウトパターン

### 運用（ops）ポータル

- **レイアウト構成**: ヘッダー（システム名 + 現在の運用モード表示）+ サイドバー（並行稼働実行/速報クロスチェック/確報クロスチェック/ハング監視/実行制御のセクションナビ）+ メインコンテンツ（TerminalPanel または ResultTable）
- **ヘッダー**: 固定。現在の運用モード（並行稼働／新実装単独本番／次世代実装との並行稼働。バリエーション: 運用モード）をBadgeで常時表示する
- **サイドバー**: 折りたたみ可能。CLI操作時は非表示（ヘッドレス相当）とし、ダッシュボード時のみ表示する
- **コンテンツエリア**: フルwidth。TerminalPanelはmonospaceフォントで等幅表示を維持する

### ターミナル出力レイアウト（CLI単体運用時の正本）

- **標準出力**: stdout.log 相当の内容をそのままCLI標準出力へ流す。整形は行末の改行以外加えない（ジョブスケジューラ側でのパース可能性を損なわないため）
- **標準エラー**: stderr.log 相当の内容をCLI標準エラーへ流す
- **終了コード**: exitcode.txt の値をプロセス終了コードとして返す
- **対話確認プロンプト（ConfirmPrompt）**: 中止操作時のみ、TTY接続時に対象・影響範囲・取消不可の明示とy/nの二択を標準出力/標準入力で提示する。非TTY（バッチ実行）時は対話確認をスキップせず、明示的な `--yes` 相当のフラグ未指定であればエラー終了する

### 共通レイアウト要素

| 要素 | デザインシステムコンポーネント | 配置 |
|------|------------------------------|------|
| 運用モードバッジ | StatusBadge（バリエーション: running等を運用モード表示に流用） | ヘッダー |
| セクションナビ | （共通コンポーネントとして Step4c で抽出） | サイドバー |
| フッター（バージョン/マップ版表示） | （共通コンポーネントとして Step4c で抽出） | フッター |

## レスポンシブ戦略

### ブレイクポイント

| 名称 | 幅 | レイアウト変更 |
|------|---|-------------|
| Mobile | < 640px | 将来ダッシュボードでは非対応（社内運用端末・踏み台サーバからのアクセスに限定されるため、モバイル最適化は対象外とする） |
| Tablet | 640px - 1024px | サイドバーを折りたたみ、ResultTableを横スクロール表示に切替 |
| Desktop | > 1024px | サイドバー常時表示、ResultTable全カラム表示 |

### モバイル対応方針

- **ナビゲーション**: 対象外（CTP-003 利用制限により運用端末・踏み台サーバ等の特定接続元からのSSH/社内アクセスに限定されるため）
- **テーブル**: Tablet幅ではResultTableを横スクロール表示に切替
- **フォーム**: ConfirmPromptはCLI/ダッシュボードいずれも単一ステップの二択に留め、複数ステップのウィザード化は行わない（対話確認の即応性を優先）

## デザインシステムコンポーネント利用ガイドライン

### コンポーネント選定ルール

| 用途 | 推奨コンポーネント | 非推奨 | 理由 |
|------|-----------------|--------|------|
| 実行結果（stdout/stderr/exitcode）表示 | RunnerResultPanel | ResultTable単体 | ターミナル調表示（TerminalPanel）でログの原文性を保つため |
| 速報/確報比較依頼の一覧 | CrossCheckRequestRow + ResultTable | ExecutionSpecCard | 一覧表示にはCrossCheckRequestRowの状態・lease情報が必須のため |
| 中止操作の確認 | AbortConfirmDialog | ConfirmPrompt単体（ダッシュボード時） | 対象・影響範囲・取消不可の明示が必須のため、汎用ConfirmPromptではなく専用ダイアログを使う |
| 異常通知 | HangDetectionNotice（banner/email） | Banner単体 | 異常検知種別・しきい値・対象slotなど専用属性の表示が必要なため |

### 状態表示パターン

| 状態モデル | 表示方法 | コンポーネント | カラートークン |
|-----------|---------|-------------|-------------|
| background slot実行状態 | Badge | StatusBadge（running/succeeded/failed/aborted） | RUNNING=blue, SUCCEEDED=green, FAILED=red, ABORTED=gray |
| 速報比較依頼状態 | Badge | StatusBadge（requested/claimed/running/succeeded/failed/aborted） | REQUESTED=amber, CLAIMED=violet, RUNNING=blue, SUCCEEDED=green, FAILED=red, ABORTED=gray |
| 確報比較依頼状態 | Badge | StatusBadge（requested/claimed/running/succeeded/failed/aborted） | 速報比較依頼状態と同一トークンを使用し、速報/確報の区別はCrossCheckRequestRowのvariant（rapid/final）で行う |

## ダークモード対応方針

- **切替方式**: システム設定連動（将来ダッシュボード実装時）。CLI出力はターミナルのテーマに従うため本システム側では制御しない
- **トークン戦略**: design-event.yaml の primitive/semantic トークンに準拠し、`dark_overrides` が定義される場合はそれを参照する
- **注意事項**: StatusBadgeの色（blue/green/red/amber/violet/gray）はダークモードでもコントラスト比WCAG AA（4.5:1以上）を維持するトーン調整を行う
