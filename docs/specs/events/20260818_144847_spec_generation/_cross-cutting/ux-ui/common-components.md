# 共通コンポーネント設計

## 概要

23個の UC（tier-facade.md / tier-worker.md）の「CLI 出力/画面表示マッピング」節を横断的に俯瞰し、
複数 UC で共通して出現するコンポーネント利用パターンを抽出する。

RelayGate は CLI が主インターフェースであり、`design-event.yaml` のコンポーネントは「CLI 出力の構造」を
表現するための論理コンポーネントとして使われている（例: RunnerResultPanel はターミナル調の stdout/stderr/exitCode
表示を抽象化したもの）。将来運用ポータル（ops）を Web/TUI ダッシュボードとして実装する際は、本書のパターンを
そのまま画面コンポーネント構成に転用できる。

本書の目的は次の3点である。

- 個々の UC 仕様に重複記述されているコンポーネント選定・状態表現ルールを1箇所に集約し、保守性を高める
- 「二段階中止確認」「状態一覧+フィルター」「実行結果ターミナル表示」という3つの反復パターンを名前付きで定義し、UC 仕様から参照可能にする
- ローディング/エラー/空状態という横断的な状態表現を `design-event.yaml` の `states` セクションと対応付ける

## design-event.yaml 既存コンポーネントとの関係

23 UC の CLI 出力/画面表示マッピング表に出現した回数（同一 UC 内で facade/worker 両方に登場しても1UCとして1回のみカウント）は以下のとおり。

| コンポーネント | 利用UC数 | 用途の要旨 |
|---|---|---|
| RunnerResultPanel | 11 | stdout/stderr/exitCode のターミナル調表示（background/foreground variant） |
| CrossCheckRequestRow | 8 | 速報/確報比較依頼の一覧行（rapid/final variant） |
| StatusBadge | 5 | 実行状態・依頼状態の色分けバッジ |
| Banner | 6 | 受理/完了/エラー等の即時フィードバック |
| Button | 4 | 中止依頼などの破壊的操作トリガー（CLI ではコマンド実行に読み替え） |
| AbortConfirmDialog | 4 | 中止操作の対話確認（y/n 二択） |
| ExecutionSpecCard | 3 | execution-spec.json の内容確認表示 |
| HangDetectionNotice | 3 | ハング疑い・異常検知の通知（banner/email variant） |
| ResultTable | 1 | OK/NG判定・差分件数の表示（Progressive Disclosure） |
| TerminalPanel | 0（間接利用） | RunnerResultPanel の内部実装として terminal-panel トークン（背景 slate-900 等）を介して利用される。UC からの直接参照はない |
| ConfirmPrompt | 0（間接言及のみ） | ui-design.md ではダッシュボード時の中止操作に非推奨（AbortConfirmDialog を使う）。CLI 単体運用時の TTY 対話確認の下地として概念上のみ存在 |
| Icon | 0（直接記述なし） | 各コンポーネント内部装飾として暗黙利用される想定。UC マッピング表への単独登場はない |

RunnerResultPanel と CrossCheckRequestRow の2つで全23 UC中19 UC（重複除く）をカバーしており、
この2コンポーネントが本システムの画面表現の中核であることが分かる。

## 共通レイアウトシェル

ui-design.md の「運用（ops）ポータル」節に基づく、将来ダッシュボード実装時の共通レイアウト構成。

- **ヘッダー（固定）**: システム名 + 現在の運用モード（並行稼働／新実装単独本番／次世代実装との並行稼働）を StatusBadge で常時表示
- **サイドバー（折りたたみ可能）**: 並行稼働実行/速報クロスチェック/確報クロスチェック/ハング監視/実行制御のセクションナビ。CLI操作時は非表示（ヘッドレス相当）
- **メインコンテンツ（フルwidth）**: TerminalPanel（RunnerResultPanel 内部利用）または ResultTable。TerminalPanel は monospace フォント（JetBrains Mono 等）で等幅表示を維持
- **フッター**: バージョン/マップ版表示（Step4c で独立コンポーネントとして抽出予定、本書では以下「フッター（バージョン表示）」として定義）

CLI単体運用時は上記シェルを持たず、「ターミナル出力レイアウト」（stdout/stderr/exitcode の素通し、対話確認プロンプトのみ TTY 時に追加）が正本となる。

### レスポンシブ

| 名称 | 幅 | レイアウト変更 |
|------|---|-------------|
| Mobile (<640px) | 対象外（社内運用端末・踏み台サーバ限定のため） |
| Tablet (640-1024px) | サイドバー折りたたみ、ResultTable横スクロール |
| Desktop (>1024px) | サイドバー常時表示、ResultTable全カラム表示 |

## 共通操作パターン

### 二段階中止確認パターン（依頼→対話確認）

