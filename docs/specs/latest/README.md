# Spec 一覧

## UC 仕様

| 業務 | BUC | UC名 | API数 | 非同期 | 最終更新イベント |
|------|-----|------|:-----:|:-----:|----------------|
| クロスチェック業務 | 確報クロスチェックフロー | [確報クロスチェック結果を確認する](クロスチェック業務/確報クロスチェックフロー/確報クロスチェック結果を確認する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| クロスチェック業務 | 確報クロスチェックフロー | [確報比較依頼を claim する](クロスチェック業務/確報クロスチェックフロー/確報比較依頼を claim する/spec.md) | 0 | 有 | 20260830_202851_spec_generation |
| クロスチェック業務 | 確報クロスチェックフロー | [確報比較依頼を登録して終端状態まで待機する](クロスチェック業務/確報クロスチェックフロー/確報比較依頼を登録して終端状態まで待機する/spec.md) | 0 | 有 | 20260830_202851_spec_generation |
| クロスチェック業務 | 確報クロスチェックフロー | [比較ツールで日次全量比較を実行して結果を保存する](クロスチェック業務/確報クロスチェックフロー/比較ツールで日次全量比較を実行して結果を保存する/spec.md) | 0 | 有 | 20260830_202851_spec_generation |
| クロスチェック業務 | 確報クロスチェックフロー | [保存済みの確報結果をジョブスケジューラへ返す](クロスチェック業務/確報クロスチェックフロー/保存済みの確報結果をジョブスケジューラへ返す/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| クロスチェック業務 | 速報クロスチェックフロー | [速報クロスチェック runner へ完了通知を送信する](クロスチェック業務/速報クロスチェックフロー/速報クロスチェック runner へ完了通知を送信する/spec.md) | 0 | 有 | 20260830_202851_spec_generation |
| クロスチェック業務 | 速報クロスチェックフロー | [速報比較依頼を claim する](クロスチェック業務/速報クロスチェックフロー/速報比較依頼を claim する/spec.md) | 0 | 有 | 20260830_202851_spec_generation |
| クロスチェック業務 | 速報クロスチェックフロー | [速報比較結果を参照する](クロスチェック業務/速報クロスチェックフロー/速報比較結果を参照する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| クロスチェック業務 | 速報クロスチェックフロー | [比較ツールでジョブ単位比較を実行して結果を登録する](クロスチェック業務/速報クロスチェックフロー/比較ツールでジョブ単位比較を実行して結果を登録する/spec.md) | 0 | 有 | 20260830_202851_spec_generation |
| クロスチェック業務 | 速報クロスチェックフロー | [両系成功時に速報比較依頼を作成する](クロスチェック業務/速報クロスチェックフロー/両系成功時に速報比較依頼を作成する/spec.md) | 0 | 有 | 20260830_202851_spec_generation |
| 実行監視業務 | background 実行監視フロー | [background 異常の通知メールを受け取る](実行監視業務/background 実行監視フロー/background 異常の通知メールを受け取る/spec.md) | 0 | 有 | 20260830_202851_spec_generation |
| 実行監視業務 | background 実行監視フロー | [background 実行の経過時間と終了状態を判定する](実行監視業務/background 実行監視フロー/background 実行の経過時間と終了状態を判定する/spec.md) | 0 | 有 | 20260830_202851_spec_generation |
| 実行監視業務 | background 実行監視フロー | [hang_detect_limit_minutes をジョブごとに調整する](実行監視業務/background 実行監視フロー/hang_detect_limit_minutes をジョブごとに調整する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| 実行監視業務 | background 実行監視フロー | [ハング疑い・実行エラー・比較異常を通知する](実行監視業務/background 実行監視フロー/ハング疑い・実行エラー・比較異常を通知する/spec.md) | 0 | 有 | 20260830_202851_spec_generation |
| 実行監視業務 | background 実行監視フロー | [監視記録を保存する](実行監視業務/background 実行監視フロー/監視記録を保存する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| 実行復旧業務 | background 側リランフロー | [リラン結果を parent_run_id で追跡する](実行復旧業務/background 側リランフロー/リラン結果を parent_run_id で追跡する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| 実行復旧業務 | background 側リランフロー | [リラン対象を検証する](実行復旧業務/background 側リランフロー/リラン対象を検証する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| 実行復旧業務 | background 側リランフロー | [元の execution-spec.json から復元して新しい run_id で起動する](実行復旧業務/background 側リランフロー/元の execution-spec.json から復元して新しい run_id で起動する/spec.md) | 0 | 有 | 20260830_202851_spec_generation |
| 実行復旧業務 | background 側リランフロー | [速報比較依頼だけを新規作成する](実行復旧業務/background 側リランフロー/速報比較依頼だけを新規作成する/spec.md) | 0 | 有 | 20260830_202851_spec_generation |
| 実行復旧業務 | 実行中止フロー | [現在状態を確認して停止確認に応答する](実行復旧業務/実行中止フロー/現在状態を確認して停止確認に応答する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| 実行復旧業務 | 実行中止フロー | [実行を ABORTED へ遷移させる](実行復旧業務/実行中止フロー/実行を ABORTED へ遷移させる/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| 実装切替業務 | 実装切替ジョブ実行フロー | [execution-spec.json を確定保存する](実装切替業務/実装切替ジョブ実行フロー/execution-spec.json を確定保存する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| 実装切替業務 | 実装切替ジョブ実行フロー | [foreground slot の結果をジョブスケジューラへ中継する](実装切替業務/実装切替ジョブ実行フロー/foreground slot の結果をジョブスケジューラへ中継する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| 実装切替業務 | 実装切替ジョブ実行フロー | [slot 実行モードを選択して runner を起動する](実装切替業務/実装切替ジョブ実行フロー/slot 実行モードを選択して runner を起動する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| 実装切替業務 | 実装切替ジョブ実行フロー | [ジョブマップで JOB_ID から実行先を解決する](実装切替業務/実装切替ジョブ実行フロー/ジョブマップで JOB_ID から実行先を解決する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| 実装切替業務 | 実装切替ジョブ実行フロー | [業務ジョブの実行結果を確認する](実装切替業務/実装切替ジョブ実行フロー/業務ジョブの実行結果を確認する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| 実装切替業務 | 実装切替ジョブ実行フロー | [実装スクリプトを実行して Runner Result を出力する](実装切替業務/実装切替ジョブ実行フロー/実装スクリプトを実行して Runner Result を出力する/spec.md) | 0 | 有 | 20260830_202851_spec_generation |
| 適用構成業務 | 適用構成定義フロー | [feature flag を設定する](適用構成業務/適用構成定義フロー/feature flag を設定する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| 適用構成業務 | 適用構成定義フロー | [slot runner の実体スクリプトを割り当てる](適用構成業務/適用構成定義フロー/slot runner の実体スクリプトを割り当てる/spec.md) | 0 | 有 | 20260830_202851_spec_generation |
| 適用構成業務 | 適用構成定義フロー | [slot ごとのジョブマップを定義する](適用構成業務/適用構成定義フロー/slot ごとのジョブマップを定義する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| 適用構成業務 | 適用構成定義フロー | [クロスチェックのジョブマップと比較定義を定義する](適用構成業務/適用構成定義フロー/クロスチェックのジョブマップと比較定義を定義する/spec.md) | 0 | 無 | 20260830_202851_spec_generation |
| 適用構成業務 | 適用構成定義フロー | [切り替えた運用モードで業務ジョブを実行する](適用構成業務/適用構成定義フロー/切り替えた運用モードで業務ジョブを実行する/spec.md) | 0 | 有 | 20260830_202851_spec_generation |

## 全体横断仕様

- [UX デザイン仕様](_cross-cutting/ux-ui/ux-design.md)
- [UI デザイン仕様(出力規約)](_cross-cutting/ux-ui/ui-design.md)
- [データ可視化仕様](_cross-cutting/ux-ui/data-visualization.md)
- [CLI コマンド契約(正本)](_cross-cutting/api/cli-command-contract.yaml)
- [OpenAPI(バリデータ互換スタブ。HTTP API 無し)](_cross-cutting/api/openapi.yaml)
- [AsyncAPI](_cross-cutting/api/asyncapi.yaml)
- [RDB スキーマ](_cross-cutting/datastore/rdb-schema.yaml)
- [データストアスキーマ(統合 Markdown)](_cross-cutting/datastore/datastore-schema.md)
- [トレーサビリティ](_cross-cutting/traceability-matrix.md)
- [UC 依存関係](_cross-cutting/uc-dependencies.md)
- [USDM 受け入れ基準マトリクス](_cross-cutting/usdm-acceptance-matrix.md)
- [RDRA フィードバック](_cross-cutting/rdra-feedback.md)

## メタデータ

- Event ID: 20260830_202851_spec_generation
- 生成日時: 2026-08-30T20:28:51
- UC 総数: 32
- API 総数: 0(HTTP API 無し。CLI コマンド契約 24 コマンドが正本)
