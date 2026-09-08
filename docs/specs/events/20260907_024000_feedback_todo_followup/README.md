# Spec 一覧

> 最新イベント: `20260907_024000_feedback_todo_followup`(design 無しモード。UI 画面なし)。UC 32 件 / BUC 7 件。

## UC 仕様

| 業務 | BUC | UC名 | API数 | 非同期 | 最終更新イベント |
|------|-----|------|:-----:|:-----:|----------------|
| クロスチェック業務 | 確報クロスチェックフロー | [確報クロスチェック結果を確認する](クロスチェック業務/確報クロスチェックフロー/確報クロスチェック結果を確認する/spec.md) | 0 | 無 | 20260907_024000_feedback_todo_followup |
| クロスチェック業務 | 確報クロスチェックフロー | [確報比較依頼を claim する](クロスチェック業務/確報クロスチェックフロー/確報比較依頼を claim する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| クロスチェック業務 | 確報クロスチェックフロー | [確報比較依頼を登録して終端状態まで待機する](クロスチェック業務/確報クロスチェックフロー/確報比較依頼を登録して終端状態まで待機する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| クロスチェック業務 | 確報クロスチェックフロー | [比較ツールで日次全量比較を実行して結果を保存する](クロスチェック業務/確報クロスチェックフロー/比較ツールで日次全量比較を実行して結果を保存する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| クロスチェック業務 | 確報クロスチェックフロー | [保存済みの確報結果をジョブスケジューラへ返す](クロスチェック業務/確報クロスチェックフロー/保存済みの確報結果をジョブスケジューラへ返す/spec.md) | 0 | 無 | 20260907_024000_feedback_todo_followup |
| クロスチェック業務 | 速報クロスチェックフロー | [速報クロスチェック runner へ完了通知を送信する](クロスチェック業務/速報クロスチェックフロー/速報クロスチェック runner へ完了通知を送信する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| クロスチェック業務 | 速報クロスチェックフロー | [速報比較依頼を claim する](クロスチェック業務/速報クロスチェックフロー/速報比較依頼を claim する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| クロスチェック業務 | 速報クロスチェックフロー | [速報比較結果を参照する](クロスチェック業務/速報クロスチェックフロー/速報比較結果を参照する/spec.md) | 0 | 無 | 20260907_024000_feedback_todo_followup |
| クロスチェック業務 | 速報クロスチェックフロー | [比較ツールでジョブ単位比較を実行して結果を登録する](クロスチェック業務/速報クロスチェックフロー/比較ツールでジョブ単位比較を実行して結果を登録する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| クロスチェック業務 | 速報クロスチェックフロー | [両系成功時に速報比較依頼を作成する](クロスチェック業務/速報クロスチェックフロー/両系成功時に速報比較依頼を作成する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| 実行監視業務 | background 実行監視フロー | [background 異常の通知メールを受け取る](実行監視業務/background 実行監視フロー/background 異常の通知メールを受け取る/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| 実行監視業務 | background 実行監視フロー | [background 実行の経過時間と終了状態を判定する](実行監視業務/background 実行監視フロー/background 実行の経過時間と終了状態を判定する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| 実行監視業務 | background 実行監視フロー | [hang_detect_limit_minutes をジョブごとに調整する](実行監視業務/background 実行監視フロー/hang_detect_limit_minutes をジョブごとに調整する/spec.md) | 0 | 無 | 20260907_024000_feedback_todo_followup |
| 実行監視業務 | background 実行監視フロー | [ハング疑い・実行エラー・比較異常を通知する](実行監視業務/background 実行監視フロー/ハング疑い・実行エラー・比較異常を通知する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| 実行監視業務 | background 実行監視フロー | [監視記録を保存する](実行監視業務/background 実行監視フロー/監視記録を保存する/spec.md) | 0 | 無 | 20260907_024000_feedback_todo_followup |
| 実行復旧業務 | background 側リランフロー | [リラン結果を parent_run_id で追跡する](実行復旧業務/background 側リランフロー/リラン結果を parent_run_id で追跡する/spec.md) | 0 | 無 | 20260907_024000_feedback_todo_followup |
| 実行復旧業務 | background 側リランフロー | [リラン対象を検証する](実行復旧業務/background 側リランフロー/リラン対象を検証する/spec.md) | 0 | 無 | 20260907_024000_feedback_todo_followup |
| 実行復旧業務 | background 側リランフロー | [元の execution-spec.json から復元して新しい run_id で起動する](実行復旧業務/background 側リランフロー/元の execution-spec.json から復元して新しい run_id で起動する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| 実行復旧業務 | background 側リランフロー | [速報比較依頼だけを新規作成する](実行復旧業務/background 側リランフロー/速報比較依頼だけを新規作成する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| 実行復旧業務 | 実行中止フロー | [現在状態を確認して停止確認に応答する](実行復旧業務/実行中止フロー/現在状態を確認して停止確認に応答する/spec.md) | 0 | 無 | 20260907_024000_feedback_todo_followup |
| 実行復旧業務 | 実行中止フロー | [実行を ABORTED へ遷移させる](実行復旧業務/実行中止フロー/実行を ABORTED へ遷移させる/spec.md) | 0 | 無 | 20260907_024000_feedback_todo_followup |
| 実装切替業務 | 実装切替ジョブ実行フロー | [execution-spec.json を確定保存する](実装切替業務/実装切替ジョブ実行フロー/execution-spec.json を確定保存する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| 実装切替業務 | 実装切替ジョブ実行フロー | [foreground slot の結果をジョブスケジューラへ中継する](実装切替業務/実装切替ジョブ実行フロー/foreground slot の結果をジョブスケジューラへ中継する/spec.md) | 0 | 無 | 20260907_024000_feedback_todo_followup |
| 実装切替業務 | 実装切替ジョブ実行フロー | [slot 実行モードを選択して runner を起動する](実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/spec.md) | 0 | 無 | 20260907_024000_feedback_todo_followup |
| 実装切替業務 | 実装切替ジョブ実行フロー | [ジョブマップで JOB_ID から実行先を解決する](実装切替業務/実装切替ジョブ実行フロー/ジョブマップで JOB_ID から実行先を解決する/spec.md) | 0 | 無 | 20260907_024000_feedback_todo_followup |
| 実装切替業務 | 実装切替ジョブ実行フロー | [業務ジョブの実行結果を確認する](実装切替業務/実装切替ジョブ実行フロー/業務ジョブの実行結果を確認する/spec.md) | 0 | 無 | 20260907_024000_feedback_todo_followup |
| 実装切替業務 | 実装切替ジョブ実行フロー | [実装スクリプトを実行して Runner Result を出力する](実装切替業務/実装切替ジョブ実行フロー/実装スクリプトを実行して Runner Result を出力する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| 適用構成業務 | 適用構成定義フロー | [feature flag を設定する](適用構成業務/適用構成定義フロー/feature flag を設定する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| 適用構成業務 | 適用構成定義フロー | [slot runner の実体スクリプトを割り当てる](適用構成業務/適用構成定義フロー/slot runner の実体スクリプトを割り当てる/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| 適用構成業務 | 適用構成定義フロー | [slot ごとのジョブマップを定義する](適用構成業務/適用構成定義フロー/slot ごとのジョブマップを定義する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |
| 適用構成業務 | 適用構成定義フロー | [クロスチェックのジョブマップと比較定義を定義する](適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md) | 0 | 無 | 20260907_024000_feedback_todo_followup |
| 適用構成業務 | 適用構成定義フロー | [切り替えた運用モードで業務ジョブを実行する](適用構成業務/適用構成定義フロー/切り替えた運用モードで業務ジョブを実行する/spec.md) | 0 | 有 | 20260907_024000_feedback_todo_followup |

## BUC 仕様

| 業務 | BUC | buc-spec |
|------|-----|----------|
| クロスチェック業務 | 確報クロスチェックフロー | [buc-spec.md](クロスチェック業務/確報クロスチェックフロー/buc-spec.md) |
| クロスチェック業務 | 速報クロスチェックフロー | [buc-spec.md](クロスチェック業務/速報クロスチェックフロー/buc-spec.md) |
| 実行監視業務 | background 実行監視フロー | [buc-spec.md](実行監視業務/background 実行監視フロー/buc-spec.md) |
| 実行復旧業務 | background 側リランフロー | [buc-spec.md](実行復旧業務/background 側リランフロー/buc-spec.md) |
| 実行復旧業務 | 実行中止フロー | [buc-spec.md](実行復旧業務/実行中止フロー/buc-spec.md) |
| 実装切替業務 | 実装切替ジョブ実行フロー | [buc-spec.md](実装切替業務/実装切替ジョブ実行フロー/buc-spec.md) |
| 適用構成業務 | 適用構成定義フロー | [buc-spec.md](適用構成業務/適用構成定義フロー/buc-spec.md) |

## 全体横断仕様

| 区分 | ファイル | 内容 |
|------|---------|------|
| API(CLI 契約) | [cli-command-contract.yaml](_cross-cutting/api/cli-command-contract.yaml) | CLI コマンド契約の正本(コマンド・設定ファイル・成果物レイアウト・環境変数・shared_rules)。HTTP API は無い |
| API(非同期) | [asyncapi.yaml](_cross-cutting/api/asyncapi.yaml) | RDB ジョブキュー・完了通知・通知メールの AsyncAPI |
| API(スタブ) | [openapi.yaml](_cross-cutting/api/openapi.yaml) | バリデータ互換スタブ(HTTP API なし) |
| データストア | [rdb-schema.yaml](_cross-cutting/datastore/rdb-schema.yaml) / [datastore-schema.md](_cross-cutting/datastore/datastore-schema.md) | ジョブキュー兼管理 DB(内部データストア)のテーブル定義 |
| UX / 出力規約 | [ux-design.md](_cross-cutting/ux-ui/ux-design.md) / [ui-design.md](_cross-cutting/ux-ui/ui-design.md) / [data-visualization.md](_cross-cutting/ux-ui/data-visualization.md) | 操作フロー・CLI 出力規約(stdout / stderr / 終了コード / 通知メール)・表形式出力 |
| トレーサビリティ | [traceability-matrix.md](_cross-cutting/traceability-matrix.md) | RDRA 要素 × UC の網羅率 |
| USDM 対応 | [usdm-acceptance-matrix.md](_cross-cutting/usdm-acceptance-matrix.md) | USDM 受け入れ条件 × UC BDD の対応表 |
| UC 間依存 | [uc-dependencies.md](_cross-cutting/uc-dependencies.md) | コマンド・テーブル・ファイル契約による UC 間依存 |
| RDRA フィードバック | [rdra-feedback.md](_cross-cutting/rdra-feedback.md) | RDRA / 方針資料への変更要望(残存分)と解消済み一覧 |

## メタデータ

- [spec-event.yaml](spec-event.yaml) / [spec-event.md](spec-event.md): イベントメタデータ(UC 一覧・横断仕様サマリー・レビュー履歴)
- [_inference.md](_inference.md): 分析根拠(UC ツリー・UC-ティアマッピング・確認推奨項目)
- [_inputs-digest.md](_inputs-digest.md): arch / nfr の入力ダイジェスト
- [decisions/](decisions/): 設計判断記録(spec-decision-001〜005)
- [source.txt](source.txt): トリガー・入力の正本
