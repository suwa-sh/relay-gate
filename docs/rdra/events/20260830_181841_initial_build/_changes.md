# 変更サマリ

- event_id: 20260830_181841_initial_build
- 元USDM: docs/usdm/events/20260830_181841_initial_build/requirements.yaml
- 生成日時: 2026-08-30T18:18:41

## 追加

- 全モデル要素を初期構築として追加
  - アクター: 運用者、基盤適用設計者
  - 外部システム: ジョブスケジューラ、現行実装(blue)、新実装(green)、比較ツール、メール通知、管理 DB(RDB)、リモート実行ホスト(SSH)
  - 業務 / BUC: 実装切替ジョブ実行フロー、速報クロスチェックフロー、確報クロスチェックフロー、background 実行監視フロー、実行中止フロー、background 側リランフロー、適用構成定義フロー
  - 情報: feature flag 設定、ジョブマップ、比較定義、実行設定(execution-spec)、Runner Result、並行稼働実行(parallel_run)、slot 実行、速報実行(rapid_run)、速報比較依頼(rapid_crosscheck_request)、比較結果(comparison_result)、確報比較依頼(final_crosscheck_request)、対象カタログ、監視記録 ほか
  - 状態モデル: クロスチェック依頼、slot 実行、並行稼働実行、速報実行の完了状況、監視状態
  - 条件 / バリエーション: slot 実行モード、運用モード、速報クロスチェックモード、ハング検知判定、リラン事前検証、停止確認応答 ほか

## 変更

- なし

## 削除

- なし