blue中止・green中止・速報比較中止・確報比較中止の4フローすべてが「①中止依頼画面 → ②対話確認画面（AbortConfirmDialog）」
という同一の2ステップ構造を持つ。UC仕様側の重複記述を避けるため、共通フローとして以下に集約する。

**共通フロー定義**:

1. **中止依頼画面**（route パターン: `/cli/abort/{target}/request`）
   - 対象の実行結果/依頼状態パネル（RunnerResultPanel または CrossCheckRequestRow）で対象run_id・現在状態を再確認表示
   - Button（destructive variant）で中止依頼を確定（CLI ではコマンド実行に読み替え）
   - 受理/エラーは Banner（info/error variant）で即時フィードバック
   - バリデーション: 対象状態が RUNNING 以外は業務エラーとして拒否
   - **本画面を経由せず対話確認画面へ直接遷移することは許可しない**（対話確認スキップの禁止）
2. **対話確認画面**（route パターン: `/cli/abort/{target}/confirm`）
   - AbortConfirmDialog で対象run_id・影響範囲・取消不可であることを明示し、y/nの二択のみ許可
   - 対話確認結果はプロセス内で一度だけ評価（リトライ・再確認は行わない）
   - n応答・非TTY未同意は状態変更を発生させずに終了コードで区別
   - 遷移完了/エラーは Banner（success/error variant）で表示

**利用UC一覧（4フロー / 8 UC）**:

| フロー | 依頼UC | 対話確認UC |
|---|---|---|
| blue中止 | blue background実行の中止を依頼する（実行制御業務/blue中止フロー） | 対話確認のうえblue background実行をABORTEDへ遷移させる |
| green中止 | green background実行の中止を依頼する（実行制御業務/green中止フロー） | 対話確認のうえgreen background実行をABORTEDへ遷移させる |
| 速報比較中止 | RUNNING中の速報比較依頼の中止を依頼する（実行制御業務/速報比較中止フロー） | 対話確認のうえ速報比較依頼をABORTEDへ遷移させる |
| 確報比較中止 | RUNNING中の確報比較依頼の中止を依頼する（実行制御業務/確報比較中止フロー） | 対話確認のうえ確報比較依頼をABORTEDへ遷移させる |

### 状態一覧+フィルターパターン

CrossCheckRequestRow（速報/確報比較依頼の一覧）や StatusBadge によるフィルタリング可能な状態一覧表示。
CLI では `--status` 等のオプションによる絞り込みに読み替える。

**共通フロー定義**:

- 一覧はテーブル形式（stdout相当）で run_id・状態バッジ（StatusBadge）・lease_expires_at・worker_id を表示
- 状態バッジは REQUESTED(amber)/CLAIMED(violet)/RUNNING(blue)/SUCCEEDED(green)/FAILED(red)/ABORTED(gray) の共通カラートークンに従う
- rapid/final の区別は CrossCheckRequestRow の variant で行い、状態カラートークン自体は共有する
- OK/NG判定・差分件数など詳細情報は ResultTable で Progressive Disclosure（最上部にOK/NG、差分詳細は展開後段）として表示する
- 状態管理はステートレス（CLI実行/CronJob実行のたびにRDBから最新値を都度取得、クライアント側キャッシュ・楽観更新は行わない）

**利用UC一覧（8 UC）**:

- 確報クロスチェック結果を確認する
- 全テーブル・全ファイルを対象に確報クロスチェックを実行する
- blue-green runnerの完了通知を受けて速報比較依頼を作成する
- 速報クロスチェック結果を確認する
- execution-spec.jsonの実行設定を保ったまま再実行する
- 再実行対象のbackground実行・速報比較依頼を選択する
- RUNNING中の確報比較依頼の中止を依頼する
- RUNNING中の速報比較依頼の中止を依頼する

### 実行結果ターミナル表示パターン

RunnerResultPanel による stdout/stderr/exitCode のターミナル調表示。全パターン中もっとも利用頻度が高い（11 UC）。

**共通フロー定義**:

- 背景 slate-900 / 文字色 slate-100 / フォント JetBrains Mono 系（terminal-panel トークン）で原文性を保ったまま表示
- **foreground variant**: stdout/stderr/exitCodeのみをレンダリングし、比較結果・差分件数・レポートURIなどの詳細は一切表示しない（運用性NFR「応答はstdout/stderr/exitcodeのみに限定」に対応）
- **background variant**: 起動直後・実行中・完了時の run_id/slot/role/started_at/状態を含めて表示
- 状態管理はキャッシュを持たず、呼び出しごとにRDB・ファイルシステムから最新の実行結果を取得する
- ローディングは概念上該当なし（CLI応答は10秒以内、CTP-009準拠）。将来ダッシュボードのみスケルトン表示を追加

**利用UC一覧（11 UC）**:

