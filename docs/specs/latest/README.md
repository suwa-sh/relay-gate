# Spec 一覧

## UC 仕様

| 業務 | BUC | UC名 | API数 | 非同期 | 最終更新イベント |
|------|-----|------|:-----:|:-----:|----------------|
| クロスチェック業務 | 確報クロスチェックフロー | [全テーブル・全ファイルを対象に確報クロスチェックを実行する](クロスチェック業務/確報クロスチェックフロー/全テーブル・全ファイルを対象に確報クロスチェックを実行する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| クロスチェック業務 | 確報クロスチェックフロー | [確報クロスチェック結果をstdout/stderr/exitcodeで応答する](クロスチェック業務/確報クロスチェックフロー/確報クロスチェック結果をstdout/stderr/exitcodeで応答する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| クロスチェック業務 | 確報クロスチェックフロー | [確報クロスチェック結果を確認する](クロスチェック業務/確報クロスチェックフロー/確報クロスチェック結果を確認する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| クロスチェック業務 | 速報クロスチェックフロー | [blue/green runnerの完了通知を受けて速報比較依頼を作成する](クロスチェック業務/速報クロスチェックフロー/blue/green runnerの完了通知を受けて速報比較依頼を作成する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| クロスチェック業務 | 速報クロスチェックフロー | [速報クロスチェックを実行し差分を検知する](クロスチェック業務/速報クロスチェックフロー/速報クロスチェックを実行し差分を検知する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| クロスチェック業務 | 速報クロスチェックフロー | [速報クロスチェック結果を確認する](クロスチェック業務/速報クロスチェックフロー/速報クロスチェック結果を確認する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 並行稼働実行業務 | 並行稼働実行フロー | [background roleを起動する](並行稼働実行業務/並行稼働実行フロー/background roleを起動する/spec.md) | 2 | 無 | 20260817_155817_spec_generation |
| 並行稼働実行業務 | 並行稼働実行フロー | [feature flag設定に基づきslotを選択して起動する](並行稼働実行業務/並行稼働実行フロー/feature flag設定に基づきslotを選択して起動する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 並行稼働実行業務 | 並行稼働実行フロー | [foreground roleの標準出力・標準エラー・終了コードを応答する](並行稼働実行業務/並行稼働実行フロー/foreground roleの標準出力・標準エラー・終了コードを応答する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 並行稼働実行業務 | 並行稼働実行フロー | [並行稼働実行結果を確認する](並行稼働実行業務/並行稼働実行フロー/並行稼働実行結果を確認する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 実行制御業務 | background側リランフロー | [execution-spec.jsonの実行設定を保ったまま再実行する](実行制御業務/background側リランフロー/execution-spec.jsonの実行設定を保ったまま再実行する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 実行制御業務 | background側リランフロー | [再実行対象のbackground実行・速報比較依頼を選択する](実行制御業務/background側リランフロー/再実行対象のbackground実行・速報比較依頼を選択する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 実行制御業務 | blue中止フロー | [blue background実行の中止を依頼する](実行制御業務/blue中止フロー/blue background実行の中止を依頼する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 実行制御業務 | blue中止フロー | [対話確認のうえblue background実行をABORTEDへ遷移させる](実行制御業務/blue中止フロー/対話確認のうえblue background実行をABORTEDへ遷移させる/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 実行制御業務 | green中止フロー | [green background実行の中止を依頼する](実行制御業務/green中止フロー/green background実行の中止を依頼する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 実行制御業務 | green中止フロー | [対話確認のうえgreen background実行をABORTEDへ遷移させる](実行制御業務/green中止フロー/対話確認のうえgreen background実行をABORTEDへ遷移させる/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 実行制御業務 | 確報比較中止フロー | [RUNNING中の確報比較依頼の中止を依頼する](実行制御業務/確報比較中止フロー/RUNNING中の確報比較依頼の中止を依頼する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 実行制御業務 | 確報比較中止フロー | [対話確認のうえ確報比較依頼をABORTEDへ遷移させる](実行制御業務/確報比較中止フロー/対話確認のうえ確報比較依頼をABORTEDへ遷移させる/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 実行制御業務 | 速報比較中止フロー | [RUNNING中の速報比較依頼の中止を依頼する](実行制御業務/速報比較中止フロー/RUNNING中の速報比較依頼の中止を依頼する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 実行制御業務 | 速報比較中止フロー | [対話確認のうえ速報比較依頼をABORTEDへ遷移させる](実行制御業務/速報比較中止フロー/対話確認のうえ速報比較依頼をABORTEDへ遷移させる/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 実行監視業務 | ハング監視フロー | [background実行の未完了・非0終了・速報比較異常を定期検知する](実行監視業務/ハング監視フロー/background実行の未完了・非0終了・速報比較異常を定期検知する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 実行監視業務 | ハング監視フロー | [ハング疑い・異常の通知を確認する](実行監視業務/ハング監視フロー/ハング疑い・異常の通知を確認する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |
| 実行監視業務 | ハング監視フロー | [ハング疑い・異常を運用者へ通知する](実行監視業務/ハング監視フロー/ハング疑い・異常を運用者へ通知する/spec.md) | 1 | 無 | 20260817_155817_spec_generation |

## 全体横断仕様

- [UX デザイン仕様](_cross-cutting/ux-ui/ux-design.md)
- [UI デザイン仕様](_cross-cutting/ux-ui/ui-design.md)
- [データ可視化仕様](_cross-cutting/ux-ui/data-visualization.md)
- [共通コンポーネント設計](_cross-cutting/ux-ui/common-components.md)
- [CLI コマンド契約](_cross-cutting/api/cli-command-contract.yaml)（HTTP APIは存在しないため、こちらが正本。`_cross-cutting/api/openapi.yaml` は構造バリデータ互換のためのスタブ）
- [RDB スキーマ](_cross-cutting/datastore/rdb-schema.yaml)
- [データストア統合Markdown](_cross-cutting/datastore/datastore-schema.md)
- [トレーサビリティマトリクス](_cross-cutting/traceability-matrix.md)
- [設計判断記録（Decision Records）](decisions/)

## メタデータ

- Event ID: 20260817_155817_spec_generation
- 生成日時: 2026-08-17T15:58:17+09:00
- UC 総数: 23
- API（CLIコマンド）総数: 24
- 業務数: 4
- BUC数: 9
- トレーサビリティ網羅率: 100%（rdra-feedback.md 生成なし）