- 確報クロスチェック結果をstdout-stderr-exitcodeで応答する
- 全テーブル・全ファイルを対象に確報クロスチェックを実行する
- 速報クロスチェックを実行し差分を検知する
- background実行の未完了・非0終了・速報比較異常を定期検知する
- execution-spec.jsonの実行設定を保ったまま再実行する
- 再実行対象のbackground実行・速報比較依頼を選択する
- blue background実行の中止を依頼する
- green background実行の中止を依頼する
- background roleを起動する
- foreground roleの標準出力・標準エラー・終了コードを応答する
- 並行稼働実行結果を確認する

## 共通状態表示パターン

`design-event.yaml` の `states` セクション（background slot実行状態／速報比較依頼状態／確報比較依頼状態）に定義された
状態モデルを、以下の共通UI表現に対応付ける。

| 状態区分 | 表現 | 対応コンポーネント | 備考 |
|---|---|---|---|
| 通常状態（RUNNING/SUCCEEDED/FAILED/ABORTED, REQUESTED/CLAIMED） | StatusBadge の色分け表示 | StatusBadge | 色トークンは states セクションと1:1対応（blue/green/red/gray, amber/violet 追加） |
| ローディング | CLIでは概念上該当なし（同期応答・10秒以内） | — | 将来ダッシュボードのみ RunnerResultPanel / ExecutionSpecCard にスケルトン表示を追加 |
| エラー | 標準エラー出力 + 終了コードで表現（stdoutは汚さない） | Banner（error variant） | 将来ダッシュボードでは Banner の error variant に置換。異常検知種別など専用属性が必要な場合は HangDetectionNotice を使う |
| 成功/受理 | 標準出力での即時反映 | Banner（info/success variant） | 依頼作成・中止受理などの即時フィードバックに使用 |
| 空状態（該当データなし） | 終了コード1 + 標準エラーで理由を明示 | — | 将来ダッシュボードでは ResultTable / CrossCheckRequestRow の空状態表示（未定義） |
| 未定義状態の非許容 | 常時いずれかの状態を明示（空白を許容しない） | StatusBadge / RunnerResultPanel | 可用性NFR（24時間無停止運用）に対応した設計制約 |

## 各共通コンポーネントの利用UC一覧

| コンポーネント | 利用UC数 | 利用UC一覧 |
|---|---|---|
| RunnerResultPanel | 11 | 確報クロスチェック結果をstdout-stderr-exitcodeで応答する／全テーブル・全ファイルを対象に確報クロスチェックを実行する／速報クロスチェックを実行し差分を検知する／background実行の未完了・非0終了・速報比較異常を定期検知する／execution-spec.jsonの実行設定を保ったまま再実行する／再実行対象のbackground実行・速報比較依頼を選択する／blue background実行の中止を依頼する／green background実行の中止を依頼する／background roleを起動する／foreground roleの標準出力・標準エラー・終了コードを応答する／並行稼働実行結果を確認する |
| CrossCheckRequestRow | 8 | 確報クロスチェック結果を確認する／全テーブル・全ファイルを対象に確報クロスチェックを実行する／blue-green runnerの完了通知を受けて速報比較依頼を作成する／速報クロスチェック結果を確認する／execution-spec.jsonの実行設定を保ったまま再実行する／再実行対象のbackground実行・速報比較依頼を選択する／RUNNING中の確報比較依頼の中止を依頼する／RUNNING中の速報比較依頼の中止を依頼する |
| Banner | 6 | blue-green runnerの完了通知を受けて速報比較依頼を作成する／RUNNING中の確報比較依頼の中止を依頼する／対話確認のうえ確報比較依頼をABORTEDへ遷移させる／RUNNING中の速報比較依頼の中止を依頼する／対話確認のうえ速報比較依頼をABORTEDへ遷移させる／feature flag設定に基づきslotを選択して起動する |
| StatusBadge | 5 | 確報クロスチェック結果を確認する／速報クロスチェックを実行し差分を検知する／速報クロスチェック結果を確認する／再実行対象のbackground実行・速報比較依頼を選択する／並行稼働実行結果を確認する |
| Button | 4 | blue background実行の中止を依頼する／green background実行の中止を依頼する／RUNNING中の確報比較依頼の中止を依頼する／RUNNING中の速報比較依頼の中止を依頼する |
| AbortConfirmDialog | 4 | 対話確認のうえblue background実行をABORTEDへ遷移させる／対話確認のうえgreen background実行をABORTEDへ遷移させる／対話確認のうえ確報比較依頼をABORTEDへ遷移させる／対話確認のうえ速報比較依頼をABORTEDへ遷移させる |
| ExecutionSpecCard | 3 | execution-spec.jsonの実行設定を保ったまま再実行する／background roleを起動する／feature flag設定に基づきslotを選択して起動する |
| HangDetectionNotice | 3 | background実行の未完了・非0終了・速報比較異常を定期検知する／ハング疑い・異常の通知を確認する／ハング疑い・異常を運用者へ通知する |
| ResultTable | 1 | 速報クロスチェック結果を確認する |
